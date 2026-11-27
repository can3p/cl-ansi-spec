---
name: plan-critic
description: Adversarial review of a proposed plan BEFORE implementing it. Use once when a milestone is planned in docs/plan/<id>.md, and before a step marked Critic full - spawn a cheap sub-agent with a self-contained brief, then revise the plan on its feedback. Steps marked Critic none skip it.
---

# Plan critic

The critic must cost far less than the step it reviews. Most of a
sub-agent's cost is fixed: every spawn starts from ~60-70k tokens of
system prompt and tool schemas, even with one tool call. So **spawn
rarely**, and keep the reading small:

- **Only where design is decided.** A step marked *Critic* `none`
  (`docs/process.md`, "A step") gets no critic: its contract is already
  fixed by the plan, the docs and the tests.
- **Pair it with a review.** When a step closes and a `full` step comes
  next in the same session, the one `lisp-review` sub-agent also critiques
  it (one spawn, two answers). Spawn a critic alone only for the first
  `full` step of a session.
- **Whole milestone.** Also check that each step's *Wave*, *After*,
  *Owns*, *Model*, *Critic* and *Review* hold: steps of one wave touch
  disjoint files; a cheaper tier gets only steps whose contract is fixed;
  `none` is never given to a step that reads a rule from the sources.
- The coordinator already knows the context, so it *hands it over*
  instead of making the critic rediscover it.

## How to run

1. Write or update the step in `docs/plan/<id>.md` first.
2. Gather the evidence yourself, cheaply: the step text, the one or two
   doc rules it must satisfy, and the facts you already found (file:line,
   counts, grep hits). Keep it under ~60 lines.
3. Spawn **one** sub-agent (or add the brief to the `lisp-review` spawn)
   with `model: sonnet` (a whole-milestone review
   may use a stronger model once). The brief contains:
   - the step text and the gathered facts, pasted in;
   - at most ~5 exact commands it may run to check suspicions
     (`grep -n …`, `sed -n 'a,bp' FILE`, `make tokens … LINES=`), and a
     hard budget: **at most 8 tool calls, no `Read` of whole files, no
     docs/architecture.md or other topic doc unless you name line ranges**;
   - "Do not modify files.";
   - the brief below.
4. Revise the milestone file on the feedback: accept, or record why a point
   was rejected. Then implement.

## Brief for the critic

Act as a skeptical senior Common Lisp / TeX engineer. Try to break the
step. Check, in this order, and skip what does not apply:

- **Completeness against the sources**: constructs in `spec/tex/` the step
  must handle and does not mention (cite file:line).
- **Shortcuts**: anything that only works for the common case (the parser
  must be full).
- **Boundaries**: one package per phase, one-way dependencies; does the
  output fit what the next phase consumes?
- **Meaning and spans**: does anything drop meaning or source spans the
  semantic model needs, or emulate typesetting it does not need?
- **Where TeX really is**: a plan about macros must say, on real lines,
  in which list and at which token their effects land: a tail call ends
  its caller first, a body may open a formula or a box, TeX expands a
  table cell's first macro before its template, a body may end the
  paragraph it was called in, a box set with `\setbox` may be thrown
  away.  Ask for a fixture from the sources for each such case.
- **Testability**: the test that proves the step done.
- **Docs**: does the step name the docs it leaves up to date (and the
  schema, if the model changes)?

Answer with at most 6 findings, ranked (blocker / should-change /
consider), each with evidence and a concrete alternative. Under 250 words.
No praise, no restating the plan.
