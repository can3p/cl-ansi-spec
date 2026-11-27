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

### Document level

| Node | Fields | Children |
|------|--------|----------|
| `:standard` | `:version` (from `setup-version.tex`) | chapters, `:glossary`, `:index` |
| `:chapter` | `:number`, `:id`, `:title` | sections, dictionary entries |
| `:section` | `:number` (e.g. `"14.1.2"`), `:id` (the `\DefineSection` label), `:title`, `:level` | sections, blocks |
| `:dictionary-entry` | `:id`, `:names`, `:kind` | `:part`s |
| `:part` | `:title` (the `\label` text), `:none` (true for "None.") | blocks |
| `:glossary-entry` | `:term`, `:id`, `:senses` | blocks |
| `:figure` | `:id`, `:number`, `:caption` | a `:table` or blocks |

### Blocks

`:paragraph`, `:code` (exact text, line structure kept), `:table`
(`:rows` → `:cells` → inlines), `:list` (`:items`), `:defun` (`:name`,
`:lambda-list`, `:values`), `:bnf`, `:display-math`, `:editor-note`
(kept even though the options hide it, with `:hidden t`).

### Inlines

A string is plain text. Other inlines:

- `(:term-ref "dotted list" :target (:glossary "dotted list"))`
- `(:operator-ref "endp" :target (:entry "endp"))`
- `(:section-ref :target (:section "Definitions"))`
- `(:figure-ref :target (:figure …))`
- `(:param "list")`, `(:code "…")`, `(:emphasis …)`, `(:strong …)`, `(:math …)`
- `(:evaluates-to)` and the other notation of examples (`:may-evaluate-to`,
  `:does-not-evaluate-to`, `:equivalent`, `(:output …)`, `(:input …)`)
- `(:citation …)`: the title of a cited work
- `(:index-entry :kind k "…")`: an index entry (`k` one of `:ref`,
  `:keyref`, `:code`, `:keyword`, `:text`, `:term`, `:example`,
  `:package`), an anchor
- `(:issue-start "NAME")` and `(:issue-end "NAME")`. Issues are **ranges**
  and may cross block and section boundaries, so they are anchors, not
  containers.

`:target` holds resolved references. An unresolved reference keeps
`:target nil` and is listed in the build report.

## Identity

Every addressable node has a stable `:id`, derived from the sources (the
entry name, the `\DefineSection` label, the glossary term), never from
numbering. Exports and consumers link by id.

## Full example

Built from `dict-conses.tex:1702-1761` (spans shortened to the line):

```lisp
(:dictionary-entry
 :id "endp" :names ("endp") :kind :function :span ("dict-conses.tex" 1702)
 :parts
 ((:part :title "Syntax"
   :content ((:defun :name "endp" :lambda-list ((:param "list"))
                     :values ((:param "generalized-boolean")))))
  (:part :title "Arguments and Values"
   :content
   ((:paragraph (:param "list") "---a " (:term-ref "list" :target (:glossary "list")) ","
                (:issue-start "DOTTED-LIST-ARGUMENTS:CLARIFY")
                " which might be a " (:term-ref "dotted list" :target (:glossary "dotted list"))
                " or a " (:term-ref "circular list" :target (:glossary "circular list")) "."
                (:issue-end "DOTTED-LIST-ARGUMENTS:CLARIFY"))
    (:paragraph (:param "generalized-boolean") "---a "
                (:term-ref "generalized boolean" :target (:glossary "generalized boolean")) ".")))
  (:part :title "Description"
   :content ((:paragraph "Returns " (:term-ref "true" :target (:glossary "true"))
                         " if " (:param "list") " is the "
                         (:term-ref "empty list" :target (:glossary "empty list")) ". …")))
  (:part :title "Examples"
   :content ((:code " (endp nil) " (:evaluates-to) " " (:term-ref "true" …) "…")))
  (:part :title "Side Effects" :none t)
  (:part :title "Affected By" :none t)
  (:part :title "Exceptional Situations"
   :content ((:paragraph "Should signal an error of " (:type-ref "type-error" …) "…")))
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

### Building

*Step 3.3.* The builder core, `make model` and the build report.  Which step
builds what: the ownership table `src/model/owners.sexp` gives every
vocabulary key and every event kind of [events.md](events.md) exactly one
owner, a step of the milestone and its handler file in `src/model/`
(`tests/model/owners.lisp` checks it).

### Text

*Step 3.12.* Not written yet.

### Structure

*Step 3.8.* Not written yet.

### Entries

*Step 3.9.* Not written yet.

### Blocks

*Step 3.10.* Not written yet.

### Tables and figures

*Step 3.11.* Not written yet.

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
