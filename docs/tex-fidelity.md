# TeX fidelity

What phases 1–3 do exactly as TeX does, and what they deliberately do not do.

## Exact

- Tokenisation: catcodes, `\endlinechar`, `^^` notation, states N/M/S, and
  the input stack (done, M1).
- Expansion: macros with full parameter matching, `\expandafter`,
  `\noexpand`, `\csname`, `\string`, `\meaning`, `\the`, `\number`,
  `\romannumeral`, `\input`, `\endinput`, and all of TeX82's conditionals.
- The expansion core (`src/expand/`: `expander.lisp`, `macro.lisp`,
  `expandable.lisp`, `show.lisp`, `primitives.lisp`, `errors.lisp`):
  - *Tokens come with their meaning*, as TeX's cur_tok comes with
    cur_cmd/cur_chr: `get-next`, `get-token` and `get-x-token` return the
    token and the meaning of its control sequence (`nil` for a character).
    A `\noexpand`-ed token is a marker token in the input; read, it is the
    plain token with the meaning `\relax` when it would have expanded.
  - *The primitive table* names every TeX82 primitive from the start, so
    `\meaning` and `\ifx` see them; each step registers the operations
    it implements.  An expandable primitive whose step has not landed is
    a TeX error that drops the token.
  - *Macro calls* follow §§389-400 token by token: delimited and
    undelimited parameters, the recovery after a partial delimiter match,
    brace stripping, `#{`, spaces before undelimited arguments (only
    character 32 of category 10), `\par` in a macro that is not `\long`,
    an extra `}`.  Arguments keep the tokens actually read, so spans
    point to the input.  The body is substituted at once and pushed as
    one list; exhausted token lists are removed first, so tail calls do
    not grow the input stack.
  - *Runaways*: an `\outer` macro, or the end of a file, met while
    matching, defining, skipping, aligning or absorbing is reported and
    ended as TeX does (an inserted `\par`, `}`, `\fi` or `\cr}`).
  - *Errors are conditions*: `tex-error` signals with a `recover` restart
    that continues as TeX does in `\batchmode`; every job recovers
    (`call-recovering-tex-errors`) and reports.  A missing `\input` file
    is a `tex-fatal-error`, as in nonstop mode.
  - *Shown as TeX shows them* (`\string`, `\meaning`): `print_cs` spacing,
    `\escapechar`, match characters, `\long`/`\outer` prefixes.  Without
    metrics, a font loaded `scaled` shows no size.
  - Marks expand to nothing until boxes and `\vsplit` set them.  Tracing
    (`\tracingmacros` and the like) writes no log.
- Assignments and grouping: the save stack, `\global`, `\globaldefs`,
  `\afterassignment` and `\aftergroup`; registers and parameters with
  INITEX defaults; TeX's integer, dimension and glue arithmetic.
- Quantities (`src/expand/`, files `arithmetic.lisp`, `units.lisp`,
  `glue.lisp`, `print.lisp`): integers are CL integers, dimensions integers
  in scaled points, glue an immutable struct (width, stretch, shrink,
  orders 0–3 for finite/fil/fill/filll, and a mu tag for `\muskip`).
  Every rule follows *TeX: The Program* and cites its section number;
  nothing is copied from it.
  - *Arithmetic*: `x_over_n`, `xn_over_d` and `nx_plus_y` as TeX computes
    them, including the value TeX leaves on overflow.  An operation that
    can overflow returns its result, then an overflow flag (TeX's
    `arith_error`), then the remainder where TeX has one; the scanner
    reports the error ("Arithmetic overflow", "Dimension too large"),
    because only it knows TeX's recovery.  `\divide` by 0 is an overflow.
    `\advance` is unchecked in TeX: sums wrap to 32 bits, as TeX's
    implementations do, so registers hold any 32-bit word.
  - *Units* are data (`physical-unit-table`: exact ratios to the point) and
    pure functions in scan_dimen's order: `true` (through `\mag`), the
    physical unit, or a scale by a unit value (em/ex from the font's
    `\fontdimen`, an internal dimen, mu), then the sign and the
    `max_dimen` clamp.  Decimal fractions round as `round_decimals` (17
    digits at most).  Parsing the keywords is the scanner's.
  - *Printing* (`\the`, `\showthe`): `print_scaled`, so every dimension
    prints with the fewest digits that read back as itself; glue shows
    ` plus `/` minus ` only when nonzero, with `fil`, `fill`, `filll` or the
    unit (`pt`, or `mu` for mu glue).
- The state (`src/expand/state.lisp`, with `meaning.lisp`, `font.lisp`,
  `parameters.lisp`): the rest of TeX's table of equivalents on top of the
  reader's `tex-state`, all under its one save stack, so one `end-group`
  restores everything.
  - *Meanings* of control sequences and active characters: undefined
    (`nil`), macro (parameter text, body, `\long`/`\outer`), primitive,
    a character (`\let` to a character token), a shorthand (`\chardef`,
    `\mathchardef`, `\countdef` … `\toksdef`), or a font.  Meanings are
    immutable, so `\let` shares them; `meaning=` compares as `\ifx` does.
  - *Registers* 0–255 of each kind (count, dimen, skip, muskip, toks,
    box), every TeX82 parameter by keyword (`:tolerance`), and the math,
    space-factor and delimiter codes.  Values are type-checked (a skip is
    never mu glue); range errors TeX reports ("Invalid code") are the
    scanner's.  Integer parameters live in the reader's table, since the
    reader reads `\endlinechar`.
  - *Defaults are INITEX's* and are not stored: an unassigned entry reads
    as INITEX's value (§§232, 240), which also gives characters beyond 255
    TeX's rule.  `\time`, `\day`, `\month`, `\year` are TeX's own
    fallback (noon, 4 July 1776), so that jobs are reproducible.
  - *`\globaldefs`* is applied to every assignment, as TeX does before
    the assignment is made (so `\globaldefs=1` itself is local).
  - *Fonts* are identifiers: file, size specification, the name of the
    control sequence that loaded it, and the `\fontdimen`, `\hyphenchar`
    and `\skewchar` values assigned (globally, as in TeX).  `\font`
    reuses a font of the same file and size; `scaled 1000` is the design
    size, but without metrics an `at` size never equals it.
- Alignments: preamble, templates, `\span`, `\omit`, `\noalign`, `\cr`,
  `\crcr`.
- Modes, tracked so that `\ifmmode`, `\leavevmode` and `\par` behave as in
  TeX.

## Not emulated (no typesetting)

- **No font metrics.** Characters have no width, height or depth.
  `\fontdimen` returns what was assigned, else 0.
- **Boxes hold events, not dimensions.** `\box`, `\copy`, `\unhbox` and
  `\unvbox` replay the events. `\lastbox` removes the last box event.
  `\vsplit` takes the whole box. `\wd`, `\ht` and `\dp` are 0 unless
  assigned.
- No line breaking and no page builder. `\pagetotal` and `\prevdepth` are 0.
  `\lastskip`, `\lastpenalty` and `\lastkern` look at the last event of the
  current list. `\output` is stored and never run; `\shipout` is an event.
- `\write` and `\openout` write nothing; writes are events.

These choices only affect layout code in `setup-*.tex`, such as running
heads (`\comline`) and `\Vskip`. They are checked against every
dimension-dependent branch the setup files take; each one has a test.

## Jobs

Each chapter file is a separate TeX job. Its `\jobname` is the chapter name.
Every job starts from a snapshot of the state after Knuth's `plain.tex` and
`hyphen.tex` were run through our expander. Those files are vendored
unmodified in `vendor/plain/`, with their provenance and licence in
`vendor/PROVENANCE.md`; `patches/` never applies to them. Jobs read inputs
along the source search path: the spec tree, then `vendor/plain/`.
