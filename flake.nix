{
  description = "pkg.go.dev extras for go-mod-ts-mode (Emacs package)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        {
          system,
          pkgs,
          lib,
          config,
          ...
        }:
        let
          inherit (pkgs.emacsPackages) melpaBuild;
          # The gomod grammar must be present for font-lock and for the
          # grammar-dependent ERT tests to run.
          treesitGrammars = pkgs.emacsPackages.treesit-grammars.with-all-grammars;
        in
        {
          packages.go-mod-ts-extras-mode = melpaBuild {
            pname = "go-mod-ts-extras-mode";
            # Matches the ;; Version: header in go-mod-ts-extras-mode.el.
            version = "0.1.0";

            src = lib.cleanSource ./.;

            # Elisp dependencies: only the gomod tree-sitter grammar,
            # everything else ships with Emacs 30.1 itself.
            packageRequires = [ treesitGrammars ];

            # Byte-compilation warnings fail the build. Keep it on: it is
            # the cheapest lint the package will ever get.
            turnCompilationWarningToError = true;

            doCheck = true;
            checkPhase = ''
              runHook preCheck
              emacs --batch -L . \
                -l go-mod-ts-extras-mode-tests.el \
                -f ert-run-tests-batch-and-exit
              runHook postCheck
            '';

            meta = {
              description = "pkg.go.dev extras for go-mod-ts-mode";
              longDescription = ''
                A minor mode that enhances go-mod-ts-mode buffers with
                pkg.go.dev URL detection and browsing.  Module paths inside
                require and replace directives are underlined, thing-at-point
                returns their pkg.go.dev URLs, and
                `go-mod-ts-extras-browse-at-point' opens them in a browser.
              '';
              license = lib.licenses.agpl3Plus;
              homepage = "https://github.com/nagy/go-mod-ts-extras-mode";
              maintainers = with lib.maintainers; [ nagy ];
              platforms = lib.platforms.unix;
            };
          };

          packages.default = config.packages.go-mod-ts-extras-mode;

          devShells.default = pkgs.mkShell {
            # A real Emacs for interactive testing, with the gomod grammar
            # on the tree-sitter search path so font-lock and ERT work.
            packages = [
              (pkgs.emacs.pkgs.withPackages [ treesitGrammars ])
            ];
          };
        };
    };
}
