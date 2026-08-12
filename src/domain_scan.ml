open Names

let in_domain domains gr =
  let dp = Nametab.dirpath_of_global gr in
  List.exists (fun d -> Libnames.is_dirpath_prefix_of d dp) domains

let members_of_domains domains =
  let env = Global.env () in
  let consts =
    Environ.fold_constants
      (fun c _ acc ->
        let gr = GlobRef.ConstRef c in
        if in_domain domains gr then gr :: acc else acc)
      env []
  in
  let inds =
    Environ.fold_inductives
      (fun mind _ acc ->
        let gr = GlobRef.IndRef (mind, 0) in
        if in_domain domains gr then gr :: acc else acc)
      env []
  in
  consts @ inds
