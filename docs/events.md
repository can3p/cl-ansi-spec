# Event stream

The interface between the semantic layer (phase 3) and the model builder
(phase 4). It is flat, ordered and replayable, and it holds no document
structure: phase 4 decides that an entry's parts run from one `\label` to the
next.

## Event kinds

| Event | Meaning |
|-------|---------|
| `(:begin <entry> . args)` / `(:end <entry> . args)` | A vocabulary entry starts or ends. `args` are its arguments, as parsed by the macro's own parameter text (strings for names, nested event lists for content). |
| `(:mark <entry> . args)` | A vocabulary entry with no extent (`\label`, `\DefineSection`). |
| `(:text "…" :style s)` | A run of characters in one font. `s` names the font by its file and size (`"cmr10"`, `"cmr10 at 12.0pt"`, `"cmr10 scaled 1200"`), whatever control sequence selected it; phase 4 maps fonts to meaning only outside vocabulary entries. |
| `(:space)` | An interword space (a blank in horizontal mode, or `\ `). |
| `(:begin :paragraph)` … `(:end :paragraph)` | A paragraph: what was appended in horizontal mode until `\par`, without its final glue. An indented one begins with `(:indent)` (as does `\indent` inside a paragraph). A display ends the paragraph; the text after it is a new one. |
| `(:glue :glue g :command c)` | Glue `g` as `\the` shows it (`"1.0pt plus 1.0fil"`), from the command `c` (`"hskip"`, `"vfil"`, …, or `"parskip"` before a paragraph). |
| `(:kern :width d)`, `(:penalty :value n)` | `\kern` (`:italic t` for `\/`) and `\penalty`. |
| `(:rule :kind k :width w :height h :depth d)` | `\hrule` or `\vrule` (`k` `:hrule` or `:vrule`); each dimension `"0.4pt"` or `:running`. |
| `(:language :number n :left-hyphen-min l :right-hyphen-min r)` | The paragraph's language changes before the next character (`\language`), or `\setlanguage`. |
| `(:begin :box :kind k :command c …)` … `(:end :box)` | A box placed in a list: `k` `:hbox` or `:vbox`, `c` `"hbox"`, `"vbox"` or `"vtop"`, then `:spec (:exactly d)`/`(:additional d)` when given, `:shift d` when moved (`\raise`, `\lower`, `\moveleft`, `\moveright`; down or right positive) and the `:width`, `:height`, `:depth` assigned to it.  A paragraph taken by `\lastbox` is an `"hbox"` with the paragraph's span. |
| `(:begin :leaders :kind k :glue g :command c)` … `(:end :leaders)` | Leaders: `k` `:leaders`, `:cleaders` or `:xleaders`, the glue `g` of the glue command `c` (`"hfil"`, `"vskip"`, …); the one child is the box or `(:rule …)` repeated. |
| `(:tex-mark :tokens …)` | A `\mark`, its text expanded. |
| `(:begin :discretionary :command c)` … `(:end :discretionary)` | `\-` or `\discretionary` (`c` `"-"` or `"discretionary"`): its non-empty lists, `(:begin :pre-break)` … `(:end :pre-break)`, then `:post-break`, then `:no-break` (the text when there is no break). |
| `(:begin :accent)` … `(:end :accent)` | `\accent`: the accent's `(:text …)`, then the accented character's when there is one. |
| `(:begin :insert :number n :split-top-skip g :split-max-depth d :floating-penalty p)` … `(:end :insert)`, `(:begin :vadjust)` … `(:end :vadjust)` | `\insert n{…}` and `\vadjust{…}`, their vertical lists. |
| `(:special :tokens …)` | `\special`, its text expanded. |
| `(:begin :shipout)` … `(:end :shipout)` | `\shipout`: the box shipped, in the outer list.  The writes it carries out follow it, as `\immediate`'s, flagged `:shipout t` instead of `:immediate t`. |
| `(:begin :math)` … `(:end :math)` | A formula (`:display t` for a display, which comes between paragraphs). |
| `(:begin :table …)`, `(:row)`, `(:cell)` | Alignments (planned). |
| `(:write :stream s :tokens …)` | A `\write`, its token list as scanned, unexpanded (TeX expands it only when the page holding it is shipped out). It carries index and reference data. Nothing is written to disk. `s` is 0–15, 16 (above 15: the terminal) or 17 (negative: the log). |
| `(:openout :stream s :file "name")`, `(:closeout :stream s)` | `\openout` and `\closeout`. |
| `(:write :stream s :tokens … :text "…" :immediate t)`, `(:openout … :immediate t)`, `(:closeout … :immediate t)` | The same after `\immediate`, carried out at once: the tokens are expanded and `:text` is what TeX would write.  An `\immediate\write` to a stream that is not open is no event but an entry of the job's log, and an `\immediate\closeout` of stream 16 or 17 closes nothing and is no event (`docs/tex-fidelity.md`). |
| `(:diagnostic …)` | A TeX error the job recovered from, or an unknown construct. |

Every event has a `:span`: where the command, character or list began
(`:end` events: what ended it, when known).  The expander builds the
events as nodes of TeX's lists (`src/expand/nodes.lisp`, `docs/tex-fidelity.md`,
"Lists and nodes"); `job-events` flattens the outer vertical list.
Properties hold strings, numbers, keywords, tokens, spans and lists of
them.  A box given again (`\box`, `\copy`, `\vsplit`, `\lastbox`)
keeps its original spans and gets the command's span in its `:via` list
(newest first); so does each node spliced by `\unhbox`, `\unhcopy`,
`\unvbox` or `\unvcopy`.

## Properties tests rely on

- The stream for a job is deterministic. A hash of it is a snapshot test.
- `:begin` and `:end` are balanced per entry.
- For each vocabulary entry, the number of events equals the number of its
  uses in the source (counted by `make vocab`, for the uses its survey does not flag as uncertain).

`make events FILE=… LINES=…` prints the events of the nodes appended
while the lines were read, one per line, nested ones indented, and the
lists still open when the job stops.
