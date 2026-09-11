(** Captures every identifier the elaborator resolves after [install] is
    called, by hijacking Rocq's [.glob]-file generation machinery
    ([Dumpglob]) to deliver its records in-memory via [Feedback] instead of
    writing them to disk. This is the same data [coqdoc] cross-referencing
    is built from.

    Caveat: this pushes [Dumpglob.Feedback] as the active glob-output mode,
    which shadows any real [-dump-glob] file output for the remainder of
    the compilation unit. Only call [install] in contexts where that
    trade-off is acceptable (e.g. this plugin's own analysis commands). *)

type occurrence = {
  loc : Loc.t;
  filepath : string;
  modpath : string;
  ident : string;
  kind : string;
}

(** Starts capturing. Idempotent: calling it more than once has no
    additional effect. *)
val install : unit -> unit

(** All identifier references captured so far, oldest first. *)
val occurrences : unit -> occurrence list

(** Clears the captured buffer without stopping capture. *)
val reset : unit -> unit
