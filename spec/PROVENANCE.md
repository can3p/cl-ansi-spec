# Provenance of `spec/tex/`

The files in `spec/tex/` are the TeX sources of the ANSI Common Lisp draft
standard (dpANS3, X3J13), copied **verbatim** from

- repository: https://github.com/LispLang/ansi-spec
- directory:  `tex/`
- commit:     `e18e52daf7dc5618527a68b7323b8ed7fb1c781a` (2019-05-21)

That repository obtained them from the CMU AI Repository
(`lang/lisp/doc/standard/ansi/dpans/dpans3.tgz`), removing only the `.dvi.Z`
files. The draft text was released by X3J13 for free distribution; the
LispLang repository's own code is MIT-licensed (Copyright (c) 2014-2019
Fernando Borretti).

## Rules

- **Never edit files under `spec/tex/` by hand.** Corrections go in
  `patches/` as independent, numbered patches (see `patches/README.md`).
- `spec/SHA256SUMS` records the pristine contents. Verify with:

  ```sh
  (cd spec/tex && sha256sum -c ../SHA256SUMS)
  ```

## Known facts about the sources

- 132 files, pure ASCII, LF line endings (tabs present in many files).
- Every `\input` target exists except `chap-N.fig` and `chap-N.tc`: those
  are figure lists / tables of contents that TeX generated during a run.
  The parser must synthesise their equivalents.
- `\input\jobname.toc` / `\input\jobname.idx` likewise refer to generated
  files.
