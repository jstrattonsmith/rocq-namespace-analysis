open Names

(** [members_of_domains domains] returns every constant, inductive type, and
    constructor loaded into the current environment whose fully-qualified
    name starts with one of the given [domains] prefixes. Mirrors what [Print
    Namespace] reports: this reflects everything *loaded* (via [Require]),
    not just what is currently visible under a short name (via [Import]).

    Every type in a mutual inductive block is walked, not just the first
    ([Inductive A := ... with B := ...] yields members for both [A] and
    [B]), and every constructor of every such type is walked too (so two
    libraries each defining a constructor named e.g. [Ok] or [Node] will be
    seen as members and can be flagged as a clash). *)
val members_of_domains : DirPath.t list -> GlobRef.t list
