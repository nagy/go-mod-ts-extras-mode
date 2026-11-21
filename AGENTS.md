# AGENTS.md

## Project

`go-mod-ts-extras-mode` adds pkg.go.dev integration to `go-mod-ts-mode` buffers.
The `;;; Commentary:` header in `go-mod-ts-extras-mode.el` holds the feature list.

## Commands

Run the ERT suite:

```sh
emacs --batch -L . -L test \
  -l test/go-mod-ts-extras-mode-test.el \
  -f ert-run-tests-batch-and-exit
```

Build through Nix.
The `checkPhase` runs ERT over `test/*-test.el`:

```sh
nix build
```

```sh
nix flake check
```

`nix flake check` runs the `lint` check (package-lint + checkdoc) and the
`treefmt` check.
The lint check covers the root files and `test/*.el`.

Format the repo:

```sh
nix fmt
```

Some tests need the `gomod` grammar.
These tests skip themselves when the grammar is absent.
The Nix `checkPhase` puts the grammar on `treesit-extra-load-path` for you.
For a manual run, supply the grammar through `treesit-grammars.with-all-grammars` or an equivalent method.

## Conventions

- Prefix all public symbols with `go-mod-ts-extras-`.
- Prefix internal helpers with `go-mod-ts-extras--`.
- Use `cl-lib` functions (`cl-loop`, `cl-letf`, etc.).
  Do not use the deprecated `cl` counterparts.
- Keep the package free of external runtime dependencies beyond Emacs itself.
- Put tests in `test/`, one file per source unit, named `<unit>-test.el`.
  Shared helpers stay in the test file or in `test/<name>-test-helper.el`.
  Name every `ert-deftest` with the `go-mod-ts-extras-` prefix.
- Keep `test/<unit>-test.el` free of `Package-Requires`.
  The lint check sets `package-lint-main-file` instead.
- After a user-visible behavior change, keep the `flake.nix` metadata (`description`, `license`) in sync with the package headers.
- Keep the `;; Version:` header at the upstream value.
  `flake.nix` appends `-unstable-<YYYY-MM-DD>` to it, because upstream has no release yet.
  The date comes from the flake source info, so do not hardcode it.
- Expose no `apps.default`.
  The package is an Elisp library, so it has no executable.

## Behavioral invariants

- `thing-at-point` for `url` must return `nil` for the `module` directive path.
  It must also return `nil` for the original (left-hand) module path of a `replace` spec.
- A `replace` spec resolves to the replacement path and its version.
  A `replace` spec never resolves to the original version.
- `GOPRIVATE` matching follows Go `path.Match` semantics.
  The `*` wildcard does not match `/`.
- If `GOMODCACHE` is set, it overrides the default module-cache prefix.
  The override does not apply when `go-mod-ts-extras-pkg-file-prefix` has an explicit value.
