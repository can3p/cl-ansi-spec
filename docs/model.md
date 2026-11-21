# Document model

The product of the parser (phase 4, milestone M3). This page is the
**draft schema**. M3 refines it, and this page is updated in the same commit
as the code.

## Shape

The model is a tree of nodes. Each node has a kind, named fields, optional
children and a `:span`. The span gives the source file, line and offsets
(`docs/architecture.md`, principle 4). In Lisp, nodes are CLOS instances. The
plist notation below is the S-expression export, and the JSON export maps it
one to one (see "Exports").

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
- `(:param "list")`, `(:code "…")`, `(:emphasis …)`, `(:math …)`
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

## Exports

- **S-expressions**: exactly the notation above, one file per chapter plus
  `glossary.sexp` and `index.sexp`. They can be read back with `read` under a
  documented readtable.
- **JSON**: `{"kind": "dictionary-entry", "id": "endp", …, "children": […]}`.
  Keywords become strings. Strings and inline objects alternate in
  `children`.

Both formats carry a schema version. Tests check the full spec against the
schema.

## Not in the model

Page layout, fonts as such (a font switch survives only as the inline it
means), page numbers, and the running heads. The generated files
(`.fig`, `.tc`, `.toc`, `.idx`) are not read: their content is rebuilt from
events.
