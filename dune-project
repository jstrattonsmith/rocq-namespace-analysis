(lang dune 3.23)
(using rocq 0.13)

(package
 (name rocq-import-analysis)
 (synopsis "Reports where imported identifiers are defined and flags name clashes across Require/Import")
 (depends
  (rocq-runtime (>= 9.0))
  (rocq-stdlib (>= 9.0))))
