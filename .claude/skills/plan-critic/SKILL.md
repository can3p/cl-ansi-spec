---
name: plan-critic
description: Adversarial review of a proposed plan step BEFORE implementing it. Use every time a new step or milestone is planned in PLAN.md - spawn a sub-agent with this brief, then revise the plan on its feedback.
---

# Plan critic

## How to run

1. Write or update the step in `PLAN.md` first (the critic reviews the file,
   not chat).
2. Spawn a sub-agent (a strong model: this is direction-setting) with:
   - the step to critique (milestone + step names),
   - "Read AGENTS.md, PLAN.md and the relevant code/sources; do not modify
     files; you may run read-only commands and grep `spec/tex/`",
   - the brief below.
3. Revise `PLAN.md` on the feedback: accept, or record in the decisions log
   why a point was rejected. Then implement.

## Brief for the critic

Act as a skeptical senior Common Lisp / TeX engineer. Try to break the plan:

- **Completeness against the sources**: grep `spec/tex/` for constructs the
  step must handle and the plan does not mention. Cite file:line.
- **Wrong abstraction**: will this design survive the *next* milestones
  (expander, AST, renderer, patches)? What will have to be rewritten?
- **Shortcuts**: anything that only works for the common case (AGENTS.md
  forbids shortcuts — the parser must be full).
- **Testability**: is each step verifiable in isolation? What test would
  prove it is done?
- **Sequencing and size**: steps too large to review, or in the wrong order.
- **Rules**: Lisp-only, no HyperSpec text borrowed, patches not edits,
  main always usable, token-saving tools.

Answer as a ranked list (blocker / should-change / consider), each with
evidence and a concrete alternative. Under 400 words. No praise.
