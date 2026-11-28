# Reader (phase 1)

Package `cl-ansi-spec/tex`, files `src/tex/*.lisp`. These are the current
rules; the history of how they were reached is in `docs/history/m0-m1.md`.

| File | Holds |
|------|-------|
| `state.lisp` | catcode, lccode and uccode tables, integer parameters (`integer-parameter`, read here for `\endlinechar`); the save stack (`begin-group`, `end-group`, `current-group-kind`, global assignment) and its table protocol (`make-equivalents`, `equivalent`, `assign`), which the expander's tables share; the INITEX and plain catcodes; `copy-tex-state` and `copy-equivalents`, for a job's copy of a format |
| `token.lisp` | spans; control sequences and active characters, interned in one namespace per state (`interned-names` lists them), plus uninterned frozen ones (`make-frozen-control-sequence`); character and control-sequence tokens; `token=` ignores spans |
| `line.lisp` | line sources, and line buffers that keep the file offset of every element; the empty line read at the end of a file for `\read` |
| `scanner.lisp` | TeX's states N, M and S, comments, `^^` notation, and control words and symbols, reading the *current* catcodes at every token; the tokens of one line for `\read` (`read-line-tokens`) |
| `input-stack.lisp` | TeX's single input stack (files, token lists, backed-up tokens) and the pluggable file resolver (`directory-resolver` over the source search path by default); the file-end hook, `\endinput` (`end-current-file`), the removal of exhausted token lists before a token is backed up (`back-input`) or a macro body pushed; alignment templates (the u-template end hook, `v-template-ended-p`); token-list levels with a tag and the level-end hook called when one is removed (an observed macro body); a macro body's level remembering its call (`push-macro-body`, `call-context`), so that `token-origin-span` gives where a token of it stands in the text, at the outermost call; the name and line number of the innermost file (`current-file-name`, `current-line-number`, TeX's `line` for `\inputlineno`); a file found without being read (`resolve-input`, for `\openin`); the level of a line of `\read` (`push-read-line`, `reading-line-p`, `end-read-line`) |

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
  After a file ends, the stack's file-end hook runs (the expander checks
  for runaways there) and may push tokens to read next.  `\endinput`
  sets TeX's one global force_eof: the next file to finish a line ends
  there (after `\endinput\input f` on one line, that is `f`).
- **Lines of `\read`.** `push-read-line` pushes the tokens of one line;
  once they are read `next-token` returns `nil` until `end-read-line`
  removes the level, as TeX's get_next ends a `\read` line.  Its
  exhausted level is not removed with other exhausted token lists.
- **Alignment templates.** A u template is a `:u-template` list: when it
  is removed exhausted, the stack's u-template end hook runs (the
  expander sets align_state to 0 there, TeX's end_token_list, §324).  A
  v template is a `:v-template` list; once exhausted, only reading on
  removes it, not backing up (§325), so that `v-template-ended-p` can
  tell that the `\endtemplate` just read ended it (TeX's do_endv,
  §1131).  Exhausted lists are removed before a token is backed up or a
  macro body is pushed, as TeX's back_input and macro_call do; other
  lists (inserted ones, `\every...`, templates) go on top of them.
- **Resolver.** It maps a name to a line source or `nil`. Names that are
  absolute or contain `..` never resolve.

Debugging: `make tokens FILE=… LINES=a-b [SKIPS=1]`.
