;;;; tests/model/nodes.lisp
;;;;
;;;; The node shapes (src/model/nodes-*.lisp; docs/plan/m3.md, step 3.2):
;;;; every vocabulary key and event kind the ownership table
;;;; (src/model/owners.sexp) gives a builder step is accounted for here,
;;;; either by the node kinds its handler builds, all declared, or by the
;;;; reason it builds none of its own.  The builder steps build against
;;;; this table; one that changes what a key builds changes it here.
;;;; Owner: step 3.2.

(in-package #:cl-ansi-spec/tests)

(defparameter *node-products*
  '(;; 3.8, structure
    (:chapter :chapter) (:simple-chapter :chapter) (:section :section)
    (:dictionary :section) (:subsection :section) (:subsubsection :section)
    (:subsubsubsection :section) (:subsubsubsubsection :section)
    (:define-chapter :none "Gives the id of the chapter it names.")
    (:define-section :none "Gives the id of the section it names.")
    (:write :none "Checks a section's or figure's number, else dropped.")
    ;; 3.9, entries
    (:com :dictionary-entry) (:endcom :none "Ends the entry :com began.")
    (:label :part) (:label-confidence :none "Marks the part as None.")
    (:defun :operator-signature) (:defun-no-return :operator-signature)
    (:defmac :operator-signature) (:defmac-no-return :operator-signature)
    (:defspec :operator-signature) (:defspec-no-return :operator-signature)
    (:defgen :operator-signature) (:defmeth :operator-signature)
    (:defun-multi :operator-signature)
    (:defun-multi-accessor :operator-signature :setf-signature)
    (:defsetf :setf-signature) (:defsetf-multi :setf-signature)
    (:defvar :variable-signature) (:defcon :variable-signature)
    (:deftype :type-signature)
    (:entry :none "A name of a -multi signature, or a row of \\tabletwo.")
    ;; 3.10, blocks
    (:code :code-block :code-line) (:endcode :none "Ends the code :code began.")
    (:list :item-list) (:endlist :none "Ends the list :list began.")
    (:item :item) (:item-2 :item-list :item) (:item-3 :item-list :item)
    (:editor-note :editor-note) (:reviewer-note :reviewer-note)
    (:paragraph :paragraph)
    (:indent :none "Presentational: indentation.")
    (:glue :none "Presentational: spacing.") (:kern :none "Presentational: spacing.")
    (:penalty :none "Presentational: line and page breaking.")
    (:rule :none "Presentational: a drawn line.")
    (:language :none "Presentational: hyphenation.")
    (:box :none "Presentational: its contents are built in its place.")
    (:leaders :none "Presentational: a filler.")
    (:tex-mark :none "Presentational: running heads.")
    (:insert :none "Presentational: its contents are built in its place.")
    (:vadjust :none "Presentational: its contents are built in its place.")
    (:special :none "Presentational: a driver command.")
    (:shipout :none "Presentational: a page.")
    (:openout :none "Output files the model does not write.")
    (:closeout :none "Output files the model does not write.")
    ;; 3.11, tables and figures
    (:figure :figure) (:caption :none "Gives the figure's number and caption.")
    (:next-figure :next-figure)
    (:define-figure :none "Gives the id of the figure it names.")
    (:alignment :table) (:row :row) (:cell :cell)
    (:no-align :none "Rules and spacing between rows.")
    ;; 3.12, text
    (:text :none "Strings, or code, emphasis and strong by the font.")
    (:space :none "A space in a string.")
    (:discretionary :none "Its no-break text, in a string.")
    (:pre-break :none "Dropped: text only where a line breaks.")
    (:post-break :none "Dropped: text only where a line breaks.")
    (:no-break :none "Its text, in a string.")
    (:accent :none "A precomposed character, in a string.")
    ;; 3.13, inlines
    (:term :term-ref) (:new-term :term-ref) (:param :param)
    (:emphasis :emphasis) (:strong :strong) (:inline-code :code)
    (:clref :operator-ref) (:funref :operator-ref) (:macref :operator-ref)
    (:typeref :operator-ref) (:varref :operator-ref) (:conref :operator-ref)
    (:declref :operator-ref) (:specref :operator-ref) (:packref :operator-ref)
    (:loopref :operator-ref) (:keyref :operator-ref) (:kwd :operator-ref)
    (:ttref :operator-ref) (:misc :operator-ref)
    (:secref :section-ref) (:figref :figure-ref) (:this-section :this-section)
    (:evaluates-to :evaluates-to) (:may-evaluate-to :may-evaluate-to)
    (:does-not-evaluate-to :does-not-evaluate-to) (:equivalent :equivalent)
    (:output :output) (:input :input) (:cite :citation)
    (:index-ref :index-entry) (:index-keyref :index-entry)
    (:index-code :index-entry) (:index-keyword :index-entry)
    (:index-text :index-entry) (:index-term :index-entry)
    (:index-example :index-entry) (:index-package :index-entry)
    (:issue :issue-start) (:endissue :issue-end)
    (:metavariable :metavariable) (:format-directive :format-directive)
    (:lambda-list-keyword :lambda-list-keyword)
    ;; 3.14, glossary
    (:glossary-letter :glossary-group) (:glossary-entry :glossary-entry)
    (:glossary-example :glossary-example)
    (:sense :none "The sense of the term-ref before it.")
    (:part-of-speech :none "A part of speech of a glossary entry or sense.")
    (:pronunciation :none "The pronunciation of a glossary entry.")
    (:usage :none "A usage of a glossary entry or sense.")
    ;; 3.15, syntax
    (:bnf-rule :bnf-rule) (:bnf-break :bnf-break) (:optional :bnf-optional)
    (:end-optional :none "Ends the :optional before it.")
    (:zero-or-more :bnf-zero-or-more) (:one-or-more :bnf-one-or-more)
    (:interleave :bnf-interleave)
    (:end-interleave :none "Ends the :interleave before it.")
    (:bracketed :bnf-bracketed) (:end-bracketed :none "Ends the :bracketed before it.")
    (:parenthesized :bnf-parenthesized)
    (:end-parenthesized :none "Ends the :parenthesized before it.")
    (:group :bnf-group) (:end-group :none "Ends the :group before it.")
    (:required :bnf-required) (:repeat-previous :bnf-repeat-previous)
    (:caret :bnf-caret) (:angle :angle-name) (:indirection :bnf-indirection)
    ;; 3.15m, math
    (:math :math) (:eqno :none "The equation number of its math.")
    (:noad :math-noad)
    (:nucleus :none "A field of its noad.") (:superscript :none "A field of its noad.")
    (:subscript :none "A field of its noad.") (:math-char :math-char)
    (:fraction :math-fraction)
    (:numerator :none "A field of its fraction.")
    (:denominator :none "A field of its fraction.")
    (:left :math-delimiter) (:right :math-delimiter)
    (:math-style :math-style-change) (:math-choice :math-choice)
    (:choice :none "A field of its math-choice."))
  "Each vocabulary key and event kind a builder step owns, and the node
kinds its handler builds, or :NONE and why it builds none of its own.")

(defun held-kinds ()
  "The node kinds some field of a declared kind may hold."
  (loop for kind in (model:node-kinds)
        append (loop for field in (model:node-fields kind)
                     for type = (model:field-type field)
                     when (and (consp type) (eq :node (first type)))
                       append (model:expand-kinds (rest type)))))

(define-test model-node-shapes
  :parent model
  ;; The builder core (3.3) owns only the report, which builds no node.
  (let ((owned (loop for owner in (model:owners)
                     unless (equal "3.3" (model:owner-step owner))
                       append (append (model:owner-vocabulary owner)
                                      (model:owner-events owner))))
        (held (held-kinds))
        (accounted (mapcar #'first *node-products*)))
    (is equal '() (duplicates accounted) "Keys accounted for twice")
    (is equal '() (set-difference owned accounted) "Owned keys not accounted for")
    (is equal '() (set-difference accounted owned) "Accounted keys no step owns")
    (loop for (key . products) in *node-products*
          do (if (eq :none (first products))
                 (true (stringp (second products)) "~S builds no node: why" key)
                 (dolist (kind products)
                   (true (model:find-node-declaration kind)
                         "~S builds ~S, which is declared" key kind))))
    (is equal '() (model:registry-problems) "The declarations name what exists")
    (dolist (kind (model:node-kinds))
      (true (or (eq kind :document)     ; the root, built from every job
                (find kind *node-products* :key #'rest :test #'member)
                (member kind held))
            "~S is built from a key, or held by another kind's field" kind))))
