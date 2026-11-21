# Architecture

## End goal

A **semantic model of the ANSI Common Lisp standard**, parsed completely and
reproducibly from the dpANS3 TeX sources in `spec/tex/` (plus our patches in
`patches/`). The model is the product. It holds:

- chapters, sections and subsections, with numbers and labels;
- glossary entries;
- dictionary entries: names, kind (Function, Macro, …) and their labelled
  parts (Syntax, Arguments and Values, Description, Examples, See Also, …);
- figures and tables, syntax and BNF, issue references, editor notes;
- the **cross-reference graph**: term → glossary entry, operator → dictionary
  entry, section/figure reference → section/figure;
- inline content by *meaning* (term, parameter, code, emphasis, math), never
  by font;
- the source span every node came from.

It is exported in stable, documented formats (S-expressions and JSON). It can
drive our own HyperSpec-like site or any other analysis. The HTML site is one
consumer; nothing is shaped around it. Nothing is ever taken from the Common
Lisp HyperSpec (see `AGENTS.md`).

## Principles

1. **Exact where meaning is decided.** The sources rely on TeX itself:
   catcode changes, `\obeylines` code blocks, `\def`s inside chapters, and
   counters that number sections. So reading, expansion, assignments and
   conditionals follow TeX's rules exactly.
2. **No typesetting.** Font metrics, line breaking, page breaking and box
   dimensions are not emulated. Layout primitives are parsed, so that the
   input stays in sync, and are then kept as presentational hints or dropped.
   [TeX fidelity](tex-fidelity.md) lists what is exact and what is not.
3. **Meaning is observed, not reconstructed.** The spec's meaningful macros
   (`\term`, `\begincom`, `\label`, …) form a declared
   [semantic vocabulary](vocabulary.md). The expander reports where each one
   begins and ends instead of guessing structure from layout afterwards.
4. **Everything points back to its source.** Every token, event and model
   node carries a span (file, offsets, line, column).
5. **Modular, one-way layers.** Each phase is its own package with a small
   exported interface. It depends only on the phases before it, and it is
   testable alone.

## Phases

```
spec/tex/ + patches/ ──► 0 Sources ──► 1 Reader ──► 2 Expander ──► 3 Semantic layer
                                                                       │ event stream
                                       5 Consumers ◄── 4 Model builder ◄┘
                                       (exports, HTML)   (document model)
```

| # | Phase | Input → output | Package | Milestone |
|---|-------|----------------|-------------------|-----------|
| 0 | Sources | files → named line sources; patched tree | `cl-ansi-spec` (source), later `…/patch` | M0 ✅, M4 |
| 1 | Reader | characters → tokens with spans, under the *current* catcodes | `cl-ansi-spec/tex` | M1 ✅ |
| 2 | Expander | tokens → executed TeX: macros, conditionals, assignments, registers | `cl-ansi-spec/expand` | M2 |
| 3 | Semantic layer | expander activity → **event stream** | `cl-ansi-spec/semantic` | M2 |
| 4 | Model builder | event streams of all chapters → **document model**, resolved references | `cl-ansi-spec/model` | M3 |
| 5 | Consumers | model → S-expression/JSON exports, HTML site | `…/export`, `…/html` | M3, M5 |

- **Sources.** These are the pristine tree and the plain-TeX files vendored
  under `vendor/plain/`. File access goes through a pluggable *resolver*.
  Missing generated files (`chap-N.fig`, `.tc`, `.toc`, `.idx`) are
  synthesised by the resolver, not treated as errors.
- **Reader** ([reader](reader.md)). This is a lazy, pull-based token stream. It consults the
  catcodes and `\endlinechar` at every token, because the sources change them
  while being read. TeX's single input stack (files, token lists, backed-up
  tokens) lives here.
- **Expander.** It runs TeX's semantics below typesetting. Each chapter is
  its own TeX job. Every job starts from a snapshot of the state after
  `plain.tex` has been loaded.
- **Semantic layer.** It turns vocabulary hits, text, and the remaining
  presentational primitives into a flat [event stream](events.md).
- **Model builder.** It assembles the events into the
  [document model](model.md) and resolves every reference. Anything
  unresolved is reported, never silently dropped.

## Example, end to end

Source (`dict-conses.tex:1702`, abridged):

```tex
\begincom{endp}\ftype{Function}
\label Syntax::
\DefunWithValues endp {list} {generalized-boolean}
\label Arguments and Values::
\param{list}---a \term{list},
\issue{DOTTED-LIST-ARGUMENTS:CLARIFY}
 which might be a \term{dotted list} or a \term{circular list}.
\endissue{DOTTED-LIST-ARGUMENTS:CLARIFY}
...
\label Side Effects:\None.
...
\endcom
```

Event stream, as phase 3 emits it (spans omitted):

```lisp
(:begin :com :names ("endp") :kind "Function")
(:mark :label :title "Syntax")
(:begin :defun :name "endp" :lambda-list ("list") :values ("generalized-boolean"))
(:end :defun)
(:mark :label :title "Arguments and Values")
(:begin :param) (:text "list") (:end :param)
(:text "---a ") (:begin :term) (:text "list") (:end :term) (:text ",")
(:begin :issue :name "DOTTED-LIST-ARGUMENTS:CLARIFY")
(:text " which might be a ") (:begin :term) (:text "dotted list") (:end :term) ...
(:end :issue :name "DOTTED-LIST-ARGUMENTS:CLARIFY")
...
(:mark :label :title "Side Effects" :none t)
...
(:end :com)
```

Document model, as phase 4 builds it (spans and most content omitted):

```lisp
(:dictionary-entry
 :id "endp" :names ("endp") :kind :function
 :span ("dict-conses.tex" :line 1702)
 :parts
 ((:part :title "Syntax"
   :content ((:defun :name "endp" :lambda-list ((:param "list"))
                     :values ((:param "generalized-boolean")))))
  (:part :title "Arguments and Values"
   :content ((:paragraph
              (:param "list") "---a " (:term-ref "list" :target (:glossary "list")) ","
              (:issue-start "DOTTED-LIST-ARGUMENTS:CLARIFY")
              " which might be a "
              (:term-ref "dotted list" :target (:glossary "dotted list")) " or a "
              (:term-ref "circular list" :target (:glossary "circular list")) "."
              (:issue-end "DOTTED-LIST-ARGUMENTS:CLARIFY"))))
  (:part :title "Side Effects" :none t)
  (:part :title "Notes"
   :content ((:paragraph "The purpose of "
              (:operator-ref "endp" :target (:entry "endp")) " is to test ...")))))
```

[Document model](model.md) has the schema draft; [exports](exports.md)
has the export formats, their JSON Schema and versioning.

## Code layout and composability

- One package per phase. A phase uses only the *exported* symbols of the
  phases below it, and nothing reaches back up. Packages use
  `:import-from`, not `:use`, across phase boundaries.
- Within a phase, files are small and each has one job. The dependency order
  is the `:serial` order in `cl-ansi-spec.asd`, and each file starts with a
  header that says what it holds.
- State is passed explicitly (`tex-state`, `input-stack`, …). Special
  variables are allowed only for dynamic context that TeX itself scopes, and
  each one is documented where it is defined.
- Extension points are data or protocols, not edits scattered across the
  code: the file resolver, the primitive table, the vocabulary table, and the
  export writers.
- Each package has its own test suite under `tests/<phase>/`, and its own
  debugging tool under `tools/` (`make tokens`; planned: `make expand`,
  `make events`, `make vocab` and `make model` as their phases land).

## Status

| Phase | State |
|-------|-------|
| 0 Sources | pristine tree and resolver done; patching is M4 |
| 1 Reader | done (M1) |
| 2–3 Expander, semantic layer | planned: [`docs/plan/m2.md`](plan/m2.md) |
| 4–5 Model, consumers | outlined in `PLAN.md` |

Related: [process](process.md) explains how work advances.
[History](history/) records finished milestones.
