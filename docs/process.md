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

## A step

1. **Plan.** Run the `plan-critic` skill on the step in
   `docs/plan/<id>.md`. Revise the file on the feedback, or note in it why a
   point was rejected.
2. **Implement**, with tests. Use the cheapest model tier that fits; the
   coordinator keeps design and review (`AGENTS.md`).
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
   - Run `lisp-review` on everything, plan tick included; fix or justify
     every finding.
   - Tick the step in `docs/plan/<id>.md` (the first unticked step is the
     current one; `PLAN.md` names only the milestone).
   - Make one commit containing code, tests, docs and the plan tick.

`main` stays usable after every step.

## A milestone

Plan it as a file `docs/plan/<id>.md` and run `plan-critic` on the whole
file once (record the date in the file); afterwards `plan-critic` runs per
step, before the step is implemented. When every step is ticked, close it with the
`milestone-close` skill: fold decisions into the topic docs, audit the
schema documentation against what the model now holds, prune what the
milestone made stale, write `docs/history/<id>.md`, delete the plan file,
and update `PLAN.md`.
