open Names

type clash = {
  name : Id.t;
  winner : GlobRef.t;  (** what the short name currently resolves to *)
  alternatives : GlobRef.t list;  (** every other visible candidate *)
}

(** [find_clashes members] probes the (deduplicated) short names of
    [members] against the current naming table and reports every name with
    more than one visible candidate. Note: the candidate set for a probed
    name is NOT restricted to [members] or to any particular domain -- a
    name is reported as a clash if it is ambiguous anywhere in the current
    scope, even against something outside the probed domain(s). This
    mirrors how [Locate] itself behaves. *)
val find_clashes : GlobRef.t list -> clash list
