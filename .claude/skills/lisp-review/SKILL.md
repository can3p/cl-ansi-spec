---
name: lisp-review
description: Pre-commit quality gate for this repository — run the build/test gate, then a sub-agent code review of the diff with the project-specific checklist below. Use before every commit.
---

# Lisp review gate

1. `make test 2>&1 | tail -5` must exit 0 (any compiler warning fails the build).
2. `(cd spec/tex && sha256sum -c --quiet ../SHA256SUMS)` must pass: `spec/tex/` is never edited.
3. Spawn a review sub-agent (a mid-size model is enough) on `git diff` / new
   files, excluding `spec/tex/`. Give it the diff command and
   `docs/architecture.md`; it reads only the diff, the files the diff touches
   (by line range), and the docs the step names. Ask for a ranked list (bug /
   should-fix / nit) with file:line and a concrete fix, under 400 words, no
   file modifications, using the checklist below.
4. Fix bugs and should-fixes; deliberately skipped items go in the commit message.

## Checklist for reviewers (grown from past findings)

- **End goal** (`docs/architecture.md`): the change serves the semantic
  model. It keeps source spans and meaning, adds no typesetting emulation,
  and its output matches the documented interface of the next phase.
- **Composability**: code sits in the package of its phase. It uses only
  exported symbols of lower phases and never reaches upward. Each file has
  one job and a header; functions are small and named for what they do.
  State is passed explicitly, and specials are documented. Extension goes
  through the documented tables and protocols (resolver, primitive table,
  vocabulary), not through special cases scattered across the code. New
  code can be tested without running the whole pipeline.
- **Docs in step**: the docs the step names, `docs/architecture.md` and
  `AGENTS.md` describe the code as it now is, as current rules with no
  history.

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
