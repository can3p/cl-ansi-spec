;;;; src/model/nodes-bnf.lisp
;;;;
;;;; The node kinds of syntax descriptions (docs/model.md, "Syntax"): BNF
;;;; rules and the inlines of the notation (concept-definitions.tex,
;;;; "Notational Conventions"), in lambda lists and syntax as in rules.
;;;; Owner: step 3.2 (shapes), then 3.15 of docs/plan/m3.md (documentation
;;;; and examples, through tests/model/undocumented-bnf.sexp).

(in-package #:cl-ansi-spec/model)

(define-node bnf-rule (:area :bnf :categories (:block))
  "A BNF rule: \\auxbnf, a non-terminal and its definition."
  (name :string :required t :doc "The non-terminal defined.")
  (definition :inlines :required t
   :doc "The right side, with its notation and line breaks."))

(define-node bnf-break (:area :bnf :categories (:inline))
  "A line break within the right side of a BNF rule: \\CR.")

(define-node bnf-optional (:area :bnf :categories (:inline))
  "What may appear once or not at all, in brackets: \\brac, or \\lbrac
… \\rbrac split over lines."
  (content :inlines :required t :doc "The optional part."))

(define-node bnf-zero-or-more (:area :bnf :categories (:inline))
  "What may appear any number of times, starred: \\star."
  (content :inlines :required t :doc "What repeats."))

(define-node bnf-one-or-more (:area :bnf :categories (:inline))
  "What appears one or more times, with a plus: \\plus."
  (content :inlines :required t :doc "What repeats."))

(define-node bnf-repeat-previous (:area :bnf :categories (:inline))
  "A plus alone: what precedes appears one or more times (\\prevplus,
after a group split over lines).")

(define-node bnf-group (:area :bnf :categories (:inline))
  "A group, usually of alternatives, in braces: \\curly, or \\lcurly …
\\rcurly split over lines."
  (content :inlines :required t :doc "The group's content."))

(define-node bnf-parenthesized (:area :bnf :categories (:inline))
  "Its content in literal parentheses: \\paren, or \\lparen … \\rparen."
  (content :inlines :required t :doc "What the parentheses hold."))

(define-node bnf-bracketed (:area :bnf :categories (:inline))
  "Its content in literal brackets, in the code font: \\ttbrac, or
\\lttbrac … \\rttbrac."
  (content :inlines :required t :doc "What the brackets hold."))

(define-node bnf-interleave (:area :bnf :categories (:inline))
  "Alternatives in any order, each at most once: \\interleave, or
\\begininterleave … \\endinterleave."
  (content :inlines :required t :doc "The alternatives."))

(define-node bnf-required (:area :bnf :categories (:inline))
  "Within an interleaving, what must appear exactly once: \\one."
  (content :inlines :required t :doc "What is required."))

(define-node bnf-indirection (:area :bnf :categories (:inline))
  "A non-terminal whose definition is spliced in place: \\down."
  (name :string :required t :doc "The non-terminal."))

(define-node bnf-caret (:area :bnf :categories (:inline))
  "The caret character `^' of a syntax description: \\hat.")

(define-node angle-name (:area :bnf :categories (:inline))
  "A name in angle brackets: \\ang, the names of characters
(\\NewlineChar) and \\noargs."
  (name :string :required t :doc "The name, e.g. \"Newline\"."))
