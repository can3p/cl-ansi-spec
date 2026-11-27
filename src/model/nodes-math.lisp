;;;; src/model/nodes-math.lisp
;;;;
;;;; The node kinds of math (docs/model.md, "Math"): formulas as a small
;;;; tree of noads, characters, fractions, delimiters and styles, nothing
;;;; typeset; characters are Unicode by font family.
;;;; Owner: step 3.2 (shapes), then 3.15m of docs/plan/m3.md
;;;; (documentation and examples, through tests/model/undocumented-math.sexp).

(in-package #:cl-ansi-spec/model)

(define-category :math-element (:area :math)
  "What a formula's list holds: noads, characters, fractions,
delimiters and style changes.")

(define-enum math-class (:area :math)
  "The class of a noad, as TeX gives it."
  (:ord "An ordinary symbol.")
  (:op "A large operator (a sum, an integral).")
  (:bin "A binary operation.")
  (:rel "A relation.")
  (:open "An opening delimiter.")
  (:close "A closing delimiter.")
  (:punct "Punctuation.")
  (:inner "A delimited subformula (\\left … \\right).")
  (:underline "An underlined subformula (\\underline).")
  (:overline "An overlined subformula (\\overline).")
  (:vcenter "A box centred on the axis (\\vcenter).")
  (:radical "A radical (\\radical), its sign the noad's delimiter.")
  (:accent "An accented nucleus (\\mathaccent), its accent the noad's."))

(define-enum math-style (:area :math)
  "A style of math, as TeX names it."
  (:display "Display style (\\displaystyle).")
  (:text "Text style (\\textstyle).")
  (:script "Script style (\\scriptstyle).")
  (:scriptscript "Scriptscript style (\\scriptscriptstyle)."))

(define-node math (:area :math :categories (:inline :block))
  "A formula: inline between $ and $, or displayed between $$ and $$."
  (display :boolean :doc "True for a displayed formula.")
  (content (:node :math-element) :repeated t
   :doc "The formula's list, in order.")
  (equation-number (:node :math-element) :repeated t
   :doc "A display's equation number, \\eqno or \\leqno; absent when it
has none."))

(define-node math-noad (:area :math :categories (:math-element))
  "A noad: a nucleus of some class with its scripts."
  (class (:enum math-class) :required t :doc "The noad's class.")
  (limits :boolean
   :doc "True for an operator whose scripts go above and below
(\\limits).")
  (delimiter :string
   :doc "A radical's sign or an accent's character, as Unicode; absent
for other classes.")
  (nucleus (:node :math-element) :repeated t
   :doc "The nucleus: one character, or a subformula; absent for {}.")
  (superscript (:node :math-element) :repeated t
   :doc "The superscript; absent when none.")
  (subscript (:node :math-element) :repeated t
   :doc "The subscript; absent when none."))

(define-node math-char (:area :math :categories (:math-element))
  "A character of a formula, mapped from its family's font to Unicode."
  (text :string :required t :doc "The character, as Unicode."))

(define-node math-fraction (:area :math :categories (:math-element))
  "A fraction: \\over, \\atop, \\above and their withdelims forms."
  (numerator (:node :math-element) :repeated t :doc "The numerator.")
  (denominator (:node :math-element) :repeated t :doc "The denominator.")
  (no-rule :boolean
   :doc "True when no bar separates the two (\\atop, or a zero
thickness).")
  (left-delimiter :string
   :doc "The delimiter on the left of a withdelims form, as Unicode;
absent otherwise.")
  (right-delimiter :string
   :doc "The delimiter on the right of a withdelims form, as Unicode;
absent otherwise."))

(define-node math-delimiter (:area :math :categories (:math-element))
  "A delimiter that grows with its subformula: \\left or \\right."
  (right :boolean :doc "True for \\right, false for \\left.")
  (text :string
   :doc "The delimiter, as Unicode; absent for the null delimiter (.)."))

(define-node math-style-change (:area :math :categories (:math-element))
  "A change of style within a formula: \\displaystyle, \\textstyle,
\\scriptstyle, \\scriptscriptstyle."
  (style (:enum math-style) :required t :doc "The new style."))

(define-node math-choice (:area :math :categories (:math-element))
  "\\mathchoice: four subformulas, of which TeX sets the one for the
style in force; all four are kept."
  (display (:node :math-element) :repeated t :doc "For display style.")
  (text (:node :math-element) :repeated t :doc "For text style.")
  (script (:node :math-element) :repeated t :doc "For script style.")
  (scriptscript (:node :math-element) :repeated t
   :doc "For scriptscript style."))
