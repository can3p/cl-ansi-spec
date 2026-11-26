;;;; src/expand/package.lisp
;;;;
;;;; Phase 2, the expander: TeX's semantics below typesetting
;;;; (docs/architecture.md, docs/tex-fidelity.md).  So far it holds TeX's
;;;; quantities (integers, dimensions and glue, with TeX's exact
;;;; arithmetic, units and printing), and its state: meanings, registers,
;;;; parameters, codes and fonts over the reader's save stack.

(defpackage #:cl-ansi-spec/expand
  (:use #:cl)
  (:import-from #:cl-ansi-spec/tex
                #:tex-state #:make-initex-state
                #:make-equivalents #:equivalent #:assign
                #:integer-parameter #:set-integer-parameter
                #:catcode #:set-catcode #:lccode #:set-lccode #:uccode #:set-uccode
                #:character-code #:catcode-value
                #:control-sequence #:token #:token= #:span #:token-span
                #:+begin-group+ #:+end-group+ #:+parameter+ #:+space+
                #:+letter+ #:+other+ #:+math-shift+ #:+alignment-tab+
                #:+superscript+ #:+subscript+
                #:cs-token #:cs-token-p #:cs-token-control-sequence #:make-cs-token
                #:character-token #:character-token-p #:character-token-code
                #:character-token-catcode #:make-character-token
                #:intern-control-sequence #:make-frozen-control-sequence
                #:control-sequence-name #:control-sequence-active-p
                #:input-stack #:make-input-stack #:input-stack-file-end-hook
                #:next-token #:back-input #:push-tokens #:push-file
                #:end-current-file #:input-file-missing #:current-line-number)
  (:export
   ;; Integers and scaled values (arithmetic.lisp)
   #:+infinity+ #:+max-dimen+ #:+unity+
   #:tex-integer #:scaled
   #:x-over-n #:xn-over-d #:nx-plus-y #:mult-integers
   #:integer-advance #:integer-multiply #:integer-divide
   #:dimen-advance #:dimen-multiply #:dimen-divide
   #:round-decimals
   ;; Units (units.lisp)
   #:physical-units #:unit-conversion
   #:apply-true-magnification #:convert-physical-unit #:scale-by-unit
   #:attach-sign #:math-unit #:mu-multiply
   ;; Glue (glue.lisp)
   #:glue #:make-glue #:glue-p #:glue-width #:glue-stretch #:glue-shrink
   #:glue-stretch-order #:glue-shrink-order #:glue-mu-p #:glue-order
   #:glue=
   #:glue-advance #:glue-multiply #:glue-divide #:glue-negate
   #:mu-glue-to-glue
   ;; Printing (print.lisp)
   #:format-scaled #:format-dimen #:format-glue
   ;; Fonts (font.lisp)
   #:tex-font #:tex-font-p #:make-tex-font #:tex-font-file #:tex-font-size
   #:tex-font-identifier #:tex-font-hyphen-char #:tex-font-skew-char
   #:normalize-font-size #:font-dimen #:set-font-dimen
   ;; Meanings (meaning.lisp)
   #:meaning #:meaning-p #:meaning=
   #:macro #:macro-p #:make-macro #:macro-parameter-text #:macro-body
   #:macro-long-p #:macro-outer-p
   #:primitive #:primitive-p #:make-primitive #:primitive-name
   #:primitive-operation #:primitive-expandable-p
   #:character-meaning #:character-meaning-p #:make-character-meaning
   #:character-meaning-code #:character-meaning-catcode
   #:shorthand #:shorthand-p #:make-shorthand #:shorthand-kind
   #:shorthand-value
   ;; Parameters (parameters.lisp)
   #:parameter-names #:parameter-kind #:initex-integer-parameters
   #:initex-code
   ;; The expander state (state.lisp)
   #:expander-state #:make-expander-state #:es-tex #:es-null-font
   #:register-kind #:register-number #:code-kind
   #:effective-global
   #:set-meaning #:register #:set-register #:parameter #:set-parameter
   #:code #:set-code #:current-font #:set-current-font
   #:family-font #:set-family-font #:par-shape #:set-par-shape
   #:load-font
   ;; Errors (errors.lisp)
   #:tex-error #:tex-fatal-error #:tex-error-message #:tex-error-context
   #:tex-error-span #:recover #:call-recovering-tex-errors
   ;; Primitives (primitives.lisp)
   #:define-primitive #:find-primitive #:install-primitives
   #:tex82-command-names #:tex82-expandable-names
   ;; The expander (expander.lisp, show.lisp, macro.lisp, expandable.lisp)
   #:expander #:make-expander #:expander-state #:expander-input
   #:expander-job-name #:expander-scanner-status #:expander-align-state
   #:expander-marks #:scanner-status
   #:get-next #:get-token #:get-x-token #:back-token #:insert-tokens
   #:expand #:expandable-p #:frozen-control-sequence #:dont-expand-meaning
   #:cs-name-text #:token-list-text #:meaning-text #:string-tokens
   #:current-list
   ;; The nest and the page (nest.lisp)
   #:+ignore-depth+ #:mode #:mode-kind #:last-node-kind
   #:list-state #:make-list-state #:list-state-p #:list-state-mode
   #:list-state-prev-depth #:list-state-space-factor #:list-state-prev-graf
   #:list-state-last-node
   #:page-state #:page-state-so-far #:page-state-contents
   #:page-state-output-active #:page-state-last-penalty
   #:page-state-last-kern #:page-state-last-glue #:page-state-dead-cycles
   #:page-state-insert-penalties
   #:expander-nest #:expander-page #:expander-mag-set #:expander-last-badness
   ;; Scanning (scan.lisp, internal.lisp, dimen-scan.lisp, toks.lisp)
   #:scan-keyword #:scan-optional-equals #:scan-optional-space
   #:scan-left-brace #:get-x-nonblank #:get-x-nonblank-nonrelax
   #:scan-int #:scan-eight-bit-int #:scan-char-num #:scan-four-bit-int
   #:scan-fifteen-bit-int #:scan-twenty-seven-bit-int
   #:internal-command-p #:scan-something-internal
   #:box-dimension #:scan-font-ident #:find-font-dimen #:font-identifier-token
   #:prepare-mag #:scan-dimen #:scan-glue
   #:scan-toks #:the-toks
   #:format-roman #:font-name-text
   #:tex-font-parameter-count
   ;; Conditionals (conditionals.lisp)
   #:conditional #:conditional-p #:conditional-kind #:conditional-line
   #:conditional-limit #:expander-conditionals #:expander-skip-line
   #:expander-read-streams #:if-limit #:if-test-names #:pass-text #:box-kind))
