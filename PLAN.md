# Plan

The index of planned work. **A session reads this file, `docs/architecture.md`
and the one milestone file it works on — nothing else up front.** How a step
and a milestone advance is in `docs/process.md`.

Goal: a semantic model of the standard, parsed from `spec/tex/`
(`docs/architecture.md`).

## Status

- Current, in parallel waves (`docs/process.md`, "Parallel waves"):
  **M3 — Semantic document model** (`docs/plan/m3.md`, its wave table
  says which steps can run now).
- Done: M0 (scaffold), M1 (TeX reader) — [`docs/history/m0-m1.md`](docs/history/m0-m1.md);
  M2 (expander and semantic layer) — [`docs/history/m2.md`](docs/history/m2.md);
  M4 (patch tooling) — [`docs/history/m4.md`](docs/history/m4.md).

## Milestones

A milestone gets its own file `docs/plan/<id>.md` (steps, order, docs each
step updates) when it is planned; the file is deleted when the milestone
closes and its history goes to `docs/history/`.  Not yet planned in detail:
M5.

### M3 — Semantic document model
Planned: `docs/plan/m3.md`.

### M5 — Consumers
An HTML site (our own HyperSpec-like rendering, nothing borrowed from the
HyperSpec) generated from the model and deployed to GitHub Pages; the
exports, the JSON Schema and the sample export
published alongside it.

## Open questions

- (none; the table-in-cell question went to a patch: 3.19p follow-up, #44)
