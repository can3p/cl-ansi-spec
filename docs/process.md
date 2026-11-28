# Process

How work advances. A step is finished when the code, the tests **and the
docs** describe the same thing. It is not finished when the code lands.

## Documents and who reads them

| Document | Role | Read |
|----------|------|------|
| `AGENTS.md` | rules and commands | always (loaded automatically) |
| `PLAN.md` | index: current milestone and step; outline of later milestones | at session start |
| `docs/architecture.md` | end goal, phases, packages, example | at session start |
| `docs/plan/<id>.md` | the running milestone's steps, each naming the docs it updates | at session start, only the current milestone's file |
| `docs/<topic>.md` | design of one phase or interface (`reader`, `events`, `vocabulary`, `tex-fidelity`, `model`, `exports`) | when the step touches that topic |
| `docs/history/<id>.md` | what a finished milestone did and decided | never by default |

The docs state **current rules with their reasons**, never history.
Decisions go into the topic doc they govern. Where they came from goes into
the milestone's history file when it closes.

## Docs name what exists

`make test` checks it (`tests/docs.lisp`), so "docs up to date" is not just
a convention. In `AGENTS.md`, `PLAN.md`, `docs/*.md`, `docs/plan/<id>.md` and
`.claude/skills/*/SKILL.md`:

- every repository path in backticks exists. A path is a code span without
  spaces that starts with `docs/`, `src/`, `tests/`, `tools/`, `spec/`,
  `patches/`, `.github/`, `.claude/`, `vendor/` or `schema/` (planned), and may end in
  `:<line>` or `:<line>-<line>`. A glob (`*`) must match something.
  Placeholders (`<id>`, `…`) are not checked, and neither are bare file
  names, system names, export paths or command lines;
- every `make <target>` is a rule of the `Makefile`, wherever `make`
  appears in a code span.

Something not built yet is marked `(planned)` right after its closing
backtick, at every mention. In a milestone file, unticked `- [ ]` steps are
planned as a whole; so is the Milestones section of `PLAN.md`. Fenced code
blocks and `docs/history/` (the past) are not checked.

## A step

Each step in `docs/plan/<id>.md` names, besides its text and *Docs:*:
*Wave*, *After* (steps that must be merged first), *Owns* (when not
obvious: the files only it changes), *Model* (the tier that implements
it), *Critic* (`full` or `none`) and *Review* (the tier of the
`lisp-review` sub-agent).  The milestone's planning sets them; the
whole-milestone critic checks them.

1. **Plan.** If the step says *Critic* `full`, run the `plan-critic`
   skill on it and revise the file on the feedback, or note in it why a
   point was rejected.  `full` is for steps that decide design (a
   contract other steps build on, a rule read from the sources).  `none`
   is for steps whose contract the plan text, the docs it names and its
   tests already fix (generators, utilities, writers, tools, docs); they
   go straight to implementation.
2. **Implement**, with tests, at the step's *Model* tier: start the
   session with that model, or have a coordinator hand the step to a
   sub-agent of that tier.  The coordinator keeps design and review
   (`AGENTS.md`).
3. **Close the step** (`step-close` skill):
   - The docs the step names under *Docs:* describe the code as it now is.
     So do `docs/architecture.md` (package table, status), `AGENTS.md`
     (commands, layout) and any topic doc the change made untrue.
   - **The schema is correct and documented.** If the step changed what
     the model holds or means, the node declarations and their
     documentation say so, and the generated JSON Schema and reference doc
     are regenerated. A step that finds a schema definition or its
     documentation wrong fixes it there and then, even if the definition
     belongs to an earlier step (`docs/exports.md`, "Versioning").
   - Run `lisp-review` on everything, plan tick included, with a reviewer
     of the step's *Review* tier; fix or justify every finding.  Never
     skip it: the gate is cheap next to a bad merge.
   - Tick the step in `docs/plan/<id>.md` (only your own step; `PLAN.md`
     names only the milestones).
   - Make one commit containing code, tests, docs and the plan tick.
     A change of the events or the model of the whole spec is meant: say
     in the message why they changed, and regenerate `tests/snapshots.sexp`
     and `tests/model-snapshots.sexp` (`make snapshots`) in that commit.

`main` stays usable after every step.

## Parallel waves

A milestone's steps are grouped into **waves**: the steps of one wave
start from the same `main` and can run at the same time, one session (and
branch, and pull request) each.  A wave's gate names the steps that must
be merged before the next wave starts; a step may start as soon as its
*After* steps are merged, even before its wave's gate.

- **Disjoint files.**  The first step of a milestone that runs in waves
  reserves the files the others fill: packages, stub files listed in
  `cl-ansi-spec.asd`, one section per step in the topic doc they share,
  extension tables (handlers, generators) instead of central `case`s.  A
  step changes the files it owns, its tests, its own sections of docs and
  its own plan item; anything else it needs goes into its pull request's
  description for the coordinator.
- **Shared files on merge.**  `cl-ansi-spec.asd`, package export lists,
  `Makefile`: keep both sides, then fix the parentheses by hand: each
  side closes the component list it ends, so a plain "accept both"
  leaves one closing paren too many (or a component twice) and the
  system no longer loads.  Merge one pull request at a time and run
  `make test` on each merge before the next.  Generated files (`tests/snapshots.sexp`,
  `tests/model-snapshots.sexp`, the JSON Schema, the reference doc): take
  either side, then run `make snapshots` or `make generate` and commit the
  result.
  `docs/plan/<id>.md`: each step ticks only its own item, so ticks merge.
- **Names in shared packages.**  Steps of one wave fill files of the
  same package, so a helper (function, macro, variable; tests included)
  carries its area's prefix (`glossary-blank-string-p`,
  `tables-spec-nodes`): two steps defining one name broke every build of
  their merge.  A handler a step registers for a key that another area's
  macros also produce (`\itemitem` inside `\gentry`, an alignment inside
  a display) is named in the step's pull request: the merge is where such
  interactions show, and the step whose area the macro belongs to adapts.
- **Coordinator only**: `PLAN.md`, `AGENTS.md`, the skills, a change to
  another phase (the semantic layer's vocabulary, the expander) that a
  wave step finds it needs: the step stops, reports it, and the
  coordinator lands it before or between waves.
- **Merging.**  A step's pull request merges after `make test` passes on
  it merged with the current `main`; the second of two conflicting
  steps merges `main` in and re-runs `make test`.  At a wave's gate the
  coordinator reads the merged plan, adjusts the next wave's steps where
  this one taught something, and runs no critic for steps marked `none`.

## A milestone

Plan it as a file `docs/plan/<id>.md`: steps, waves, and each step's
*Model*, *Critic* and *Review*.  Run `plan-critic` on the whole file once
(record the date in the file), with a stronger model if the milestone
sets contracts; afterwards `plan-critic` runs only before steps marked
*Critic* `full`.  Two milestones may run at once when their steps own
disjoint files; `PLAN.md` lists both. When every step is ticked, close it with the
`milestone-close` skill: fold decisions into the topic docs, audit the
schema documentation against what the model now holds, prune what the
milestone made stale, write `docs/history/<id>.md`, delete the plan file,
and update `PLAN.md`.
