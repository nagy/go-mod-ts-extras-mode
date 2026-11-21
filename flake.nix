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
              # `melpaBuild' stages only the root-level files matched by
              # `files', so copy the test tree back into the build directory.
              cp -r ${./test} ./test
              # printf repeats "-l %s" per match.  failglob makes an empty
              # glob a shell error, so the || guard fires even without
              # `set -e'.  Restore the default right after: later commands
              # must keep default glob semantics.  The unquoted $test_args
              # is intentional: the words must split into -l <file> pairs,
              # which is safe because test file names never contain spaces.
              # A plain nullglob does not work here: printf with zero
              # arguments still emits the format and -n checks pass.
              shopt -s failglob
              test_args=$(printf -- "-l %s " test/*-test.el) || { echo 'no tests matched test/*-test.el' >&2; exit 1; }
              shopt -u failglob
              # The grammar package ships only the shared libraries in its
              # `lib' directory, so its load-path entry does nothing here.
              # Point `treesit-extra-load-path' at that directory, or every
              # grammar-dependent test skips itself and the check proves
              # nothing.
              emacs --batch -L . -L test \
                --eval "(setq treesit-extra-load-path (list \"${treesitGrammars}/lib\"))" \
                $test_args \
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

          checks.lint =
            pkgs.runCommand "go-mod-ts-extras-mode-lint"
              {
                nativeBuildInputs = [
                  (pkgs.emacsPackages.emacsWithPackages (p: [ p.package-lint ]))
                  # Gives Emacs a writable HOME, so the builder needs no
                  # `export HOME=$TMPDIR' line and no two checks share a home.
                  pkgs.writableTmpDirAsHomeHook
                ];
                src = config.packages.go-mod-ts-extras-mode.src;
              }
              ''
                # test/ is part of the lint surface.  `src' may be filtered by
                # cleanSource, so copy the tree explicitly instead of relying on
                # what melpaBuild staged.
                cp -r "$src"/. .
                # package-lint-main-file is mandatory: without it, package-lint
                # treats each test file as its own package and demands a
                # Package-Requires header.  The sane-prefix extension covers the
                # `go-mod-ts-extras-' prefix, which is shorter than the file name
                # suggests, so the gate stays on rather than being relaxed.
                emacs --batch -l package-lint \
                  --eval '(setq package-lint-main-file "go-mod-ts-extras-mode.el")' \
                  --eval '(setq package-lint--sane-prefixes (concat package-lint--sane-prefixes "\\|go-mod-ts-extras"))' \
                  -f package-lint-batch-and-exit \
                  *.el test/*.el
                # checkdoc exits 0 on findings, so gate on non-empty output.
                lint_log=$(emacs --batch -l checkdoc \
                  --eval '(setq checkdoc-arguments-in-order-flag t)' \
                  --eval '(mapc (lambda (f) (checkdoc-file f)) command-line-args-left)' \
                  *.el test/*.el 2>&1)
                if [ -n "$lint_log" ]; then printf '%s\n' "$lint_log"; exit 1; fi
                touch $out
              '';

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
