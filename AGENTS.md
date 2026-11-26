# Ground rules

* Everything should be written in Common Lisp
* CI/CD is a must
* Tests are a must
* Do not make shortcuts, the parser should be full
* Do not trust your self alone, run sub agents for the code review
* Extract skills as you go and enhance them - quality control, code review
* Write clean idiomatic common lisp code
* End goal is a clean render based on the source spec
* Any future adjustments to the spec will should go as a list of indepentent patches.
* Defer simple work to simple models, smart models set direction and coordinate
* Save tokens, make tools that help reducing the usage and encode their usage in this file
* main branch should be usable at any point in time
* do not improvise, plan your actions
* The Common Lisp HyperSpec may be **consulted** to resolve ambiguity while
  parsing, but **never borrow anything from it** (text, markup, structure,
  examples, links) — its license forbids it. Everything rendered comes from
  `spec/tex/` (plus `patches/`).
* Keep the plan in `PLAN.md` (an index) and `docs/plan/<id>.md` (the running
  milestone), so that any new session can pick up where the last one
  stopped. Update it in the same commit as the work.
* End goal and design: `docs/architecture.md`. The product is a semantic
  model of the standard, not a TeX rendering; keep the code modular (one
  package per phase, one-way dependencies).

# Repository layout

* `spec/tex/` — pristine dpANS3 TeX sources. Never edit; see `spec/PROVENANCE.md`.
* `vendor/plain/` — Knuth's `plain.tex` and `hyphen.tex`, unmodified (their
  licence requires it). Never edit; see `vendor/PROVENANCE.md`.
* `patches/` — independent, numbered patches applied on top of `spec/tex/`.
* `src/` — the `cl-ansi-spec` system. `tests/` — `cl-ansi-spec/tests` (Parachute).
* `tools/` — command-line tools, written in Lisp; `make` is only a thin wrapper.
* `docs/` — `architecture.md` (start here), `process.md`, topic docs (`reader`, `events`,
  `vocabulary`, `tex-fidelity`, `model`, `exports`), `plan/<id>.md`
  (running milestone), `history/` (finished milestones; not read by default).
* `.deps/` — git-ignored checkouts of the dependencies pinned in `tools/deps.sexp`.

# Commands

* `make test` — fetch pinned deps, build from scratch into `build/` with *any*
  warning (style-warnings included) as an error, run the suite. Exit status is
  the verdict. Pipe through `tail -5` to read only the summary and save tokens.
  It also checks that the docs name only existing paths and make targets
  (mark the rest `(planned)`; rules in `docs/process.md`).
* `make deps` — bring `.deps/` to the commits in `tools/deps.sexp`. Offline
  once fetched; broken checkouts are re-cloned automatically.
* `make tokens FILE=chap-1 [LINES=10-20] [SKIPS=1]` — dump a spec file's
  tokens, one `LINE:COL<tab>TOKEN` per line (character tokens as
  `<char> <catcode>`), under plain catcodes and without expansion. Always
  pass `LINES` to keep the output small; `SKIPS=1` also lists comments,
  skipped spaces, etc.
* `make vocab [JOB=chap-1] [FILE=setup-aux.tex] [NAME=\term] [LIMIT=40]` —
  survey of the control sequences the sources define and use, without
  expansion: one line per name (class, first definition, text/body/
  uncertain uses, files), most used first; `NAME=` details one macro. All
  chapter jobs unless `JOB=`; keep `LIMIT` small. Rules: `docs/vocabulary.md`.
* `make expand FILE=chap-1 [LINES=10-20]` — run a spec file as a TeX job
  (INITEX with plain catcodes) through main control and print what it hands
  on to later steps (events, alignments, input/output),
  `FILE:LINE:COL<tab>TOKEN<tab>MODE`, TeX errors as `!! …` and TeX's notes
  as `-- (…)`.  Always
  pass `LINES`, and a timeout: while jobs do not load plain TeX first, a
  chapter job may loop for ever, as TeX would.
* `make clean` — remove `build/`. `make distclean` — also remove `.deps/`.
* `(cd spec/tex && sha256sum -c --quiet ../SHA256SUMS)` and
  `(cd vendor/plain && sha256sum -c --quiet ../SHA256SUMS)` — verify pristine
  sources (also run in CI; `make test` checks both file lists against them).

# Process

See `docs/process.md`. In short:

* New session: read `PLAN.md`, `docs/architecture.md` and the current
  `docs/plan/<id>.md`; continue at its first unchecked step.
* Before implementing a step: `plan-critic` skill. To finish it: `step-close`
  skill (docs up to date, `lisp-review`, plan ticked, one commit). To finish
  a milestone: `milestone-close` skill.

# Reading economy

Context is re-read on every turn; what you load early you pay for all
session.

* Learn the project from `docs/`, not from the code. Each topic doc has a
  file table; open code only for the step at hand.
* Never `cat` whole directories or several source files at once. To see a
  file's contents: its header (`head -12 FILE`) and its definitions
  (`grep -n '^(def' FILE`), then `Read` only the line ranges you need.
* Never read whole `spec/tex/` files: `grep -n` them, `make tokens … LINES=`,
  or `sed -n 'a,bp'`.
* Pipe long command output through `tail`/`head`, or write it to a file in
  the scratchpad and grep that file.
* Every sub-agent brief names what to read (docs and line ranges), forbids
  whole-file and whole-directory reads, gives a tool-call budget, and asks
  for a bounded answer (word limit, fixed format).

# Environment notes

* No Quicklisp: dependencies are pinned by commit in `tools/deps.sexp` and
  cloned from GitHub (the cloud agent's network reaches GitHub only, so
  e.g. Alexandria/FiveAM from common-lisp.net are not usable).
* SBCL comes from apt (`apt-get install sbcl`) both locally and in CI.
