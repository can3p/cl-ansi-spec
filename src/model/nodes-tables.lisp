;;;; src/model/nodes-tables.lisp
;;;;
;;;; The node kinds of tables and figures (docs/model.md, "Tables and
;;;; figures"), and the target kind that points to figures.
;;;; Its documentation ratchet: tests/model/undocumented-tables.sexp.

(in-package #:cl-ansi-spec/model)

(define-target-kind :figure (:area :tables :node :figure)
  "A figure, by its id: the target of \\figref and \\thenextfigure.")

(define-node table (:area :tables :categories (:block)
                    :example (:table
                              :rows ((:row :header t
                                      :cells ((:cell :content ((:strong :content ("Abbreviation"))))
                                              (:cell :content ((:strong :content ("Meaning"))))))
                                     (:row :cells ((:cell :content ((:emphasis :content ("adj."))))
                                                   (:cell :content ("adjective")))))))
  "A table: an alignment (\\halign, as \\tabletwo, \\tablefigtwo …,
\\displaytwo … and \\showtwo … set it) read as rows of cells."
  (rows (:node :row) :repeated t :required t
   :doc "The table's rows, in order: the rows TeX set, but not the
spacing rows between its rules, whose cells are all empty."
   :example ((:row :cells ((:cell :content ("adverb")))))))

(define-node row (:area :tables
                  :example (:row :header t
                            :cells ((:cell :content ((:strong :content ("Context"))))
                                    (:cell :content ((:strong :content ("Kind of Lambda List")))))))
  "A row of a table."
  (header :boolean
   :doc "True for the first row of a table when every cell that has
content holds nothing but bold text: the row of column headings
(\\tablefigtwo, \\tabletwo)."
   :example t)
  (cells (:node :cell) :repeated t :required t
   :doc "The row's cells, in order; the columns that only draw a rule
(\\vrule in their template) have none."
   :example ((:cell :content ("adjective")))))

(define-node cell (:area :tables
                   :example (:cell :content ((:strong :content ("defun")) " "
                                             (:emphasis :content ("form")))))
  "A cell of a row."
  (content :inlines
   :doc "The cell's text and inlines, without the spaces around them;
absent for an empty cell."
   :example ("compatible with one or more ANSI standards"))
  (columns :integer
   :doc "The number of columns the cell spans when \\span joined more
than one; absent for one."
   :example 2))

(define-node figure (:area :tables :categories (:block)
                     :example (:figure :id "ObjectSystemClasses" :number "4-7"
                               :caption ("Object System Classes")
                               :content ((:table
                                          :rows ((:row :cells ((:cell :content ("class"))
                                                               (:cell :content ("standard-class")))))))))
  "A figure: a numbered display with a caption (\\endfig, \\tablefigtwo
and its relatives)."
  (id :string :required t
   :doc "The label of the \\DefineFigure that names the figure, or
<chapter-id>/fig-<n> for a figure that none names (n the second part of
its number)."
   :example "ObjectSystemClasses")
  (number :string :required t
   :doc "The figure's number, its chapter's and its own joined by a
hyphen (\"14-1\"), from the caption, checked against the :write of its
\\DefineFigure when there is one."
   :example "4-7")
  (caption :inlines
   :doc "The caption's text after the number; absent when the figure has
none."
   :example ("Object System Classes"))
  (content (:node :block) :repeated t :required t
   :doc "What the figure shows: a table, or other blocks."
   :example ((:table :rows ((:row :cells ((:cell :content ("class")))))))))
