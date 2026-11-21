# Plan

The living plan for this repository. **Any session starts here**: read this
file and `AGENTS.md`, then continue at the first unchecked step of the
current milestone. Update this file in the same commit as the work it
describes (tick steps, record decisions, adjust what comes next).

Goal: a complete, reproducible parser of the dpANS3 TeX sources into a
**semantic document model** of the standard — chapters and sections,
glossary entries, dictionary entries (operator kind, syntax, arguments and
values, description, examples, see-also, ...), figures, BNF, and the full
cross-reference graph between them — with inline markup kept as meaning
(term reference, parameter, code, emphasis, math), not as fonts.  The
model is the product: it is exported in stable, documented data formats so
that it can drive a HyperSpec-like site of our own *or* other analyses.
The HTML site on GitHub Pages is one consumer of it, not the goal.

Consequence for every milestone: we never emulate typesetting (font
metrics, line/page breaking, box dimensions).  TeX is run only as far as
its *meaning* goes: expansion, assignments and conditionals are exact;
layout primitives are parsed (so the input stays in sync) and then either
kept as presentational hints or dropped.

## Status

- Current milestone: **M2 — Expander and semantic layer**, step 1.
- Last completed: M1 (TeX reader), all steps below.

## Milestones

### M0 — Scaffold ✅
- [x] Vendor sources into `spec/tex/` with provenance + SHA256SUMS.
- [x] ASDF system, Parachute tests, strict build, pinned deps, CI.
- [x] `lisp-review` skill.

### M1 — TeX reader (tokenizer) ✅
TeX tokenisation depends on category codes that the sources change while
being read (`\catcode`\|=\active`, active `,`/`-` inside `\begincom`,
`\catothers` in format directives, `\obeylines`, `\IgnoreWhiteSpace`).
So the reader is a **lazy token stream** that consults the *current*
catcodes and `\endlinechar` at every token, pulled by the expander (M2) —
never a whole-file pre-pass. M1 builds TeX's machinery below expansion;
the `\input` *primitive* (which needs expansion to read its file name,
e.g. `\input\jobname.toc`, `\input #1`) belongs to M2.

Steps (each separately reviewable, in this order):

- [x] **1. Token dump tool first** — `tools/tokens.lisp`, `make tokens
      FILE=… [LINES=a-b]`: compact one-token-per-line dump, used to debug
      every later step. Grows as the steps land.
- [x] **2. `src/tex/state.lisp` — equivalents + save stack.** One TeX-style
      state (eqtb-like): catcode, lccode, uccode tables, `\endlinechar`
      (later: meanings, registers). Scoping via a single **save stack** of
      (location . old-value) entries restored at group end — not table
      copying. Includes `begin-group`/`end-group` and global assignment.
      Initialised with INITEX defaults plus the plain-TeX catcode changes,
      each listed and tested: `\`=0, `{`=1, `}`=2, `$`=3, `&`=4, `^^M`=5,
      `#`=6, `^`=7, `^^K`=7, `_`=8, `^^A`=8, `^^@`=9, `^^I`=10, space=10,
      letters=11, `~`=13, `^^L`=13 (active), `%`=14, `^^?`=15, others=12.
      Plain-TeX *macros* are not part of M1 (see open questions).
- [x] **3. `src/tex/token.lisp` — tokens.** Character tokens (char +
      catcode) and symbolic tokens; control sequences **and active
      characters** share one interned *meaning namespace* (so `\let<=\LT`,
      `\ifx`, `\csname` are cheap in M2). Each token carries a source span
      (file name, start/end line and column). TeX equality ignores spans.
- [x] **4. `src/tex/line.lisp` — line buffer.** Reads a file line by line;
      strips trailing spaces (103 files have them); appends `\endlinechar`
      as read from state at the moment the line is loaded.
- [x] **5. `src/tex/scanner.lisp` — state machine** (TeXbook ch. 7–8):
      states N/M/S; space skipping after control words; `\par` on empty
      lines; comments (14) and ignored (9) characters; invalid (15) →
      condition; `^^` notation (`^^X`, `^^hh`) everywhere incl. control
      sequence names; control symbols vs words.
- [x] **6. `src/tex/input-stack.lisp` — TeX's single input stack.** Levels
      of kind file, token list (macro bodies, inserted lists) and back
      list; operations `push-file`, `push-tokens`, `back-input`,
      `next-token`, `peek`, end-of-file handling; **pluggable file
      resolver** returning a stream or a synthesised source, so missing
      generated files (`chap-N.fig`, `.tc`, `.toc`, `.idx`) are a hook M3
      fills, not an error.

Tests:
- Golden token dumps for small fixtures, one per TeXbook rule, including
  catcode changes in the middle of a line and `\endlinechar` changes.
- **Coverage property**: for every `spec/tex/*.tex` (not `.text`/`.lisp`),
  the source spans of tokens plus skipped comments/spaces/line ends cover
  the file exactly, in order — proves locations are right.
- Save-stack tests: nested groups, global assignments inside groups.

Done when: every step ticked, coverage property green on all 125 `.tex`
files under plain catcodes, `lisp-review` clean.

### M2 — Expander and semantic layer
Input: tokens from M1.  Output: an **event stream** — a flat sequence of
semantic events (begin/end of a semantic construct with its parsed
arguments, text runs with their inline style, markers such as `\label`),
each with the source span it came from.  M3 assembles the stream into the
document model; M2 knows nothing about chapters or dictionary entries.

How meaning is kept: a declared **semantic vocabulary** — the spec's own
macros (from `setup-*.tex`) and a few plain ones that carry meaning
(`\term`, `\param`, `\code`…`\endcode`, `\begincom`…`\endcom`, `\label`,
`\beginSection`, `\Defun*`, `\funref`/`\clref`, `\secref`, `\figref`,
`\DefineSection`, `\DefineFigure`, `\issue`…`\endissue`, `\editornote`,
figure and table macros, `\+`, ...).  Rules (from the plan critique):

- **Keyed on meanings, not names.**  An entry is attached to a macro
  meaning, so aliases (`\def\funref{\clref}`, setup-document.tex:61-75)
  and tokens inserted from `\halign` templates (`\misc{##}`,
  setup-tables.tex:7) are recognised.  Redefining a vocabulary macro is
  reported (`\caption` is defined twice, setup-aux.tex:706/737).
- **Observe by default.**  The entry emits a begin event with its
  arguments as parsed by the macro's own parameter text, then lets the
  macro expand normally — so counters, `\gdef`s and flags it sets
  (`\startSection`, `\toc`, `\capno`, `\incomtrue`) stay exact — and an
  end event when its expansion is done; presentational events in between
  belong to the entry.  An entry may name a later macro of a chain as its
  observation point (`\begincom` → `\dobegincom`, after the catcode
  changes).  *Replacing* a macro by a Lisp handler is the exception, each
  one justified in the vocabulary file.
- **Environments** (`\code`…`\endcode` via `\screen!`, `\begincom`…
  `\endcom`, `\issue`…`\endissue`) are begin/end pairs; issues may cross
  section boundaries (ranges, not tree nodes).  Code keeps its exact
  characters, spaces and line structure (golden round-trip tests).

Each chapter file is its **own TeX job**, started from the plain-TeX
snapshot (`chap-0.tex` reads `setup-for-toc`, others `setup`); `\jobname`
is the chapter's name.

Steps (each separately reviewable, in this order; tools and tests grow with
every step):

- [ ] **1. Vendor plain TeX.** `vendor/plain/plain.tex` and `hyphen.tex`
      unmodified, from the Debian `texlive-base` 2023.20240207-1 package,
      with `PROVENANCE.md` and `SHA256SUMS` (checked by `make test` and CI
      like `spec/`).  A search-path resolver (spec tree, then
      `vendor/plain/`); sources keep their own file names in spans.
- [ ] **2. Vocabulary inventory tool** (`make vocab`, no expansion, uses
      M1 tokens): every macro `\def`'d in each file, its uses per file,
      simple aliases, and source counts of candidate vocabulary entries.
      Its output seeds the vocabulary and the step-14 invariants, and tells
      which primitives and quantities the later steps must get exactly.
- [ ] **3. Quantities.** Integers with TeX's overflow rules, dimensions in
      scaled points, glue specs with stretch/shrink orders, TeX's exact
      arithmetic (`x_over_n`, `xn_over_d`, `nx_plus_y`, decimal rounding)
      and printing (`\the` of dimens and glue).  Golden tests derived from
      the TeX rules.
- [ ] **4. Meanings and registers in the state.** Meanings of control
      sequences and active characters (undefined, macro with parameter
      text/body and `\long`/`\outer` flags, primitive, `\let` to a
      character, `\chardef`/`\mathchardef`/`\countdef`/...); count, dimen,
      skip, muskip, toks and box registers; every TeX82 integer, dimen,
      glue and token-list parameter with INITEX defaults; mathcode, sfcode,
      delcode tables; fonts as identifiers with a `\fontdimen` table and
      no metrics.  All through the existing save stack; `\globaldefs`.
- [ ] **5. Expansion core and `make expand` tool.** `get-x-token`; macro
      calls with full parameter matching (TeXbook ch. 20: delimited and
      undelimited, `#{`, brace stripping, `\par` in non-`\long` macros,
      `\outer` checks); `\expandafter`, `\noexpand`, `\csname`,
      `\string`, `\meaning`, `\jobname`, `\input`/`\endinput`, marks.
      TeX errors are conditions with TeX's recovery as restarts.  The tool
      prints the expanded token stream of a file/line range.
- [ ] **6. Scanning.** Keywords, `<number>`, `<dimen>` (all units, `true`,
      `em`/`ex` from `\fontdimen`), `<glue>`, `<mudimen>`, internal
      quantities, general text; `\the`, `\number`, `\romannumeral`,
      `\fontname`.
- [ ] **7. Conditionals.** All of TeX82's (`\if`, `\ifcat`, `\ifx`,
      `\ifnum`, `\ifdim`, `\ifodd`, `\ifvmode`, `\ifhmode`, `\ifmmode`,
      `\ifinner`, `\ifvoid`, `\ifhbox`, `\ifvbox`, `\ifeof`, `\iftrue`,
      `\iffalse`, `\ifcase`), condition stack, skipping nested
      conditionals.
- [ ] **8. Main control: assignments and grouping.** Assignments with
      prefixes, `\afterassignment`, `{}`/`\begingroup`/`\aftergroup`,
      `\uppercase`/`\lowercase`, `\message`/`\show*`,
      `\openout`/`\write`/`\closeout`/`\immediate` (writes become events
      carrying their token list; nothing is written to disk), `\relax`,
      `\ignorespaces`; TeX's modes tracked (`\ifmmode`, `\leavevmode`,
      `\par`) without building lists.
- [ ] **9. Presentational events and `make events` tool.** The
      per-primitive table: every remaining primitive has its operand
      syntax scanned and becomes a presentational event (`\par`, glue,
      `\hbox{...}` as begin/end, `\char`, math shifts, sub/superscripts,
      rules, ...) or is dropped — each choice listed.  Text runs carry the
      current font identifier.  Box registers hold the events emitted
      inside them, with specified, tested semantics for everything the
      setup files rely on: `\box`/`\copy`/`\unhbox`/`\unvbox` replay;
      `\lastbox` removes the last box event; `\vsplit` takes the whole
      box; `\wd`/`\ht`/`\dp` are 0 unless assigned; `\lastskip`,
      `\lastpenalty`, `\lastkern` look at the last event of the current
      list; `\pagetotal`, `\prevdepth` are 0 (no metrics).
- [ ] **10. Alignments.** `\halign`/`\valign`: preamble with `\tabskip`,
      `&&`, `\span`; u/v templates inserted per cell; `\omit`, `\span`,
      `\noalign`, `\cr`, `\crcr` — emitted as table/row/cell events.
- [ ] **11. Plain TeX loads.** All of `vendor/plain/plain.tex` runs with no
      error; the resulting state is snapshotted (TeX's `\dump`) and
      reused by every job.
- [ ] **12. Vocabulary mechanism.** Entries keyed on meanings, observe
      and replace modes, observation points, begin/end environments,
      redefinition reports; fixture tests for aliases, template-inserted
      tokens and code round-trip.
- [ ] **13. The vocabulary.** The entries themselves (a data file, each
      with its mode and justification), including every cross-reference
      macro (`\secref`, `\figref`/`\Figref`, `\DefineSection`,
      `\DefineFigure`, `\deffigrefs`/`\defsecrefs`).  Content hidden by
      options (`\editornotesfalse`, `\issdispfalse`) is still emitted,
      flagged, by its entry: the model keeps everything the sources say.
- [ ] **14. Whole spec.** Every chapter job runs with no error;
      generated files (`chap-N.fig`, `.tc`, `\jobname.toc`/`.idx`) resolve
      to empty synthesised sources.  Invariants: for each job, source
      counts of each vocabulary entry (from step 2) equal its event counts;
      files no job reaches are reported (`setup-boxfig.tex`); a hash of
      each job's event stream is kept as a snapshot test.

Done when: every step ticked, step 14 green in the test suite,
`lisp-review` clean.

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
reported.  **Export** to documented formats (S-expressions and JSON), with
schema tests over the whole spec.

### M4 — Patch tooling
Apply `patches/*.patch` in order onto a copy of `spec/tex/`, in Lisp.

### M5 — Consumers
An HTML site (our own HyperSpec-like rendering, nothing borrowed from the
HyperSpec) generated from the model and deployed to GitHub Pages; the
exports published alongside it.

## Decisions log

- 2026-11-20: Sources vendored verbatim from LispLang/ansi-spec@e18e52d.
- 2026-11-20: Parachute over FiveAM (Alexandria unreachable from the agent
  network); deps pinned by commit, no Quicklisp.
- 2026-11-21: Reader is lazy and catcode-driven (sources change catcodes).
- 2026-11-21: M1 revised after plan-critic: single input stack with
  back-input and resolver hook in M1, `\input` primitive in M2; eqtb-like
  state with one save stack instead of copied catcode tables; active chars
  share the control-sequence meaning namespace; coverage-property tests
  instead of token counts; token dump tool built first.
- 2026-11-21: Source locations name the file actually read, by file name
  relative to the tree root. Patched and pristine trees use the same names,
  so locations stay meaningful once M4 exists. M4 may add the patch origin
  to these locations.
- 2026-11-21: Plain-TeX macro layer: **option A** (user decision). Vendor
  Knuth's `plain.tex` unmodified (own directory, with provenance) and run
  it through our expander before the spec, as TeX does. Typesetting-only
  primitives it relies on (fonts, boxes, ...) are accepted and recorded or
  ignored by the expander, never faked as macros. Candidate source: the
  Debian/Ubuntu `texlive-base` package (reachable via apt); verify against
  CTAN's published checksum where possible. Planned in detail with M2.
- 2026-11-21: The HyperSpec may be consulted for ambiguity only; nothing is
  ever copied from it (see AGENTS.md).

- 2026-11-21: M1 implementation notes.  The token dump tool landed together
  with the scanner (it has nothing to dump before tokens exist).  Spans are
  file character offsets [start, end) plus line/column of start; a line's
  \endlinechar owns the removed trailing spaces and the newline, otherwise
  they are reported as a `:line-end` skip.  Every buffer element keeps its
  file offset, so `^^` notation inside control sequence names is rewritten
  in the buffer exactly as TeX does (a later catcode change cannot re-read
  it).  Character tables are vectors for codes 0-255 plus a hash table for
  larger codes (patched sources may be UTF-8), defaulting to category 12.
  `next-token` returns NIL at the end of all input; `\endinput`, `\outer`
  checks and `\everyeof`-style hooks are left to M2.

- 2026-11-21: Goal clarified by the user: the product is a semantic
  document model usable for our own HyperSpec-like site or other
  analyses; HTML is one consumer.  Hence: no typesetting emulation (no
  metrics, box dimensions are 0, no line/page breaking); a semantic
  vocabulary of macros is intercepted in M2 instead of expanded; M3 is the
  model plus its exports.
- 2026-11-21: M2 revised after plan-critic: vocabulary keyed on meanings
  and observing (macros still expand, so their counters and flags stay
  exact) rather than replacing; environments as begin/end pairs; one TeX
  job per chapter from a plain-TeX snapshot; cross-reference macros in the
  vocabulary, resolved in M3 from `\Define*` events; vocabulary inventory
  tool moved to step 2; main control split into assignments, presentational
  events and alignments; count invariants and stream snapshots for step 14.
- 2026-11-21: Review of M1 against the clarified goal: all of it is
  needed.  The sources change catcodes (`\begincom`, `\code` via
  `\screen!`, `\obeylines`) and 17 non-setup files contain `\def`,
  `\let` or `\catcode` (102 uses), so a catcode-exact reader and a real
  expander are the only full route; source spans are what lets every
  model node point back to its source (and to patches, M4).  Nothing is
  stripped.

## Open questions

- (none)
