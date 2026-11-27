# Semantic vocabulary

The vocabulary is how meaning survives expansion. It is a declared table of
the macros that carry meaning. Most come from `setup-*.tex`; a few come from
plain TeX. It is a data file (planned, step 13 of `docs/plan/m2.md`) with one entry per macro
(`make-entry`, `src/semantic/vocabulary.lisp`): the macro's name, the key
of its events, its kind and placement, a handler when it replaces the call,
and why it is in the table.

## Rules

- **Keyed on meanings, not names.** An entry names a macro; the macro
  *meaning* that name has is attached to the entry: the format's at job
  start, then each one a definition gives it (`observe-vocabulary`,
  `src/semantic/observe.lisp`). A call is recognised by its meaning, so
  `\let` copies, `\csname`-built calls and tokens inserted from
  `\halign` templates (`\misc{##}`, setup-tables.tex:8-9) are recognised.
  A `\def` wrapper (`\def\funref{\clref}`, setup-document.tex:75) is
  another macro and no entry by itself: the entry it calls is observed,
  after it (a tail call) or nested in it.
- **Reports.** Defining an entry's macro again is reported by name, with
  the span of the new definition and of the last one seen (none for the
  format's): `\caption` is defined twice, setup-aux.tex:706 and :737. The
  new meaning is attached too, and the old one stays. A meaning that
  already belongs to another entry (`\let` of one entry's macro to
  another's name) is reported and stays with the first entry. Reports
  are compared with the last definition *seen*: a group's end restoring
  a meaning is not one, and a definition run again (one a macro makes each
  time it is called, `\defsecrefs`) is not another one. A `:call` entry
  whose `:end` goes to another list than its `:begin` (a body that ends a
  paragraph or opens a box it does not close) is reported `:unbalanced`:
  such an entry must be `:block` or observed at another macro.
- **Kinds.** A `:call` entry (the default) is a `:begin` with the call's
  arguments when it is called and an `:end` when its body ends (see
  "Observers"), its span the body's last token. A `:mark` entry is one
  `:mark` event. Environments are pairs: an `:open` entry's call is a
  `:begin`, a `:close` entry's call the `:end` of the `:open` entry it
  names, both with their arguments. `\code`…`\endcode` (through
  `\screen!`), `\begincom`…`\endcom`, `\issue`…`\endissue` are
  environments; issues are ranges that may cross section boundaries.
- **Observe (default).** The macro expands as usual, so counters,
  `\gdef`s and flags stay exact (section numbers come from
  `\startSection`). The macro an entry names is its *observation point*,
  the one whose body holds the content, not necessarily the one the
  sources call: `\begincom` first changes catcodes, so its entry names
  `\dobegincom`.
- **Replace (exception).** An entry with a handler, a function
  `(observer expander token arguments)`, replaces the call: the body is
  not read, and the handler emits the events itself (`emit-event`) and
  does what the macro must still do. It is used only where expansion
  would hide content, for example editor notes that the options suppress.
  Each use is justified in the table.
- **Placement.** The `:begin` of an `:inline` `:call` entry waits until
  the first node of its content: it is placed just before the next node
  appended, or the next character added to a text node, in whatever
  list, except for what TeX adds by itself when a paragraph begins
  (`\parskip` glue, the indentation); so an inline entry used in vertical
  mode begins inside the paragraph it starts. With no such node it is
  placed with its end. A `:block` entry's `:begin`, and every other
  marker, is placed at once in the current list, after the begins still
  waiting. A body whose last token is the character that starts a
  paragraph ends before the paragraph begins (TeX reads that character
  again, from below the body): such an entry is empty.
- **Code** keeps its exact characters, spaces and lines: under
  `\obeylines` and `\obeyspaces` each line is a paragraph and each blank
  an interword space, checked by a round-trip test
  (`tests/semantic/observe.lisp`).
- **Cross-references** are entries: `\secref`, `\figref`/`\Figref`,
  `\DefineSection`, `\DefineFigure`, `\deffigrefs`/`\defsecrefs`, `\funref`,
  `\term`, …. Phase 4 resolves them from the `\Define*` events, not from the
  stale generated `setup-sections.tex`/`setup-figures.tex`.

## Observers

The expander knows nothing of the vocabulary. It offers observers, slots
of the expander that are NIL by default (`src/expand/expander.lisp`), and
markers, nodes that carry an event (`src/expand/nodes.lisp`):

- **`call-observer`** `(expander token macro arguments)` is called by
  `macro-call` once a call's arguments are matched, before its body is
  read. It returns an action, NIL (the body is read) or `:replace` (it is
  not, and no tag may be given), and a tag. A non-NIL tag goes on the
  body's token-list level.
- **`level-end-observer`** `(expander tag)` is called when that level is
  removed, which is TeX's own end of the body (§§324-325, 390): lazily,
  when a token is next wanted from below it, or when back_input or a later
  macro call removes it. A tail call therefore ends its caller before it
  begins, so an entry is observed at the macro whose body holds the
  content (its observation point); a body whose last command reads ahead
  (`\futurelet`, or a `\kern` scanning for a space) ends when it reads
  past. An empty body ends at once; bodies still being read when the job
  ends (`\end`, `\dump`) end with it, innermost first.
- **`definition-observer`** `(expander control-sequence meaning span)` is
  called after `\def`, `\gdef`, `\edef`, `\xdef`, `\let`, `\futurelet`
  and the shorthand definitions (`\chardef`, …).
- **`append-observer`** `(expander node list)` is called before a node is
  appended to a list (`append-node`), and before a character extends the
  text node ending a list (that node is passed). Markers it appends
  come first; a text node then no longer ends the list, so the character
  begins a new one.
- **Markers** (`append-marker`) are appended to a list like any node, but
  TeX never sees them, so observing never changes what TeX does: every
  read of a list's tail (`\lastskip` and friends, `\unskip`, `\unkern`,
  `\unpenalty`, `\lastbox`, `\/`, a script's or `\limits`' noad, the page
  builder) skips them (`list-tail`); the removing commands leave them in
  place; a discretionary's lists may hold them; a list holding only
  markers counts as empty (`list-empty-p`: no
  `\parskip` before a paragraph, an empty paragraph dropped, `$$` after
  it), and what such a dropped list or a flushed display (`\halign`
  inside `$$`) held of markers goes on to the enclosing list. Characters
  never join a text node across a marker. `\showlists` does not show them.

## Choosing entries

`make vocab` surveys the sources without expansion (package
`cl-ansi-spec/inventory`, `src/inventory/`). It lists, per job or for the
whole spec, every control sequence defined and used: where it is defined,
how (kind, prefixes, arity, alias), and how often it is used as text,
inside macro bodies and on uncertain lines; `NAME=` shows one macro with
its aliases. A macro that means something but is left to expand down to
presentational events is a bug.

The survey reads like TeX wherever reading does not depend on expansion,
and says where it cannot:

- **Definitions.** `\def`, `\gdef`, `\edef`, `\xdef` (with `\global`,
  `\long`, `\outer`), `\let` with or without `=`, `\chardef` and the
  other `…def`s (a literal value is kept), `\font` and plain's `\new…`
  allocations (`\newif\iffoo` also defines `\footrue` and `\foofalse`).
  `\def\a{\b}` is an alias of `\b`; so is `\let\a=\b`, whose target is
  not counted as a use since `\let` does not expand it. A definition
  inside a macro body is *nested* under that macro (`\secref`, made by
  `\defsecrefs`, setup-aux.tex:1118): it exists only once the outer macro
  runs.
- **Catcodes.** Literal top-level assignments (`\catcode` with a
  literal character and a number, `\active` or a `\chardef`'d name;
  `\obeylines`; `\obeyspaces`) are applied, scoped by groups, so reading
  stays exact (`!` as escape in chap-0.tex). Assignments inside macros
  are not executed: calling such a macro makes its characters unknown for
  the rest of the job. A line holding an unknown character that may be
  structural (escape, braces, letter, comment) is *uncertain*, and so is
  all on it. `\begincom` only makes `,` and `-` active, so the spec has no
  uncertain line today.
- **Inputs.** A job is a chapter file and what it inputs. `\input name`
  is followed; so is a call of an *input macro*, one with undelimited
  parameters whose body inputs one of them (`\includeDictionary{dict-x}`),
  its arguments being read as text first. An active character in a file
  name stands for itself (TeX would expand it). Each file is read once per
  job, since the conditionals that guard real repeats cannot be
  evaluated; missing (generated) files, repeats and computed names
  (`\input\jobname.toc`) are listed. Files no chapter job reads are
  checked by a test (`setup-boxfig.tex`, two commented-out appendices,
  `setup-amfont.tex`).

The survey's counts seed the invariants of the full runs: for each
vocabulary entry, its events equal its certain uses.
