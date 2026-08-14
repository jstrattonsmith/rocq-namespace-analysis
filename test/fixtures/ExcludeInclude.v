From NamespaceAnalysis Require Import Loader.
From ExcludeDemo Require Import CorelibClash.

Check double 3.

NamespaceAnalysis ExcludeDemo.CorelibClash.
NamespaceAnalysis ExcludeDemo.CorelibClash : Including Corelib.
