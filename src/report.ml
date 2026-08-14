open Names
open Pp

type t = {
  member_count : int;
  clashes : Clash_detect.clash list;
  used : Glob_capture.occurrence list;
}

let make ~member_count ~clashes ~used = { member_count; clashes; used }

let pr_gr gr = Libnames.pr_path (Nametab.path_of_global gr)

let pr_clash (c : Clash_detect.clash) =
  v 2 (
    str "  " ++ Id.print c.name ++ str " -> " ++ pr_gr c.winner
    ++ (if c.alternatives = [] then mt ()
        else
          str " (shadows " ++
          prlist_with_sep (fun () -> str ", ") pr_gr c.alternatives
          ++ str ")")
  )

let is_named_occurrence (o : Glob_capture.occurrence) = o.ident <> "<>"

let pr_occurrence (o : Glob_capture.occurrence) =
  str "  " ++ str o.ident ++ str " -> "
  ++ (if o.filepath = "<>" || o.filepath = "" then str "?" else str o.filepath)
  ++ (if o.modpath = "<>" || o.modpath = "" then mt () else str "." ++ str o.modpath)

let to_pp (r : t) =
  let header =
    str "NamespaceAnalysis: " ++ int r.member_count ++ str " symbol(s) in scanned domain(s)"
  in
  let clash_body =
    if r.clashes = [] then str "No clashes found."
    else v 0 (str "Clashes:" ++ fnl () ++ prlist_with_sep fnl pr_clash r.clashes)
  in
  let named_used = List.filter is_named_occurrence r.used in
  let used_body =
    if named_used = [] then str "Used identifiers: (none captured)"
    else v 0 (str "Used identifiers:" ++ fnl () ++ prlist_with_sep fnl pr_occurrence named_used)
  in
  header ++ fnl () ++ clash_body ++ fnl () ++ used_body

let to_string r = string_of_ppcmds (to_pp r)
