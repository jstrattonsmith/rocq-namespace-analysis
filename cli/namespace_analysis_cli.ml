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
        \                         the Corelib default and --exclude)\n\
        \  --dir <path>           recursively add every *.v file under <path>\n\
        \                         (repeatable; sorted per directory for\n\
        \                         determinism; appended after any explicit\n\
        \                         target files)\n\
        \  --format <mode>        grid (default), summary, or json\n";
    }

(* Consumes our own --domain/--exclude/--include/--dir/--format/<file>
   arguments, leaving everything else (standard -R/-Q/-I flags, etc.) for
   Coqargs.parse_args to handle, mirroring how coqtop.ml's parse_extra hands
   off to Stmargs.parse_args and then to the standard argument parser inside
   Coqinit.parse_arguments.

   Every bare non-dash token is a target file -- not just the first -- since
   `extras` handed here has already had every *recognized* flag (including
   -R/-Q/-I and their arguments) stripped out by the outer Rocq arg parser
   before parse_extra ever sees it (confirmed: this is exactly why the
   existing `-R dir dirpath --domain ... file.v` invocations already parsed
   correctly even before batch mode). *)
let parse_extra opts extras =
  let rec go domains excl incl files dirs format = function
    | "--domain" :: d :: rest -> go (d :: domains) excl incl files dirs format rest
    | "--exclude" :: d :: rest -> go domains (d :: excl) incl files dirs format rest
    | "--include" :: d :: rest -> go domains excl (d :: incl) files dirs format rest
    | "--dir" :: d :: rest -> go domains excl incl files (d :: dirs) format rest
    | "--format" :: f :: rest -> go domains excl incl files dirs (Some f) rest
    | x :: rest when String.length x = 0 || x.[0] <> '-' ->
      go domains excl incl (x :: files) dirs format rest
    | x :: rest ->
      let (domains, excl, incl, files, dirs, format), rest =
        go domains excl incl files dirs format rest
      in
      (domains, excl, incl, files, dirs, format), x :: rest
    | [] -> (domains, excl, incl, files, dirs, format), []
  in
  let (domains, excl, incl, files, dirs, format), extras = go [] [] [] [] [] None extras in
  let async_opts, extras = Stmargs.parse_args opts extras in
  ( (List.rev domains, List.rev excl, List.rev incl, List.rev files, List.rev dirs, format, async_opts),
    extras )

let dirpath_of_string s =
  let parts = String.split_on_char '.' s in
  DirPath.make (List.rev_map Id.of_string parts)

let default_excludes = [ dirpath_of_string "Corelib" ]

let die msg =
  prerr_endline ("namespace-analysis: " ^ msg);
  exit 1

(* Recursively collects every *.v under [dir], sorted by full path for
   deterministic ordering regardless of the underlying filesystem's own
   directory-entry order. Doesn't special-case build byproduct directories
   (e.g. _build) -- --dir is meant to be pointed at a real source tree, and
   guarding against every possible byproduct directory name a target project
   might use would be guessing at a problem no one has actually hit. *)
let collect_v_files_under dir =
  let rec walk d acc =
    Array.fold_left
      (fun acc name ->
        let path = Filename.concat d name in
        if Sys.is_directory path then walk path acc
        else if Filename.check_suffix name ".v" then path :: acc
        else acc)
      acc (Sys.readdir d)
  in
  List.sort String.compare (walk dir [])

let parse_format = function
  | None | Some "grid" -> `Grid
  | Some "summary" -> `Summary
  | Some "json" -> `Json
  | Some other -> die (Printf.sprintf "unknown --format value %S (expected grid, summary, or json)" other)

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
    let opts, (domain_strs, excl_strs, incl_strs, files, dirs, format_str, async_opts) =
      Coqinit.parse_arguments ~parse_extra ~initial_args:Coqargs.default args
    in
    let format = parse_format format_str in
    let f_ins = files @ List.concat_map collect_v_files_under dirs in
    let f_ins = match f_ins with
      | [] -> die "need a target .v file"
      | fs -> fs
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
    (* Load every file into this one Rocq session -- state threads through
       each call exactly as the single-file case already did -- then do
       exactly one domain scan + clash detection + report at the end below,
       same as today. The single-file case is just the [f_ins = [f]] case of
       this same fold, byte-for-byte unchanged. *)
    let state =
      List.fold_left
        (fun state f_in ->
          let source = Loc.InFile { dirpath = Some (DirPath.to_string ldir); file = f_in } in
          Vernac.load_vernac ~echo:false ~check:true ~state ~source f_in)
        state f_ins
    in
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
    (match format with
     | `Grid -> print_string (Report.to_string ~color:(Unix.isatty Unix.stdout) report)
     | `Summary -> print_string (Report.to_summary report)
     | `Json -> print_string (Report.to_json report));
    print_newline ()
  with exn ->
    flush_all ();
    Topfmt.print_err_exn exn;
    flush_all ();
    exit (if CErrors.is_anomaly exn then 129 else 1)
