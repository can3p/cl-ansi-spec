# Thin wrapper around the Lisp tools in tools/.  All logic lives in Lisp.

SBCL ?= sbcl
LISP := $(SBCL) --noinform --non-interactive --no-sysinit --no-userinit

.PHONY: all deps test snapshots generate export patched tokens vocab expand events model clean distclean

all: test

deps:
	$(LISP) --load tools/deps.lisp

test: deps
	$(LISP) --load tools/test.lisp

# Rewrite tests/snapshots.sexp from the current events of every chapter job.
snapshots: deps
	$(LISP) --load tools/snapshots.lisp

# Rewrite the generated files (JSON Schema, reference doc) from the node
# declarations.
generate: deps
	$(LISP) --load tools/generate.lisp

# Write the export of the whole spec to build/export/ (or OUT=dir).
export: deps
	@OUT='$(OUT)' $(LISP) --load tools/export.lisp

# Write the patched spec tree to build/patched/ (reading and diffing only).
patched: deps
	$(LISP) --load tools/patched.lisp

# Dump the tokens of a spec file: make tokens FILE=chap-1 [LINES=10-20] [SKIPS=1]
tokens: deps
	@FILE='$(FILE)' LINES='$(LINES)' SKIPS='$(SKIPS)' $(LISP) --load tools/tokens.lisp

# Survey the macros the sources define and use (no expansion):
# make vocab [JOB=chap-1] [FILE=setup-aux.tex] [NAME=\term] [LIMIT=40]
vocab: deps
	@JOB='$(JOB)' FILE='$(FILE)' NAME='$(NAME)' LIMIT='$(LIMIT)' $(LISP) --load tools/vocab.lisp

# Expand a spec file as a TeX job: make expand FILE=chap-1 [LINES=10-20]
expand: deps
	@FILE='$(FILE)' LINES='$(LINES)' $(LISP) --load tools/expand.lisp

# The events of a spec file's lines: make events FILE=chap-1 [LINES=10-20]
events: deps
	@FILE='$(FILE)' LINES='$(LINES)' EVENTS=1 $(LISP) --load tools/expand.lisp

# The model built from a spec file's lines: make model FILE=chap-1 [LINES=10-20] [JOB=chap-1]
model: deps
	@FILE='$(FILE)' LINES='$(LINES)' JOB='$(JOB)' $(LISP) --load tools/model.lisp

# Remove build outputs (fasls).
clean:
	rm -rf build

# Also remove the fetched dependencies (next build needs the network).
distclean: clean
	rm -rf .deps
