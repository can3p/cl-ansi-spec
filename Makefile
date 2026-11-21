# Thin wrapper around the Lisp tools in tools/.  All logic lives in Lisp.

SBCL ?= sbcl
LISP := $(SBCL) --noinform --non-interactive --no-sysinit --no-userinit

.PHONY: all deps test tokens clean distclean

all: test

deps:
	$(LISP) --load tools/deps.lisp

test: deps
	$(LISP) --load tools/test.lisp

# Dump the tokens of a spec file: make tokens FILE=chap-1 [LINES=10-20] [SKIPS=1]
tokens: deps
	@FILE='$(FILE)' LINES='$(LINES)' SKIPS='$(SKIPS)' $(LISP) --load tools/tokens.lisp

# Remove build outputs (fasls).
clean:
	rm -rf build

# Also remove the fetched dependencies (next build needs the network).
distclean: clean
	rm -rf .deps
