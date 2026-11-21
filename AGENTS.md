# AGENTS.md — go-mod-ts-extras-mode

## Purpose

`go-mod-ts-extras-mode`: Emacs minor mode that adds pkg.go.dev integration to
`go-mod-ts-mode` buffers. Emacs 30.1 or newer. License: AGPL-3.0-or-later. The
`;;; Commentary:` header in `go-mod-ts-extras-mode.el` holds the feature list.

## Layout

- `go-mod-ts-extras-mode.el` — the mode.
- `test/go-mod-ts-extras-mode-test.el` — ERT suite.
- `flake.nix` — `melpaBuild` package, ERT checkPhase, lint and treefmt checks,
  devShell.

## Build and test

- `nix flake check` — the gate.
- `nix build` — the package.
- `nix fmt` — format the repo.
- `emacs --batch -L . -L test -l test/go-mod-ts-extras-mode-test.el -f
  ert-run-tests-batch-and-exit` — run the suite by hand.

Some tests need the `gomod` grammar and skip themselves when it is absent. The
Nix checkPhase puts the grammar on `treesit-extra-load-path`. For a manual run,
supply it through `treesit-grammars.with-all-grammars` or an equivalent method.

## Rules

- `thing-at-point` for `url` returns nil for the `module` directive path, and nil
  for the original left-hand module path of a `replace` spec.
- A `replace` spec resolves to the replacement path and its version. It never
  resolves to the original version.
- `GOPRIVATE` matching follows Go `path.Match` semantics. The `*` wildcard does
  not match `/`.
- When set, `GOMODCACHE` overrides the default module-cache prefix. The override
  does not apply when `go-mod-ts-extras-pkg-file-prefix` holds an explicit value.
- Keep the package free of external runtime dependencies beyond Emacs itself.
- Keep `test/<unit>-test.el` free of `Package-Requires`. The lint check sets
  `package-lint-main-file` instead.
- After a user-visible behaviour change, keep the `flake.nix` metadata
  (`description`, `license`) in sync with the package headers.
- Keep the `;; Version:` header at the upstream value. `flake.nix` appends
  `-unstable-<YYYY-MM-DD>` to it, because upstream holds no release yet. The date
  comes from the flake source info, so never hardcode it.
- Expose no `apps.default`. The package is an Elisp library with no executable.

## Conventions

- Prefix public symbols with `go-mod-ts-extras-` and internal helpers with
  `go-mod-ts-extras--`.
- Use `cl-lib` functions (`cl-loop`, `cl-letf`, and the rest). Do not use the
  deprecated `cl` counterparts.
- Put tests in `test/`, one file per source unit, named `<unit>-test.el`. Shared
  helpers stay in the test file or in `test/<name>-test-helper.el`. Name every
  `ert-deftest` with the `go-mod-ts-extras-` prefix.
