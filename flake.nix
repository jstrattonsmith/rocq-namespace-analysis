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

        # Once `dune build` has run, this project's own plugin/CLI output
        # lands in _build/install/default/lib, which findlib doesn't know
        # about by default (it's local, not a Nix dependency). Wiring it
        # into OCAMLPATH here means `Declare ML Module` and the CLI work
        # immediately after `dune build`, with no manual export. Shared by
        # every devShell below -- editor tooling needs this exactly as much
        # as the CLI/tests do.
        ocamlpathHook = ''
          export OCAMLPATH="$PWD/_build/install/default/lib''${OCAMLPATH:+:}$OCAMLPATH"
        '';

        corePackages = [
          rocq
          pkgs.dune_3
          ocamlPackages.ocaml
          ocamlPackages.findlib
          ocamlPackages.zarith
          ocamlPackages.odoc
          # Editor tooling (VsRocq's language server) folded into the one
          # shared shell rather than split into a separate `.#editor`
          # output -- this is a private, single-maintainer project, not a
          # shared team repo where closure-size discipline for occasional
          # CLI/test sessions is worth the extra "which shell do I use"
          # friction. Confirmed via the nixpkgs binary cache that this adds
          # fetch time, not build time (no from-source builds triggered).
          pkgs.rocqPackages_9_1.vsrocq-language-server
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          packages = corePackages;
          shellHook = ocamlpathHook;
        };
      }
    );
}
