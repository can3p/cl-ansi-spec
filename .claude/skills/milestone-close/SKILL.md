---
name: milestone-close
description: Finish a milestone - fold its decisions into the topic docs, prune stale text, write its history, delete its plan file and update PLAN.md. Use when every step of docs/plan/<id>.md is ticked, or when asked to close or ship a milestone.
---

# Closing a milestone

1. **Decisions.** For each decision the milestone took or relied on, check
   that a topic doc (`docs/<topic>.md`, `docs/architecture.md`,
   `AGENTS.md`) states it as a current rule with its reason. Add it where
   it is missing.
2. **Learn.** Go through what went wrong or was surprising: review
   findings, sub-agent reports, detours. A lesson that would help most
   future steps becomes a rule where that work's reader looks: `AGENTS.md`,
   a skill's checklist (`lisp-review`, `plan-critic`), or a topic doc.
   Sharpen an existing rule rather than adding a second one. A one-off goes
   to the history only.
3. **Schema audit** (once `docs/model-reference.md` exists). Have a sub-agent read the generated
   `docs/model-reference.md` against the model built for the whole spec. It reports any
   description that is wrong, vague, a mere restatement of the name, or
   missing an example. Fix the declarations and regenerate.
4. **Prune.** `grep -rnE '<id>\b|\bM[0-9]+\b|step [0-9]+'` over `AGENTS.md`, `.claude/skills`,
   `docs/*.md` and `PLAN.md`. Delete rules that only held during the
   milestone, and restate lasting ones without the milestone's name. Check
   the paths, symbols and commands the docs name against the code.
5. **Next milestone.** If the milestone changed what the next one assumes,
   update its outline in `PLAN.md`.
6. **History.** Write `docs/history/<id>.md`: what was built, what turned
   out wrong, what was left out on purpose, the options weighed, and which
   docs and skills changed. Delete `docs/plan/<id>.md`, and update
   `PLAN.md` Status.
7. **Commit** the docs separately from the last step's code. Push.
