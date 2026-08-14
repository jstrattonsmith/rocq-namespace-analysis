(** A small two-column grid renderer, shared by every report section that
    needs one (Clashes, Used identifiers). Deliberately generic: it knows
    nothing about clashes or domains, just rows/entries/emphasis. *)

type entry = {
  text : string;
  emphasized : bool;
      (** Gets a color/bold treatment where the renderer supports it. Never
          rely on this alone to convey meaning -- callers should already
          have baked a plain-text marker (see {!plain_marker}) into [text]
          for anything the emphasis is meant to signal, since emphasis is a
          pure enhancement layered on top, not the only signal. *)
}

type row = {
  label : string;  (** Column 1, shown once per row (first line only). *)
  entries : entry list;
      (** Column 2, one line per entry, non-empty. Caller is responsible
          for sort order (e.g. alphabetical). *)
}

val plain_marker : string
(** A short, always-visible suffix (e.g. [" <- used"]) callers can append to
    an emphasized entry's [text] so it's identifiable even with zero color
    support (piped output, an IDE panel that ignores the [Pp] tag below). *)

val render_pp : headers:string * string -> row list -> Pp.t
(** Renders as Unicode box-drawing table. Emphasized entries are wrapped in
    [Pp.tag "namespaceanalysis.used"] -- a free-form tag string, a harmless
    no-op in any renderer/IDE that doesn't recognize it. *)

val render_string : ansi:bool -> headers:string * string -> row list -> string
(** Same table, as a plain string. When [ansi] is true (i.e. stdout is a
    TTY), emphasized entries additionally get bold+color ANSI codes; the
    grid's box-drawing characters and column alignment are identical either
    way. *)
