(** Captures every identifier the elaborator resolves after [install] is
    called, by hijacking Rocq's [.glob]-file generation machinery
    ([Dumpglob]) to deliver its records in-memory via [Feedback] instead of
    writing them to disk. This is the same data [coqdoc] cross-referencing
    is built from.

    Each record is also judged {e at its use site}: [Feedback] delivers it
    synchronously, while the command using the name is still being
    elaborated, so [Nametab] at that moment is exactly the namespace the
    name was resolved against -- including a [Section]/[Module]-scoped
    [Import] that is gone again by the end of the file, and a later
    [Import] that would change what the same name means further down.

    Caveat: this pushes [Dumpglob.Feedback] as the active glob-output mode,
    which shadows any real [-dump-glob] file output for the remainder of
    the compilation unit. Only call [install] in contexts where that
    trade-off is acceptable (e.g. this plugin's own analysis commands). *)

(** One candidate a name could have referred to, captured while it was
    still in scope (its [Nametab] path may not survive to report time,
    e.g. once its section or module is closed). *)
type candidate = {
  path : string;  (** fully qualified name *)
  dirpath : Names.DirPath.t;  (** for excluded-prefix filtering *)
  local : bool;  (** declared [Local]; see [Report] *)
  status : Import_status.t option;
      (** for an alternative (not the winner, not [Local]): whether its
          module was imported at the use site -- [Imported] means it was
          reachable by that name and lost ("last import wins"),
          [Not_imported] that it's only loaded (latent). *)
}

(** What the name, as written, could have meant at the moment it was used.
    Only recorded when there was more than one candidate. *)
type use_site = {
  written : string;  (** the reference as it appears in the source *)
  winner : candidate;  (** what [Nametab] resolved it to then *)
  others : candidate list;
      (** every other loaded global sharing that written (partial) name --
          mirrors [Locate]: this includes candidates whose module was only
          [Require]d, not [Import]ed; each one's [status] tells them apart
          (approximately -- see {!Import_status}). Libraries loaded by
          this tool itself (see {!Ensure_loaded.loaded_by_tool}) are left
          out. *)
}

type occurrence = {
  loc : Loc.t;
  filepath : string;
  modpath : string;
  ident : string;
  kind : string;
  use_site : use_site option;
}

(** Starts capturing. Idempotent: calling it more than once has no
    additional effect. *)
val install : unit -> unit

(** All identifier references captured so far, oldest first. *)
val occurrences : unit -> occurrence list

(** Clears the captured buffer without stopping capture. *)
val reset : unit -> unit
