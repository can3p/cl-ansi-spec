;;;; src/model/nodes-bnf.lisp
;;;;
;;;; The node kinds of syntax descriptions (docs/model.md, "Syntax"): BNF
;;;; rules and the inlines of the notation (concept-definitions.tex,
;;;; "Notational Conventions"), in lambda lists and syntax as in rules.
;;;; Owner: step 3.2 (shapes), then 3.15 of docs/plan/m3.md (documentation
;;;; and examples, through tests/model/undocumented-bnf.sexp).

(in-package #:cl-ansi-spec/model)

(define-node bnf-rule (:area :bnf :categories (:block)
                      :example (:bnf-rule :name "wholevar"
                                :definition ((:bnf-bracketed :content ("&whole var")))))
  "A BNF rule: \\auxbnf, a non-terminal and its definition."
  (name :string :required t :doc "The non-terminal defined." :example "wholevar")
  (definition :inlines :required t
   :doc "The right side, with its notation and line breaks; the name and
the glyphs the notation macros typeset (brackets, parentheses, stars) are
not repeated in it."
   :example ((:bnf-bracketed :content ("&whole var")))))

(define-node bnf-break (:area :bnf :categories (:inline) :example (:bnf-break))
  "A line break within the right side of a BNF rule: \\CR.")

(define-node bnf-optional (:area :bnf :categories (:inline)
                    :example (:bnf-optional :content ("supplied-p-parameter")))
  "What may appear once or not at all, in brackets: \\brac, or \\lbrac
… \\rbrac split over lines."
  (content :inlines :required t :doc "The optional part." :example ("supplied-p-parameter")))

(define-node bnf-zero-or-more (:area :bnf :categories (:inline)
                    :example (:bnf-zero-or-more :content ((:bnf-group :content ("var")))))
  "What may appear any number of times, starred: \\star."
  (content :inlines :required t :doc "What repeats." :example ((:bnf-group :content ("var")))))

(define-node bnf-one-or-more (:area :bnf :categories (:inline)
                    :example (:bnf-one-or-more :content ("var")))
  "What appears one or more times, with a plus: \\plus."
  (content :inlines :required t :doc "What repeats." :example ("var")))

(define-node bnf-repeat-previous (:area :bnf :categories (:inline)
                    :example (:bnf-repeat-previous))
  "A plus alone: what precedes appears one or more times (\\prevplus,
after a group split over lines).")

(define-node bnf-group (:area :bnf :categories (:inline)
                    :example (:bnf-group :content ("var")))
  "A group, usually of alternatives, in braces: \\curly, or \\lcurly …
\\rcurly split over lines."
  (content :inlines :required t :doc "The group's content." :example ("var")))

(define-node bnf-parenthesized (:area :bnf :categories (:inline)
                    :example (:bnf-parenthesized :content ("keyword-name var")))
  "Its content in literal parentheses: \\paren, or \\lparen … \\rparen."
  (content :inlines :required t :doc "What the parentheses hold." :example ("keyword-name var")))

(define-node bnf-bracketed (:area :bnf :categories (:inline)
                    :example (:bnf-bracketed :content ("&rest var")))
  "Its content in literal brackets, in the code font: \\ttbrac, or
\\lttbrac … \\rttbrac."
  (content :inlines :required t :doc "What the brackets hold." :example ("&rest var")))

(define-node bnf-interleave (:area :bnf :categories (:inline)
                    :example (:bnf-interleave :content ((:bnf-required :content ("A")) " " (:bnf-required :content ("B")) " B")))
  "Alternatives in any order, each at most once: \\interleave, or
\\begininterleave … \\endinterleave."
  (content :inlines :required t :doc "The alternatives." :example ((:bnf-required :content ("A")) " B")))

(define-node bnf-required (:area :bnf :categories (:inline)
                    :example (:bnf-required :content ("A")))
  "Within an interleaving, what must appear exactly once: \\one."
  (content :inlines :required t :doc "What is required." :example ("A")))

(define-node bnf-indirection (:area :bnf :categories (:inline)
                    :example (:bnf-indirection :name "pattern"))
  "A non-terminal whose definition is spliced in place: \\down."
  (name :string :required t :doc "The non-terminal." :example "pattern"))

(define-node bnf-caret (:area :bnf :categories (:inline)
                    :example (:bnf-caret))
  "The caret character `^' of a syntax description: \\hat.")

(define-node angle-name (:area :bnf :categories (:inline)
                    :example (:angle-name :name "Newline"))
  "A name in angle brackets: \\ang, the names of characters
(\\NewlineChar) and \\noargs."
  (name :string :required t :doc "The name, e.g. \"Newline\"." :example "Newline"))
