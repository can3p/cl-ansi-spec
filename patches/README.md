# Spec patches

Adjustments to the pristine sources in `spec/tex/` live here as a list of
**independent** patches, applied in order on top of the pristine tree.

Conventions (the format and application are enforced by
`cl-ansi-spec/patch`, `src/patch/`; names, headers and independence by the
patch set, `src/patch/set.lisp`):

- One concern per patch, named `NNNN-short-description.patch`
  (unified diff, paths relative to `spec/tex/`).
- Each patch starts with a header explaining *why* (erratum, typo,
  markup fix) and, where possible, a reference.
- Format: plain `diff -u` output, run from `spec/tex/`, so `--- FILE` and
  `+++ FILE` name the same relative path (no `a/` or `b/` prefix: it would name a file that does not exist, no
  rename, creation or deletion, no absolute or `..` path). The hunk
  lines must be plain context, `-` or `+` lines; an empty line is an
  error, as are text between hunks and a count that disagrees with the
  hunk.
- Every hunk's old line numbers are counted in the **pristine** file, even
  when an earlier hunk or patch adds lines. Application is strict: the
  context and deleted lines must be exactly the file's lines at those
  numbers (no fuzz, no offset), and no two hunks of a file, from any
  patches, may overlap or touch (context included). A failure names the
  patch, the hunk and the line.
- Patches must apply independently of each other; no patch may depend on
  another's context.
- Keep the line count where possible (uncomment rather than add a line),
  so spans, `make events LINES=` and test fixtures keep their lines; a
  patch that must add or remove lines says so in its header.
- A source error found later (an unresolved reference caused by a typo, a
  malformed `\ftype`) is fixed by a new patch here, never by a special
  case in code; the step that finds it writes it.
- Before writing a patch, show with `make events` that the error is the
  sources' own and that the patched text gives the structure expected.

The set is checked when it loads (`make test`, `make patched`): a name not
of that form, a duplicate number, an empty header, a patch that does not
apply alone to the pristine tree, or two patches whose hunks overlap or
touch is an error naming the patch. Every job reads the patched text;
`make patched` writes the patched tree to `build/patched/` for reading and
diffing only. `vendor/` is never patched.

Patches so far: `0001-syntax-type-table-definitions` (the abbreviations the
syntax-type table of concept-syntax.tex uses were commented out),
`0002-loop-numeric-accumulation-group` (a row break inside a brace group of
dict-iteration.tex), `0003-defsetf-lambda-list-closing-paren` (a rule that
opens a parenthesis and never closes it), `0004-ftype-function-case`,
`0005-ftype-special-form` and `0006-ftype-macro-case` (the three `\ftype`
texts that spelled an entry kind otherwise: `function`, `Special Form`,
`macro`), `0007-code-after-paragraph-text` (a `\par` before a `\code` run
into a paragraph), `0008-empty-code-in-type-of-examples` (an empty `\code`
block) and `0009-open-and-closed-streams-label-twice` (two sections with one
`\DefineSection` label).

Term patches (step 3.19p), from the term references the model could not
resolve: `0010-seeterm-nested-term` (`\seeterm\term{close}`),
`0011-implementation-dependent-spelling`, `0012-satisfies-the-test-spelling`,
`0013-compound-type-specifier-spelling`, `0014-generalized-boolean`,
`0015-hash-table-term-loop`, `0016-hash-tables-term-equalp`,
`0017-type-specifier-term`, `0018-function-names-term`,
`0019-lambda-list-term-glossary`, `0020-method-defining-form-term` and
`0021-object-term-period` fix the 12 misspelt terms; `0022-term-for-argument-names`
and `0023-term-for-operator-and-type-names` set argument, operator and type
names as `\param`, `\funref`, `\macref`, `\typeref` or `\f` where they were
`\term`.  The `:not-a-term` rows whose intended markup is not plain stay
pinned in `tests/model/unresolved-terms.sexp`.
