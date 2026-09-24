#!/usr/bin/env python3
"""Turns the two Iris runs (see METHOD.md) into every number RESULTS.md cites.

Usage: python3 triage.py <batch.json> <triage_stderr.txt> <outdir>

<batch.json>          `--format json` output of the unmodified CLI (run 1).
<triage_stderr.txt>   stderr of the probe-patched CLI (run 2): one TRIAGE line
                      per (ambiguous use site, alternative) pair.
<outdir>              where output.json (trimmed batch JSON) and sites.tsv go.

Classification of each alternative, from the probe (import_probe.patch):
  shadowed  every uniquely named sibling in its module resolves by bare name,
            so the module is imported: the alternative was import-visible
            and lost to the winner (real "last import wins").
  latent    no such sibling resolves: the module is loaded, not imported.
  filtered  some do, some don't: a filtered import like
            `Export String (string(..))`. Resolved here by ratio (>= 90%
            resolving counts as imported: in Iris that's a lone #[local]
            sibling; the one low-ratio case, Stdlib String at 5/28, was
            checked by hand against stdpp/strings.v and is latent).
  unknown   no uniquely named sibling to test. Every module this happens
            for in Iris (all printed by this script) was checked by grep to
            be never Import-ed/Export-ed anywhere in Iris or stdpp, so these
            count as latent.
  local     the alternative is itself declared Local: never reachable by
            its bare name, whether or not its module is imported, so it can
            neither be shadowed nor flip anything later (overrides the
            above).
A use site is "shadowed" if any non-excluded alternative is; otherwise
"latent" if any is; otherwise "local-only".
"""
import collections
import json
import sys

PREFIX_MARK = "/user-contrib/"
EXCLUDED = ("Corelib.",)  # the CLI's default exclusion, mirrored here


def rel(path):
    return path.split(PREFIX_MARK, 1)[1] if PREFIX_MARK in path else path


def excluded(name):
    return name.startswith(EXCLUDED)


def load_triage(path):
    pairs = collections.defaultdict(set)
    unknown_modules = set()
    for line in open(path):
        if not line.startswith("TRIAGE\t"):
            continue
        _, f, ln, written, winner, alt, status, sib, local = line.rstrip("\n").split("\t")
        if local == "local":
            status = "local"
        elif status == "filtered":
            yes, n = map(int, sib.split("/"))
            status = "shadowed" if yes / n >= 0.9 else "latent"
        elif status == "unknown":
            if not excluded(alt):
                unknown_modules.add(alt.rsplit(".", 1)[0])
            status = "latent"
        pairs[(rel(f), int(ln), written)].add((winner, alt, status))
    return pairs, unknown_modules


def classify(pairs):
    sites = {}
    for key, v in pairs.items():
        winner = next(iter(v))[0]
        alts = sorted({(a, s) for _, a, s in v if not excluded(a)})
        if len({a for a, _ in alts}) + (0 if excluded(winner) else 1) < 2:
            continue
        statuses = {s for _, s in alts}
        kind = next(k for k in ("shadowed", "latent", "local") if k in statuses)
        kind = "local-only" if kind == "local" else kind
        sites[key] = (kind, winner, alts)
    return sites


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


def main(batch_path, triage_path, outdir):
    batch = json.load(open(batch_path))
    pairs, unknown_modules = load_triage(triage_path)
    sites = classify(pairs)

    # Cross-check: exactly the use sites the unmodified CLI reported.
    reported = set()
    for f in batch["files"]:
        for a in f["report"]["ambiguous_uses"]:
            for ln in a["lines"]:
                reported.add((rel(f["file"]), ln, a["name"]))
    assert reported == set(sites), (len(reported), len(sites))

    files = batch["files"]
    print(f"files analyzed: {len(files)}, failed: {batch['failed']}")
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
    main(*sys.argv[1:4])
