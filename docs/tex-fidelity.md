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
    one list; exhausted token lists are removed first (as before a token
    is backed up), so tail calls do not grow the input stack.
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
  - `\topmark`, `\firstmark` and `\botmark` expand to nothing (no page
    is ever built); `\splitfirstmark` and `\splitbotmark` to what
    `\vsplit` set (see Lists and nodes).  Tracing
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
    and pages.  Those last read TeX's semantic nest (`nest.lisp`): mode,
    `\prevdepth` (−1000pt at first), `\spacefactor` (each "Improper"
    outside its mode), `\prevgraf`, and the last node of the list
    (penalty, kern, glue or other, see Lists and nodes); an empty main
    vertical list shows the page builder's last values.  No page is ever started, so `\pagegoal` is
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
  `main-control.lisp`, `log.lisp`, `messages.lisp`, `streams.lisp`,
  `nodes.lisp`, `list-commands.lisp`), §§1029-1298, 1335, 1340-1375:
  - *Every primitive has one disposition* (`command-disposition`):
    expandable, main control's own, or an event (it appends the node of
    an event); every primitive of the latter two has an operation, which
    main control runs (a primitive meaning's own, so that the frozen
    `\endtemplate`'s, which no name reaches, runs too).
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
    mode, `\vbox`, `\vtop`), math-shift and math (subformulas)
    groups; the others are opened by the commands that need them
    (disc, insert, vcenter, math-choice, math-left) and by alignments.  `}` ends each as handle_right_brace does ("Too many }'s",
    "Extra }, or forgotten \endgroup/$/\right"); `\endgroup` and `$`
    ending the wrong group go through off_save ("Extra x", "Missing }
    inserted", "Missing \endgroup inserted", "Missing $ inserted").
    `\aftergroup` tokens are put back in the order they were saved;
    outside every group they are forgotten.
  - *Modes and the nest*: a paragraph begins with `\everypar` (after
    `\parskip` glue in the enclosing list and the indentation node in
    its own) and ends with normal_paragraph (`\looseness`,
    `\hangindent`, `\hangafter`, `\parshape` reset locally, ignoring
    `\globaldefs`).  `\hbox`, `\vbox` and `\vtop` read `to`/`spread`,
    push restricted horizontal or internal vertical mode with
    `\everyhbox`/`\everyvbox` (a `\vbox` also normal_paragraph) and at
    their `}` end the paragraph inside and make a box; `\setbox` puts it
    in the register; anywhere else it becomes a box node, after which
    the list's `\spacefactor` is 1000 or its `\prevdepth` the box's
    depth (`\indent` in a paragraph sets the space factor too).  `\box`,
    `\copy`, `\vsplit` and `\lastbox` give a box that exists (`\box`
    voids the register at its own level; see Lists and nodes).
    `$` reads the next token unexpanded: `$$` in a paragraph is a display
    (with `\everydisplay`, `\displaywidth` and `\displayindent` from
    `\parshape` or `\hangindent`/`\hangafter`), anything else inline
    math (with `\everymath`); `\fam` is -1 inside.  A display must end
    with `$$` ("Display math should end with $$"); the paragraph then
    resumes three lines further on, after an optional space, as a new
    paragraph node.  Math
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
  - *Input, output and messages.*  What TeX prints goes to the job's
    log (`job-log`, entries `log-entry`, each also signalled as a
    `job-output` condition), one string per entry: TeX's line breaking
    and `\newlinechar` are not kept.  `\message` and `\errmessage`
    expand their text as `\edef` does; `\errmessage` is also a TeX
    error whose message is the text, and its entry keeps `\errhelp` (TeX's
    fixed help, used when `\errhelp` is empty, is not kept).
    `\show` (the next token, unexpanded, and its meaning) and `\showthe`
    are logged as `:show` entries and not signalled as errors (TeX's
    error there only stops an interactive run); their text is what
    follows `> `, without the final `.`.
    `\uppercase`/`\lowercase` map character tokens of every category,
    and active characters, by `\uccode`/`\lccode` when that is not 0,
    and leave other control sequences; the result is read next.
    `\openin` finds its file through the resolver, as `\input` (a file
    not found leaves the stream closed, for `\ifeof`); `\closein` closes
    it.  `\read` (read_toks) reads whole lines, under the catcodes and
    `\endlinechar` in force, until braces balance: a right brace that
    closes more than was opened ends the line and drops its rest; at the
    end of the file the stream closes and the (empty) line read gives
    `\par`, with "File ended within \read" if braces are open; an
    `\outer` macro on a line becomes a space and is not read again
    (§339).  The result is a macro without parameters ("Missing `to'
    inserted").  A stream not open, or one outside 0..15, is the
    terminal, which a job has not: the fatal "*** (cannot \read from
    terminal in nonstop modes)".  A line of `\read` is tokenized as soon
    as it is read; nothing can change catcodes while it is absorbed.
    `\openout`, `\write` and `\closeout` are whatsits: events
    (`docs/events.md`) with the stream (`\write` and `\closeout`: 17 for
    a negative number, 16 above 15) and the file name or the unexpanded
    token list; TeX carries them out when the page holding them is
    shipped out.  After
    `\immediate` (anything else after it is read again) they are carried
    out at once: a stream 0..15 opens or closes (nothing is written to
    disk; an event with `:immediate t` records it; streams 16 and 17
    close nothing and emit no event), and a `\write`'s text is
    expanded as TeX's write_out does (in braces, then the frozen
    `\outer` `\endwrite`: "Unbalanced write command" for too many right
    braces, a runaway for too many left ones; mode none, so `\ifvmode`
    and its friends are false, and `\setbox` is "Improper"), then
    becomes an event with `:text` when its stream is open, else a
    `:write` log entry with the stream number (17: the log only).
- Lists and nodes (`src/expand/`: `nodes.lisp`, `list-commands.lisp`,
  with `modes.lisp`, `boxes.lisp`, `discretionaries.lisp`, `inserts.lisp`,
  `whatsits.lisp` and `show-lists.lisp`), §§180-198, 218, 638-640,
  977-979, 1034-1044, 1056-1061, 1071-1125, 1293-1298, 1354, 1366-1377:
  each list of the nest keeps its nodes, as
  TeX's tail_append adds them, and what TeX reads back of the last one
  (§424: `\lastpenalty`, `\lastkern`, `\lastskip`) is read from them.
  The job's events are the outer vertical list's nodes, flattened
  (`docs/events.md`).  Each primitive, and what it appends:
  - *Characters* (a letter or other character, `\char`, a `\chardef`
    or a control sequence `\let` to one) in horizontal mode: TeX's main
    loop without ligatures and kerns (which need metrics), so
    `\noboundary` does nothing.  `\sfcode` sets `\spacefactor`
    (adjust_space_factor); in a paragraph (not in a restricted box) a
    `\language` other than the paragraph's current one first appends a
    `:language` whatsit with the hyphenation minimums (fix_language).
    A character extends the `:text` node that ends the list when it has
    the same font and its span is in the same file and not before the
    node's end; else it begins a new one.  The style is the font's file
    and size (`cmr10`, `cmr10 at 12.0pt`, `cmr10 scaled 1200`).
  - *Spaces*: a blank in horizontal mode and `\ ` anywhere append a
    `:space` node holding app_space's glue: `\xspaceskip` at a space
    factor of 2000 or more, else `\spaceskip` or the font's
    `\fontdimen` 2-4 (0 unless assigned), the width plus `\fontdimen` 7
    at 2000 or more, the stretch and shrink scaled by the space factor
    (`xn_over_d`); `\ ` and a space factor of 1000 take the glue
    unscaled.  A glue of zero width, stretch and shrink counts as
    zero_glue (trap_zero_glue).
  - *Paragraphs*: `\par` (and what ends a paragraph) makes the
    horizontal list one `:paragraph` node of the enclosing vertical
    list, without its final glue (§816); an empty list makes none.
    TeX's `\parfillskip`, `\leftskip`, `\rightskip` and interline glue
    are layout and not kept.  Math is a `:math` node (`:display t` in
    the vertical list for a display), its nodes those of the math list
    (see *Math lists*).
  - *Glue, kerns, penalties, rules*: `\hskip`, `\vskip` and the
    `fil`/`fill`/`ss`/`filneg` commands make `:glue` nodes, `\kern`
    `:kern`, `\penalty` `:penalty`, `\hrule`/`\vrule` `:rule` with
    scan_rule_spec's dimensions (an `\hrule` 0.4pt high, a `\vrule` 0.4pt
    wide, the rest running; then `\prevdepth` is ignore_depth or the
    space factor 1000); `\/` a kern of 0 after a character (and always
    in math), since the italic correction needs metrics.  The keywords
    of a rule are scanned with expansion, before it is appended.
  - *Removing*: `\unskip`, `\unkern` and `\unpenalty` remove the last
    node when it is glue (a space or leaders too), a kern or a penalty.
  - *The page builder's traces*: where TeX runs build_page (after a
    paragraph, a box or a penalty in the outer vertical list, after a
    display), the list's nodes stay in it (they are the job's output) but
    count as moved to the page: the list reads as empty, and the page's
    last glue, penalty and kern are those of its last node (§996), which
    `\lastskip` and friends then read.  From an empty outer list
    `\unkern` and `\unpenalty` are "You can't use", and so is `\unskip`
    when the page's last node was glue.
  - *Boxes* placed in a list are `:box` nodes (kind, command, spec,
    assigned dimensions) whose children are the box's list; the span is
    where the box was made.  `\raise`/`\lower` (horizontal and math
    modes) and `\moveleft`/`\moveright` (vertical) scan a dimension and
    a box, placed with `:shift` (down or right positive: `\raise` and
    `\moveleft` negate).  `\box`, `\copy`, `\vsplit` and `\lastbox`
    add their span to the box's `:via`, newest first (it stays with the
    box through registers).  What leaves a register for a list without
    voiding it (`\copy`, `\unhcopy`, `\unvcopy`) is a deep copy, so a
    list's text never grows the register's.
  - *Unboxing* (§1110): `\unhbox`/`\unhcopy` in horizontal mode and
    `\unvbox`/`\unvcopy` in vertical mode splice the register's nodes
    (copies) into the current list, each with the command's span added
    to its `:via`; a void register gives nothing; any other kind of
    box, and math mode, are "Incompatible list can't be unboxed" and
    the register is kept.  `\unhbox` voids it.  A text node that came
    from a box is never extended by later characters.
  - *`\lastbox`* (§§1080-1081) removes the last node of the current list
    when it is a box, its shift dropped, or a paragraph, taken as the
    `\hbox` of its contents that TeX's one line would be; else the box
    is void.  In math mode, and from an empty outer vertical list (also
    after build_page), it is "You can't use" and void.
  - *`\mark{…}`* (§1101): its text expanded as `\edef`'s, a `:tex-mark`
    node holding the tokens.  `\vsplit` (§§977-979, 1082: "Missing `to'
    inserted"; "\vsplit needs a \vbox" for an `\hbox`, which stays)
    takes the whole box, voiding the register, and sets
    `\splitfirstmark`/`\splitbotmark` to the first and last marks of
    its list, counting those that TeX's line breaking or an adjusted
    `\hbox` (one placed or moved in vertical mode, §§655, 1083) would
    have moved out of
    a paragraph or box at its top level; nodes stay where they were
    appended.  Both marks are cleared first.
  - *Leaders* (§1078): `\leaders`, `\cleaders` and `\xleaders` scan a
    box (or a rule), then, expanding, skip blanks and `\relax`: a glue
    command of the mode (`\hskip` family outside vertical mode, `\vskip`
    family inside it) makes a `:leaders` node (`:kind`, the glue, the
    glue's command) whose child is the box or rule; anything else is
    "Leaders not followed by proper glue", read again, the leaders
    dropped.  A void box makes no leaders, and the glue is then plain
    glue.  Leaders are glue for `\lastskip`, `\unskip` and a paragraph's
    final glue.
  - *Discretionaries* (§§1117-1121): `\-` and `\discretionary` append a
    `:discretionary` node whose children are its non-empty lists,
    `:pre-break`, `:post-break` and `:no-break`.  `\-` pre-breaks the
    font's `\hyphenchar` when it is 0-255 (`-` for INITEX's
    `\nullfont`, §552).  `\discretionary` reads three disc groups (each
    `{` after blanks and `\relax`, each list restricted horizontal at
    space factor 1000).  A list is pruned at its first node other than
    a character, box (the indentation too), rule or kern: that node and
    the rest are deleted, "Improper discretionary list" and a
    `:diagnostic` log entry showing them (§1121).  A non-empty no-break
    list is "Illegal math \discretionary" in math, and dropped; one of
    more than 255 nodes (each character one) is "Discretionary list is
    too long", and its nodes follow the disc node as ordinary ones.
    TeX puts the no-break list after the disc node (replace_count); here
    it is nested, with the same effect on every command reading the
    list's end: `\lastkern` and friends and `\/` see the no-break
    list's last node, while `\unskip`, `\unkern`, `\unpenalty` and
    `\lastbox` do not take it (§§424, 1080, 1105, 1113), and characters
    after the node begin a new `:text` node.
  - *`\accent`* (§§1122-1125) in horizontal mode (in math it is
    `\mathaccent`'s, see *Math lists*):
    the accent's code, then do_assignments (blanks, `\relax` and
    assignments, `\setbox` "Improper"), then a character, `\chardef` or
    `\char` is the accented character, anything else read again.  An
    `:accent` node holds the accent's `:text` node (in the font before
    the assignments) and the character's (in the font after them); its
    last node for `\lastkern` and `\/` is the character.  The space
    factor becomes 1000; TeX's kerns are 0 without metrics and not kept.
  - *`\insert n{…}`* and *`\vadjust{…}`* (§§1097-1100): an insert group
    and an internal vertical list (normal_paragraph first,
    `\prevdepth` ignored); "You can't \insert255" makes it `\insert0`;
    `\vadjust` is illegal in vertical mode.  At the `}` the paragraph
    inside ends and the list is an `:insert` node (number, and the
    `\splittopskip`, `\splitmaxdepth` and `\floatingpenalty` in force
    inside the group) or a `:vadjust` node; in the outer list the page
    builder's traces follow.  Both stay where appended.  `\vsplit`'s
    marks include those at the top of a `\vadjust`'s list in a
    paragraph, an adjusted `\hbox` or a display, and those of math in
    them (math becomes part of the list it is in; §§655, 1199).
  - *Whatsits*: the deferred `\openout`, `\write` and `\closeout` are
    nodes of the current list, so a box holds them; the `\immediate`
    ones are nodes of the outer list, appended when they are carried
    out.  `\special` is a `:special` node of its text, expanded at once
    (§1354).  `\setlanguage n` (horizontal modes only, else "You can't
    use") is a `:language` node as fix_language's, `n` outside 1-255
    being 0, and it becomes the list's current language (§1377).
  - *`\shipout`* (§§638-640, 1366-1374) scans a box (only a box: "A
    <box> was supposed to be here"); a void one is nothing.  The box
    becomes a `:shipout` node of the outer vertical list, wherever
    `\shipout` is read, then its `\openout`, `\write` and `\closeout`
    nodes are carried out as `\immediate` would (`docs/events.md`:
    events flagged `:shipout`, or log entries), in the order hlist_out
    and vlist_out meet them: depth first through boxes, paragraphs (as
    their lines), math and no-break lists, not leaders, inserts or break
    lists; a `\vadjust`'s list (also one in math) after the paragraph,
    adjusted `\hbox` or display holding it.  The writes expand under the state of the moment.  Then
    `\deadcycles` is 0.  With `\tracingoutput` positive the box is
    shown in a `:diagnostic` log entry.  The `[\count0]` TeX prints on
    the terminal is not kept.
  - *Math lists* (`math-lists.lisp`, §§1136-1199) hold TeX's noads,
    never converted to boxes (mlist_to_hlist needs metrics).  A
    character, `\char`, `\mathchar`, a `\mathchardef` or `\delimiter`
    (its code divided by 4096) is a noad of its math code's class whose
    nucleus is a `:math-char`; the family is `\fam` for a variable code
    (class 7, an ord noad) when `\fam` is 0-15, as set_math_char
    resolves it; math code `"8000` reads the character again as active.
    A field (scan_math, after blanks and `\relax`) is a math character
    or a subformula in braces ("Missing { inserted" otherwise), read in a
    math group; at its `}` a subformula of one ord noad without scripts
    gives its nucleus, and one accent noad as the nucleus of the ord noad
    ending the list replaces it (§1187).  `{` in math is an ord noad of
    its subformula.  `^`/`_` script the noad or fraction ending the list,
    else a new ord noad ("Double superscript"/"Double subscript" when the
    script is there, even `{}`).  `\mathord` … `\mathinner`,
    `\underline`, `\overline` make a noad of their class; `\limits`,
    `\nolimits`, `\displaylimits` set an op noad's limits ("Limit
    controls must follow a math operator"); `\radical` scans a 27-bit
    delimiter, `\mathaccent` (and `\accent`: "Please use \mathaccent
    for accents in math mode") a 15-bit character; `\vcenter` reads a
    vbox (as `\vbox`, in a vcenter group) for its nucleus; a box or
    `\indent` is an ord noad of it.  Delimiters (scan_delimiter: a
    character's `\delcode` or `\delimiter`; else, or negative, "Missing
    delimiter (. inserted)", read again, and the null delimiter) are
    four numbers.  `\over`, `\atop`, `\above` and the `withdelims`
    forms make the list the numerator of the list's incompleat fraction,
    whose denominator is the rest of the list (fin_mlist); a second is
    "Ambiguous; you need another { and }", its operands scanned.
    `\left` opens a math-left group whose list `\right` ends as an
    inner noad (left delimiter, list, right delimiter; "Extra \right"
    outside one, off_save in other groups).  `\mathchoice` reads four
    lists in math-choice groups; the style commands, `\nonscript` (zero
    glue), `\mskip` (mu glue) and `\mkern` (a mu kern) are nodes.  In a
    display `\eqno`/`\leqno` (privileged, in the display's own group,
    else off_save) begins inline math whose `$` ends the display too
    ("Display math should end with $$"): the number is the display's
    last child.  Math fonts are checked at each `$`, as before.
  - *`\showbox n`* and *`\showlists`* (§§180-198, 218-219, 1293-1298)
    are `:show` log entries, like `\show`'s (not errors).  The format
    is our own, since nodes have no dimensions: each node on a line, as
    its event without spans after a `.` per level, levels deeper than
    `\showboxdepth` as ` []`, nodes beyond `\showboxbreadth` (5 when
    not positive) as `etc.`.  `\showbox` shows `\box n=` and the box or
    `void`; `\showlists` each list of the nest, innermost first: `###
    <mode> entered at line n` (a paragraph's hyphenation data unless
    TeX's defaults), its nodes, then `prevdepth`/`prevgraf` or
    `spacefactor` and the current language, as TeX's.  Of the outer
    list only TeX's "recent contributions" are shown (the nodes not
    yet on the page); no page is kept.
  Every node appended (and each character added to a `:text` node) is
  signalled as `job-output`.
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
- Alignments (`src/expand/alignments.lisp`), §§768-812, 1126-1131,
  1206, as TeX carries them out, never by splitting the text on `&`:
  - *The preamble*: `\halign` or `\valign` pushes an alignment (TeX's
    alignment stack, saving align_state) and a list (internal vertical,
    or restricted horizontal), reads `to`/`spread` in a first alignment
    group, then the preamble with the scanner status `:aligning` (an
    `\outer` macro or the end of the file is a runaway) at align_state
    -1000000: u templates up to `#` (leading blanks dropped; `&` first
    makes the columns from there on repeat), v templates up to `&` or
    `\cr` at that brace level, each ended by the frozen `\endtemplate`;
    `\span` expands the next token once, `\tabskip` assignments are
    carried out (local to the alignment's group) and each column gets the
    glue in force after it; "Missing # inserted in alignment preamble",
    "Only one # is allowed per tab".  Then a second alignment group
    (each entry's: restarted at every entry's end), `\everycr`, and
    align_peek.
  - *align_peek*, after the preamble, every `\cr` and every `\noalign`,
    skips blanks (not `\relax`, which begins a row): `\noalign` begins
    its group (`normal_paragraph` in an `\halign`), `}` ends the
    alignment, `\crcr` is ignored, anything else begins a row and is the
    first token of its first entry.
  - *Entries*: a row and each entry are lists of the nest (the row's of
    the other orientation).  An entry's first token, if not `\omit`, is
    read again after its column's u template; the end of the u template
    sets align_state to 0, so that `&`, `\span`, `\cr` or `\crcr` (or a
    token `\let` to `&`) at the entry's own brace level is caught by
    get_next, dropped, and replaced by the column's v template (after
    `\omit`, `\endtemplate` alone).  `\endtemplate` counts as `\outer`
    while the scanner is not `:normal`, and becomes endv: do_endv checks
    that it ended the v template on top of the input stack (else TeX's
    fatal "interwoven alignment preambles are not allowed", as when a
    template's end finds align_state out of step), ends a paragraph, and
    ends the entry (fin_col) unless `\span` joins the next column into
    it; at `\cr` the row ends (fin_row) and `\everycr` follows.  In
    another group, what ends that group is inserted first (off_save).
    A repeating preamble grows by one column whenever an entry needs
    one; without one an extra `&` is "Extra alignment tab has been
    changed to \cr".  A `}` at an entry's level is "Missing \cr
    inserted".
  - *Misplaced commands*: `&`, `\span`, `\cr` and `\crcr` outside
    entries are "Misplaced" (align_error), or, within two braces of an
    entry's level, "Missing { inserted" or "Missing } inserted" to
    reach it; `\noalign` and `\omit` are "Misplaced".  `\halign` begins
    an alignment in vertical mode and in a display, `\valign` in
    horizontal mode; otherwise the modes' rules apply (a paragraph
    begins or ends first; "You can't use" in inline math; in a group of
    the display, off_save).
  - *The end*: the two alignment groups end, the alignment is popped
    (align_state restored), and its node (with its preamble, rows and
    `\noalign` material, `docs/events.md`) goes into the enclosing list,
    which takes the alignment list's `\prevdepth` or `\spacefactor`.  A
    row's depth is 0 (no metrics).  In a display (which must hold
    nothing else: "Improper \halign inside $$'s" flushes it) assignments
    may follow, then `$$` ("Missing $$ inserted", "Display math should
    end with $$"); the node, `:display t`, goes into the vertical list
    and the paragraph resumes, as after a display.

## Not emulated (no typesetting)

- **No font metrics.** Characters have no width, height or depth.
  `\fontdimen` returns what was assigned, else 0.  Every character code
  0-255 is taken to exist in every font, so TeX's new_character never
  fails (`\-`, `\accent`, discretionaries).
- **Boxes hold nodes, not dimensions.** `\box`, `\copy`, `\unhbox` and
  `\unvbox` replay the nodes. `\lastbox` removes the last box node.
  `\vsplit` takes the whole box. `\wd`, `\ht` and `\dp` are 0 unless
  assigned.
- No line breaking and no page builder. `\pagetotal` and `\prevdepth` are 0.
  A paragraph counts as one line (`\prevgraf`), its paragraph node, of
  depth 0; `\predisplaysize` is 0pt after a nonempty paragraph.  `\end`
  never waits for the page builder or `\output`.
  `\lastskip`, `\lastpenalty` and `\lastkern` look at the last node of the
  current list, or of the page (see Lists and nodes). `\output` is stored and never run; `\shipout` makes no DVI (see
  Lists and nodes).
- **Alignments are not packaged.** No column widths, no setting of the
  `\tabskip` glue and no unset boxes (§§801-810): an alignment is a node
  of its preamble, rows and cells; `to`/`spread` is kept as data.  The
  `\vadjust`, `\insert` and `\mark` material of an `\halign`'s entry
  stays in its cell (no hpack), which the readers that care (`\vsplit`'s
  marks, whatsits at `\shipout`) treat as an adjusted `\hbox`'s.
- `\write` and `\openout` write nothing; writes are events, and
  `\immediate\write`s to no open file are log entries.

These choices only affect layout code in `setup-*.tex`, such as running
heads (`\comline`) and `\Vskip`. They are checked against every
dimension-dependent branch the setup files take; each one has a test.

## Jobs

Each chapter file `chap-N.tex` (N a number or a letter) is a separate TeX
job (`chapter-jobs`); `chap-0-edit-history.tex` is not one, `chap-0`
inputs it. Its `\jobname` is the chapter name.
Every job starts from a snapshot of the state after Knuth's `plain.tex` and
`hyphen.tex` were run through our expander. Those files are vendored
unmodified in `vendor/plain/`, with their provenance and licence in
`vendor/PROVENANCE.md`; `patches/` never applies to them. Jobs read inputs
along the source search path: the spec tree, then `vendor/plain/`; a file
of the spec tree is read as the patch set patches it (`docs/architecture.md`,
"Sources"), in memory, with the file's own name in spans. A file
a TeX run of the spec writes and a later run reads (`chap-N.fig`,
`chap-N.tc`, `\jobname.toc`, `.idx`, `.iss`, `.ref`, `.sec`:
`generated-file-name-p`, `src/source.lisp`) is an empty source when
the trees do not hold it, as on a first run.

Every job runs to its `\end` without a fatal error. The sources have errors
TeX itself would report, which patches fix (`patches/`): concept-syntax.tex
comments out the group that defines `\w`, `\c`, `\SE`, … but not its
closing brace, and the table at :279-302 uses them (0001). Two rules are
left unbalanced by the sources, which the semantic layer reports, not TeX: the numeric-accumulation rule of dict-iteration.tex
breaks a row inside `\curly` (0002) and the defsetf lambda list of
concept-bvl.tex lacks its `\rparen` (0003). With the patches, no job has an
error or an unbalanced report.

Formats and jobs (`src/expand/format.lisp`), §§1299-1337:

- *The format.*  `load-plain-format` runs an INITEX job `plain` that
  reads `plain.tex` (which inputs `hyphen.tex`) and then an inserted
  `\dump`, as `initex plain \dump` reads the rest of its first line after
  the file.  So final_cleanup's checks are TeX's: `\dump` inside a group
  is fatal, open conditionals are noted, and the trie becomes ready.  The
  format must load clean: any TeX error or note, or an end other than
  `\dump`, is a Lisp `format-error`.  Loading takes about 20 ms, so nothing
  is cached; a caller keeps the format it loaded.
- *What it keeps* (`tex-format`): the expander state at the `\dump`
  (meanings, registers, parameters, codes, fonts, `\parshape`, the
  reader's catcodes, case codes and interned names), the frozen control
  sequences and font identifiers made so far, the patterns and
  exceptions (so a job's `\patterns` is "Too late for \patterns"), and
  the interaction mode (TeX dumps it, §1326).  `\fmtname` is plain's own
  macro.
- *A job* (`make-job`) works on a copy of the format's state and never
  shares anything mutable with the format or another job: every table is
  copied; each font is copied once and the copy used wherever the font
  appears (meanings, the font tables, `\nullfont`, the loaded fonts, the
  font identifiers); box registers (`\strutbox`) are copied as `\copy`
  does.  Control sequences, tokens, token lists, glue and the other
  meanings are immutable and shared.  Everything else is fresh, as after
  TeX's load_fmt_file: an empty input stack, nest and page, no marks,
  conditionals or open streams, align_state 1000000, an empty log.
- *Starting it* (`start-job`): the job's file is pushed, then
  `\everyjob` is inserted on top of it (§1337), so it is read first.
- Tokens of plain's macros keep their spans into `plain.tex`, the file
  name the resolver gives.
