open Names

let fold_globals f acc =
  let env = Global.env () in
  let acc = Environ.fold_constants (fun c _ acc -> f (GlobRef.ConstRef c) acc) env acc in
  Environ.fold_inductives
    (fun mind mib acc ->
      let acc = ref acc in
      Array.iteri
        (fun i pkt ->
          acc := f (GlobRef.IndRef (mind, i)) !acc;
          let n = Array.length pkt.Declarations.mind_consnames in
          for j = 1 to n do
            acc := f (GlobRef.ConstructRef ((mind, i), j)) !acc
          done)
        mib.Declarations.mind_packets;
      !acc)
    env acc

let in_domain domains gr =
  let dp = Nametab.dirpath_of_global gr in
  List.exists (fun d -> Libnames.is_dirpath_prefix_of d dp) domains

let members_of_domains domains =
  fold_globals (fun gr acc -> if in_domain domains gr then gr :: acc else acc) []
