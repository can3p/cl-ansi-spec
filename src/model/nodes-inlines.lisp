;;;; src/model/nodes-inlines.lisp
;;;;
;;;; The node kinds of inlines (docs/model.md, "Inlines"): the category
;;;; :inline, references (unresolved until 3.17-3.19 resolve them),
;;;; parameters, fonts by meaning, example notation, citations, index
;;;; entries and issue anchors.
;;;; Owner: step 3.2 (shapes), then 3.13 of docs/plan/m3.md (documentation
;;;; and examples, through tests/model/undocumented-inlines.sexp).

(in-package #:cl-ansi-spec/model)

(define-category :inline (:area :inlines)
  "What stands in running text beside strings: references, parameters,
code, emphasis, example notation, math, anchors.")

;;; References

(define-enum reference-kind (:area :inlines)
  "The macro a reference to a defined name was written with, which says
what kind of name it means."
  (:any "\\clref: a defined name of any kind.")
  (:function "\\funref: a function.")
  (:macro "\\macref: a macro.")
  (:special-operator "\\specref: a special operator.")
  (:type "\\typeref: a type or a class.")
  (:variable "\\varref: a variable.")
  (:constant "\\conref: a constant variable.")
  (:declaration "\\declref: a declaration identifier.")
  (:package "\\packref: a package.")
  (:keyword "\\kwd, \\kwdref: a keyword, written with its colon.")
  (:loop-keyword "\\loopref: a loop keyword.")
  (:lambda-list-keyword "\\keyref: a lambda list keyword, written with its
ampersand.")
  (:typewriter "\\ttref: a name set in the typewriter font.")
  (:misc "\\misc, \\miscref: a symbol of no other kind (t, nil, a
restart)."))

(define-node term-ref (:area :inlines :categories (:inline))
  "A use of a glossary term: \\term, or \\newterm and \\newtermidx where
the text defines the term."
  (text :string :required t
   :doc "The term as written, inflected (\"dotted lists\").")
  (defining :boolean
   :doc "True for \\newterm and \\newtermidx: the use defines the term.")
  (sense :integer
   :doc "The glossary sense meant, from the \\meaning that follows;
absent when none does.")
  (target (:target :glossary)
   :doc "The glossary entry of the term; absent while unresolved."))

(define-node operator-ref (:area :inlines :categories (:inline))
  "A reference to a defined name: \\clref and its wrappers."
  (text :string :required t
   :doc "The name as the reference sets it.")
  (via (:enum reference-kind) :required t
   :doc "The macro the reference was written with.")
  (target (:target :entry)
   :doc "The dictionary entry of the name; absent while unresolved."))

(define-node section-ref (:area :inlines :categories (:inline))
  "A reference to a section or a chapter: \\secref."
  (label :string :required t
   :doc "The label referred to, as written after \\secref.")
  (target (:target :section :chapter)
   :doc "The section or chapter of the label; absent while unresolved."))

(define-node figure-ref (:area :inlines :categories (:inline))
  "A reference to a figure: \\figref."
  (label :string :required t
   :doc "The label referred to, as written after \\figref.")
  (target (:target :figure)
   :doc "The figure of the label; absent while unresolved."))

(define-node this-section (:area :inlines :categories (:inline))
  "The words `this section': \\thissection, \\Thissection, a reference to
the section they are in."
  (target (:target :section)
   :doc "The section the words are in; absent while unresolved."))

(define-node next-figure (:area :inlines :categories (:inline))
  "The words `Figure N-M' for the figure that follows: \\thenextfigure,
\\Thenextfigure."
  (target (:target :figure)
   :doc "The next figure; absent while unresolved."))

;;; Names and fonts by meaning

(define-node param (:area :inlines :categories (:inline))
  "A parameter of the operator described: \\param."
  (name :string :required t :doc "The parameter's name."))

(define-node metavariable (:area :inlines :categories (:inline))
  "A metavariable, in double angle brackets: \\metavar, \\metaparam."
  (name :string :required t :doc "The metavariable's name."))

(define-node format-directive (:area :inlines :categories (:inline))
  "A format directive: \\formatOp, \\formatdirective."
  (name :string :required t
   :doc "The directive after its tilde, e.g. \"A\"."))

(define-node lambda-list-keyword (:area :inlines :categories (:inline))
  "A lambda list keyword in a lambda list: \\opt, \\rest, \\key and their
relatives."
  (name :string :required t
   :doc "The keyword with its ampersand, e.g. \"&optional\"."))

(define-node code (:area :inlines :categories (:inline))
  "Code within text: \\f, \\ff, and text in the typewriter font outside
vocabulary entries."
  (content :inlines :required t :doc "The code's text."))

(define-node emphasis (:area :inlines :categories (:inline))
  "Emphasis: \\i, \\j, and italic text outside vocabulary entries."
  (content :inlines :required t :doc "The emphasised text."))

(define-node strong (:area :inlines :categories (:inline))
  "Strong emphasis: \\b, and bold text outside vocabulary entries."
  (content :inlines :required t :doc "The text set in bold."))

;;; Example notation

(define-node evaluates-to (:area :inlines :categories (:inline))
  "The arrow `evaluates to' of an example: \\EV.")

(define-node may-evaluate-to (:area :inlines :categories (:inline))
  "The arrow `might evaluate to' (implementation-dependent) of an
example: \\OV.")

(define-node does-not-evaluate-to (:area :inlines :categories (:inline))
  "The arrow `does not evaluate to' of an example: \\NV.")

(define-node equivalent (:area :inlines :categories (:inline))
  "The sign `is equivalent to' of an example: \\EQ.")

(define-node output (:area :inlines :categories (:inline))
  "The triangle that marks the output of an example, which follows it:
\\OUT.")

(define-node input (:area :inlines :categories (:inline))
  "User input in an example: \\IN."
  (content :inlines :required t :doc "The input."))

;;; Citations, index entries, issues

(define-node citation (:area :inlines :categories (:inline))
  "The title of a work the standard cites: \\CLtL, \\CLtLTwo and the
other citation macros of setup-terms.tex."
  (content :inlines :required t :doc "The title as set."))

(define-enum index-kind (:area :inlines)
  "What an index entry indexes, by its macro."
  (:ref "\\idxref: a defined name.")
  (:keyref "\\idxkeyref: a lambda list keyword, without its ampersand.")
  (:code "\\idxcode: code.")
  (:keyword "\\idxkwd: a keyword.")
  (:text "\\idxtext: a phrase.")
  (:term "\\idxterm: a glossary term.")
  (:example "\\idxexample: an example.")
  (:package "\\idxpackref: a package."))

(define-node index-entry (:area :inlines :categories (:inline :block))
  "An entry of the index: an anchor where the text indexes a name or a
phrase, \\idxref and its relatives."
  (index-kind (:enum index-kind) :required t :doc "What is indexed.")
  (text :string :required t :doc "The indexed text, as written."))

(define-node issue-start (:area :inlines :categories (:inline :block))
  "Where the text an X3J13 issue brought begins: \\issue.  Issues are
ranges that may cross blocks and sections, so they are anchors."
  (name :string :required t
   :doc "The issue's name, e.g. \"DOTTED-LIST-ARGUMENTS:CLARIFY\"."))

(define-node issue-end (:area :inlines :categories (:inline :block))
  "Where the text an X3J13 issue brought ends: \\endissue, the one end
of the issue-start before it with its name."
  (name :string :required t :doc "The issue's name."))
