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
        \                         target files). With 2+ target files, each\n\
        \                         is analyzed on its own, in its own process\n\
        \  --format <mode>        grid (default), summary, or json\n";
    }

type extra = {
  domains : string list;
  excl : string list;
  incl : string list;
  files : string list;
  dirs : string list;
  format : string option;
  worker : (string * bool) option;
      (** internal: [--batch-worker <result file> <0|1 color>], set only
          by a batch parent on the child processes it spawns *)
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
  let rec go x = function
    | "--domain" :: d :: rest -> go { x with domains = d :: x.domains } rest
    | "--exclude" :: d :: rest -> go { x with excl = d :: x.excl } rest
    | "--include" :: d :: rest -> go { x with incl = d :: x.incl } rest
    | "--dir" :: d :: rest -> go { x with dirs = d :: x.dirs } rest
    | "--format" :: f :: rest -> go { x with format = Some f } rest
    | "--batch-worker" :: out :: color :: rest -> go { x with worker = Some (out, color = "1") } rest
    | a :: rest when String.length a = 0 || a.[0] <> '-' -> go { x with files = a :: x.files } rest
    | a :: rest ->
      let x, rest = go x rest in
      x, a :: rest
    | [] -> x, []
  in
  let empty = { domains = []; excl = []; incl = []; files = []; dirs = []; format = None; worker = None } in
  let x, extras = go empty extras in
  let async_opts, extras = Stmargs.parse_args opts extras in
  ( ( { x with domains = List.rev x.domains; excl = List.rev x.excl; incl = List.rev x.incl;
        files = List.rev x.files; dirs = List.rev x.dirs },
      async_opts ),
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
(* Analyzes exactly one file in this process, the same way `rocq compile`
   would elaborate it -- including under its real logical name (derived
   from the -R/-Q load path by the same Coqinit.dirpath_of_file coqc uses),
   not a fixed `Top`. That matters for files that refer to their own
   definitions by their module name (e.g. Iris's `big_op.big_opM_unseal`
   inside big_op.v), which fail to elaborate at all under `Top`. An explicit
   `-top` still wins. *)
let analyze opts async_opts x f_in =
  Stm.init_process async_opts;
  Coqinit.init_runtime ~usage opts;
  Coqinit.init_document opts;
  Stm.init_core ();
  let injections = Coqargs.injection_commands opts in
  let top =
    if opts.Coqargs.config.logic.toplevel_name = Coqargs.default.config.logic.toplevel_name then
      Coqargs.TopPhysical f_in
    else opts.config.logic.toplevel_name
  in
  let doc, sid = Stm.(new_doc { doc_type = Interactive top; injections }) in
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
  let dps = if x.domains = [] then Library.loaded_libraries () else List.map dirpath_of_string x.domains in
  List.iter Ensure_loaded.ensure_required dps;
  let excl_dps = List.map dirpath_of_string x.excl in
  let incl_dps = List.map dirpath_of_string x.incl in
  let excluded =
    List.filter
      (fun e -> not (List.exists (DirPath.equal e) incl_dps))
      (default_excludes @ excl_dps)
  in
  let members = Domain_scan.members_of_domains dps in
  let clashes = Clash_detect.find_clashes ~excluded members in
  let used = Glob_capture.occurrences () in
  let ambiguous = Clash_detect.ambiguous_uses ~excluded used in
  Report.make ~member_count:(List.length members) ~clashes ~ambiguous ~used

(* What a batch worker hands back to its parent. Pre-rendered, because
   rendering needs the worker's own loaded environment (Nametab paths of
   clash candidates), which the parent never has. *)
type worker_result = {
  grid : string;
  json : string;
  counts : Report.counts;
}

(* The parent's own argv minus everything that selects targets or output
   (--dir, --format, the target files), so each worker gets the same
   load path, domains, and exclusions, plus its one file. *)
let worker_base_args args (x : extra) =
  let rec strip = function
    | ("--dir" | "--format") :: _ :: rest -> strip rest
    | a :: rest when List.mem a x.files -> strip rest
    | a :: rest -> a :: strip rest
    | [] -> []
  in
  strip args

let run_worker ~base_args ~color f =
  let out = Filename.temp_file "namespace-analysis" ".result" in
  let exe = Sys.executable_name in
  let argv = Array.of_list ((exe :: base_args) @ [ "--batch-worker"; out; (if color then "1" else "0"); f ]) in
  (* Worker stdout goes to our stderr: anything Rocq prints there is
     diagnostics, and our own stdout must stay a clean report (e.g. JSON). *)
  let pid = Unix.create_process exe argv Unix.stdin Unix.stderr Unix.stderr in
  let _, status = Unix.waitpid [] pid in
  let result =
    match status with
    | Unix.WEXITED 0 -> Some (In_channel.with_open_bin out (fun ic -> (Marshal.from_channel ic : worker_result)))
    | _ -> None
  in
  (try Sys.remove out with Sys_error _ -> ());
  result

(* Batch mode: one fresh process per file, never a shared session. Loading
   several files into one session (the original design) put each file's
   definitions under `Top` next to the compiled copy its neighbours
   Require -- every symbol "clashed" with itself -- and leaked one file's
   Imports into the next. Each file's report stands alone; only the
   ambiguous-use-site count is added up, since the other counts describe
   overlapping environments and wouldn't mean anything summed. *)
let run_batch args x format files =
  let base_args = worker_base_args args x in
  let color = format = `Grid && Unix.isatty Unix.stdout in
  let results = List.map (fun f -> (f, run_worker ~base_args ~color f)) files in
  let failed = List.length (List.filter (fun (_, r) -> r = None) results) in
  let total_sites =
    List.fold_left (fun n (_, r) -> match r with Some r -> n + r.counts.Report.ambiguous_sites | None -> n) 0 results
  in
  let total_line =
    Printf.sprintf "Total: %d file(s) analyzed, %d failed, %d ambiguous use site(s)"
      (List.length files) failed total_sites
  in
  (match format with
   | `Grid ->
     List.iter
       (fun (f, r) ->
         print_endline ("==> " ^ f);
         match r with
         | Some r -> print_endline r.grid
         | None -> print_endline "FAILED (see the error on stderr)")
       results;
     print_endline total_line
   | `Summary ->
     List.iter
       (fun (f, r) ->
         match r with
         | Some r -> print_endline (f ^ ": " ^ Report.summary_of_counts r.counts)
         | None -> print_endline (f ^ ": FAILED (see the error on stderr)"))
       results;
     print_endline total_line
   | `Json ->
     let file_json (f, r) =
       match r with
       | Some r -> Printf.sprintf {|{"file":%s,"report":%s}|} (Report.json_string f) r.json
       | None -> Printf.sprintf {|{"file":%s,"error":true}|} (Report.json_string f)
     in
     Printf.printf {|{"files":[%s],"failed":%d,"ambiguous_sites":%d}|}
       (String.concat "," (List.map file_json results)) failed total_sites;
     print_newline ());
  if failed > 0 then exit 1

let () =
  Coqinit.init_ocaml ();
  try
    let args = List.tl (Array.to_list Sys.argv) in
    let opts, (x, async_opts) =
      Coqinit.parse_arguments ~parse_extra ~initial_args:Coqargs.default args
    in
    let format = parse_format x.format in
    let f_ins = x.files @ List.concat_map collect_v_files_under x.dirs in
    match x.worker, f_ins with
    | _, [] -> die "need a target .v file"
    | Some (out, color), [ f ] ->
      let report = analyze opts async_opts x f in
      let result =
        { grid = Report.to_string ~color report; json = Report.to_json report; counts = Report.counts report }
      in
      Out_channel.with_open_bin out (fun oc -> Marshal.to_channel oc result [])
    | Some _, _ -> die "--batch-worker takes exactly one target file"
    | None, [ f ] ->
      let report = analyze opts async_opts x f in
      (match format with
       | `Grid -> print_string (Report.to_string ~color:(Unix.isatty Unix.stdout) report)
       | `Summary -> print_string (Report.to_summary report)
       | `Json -> print_string (Report.to_json report));
      print_newline ()
    | None, files -> run_batch args x format files
  with exn ->
    flush_all ();
    Topfmt.print_err_exn exn;
    flush_all ();
    exit (if CErrors.is_anomaly exn then 129 else 1)
