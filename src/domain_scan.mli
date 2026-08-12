open Names

(** [members_of_domains domains] returns every constant and inductive type
    loaded into the current environment whose fully-qualified name starts
    with one of the given [domains] prefixes. Mirrors what [Print Namespace]
    reports: this reflects everything *loaded* (via [Require]), not just
    what is currently visible under a short name (via [Import]). *)
val members_of_domains : DirPath.t list -> GlobRef.t list
