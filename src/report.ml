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
  header ++ fnl () ++ str "Clashes:" ++ fnl () ++ clash_body ++ fnl ()
  ++ str "Used identifiers:" ++ fnl () ++ used_body

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
  String.concat "\n"
    [ header; "Clashes:"; clash_body; "Used identifiers:"; used_body ]
