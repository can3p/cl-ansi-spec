;;;; src/model/nodes-math.lisp
;;;;
;;;; The node kinds of math (docs/model.md, "Math"): formulas as a small
;;;; tree of noads, characters, fractions, delimiters and styles, nothing
;;;; typeset; characters are Unicode by font family.
;;;; Owner: step 3.2 (shapes), then 3.15m of docs/plan/m3.md
;;;; (documentation and examples; 3.15m also added the fields NUMBER-LEFT,
;;;; THICKNESS and the enum MATH-LIMITS, which the events carry and the
;;;; shapes of 3.2 had no place for).

(in-package #:cl-ansi-spec/model)

(define-category :math-element (:area :math)
  "What a formula's list holds: noads, characters, fractions,
delimiters, style changes and \\mathchoice.  A formula keeps what TeX's
math list holds, minus the typesetting.  Its fields also take inlines,
since the sources set words in a formula with a font wrapper
(`\\ff{arccos}` is code), which the vocabulary turns into one.")

(define-enum math-class (:area :math)
  "The class of a noad, as TeX gives it: the spacing and the limits of
the noad follow from it.  The class comes from a character's math code
\\mathcode, a \\mathord-like command or the construct (a \\left … \\right
is an inner noad)."
  (:ord "An ordinary symbol: a letter, a digit, a subformula in braces.")
  (:op "A large operator (a sum, an integral, \\log): \\mathop and its
relatives.")
  (:bin "A binary operation: +, −, \\cdot.")
  (:rel "A relation: =, ≤, →.")
  (:open "An opening delimiter: ( or [.")
  (:close "A closing delimiter: ) or ].")
  (:punct "Punctuation: a comma, a semicolon.")
  (:inner "A delimited subformula (\\left … \\right), or \\ldots.")
  (:underline "An underlined subformula (\\underline).")
  (:overline "An overlined subformula (\\overline).")
  (:vcenter "A box centred on the axis (\\vcenter).")
  (:radical "A radical (\\radical, \\sqrt), its sign the noad's delimiter.")
  (:accent "An accented nucleus (\\mathaccent, \\hat), its accent the noad's
delimiter."))

(define-enum math-limits (:area :math)
  "Where an operator's scripts go, when the source said."
  (:limits "\\limits: the scripts go above and below.")
  (:no-limits "\\nolimits: the scripts go beside the operator."))

(define-enum math-style (:area :math)
  "A style of math, as TeX names it."
  (:display "Display style (\\displaystyle).")
  (:text "Text style (\\textstyle).")
  (:script "Script style (\\scriptstyle).")
  (:scriptscript "Scriptscript style (\\scriptscriptstyle)."))

(define-node math
    (:area :math :categories (:inline :block)
     :example (:math :display t
               :content ((:math-fraction :numerator ((:math-char :text "π"))
                          :denominator ((:math-char :text "2"))))))
  "A formula: inline between $ and $ (an inline of its paragraph), or
displayed between $$ and $$ (a block between paragraphs).  Its content is
TeX's math list; for example `$$ \\ff{arccos} z = {\\pi\\over2} - \\ff{arcsin} z $$`
at dict-numbers.tex:1435 is one displayed formula."
  (display :boolean :example t
   :doc "True for a displayed formula, false for an inline one.")
  (content (:node :math-element :inline) :repeated t
   :example ((:math-char :text "x"))
   :doc "The formula's list, in order; absent for an empty formula.")
  (equation-number (:node :math-element :inline) :repeated t
   :example ((:math-char :text "("))
   :doc "A display's equation number, set by \\eqno or \\leqno; absent when
it has none.")
  (number-left :boolean :example nil
   :doc "True when the equation number was set by \\leqno (at the left),
false for \\eqno; absent with no number."))

(define-node math-noad
    (:area :math :categories (:math-element)
     :example (:math-noad :class :op :limits :no-limits
               :nucleus ((:math-char :text "l") (:math-char :text "o")
                         (:math-char :text "g"))))
  "A noad: a nucleus of some class with its scripts, TeX's unit of math
before typesetting.  Every character of a formula is the nucleus of one;
braces make a subformula the nucleus of an ordinary noad."
  (class (:enum math-class) :required t :example :ord
   :doc "The noad's class.")
  (limits (:enum math-limits) :example :limits
   :doc "\\limits or \\nolimits after an operator; absent when the source
says neither (TeX then decides by the style).")
  (delimiter :string :example "√"
   :doc "A radical's sign or an accent's character, as Unicode; absent for
the other classes.")
  (nucleus (:node :math-element :inline) :repeated t
   :example ((:math-char :text "x"))
   :doc "The nucleus: one character, or a subformula; absent for {}.")
  (superscript (:node :math-element :inline) :repeated t
   :example ((:math-char :text "2"))
   :doc "The superscript (^); absent when none.")
  (subscript (:node :math-element :inline) :repeated t
   :example ((:math-char :text "i"))
   :doc "The subscript (_, which the sources reach through \\sub); absent
when none."))

(define-node math-char
    (:area :math :categories (:math-element)
     :example (:math-char :text "π"))
  "A character of a formula, mapped from its family's font to Unicode by
the tables of build-math.lisp (TeX holds a family and a code; the model
keeps what they show)."
  (text :string :required t :example "π"
   :doc "The character, as Unicode.  A font whose slot has no Unicode of
its own (an extensible piece) is U+FFFD, and the build report says so;
no character is guessed."))

(define-node math-fraction
    (:area :math :categories (:math-element)
     :example (:math-fraction :numerator ((:math-char :text "π"))
               :denominator ((:math-char :text "2"))))
  "A fraction: \\over, \\atop, \\above and their withdelims forms
(\\overwithdelims, …), as at dict-numbers.tex:1435."
  (numerator (:node :math-element :inline) :repeated t
   :example ((:math-char :text "π")) :doc "The numerator; absent when empty.")
  (denominator (:node :math-element :inline) :repeated t
   :example ((:math-char :text "2")) :doc "The denominator; absent when empty.")
  (no-rule :boolean :example nil
   :doc "True when no bar separates the two: \\atop, or a thickness of zero.")
  (thickness :string :example "1.0pt"
   :doc "The bar's thickness as written, for \\above; absent for the
font's default (\\over, \\atop).")
  (left-delimiter :string :example "("
   :doc "The delimiter on the left of a withdelims form, as Unicode; absent
for the other forms.")
  (right-delimiter :string :example ")"
   :doc "The delimiter on the right of a withdelims form, as Unicode;
absent for the other forms."))

(define-node math-delimiter
    (:area :math :categories (:math-element)
     :example (:math-delimiter :right nil :text "{"))
  "A delimiter that grows with its subformula: \\left or \\right, which
open and close an inner noad (dict-arrays.tex:27 sets a set in braces)."
  (right :boolean :example nil
   :doc "True for \\right, false for \\left.")
  (text :string :example "{"
   :doc "The delimiter, as Unicode; absent for the null delimiter (the
period: \\left. or \\right.)."))

(define-node math-style-change
    (:area :math :categories (:math-element)
     :example (:math-style-change :style :script))
  "A change of style within a formula: \\displaystyle, \\textstyle,
\\scriptstyle, \\scriptscriptstyle."
  (style (:enum math-style) :required t :example :script
   :doc "The style in force from here, to the end of the group."))

(define-node math-choice
    (:area :math :categories (:math-element)
     :example (:math-choice :display ((:math-char :text "A"))
               :text ((:math-char :text "a"))))
  "\\mathchoice: four subformulas, of which TeX sets the one for the
style in force; all four are kept, since which one shows is a matter of
typesetting."
  (display (:node :math-element :inline) :repeated t
   :example ((:math-char :text "A")) :doc "For display style; absent when empty.")
  (text (:node :math-element :inline) :repeated t
   :example ((:math-char :text "a")) :doc "For text style; absent when empty.")
  (script (:node :math-element :inline) :repeated t
   :example ((:math-char :text "a")) :doc "For script style; absent when empty.")
  (scriptscript (:node :math-element :inline) :repeated t
   :example ((:math-char :text "a"))
   :doc "For scriptscript style; absent when empty."))
