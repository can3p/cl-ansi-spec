---
name: lisp-review
description: Pre-commit quality gate for this repository — run the build/test gate, then a sub-agent code review of the diff with the project-specific checklist below. Use before every commit.
---

# Lisp review gate

1. `make test 2>&1 | tail -5` must exit 0 (any compiler warning fails the build).
2. `(cd spec/tex && sha256sum -c --quiet ../SHA256SUMS)` must pass: `spec/tex/` is never edited.
3. Spawn a review sub-agent (a mid-size model is enough) on `git diff` / new
   files, excluding `spec/tex/`. Ask for a ranked list (bug / should-fix / nit)
   with file:line and a concrete fix, under 400 words, no file modifications.
4. Fix bugs and should-fixes; deliberately skipped items go in the commit message.

## Checklist for reviewers (grown from past findings)

- **Reproducibility**: tools must ignore user/system ASDF config (source
  registry *and* output translations); deps pinned by commit in `tools/deps.sexp`.
- **Subprocesses**: never let `git` (or similar) discover an enclosing repo —
  pass `--git-dir`/`--work-tree` explicitly; set `GIT_TERMINAL_PROMPT=0`, `:input nil`.
- **Idempotency**: tools must recover from interrupted runs and work offline
  once inputs are local.
- **Pathnames**: reject wild names from user input (`wild-pathname-p`); use
  `uiop:directory-files` (not `directory`) to list files only.
- **No hard-coded facts duplicated from data**: derive expectations from the
  data's manifest (e.g. `spec/SHA256SUMS`), not magic numbers.
- **Tests**: exit status must reflect failure; verify by breaking a test once.
- **Idiom**: docstrings on public definitions, conditions for error cases,
  `:import-from` over `:use` for third-party packages.
- **Rare paths**: code paths the corpus barely exercises (e.g. `^^`
  rewriting inside control sequence names) need dedicated fixtures with
  exact expected values; a global property test is not enough.
- **Untrusted names**: file resolvers reject absolute and `..` names.
- **Make → Lisp**: pass user values as environment variables
  (`VAR='$(VAR)'`, read with `uiop:getenv`), never interpolated into argv.
- **Test expectations**: when a new test fails, re-derive the expectation
  from the TeX rules before touching the code (most M1 failures were
  wrong expectations, e.g. line ends after control words are skipped).
