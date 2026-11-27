# Semantic vocabulary

The vocabulary is how meaning survives expansion. It is a declared table of
the macros that carry meaning. Most come from `setup-*.tex`; a few come from
plain TeX. It is a data file with one entry per macro. Each entry states its
mode and why it is in the table.

## Rules

- **Keyed on meanings, not names.** An entry is attached to the macro
  *meaning* it names. Aliases are therefore recognised
  (`\def\funref{\clref}`, setup-document.tex:61-75). Tokens inserted from
  `\halign` templates are recognised too (`\misc{##}`, setup-tables.tex:8-9).
  Redefining a vocabulary macro is reported (`\caption` is defined twice,
  setup-aux.tex:706 and :737).
- **Observe (default).** The semantic layer emits `:begin` with the
  arguments, parsed by the macro's own parameter text. It then lets the macro
  expand normally, so counters, `\gdef`s and flags stay exact (section
  numbers come from `\startSection`). It emits `:end` once the expansion is
  done. An entry may name a later macro in a chain as its *observation
  point*. For example, `\begincom` first changes catcodes and is observed at
  `\dobegincom`.
- **Replace (exception).** A Lisp handler reads the arguments and emits
  events itself. This is used only where expansion would hide content, for
  example editor notes that the options suppress. Each use is justified in
  the table.
- **Environments** are begin/end pairs: `\code`…`\endcode` (through
  `\screen!`), `\begincom`…`\endcom`, `\issue`…`\endissue`. Issues are
  ranges that may cross section boundaries. Code keeps its exact characters,
  spaces and lines; this is checked by golden round-trip tests.
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
