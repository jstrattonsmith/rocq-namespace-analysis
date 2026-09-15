open Names

let usage =
  Boot.Usage.
    {
      executable_name = "namespace-analysis";
      extra_args = "file.v";
      extra_options =
        "\n\
         namespace-analysis specific options:\n\
         \n\
        \  --domain <dirpath>     scan this library/module prefix for clashes\n\
        \                         (repeatable; 0 domains = everything currently\n\
        \                         imported, including auto-loaded Corelib)\n\
        \  --exclude <dirpath>    hide candidates under this prefix (repeatable;\n\
        \                         Corelib is excluded by default)\n\
        \  --include <dirpath>    un-hide a prefix (repeatable; overrides both\n\
        \                         the Corelib default and --exclude)\n";
    }

(* Consumes our own --domain/--exclude/--include/<file> arguments, leaving
   everything else (standard -R/-Q/-I flags, etc.) for Coqargs.parse_args to
   handle, mirroring how coqtop.ml's parse_extra hands off to
   Stmargs.parse_args and then to the standard argument parser inside
   Coqinit.parse_arguments. *)
let parse_extra opts extras =
  let rec go domains excl incl file = function
    | "--domain" :: d :: rest -> go (d :: domains) excl incl file rest
    | "--exclude" :: d :: rest -> go domains (d :: excl) incl file rest
    | "--include" :: d :: rest -> go domains excl (d :: incl) file rest
    | x :: rest when file = None && (String.length x = 0 || x.[0] <> '-') ->
      go domains excl incl (Some x) rest
    | x :: rest ->
      let (domains, excl, incl, file), rest = go domains excl incl file rest in
      (domains, excl, incl, file), x :: rest
    | [] -> (domains, excl, incl, file), []
  in
  let (domains, excl, incl, file), extras = go [] [] [] None extras in
  let async_opts, extras = Stmargs.parse_args opts extras in
  (List.rev domains, List.rev excl, List.rev incl, file, async_opts), extras

let dirpath_of_string s =
  let parts = String.split_on_char '.' s in
  DirPath.make (List.rev_map Id.of_string parts)

let default_excludes = [ dirpath_of_string "Corelib" ]

let die msg =
  prerr_endline ("namespace-analysis: " ^ msg);
  exit 1

(* Mirrors rocq-runtime's own `coqc_run` (toplevel/coqc.ml): without this,
   any exception past argument parsing (a bad `-R` directory, a `.v` file
   that fails to compile, a malformed `--domain` identifier, ...) escapes as
   a raw OCaml "Fatal error: exception ..." dump with exit code 2, instead
   of the clean one-line Rocq-style error message and conventional exit code
   (1 for a normal user error, 129 for an anomaly) every other Rocq
   command-line tool gives. Confirmed by direct testing before this fix
   existed: all of `-R <nonexistent dir>`, a type error in the target file,
   and a `--domain` string with an invalid identifier character all produced
   an uncaught-exception dump here even though `rocq compile` handles the
   same inputs cleanly. *)
let () =
  Coqinit.init_ocaml ();
  try
    let args = List.tl (Array.to_list Sys.argv) in
    let opts, (domain_strs, excl_strs, incl_strs, file, async_opts) =
      Coqinit.parse_arguments ~parse_extra ~initial_args:Coqargs.default args
    in
    let f_in = match file with
      | Some f -> f
      | None -> die "need a target .v file"
    in
    Stm.init_process async_opts;
    Coqinit.init_runtime ~usage opts;
    Coqinit.init_document opts;
    Stm.init_core ();
    let injections = Coqargs.injection_commands opts in
    let doc, sid =
      Stm.(new_doc { doc_type = Interactive opts.config.logic.toplevel_name; injections })
    in
    let state =
      Vernac.State.
        { doc; sid; proof = None; time = Option.map Vernac.make_time_output opts.config.time }
    in
    let state = Load.load_init_vernaculars opts ~state in
    (* Install capture before loading the target file: unlike the in-session
       plugin command, the CLI controls its own driver loop, so it doesn't
       need the "Require Import the plugin first" workaround. *)
    Glob_capture.install ();
    let ldir = Stm.get_ldir ~doc:state.doc in
    let source = Loc.InFile { dirpath = Some (DirPath.to_string ldir); file = f_in } in
    let state = Vernac.load_vernac ~echo:false ~check:true ~state ~source f_in in
    let _fullstate = Stm.finish ~doc:state.doc in
    Stm.join ~doc:state.doc;
    let dps = if domain_strs = [] then Library.loaded_libraries () else List.map dirpath_of_string domain_strs in
    List.iter Ensure_loaded.ensure_required dps;
    let excl_dps = List.map dirpath_of_string excl_strs in
    let incl_dps = List.map dirpath_of_string incl_strs in
    let excluded =
      List.filter
        (fun e -> not (List.exists (DirPath.equal e) incl_dps))
        (default_excludes @ excl_dps)
    in
    let members = Domain_scan.members_of_domains dps in
    let clashes = Clash_detect.find_clashes ~excluded members in
    let used = Glob_capture.occurrences () in
    let report = Report.make ~member_count:(List.length members) ~clashes ~used in
    print_string (Report.to_string ~color:(Unix.isatty Unix.stdout) report);
    print_newline ()
  with exn ->
    flush_all ();
    Topfmt.print_err_exn exn;
    flush_all ();
    exit (if CErrors.is_anomaly exn then 129 else 1)
