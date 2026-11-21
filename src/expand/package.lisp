;;;; src/expand/package.lisp
;;;;
;;;; Phase 2, the expander: TeX's semantics below typesetting
;;;; (docs/architecture.md, docs/tex-fidelity.md).  So far it holds TeX's
;;;; quantities: integers, dimensions and glue, with TeX's exact
;;;; arithmetic, units and printing.

(defpackage #:cl-ansi-spec/expand
  (:use #:cl)
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
   #:format-scaled #:format-dimen #:format-glue))
