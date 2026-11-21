# Provenance of `vendor/plain/`

Every TeX job starts from the state after Knuth's plain TeX format has been
run through our expander (`docs/tex-fidelity.md`, "Jobs"). The two files of
that format are copied **verbatim** from

- package:  `texlive-base`, version `2023.20240207-1` (Debian's packaging,
  as shipped by Ubuntu 24.04 "noble")
- archive:  `http://archive.ubuntu.com/ubuntu/pool/universe/t/texlive-base/texlive-base_2023.20240207-1_all.deb`
- `.deb` SHA-256: `d5fb8e71ede65344896349498fc9d8931dfdc69892c601f0c406c2767ccd6216`

| File | Path in the package | Notes |
|------|---------------------|-------|
| `plain.tex` | `usr/share/texlive/texmf-dist/tex/plain/base/plain.tex` | `\fmtversion` 3.1415926535 |
| `hyphen.tex` | `usr/share/texlive/texmf-dist/tex/generic/hyphen/hyphen.tex` | Knuth's hyphenation patterns |

To reproduce: `apt-get download texlive-base=2023.20240207-1`, then
`dpkg-deb -x` the package and compare with `vendor/SHA256SUMS`.

## Licence

Both files permit unlimited copying and redistribution **as long as they
are not modified**; a modified file must not keep its name (see the header
of each file). Hence:

- **Never edit files under `vendor/plain/`.** `patches/` applies only to
  `spec/tex/`, never here.
- `vendor/SHA256SUMS` records the pristine contents. Verify with:

  ```sh
  (cd vendor/plain && sha256sum -c ../SHA256SUMS)
  ```

## Known facts about the files

- Pure ASCII, LF line endings.
- A closed set: `\input hyphen` is the only `\input` in `plain.tex`, and
  `hyphen.tex` inputs nothing.
- `plain.tex` ends by defining `\fmtname`; it has no `\dump` (INITEX users
  add one). Our snapshot of the state replaces it.
- `plain.tex` loads fonts (`\font\tenrm=cmr10`, ...). No font metric
  files are vendored: fonts are identifiers without metrics
  (`docs/tex-fidelity.md`, "Not emulated").
