# AGENTS.md

## Project

`go-mod-ts-extras-mode` adds pkg.go.dev integration to `go-mod-ts-mode` buffers.
The `;;; Commentary:` header in `go-mod-ts-extras-mode.el` holds the feature list.

## Commands

Run the ERT suite:

```sh
emacs --batch -L . \
  -l go-mod-ts-extras-mode-tests.el \
  -f ert-run-tests-batch-and-exit
```

Build through Nix.
The `checkPhase` runs ERT:

```sh
nix build
```

Some tests need the `gomod` grammar.
These tests skip themselves when the grammar is absent.
Supply the grammar through `treesit-grammars.with-all-grammars` or an equivalent method before you run the full suite.

## Conventions

- Prefix all public symbols with `go-mod-ts-extras-`.
- Prefix internal helpers with `go-mod-ts-extras--`.
- Use `cl-lib` functions (`cl-loop`, `cl-letf`, etc.).
  Do not use the deprecated `cl` counterparts.
- Keep the package free of external runtime dependencies beyond Emacs itself.
- After a user-visible behavior change, keep the `flake.nix` metadata (`version`, `description`, `license`) in sync with the package headers.

## Behavioral invariants

- `thing-at-point` for `url` must return `nil` for the `module` directive path.
  It must also return `nil` for the original (left-hand) module path of a `replace` spec.
- A `replace` spec resolves to the replacement path and its version.
  A `replace` spec never resolves to the original version.
- `GOPRIVATE` matching follows Go `path.Match` semantics.
  The `*` wildcard does not match `/`.
- If `GOMODCACHE` is set, it overrides the default module-cache prefix.
  The override does not apply when `go-mod-ts-extras-pkg-file-prefix` has an explicit value.
