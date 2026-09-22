(** A plugin/CLI-agnostic report: built once from live environment state,
    then rendered either for the proof/message panel ([to_pp], via
    [Feedback.msg_notice]) or for a terminal ([to_string]). Both front ends
    must render identical content. *)

type t = {
  member_count : int;
  clashes : Clash_detect.clash list;
  used : Glob_capture.occurrence list;
}

val make :
  member_count:int ->
  clashes:Clash_detect.clash list ->
  used:Glob_capture.occurrence list ->
  t

(** Both [to_pp] and [to_string]'s grid, past {!large_report_threshold}
    distinct clashing names, prepend a one-line note pointing at
    [to_summary]/[to_json] via the CLI's [--format] flag (confirmed: 1,000
    clashes alone render as a 3,007-line table) -- the plugin has no
    [--format] of its own, so the note always points at the CLI regardless
    of which front end is showing it.

    Both also append [" (Local)"] to any candidate declared [Local]
    (outside a section) -- such a candidate is a domain member (still
    fully-qualified-accessible, so [Environ.fold_constants] retains it)
    but Rocq would never actually resolve a bare short name to it, so it's
    labeled rather than shown as an indistinguishable clash risk (see
    [Declare.is_local_constant] in [report.ml]). [to_summary]/[to_json] do
    not include this label, matching the large-report note above in being
    grid-only. *)
val to_pp : t -> Pp.t

(** [color] (default [false]) additionally wraps the winning candidate in
    bold+ANSI color codes; pass [~color:(Unix.isatty Unix.stdout)] from a
    terminal front end. The plain-text winner marker is always present
    regardless. *)
val to_string : ?color:bool -> t -> string

(** Counts only, one line, no per-name grid -- for a whole-corpus batch run
    where the full grid could run to hundreds of rows. "No winner marked"
    covers both a purely hypothetical clash (nothing visible yet) and an
    excluded actual winner ({!Clash_detect.clash.winner}'s [None] case
    doesn't currently distinguish the two -- see its doc comment); this is
    reported as one combined count rather than overclaiming a split we can't
    actually make from the data we have. *)
val to_summary : t -> string

(** A fixed JSON shape (hand-serialized, no external JSON dependency,
    intentionally not a general-purpose encoder): [{"member_count": int,
    "clashes": [{"name", "winner" (string or null), "alternatives": [string]},
    ...], "used": [{"identifier", "defined_in"}, ...]}]. Alternatives are
    sorted alphabetically, same as the grid. *)
val to_json : t -> string
