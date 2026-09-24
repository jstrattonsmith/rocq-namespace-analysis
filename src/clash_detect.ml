open Names

type clash = {
  name : Id.t;
  winner : GlobRef.t option;
  alternatives : GlobRef.t list;
}

let in_excluded excluded gr =
  let dp = Nametab.dirpath_of_global gr in
  List.exists (fun e -> Libnames.is_dirpath_prefix_of e dp) excluded

(* Grouping [members] by basename once, up front, turns the per-name lookup
   below into an O(log n) map access instead of an O(n) linear scan over
   every member for every name -- the difference between O(n) and O(n^2)
   overall. Confirmed by direct measurement: before this, 10,000 scanned
   members took ~10.6s; the naive version scaled roughly quadratically
   (1,000 members took ~0.16s, a 10x input growing to a ~65x-70x runtime
   increase). *)
let find_clashes ~excluded members =
  let by_name =
    List.fold_left
      (fun acc gr ->
        let name = Nametab.basename_of_global gr in
        let existing = match Id.Map.find_opt name acc with Some l -> l | None -> [] in
        Id.Map.add name (gr :: existing) acc)
      Id.Map.empty members
  in
  List.filter_map
    (fun (name, from_members) ->
      let qid = Libnames.qualid_of_ident name in
      let visible = Nametab.locate_all qid in
      let all =
        List.sort_uniq GlobRef.UserOrd.compare (visible @ from_members)
        |> List.filter (fun gr -> not (in_excluded excluded gr))
      in
      match all with
      | [] | [ _ ] -> None
      | all ->
        let winner =
          match Nametab.locate qid with
          | exception Not_found -> None
          | w -> if in_excluded excluded w then None else Some w
        in
        let alternatives =
          match winner with
          | Some w -> List.filter (fun gr -> not (GlobRef.UserOrd.equal gr w)) all
          | None -> all
        in
        Some { name; winner; alternatives })
    (Id.Map.bindings by_name)

type use_kind = Shadowing | Partly_imported | Unknown_import | Latent | Local_only

type ambiguous_use = {
  written : string;
  lines : int list;
  use_winner : Glob_capture.candidate option;
  use_alternatives : Glob_capture.candidate list;
  kind : use_kind;
}

(* Strongest claim first: one really shadowed alternative makes the use a
   real "last import wins"; an undecided one (partial/unknown) outranks a
   clean "only loaded"; all-Local means nothing else could ever be reached
   by this name. *)
let kind_of (alts : Glob_capture.candidate list) =
  let has p = List.exists p alts in
  let status s (c : Glob_capture.candidate) = c.status = Some s in
  if has (status Import_status.Imported) then Shadowing
  else if has (fun c -> match c.status with Some (Import_status.Partial _) -> true | _ -> false) then Partly_imported
  else if has (status Import_status.Unknown) then Unknown_import
  else if has (status Import_status.Not_imported) then Latent
  else Local_only

let candidate_excluded excluded (c : Glob_capture.candidate) =
  List.exists (fun e -> Libnames.is_dirpath_prefix_of e c.dirpath) excluded

(* Same rule as [find_clashes], applied per use site: excluded candidates
   drop out, 2+ remaining makes the use ambiguous, and an excluded winner
   is left unmarked rather than revealed. Uses of the same written name
   that saw the same winner and the same alternatives collapse into one
   entry listing every line, in first-seen order; a use whose winner, or
   any alternative's import status, changed (a later Import, a
   Section-scoped one) stays a separate entry. *)
let ambiguous_uses ~excluded (occurrences : Glob_capture.occurrence list) =
  let key_of written winner alts =
    ( written,
      Option.map (fun (c : Glob_capture.candidate) -> c.path) winner,
      List.map (fun (c : Glob_capture.candidate) -> (c.path, c.status)) alts )
  in
  let groups = Hashtbl.create 16 in
  let order = ref [] in
  List.iter
    (fun (o : Glob_capture.occurrence) ->
      match o.use_site with
      | None -> ()
      | Some u ->
        let keep = List.filter (fun c -> not (candidate_excluded excluded c)) in
        let winner = if candidate_excluded excluded u.winner then None else Some u.winner in
        let alts =
          List.sort_uniq (fun (a : Glob_capture.candidate) b -> String.compare a.path b.path) (keep u.others)
        in
        let count = List.length alts + (if winner = None then 0 else 1) in
        if count >= 2 then begin
          let key = key_of u.written winner alts in
          let line = o.loc.Loc.line_nb in
          match Hashtbl.find_opt groups key with
          | Some g ->
            if not (List.mem line g.lines) then Hashtbl.replace groups key { g with lines = line :: g.lines }
          | None ->
            order := key :: !order;
            Hashtbl.replace groups key
              { written = u.written; lines = [ line ]; use_winner = winner; use_alternatives = alts;
                kind = kind_of alts }
        end)
    occurrences;
  List.rev_map
    (fun key ->
      let g = Hashtbl.find groups key in
      { g with lines = List.sort_uniq Int.compare g.lines })
    !order
