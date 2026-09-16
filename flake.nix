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
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          packages = corePackages;
          shellHook = ocamlpathHook;
        };

        # `nix develop .#editor` -- everything in devShells.default, plus
        # editor/language-server tooling for live/interactive testing (see
        # Editor_planning.md). Kept separate from devShells.default so the
        # CLI/test-suite path (and CI, which only ever needs the default
        # shell) doesn't pull in a heavier closure for tooling most sessions
        # never touch. To demo in VS Code: `nix develop .#editor`, then
        # `code .` from inside that shell so it inherits OCAMLPATH/PATH
        # (VS Code's own direnv integration is a fine alternative once
        # .envrc is pointed at this shell instead of the default one, but
        # isn't required).
        devShells.editor = pkgs.mkShell {
          packages = corePackages ++ [ pkgs.rocqPackages_9_1.vsrocq-language-server ];
          shellHook = ocamlpathHook;
        };
      }
    );
}
