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
| `(:text "…" :style s)` | A run of characters. `s` is the current font identifier; phase 4 maps fonts to meaning only outside vocabulary entries. |
| `(:space)`, `(:par)` | Inter-word space and end of paragraph. |
| `(:begin :box …)`, `(:begin :math …)`, `(:begin :table …)`, `(:row)`, `(:cell)` | Presentational structure that is kept. |
| `(:write :stream s :tokens …)` | A `\write`, its token list as scanned, unexpanded (TeX expands it only when the page holding it is shipped out). It carries index and reference data. Nothing is written to disk. `s` is 0–15, 16 (above 15: the terminal) or 17 (negative: the log). |
| `(:openout :stream s :file "name")`, `(:closeout :stream s)` | `\openout` and `\closeout`. |
| `(:write :stream s :tokens … :text "…" :immediate t)`, `(:openout … :immediate t)`, `(:closeout … :immediate t)` | The same after `\immediate`, carried out at once: the tokens are expanded and `:text` is what TeX would write.  An `\immediate\write` to a stream that is not open is no event but an entry of the job's log, and an `\immediate\closeout` of stream 16 or 17 closes nothing and is no event (`docs/tex-fidelity.md`). |
| `(:diagnostic …)` | A TeX error the job recovered from, or an unknown construct. |

Every event has a `:span`.  Main control emits the write events
(`src/expand/streams.lisp`, `job-events`); the others are planned. An event inside a box that is replayed
(`\box`, `\copy`) keeps its original span and gets a `:via` span for the
replay.

## Properties tests rely on

- The stream for a job is deterministic. A hash of it is a snapshot test.
- `:begin` and `:end` are balanced per entry.
- For each vocabulary entry, the number of events equals the number of its
  uses in the source (counted by `make vocab`, for the uses its survey does not flag as uncertain).

`make events FILE=… LINES=…` (planned) prints the stream compactly.
