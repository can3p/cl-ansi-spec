# Exports and their schema

How outside code learns the shape of the model. The model itself is
described in [model.md](model.md); this page covers the formats it is
exported in and how they are specified, checked and versioned.

## One definition, everything generated

Each node kind is declared once, in Lisp, with a `define-node` form (planned).
The form gives the node's fields, each field's type, whether it is required
or repeated, and a docstring. Everything else is generated from these
declarations:

| Generated | What it is |
|-----------|------------|
| the model classes | the CLOS classes the model builder fills in |
| `schema/model.schema.json` (planned) | a JSON Schema, draft 2020-12. It has one `$defs` entry per node kind, picked out by a constant `"kind"`, and `additionalProperties: false`. Each field's description is its docstring. The `$id` contains the schema version. |
| `docs/model-reference.md` (planned) | the human reference: a field table for each node kind, plus one short example taken from the real spec |

The generated files are committed. `make test` regenerates them and fails if
they differ from the committed copies, so code, schema and docs cannot drift
apart.

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

## Files

| File | Contents |
|------|----------|
| `manifest.json` | `schemaVersion`; `generator` (the `cl-ansi-spec` version and git commit); `source`: the SHA-256 of `spec/SHA256SUMS` and the list of patch file names applied, in order, each with its SHA-256; `files`: every file below with its SHA-256 |
| `chapters/<id>.json` | one chapter, named by its chapter id |
| `glossary.json`, `index.json` | the glossary, and the symbol index |
| `report.json` | unresolved references and recovered TeX errors, each with its span |

Every JSON file is an object with `schemaVersion` and its content.
The S-expression export has the same files with `.sexp`. Each one is a
single form `(:schema-version "1.2.0" . content)`, read back with `read`
under the readtable documented in `docs/model-reference.md`.

## Versioning

`schemaVersion` follows semver:

- Adding an optional field or a new node kind bumps the **minor** version.
- These changes bump the **major** version:
  - removing or renaming anything;
  - changing a field's type or meaning;
  - making a field required;
  - adding a value to an existing enum or target kind.

The schema `$id` names its major version: `…/schema/v<major>/model.schema.json`.
The base URL is the published site, fixed in M5. Each major version's
schema stays published there.

Rules for consumers:

- Accept files whose major version you were built for.
- Within that major version, **ignore unknown fields and unknown node
  kinds**: they are minor additions.
- `additionalProperties: false` in the schema is how *we* check our own
  output. A consumer validating with an older schema of the same major
  version should drop it, or validate with the schema named by the file's
  `schemaVersion`.

Each change is recorded in `schema/CHANGES.md` (planned).

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
