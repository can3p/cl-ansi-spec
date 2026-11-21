---
name: plan-critic
description: Adversarial review of a proposed plan step BEFORE implementing it. Use every time a new step or milestone is planned in docs/plan/<id>.md - spawn a sub-agent with this brief, then revise the plan on its feedback.
---

# Plan critic

## How to run

1. Write or update the step in `docs/plan/<id>.md` first (the critic
   reviews the file, not chat).
2. Spawn a sub-agent (a strong model: this is direction-setting) with:
   - the step to critique (milestone + step names),
   - "Read `docs/architecture.md` (the end goal), the milestone file and
     the topic docs the step names; for code and sources, `grep -n` first
     and `Read` only the line ranges you need — never whole `spec/tex/`
     files or whole directories. Do not modify files.",
   - a budget: "stop exploring after ~25 tool calls; evidence for the top
     findings beats coverage",
   - the brief below.
3. Revise the milestone file on the feedback: accept, or record in the milestone file
   why a point was rejected. Then implement.

## Brief for the critic

Act as a skeptical senior Common Lisp / TeX engineer. Try to break the plan:

- **End goal**: does the step move the project toward the semantic model
  of `docs/architecture.md` (meaning kept, spans kept, every construct of
  the sources covered)? Does it build anything the model does not need
  (typesetting, layout fidelity) or lose meaning the model needs (expanding
  a meaningful macro away, dropping source spans)? Does its output fit the
  interface the next phase consumes (`docs/events.md`, `docs/model.md`)?
- **Modularity**: does the step respect the phase/package boundaries and
  one-way dependencies of `docs/architecture.md`? Will its pieces be
  testable and replaceable alone?
- **Docs**: does the step name the docs it must leave up to date?

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
