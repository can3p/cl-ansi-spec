# Thin wrapper around the Lisp tools in tools/.  All logic lives in Lisp.

SBCL ?= sbcl
LISP := $(SBCL) --noinform --non-interactive --no-sysinit --no-userinit

.PHONY: all deps test tokens vocab expand clean distclean

all: test

deps:
	$(LISP) --load tools/deps.lisp

test: deps
	$(LISP) --load tools/test.lisp

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

# Remove build outputs (fasls).
clean:
	rm -rf build

# Also remove the fetched dependencies (next build needs the network).
distclean: clean
	rm -rf .deps
