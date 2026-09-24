open Names

type candidate = {
  path : string;
  dirpath : DirPath.t;
  local : bool;
}

type use_site = {
  written : string;
  winner : candidate;
  others : candidate list;
}

type occurrence = {
  loc : Loc.t;
  filepath : string;
  modpath : string;
  ident : string;
  kind : string;
  use_site : use_site option;
}

let buffer : occurrence list ref = ref []
let feeder_id : int option ref = ref None

(* Glob kinds that name modules, sections, notations, or libraries rather
   than a global term -- Nametab.locate would either miss them or find an
   unrelated term of the same name. *)
let non_term_kinds = [ "lib"; "mod"; "modtype"; "sec"; "not"; "binder" ]

(* The reference as the user wrote it is only available as a byte range
   into the source file, so read the file (once per file) and slice it.
   When the text on disk can't be what was elaborated (an editor buffer
   with unsaved edits, say), the slice won't end in the resolved
   identifier, and the use site is simply not judged rather than judged
   against garbage. *)
let sources : (string, string option) Hashtbl.t = Hashtbl.create 7

let source_of file =
  match Hashtbl.find_opt sources file with
  | Some s -> s
  | None ->
    let s = try Some (In_channel.with_open_bin file In_channel.input_all) with Sys_error _ -> None in
    Hashtbl.add sources file s;
    s

let last_segment s =
  match String.rindex_opt s '.' with
  | Some i -> String.sub s (i + 1) (String.length s - i - 1)
  | None -> s

let written_text (loc : Loc.t) ident =
  match loc.Loc.fname with
  | Loc.InFile { file; _ } -> (
    match source_of file with
    | Some src when loc.bp >= 0 && loc.ep <= String.length src && loc.bp < loc.ep ->
      let text = String.sub src loc.bp (loc.ep - loc.bp) in
      if String.equal (last_segment text) (last_segment ident) then Some text else None
    | _ -> None)
  | Loc.ToplevelInput -> None

let candidate_of gr =
  { path = Libnames.string_of_path (Nametab.path_of_global gr);
    dirpath = Nametab.dirpath_of_global gr;
    local = (match gr with GlobRef.ConstRef c -> Declare.is_local_constant c | _ -> false) }

let is_global = function GlobRef.VarRef _ -> false | _ -> true

let judge_use_site loc filepath ident kind =
  if filepath = "<>" || List.mem kind non_term_kinds then None
  else
    match written_text loc ident with
    | None -> None
    | Some written -> (
      match Libnames.qualid_of_string written with
      | exception _ -> None
      | qid -> (
        match Nametab.locate qid with
        | exception Not_found -> None
        | winner when not (is_global winner) -> None
        | winner ->
          let others =
            Nametab.locate_all qid
            |> List.filter (fun gr ->
                   is_global gr
                   && (not (GlobRef.UserOrd.equal gr winner))
                   && not (Ensure_loaded.loaded_by_tool (Nametab.dirpath_of_global gr)))
          in
          if others = [] then None
          else Some { written; winner = candidate_of winner; others = List.map candidate_of others }))

let handle_feedback (fb : Feedback.feedback) =
  match fb.Feedback.contents with
  | Feedback.GlobRef (loc, filepath, modpath, ident, kind) ->
    let use_site = judge_use_site loc filepath ident kind in
    buffer := { loc; filepath; modpath; ident; kind; use_site } :: !buffer
  | _ -> ()

let install () =
  if !feeder_id = None then begin
    Dumpglob.push_output Dumpglob.Feedback;
    feeder_id := Some (Feedback.add_feeder handle_feedback)
  end

let occurrences () = List.rev !buffer

let reset () = buffer := []
