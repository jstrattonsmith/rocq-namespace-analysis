(** A plugin/CLI-agnostic report: built once from live environment state,
    then rendered either for the proof/message panel ([to_pp], via
    [Feedback.msg_notice]) or for a terminal ([to_string]). Both front ends
    must render identical content. *)

type t = {
  member_count : int;
  clashes : Clash_detect.clash list;
  used : Glob_capture.occurrence list;
}

val make :
  member_count:int ->
  clashes:Clash_detect.clash list ->
  used:Glob_capture.occurrence list ->
  t

val to_pp : t -> Pp.t
val to_string : t -> string
