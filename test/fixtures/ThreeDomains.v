From NamespaceAnalysis Require Import Loader.
From LibOne Require Import Mod.
From LibTwo Require Import Mod.
From LibThree Require Import Mod.

Check Shared.

NamespaceAnalysis.
NamespaceAnalysis LibOne.Mod.
NamespaceAnalysis LibOne.Mod LibTwo.Mod.
NamespaceAnalysis LibOne.Mod LibTwo.Mod LibThree.Mod.
