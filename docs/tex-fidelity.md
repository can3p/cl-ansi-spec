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
unmodified in `vendor/plain/` (planned) with their provenance.
