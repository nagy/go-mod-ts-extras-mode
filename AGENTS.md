# AGENTS.md

Guidance for automated agents and contributors working in this repository.

## Project

`go-mod-ts-extras-mode` is an Emacs Lisp minor mode that enhances
`go-mod-ts-mode` buffers with pkg.go.dev integration:

- `thing-at-point` for `url` returns the pkg.go.dev URL for a module path
  in a `require` or `replace` spec.
- `thing-at-point` for `filename` returns the local module cache path for
  the module under point.
- Module paths in `require` and `replace` specs are underlined through a
  tree-sitter font-lock rule.
- `go-mod-ts-extras-browse-at-point` opens the resolved pkg.go.dev URL.

The package targets Emacs 30.1 and relies on the built-in `go-ts-mode`
and the `gomod` tree-sitter grammar.

## Repository layout

- `go-mod-ts-extras-mode.el` — the package implementation.
- `go-mod-ts-extras-mode-tests.el` — ERT test suite.
- `default.nix` — Nix build with `melpaBuild` and a `checkPhase` running ERT.
- `LICENSE` — GNU AGPL-3.0-or-later.

## Commands

Run the ERT suite:

```sh
emacs --batch -L . \
  -l go-mod-ts-extras-mode-tests.el \
  -f ert-run-tests-batch-and-exit
```

Build through Nix (also runs the check phase):

```sh
nix-build
```

Tests that need the `gomod` grammar skip themselves when it is not
available; provide the grammar through
`treesit-grammars.with-all-grammars` or equivalent before running the
full suite.

## Conventions

- All public symbols use the `go-mod-ts-extras-` prefix.
- Internal helpers use the double dash: `go-mod-ts-extras--`.
- Use `cl-lib` functions (`cl-loop`, `cl-letf`, etc.), not their
  deprecated `cl` counterparts.
- Source and test files start with `lexical-binding: t`.
- Preserve the existing ERT style: `skip-unless (treesit-ready-p 'gomod)`
  guards grammar-dependent tests, temporary buffers use
  `generate-new-buffer`, and cleanup uses `unwind-protect`.
- Keep the package free of external runtime dependencies beyond Emacs
  itself.
- Keep `default.nix` metadata (`version`, `description`, `license`) in
  sync with the package headers and any user-visible behavior changes.

## Behavioral invariants

- `thing-at-point` for `url` must return `nil` for the `module` directive
  path and for the original (left-hand) module path of a `replace` spec.
- A `replace` spec resolves to the replacement path and its version,
  never the original version.
- `GOPRIVATE` matching follows Go `path.Match` semantics: `*` does not
  match `/`.
- When `GOMODCACHE` is set, it overrides the default module-cache prefix
  unless `go-mod-ts-extras-pkg-file-prefix` is explicitly configured.
