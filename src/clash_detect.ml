open Names

type clash = {
  name : Id.t;
  winner : GlobRef.t option;
  alternatives : GlobRef.t list;
}

let in_excluded excluded gr =
  let dp = Nametab.dirpath_of_global gr in
  List.exists (fun e -> Libnames.is_dirpath_prefix_of e dp) excluded

let find_clashes ~excluded members =
  let names = List.sort_uniq Id.compare (List.map Nametab.basename_of_global members) in
  List.filter_map
    (fun name ->
      let qid = Libnames.qualid_of_ident name in
      let visible = Nametab.locate_all qid in
      let from_members =
        List.filter (fun gr -> Id.equal (Nametab.basename_of_global gr) name) members
      in
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
    names
