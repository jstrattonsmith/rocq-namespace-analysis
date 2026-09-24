open Names
open Pp

type t = {
  member_count : int;
  clashes : Clash_detect.clash list;
  ambiguous : Clash_detect.ambiguous_use list;
  used : Glob_capture.occurrence list;
  mutable clash_statuses : Import_status.t DPmap.t;
      (* memo for [clash_status], per module: filled on first render, which
         both front ends do right after [make], at the same analysis point.
         Per module is exact here, see Import_status.of_module. Not per
         GlobRef: GlobRef.Map compares canonical names, and a module that
         Includes another (Stdlib's BinInt.Z / BinIntDef.Z) shares them, so
         two candidates from different modules would collide. *)
}

let make ~member_count ~clashes ~ambiguous ~used =
  { member_count; clashes; ambiguous; used; clash_statuses = DPmap.empty }

let qualified_name gr = Libnames.string_of_path (Nametab.path_of_global gr)

(* `Local` (outside a section) only blocks a definition's short-name
   binding on Import -- it's still fully-qualified-accessible, and still
   shows up as a domain member (Environ.fold_constants retains it), so it
   was previously reported as an indistinguishable clash candidate even
   though Rocq itself would never actually resolve a bare short name to
   it. Declare.is_local_constant answers this directly and correctly,
   without ever consulting Nametab/short-name-visibility state -- it's
   populated at `load_constant` time (fires on Require), not at
   `Import`/`Export` time, so a genuinely Local constant is flagged
   regardless of whether its library is ever Import-ed, while an ordinary
   constant in a Require-only "hypothetical" domain (see Ensure_loaded,
   test/fixtures/Hypothetical.v) is correctly never flagged, Import status
   notwithstanding -- confirmed directly, not assumed (see
   case-study/corelib-stdlib/RESULTS.md and test/fixtures/LocalFalsePositive.v).
   Inductives/constructors don't need an analogous check: `Local` outside
   a section isn't a distinct state Rocq's inductive/constructor machinery
   tracks in the first place (no discharge/locality field on that AST
   node at all). *)
let is_local_member = function
  | GlobRef.ConstRef c -> Declare.is_local_constant c
  | GlobRef.IndRef _ | GlobRef.ConstructRef _ | GlobRef.VarRef _ -> false

let local_marker = " (Local)"

(* Whether a non-winning candidate's module is imported (Import_status): a
   plain-text suffix, like the other markers, so it survives any terminal. *)
let status_marker = function
  | Import_status.Imported -> " (shadowed)"
  | Import_status.Not_imported -> " (not imported)"
  | Import_status.Partial (k, n) -> Printf.sprintf " (partly imported %d/%d)" k n
  | Import_status.Unknown -> " (import status unknown)"

let status_json = function
  | Import_status.Imported -> {|"status":"shadowed"|}
  | Import_status.Not_imported -> {|"status":"not_imported"|}
  | Import_status.Partial (k, n) -> Printf.sprintf {|"status":"partial","resolving":%d,"tested":%d|} k n
  | Import_status.Unknown -> {|"status":"unknown"|}

(* Clash-grid candidates are judged at report time, which is exactly the
   moment that grid describes (the command's position for the plugin, the
   end of the file for the CLI) -- so e.g. a hypothetical domain's
   candidate reads "not imported". *)
let clash_status (r : t) gr =
  if is_local_member gr then None
  else
    match Import_status.module_of_global gr with
    | None -> Some Import_status.Unknown
    | Some dp -> (
      match DPmap.find_opt dp r.clash_statuses with
      | Some st -> Some st
      | None ->
        let st = Import_status.of_module dp in
        r.clash_statuses <- DPmap.add dp st r.clash_statuses;
        Some st)

let clash_row r (c : Clash_detect.clash) =
  let all =
    match c.winner with
    | Some w -> w :: c.alternatives
    | None -> c.alternatives
  in
  let is_winner gr =
    match c.winner with
    | Some w -> GlobRef.UserOrd.equal w gr
    | None -> false
  in
  let entries =
    all
    |> List.map (fun gr -> (qualified_name gr, is_winner gr, is_local_member gr, gr))
    |> List.sort (fun (a, _, _, _) (b, _, _, _) -> String.compare a b)
    |> List.map (fun (text, is_winner, is_local, gr) ->
           let text = if is_local then text ^ local_marker else text in
           let text =
             match (if is_winner then None else clash_status r gr) with
             | Some st -> text ^ status_marker st
             | None -> text
           in
           let text = if is_winner then text ^ Text_table.plain_marker else text in
           { Text_table.text; emphasized = is_winner })
  in
  { Text_table.label = Id.to_string c.name; entries }

let ambiguous_row (a : Clash_detect.ambiguous_use) =
  let candidate is_winner (c : Glob_capture.candidate) =
    let text = if c.local then c.path ^ local_marker else c.path in
    let text = match c.status with Some st -> text ^ status_marker st | None -> text in
    let text = if is_winner then text ^ Text_table.plain_marker else text in
    (c.path, { Text_table.text; emphasized = is_winner })
  in
  let entries =
    (match a.use_winner with Some w -> [ candidate true w ] | None -> [])
    @ List.map (candidate false) a.use_alternatives
    |> List.sort (fun (a, _) (b, _) -> String.compare a b)
    |> List.map snd
  in
  let lines =
    match a.lines with
    | [ l ] -> Printf.sprintf "line %d" l
    | ls -> "lines " ^ String.concat ", " (List.map string_of_int ls)
  in
  { Text_table.label = Printf.sprintf "%s (%s)" a.written lines; entries }

let ambiguous_site_count ?kind (r : t) =
  List.fold_left
    (fun n (a : Clash_detect.ambiguous_use) ->
      if (match kind with None -> true | Some k -> a.kind = k) then n + List.length a.lines else n)
    0 r.ambiguous

let kind_json = function
  | Clash_detect.Shadowing -> "shadowing"
  | Partly_imported -> "partly_imported"
  | Unknown_import -> "unknown"
  | Latent -> "latent"
  | Local_only -> "local_only"

(* Past this many distinct clashing names, the grid itself becomes the
   readability problem, not the analysis (confirmed: 1,000 clashes render
   as a 3,007-line table) -- surface a hint toward --format summary/json
   (CLI) rather than silently leaving the reader to scroll through it. Only
   the grid needs this: --format summary/json are already the compact
   alternative, and the plugin's message panel has no --format of its own,
   so the hint always points at the CLI regardless of which front end is
   currently showing it. *)
let large_report_threshold = 100

let size_note (r : t) =
  let n = List.length r.clashes and m = List.length r.ambiguous in
  if n > large_report_threshold || m > large_report_threshold then
    Some
      (Printf.sprintf
         "Note: %d clashes and %d ambiguous uses found -- for a more compact view of a report this size, use the CLI with --format summary or --format json."
         n m)
  else None

let ambiguous_heading = "Ambiguous uses (judged where each name was used):"
let no_ambiguous = "No ambiguous uses found."
let ambiguous_headers = ("Name as written", "Candidates at that point (alphabetical)")
let clash_heading = "Clashes (namespace state at the analysis point):"

let is_named_occurrence (o : Glob_capture.occurrence) = o.ident <> "<>"

let occurrence_location (o : Glob_capture.occurrence) =
  let filepath = if o.filepath = "<>" || o.filepath = "" then "?" else o.filepath in
  let modpath = if o.modpath = "<>" || o.modpath = "" then "" else "." ^ o.modpath in
  filepath ^ modpath

let used_row (o : Glob_capture.occurrence) =
  { Text_table.label = o.ident;
    entries = [ { Text_table.text = occurrence_location o; emphasized = false } ] }

let to_pp (r : t) =
  let header =
    str "NamespaceAnalysis: " ++ int r.member_count ++ str " symbol(s) in scanned domain(s)"
  in
  let clash_body =
    if r.clashes = [] then str "No clashes found."
    else Text_table.render_pp ~headers:("Short name", "Candidates (alphabetical)") (List.map (clash_row r) r.clashes)
  in
  let named_used = List.filter is_named_occurrence r.used in
  let used_body =
    if named_used = [] then str "Used identifiers: (none captured)"
    else Text_table.render_pp ~headers:("Identifier", "Defined in") (List.map used_row named_used)
  in
  let ambiguous_body =
    if r.ambiguous = [] then str no_ambiguous
    else Text_table.render_pp ~headers:ambiguous_headers (List.map ambiguous_row r.ambiguous)
  in
  let note_line = match size_note r with Some msg -> str msg ++ fnl () | None -> mt () in
  header ++ fnl () ++ note_line ++ str ambiguous_heading ++ fnl () ++ ambiguous_body ++ fnl ()
  ++ str clash_heading ++ fnl () ++ clash_body ++ fnl ()
  ++ str "Used identifiers:" ++ fnl () ++ used_body

type counts = {
  members : int;
  clash_count : int;
  no_winner_count : int;
  used_count : int;
  ambiguous_sites : int;
  shadowing_sites : int;
  partial_sites : int;
  unknown_sites : int;
  latent_sites : int;
  local_only_sites : int;
}

let counts (r : t) =
  { members = r.member_count;
    clash_count = List.length r.clashes;
    no_winner_count = List.length (List.filter (fun (c : Clash_detect.clash) -> c.winner = None) r.clashes);
    used_count = List.length (List.filter is_named_occurrence r.used);
    ambiguous_sites = ambiguous_site_count r;
    shadowing_sites = ambiguous_site_count ~kind:Clash_detect.Shadowing r;
    partial_sites = ambiguous_site_count ~kind:Clash_detect.Partly_imported r;
    unknown_sites = ambiguous_site_count ~kind:Clash_detect.Unknown_import r;
    latent_sites = ambiguous_site_count ~kind:Clash_detect.Latent r;
    local_only_sites = ambiguous_site_count ~kind:Clash_detect.Local_only r }

let add_counts a b =
  { members = a.members + b.members;
    clash_count = a.clash_count + b.clash_count;
    no_winner_count = a.no_winner_count + b.no_winner_count;
    used_count = a.used_count + b.used_count;
    ambiguous_sites = a.ambiguous_sites + b.ambiguous_sites;
    shadowing_sites = a.shadowing_sites + b.shadowing_sites;
    partial_sites = a.partial_sites + b.partial_sites;
    unknown_sites = a.unknown_sites + b.unknown_sites;
    latent_sites = a.latent_sites + b.latent_sites;
    local_only_sites = a.local_only_sites + b.local_only_sites }

let ambiguous_breakdown c =
  Printf.sprintf
    "%d ambiguous use site(s) (%d shadowing, %d partly imported, %d unknown, %d latent, %d local-only)"
    c.ambiguous_sites c.shadowing_sites c.partial_sites c.unknown_sites c.latent_sites c.local_only_sites

let summary_of_counts c =
  Printf.sprintf
    "NamespaceAnalysis: %s, %d symbol(s) in scanned domain(s), %d clash(es) found (%d with no winner marked), %d identifier(s) used"
    (ambiguous_breakdown c) c.members c.clash_count c.no_winner_count c.used_count

let to_summary (r : t) = summary_of_counts (counts r)

let json_escape s =
  let buf = Buffer.create (String.length s + 2) in
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string buf "\\\""
      | '\\' -> Buffer.add_string buf "\\\\"
      | '\n' -> Buffer.add_string buf "\\n"
      | '\t' -> Buffer.add_string buf "\\t"
      | c when Char.code c < 0x20 -> Buffer.add_string buf (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char buf c)
    s;
  Buffer.contents buf

let json_string s = "\"" ^ json_escape s ^ "\""

let to_json (r : t) =
  let clash_json (c : Clash_detect.clash) =
    let winner =
      match c.winner with
      | Some w -> json_string (qualified_name w)
      | None -> "null"
    in
    let alternatives =
      c.alternatives
      |> List.map (fun gr -> (qualified_name gr, gr))
      |> List.sort (fun (a, _) (b, _) -> String.compare a b)
      |> List.map (fun (name, gr) ->
             let status = match clash_status r gr with Some st -> status_json st | None -> {|"status":"local"|} in
             Printf.sprintf {|{"name":%s,%s}|} (json_string name) status)
      |> String.concat ","
    in
    Printf.sprintf {|{"name":%s,"winner":%s,"alternatives":[%s]}|}
      (json_string (Id.to_string c.name)) winner alternatives
  in
  let used_json (o : Glob_capture.occurrence) =
    Printf.sprintf {|{"identifier":%s,"defined_in":%s}|}
      (json_string o.ident) (json_string (occurrence_location o))
  in
  let alternative_json (c : Glob_capture.candidate) =
    let status = match c.status with Some st -> status_json st | None -> {|"status":"local"|} in
    Printf.sprintf {|{"name":%s,%s}|} (json_string c.path) status
  in
  let ambiguous_json (a : Clash_detect.ambiguous_use) =
    Printf.sprintf {|{"name":%s,"lines":[%s],"kind":"%s","winner":%s,"alternatives":[%s]}|}
      (json_string a.written)
      (String.concat "," (List.map string_of_int a.lines))
      (kind_json a.kind)
      (match a.use_winner with Some w -> json_string w.path | None -> "null")
      (String.concat "," (List.map alternative_json a.use_alternatives))
  in
  let clashes_json = r.clashes |> List.map clash_json |> String.concat "," in
  let ambiguous_json_list = r.ambiguous |> List.map ambiguous_json |> String.concat "," in
  let used_json_list =
    r.used |> List.filter is_named_occurrence |> List.map used_json |> String.concat ","
  in
  Printf.sprintf {|{"member_count":%d,"ambiguous_uses":[%s],"clashes":[%s],"used":[%s]}|}
    r.member_count ambiguous_json_list clashes_json used_json_list

let to_string ?(color = false) r =
  let header =
    Printf.sprintf "NamespaceAnalysis: %d symbol(s) in scanned domain(s)" r.member_count
  in
  let clash_body =
    if r.clashes = [] then "No clashes found."
    else Text_table.render_string ~ansi:color ~headers:("Short name", "Candidates (alphabetical)") (List.map (clash_row r) r.clashes)
  in
  let named_used = List.filter is_named_occurrence r.used in
  let used_body =
    if named_used = [] then "Used identifiers: (none captured)"
    else Text_table.render_string ~ansi:color ~headers:("Identifier", "Defined in") (List.map used_row named_used)
  in
  let ambiguous_body =
    if r.ambiguous = [] then no_ambiguous
    else Text_table.render_string ~ansi:color ~headers:ambiguous_headers (List.map ambiguous_row r.ambiguous)
  in
  let note_lines = match size_note r with Some msg -> [ msg ] | None -> [] in
  String.concat "\n"
    (([ header ] @ note_lines)
    @ [ ambiguous_heading; ambiguous_body; clash_heading; clash_body; "Used identifiers:"; used_body ])
