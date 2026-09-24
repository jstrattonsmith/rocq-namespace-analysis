(* Two bugs/quirks worked around here, both confirmed by direct
   experimentation against the actual installed Rocq sources, not assumed:

   1. Library.library_is_loaded is unusable: in the installed 9.2.0 sources
      (vernac/library.ml) it's [try let _ = find_library dir in true with
      Not_found -> false], but [find_library] uses [DirPath.Map.find_opt],
      which returns an option and never raises [Not_found] -- so
      [library_is_loaded] always returns [true], for any dirpath, loaded or
      not. [Library.loaded_libraries] reads the same underlying table
      correctly (no try/with bug), so that's used instead.

   2. Bypassing the real `Require` vernacular (calling
      [Library.require_library_from_dirpath] directly, since we already
      have a resolved DirPath.t and don't need `Require`'s qualid/`From X
      Require Y` resolution) loads the library into the kernel environment
      fine, but the *loaded-library bookkeeping* doesn't durably persist to
      the next vernacular command the way it does for a real `Require` --
      confirmed via a minimal two-command repro: [Library.loaded_libraries]
      reports the domain as not-loaded again on the second command, so a
      second [ensure_required] call for the same domain re-attempts the
      load and fails with "K already exists" (the kernel already has it
      from the first, real, successful load). Tried flagging the call as
      running in Rocq's synterp phase (Flags.in_synterp_phase, which is
      what real `Require` does internally, per vernacentries.ml's
      vernac_require) to see if that was the missing piece, but its type
      isn't even stable across the two Rocq versions this project supports
      (bool ref in 9.1.1, bool option ref in 9.2.0) -- not something to
      depend on. Instead: remember what *we* have force-required in a
      plain OCaml table, which trivially persists for the life of the
      process regardless of whatever Rocq's own Summary/STM bookkeeping
      does between sentences.

   TODO(revisit): worth a closer look eventually -- either report (1)
   upstream, or find the real fix for (2) (something in Synterp's phase
   handling is almost certainly the actual answer) rather than routing
   around it. Low priority: the workarounds are correct and cheap, and
   Ensure_loaded's own behavior is unaffected by which one is doing the
   work internally. *)

let already_required : (Names.DirPath.t, unit) Hashtbl.t = Hashtbl.create 16

(* Every library this module itself caused to be loaded -- [dp] plus any
   dependency of it that wasn't already loaded -- as opposed to anything the
   analyzed file loaded on its own. Glob_capture's use-site snapshot leaves
   these out: a use site should be judged against the file's own namespace,
   not against a side effect of this tool (e.g. an earlier in-file
   `NamespaceAnalysis <hypothetical domain>` command, which would otherwise
   make every later use in the plugin see candidates the CLI never would). *)
let tool_loaded : (Names.DirPath.t, unit) Hashtbl.t = Hashtbl.create 16

let loaded_by_tool dp =
  Hashtbl.mem tool_loaded dp
  || Hashtbl.fold (fun lib () acc -> acc || Libnames.is_dirpath_prefix_of lib dp) tool_loaded false

let is_loaded dp =
  Hashtbl.mem already_required dp
  || List.exists (Names.DirPath.equal dp) (Library.loaded_libraries ())

(* A domain argument has always been allowed to be a namespace PREFIX, not
   just an exact compiled library (e.g. probing plain `MyDev` has always
   matched both `MyDev.PartA` and `MyDev.PartB`) -- and that's exactly what
   makes multi-level probing useful (probing a shallow prefix to catch a
   clash several levels deeper). Only an EXACT library dirpath can be
   `Require`d, though: `Demo.Sub` alone, naming a level with no compiled
   unit of its own (only `Demo.Sub.Deep.DeepOne` actually exists), can never
   be located by [Loadpath.locate_absolute_library] -- confirmed directly:
   "Cannot load Demo.Sub: no physical path bound to Demo". So a
   not-found here isn't necessarily a typo: silently doing nothing lets
   Domain_scan's own prefix matching find whatever's already loaded under
   it. The tradeoff, worth being upfront about: a genuine typo of an
   otherwise-exact hypothetical domain name degrades to the same "0 members,
   no clashes" result this already gave before hypothetical domains existed
   -- not a regression, just not the loud error initially hoped for
   (unavoidable without knowing in advance whether a given dirpath was
   *meant* to be exact). *)
let ensure_required dp =
  if is_loaded dp then ()
  else
    match Loadpath.locate_absolute_library dp with
    | Error Loadpath.Error.(LibUnmappedDir | LibNotFound) -> ()
    | Ok physical_path -> (
      match Library.intern_from_file physical_path with
      | Ok lib, _provenance ->
        let before = Library.loaded_libraries () in
        Library.require_library_from_dirpath [ lib ];
        Hashtbl.replace already_required dp ();
        Hashtbl.replace tool_loaded dp ();
        List.iter
          (fun l -> if not (List.exists (Names.DirPath.equal l) before) then Hashtbl.replace tool_loaded l ())
          (Library.loaded_libraries ())
      | Error iexn, _provenance -> Exninfo.iraise iexn)
