# Exports and their schema

How outside code learns the shape of the model. The model itself is
described in [model.md](model.md); this page covers the formats it is
exported in and how they are specified, documented and checked.

## One definition, everything generated

Each node kind is declared once, in Lisp, with a `define-node` form
(`src/model/define-node.lisp`; [model.md](model.md), "Declarations").
The form gives the node's fields, each field's type, whether it is required
or repeated, and documentation; `define-enum`, `define-target-kind` and
`define-category` declare what field types name. The declarations go into
a registry, and everything else is generated from it, through its
introspection functions (`node-kinds`, `node-fields`, `enums`,
`target-kinds`, `categories`):

| Generated | What it is |
|-----------|------------|
| the model classes | the CLOS classes the model builder fills in |
| `schema/model.schema.json` | a JSON Schema, draft 2020-12. It has one `$defs` entry per node kind, picked out by a constant `"kind"`, and `additionalProperties: false`. All the documentation (see below) is carried over as `title`, `description` and `examples`. |
| `docs/model-reference.md` | the human reference, generated (see below): by area, each node kind with a field table and its example, then the enumerations, target kinds and categories |

The generated files are committed. Each generator registers itself with
`define-generator` (`src/export/generate.lisp`); `make generate` rewrites
the files, and `make test` fails if they differ from what the generators
make, so code, schema and docs cannot drift apart.

### The generated schema

`src/export/schema.lisp`. Any node kind may be the root (a top-level
`oneOf` of references). `$defs` holds, in order: `span`, `text` (the
`{"kind": "text", …}` object, unless a node kind `text` is declared),
`enum-<name>` (a `oneOf` of `{"const", "description"}`), `target-<name>`
(`{"kind", "id"}`), then one entry per node kind, named as the kind. A
node's properties are `kind`, `span`, then its fields in declaration
order; `required` lists `kind`, `span`, the required fields and every
`target` field. A repeated field is an array of its type; a field of
several kinds or categories is a `oneOf` of references; an inline list is an
array of `text` and the kinds of the category `inline`; a target field is a
`oneOf` of its target definitions and `{"type": "null"}`. A docstring becomes `description`,
a field's name its `title`, examples `examples` (an example is converted
by the field's type; one that does not fit its kind stops the generator).
Examples are illustrative: they carry no `span`, so they do not validate
against their own definition. With no node kind, the top-level `oneOf` is
omitted.
`schema-outside-subset` and `schema-undescribed` are what the suite checks.

## Documentation of every definition

The schema is how a consumer learns what the data *means*, not only its
shape. So documentation is part of every declaration, and `make test`
rejects a declaration that lacks any of it.

- **Every node kind, field, enum value and target kind** has a docstring.
  The docstring says:
  - what it means in the standard;
  - where it comes from in the sources (the macro or construct, e.g. "the
    `\label` heading of a dictionary entry's part");
  - for fields, when the field is absent.

  Node kinds and fields also carry an example value taken from the real
  spec.
- **Checks.** `make test` checks mechanically that every docstring is
  present and non-empty, and that every node kind and field has an
  example (`undocumented-items`, `tests/model/documentation.lisp`). While
  the model is being built, what still lacks them is listed per area in
  `tests/model/undocumented-<area>.sexp`: the test fails on an
  undocumented item missing from its list and on a listed item that is
  now documented, so the lists only shrink; they are empty when the
  model is complete. Whether a docstring is *meaningful* is a manual check, done in
  review (`lisp-review` checklist). A docstring that only restates the
  name ("The id of the entry") fails that check.
- **Everything goes into the schema.**
  - Node kinds and fields get `title` and `description`.
  - Enum values are emitted as `oneOf` of `{"const": …, "description": …}`,
    so each value keeps its own meaning.
  - Examples become `examples`.

  A test walks the generated schema and fails on any definition, property
  or enum value without a description.
- **The reference doc** (`docs/model-reference.md`) is generated from the
  same declarations (`src/export/reference.lisp`, `make generate`). It has
  one section per area, in the order of `*areas*`. Each node kind gets its
  docstring, its categories, a field table (type, required, description),
  and its example as an S-expression. Enumerations, target kinds and
  categories get their docstrings and values. Nothing about a node is
  written by hand anywhere else.

## Validation

Every exported file of the whole spec is validated against the schema in
the test suite. The validator is Lisp and implements exactly the subset of
JSON Schema the generator emits: `type`, `const`, `enum`, `required`,
`properties`, `additionalProperties`, `items`, `$ref`, and `oneOf` (over
kind-constant objects, over `const` values, and over a target and `null`).
The generator never emits anything outside that subset; a test checks this.

CI also checks the export with one widely used external validator, ajv-cli
(pinned in `.github/workflows/ci.yml`, step "Validate the export against the
schema"). It runs in CI only and is not part of the code base. The step runs
`make export` and checks every node of the chapter, glossary and index files
in `build/export/` against `schema/model.schema.json`. Each file wraps its
node (`chapter`, `glossary` or `index`), so the nodes are taken out first.
`manifest.json` and `report.json` have no schema and are not checked. Any
violation fails the job; an export with no nodes fails it too. The Python
validator check-jsonschema did not finish within 110 seconds on the largest
chapter alone (it was stopped there), too slow for CI, so the step uses ajv.

The validator is `src/export/validate.lisp`. `(validate-json schema
instance)` takes both as parsed JSON (`cl-ansi-spec/json`) and returns the
list of `validation-error`s (a JSON Pointer into the instance and a message,
ordered by keyword, then by member or element),
`NIL` when valid; `json-valid-p` is the boolean form. `title`, `description`,
`examples`, `default`, `$schema`, `$id`, `$comment` and `$defs` are accepted;
any other keyword, or a supported one with a value of the wrong form
(`items` as an array, say), signals `unsupported-schema-keyword` for the first
violation; `schema-subset-violations` lists them all, for the test of the
generator. `number` accepts integers only, as the model has no floats; `true`
and `false` are schemas. A `$ref` cycle that consumes no data signals
`circular-schema-reference`.
In a `oneOf` whose branches are objects with a constant `"kind"` (directly or
through `$ref`), an instance with a known `kind` reports the errors of that
branch only. `$ref` resolves to `#` or a JSON Pointer in the same schema.

## JSON shape

- **Nodes are objects.** Every node has `"kind"` (the node kind without its
  colon, e.g. `"dictionary-entry"`) and `"span"`. Its other fields are typed
  by the schema. A field that holds nodes (`children`, `rows`, `cells`,
  `items`, `senses`, `values`, `caption`, …) holds an array of node objects.
  An optional field without a value, and an empty array, are **omitted**,
  never `null` or `[]`. The one exception is `target` (see below).
- **Text is an object too:** `{"kind": "text", "text": "…"}`. Arrays never
  mix bare strings with objects, so typed languages can decode them
  directly. Adjacent text is merged into one object. (The S-expression
  export uses bare strings, as in [model.md](model.md).)
- **Issue anchors** are inline nodes like any other:
  `{"kind": "issue-start", "name": "DOTTED-LIST-ARGUMENTS:CLARIFY"}` and
  `{"kind": "issue-end", …}`. Issues are ranges, so an issue's start and end
  may sit in different blocks or sections. Each start has exactly one
  matching end later in document order.
- **References:**
  `{"kind": "term-ref", "text": "dotted list", "target": {"kind": "glossary", "id": "dotted list"}}`.
  `target` is always present. It is `null` when the reference is
  unresolved, and the reference is then also listed in `report.json`.
  Target kinds:

  | `target.kind` | points to node kind |
  |---------------|---------------------|
  | `chapter` | `chapter` |
  | `section` | `section` |
  | `entry` | `dictionary-entry` |
  | `glossary` | `glossary-entry` |
  | `figure` | `figure` |

- **Ids** are strings taken from the sources, never from numbering:
  - chapters: the chapter label of `\beginchapter` (e.g. `ChapFourteen`);
  - sections: their `\DefineSection` label;
  - dictionary entries: the first name, e.g. `endp`;
  - glossary entries: the term.

  - figures: their `\DefineFigure` label, else `<chapter-id>/fig-<m>`
    for figure `N-M`;
  - a section without a `\DefineSection`: `<parent-id>/<n>`, its *n*-th
    among its parent's sections (stable because its parent's id is; no
    source links to it).

  An id is unique among the nodes of one target kind, so a link is the pair
  `{"kind", "id"}`. Two dictionary entries can share a first name (an
  operator documented once as a function and once as a type). In that case
  both ids become `<name>/<ftype>`, e.g. `function/special-operator`, with
  the `\ftype` text in kebab-case. Any collision that rule does not settle
  is an `:id-collision` of the build report (a source error that a patch
  fixes); the whole-spec test pins the report, so none goes unnoticed
  ([model.md](model.md), "Ids").
- **Spans:**
  `{"file": "dict-conses.tex", "start": 61234, "end": 61262, "line": 1702, "column": 0}`.
  `start` and `end` are character offsets, with `end` exclusive. `line`
  counts from 1 and `column` from 0 (`docs/reader.md`, "Spans"). In the
  S-expression export a span is `(file start end line column)`;
  [model.md](model.md) shortens it to `(file line)` in examples.
- **Names** are kebab-case. Keywords in the Lisp model become strings with
  the colon removed.

### Byte format

Written by `cl-ansi-spec/json` (`src/json/`): UTF-8, LF line endings, two-space
indentation, one member or element per line, `"key": value`, empty
containers as `{}` and `[]`, a final newline, members in the order the
exporter gives them. Strings escape only `"`, `\`, and the control
characters (`\b \f \n \r \t`, else `\u00xx` in lowercase hex); all other
characters are written as they are. Numbers are integers only; a float
is an error. The reader is strict (RFC 8259): it rejects duplicate keys, lone
surrogates, floats and trailing text. Lisp side: object `(:object (key . value)…)`,
array vector, `:true`/`:false`/`:null`.

## Files

| File | Contents |
|------|----------|
| `manifest.json` | `schemaVersion`; `generator` (the `cl-ansi-spec` version and git commit); `source`: the SHA-256 of `spec/SHA256SUMS` and the list of patch file names applied, in order, each with its SHA-256; `files`: every file below with its SHA-256 |
| `chapters/<id>.json` | one chapter, named by its chapter id |
| `glossary.json`, `index.json` | the glossary, and the symbol index |
| `report.json` | unresolved references and recovered TeX errors, each with its span |

Every JSON file is an object with `schemaVersion` and its content, e.g.
`{"schemaVersion": "<sha256>", "chapter": {…}}`.
The S-expression export has the same files with `.sexp`. Each one is a
single form `(:schema-version "<digest>" . content)`, read back with `read`
with `*read-eval*` false under standard syntax (keywords, strings, integers
and lists only).

### The whole export

`make export` (`tools/export.lisp`) builds the document of every chapter
job (`build-document`) and writes it under `build/export/` (`OUT=dir` for
another place): `write-whole-export` (`src/export/manifest.lisp`) writes
the chapter files, `glossary` (every `glossary-group` of the document) and
`index` (every `index-entry`, in document order), each as JSON and as an
S-expression, then `report.json` and `manifest.json`. The two are JSON
only: they describe the export, not the model.

- **`manifest.json`** (`export-manifest-object`): `schemaVersion`;
  `generator` (`name`, `version`, `commit`, the git commit of the
  working tree, `"unknown"` outside a checkout); `source`: `specSha256`
  (the SHA-256 of `spec/SHA256SUMS`, which names every source by its
  digest) and `patches`, `{"name", "sha256"}` of each applied patch in
  order (`applied-patches`, M4); `files`: `{"path", "sha256"}` of every
  other file written, in the order written.
- **`report.json`** (`export-report-object`): `schemaVersion`, then
  three arrays of groups `{"kind", "description", "count", "items"}`,
  each item `{"job", "span", "message"}` (job and span left out when
  the problem has none): `unresolvedReferences` (the kinds
  `unresolved-term`, `ambiguous-term`, `missing-sense`,
  `unresolved-reference`, `ambiguous-reference`; the message is the
  reason), `texErrors` (`tex-error`, `fatal-error`: errors the job
  recovered from, or stopped on), and `other` (every other kind of
  problem, e.g. `diagnostic`). A kind with no problem has no group. The
  kinds and their meaning are `*problem-kinds*`
  (`src/model/build.lisp`).

`tests/export/whole-spec.lisp` writes the export of the whole spec to a
temporary directory and checks every digest of the manifest, every node
of the JSON files against the schema ("Validation"), the S-expression files, and
the counts of the report by kind (pinned there). Every node of the
export is valid against the schema.

The validator's cost matters here: a `oneOf` over node kinds validates only
the branches whose constant `kind` matches the instance's, and a schema is
checked against the subset once, not at every call.

### The writers

`src/export/write-json.lisp` (`node-json`), `write-sexp.lisp` (`file-sexp`,
`sexp-text`, `read-sexp-text`) and `files.lisp` (`write-export-files`,
`schema-version`). Both writers walk the registry's declarations, so a node
kind needs no writer code. Besides the rules of "JSON shape":

- a required field that has no value is written empty (`[]`, `false`), not
  omitted, and a node made without a span has no `span`; the validator then
  reports it, since the writer does not hide what the builder left out;
- an empty text is dropped when adjacent text is merged;
- a file's content is a plist of keys and nodes or lists of nodes: `:chapter`
  (one chapter node), `:glossary` (glossary groups), `:index` (index entries);
- a chapter file is named by its id with every run of characters other than
  letters, digits, `.` and `_` replaced by one `-` (simple chapters are named
  by their title); two chapters naming one file stop the export;
- `write-export-files` returns the `(path . sha256)` of each file written,
  for the manifest.

## Versioning

Correctness comes before compatibility. Until the model is complete, the
schema changes whenever correctness requires it. No deprecation path is
kept, and no compatibility layer is added.

- Every file states the `schemaVersion` it was written with: the
  lowercase hex SHA-256 of the committed `schema/model.schema.json` file's
  bytes, untruncated, so a consumer always knows exactly which
  schema matches a file.
- The schema is published alongside every export.
- A summary of each schema change goes in the commit message that makes
  it.

This is the one place the rule is stated; the process docs and skills link
here. Compatibility rules are decided only when a stable release is
planned.

### The sample export

`make sample` (`tools/sample.lisp`; `OUT=dir` for another place) writes a
small export to `build/sample/`, for code that reads the exports to be
built and tested without running the parser (it still takes about 25 s: it
builds the whole model and keeps a few entries of it). `write-sample-export`
(`src/export/sample.lisp`) writes, for each id of `*sample-entry-ids*`
(`endp`, `boolean`, `type-error`, `when`, `car`, `*print-base*`: a
function, a system class, a condition type, a macro, an accessor, a
variable), the dictionary entry as `entries/<id>.json` and `.sexp` (the id
named as a file as chapters are, "The writers"), then `manifest.json`,
built as the whole export's, which lists the files with their digests. An
entry file is a file as any other: `{"schemaVersion": "…", "entry": {…}}`,
and `(:schema-version "…" :entry (:dictionary-entry …))`. It is a slice of
the whole export, so its references point to chapters, sections and glossary
entries the sample does not hold; they are resolved in the whole export.
There is no `report.json`.

`tests/export/sample.lisp` writes the sample from the real model and checks
the manifest, every digest, every entry against the schema and the
S-expression files. The entries are chosen from those the schema accepts:
the pinned violations of "The whole export" are not in them.

## For consumers

`docs/consuming.md` is the short guide for code that reads the
exports:

- how the files fit together, starting from `manifest.json`;
- walking the tree and resolving references;
- getting from a node back to its TeX source;
- a worked example on `endp`.

The sample export of "The sample export" is published next
to the full exports (under `sample/` at the same base URL), so a library can be built and tested without running
the parser. Bindings for other languages are not provided; they can be
generated from the JSON Schema with standard tools.
