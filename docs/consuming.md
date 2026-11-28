# Consuming the exports

A short guide for code that reads the exports of `docs/exports.md`: what is
in them, how to walk them and how to get back to the TeX. Every definition
(node kinds, fields, enumerations) is in [model-reference.md](model-reference.md)
and in `schema/model.schema.json`; this guide does not repeat them. The
sample export (`make sample`, or `sample/` next to the full exports) holds
six entries and is enough to build a reader against.

## How the files fit together

Start from `manifest.json`:

- `schemaVersion` is the SHA-256 of the schema the files were written with.
  Every other file states the same value; refuse a file whose value differs.
- `source` says what the files were made from: `specSha256`, the digest of
  `spec/SHA256SUMS` (the pristine sources), and `patches`, the patches
  applied to them, in order, each with its digest.
- `generator` names the version and git commit of the program.
- `files` lists every other file with its SHA-256, in the order written:
  check a digest before trusting a file.

The files named there are `chapters/<id>.json` (one per chapter, front
matter included), `glossary.json`, `index.json` and `report.json`, and a
`.sexp` twin of each model file with the same content in S-expressions. Pick
one format: JSON for most code, S-expressions for Lisp. A model file is
`{"schemaVersion": "…", "<key>": …}` with the key `chapter` (one node),
`glossary` (an array of glossary groups) or `index` (an array of index
entries). `report.json` is not part of the model: it lists what the build
could not resolve (`unresolvedReferences`) and the TeX errors it recovered
from (`texErrors`), each with its span. The sample's files are
`entries/<id>.json`, each with the key `entry`, and no report.

## Walking the tree

Every node is an object with `kind` (its node kind) and, apart from text,
`span`. The other members are those of the kind in the schema; one that
holds nodes is an array of objects, and an empty or absent value is left
out. `oneOf` over `kind` in the schema tells a decoder which type to build,
so a typed language can generate its classes from the schema with standard
tools.

A chapter holds `children`: blocks, sections and dictionary entries in
document order, a section holds its subsections the same way. Inline content
(`content` of a paragraph, `lambda-list`, …) is an array of nodes; text is
`{"kind": "text", "text": "…"}`, never a bare string. A generic walk visits
every object with a `kind`, depth first, in member order; the order of the
arrays is the order of the document.

**Issue anchors** are inline nodes. An `issue-start` and an `issue-end` with
the same `name` bracket a range, possibly across blocks and sections: when
walking, keep the open names and mark what lies between them.

## Resolving references

A reference node (`term-ref`, and the others that have a `target`) carries
`"target": {"kind": K, "id": ID}`. A target is the pair of a kind and an id,
and an id is unique among the nodes of its kind:

| `target.kind` | look for the node of kind | in |
|---------------|---------------------------|-----|
| `chapter` | `chapter` | the chapter files |
| `section` | `section` | the chapter files |
| `entry` | `dictionary-entry` | the chapter files |
| `glossary` | `glossary-entry` | `glossary.json` (the same nodes sit in the glossary's chapter) |
| `figure` | `figure` | the chapter files |

Build one table from `(kind, id)` to node by walking every file once, then
resolve each reference by lookup. `target` is `null` for a reference the
build could not resolve (it is then in `report.json`): keep the text, show no
link. A slice of the export, the sample for one, has references whose target
it does not hold; treat them as unresolved.

## From a node to its TeX source

The `span` of a node is `{"file", "start", "end", "line", "column"}`: the
file is named as under `spec/tex/` (`dict-conses.tex`), `start` and `end` are
character offsets into that file, `end` exclusive, and `line` (from 1) and
`column` (from 0) give the place of `start`. The text is that of the file
**after the patches** of `manifest.json` have been applied to the pristine
sources, so apply them first: `make patched` writes that tree to
`build/patched/`. Then `text[start:end]` is the source of the node: for the
`endp` entry, the text from `\begincom{endp}` to `\endcom`. S-expression
spans are the list `(file start end line column)`.

## Worked example: `endp`

`entries/endp.json` of the sample:

```json
{
  "schemaVersion": "12253a53…",
  "entry": {
    "kind": "dictionary-entry",
    "span": {"file": "dict-conses.tex", "start": 46461, "end": 48187,
             "line": 1702, "column": 0},
    "id": "endp",
    "names": ["endp"],
    "entry-kind": "function",
    "parts": [ … ]
  }
}
```

(Digest shortened; the file has one member per line.) The entry is a function
documented in nine parts, each a `part` with a `title` taken from the source:
Syntax, Arguments and Values, Description, Examples, Side Effects, Affected
By, Exceptional Situations, See Also, Notes. A part with no text in the
source (Side Effects here) has `"none": true` instead of `content`.

1. **The signature.** The first part's `content` is an `operator-signature`:
   `operator` `function`, `names` `["endp"]`, `lambda-list` and `values` as
   inline nodes (`list`, `generalized-boolean`).
2. **The parameters.** In Arguments and Values each paragraph opens with a
   `param` node (`"name": "list"`), then the description as text and
   `term-ref` nodes, e.g.
   `{"kind": "term-ref", "text": "dotted list", "target": {"kind": "glossary", "id": "dotted list"}}`.
   Between them an `issue-start` and an `issue-end` named
   `DOTTED-LIST-ARGUMENTS:CLARIFY` bracket the words the issue changed.
3. **The examples.** Examples holds a `code-block` of three `code-line`
   nodes, each text and an `evaluates-to` node (the arrow) and a result:
   `(endp nil) ⇒ true`.
4. **The source.** The span above is lines 1702–1759 of
   `dict-conses.tex` of the patched tree; its first characters are
   `\begincom{endp}\ftype{Function}`.

In Lisp, with this system's own reader (the sample entry, then its signature):

```lisp
(let* ((file (cl-ansi-spec/json:parse-json-file "build/sample/entries/endp.json"))
       (entry (cl-ansi-spec/json:json-get file "entry"))
       (part (aref (cl-ansi-spec/json:json-get entry "parts") 0)))
  (list (cl-ansi-spec/json:json-get entry "id")
        (cl-ansi-spec/json:json-get (aref (cl-ansi-spec/json:json-get part "content") 0)
                                    "operator")))
;; => ("endp" "function")
```

Code that only reads the sample can check itself against the schema with any
JSON Schema validator: `schema/model.schema.json` validates one node, the
value of `chapter` or `entry` (or an element of the two arrays), not the
whole file.
