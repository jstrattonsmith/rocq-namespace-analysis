open Names

let usage =
  Boot.Usage.
    {
      executable_name = "import-analysis";
      extra_args = "file.v";
      extra_options =
        "\n\
         import-analysis specific options:\n\
         \n\
        \  --domain <dirpath>     scan this library/module prefix for clashes (repeatable)\n";
    }

(* Consumes our own --domain/<file> arguments, leaving everything else
   (standard -R/-Q/-I flags, etc.) for Coqargs.parse_args to handle, mirroring
   how coqtop.ml's parse_extra hands off to Stmargs.parse_args and then to
   the standard argument parser inside Coqinit.parse_arguments. *)
let parse_extra opts extras =
  let rec go domains file = function
    | "--domain" :: d :: rest -> go (d :: domains) file rest
    | x :: rest when file = None && (String.length x = 0 || x.[0] <> '-') ->
      go domains (Some x) rest
    | x :: rest ->
      let (domains, file), rest = go domains file rest in
      (domains, file), x :: rest
    | [] -> (domains, file), []
  in
  let (domains, file), extras = go [] None extras in
  let async_opts, extras = Stmargs.parse_args opts extras in
  (List.rev domains, file, async_opts), extras

let dirpath_of_string s =
  let parts = String.split_on_char '.' s in
  DirPath.make (List.rev_map Id.of_string parts)

let die msg =
  prerr_endline ("import-analysis: " ^ msg);
  exit 1

let () =
  Coqinit.init_ocaml ();
  let args = List.tl (Array.to_list Sys.argv) in
  let opts, (domain_strs, file, async_opts) =
    Coqinit.parse_arguments ~parse_extra ~initial_args:Coqargs.default args
  in
  if domain_strs = [] then die "need at least one --domain <dirpath>";
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
  let domains = List.map dirpath_of_string domain_strs in
  let members = Domain_scan.members_of_domains domains in
  let clashes = Clash_detect.find_clashes members in
  let used = Glob_capture.occurrences () in
  let report = Report.make ~member_count:(List.length members) ~clashes ~used in
  print_string (Report.to_string report);
  print_newline ()
