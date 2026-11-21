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
                #:control-sequence #:token #:token=)
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
   #:primitive-operation
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
   #:load-font))
