;;;; src/model/nodes-entries.lisp
;;;;
;;;; The node kinds of dictionary entries (docs/model.md, "Entries"): the
;;;; entry, its parts and its signatures, the enum of entry kinds and the
;;;; target kind that points to entries.
;;;; Owner: step 3.2 (shapes), then 3.9 of docs/plan/m3.md (documentation
;;;; and examples, through tests/model/undocumented-entries.sexp).

(in-package #:cl-ansi-spec/model)

(define-target-kind :entry (:area :entries :node :dictionary-entry)
  "A dictionary entry, by its id: the target of \\clref and its
wrappers (\\funref, \\macref, …).")

(define-enum entry-kind (:area :entries)
  "What a dictionary entry defines: the text of its \\ftype, in
kebab-case.  A variant spelling of one of these in the sources is fixed
by a patch, not by a value of its own."
  (:function "An ordinary function, called with evaluated arguments
(\\ftype{Function}).")
  (:system-class "A class the implementation may define as a built-in
class rather than a standard class (\\ftype{System Class}).")
  (:macro "A global macro, expanded before evaluation (\\ftype{Macro}).")
  (:condition-type "A type of condition, signalled to the handlers
(\\ftype{Condition Type}).")
  (:variable "A dynamic variable whose value may change
(\\ftype{Variable}).")
  (:type "A type that is not a class (\\ftype{Type}).")
  (:accessor "A function that reads a place and, through setf, writes
it (\\ftype{Accessor}).")
  (:standard-generic-function
   "A generic function of the standard, whose methods users may add\n(\\ftype{Standard Generic Function}).")
  (:special-operator "An operator with its own evaluation rule, not a
macro or function (\\ftype{Special Operator}).")
  (:type-specifier "A symbol that is only a compound type specifier,
naming no type alone (\\ftype{Type Specifier}).")
  (:constant-variable "A variable whose value never changes
(\\ftype{Constant Variable}).")
  (:declaration "The identifier of a declaration, used in declare and
proclaim (\\ftype{Declaration}).")
  (:restart "The name of a restart the standard establishes or invokes
(\\ftype{Restart}).")
  (:local-macro "A macro defined only within another form (\\ftype{Local Macro}).")
  (:class "A standard class, defined as by defclass (\\ftype{Class}).")
  (:symbol "A symbol described for its own sake, neither operator,
variable nor type (\\ftype{Symbol}).")
  (:local-function
   "A function defined only within another form (\\ftype{Local Function})."))

(define-enum operator (:area :entries)
  "The kind of operator a signature describes, by the macro that sets it."
  (:function "A function: \\Defun and its variants, \\DefunMultiWithValues.")
  (:macro "A macro: \\Defmac and its variants.")
  (:special-operator "A special operator: \\Defspec and its variants.")
  (:generic-function "A generic function: \\Defgen and its variants.")
  (:method "A method of a generic function: \\Defmeth."))

(define-node dictionary-entry (:area :entries)
  "A dictionary entry, from \\begincom to \\endcom: the description of
one or more defined names of one kind."
  (id :string :required t
   :doc "The entry's id: its first name, or <name>/<entry-kind> when two
entries share a first name (docs/exports.md, \"Ids\").")
  (names :string :required t :repeated t
   :doc "The names the entry describes, the comma-separated list of
\\begincom's first argument, in order.")
  (entry-kind (:enum entry-kind) :required t
   :doc "What the names are, from the entry's \\ftype.")
  (parts (:node :part) :repeated t
   :doc "The entry's parts, one per \\label, in order."))

(define-node part (:area :entries)
  "A part of a dictionary entry: a \\label heading (Syntax, Arguments and
Values, Description, …) and what follows it up to the next \\label or
the entry's end."
  (title :string :required t
   :doc "The heading, the text of the \\label before its colon.")
  (none :boolean
   :doc "True when the part says only \"None.\" (\\None after the
\\label).")
  (content (:node :block) :repeated t
   :doc "The part's blocks; absent when NONE is true."))

(define-node operator-signature (:area :entries :categories (:block))
  "The syntax of an operator as a Syntax part sets it: \\Defun,
\\Defmac, \\Defspec, \\Defgen and their WithValues, WithValuesNewline
and NoReturn variants, \\Defmeth, \\DefunMultiWithValues, and the
reader half of \\DefunMultiAccessorWithValues."
  (operator (:enum operator) :required t
   :doc "The kind of operator, by the macro.")
  (names :string :required t :repeated t
   :doc "The operator's name, or the names of the \\entry lines of a
-Multi form, which share the lambda list and values.")
  (lambda-list :inlines
   :doc "The lambda list as written, with its parameters and lambda list
keywords; absent when empty.")
  (values :inlines
   :doc "The values as written after the arrow; absent for a form
without values (\\Defun, \\Defmeth) and when NO-RETURN is true.")
  (no-return :boolean
   :doc "True for a NoReturn form: the operator never returns normally."))

(define-node setf-signature (:area :entries :categories (:block))
  "The syntax of a setf form: \\Defsetf, \\DefsetfMulti, and the setf
half of \\DefunMultiAccessorWithValues."
  (names :string :required t :repeated t
   :doc "The accessor's name, or the names of the \\entry lines of a
-Multi form.")
  (lambda-list :inlines
   :doc "The accessor's lambda list as written; absent when empty.")
  (new-value :inlines :required t
   :doc "The new value as written."))

(define-node variable-signature (:area :entries :categories (:block))
  "The syntax of a variable or a constant: \\Defvar, \\Defvarnoast,
\\Defcon."
  (name :string :required t
   :doc "The variable's name, with its asterisks when the source sets
them.")
  (constant :boolean
   :doc "True for a constant variable (\\Defcon)."))

(define-node type-signature (:area :entries :categories (:block))
  "The syntax of a compound type specifier: \\Deftype."
  (name :string :required t
   :doc "The type specifier's symbol.")
  (syntax :inlines
   :doc "The lines of the compound form after the name, with their BNF
notation; absent when there are none."))
