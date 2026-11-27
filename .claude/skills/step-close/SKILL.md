---
name: step-close
description: Finish one step of the current milestone - bring the docs in line with the code, run lisp-review, tick the plan and commit everything together. Use when a step's code and tests are done, or when asked to wrap up or commit a step.
---

# Closing a step

A step is done when code, tests and docs agree (`docs/process.md`).

1. **Docs.** Read the step's *Docs:* line in `docs/plan/<id>.md`. In each doc
   it names, `grep -n` for the symbols, files, commands and numbers the step
   touched, then fix what is now untrue or missing. Also:
   - `docs/architecture.md`: the package table and Status, if a package
     appeared or a phase changed state;
   - `AGENTS.md`: Commands and Repository layout, if a tool, make target or
     directory appeared;
   - a decision the step took: state it as a current rule, with its reason,
     in the topic doc it governs, not in the plan.
   - the schema: if the step changed what the model holds or means, or
     showed a definition to be wrong, fix the `define-node` declarations
     and their documentation (`docs/exports.md`, "Documentation of every
     definition") and regenerate the JSON Schema and reference doc. Wrong
     definitions are fixed now, whichever step wrote them (`docs/exports.md`,
     "Versioning").
   Docs hold no history and no milestone names ("since step 4…", "in M2");
   history goes to `docs/history/` when the milestone closes.
2. **Plan.** Tick the step in `docs/plan/<id>.md`. Adjust later steps only
   where this step taught something. In a parallel wave
   (`docs/process.md`, "Parallel waves") tick only your own step and put
   proposed changes to other steps, `PLAN.md`, `AGENTS.md` or the skills
   in the pull request's description instead.
3. **Review.** Run the `lisp-review` skill (it includes the build gate) on
   the whole diff: code, tests, docs and plan, with the step's *Review*
   tier. Fix or justify every finding.
4. **Commit.** Make one commit: code, tests, docs and the plan tick. List
   skipped review findings in the message. Push to the session branch.
   (Milestone closing commits its docs separately; a step never does.)
