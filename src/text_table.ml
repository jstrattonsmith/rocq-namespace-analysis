type entry = {
  text : string;
  emphasized : bool;
}

type row = {
  label : string;
  entries : entry list;
}

let plain_marker = " <- used"

let box_h = "\xe2\x94\x80" (* ─ *)
let box_v = "\xe2\x94\x82" (* │ *)
let box_tl = "\xe2\x94\x8c" (* ┌ *)
let box_tr = "\xe2\x94\x90" (* ┐ *)
let box_bl = "\xe2\x94\x94" (* └ *)
let box_br = "\xe2\x94\x98" (* ┘ *)
let box_t = "\xe2\x94\xac" (* ┬ *)
let box_b = "\xe2\x94\xb4" (* ┴ *)
let box_l = "\xe2\x94\x9c" (* ├ *)
let box_r = "\xe2\x94\xa4" (* ┤ *)
let box_x = "\xe2\x94\xbc" (* ┼ *)

let ansi_on = "\x1b[1;36m"
let ansi_off = "\x1b[0m"

let rep s n = String.concat "" (List.init (max 0 n) (fun _ -> s))

let pad s w = s ^ String.make (max 0 (w - String.length s)) ' '

let col_widths ~headers rows =
  let h1, h2 = headers in
  let w1 = List.fold_left (fun acc r -> max acc (String.length r.label)) (String.length h1) rows in
  let w2 =
    List.fold_left
      (fun acc r -> List.fold_left (fun acc e -> max acc (String.length e.text)) acc r.entries)
      (String.length h2) rows
  in
  (w1, w2)

let hline l m r w1 w2 = l ^ rep box_h (w1 + 2) ^ m ^ rep box_h (w2 + 2) ^ r

type physical_line = {
  col1 : string;
  col2_text : string;
  col2_emphasized : bool;
}

(* One inner list per [row]: first physical line carries the label, any
   further entries continue on blank-label lines. A row separator is drawn
   between blocks, never inside one. *)
let to_blocks rows =
  List.map
    (fun row ->
      match row.entries with
      | [] -> [ { col1 = row.label; col2_text = ""; col2_emphasized = false } ]
      | first :: rest ->
        { col1 = row.label; col2_text = first.text; col2_emphasized = first.emphasized }
        :: List.map
             (fun (e : entry) -> { col1 = ""; col2_text = e.text; col2_emphasized = e.emphasized })
             rest)
    rows

let render_string ~ansi ~headers rows =
  let w1, w2 = col_widths ~headers rows in
  let h1, h2 = headers in
  let buf = Buffer.create 256 in
  let line s =
    if Buffer.length buf > 0 then Buffer.add_char buf '\n';
    Buffer.add_string buf s
  in
  line (hline box_tl box_t box_tr w1 w2);
  line (box_v ^ " " ^ pad h1 w1 ^ " " ^ box_v ^ " " ^ pad h2 w2 ^ " " ^ box_v);
  line (hline box_l box_x box_r w1 w2);
  List.iteri
    (fun i block ->
      if i > 0 then line (hline box_l box_x box_r w1 w2);
      List.iter
        (fun (l : physical_line) ->
          let col2 =
            if l.col2_emphasized && ansi then
              ansi_on ^ l.col2_text ^ ansi_off
              ^ String.make (max 0 (w2 - String.length l.col2_text)) ' '
            else pad l.col2_text w2
          in
          line (box_v ^ " " ^ pad l.col1 w1 ^ " " ^ box_v ^ " " ^ col2 ^ " " ^ box_v))
        block)
    (to_blocks rows);
  line (hline box_bl box_b box_br w1 w2);
  Buffer.contents buf

let render_pp ~headers rows =
  let open Pp in
  let w1, w2 = col_widths ~headers rows in
  let h1, h2 = headers in
  let hline_pp l m r = str (hline l m r w1 w2) in
  let header_line =
    str box_v ++ str " " ++ str (pad h1 w1) ++ str " " ++ str box_v ++ str " "
    ++ str (pad h2 w2) ++ str " " ++ str box_v
  in
  let block_pp block =
    prlist_with_sep fnl
      (fun (l : physical_line) ->
        let col2_plain = pad l.col2_text w2 in
        let col2 =
          if l.col2_emphasized then tag "namespaceanalysis.used" (str col2_plain)
          else str col2_plain
        in
        str box_v ++ str " " ++ str (pad l.col1 w1) ++ str " " ++ str box_v ++ str " " ++ col2
        ++ str " " ++ str box_v)
      block
  in
  let body =
    List.mapi
      (fun i block -> (if i > 0 then hline_pp box_l box_x box_r ++ fnl () else mt ()) ++ block_pp block)
      (to_blocks rows)
  in
  v 0 (
    hline_pp box_tl box_t box_tr ++ fnl ()
    ++ header_line ++ fnl ()
    ++ hline_pp box_l box_x box_r ++ fnl ()
    ++ prlist_with_sep fnl (fun x -> x) body ++ fnl ()
    ++ hline_pp box_bl box_b box_br
  )
