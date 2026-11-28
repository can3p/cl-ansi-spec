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
`:limits` (`:limits` or `:no-limits`, when written), `:delimiter`,
`:nucleus`, `:superscript`, `:subscript`), `:math-char` (`:text`,
Unicode), `:math-fraction` (`:numerator`, `:denominator`, `:no-rule`,
`:thickness`, delimiters), `:math-delimiter` (`\left`, `\right`),
`:math-style-change` and `:math-choice`; a display's `:equation-number`
likewise, with `:number-left` for `\leqno`.  The lists also take inlines:
the sources set words in a formula with a font wrapper (`\ff{arccos}`),
which the vocabulary turns into a `:code`.

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

`src/model/build-structure.lisp` (step 3.8) builds the chapters, the
sections and the standard. Its handlers are the functions of
`install-structure-handlers`, registered in `*handlers*` at load.

- **No ends.** A chapter and a section are marks (`\beginchapter`,
  `\beginSection`, …); `\endSection` and its relatives are `\let` to
  `\empty`, so nothing closes them. The handlers keep one container per
  chapter and section, keyed by the mark's key, and a mark of level *L*
  closes the open sections of level *L* or more (a chapter closes them
  all) and opens its node in the nearest open one of a lower level. These
  closings are not problems; any other container still open then is
  reported `:unclosed`. At the end of a job the last chapter and its open
  sections are closed by the core, which reports each `:unclosed` (the
  job has no event for `\endchapter`): a build of a whole job has exactly
  those, no others, until step 3.16 closes them or filters them from
  its pinned report.
- **Headings.** After a section's mark the handler takes the events up
  to the end of the heading paragraph (`\HeadII`…): what comes before is
  handled as usual, the empty math of the hang is skipped, the first box
  is the number TeX typeset, and the rest is the title, in a container
  whose text is not read by font (a heading is bold and the title is not
  `:strong`). A mark, a text or another container before the paragraph is
  reported (`:node`, "No heading follows"). A dictionary section has no
  heading: its title is its chapter's title and "Dictionary", as
  `\includeDictionary` has the table of contents show it. A chapter's
  title is the mark's argument, run through the ligatures of its font
  (`convert-text`); its two heading paragraphs (the running head and the
  title) are consumed and dropped.
- **Numbers are counted** (`counted-number`) as TeX's counters are: the
  parent's number, a `.0` for each level skipped, then one more than the
  sections of the level since the last one of a higher level (the
  `\ssecn`… registers). They are **checked** twice: against the number
  TeX typeset in the heading's box, and against the line `\DefineSection`
  writes to the section file (`!<label> Section <number>\ <title>`,
  consumed by the handler of the mark, `parse-reference-write`); a
  mismatch is a `:node` problem ("counted … but TeX wrote …"). In a build
  that starts inside a chapter (a fixture) the parent has no number and
  the typeset one is used unchecked. `\DefineChapter` is checked in the
  same way: its reference name is the chapter's id, and the two lines it
  writes give its number.
- **Ids.** A chapter's id is the reference name of `\beginchapter`
  (`ChapOne`), a simple chapter's its title. A section's is the label of
  the `\DefineSection` in it (set when the mark comes, which must be
  before any subsection of its own: reported else), until then and for a
  section none names `<parent-id>/<n>`, its *n*-th among its parent's
  sections; with no parent in the build, `section-<number>`.
- **Other writes.** The `:write` handler is this step's, whose one owner
  drops every `\write` the handlers above do not take: the table of
  contents, the index and the issue files are data the model rebuilds from
  events.
- **The standard.** `build-standard` makes the `:document` of the chapter
  nodes of the jobs in order: those with no number (`\beginSimpleChapter`,
  chap-0.tex) are the front matter. `job-version` reads `\rev`, the draft's
  revision, from a job's expander. Calling both for the whole spec is
  step 3.16's.
- **Not yet.** Paragraphs, entries and the other blocks of a section's
  children come from their own steps; until they land they are reported
  as unhandled events.

### Entries

`src/model/build-entries.lisp` (step 3.9) builds a dictionary entry from
the events `\begincom` … `\endcom` make; `install-entry-handlers`
registers its handlers (in `*handlers*` at load, in a table of their own
for tests).

- **Entry.** `(:begin :com)` has two arguments: the names, a
  comma-separated list (catcode-active commas, lines wrapped: split on
  commas, trimmed), and the `\ftype` text.  The kind is that text in
  kebab-case and must be a value of `entry-kind` (an unknown one is
  reported and the entry has none).  The id is the first name: the
  collision rule (`<name>/<kind>`) needs every entry and is 3.16's
  (`ids.lisp`).  Three entries spelled the kind otherwise
  (`function`, `macro`, `Special Form`): patches 0004–0006.
- **Heading.** `\dobegincom` typesets the names and the kind in a
  paragraph of its own, and each `\label` its title in a box.  The part
  and the entry carry that meaning, so the paragraph and the box are
  skipped; one holding an event with a vocabulary key is reported, not
  dropped silently.  Everything before the first part is built as usual,
  and what no part can hold (the entry's `:parts` hold parts only) is
  reported.
- **Parts.** `(:mark :label)` closes the part before and opens one:
  its title is argument 1; `:none` is true when argument 2 is not `:`
  (`\label Side Effects:\None.`, which the `(:mark :label-confidence)`
  that follows completes: its `.`, `!` or `?`, how sure the authors are
  that the part is empty, is the part's `:confidence`).  A part runs to
  the next label or to the entry's end.
- **The end.** `\endcom` ends the entry's last part.  It may sit inside
  the last paragraph (dict-conses.tex:201, :4021), so that its `(:end
  :com)` comes before the paragraph's: the handler first takes the
  events that follow as usual while a container of another handler is
  open (stopping at a new paragraph, entry or part, or an end that closes
  nothing there), so that the paragraph closes where TeX closed it.  A
  stray `\endcom` is an `:underflow`.
- **Signatures.** A `\Def…` macro sets a signature in a paragraph of its
  own, which the part's blocks do not need: the handler closes it and
  drops its end.  It takes the signature's events itself, up to its
  `:end`, into a container of its own (text there is read as it comes,
  not by font): the first `:evaluates-to` (the arrow; also in the
  `NoReturn` forms) is dropped and splits the words into those before
  it (the name, then the lambda list) and after (the values).  Position
  does not matter, so the `Newline` forms need no rule of their own; a
  box (the stacked keyword parameters of `make-array`) starts a word.
  The name is removed from the front of the first words (reported when it
  is not there).
  - `:operator-signature`: `:defun`, `:defmac`, `:defspec`, `:defgen`,
    `:defmeth` and their `-no-return` forms; no values and `:no-return t`
    for the latter.
  - `:setf-signature`: `\Defsetf`'s words are `(setf (NAME lambda-list)
    new-value)`: the lambda list ends at the first unbalanced `)`, the
    new value at the last.
  - `:variable-signature`: `:defvar` and `:defcon` (`:constant t`); no
    entry of the sources uses them, so their tests use events made by
    hand.
  - `:type-signature`: `(:mark :deftype)`, whose alignment follows: one
    row per line of syntax, each `(NAME …)` without its parentheses and
    name, joined by `bnf-break`; the macro's empty last paragraph is
    dropped.
  - The `-multi` forms set a table with one `\entry` row per name (events
    outside the captured rows, the layout of the rest of the table, are
    skipped): the
    names are the `(:mark :entry)` marks (the second table of
    `\DefunMultiAccessorWithValues` repeats them), and the words of the
    first row of each table are the signature's.  The accessor builds an
    operator and a setf signature, `\DefsetfMulti` a setf one.  An
    `:entry` mark elsewhere (a row of `\tabletwo`) builds nothing: its
    cells are built in the table.
- **Reports.** A shape the rules do not expect (a signature that does not
  start with its name, a setf form without its parentheses, a label
  outside an entry, content outside a part) is a `:node` problem.

### Blocks

`src/model/build-blocks.lisp` (step 3.10) builds paragraphs, code, lists
and notes, and drops the presentational events.

- **Paragraphs.** `(:begin :paragraph)` … `(:end :paragraph)` is a
  `:paragraph` whose content is what the container collected.  One that
  holds only spaces (TeX starts one for an empty line) is dropped.
- **Dropped events.** `*dropped-events*` lists each event type with its
  reason: `:indent`, `:glue`, `:kern`, `:penalty`, `:rule`, `:language`,
  `:tex-mark`, `:special`, `:openout`, `:closeout`.  `*discarded-containers*`
  lists the containers whose whole content goes (`:leaders`, `:insert`,
  `:vadjust`, `:shipout`).  A `:box` is kept transparent: its content
  is built in its place.  `:write` is 3.8's.  Nothing else is dropped.
- **Code.** `\code` … `\endcode` is a `:code-block`; each line is a
  paragraph there (`\par` is `\endgraf`) and becomes a `:code-line`, its
  spaces as written (one per `:space`), an empty line a line without
  content.  The text is plain (`:code-line` is in `*plain-text-containers*`).
- **Lists.** `\beginlist` … `\endlist` is an `:item-list`, each
  `\item`, `\itemitem`, `\itemitemitem` an `:item` with the blocks up to
  the next item of its level or above; items of a deeper level form an
  `:item-list` in its content, and an `\itemitem` straight in the list
  (concept-args.tex:15) is an item of it.  The label is the content of the
  box `\listlabel` sets at the start of the item's first paragraph, so a
  bullet, which is math, arrives with 3.15m's handlers (the argument of
  the macro is not read: a source that puts text in it, concept-conditions.tex:248,
  gets it as the label).
- **Where TeX is.** The mark of `\item` comes while the *previous* item's
  paragraph is still open, and `\beginlist` (when no blank line precedes
  it, concept-args.tex:14) and `\endlist` (`\par\endgroup`) come before the
  paragraph they end.  So an item mark is remembered and applied when the
  next paragraph begins, and a list's begin and end wait for the open
  paragraph to end.  A paragraph ends with `close-block`, which gives
  the container's on-close function the end span through a weak table
  (the core's on-close does not get it).
- **Notes.** `\editornote` and `\reviewer` are marks carrying `:hidden`;
  the spec sets `\editornotesfalse` (setup-options.tex:23), so their body
  typesets nothing and the note's text is the argument as TeX shows it,
  `\term{x}` and `` `` `` as written, not inlines.  A note shown by the
  options is reported (its typeset copy would also be in the text).

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
  for the `:figure` that follows (a `\DefineFigure` always precedes its
  figure in the sources; one that does not would name the next).  The `:caption` inside the figure is
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

*Step 3.13* (`src/model/build-inlines.lisp`; `make model` shows them).
The node shapes are those of "Node shapes" above; what the builder
decides:

- **Containers for the macros with an extent, anchors for the rest.**
  A vocabulary `:begin` opens a container of its key; its `:end`
  closes it. The text inside a term, parameter, reference or notation
  is dropped, because the node says it (`:term-ref` and `:operator-ref`
  keep the *argument* text, not the typeset one: `\term{dotted list}`
  inflected as `dotted lists` is `:text "dotted list"`). Only
  `:emphasis`, `:strong`, `:code`, `:citation` and `:input` keep their
  content, read as plain text (their keys are plain-text containers, so
  the font does not make a second `:code` inside a `:code`).
- **References are unresolved.** `:operator-ref` takes its `:via` from
  the macro's key (`*reference-vias*`) and its `:text` from the *last*
  argument, as the reference sets it: `\kwd{test}` is `":test"`, `\keyref{key}`
  is `"\\&key"`. `:section-ref` and `:figure-ref` hold the label as
  written, trimmed (`"\\OrdinaryLambdaLists"`). No `:target` is set;
  3.17-3.19 resolve them.
- **`:lambda-list-keyword`** has no argument: its name is the text its
  macro typeset (`"&allow-other-keys"`).
- **Notation** (`:evaluates-to` …, `:output`, `:this-section`) has no
  field; the math or text the macro typesets is dropped.
- **Index entries and issues are anchors.** `:index-*` marks are
  `:index-entry` nodes (`:index-kind` from `*index-kinds*`, `:text` the
  first argument). `\issue` and `\endissue` are an `:issue-start` and an
  `:issue-end`, each with the name its macro was called with; the text
  between them stays in the surrounding container.
- `\thenextfigure` (`:next-figure`) is built by the figures' step 3.11.

### Glossary

*Step 3.14.* `src/model/build-glossary.lisp` builds the glossary of
`concept-glossary.tex` (24 groups, 692 entries).  The glossary is flat in
the events: `\firstindextab` and `\indextab` are `:glossary-letter` marks,
`\gentry` a `:glossary-entry` mark, and nothing ends them, so a group runs
to the next letter and an entry to the next entry or letter.  The
macros' own layout (`\beginlist` around the glossary, a list and an item
for each letter, a paragraph for each entry) is dropped: the handlers
skip those events while they run the group, and drop the list 3.10 opened
around the glossary when the first letter begins.  Their handlers
open a container and *run* the events that follow (`dispatch`) until that
stopping mark, or until the end of a container opened before them (the
section that holds the glossary), so no `:unclosed` is reported and no
step has to close them.

- **Entry.**  `id` and `term` are `\gentry`'s argument.  The heading
  `\gentry` sets again (the term in bold, its `:index-entry`, the term's
  text) is dropped from the items: it only repeats the term.
- **Notation.**  `\Noun` … `\Adverb` and `\ANSI` … `\Computers` are
  `:part-of-speech` and `:usage` containers told by their argument text
  (`*part-of-speech-texts*`, `*usage-texts*`); `\pronounced` is a
  `:pronunciation` container; its square brackets are notation, set in a
  formula, so the formula is unwrapped to its content (the stress marks
  `\Stress` sets are formulas that hold nothing and are dropped).  In an entry each leaves a tag, and the entry
  reads the tags when it closes; outside an entry (the glossary's
  introduction explains the notation) the text stays, in italics, and a
  pronunciation keeps its items.  A text that is not in the table is a
  `:diagnostic`.
- **Senses.**  The text of an entry has `1.`, `2.` … typed in it.  They
  are found by their order: `N.` set off by a space before and after, the
  next number being expected (`split-segments`), so `the integer 1.` at the
  end of a definition and a `2.` before sense 1 are text.  What comes
  before `1.` holds the entry's pronunciation, parts of speech and usages
  (those given for every sense), and, when it has words (an optional
  context, `(of an array)`), a first sense without a number.  An
  entry without `1.` has one sense without a number.  Tags after a number
  are that sense's.  A `:glossary-example` (`\gexample`) goes to the
  sense's `:examples`, not to its definition.  Commas that set the notation
  apart (`\Noun, \TransitiveVerb`, next to a tag) are dropped; those in
  the text stay.  A sense has the span of its entry: the events do not say
  where a number was typed.  Numbers are found by order, so a ` 2. ` inside
  sense 1's text, after sense 1 began, would split it; the glossary has
  none (`glossary-whole` checks that every sense has a definition).
- **Meanings.**  `\meaning{n}` (`:sense`) sets the `:sense` of the
  `:term-ref` it follows, from the integer its text starts with; `2a` is
  sense 2 and is reported (`:diagnostic`) because the sub-sense letter is
  not kept, and `n` is reported and not set.  The `:term-ref` is 3.13's:
  a `\meaning` that does not follow one is reported.

### Syntax

*Step 3.15* (`src/model/build-bnf.lisp`).  The BNF notation is built
from the begin/end pairs of the vocabulary: a macro with an argument and
its opening and closing forms (`\lbrac` … `\rbrac`) report the same
`:begin`/`:end` of one key, so the model does not tell them apart.

- `:bnf-rule` (`\auxbnf`): `name` is the first argument; `definition` is
  what the rule typeset after it, without the leading `name::`.
- `:bnf-optional`, `:bnf-zero-or-more`, `:bnf-group`,
  `:bnf-parenthesized`, `:bnf-bracketed`, `:bnf-required` and
  `:bnf-one-or-more` hold their `content`.  The glyphs a macro typesets
  as text (`[ ]`, `( )`, a trailing `*`, `*bnf-glyphs*`) are removed from
  the content, since the node says it; braces and plus signs are math
  characters and never were text.
- `:bnf-interleave` likewise.  `\interleave` calls `\begininterleave`, so
  an interleaving that begins with no argument right inside one that has
  no content yet is the same one, not a nested node.
- `:bnf-break` (`\CR`) and `:bnf-repeat-previous` (`\prevplus`) are leaf
  nodes, as are `:bnf-caret` (`\hat`; what it draws is dropped),
  `:angle-name` (`\ang`, `name`) and `:bnf-indirection` (`\down`, `name`).
- Not done here: the `\param` that follows a `\down` is a separate inline
  (inlines), so the parameter's name appears twice until the two are
  merged; the rule's alignment cells belong to tables and figures, and an
  unhandled alignment event is reported, not dropped silently.

### Math

*Step 3.15m.* `src/model/build-math.lisp` builds the formulas the expander
makes of math mode ([events.md](events.md), `:math`, `:noad`, …) into a
small tree of TeX's own noads; nothing is typeset.

- **Containers.** `:math` is a formula (`:display` from the event);
  `:noad` a noad of the event's class; `:fraction`, `:math-choice` the
  fractions and `\mathchoice`.  The sub-lists `:nucleus`, `:superscript`,
  `:subscript`, `:numerator`, `:denominator`, `:choice` and `:eqno` are
  containers that build no node: when one closes, its items become the
  field of the node of the container below (empty ones leave it absent).
  A string a text event left in a math list (a control space) becomes a
  `:math-char`, so every list holds only math elements and inlines.
- **Leaves.** `(:math-char :fam f :code c)` is a `:math-char` whose text
  is the slot of family *f*; `(:left …)`, `(:right …)` a `:math-delimiter`;
  `(:math-style …)` a `:math-style-change`.
- **Characters** are mapped by *family*, as the jobs set the families:
  plain.tex's 0–3 (cmr, cmmi, cmsy, cmex), then `setup-aux.tex:50-59`'s
  4 (cmbx), 5 (cmti), 6 (cmtt) and the math italic and symbol families
  7 and 8 (`*math-families*`).  Roman, bold, italic and typewriter families
  use the layouts of the text fonts (3.12); cmmi, cmsy and cmex have
  tables of their own (`*math-tables*`: code, Unicode, reason), cmmi and
  cmsy for every slot, cmex for the delimiters of plain.tex's `\delcode`
  table, the big operators and the radicals.  Letters and old-style digits
  of cmmi are kept as plain letters and digits (the italic is the font's);
  a combining mark (the vector accent, `\not`) stays a combining mark.
  A slot without a Unicode text (a cmex extensible piece) is shown as
  U+FFFD and reported (`:diagnostic`), never guessed.
- **Delimiters** (`\left`, `\right`, withdelims fractions, radicals)
  come as four numbers, small family and code and large family and code:
  the text is the small character, else the large; all zero is the null
  delimiter (the field is absent).
- **Fractions.** `:thickness` is `:default` (`\over`, `\atop` writes
  zero) or the dimension as TeX writes it: `:no-rule` is true for zero
  thickness, `:thickness` holds any other dimension (`\above`).
- **Not here.** Glue, kerns, boxes and rules in a math list belong to 3.10
  and 3.11; `\mathchoice`'s four choices keep all four.

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
