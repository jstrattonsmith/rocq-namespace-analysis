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
  let inds, constructs =
    Environ.fold_inductives
      (fun mind mib (inds_acc, constrs_acc) ->
        let inds_acc = ref inds_acc and constrs_acc = ref constrs_acc in
        Array.iteri
          (fun i pkt ->
            let ind_gr = GlobRef.IndRef (mind, i) in
            if in_domain domains ind_gr then inds_acc := ind_gr :: !inds_acc;
            let n = Array.length pkt.Declarations.mind_consnames in
            for j = 1 to n do
              let gr = GlobRef.ConstructRef ((mind, i), j) in
              if in_domain domains gr then constrs_acc := gr :: !constrs_acc
            done)
          mib.Declarations.mind_packets;
        (!inds_acc, !constrs_acc))
      env ([], [])
  in
  consts @ inds @ constructs
