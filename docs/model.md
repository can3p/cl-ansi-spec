# Document model

The product of the parser (phase 4, milestone M3). This page is the
**draft schema**. M3 refines it, and this page is updated in the same commit
as the code.

## Shape

The model is a tree of nodes. Each node has a kind, named fields, optional
children and a `:span`. The span gives the source file, line and offsets
(`docs/architecture.md`, principle 4). In Lisp, nodes are CLOS instances. The
plist notation below is the S-expression export. The JSON export follows the
rules in [exports.md](exports.md); for example, text becomes `{"kind": "text"}`
objects there.

The kinds are declared in `src/model/nodes-<area>.lisp`, one file per
area ("Node shapes" below); the tables here summarise them, and the
generated reference (`docs/model-reference.md` (planned)) has every
field.

### Document level

| Node | Fields | Children |
|------|--------|----------|
| `:document` | `:version` (`\rev` of `setup-version.tex`) | `:front-matter`, `:chapters` |
| `:chapter` | `:id`, `:number` (`"1"` … `"26"`, `"A"`; none for a simple chapter), `:title` | `:children`: blocks, sections, dictionary entries |
| `:section` | `:id` (the `\DefineSection` label), `:number` (e.g. `"14.1.2"`), `:level` (1–5), `:dictionary`, `:title` | `:children`: blocks, sections, dictionary entries, glossary groups |
| `:dictionary-entry` | `:id`, `:names`, `:entry-kind` (the `\ftype`, an enum) | `:parts` |
| `:part` | `:title` (the `\label` text), `:none` (true for "None.") | `:content`: blocks |
| `:glossary-group` | `:letter` | `:entries` |
| `:glossary-entry` | `:id`, `:term`, `:pronunciation`, `:parts-of-speech`, `:usages` | `:senses` (`:glossary-sense`: `:number`, `:parts-of-speech`, `:usages`, `:content`, `:examples`) |
| `:figure` | `:id`, `:number` (`"14-1"`), `:caption` | `:content`: a `:table` or blocks |

### Blocks

`:paragraph`, `:code-block` (`:lines` of `:code-line`, exact text),
`:table` (`:rows` → `:cells` → inlines), `:item-list` (`:items`, each a
`:label` and blocks), the signatures (`:operator-signature`,
`:setf-signature`, `:variable-signature`, `:type-signature`),
`:bnf-rule`, `:math` with `:display t`, `:editor-note` and
`:reviewer-note` (kept even though the options hide them, with
`:hidden t`), and the anchors `:issue-start`, `:issue-end` and
`:index-entry` when they stand between blocks.

### Inlines

A string is plain text. Other inlines:

- `(:term-ref :text "dotted list" :target (:glossary "dotted list"))`,
  with `:defining t` for `\newterm` and `:sense n` for `\meaning`
- `(:operator-ref :text "endp" :via :function :target (:entry "endp"))`:
  `:via` the macro (`\clref` `:any`, `\funref` `:function`, …)
- `(:section-ref :label "…" :target (:section "…"))`,
  `(:figure-ref :label "…" :target (:figure …))`, `(:this-section …)`,
  `(:next-figure …)`
- `(:param :name "list")`, `(:metavariable …)`, `(:format-directive …)`,
  `(:lambda-list-keyword …)`, `(:code …)`, `(:emphasis …)`,
  `(:strong …)`, `(:math …)`
- `(:evaluates-to)` and the other notation of examples (`:may-evaluate-to`,
  `:does-not-evaluate-to`, `:equivalent`, `(:output)`, `(:input …)`)
- `(:citation …)`: the title of a cited work
- `(:index-entry :index-kind k :text "…")`: an index entry (`k` one of
  `:ref`, `:keyref`, `:code`, `:keyword`, `:text`, `:term`, `:example`,
  `:package`), an anchor
- `(:issue-start :name "NAME")` and `(:issue-end :name "NAME")`. Issues
  are **ranges** and may cross block and section boundaries, so they are
  anchors, not containers.
- the notation of syntax: `:bnf-optional`, `:bnf-zero-or-more`,
  `:bnf-one-or-more`, `:bnf-group`, `:bnf-parenthesized`,
  `:bnf-bracketed`, `:bnf-interleave`, `:bnf-required`,
  `:bnf-repeat-previous`, `:bnf-indirection`, `:bnf-break`,
  `:bnf-caret`, `:angle-name`

### Math

`(:math :display t …)` holds a formula's list: `:math-noad` (`:class`,
`:limits`, `:delimiter`, `:nucleus`, `:superscript`, `:subscript`),
`:math-char` (`:text`, Unicode), `:math-fraction` (`:numerator`,
`:denominator`, `:no-rule`, delimiters), `:math-delimiter` (`\left`,
`\right`), `:math-style-change` and `:math-choice`; a display's
`:equation-number` likewise.

`:target` holds resolved references. An unresolved reference keeps
`:target nil` and is listed in the build report.

`kind` names the node kind and no field (`"kind"` in JSON), so what a
dictionary entry defines is its field `:entry-kind`.

## Identity

Every addressable node has a stable `:id`, derived from the sources (the
entry name, the `\DefineSection` label, the glossary term), never from
numbering. Exports and consumers link by id.

## Full example

Built from `dict-conses.tex:1702-1761` (spans shortened to the line):

```lisp
(:dictionary-entry
 :id "endp" :names ("endp") :entry-kind :function :span ("dict-conses.tex" 1702)
 :parts
 ((:part :title "Syntax"
   :content ((:operator-signature :operator :function :names ("endp")
              :lambda-list ((:param :name "list"))
              :values ((:param :name "generalized-boolean")))))
  (:part :title "Arguments and Values"
   :content
   ((:paragraph (:param :name "list") "—a " (:term-ref :text "list" :target (:glossary "list")) ","
                (:issue-start :name "DOTTED-LIST-ARGUMENTS:CLARIFY")
                " which might be a " (:term-ref :text "dotted list" :target (:glossary "dotted list"))
                " or a " (:term-ref :text "circular list" :target (:glossary "circular list")) "."
                (:issue-end :name "DOTTED-LIST-ARGUMENTS:CLARIFY"))
    (:paragraph (:param :name "generalized-boolean") "—a "
                (:term-ref :text "generalized boolean" :target (:glossary "generalized boolean")) ".")))
  (:part :title "Description"
   :content ((:paragraph "Returns " (:term-ref :text "true" :target (:glossary "true"))
                         " if " (:param :name "list") " is the "
                         (:term-ref :text "empty list" :target (:glossary "empty list")) ". …")))
  (:part :title "Examples"
   :content ((:code-block :lines ((:code-line :content (" (endp nil) " (:evaluates-to) " "
                                                          (:term-ref :text "true" …)))
                                  …))))
  (:part :title "Side Effects" :none t)
  (:part :title "Affected By" :none t)
  (:part :title "Exceptional Situations"
   :content ((:paragraph "Should signal an error of " (:operator-ref :text "type-error" :via :type …) "…")))
  (:part :title "See Also" :none t)
  (:part :title "Notes" :content (…))))
```

`\Shouldchecktype{list}{a \term{list}}` is a vocabulary entry: it appears in
the model by meaning, as standard error wording, and is expanded only for its
text.

## Building the model, by area

One section per step of the milestone that builds it (`docs/plan/m3.md`),
each written by its step.

### Declarations

*Step 3.1.* Every node kind is declared once
(`src/model/define-node.lisp`):

```lisp
(define-node dictionary-entry (:area :entries :categories (:block)
                               :example (:dictionary-entry :id "endp" …))
  "A dictionary entry: … (docstring)"
  (id :string :required t :doc "…" :example "endp")
  (names :string :required t :repeated t :doc "…" :example ("endp"))
  (entry-kind (:enum entry-kind) :required t :doc "…" :example :function)
  (parts (:node part) :repeated t :doc "…"))
```

- **Kind and class.** The kind is the keyword of the name; the form
  defines the class of that name, a subclass of `node` (whose `node-span`
  every node has), with one slot per field: initarg the field's keyword,
  accessor `<kind>-<field>`, `nil` until set.  `kind` and `span` are not
  field names, a field's JSON name is its name in lower case, and the
  name of a kind may not be a symbol of `common-lisp` or a class that is
  not a node's.  `node-kind` gives a node's kind; `make-node` makes one
  by kind, and `node-field-value` (setf-able) reads a field by its name,
  a keyword, so that the builder fills a node as its events come.
  A malformed or clashing declaration signals `declaration-error`.
- **Field types.** `:string`, `:integer`, `:boolean`, `:span`;
  `(:enum name)`, a value of a `define-enum`; `(:node name …)`, a node of
  one of the kinds or categories named; `:inlines`, a list of strings and
  nodes of the category `:inline`; `(:target kind …)`, a resolved
  reference (`make-target`: a target kind of `define-target-kind` and an
  id), `nil` while unresolved.  `:repeated t` makes the value a list of
  values of the type (not for `:boolean` and `:inlines`); `:required t`
  says every node of the kind has a value (a non-empty list when
  repeated; a target may still be unresolved).  `node-problems` checks a
  node against its declaration, `registry-problems` that every name a
  declaration uses is declared.
- **Categories** (`define-category`) group kinds that may stand in the
  same place, `:block` and `:inline` among them; a kind joins one by
  naming it in `:categories`.
- **Areas.** Each declaration names its area, one of `*areas*`
  (structure, entries, blocks, tables, inlines, glossary, bnf, math):
  the file `src/model/nodes-<area>.lisp` it lives in and its
  documentation ratchet ([exports.md](exports.md), "Documentation of
  every definition").
- **Documentation**: the node's docstring and `:example` (a node of the
  real spec, as the S-expression export writes it), each field's `:doc`
  and `:example`, each enum value's and each target kind's and
  category's docstring.
- **Registry.** Declarations go into `*registry*` (or the registry a
  `:registry` option names, so that tests declare kinds of their own),
  in order; a name declared again replaces its declaration in place.
  Introspection: `node-kinds`, `find-node-declaration`, `node-fields`,
  `enums`, `target-kinds`, `categories`, `category-kinds`,
  `expand-kinds`.

### Node shapes

*Step 3.2.* Every kind, enum, category and target kind is declared in
`src/model/nodes-<area>.lisp` with its type and a one-line meaning; the
examples, and fuller docstrings where needed, come with the builder step
that owns the area (its ratchet file lists what is missing).

- **What each key builds.** `tests/model/nodes.lisp` (`*node-products*`)
  gives every vocabulary key and event kind a builder step owns the node
  kinds its handler builds, or `:none` and why it builds none of its own
  (a closing key, a mark that only feeds its container, a presentational
  event).  The test checks that each kind named is declared, that every
  owned key is listed, and that every kind is built from a key or held
  by another kind's field (`:document`, the root, aside).  A builder step
  that builds something else changes the table in the same commit.
- **Names.** A kind's name cannot be a symbol of `common-lisp`, hence
  `:document` (the standard) and `:item-list`; the block of code is
  `:code-block`, so that `:code` is the inline.  The notation of syntax
  is prefixed `bnf-`, math `math-`.
- **Signatures** are four kinds by shape: `:operator-signature` (its
  `:operator` an enum: function, macro, special operator, generic
  function, method), `:setf-signature`, `:variable-signature`,
  `:type-signature`.  `\DefunMultiAccessorWithValues` sets two, readers
  and setf forms, and builds both.  A `-Multi` form's `\entry` lines are
  its `:names`.
- **Entry kinds** are the 17 `\ftype` texts in kebab-case; `macro`,
  `function` and `Special Form` are source errors left to patches.
- **Anchors** (`:issue-start`, `:issue-end`, `:index-entry`) and notes
  are both blocks and inlines: they stand in text and between blocks
  (`\issue` alone between paragraphs, dict-types.tex:72).
- **Glossary.** Parts of speech and usages are lists, on the entry (given
  before the senses, `\Noun, \TransitiveVerb`) and on each sense; the
  pronunciation keeps its stress marks, so it is inlines.  `\meaning`
  after a `\term` is the `:sense` of that term reference.
- **Math** keeps `\mathchoice`'s four lists (`:math-choice`): which one
  TeX sets depends on the style at typesetting time.

### Building

*Step 3.3.* The builder core, `make model` and the build report.  Which step
builds what: the ownership table `src/model/owners.sexp` gives every
vocabulary key and every event kind of [events.md](events.md) exactly one
owner, a step of the milestone and its handler file in `src/model/`
(`tests/model/owners.lisp` checks it).

The builder core (`src/model/build.lisp`) reads a job's events
([events.md](events.md)) in order and hands each to its **handler**; the
handlers of an area live in its own file and build the nodes.

- **Events.** `event-type` (`:begin`, `:text`, `:glue`, …), `event-key`
  (the key of a `:begin`, `:end` or `:mark`, else `nil`), `event-text`,
  `event-property`, `event-span`, `event-arguments`; `argument-text` gives
  an argument's token list as TeX shows it (`token-list-text`, so the
  builder keeps the job's expander), `event-argument-texts` all of them.
- **Cursor.** The events of a build are a cursor; `next-event` and
  `peek-event` give the next event and its span, so a handler may take the
  events that follow its own.
- **Handlers** are keyed on the pair (event type, key), since `:begin`,
  `:end` and `:mark` share keys: `(define-handler (:begin :com) (builder
  event span) …)`, key `nil` for a type without keys (`(:text nil)`).  A
  handler table (`make-handler-table`) is passed to the build like the
  registry; the model's is `*handlers*`, tests use their own.  An `:end`
  without a handler of its own closes its key's container when the key
  has a `:begin` handler.
- **Containers.** A handler opens a container for a key with
  `open-container` (the node it builds and the field that receives its
  items, or no node: its items then go to the container below), adds
  nodes and strings to the innermost one with `add-item`, and closes it
  with `close-container`.  When a container closes, its items fill the
  field, its node's span **joins** the span of its beginning and that of
  its end (`join-spans`: from the start of one to the end of the other
  when both lie in one file, else the beginning's; spans are
  `cl-ansi-spec/tex` spans, which the package imports with
  `make-span` and their readers), its node is checked with
  `node-problems`, and the node is added to the container below.  Nodes
  are made from the build's registry (`make-builder-node`).
- **Build report.** Nothing is dropped silently: every problem goes into
  the report with its span (`*problem-kinds*`): an event no handler takes
  (`:unhandled`); an `:end` whose key has no open container (`:underflow`
  when none is open, `:unmatched-end` otherwise); a container still open
  when one below it closes, or at the end of the build, which is closed
  there (`:unclosed`); a node that does not match its declaration
  (`:node`); a `:diagnostic` event or log entry; a TeX error the job
  recovered from (`:tex-error`) or that stopped it (`:fatal-error`).
- **Builds.** `build-events` builds a list of events; `build-job` runs a
  chapter job from plain TeX's format, observing the spec's vocabulary,
  and builds its events; `build-model` builds the chapter jobs it is given
  (the model does not list them: `cl-ansi-spec/inventory` does).
  `build-fixture` builds the nodes a job appended while the reader was at
  some lines of a file (`dict-conses.tex` 1702–1759 is `endp`): a
  composite node appended then whole, and of one appended later the
  nodes inside it appended then.  It places nodes by the reader's line,
  not by their spans as `make events` does, because a vocabulary entry
  called from a setup macro (`\begincom` calls `\dobegincom`) has the
  span of that call, in `setup-aux.tex`.  Each job runs once per session
  for fixtures (`forget-job-runs`), so the builders' tests stay fast.
- **Printing.** `node-sexp` writes a node as `(kind :field value … :span
  span)`, its fields in declaration order, empty ones left out;
  `print-node` prints it.  `make model FILE=… LINES=… [JOB=…]` prints the
  nodes `build-fixture` builds from those lines (the job: `FILE` itself
  when it is a chapter job, else `JOB`, else the chapter job that inputs
  it), then the report, unhandled events counted by type and key.

### Text

`src/model/build-text.lisp` (step 3.12) turns `:text` and `:space`
events into strings, and font runs into inlines.

- **Fonts.** `*fonts*` lists the font families the jobs set text in
  (a survey of every chapter job: cmr10/7, cmtt9, cmbx9/10 and the
  scaled headings, cmbxsl10, cmti10, cmssi10), each with its *layout*
  (what its character codes show) and its *class* (what a run in it
  means). A font is told by its file; its size is not looked at, so a
  heading in `cmbx10 scaled 1728` is cmbx10. A font outside the list
  keeps its characters and is reported once per build (`:diagnostic`).
- **Codes.** `*layout-codes*` gives, per layout, every slot that does
  not show the ASCII character of its code, each with the reason (the
  font's layout): the Greek capitals, the f ligature glyphs (shown as
  their letters), the accents (spacing forms), `ß æ œ ø Æ Œ Ø`, the
  quotes and dashes, and in cmti the pound sign where cmr has `$`. The
  typewriter layout is ASCII apart from its low slots, so `<`, `\`, `{`,
  `|` and `~` are themselves, where cmr's slots for those codes are `¡`,
  `“`, `–`, `—` and `˜`.
- **Ligatures.** In the cmr-style layouts: `` `` `` → `“`, `''` → `”`,
  `--` → `–`, `---` → `—`, `!`` → `¡`, `?`` → `¿`. The f ligatures
  change no text and are not applied; the typewriter font has none.
  Ligatures work across the `:text` events of one font with nothing
  between them, as TeX's do across character nodes (the expander splits
  a run where a macro's text begins); an item another handler adds
  between two events ends the run, and a dropped event does not.
- **Accents.** An `:accent` becomes the accent's code in its font
  (before the assignments) composed, with Unicode NFC, with the
  character's code in its font (after them); a base with no precomposed
  form keeps the combining mark after it (`u` and a dot above), an accent
  alone shows its spacing form. The result is in the character's font.
- **Discretionaries.** Their `:no-break` text is kept; `:pre-break` and
  `:post-break` are dropped (text only where a line breaks).
- **Spaces.** A `:space` is one `" "`; it is inside a font run when the
  text on both sides is in runs of one class, else plain.
- **Font runs.** Directly in a container, a run in a class-bearing font
  becomes `code` (tt), `emphasis` (italic, sans italic, slanted) or
  `strong` (bold); text in a container whose key
  `plain-text-container-p` names stays plain, because the container
  gives it its meaning: the vocabulary keys of structure, entries,
  tables and figures, inlines, glossary and syntax, and `:code`
  (`*plain-text-containers*`; a step with another such container pushes
  its key). So `{\tt …}` in a paragraph is `code`, `\f{…}` is whatever
  3.13 builds for it, and a heading stays text.
- **Mechanism.** The handlers are the functions of
  `install-text-handlers`, registered in `*handlers*` at load; tests
  register them in a table of their own. A container's current run of
  pieces is converted again at each event and replaces its tail of
  items, so ligatures and spaces see their neighbours; it is closed
  when the container's items no longer end as it left them.

### Structure

*Step 3.8.* Not written yet.

### Entries

*Step 3.9.* Not written yet.

### Blocks

*Step 3.10.* Not written yet.

### Tables and figures

*Step 3.11.* `src/model/build-tables.lisp` (`install-table-handlers`,
registered in `*handlers*` at load).

- **Tables.** An `:alignment` opens a `:table`, a `:row` a `:row`, a
  `:cell` a `:cell` whose content is the text and inlines of its list,
  without the spaces around them (none: an empty cell).  `\span` gives
  `:columns`.  A column whose template has a `\vrule` (the preamble of
  the alignment event, its `:loop` honoured) only draws a rule: it has no
  cell (one with text in it is kept).  A row whose cells are all empty
  is spacing (`\tabletwo` sets one around each rule) and is dropped;
  `:no-align` material (rules, glue) is dropped, anything else in it, and
  anything but rows in an alignment, is reported.  The first row is a
  heading (`:header`) when every cell that has content holds nothing but
  a bold run (`\tablefigtwo`'s heading arguments, `\tabletwo`'s `\b`).
  Only `\halign` is read as a table; a `\valign` is reported.
- **Figures.** `\DefineFigure` (a mark) gives the label, and the `:write`
  after it (left to 3.8, which drops it) the number TeX wrote; both wait
  for the `:figure` that follows.  The `:caption` inside the figure is
  `Figure N--M. text`: its paragraph and its bold runs (a caption is set
  in the bold font) are flattened, the number `N-M` is read from it and
  the text after it is the figure's `:caption`.  A figure with a caption
  that gives no number, or whose number is not the one TeX wrote, is
  reported (the caption's stands); without a caption the written number
  is used.  The id is the label, else `<chapter-id>/fig-<m>` for the
  number `N-M`, the chapter's id being that of the enclosing chapter node
  when it has one, else `N` (3.16 gives final ids).  Text directly in a
  figure is reported and dropped; the content is its blocks.
- **`\thenextfigure`** (`:next-figure`) is a `:next-figure` node with no
  words: its text is the number of the figure that follows, which 3.17
  resolves.

### Inlines

*Step 3.13.* Not written yet.

### Glossary

*Step 3.14.* Not written yet.

### Syntax

*Step 3.15.* Not written yet.

### Math

*Step 3.15m.* Not written yet.

### References

Resolved after the whole spec builds.

#### Sections, chapters and figures

*Step 3.17.* Not written yet.

#### Operators

*Step 3.18.* Not written yet.

#### Terms

*Step 3.19.* Not written yet.

## Exports

S-expression and JSON exports are generated from the same node declarations
as the model classes. They come with a generated JSON Schema, a reference
doc and a manifest, and they are versioned. All of this is in
[exports.md](exports.md).

## Not in the model

Page layout, fonts as such (a font switch survives only as the inline it
means), page numbers, and the running heads. The generated files
(`.fig`, `.tc`, `.toc`, `.idx`) are not read: their content is rebuilt from
events.
