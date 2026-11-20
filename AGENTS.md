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

# Repository layout

* `spec/tex/` — pristine dpANS3 TeX sources. Never edit; see `spec/PROVENANCE.md`.
* `patches/` — independent, numbered patches applied on top of `spec/tex/`.
* `src/` — the `cl-ansi-spec` system. `tests/` — `cl-ansi-spec/tests` (Parachute).
* `tools/` — command-line tools, written in Lisp; `make` is only a thin wrapper.
* `.deps/` — git-ignored checkouts of the dependencies pinned in `tools/deps.sexp`.

# Commands

* `make test` — fetch pinned deps, build from scratch into `build/` with *any*
  warning (style-warnings included) as an error, run the suite. Exit status is
  the verdict. Pipe through `tail -5` to read only the summary and save tokens.
* `make deps` — bring `.deps/` to the commits in `tools/deps.sexp`. Offline
  once fetched; broken checkouts are re-cloned automatically.
* `make clean` — remove `build/`. `make distclean` — also remove `.deps/`.
* `(cd spec/tex && sha256sum -c --quiet ../SHA256SUMS)` — verify pristine
  sources (also run in CI; `make test` checks the file list against it).

# Process

* Before each commit, run the `lisp-review` skill (`.claude/skills/lisp-review`):
  build gate + sub-agent review of the diff; fix or justify every finding.

# Environment notes

* No Quicklisp: dependencies are pinned by commit in `tools/deps.sexp` and
  cloned from GitHub (the cloud agent's network reaches GitHub only, so
  e.g. Alexandria/FiveAM from common-lisp.net are not usable).
* SBCL comes from apt (`apt-get install sbcl`) both locally and in CI.
