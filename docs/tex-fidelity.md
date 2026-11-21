# TeX fidelity

What phases 1–3 do exactly as TeX does, and what they deliberately do not do.

## Exact

- Tokenisation: catcodes, `\endlinechar`, `^^` notation, states N/M/S, and
  the input stack (done, M1).
- Expansion: macros with full parameter matching, `\expandafter`,
  `\noexpand`, `\csname`, `\string`, `\meaning`, `\the`, `\number`,
  `\romannumeral`, `\input`, `\endinput`, and all of TeX82's conditionals.
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
