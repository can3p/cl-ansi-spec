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
- Scanning (`src/expand/`: `scan.lisp`, `internal.lisp`,
  `dimen-scan.lisp`, `toks.lisp`, `nest.lisp`), §§402-479:
  - *Tokens are compared as TeX compares them*: signs, digits, `=`, the
    decimal point and keyword letters only as character tokens (a `\let`
    copy does not count; keyword letters of any category do); blanks,
    braces and `\relax` by meaning, so `\let` copies count.  A keyword
    that fails to match puts back what it read, but not the blanks
    before its first letter.
  - *Integers*: decimal, octal, hexadecimal (`A`–`F` of category 11 or
    12), alphabetic constants (a character, active character or
    one-character control sequence, else `Improper alphabetic constant`
    and 48), one optional space after a constant, `Number too big` (the
    value is 2³¹−1), `Missing number, treated as zero`; the bounded
    scanners (register, character, family, math character, delimiter)
    report TeX's message and give 0.
  - *Dimensions and glue*: every unit in TeX's order of trial, `true`
    through `prepare_mag` (its errors reset `\mag` globally), em/ex from
    the current font's `\fontdimen` 6 and 5, an internal quantity as the
    unit, mu, fil/fill/filll, the units TeX inserts after `Illegal unit
    of measure`, `Dimension too large`.  Glue reads `plus` and `minus`;
    a mu/non-mu mismatch is `Incompatible glue units`, and the value
    keeps the kind that was asked for.
  - *Internal quantities* (scan_something_internal) at their level, with
    TeX's coercion (glue to its width, mu glue after an error, dimen to
    sp) and negation: registers and their shorthands, parameters, codes,
    `\parshape`, font identifiers and family fonts, `\fontdimen`,
    `\hyphenchar`, `\skewchar`, `\inputlineno`, and what belongs to lists
    and pages.  Those last read TeX's semantic nest, kept without its
    lists (`nest.lisp`): mode, `\prevdepth` (−1000pt at first),
    `\spacefactor` (each "Improper" outside its mode), `\prevgraf`, and
    the last node of the list (penalty, kern, glue or other), which the
    event layer records; an empty main vertical list shows the page
    builder's last values.  No page is ever started, so `\pagegoal` is
    `\maxdimen` and the other page totals 0; `\badness` is 0.  `\wd`,
    `\ht` and `\dp` go through the generic function `box-dimension` and
    its setter (a void box reads 0 and ignores assignments); the box
    layer adds the methods for its boxes.
  - *`\fontdimen` without metrics*: `\nullfont` has TeX's 7 parameters
    and grows only while no font has been loaded; a font loaded by
    `\font` has unknown parameters, so any number from 1 is accepted
    (TeX would know the count from the TFM; the sources, typeset by TeX,
    never take that error path).  An unassigned parameter is 0, so
    `\kern\fontdimen2\font` is 0pt.
  - *`\the`* of a font gives a frozen identifier token whose meaning is
    always that font; `\fontname` shows the `at` size only, as `\meaning`
    does.
  - *Token lists* (`scan-toks`): a definition's parameter text (match
    tokens, `#{`, `Parameters must be numbered consecutively`, `You
    already have nine parameters`) and body (`#n`, `##`, `Illegal
    parameter number`), or a general text after its left brace; with
    expansion, `\noexpand`-ed tokens stay and what `\the` gives is not
    expanded again.  Every definition and general text of main control
    goes through it.
- Conditionals (`src/expand/conditionals.lisp`), §§487-510:
  - *The condition stack* holds one entry per open conditional, innermost
    first: its test, the line it began on, and its limit (what may end
    it next: `\else`/`\fi` after a true test, `\or` in `\ifcase`,
    `\fi` after `\else`).  A test may leave conditionals of its own open
    (`\ifnum\iftrue 1\else 2\fi=1`); skipping closes them by their `\fi`.
  - *Skipping* reads without expansion and counts nested conditionals,
    with the scanner status `:skipping`: an `\outer` macro or the end of
    a file there is "Incomplete \ifx; all text was ignored after line N"
    and a `\fi` is inserted.
  - *`\fi`, `\else`, `\or`* end the innermost conditional (skipping to
    its `\fi`); met while its test is still read they insert `\relax`
    before themselves; otherwise they are "Extra" and dropped, as is an
    `\or` that ends the false branch of a test that is not `\ifcase`.
  - *The tests*: `\if`/`\ifcat` expand and compare code or category, a
    control sequence `\let` to a character counting as it and a
    `\noexpand`-ed active character as itself, anything else as
    (\relax, 256); `\ifx` reads two tokens unexpanded (an `\outer` macro
    allowed) and compares meanings, a `\noexpand`-ed token equalling only
    another; `\ifnum`/`\ifdim` with "Missing = inserted"; `\ifcase` counts
    only its own `\or`s.  Modes come from the nest (`\ifinner`: internal
    vertical, restricted horizontal, inline math; mode `:none` makes all
    four mode tests false).  `\ifvoid`/`\ifhbox`/`\ifvbox` ask the
    generic function `box-kind` (void is NIL); `\ifeof` reads the
    expander's table of the sixteen read streams, all closed until
    `\openin` opens one.
- Main control (`src/expand/`: `commands.lisp`, `groups.lisp`,
  `modes.lisp`, `boxes.lisp`, `prefixed.lisp`, `assignments.lisp`,
  `main-control.lisp`), §§1029-1280, 1335:
  - *Every primitive has one disposition* (`command-disposition`):
    expandable, main control's own, an event, or an alignment command.
    What main control does not carry out yet is handed on as the
    condition `unhandled-command` (with its token, disposition and
    mode), which `make expand` prints; nothing is dropped unseen.
  - *TeX's cases by mode* come first: in vertical mode a character,
    `\char`, `$`, `\hskip`, `\unhbox`, `\vrule`, `\valign`, ... back up
    and begin a paragraph; in a paragraph `\vskip`, `\hrule`, `\end`,
    `\halign`, ... insert `\par` (in a restricted horizontal box the box
    must end first: off_save); math-only commands outside math and
    `\par`, `\vskip`, ... inside it are "Missing $ inserted"; `#`,
    `\lastskip` and friends, `\raise` in vertical mode, `\moveleft` in
    horizontal or math mode, `\vadjust` and `\/` in vertical mode and
    `\eqno` outside math or in inline math are "You can't use x in y
    mode".  TeX's limit of 100 errors per paragraph is not kept: every
    job recovers from every error.
  - *prefixed_command*, all of it: `\global`, `\long`, `\outer` with
    "You can't use a prefix with" (the token is read again) and "You
    can't use `\long' or `\outer' with"; `\globaldefs` applied once,
    before the assignment (so `\gdef` is local when it is negative);
    get_r_token with "Missing control sequence inserted" and
    `\inaccessible `; `\def`/`\gdef`/`\edef`/`\xdef`, `\let` (one optional
    `=` and one space) and `\futurelet`; the shorthand definitions (the
    name is `\relax` while its value is read); token registers and
    parameters, from another one or a general text, `\output` kept in
    braces; registers, parameters and register shorthands with
    `\advance`/`\multiply`/`\divide` ("Arithmetic overflow" leaves the
    value), "You can't use x after \advance"; codes with "Invalid code"
    and TeX's ranges (`\delcode` alone may be negative); family fonts;
    `\font` with its `at`/`scaled` errors, the name meaning `\nullfont`
    while the file is read, and the last name given to a font as its
    identifier; `\fontdimen`, `\hyphenchar`, `\skewchar` (global);
    `\setbox`; `\wd`/`\ht`/`\dp`, `\prevdepth`, `\spacefactor` ("Bad
    space factor"), `\prevgraf` ("Bad \prevgraf"), the page dimensions,
    `\deadcycles` and `\insertpenalties`, all outside the save stack;
    `\parshape`; `\patterns` (while the trie is not ready, that is until
    `\dump`; then "Too late for \patterns") and `\hyphenation`, kept as
    data with TeX's errors ("Nonletter", "Duplicate pattern", "Bad
    \patterns", "Not a letter", "Improper \hyphenation will be flushed");
    the interaction modes, recorded only.  `\afterassignment`'s token is
    put back after the assignment; for `\setbox` that is just after the
    box's `{`, before `\everyhbox` (§1279).
  - *Groups* are group records on the reader's save stack, with TeX's
    group codes (§269) and the line they began on.  Main control opens
    simple, semi-simple, box (`\hbox`, adjusted `\hbox` in vertical
    mode, `\vbox`, `\vtop`), math-shift and math (braces in math)
    groups; the others are opened by the commands of events and
    alignments.  `}` ends each as handle_right_brace does ("Too many }'s",
    "Extra }, or forgotten \endgroup/$/\right"); `\endgroup` and `$`
    ending the wrong group go through off_save ("Extra x", "Missing }
    inserted", "Missing \endgroup inserted", "Missing $ inserted").
    `\aftergroup` tokens are put back in the order they were saved;
    outside every group they are forgotten.
  - *Modes and the nest*: a paragraph begins with `\everypar` (after
    `\parskip` glue and the indentation box, recorded as the last nodes
    of their lists) and ends with normal_paragraph (`\looseness`,
    `\hangindent`, `\hangafter`, `\parshape` reset locally, ignoring
    `\globaldefs`).  `\hbox`, `\vbox` and `\vtop` read `to`/`spread`,
    push restricted horizontal or internal vertical mode with
    `\everyhbox`/`\everyvbox` (a `\vbox` also normal_paragraph) and at
    their `}` end the paragraph inside and make a box; `\setbox` puts it
    in the register; anywhere else placing it is an event, after which
    the list's `\spacefactor` is 1000 or its `\prevdepth` the box's
    depth (`\indent` in a paragraph sets the space factor too).  `\box`,
    `\copy` and `\vsplit` take a register's box (`\box` voids the
    register at its own level; `\vsplit` takes the whole box, voids the
    split marks, and gives a void box and an error for an `\hbox`).
    `$` reads the next token unexpanded: `$$` in a paragraph is a display
    (with `\everydisplay`, `\displaywidth` and `\displayindent` from
    `\parshape` or `\hangindent`/`\hangafter`), anything else inline
    math (with `\everymath`); `\fam` is -1 inside.  A display must end
    with `$$` ("Display math should end with $$"); the paragraph then
    resumes three lines further on, after an optional space.  Math
    without families 2 and 3 of enough parameters (`\nullfont`'s 7) is
    "Math formula deleted: Insufficient symbol/extension fonts".
  - `\relax`, `\ignorespaces`, `\endcsname` ("Extra \endcsname"),
    `\indent`/`\noindent`, `\par`, and `\end`/`\dump`, which end the job
    in an outer vertical mode with final_cleanup, which notes (a
    `tex-report`, not an error, as TeX's history is unchanged) "\end
    occurred inside a group at level N" and "\end occurred when \ifx on
    line N was incomplete"; `\dump` inside a group is fatal, and ends the trie's
    readiness for `\patterns`.  The end of all input before them is
    fatal: "*** (job aborted, no legal \end found)".
- Registers and parameters have INITEX defaults; TeX's integer,
  dimension and glue arithmetic is exact (see Quantities).
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

## Not emulated (no typesetting)

- **No font metrics.** Characters have no width, height or depth.
  `\fontdimen` returns what was assigned, else 0.
- **Boxes hold events, not dimensions.** `\box`, `\copy`, `\unhbox` and
  `\unvbox` replay the events. `\lastbox` removes the last box event.
  `\vsplit` takes the whole box. `\wd`, `\ht` and `\dp` are 0 unless
  assigned.
- No line breaking and no page builder. `\pagetotal` and `\prevdepth` are 0.
  A paragraph counts as one line (`\prevgraf`), ending in a line box of
  depth 0; `\predisplaysize` is 0pt after a nonempty paragraph.  `\end`
  never waits for the page builder or `\output`.
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
