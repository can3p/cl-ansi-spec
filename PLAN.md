# Plan

The living plan for this repository. **Any session starts here**: read this
file and `AGENTS.md`, then continue at the first unchecked step of the
current milestone. Update this file in the same commit as the work it
describes (tick steps, record decisions, adjust what comes next).

Goal: a complete, reproducible parser of the dpANS3 TeX sources into an
AST, and a clean HTML rendering of it published on GitHub Pages.

## Status

- Current milestone: **M1 — TeX reader (tokenizer)**
- Last completed: M0 (scaffold), commit `a007a6b`.

## Milestones

### M0 — Scaffold ✅
- [x] Vendor sources into `spec/tex/` with provenance + SHA256SUMS.
- [x] ASDF system, Parachute tests, strict build, pinned deps, CI.
- [x] `lisp-review` skill.

### M1 — TeX reader (tokenizer)
TeX tokenisation depends on category codes that the sources change while
being read (`\catcode`\|=\active`, active `,`/`-` inside `\begincom`,
`\catothers` in format directives, `\obeylines`, `\IgnoreWhiteSpace`).
So the reader is a **lazy token stream** that consults the *current*
catcodes and `\endlinechar` at every token, pulled by the expander (M2) —
never a whole-file pre-pass. M1 builds TeX's machinery below expansion;
the `\input` *primitive* (which needs expansion to read its file name,
e.g. `\input\jobname.toc`, `\input #1`) belongs to M2.

Steps (each separately reviewable, in this order):

- [ ] **1. Token dump tool first** — `tools/tokens.lisp`, `make tokens
      FILE=… [LINES=a-b]`: compact one-token-per-line dump, used to debug
      every later step. Grows as the steps land.
- [ ] **2. `src/tex/state.lisp` — equivalents + save stack.** One TeX-style
      state (eqtb-like): catcode, lccode, uccode tables, `\endlinechar`
      (later: meanings, registers). Scoping via a single **save stack** of
      (location . old-value) entries restored at group end — not table
      copying. Includes `begin-group`/`end-group` and global assignment.
      Initialised with INITEX defaults plus the plain-TeX catcode changes,
      each listed and tested: `\`=0, `{`=1, `}`=2, `$`=3, `&`=4, `^^M`=5,
      `#`=6, `^`=7, `^^K`=7, `_`=8, `^^A`=8, `^^@`=9, `^^I`=10, space=10,
      letters=11, `~`=13, `^^L`=13 (active), `%`=14, `^^?`=15, others=12.
      Plain-TeX *macros* are not part of M1 (see open questions).
- [ ] **3. `src/tex/token.lisp` — tokens.** Character tokens (char +
      catcode) and symbolic tokens; control sequences **and active
      characters** share one interned *meaning namespace* (so `\let<=\LT`,
      `\ifx`, `\csname` are cheap in M2). Each token carries a source span
      (file name, start/end line and column). TeX equality ignores spans.
- [ ] **4. `src/tex/line.lisp` — line buffer.** Reads a file line by line;
      strips trailing spaces (103 files have them); appends `\endlinechar`
      as read from state at the moment the line is loaded.
- [ ] **5. `src/tex/scanner.lisp` — state machine** (TeXbook ch. 7–8):
      states N/M/S; space skipping after control words; `\par` on empty
      lines; comments (14) and ignored (9) characters; invalid (15) →
      condition; `^^` notation (`^^X`, `^^hh`) everywhere incl. control
      sequence names; control symbols vs words.
- [ ] **6. `src/tex/input-stack.lisp` — TeX's single input stack.** Levels
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

### M2 — Macro expander
Macros from `setup-*.tex` (~1000 `\def`s) and inline `\def`s expanded per
TeX semantics: delimited/undelimited parameters, `\let`, `\edef`/`\xdef`/
`\gdef`, grouping, `\expandafter`, `\noexpand`, `\csname`, conditionals
(`\if`, `\ifx`, `\ifcase`, `\ifnum`, `\ifdim`, `\ifodd`, `\ifmmode`, …),
`\catcode` assignments, registers as needed. A configurable set of
*semantic* control sequences (`\term`, `\param`, `\begincom`, `\label`,
`\code`, tables, …) is not expanded but emitted as structure.
Plain-TeX macros come from vendored `plain.tex`, loaded through the
expander first (see decisions log).
Detailed steps to be planned (and critiqued) when M1 is done.

### M3 — Document model / AST
Chapters, sections, dictionary entries, glossary, figures, tables, BNF,
cross-references; synthesise the generated `.fig`/`.tc`/`.toc`/`.idx` data.

### M4 — Patch tooling
Apply `patches/*.patch` in order onto a copy of `spec/tex/`, in Lisp.

### M5 — HTML renderer + GitHub Pages deployment

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

## Open questions

- (none)
