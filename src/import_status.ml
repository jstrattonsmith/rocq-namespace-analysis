open Names

type t =
  | Imported
  | Not_imported
  | Partial of int * int
  | Unknown

let module_of gr = fst (Libnames.repr_path (Nametab.path_of_global gr))

(* Innermost module dirpath -> its globals, built from one environment walk
   and reused while the environment stays the same. A lookup that misses
   triggers a rebuild only if the environment has changed since the last
   build ([Global.env ()] is a new value after any change) -- a module
   loaded or defined since then shows up, and a module that really has no
   members costs at most one rebuild per environment state. (An earlier
   version cached misses until the next rebuild, which left a module that
   was loaded later looking empty -- "unknown" -- whenever nothing else
   happened to force a rebuild.) *)
let table : (DirPath.t, GlobRef.t list) Hashtbl.t option ref = ref None
let built_for : Environ.env option ref = ref None

let build () =
  let tbl = Hashtbl.create 4096 in
  Domain_scan.fold_globals
    (fun gr () ->
      match module_of gr with
      | exception Not_found -> ()
      | dp -> Hashtbl.replace tbl dp (gr :: Option.default [] (Hashtbl.find_opt tbl dp)))
    ();
  table := Some tbl;
  built_for := Some (Global.env ());
  tbl

let members dp =
  let tbl = match !table with Some t -> t | None -> build () in
  match Hashtbl.find_opt tbl dp with
  | Some l -> l
  | None ->
    let env_changed = match !built_for with Some e -> e != Global.env () | None -> true in
    if env_changed then Option.default [] (Hashtbl.find_opt (build ()) dp) else []

let is_local = function GlobRef.ConstRef c -> Declare.is_local_constant c | _ -> false

(* [Some resolves] for a testable sibling -- its bare name has exactly one
   candidate, itself -- and [None] otherwise. *)
let test_sibling d =
  let q = Libnames.qualid_of_ident (Nametab.basename_of_global d) in
  match Nametab.locate_all q with
  | [ only ] when GlobRef.UserOrd.equal only d -> (
    match Nametab.locate q with
    | exception Not_found -> Some false
    | w -> Some (GlobRef.UserOrd.equal w d))
  | _ -> None

let tally ?except dp =
  let tested, resolving =
    List.fold_left
      (fun (tested, resolving) d ->
        let excepted = match except with Some gr -> GlobRef.UserOrd.equal d gr | None -> false in
        if excepted || is_local d then (tested, resolving)
        else
          match test_sibling d with
          | None -> (tested, resolving)
          | Some r -> (tested + 1, if r then resolving + 1 else resolving))
      (0, 0) (members dp)
  in
  if tested = 0 then Unknown
  else if resolving = tested then Imported
  else if resolving = 0 then Not_imported
  else Partial (resolving, tested)

let of_global gr =
  match module_of gr with
  | exception Not_found -> Unknown
  | dp -> tally ~except:gr dp

let module_of_global gr = try Some (module_of gr) with Not_found -> None

let of_module dp = tally dp
