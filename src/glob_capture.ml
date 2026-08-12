type occurrence = {
  loc : Loc.t;
  filepath : string;
  modpath : string;
  ident : string;
  kind : string;
}

let buffer : occurrence list ref = ref []
let feeder_id : int option ref = ref None

let handle_feedback (fb : Feedback.feedback) =
  match fb.Feedback.contents with
  | Feedback.GlobRef (loc, filepath, modpath, ident, kind) ->
    buffer := { loc; filepath; modpath; ident; kind } :: !buffer
  | _ -> ()

let install () =
  if !feeder_id = None then begin
    Dumpglob.push_output Dumpglob.Feedback;
    feeder_id := Some (Feedback.add_feeder handle_feedback)
  end

let occurrences () = List.rev !buffer

let reset () = buffer := []
