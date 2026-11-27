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
| `schema/model.schema.json` (planned) | a JSON Schema, draft 2020-12. It has one `$defs` entry per node kind, picked out by a constant `"kind"`, and `additionalProperties: false`. All the documentation (see below) is carried over as `title`, `description` and `examples`. |
| `docs/model-reference.md` | the human reference, generated (see below): by area, each node kind with a field table and its example, then the enumerations, target kinds and categories |

The generated files are committed. Each generator registers itself with
`define-generator` (`src/export/generate.lisp`); `make generate` rewrites
the files, and `make test` fails if they differ from what the generators
make, so code, schema and docs cannot drift apart.

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
`properties`, `additionalProperties`, `items`, `$ref`, and `oneOf` on
`"kind"`. The generator never emits anything outside that subset; a test
checks this. CI also cross-checks the exports with one widely used external
JSON Schema validator. That validator runs in CI only and is not part of the
code base.

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

  An id is unique among the nodes of one target kind, so a link is the pair
  `{"kind", "id"}`. Two dictionary entries can share a first name (an
  operator documented once as a function and once as a type). In that case
  the id becomes `<name>/<ftype>`, e.g. `function/special-operator`, with
  the `\ftype` text in kebab-case. Any collision that rule does not settle
  stops the build.
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
under the readtable documented in `docs/model-reference.md` (planned).

## Versioning

Correctness comes before compatibility. Until the model is complete, the
schema changes whenever correctness requires it. No deprecation path is
kept, and no compatibility layer is added.

- Every file states the `schemaVersion` it was written with: the
  lowercase hex SHA-256 of the committed `schema/model.schema.json` (planned) file's
  bytes, untruncated, so a consumer always knows exactly which
  schema matches a file.
- The schema is published alongside every export.
- A summary of each schema change goes in the commit message that makes
  it.

This is the one place the rule is stated; the process docs and skills link
here. Compatibility rules are decided only when a stable release is
planned.

## For consumers

`docs/consuming.md` (planned) is the short guide for code that reads the
exports:

- how the files fit together, starting from `manifest.json`;
- walking the tree and resolving references;
- getting from a node back to its TeX source;
- a worked example on `endp`.

A small sample export, a few entries with the manifest, is published next
to the full exports (under `sample/` at the same base URL), so a library can be built and tested without running
the parser. Bindings for other languages are not provided; they can be
generated from the JSON Schema with standard tools.
