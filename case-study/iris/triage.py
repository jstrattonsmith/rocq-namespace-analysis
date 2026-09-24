#!/usr/bin/env python3
"""Turns the Iris run (see METHOD.md) into every number RESULTS.md cites.

Usage: python3 triage.py <batch.json> <outdir>

<batch.json>   `--format json` output of the CLI over all of Iris.
<outdir>       where output.json (trimmed batch JSON) and sites.tsv go.

Each ambiguous use's alternatives carry the tool's own import-status label
(Workstream 11; originally prototyped as a throwaway probe for this case
study, and confirmed to agree with it on all 5,841 (site, alternative)
pairs):
  shadowed      every uniquely named sibling in its module resolves by bare
                name, so the module is imported: the alternative was
                import-visible and lost to the winner (real "last import
                wins").
  not_imported  no such sibling resolves: the module is loaded, not imported.
  partial       some do, some don't: a filtered import like
                `Export String (string(..))`.
  unknown       no uniquely named sibling to test.
  local         the alternative is itself Local: never reachable by its bare
                name.

The tool reports partial and unknown as such. For Iris only, this script
then resolves them by two judgment calls, each checked against the source:
  partial   >= 90% resolving counts as imported: in Iris that's a lone
            #[local] sibling; the one low-ratio case, Stdlib String at
            5/28, was checked by hand against stdpp/strings.v and is latent.
  unknown   every module this happens for in Iris (all printed below) was
            checked by grep to be never Import-ed/Export-ed anywhere in Iris
            or stdpp, so these count as latent.
A use site is "shadowed" if any alternative is; otherwise "latent" if any
is; otherwise "local-only".
"""
import collections
import json
import sys

PREFIX_MARK = "/user-contrib/"


def rel(path):
    return path.split(PREFIX_MARK, 1)[1] if PREFIX_MARK in path else path


def judged(alt, unknown_modules):
    status = alt["status"]
    if status == "partial":
        return "shadowed" if alt["resolving"] / alt["tested"] >= 0.9 else "latent"
    if status == "unknown":
        unknown_modules.add(alt["name"].rsplit(".", 1)[0])
        return "latent"
    return {"shadowed": "shadowed", "not_imported": "latent", "local": "local"}[status]


def classify(batch):
    sites = {}
    unknown_modules = set()
    for f in batch["files"]:
        for a in f["report"]["ambiguous_uses"]:
            alts = sorted({(x["name"], judged(x, unknown_modules)) for x in a["alternatives"]})
            statuses = {s for _, s in alts}
            kind = next(k for k in ("shadowed", "latent", "local") if k in statuses)
            kind = "local-only" if kind == "local" else kind
            winner = a["winner"] if a["winner"] is not None else "(excluded)"
            for ln in a["lines"]:
                sites[(rel(f["file"]), ln, a["name"])] = (kind, winner, alts)
    return sites, unknown_modules


LANG = ("iris.program_logic.language.", "iris.program_logic.ectx_language.",
        "iris.program_logic.ectxi_language.")
HEAP_LIB = ("iris.heap_lang.lib.", "iris.heap_lang.primitive_laws.",
            "iris.base_logic.lib.gen_heap.", "iris.base_logic.lib.gen_inv_heap.")
LOGIC = ("iris.base_logic.", "iris.bi.", "iris.si_logic.")


def bucket(winner, shadowed):
    if all(a.startswith(LANG) for a in shadowed):
        return "language interface shadowed by an instance or refinement"
    if winner.startswith("stdpp.") and all(a.startswith("Stdlib.") for a in shadowed):
        return "stdpp replacing Stdlib"
    if winner.startswith("iris.heap_lang") and all(a.startswith(HEAP_LIB) for a in shadowed):
        return "heap_lang library: implementation over interface"
    if winner.startswith(LOGIC) and all(a.startswith(LOGIC + ("stdpp.", "iris.algebra.")) for a in shadowed):
        return "logic layering (model/BI/restate modules, BI over stdpp)"
    if winner.startswith("iris.algebra.stepindex") and all(a.startswith("iris.algebra.") for a in shadowed):
        return "step-index specialization over the generic OFE/CMRA lemma"
    return "other (listed individually)"


def main(batch_path, outdir):
    batch = json.load(open(batch_path))
    sites, unknown_modules = classify(batch)
    assert len(sites) == batch["ambiguous_sites"], (len(sites), batch["ambiguous_sites"])

    files = batch["files"]
    print(f"files analyzed: {len(files)}, failed: {batch['failed']}")
    print(f"tool's own split (before this script's judgment calls): {batch['by_kind']}")
    print(f"ambiguous use sites: {batch['ambiguous_sites']} "
          f"(grouped rows: {sum(len(f['report']['ambiguous_uses']) for f in files)})")
    per_file = collections.Counter(k[0] for k in sites)
    print(f"files with >= 1 ambiguous use site: {len(per_file)}")
    print(f"distinct names as written: {len({k[2] for k in sites})}")
    print("top files:", per_file.most_common(8))
    kinds = collections.Counter(v[0] for v in sites.values())
    print(f"shadowed: {kinds['shadowed']}  latent: {kinds['latent']}  local-only: {kinds['local-only']}")
    print("unknown-verdict modules (all checked never imported):", len(unknown_modules))
    for m in sorted(unknown_modules):
        print("   ", m)

    buckets = collections.Counter()
    other = collections.Counter()
    for (f, ln, w), (kind, winner, alts) in sites.items():
        if kind != "shadowed":
            continue
        sh = tuple(sorted({a for a, s in alts if s == "shadowed"}))
        b = bucket(winner, sh)
        buckets[b] += 1
        if b.startswith("other"):
            other[(w, winner, sh)] += 1
    print("shadowed sites by pattern:")
    for b, n in buckets.most_common():
        print(f"  {n:5d}  {b}")
    print("other patterns:")
    for (w, winner, sh), n in other.most_common():
        print(f"  {n:4d}  {w}: {winner} over {', '.join(sh)}")

    latent_alts = collections.Counter(
        a.split(".")[0] for kind, _, alts in sites.values() if kind == "latent" for a, _ in alts)
    print("latent sites' alternatives by root library:", latent_alts.most_common())

    with open(f"{outdir}/sites.tsv", "w") as out:
        out.write("file\tline\twritten\tkind\twinner\talternative:status ...\n")
        for (f, ln, w), (kind, winner, alts) in sorted(sites.items()):
            out.write("\t".join([f, str(ln), w, kind, winner] + [f"{a}:{s}" for a, s in alts]) + "\n")
    # Trimmed: the per-file used-identifier and clash lists are ~21 MB
    # together and reproducible from METHOD.md; keep counts and every
    # ambiguous use, one file per line.
    with open(f"{outdir}/output.json", "w") as out:
        out.write('{"failed":%d,"ambiguous_sites":%d,"files":[\n' % (batch["failed"], batch["ambiguous_sites"]))
        entries = []
        for f in files:
            r = f["report"]
            entries.append(json.dumps(
                {"file": rel(f["file"]), "member_count": r["member_count"],
                 "clash_count": len(r["clashes"]), "used_count": len(r["used"]),
                 "ambiguous_uses": r["ambiguous_uses"]}, ensure_ascii=False))
        out.write(",\n".join(entries))
        out.write("\n]}\n")


if __name__ == "__main__":
    main(*sys.argv[1:3])
