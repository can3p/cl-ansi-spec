# Plan

The index of planned work. **A session reads this file, `docs/architecture.md`
and the one milestone file it works on — nothing else up front.** How a step
and a milestone advance is in `docs/process.md`.

Goal: a semantic model of the standard, parsed from `spec/tex/`
(`docs/architecture.md`).

## Status

- Current: **M2 — Expander and semantic layer** (first unticked step) —
  [`docs/plan/m2.md`](docs/plan/m2.md).
- Done: M0 (scaffold), M1 (TeX reader) — [`docs/history/m0-m1.md`](docs/history/m0-m1.md).

## Milestones

A milestone gets its own file `docs/plan/<id>.md` (steps, order, docs each
step updates) when it is planned; the file is deleted when the milestone
closes and its history goes to `docs/history/`.  Not yet planned in detail:

### M3 — Semantic document model
A documented schema (Lisp classes) for the standard: chapters and
sections (numbered, labelled), glossary entries, dictionary entries (names,
kind, `\label` sections such as Syntax, Arguments and Values, Description,
Examples, Affected By, Exceptional Situations, See Also, Notes, ...),
figures and tables, BNF/syntax, issues (ranges over content), editor
notes; inline content as a small tree of semantic nodes.  Built from the
M2 event streams of all jobs.  Tables of contents and figure lists come
from section and figure events (not from `\write`s, which the options
gate and which carry `\pagenumber`).  The cross-reference graph is
resolved: section and figure references from `\Define*` events (not from
the stale generated `setup-sections.tex`/`setup-figures.tex`), operator
references to entries, `\term` uses to glossary entries with explicit,
tested inflection rules (plurals, "-ing", ...); everything unresolved is
reported.  **Exports** per `docs/exports.md`.

First steps, before the model builder, so that the builder is written
against them:

- node declarations (`define-node`) with documentation of every node kind,
  field and enum value (`docs/exports.md`);
- the model classes, the JSON Schema and `docs/model-reference.md`
  generated from them; `make test` fails if they are stale or if any
  description or example is missing;
- the Lisp validator for the emitted schema subset.

Later steps: the S-expression and JSON writers, `manifest.json`,
`report.json`, validation of the whole spec's exports (plus an external
validator as a CI-only cross-check), and `docs/consuming.md` with a
sample export.

### M4 — Patch tooling
Apply `patches/*.patch` in order onto a copy of `spec/tex/`, in Lisp.
First patch: concept-syntax.tex:271-278, the commented-out definitions
of the syntax-type table's abbreviations (`docs/tex-fidelity.md`, "Jobs").

### M5 — Consumers
An HTML site (our own HyperSpec-like rendering, nothing borrowed from the
HyperSpec) generated from the model and deployed to GitHub Pages; the
exports, the JSON Schema and the sample export
published alongside it.

## Open questions

- (none)
