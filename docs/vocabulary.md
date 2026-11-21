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

## Choosing entries

`make vocab` (planned) lists every macro each file defines and
uses, its simple aliases, and the source counts of candidate entries. A
macro that means something but is left to expand down to presentational
events is a bug.
