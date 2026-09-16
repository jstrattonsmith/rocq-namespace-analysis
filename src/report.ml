open Names
open Pp

type t = {
  member_count : int;
  clashes : Clash_detect.clash list;
  used : Glob_capture.occurrence list;
}

let make ~member_count ~clashes ~used = { member_count; clashes; used }

let qualified_name gr = Libnames.string_of_path (Nametab.path_of_global gr)

let clash_row (c : Clash_detect.clash) =
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
    |> List.map (fun gr -> (qualified_name gr, is_winner gr))
    |> List.sort (fun (a, _) (b, _) -> String.compare a b)
    |> List.map (fun (text, is_winner) ->
           { Text_table.text = (if is_winner then text ^ Text_table.plain_marker else text);
             emphasized = is_winner })
  in
  { Text_table.label = Id.to_string c.name; entries }

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
  let n = List.length r.clashes in
  if n > large_report_threshold then
    Some
      (Printf.sprintf
         "Note: %d clashes found -- for a more compact view of a report this size, use the CLI with --format summary or --format json."
         n)
  else None

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
    else Text_table.render_pp ~headers:("Short name", "Candidates (alphabetical)") (List.map clash_row r.clashes)
  in
  let named_used = List.filter is_named_occurrence r.used in
  let used_body =
    if named_used = [] then str "Used identifiers: (none captured)"
    else Text_table.render_pp ~headers:("Identifier", "Defined in") (List.map used_row named_used)
  in
  let note_line = match size_note r with Some msg -> str msg ++ fnl () | None -> mt () in
  header ++ fnl () ++ note_line ++ str "Clashes:" ++ fnl () ++ clash_body ++ fnl ()
  ++ str "Used identifiers:" ++ fnl () ++ used_body

let to_summary (r : t) =
  let clash_count = List.length r.clashes in
  let no_winner_count = List.length (List.filter (fun (c : Clash_detect.clash) -> c.winner = None) r.clashes) in
  let used_count = List.length (List.filter is_named_occurrence r.used) in
  Printf.sprintf
    "NamespaceAnalysis: %d symbol(s) in scanned domain(s), %d clash(es) found (%d with no winner marked), %d identifier(s) used"
    r.member_count clash_count no_winner_count used_count

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
      |> List.map qualified_name
      |> List.sort String.compare
      |> List.map json_string
      |> String.concat ","
    in
    Printf.sprintf {|{"name":%s,"winner":%s,"alternatives":[%s]}|}
      (json_string (Id.to_string c.name)) winner alternatives
  in
  let used_json (o : Glob_capture.occurrence) =
    Printf.sprintf {|{"identifier":%s,"defined_in":%s}|}
      (json_string o.ident) (json_string (occurrence_location o))
  in
  let clashes_json = r.clashes |> List.map clash_json |> String.concat "," in
  let used_json_list =
    r.used |> List.filter is_named_occurrence |> List.map used_json |> String.concat ","
  in
  Printf.sprintf {|{"member_count":%d,"clashes":[%s],"used":[%s]}|}
    r.member_count clashes_json used_json_list

let to_string ?(color = false) r =
  let header =
    Printf.sprintf "NamespaceAnalysis: %d symbol(s) in scanned domain(s)" r.member_count
  in
  let clash_body =
    if r.clashes = [] then "No clashes found."
    else Text_table.render_string ~ansi:color ~headers:("Short name", "Candidates (alphabetical)") (List.map clash_row r.clashes)
  in
  let named_used = List.filter is_named_occurrence r.used in
  let used_body =
    if named_used = [] then "Used identifiers: (none captured)"
    else Text_table.render_string ~ansi:color ~headers:("Identifier", "Defined in") (List.map used_row named_used)
  in
  let note_lines = match size_note r with Some msg -> [ msg ] | None -> [] in
  String.concat "\n"
    (([ header ] @ note_lines) @ [ "Clashes:"; clash_body; "Used identifiers:"; used_body ])
