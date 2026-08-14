{
  description = "NamespaceAnalysis: Rocq import/clash analyzer";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        rocq = pkgs.rocqPackages_9_1.rocq-core;
        ocamlPackages = rocq.passthru.ocamlPackages;
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            rocq
            pkgs.dune_3
            ocamlPackages.ocaml
            ocamlPackages.findlib
            ocamlPackages.zarith
          ];

          # Once `dune build` has run, this project's own plugin/CLI output
          # lands in _build/install/default/lib, which findlib doesn't know
          # about by default (it's local, not a Nix dependency). Wiring it
          # into OCAMLPATH here means `Declare ML Module` and the CLI work
          # immediately after `dune build`, with no manual export.
          shellHook = ''
            export OCAMLPATH="$PWD/_build/install/default/lib''${OCAMLPATH:+:}$OCAMLPATH"
          '';
        };
      }
    );
}
