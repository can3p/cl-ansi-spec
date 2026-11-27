;;;; src/model/nodes-tables.lisp
;;;;
;;;; The node kinds of tables and figures (docs/model.md, "Tables and
;;;; figures"), and the target kind that points to figures.
;;;; Owner: step 3.2 (shapes), then 3.11 of docs/plan/m3.md (documentation
;;;; and examples, through tests/model/undocumented-tables.sexp).

(in-package #:cl-ansi-spec/model)

(define-target-kind :figure (:area :tables :node :figure)
  "A figure, by its id: the target of \\figref and \\thenextfigure.")

(define-node table (:area :tables :categories (:block))
  "A table: an alignment (\\halign, as \\tabletwo, \\tablefigtwo …,
\\displaytwo … and \\showtwo … set it) read as rows of cells."
  (rows (:node :row) :repeated t :required t
   :doc "The table's rows, in order."))

(define-node row (:area :tables)
  "A row of a table."
  (header :boolean
   :doc "True for a row of column headings (the heading arguments of
\\tablefigtwo and its relatives).")
  (cells (:node :cell) :repeated t :required t
   :doc "The row's cells, in order."))

(define-node cell (:area :tables)
  "A cell of a row."
  (content :inlines
   :doc "The cell's text and inlines; absent for an empty cell.")
  (columns :integer
   :doc "The number of columns the cell spans when \\span joined more
than one; absent for one."))

(define-node figure (:area :tables :categories (:block))
  "A figure: a numbered display with a caption (\\endfig, \\tablefigtwo
and its relatives)."
  (id :string :required t
   :doc "The label of the \\DefineFigure that names the figure, or
<chapter-id>/fig-<n> for a figure that none names.")
  (number :string :required t
   :doc "The figure's number, its chapter's and its own joined by a
hyphen (\"14-1\"), from the caption, checked against the :write of its
\\DefineFigure when there is one.")
  (caption :inlines
   :doc "The caption's text after the number; absent when the figure has
none.")
  (content (:node :block) :repeated t :required t
   :doc "What the figure shows: a table, or other blocks."))
