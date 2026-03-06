val version : string
(** Version of the library, e.g. ["0.12"]. ["dev"] if not built from a release
    tag. *)

val git_hash : string
(** Full git commit hash at build time, e.g. ["b92159c1..."]. ["unknown"] if git
    was unavailable. *)
