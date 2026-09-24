(** [ensure_required dp] makes [dp] loaded, as if by a bare [Require dp]
    (never [Import]) -- so its members become visible to
    {!Domain_scan.members_of_domains}, without binding any short names into
    the ambient namespace. This is what makes it safe to name a domain that
    isn't imported yet: [Require] alone never touches short-name
    visibility (confirmed against Rocq's own [vernac_require_interp], which
    only binds short names as a separate, conditional [Import] step this
    function never takes).

    A no-op if [dp] is already loaded. Also a no-op (deliberately, not an
    error) if [dp] can't be located as an exact compiled library -- domain
    arguments have always been allowed to be namespace prefixes with no
    compiled unit of their own (e.g. plain [MyDev] matching both
    [MyDev.PartA] and [MyDev.PartB]), and only an exact dirpath can be
    [Require]d. This does mean a genuine typo of an exact hypothetical
    domain degrades to the same "0 members" result an ordinary unmatched
    domain always gave, rather than a loud error -- not distinguishable in
    general from "this was always meant as a prefix". *)
val ensure_required : Names.DirPath.t -> unit

(** [loaded_by_tool dp]: whether [dp] lies under a library that
    {!ensure_required} itself loaded (the domain or any not-yet-loaded
    dependency of it), rather than one the analyzed file loaded on its own.
    Used to keep this tool's own side effects out of use-site judgments
    (see {!Glob_capture}). *)
val loaded_by_tool : Names.DirPath.t -> bool
