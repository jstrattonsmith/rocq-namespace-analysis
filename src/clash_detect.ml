open Names

type clash = {
  name : Id.t;
  winner : GlobRef.t;
  alternatives : GlobRef.t list;
}

let find_clashes members =
  let names = List.sort_uniq Id.compare (List.map Nametab.basename_of_global members) in
  List.filter_map
    (fun name ->
      let qid = Libnames.qualid_of_ident name in
      match Nametab.locate_all qid with
      | [] | [ _ ] -> None
      | all -> (
        match Nametab.locate qid with
        | winner ->
          let alternatives =
            List.filter (fun gr -> not (GlobRef.UserOrd.equal gr winner)) all
          in
          Some { name; winner; alternatives }
        | exception Not_found -> None))
    names
