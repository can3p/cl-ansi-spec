# Reader (phase 1)

Package `cl-ansi-spec/tex`, files `src/tex/*.lisp`. These are the current
rules; the history of how they were reached is in `docs/history/m0-m1.md`.

| File | Holds |
|------|-------|
| `state.lisp` | catcode, lccode and uccode tables, integer parameters (`\endlinechar`); the save stack (`begin-group`, `end-group`, `current-group-kind`, global assignment); the INITEX and plain catcodes |
| `token.lisp` | spans; control sequences and active characters, interned in one namespace per state; character and control-sequence tokens; `token=` ignores spans |
| `line.lisp` | line sources, and line buffers that keep the file offset of every element |
| `scanner.lisp` | TeX's states N, M and S, comments, `^^` notation, and control words and symbols, reading the *current* catcodes at every token |
| `input-stack.lisp` | TeX's single input stack (files, token lists, backed-up tokens) and the pluggable file resolver (`directory-resolver` over the source search path by default) |

Rules:

- **Spans.** A span is a `[start, end)` range of file character offsets,
  plus the line and column of its start, in a file named relative to its
  tree root. Patched and pristine trees use the same names.
- **Line ends.** A line's `\endlinechar` owns the trailing spaces that were
  removed and the newline. When there is no `\endlinechar`, they are
  reported as a `:line-end` skip. Token spans plus skips cover every file
  exactly; a property test checks this over all of `spec/tex/*.tex`.
- **`^^` in names.** `^^` notation inside a control-sequence name is
  rewritten in the buffer, as TeX does, so a later catcode change cannot
  re-read it.
- **Character codes.** Tables are vectors for codes 0–255, plus a hash table
  for larger codes (patched sources may be UTF-8). Unassigned codes default
  to category 12.
- **End of input.** `next-token` returns `nil` at the end of all input.
  `\endinput`, `\outer` checks and end-of-file hooks belong to the expander.
- **Resolver.** It maps a name to a line source or `nil`. Names that are
  absolute or contain `..` never resolve.

Debugging: `make tokens FILE=… LINES=a-b [SKIPS=1]`.
