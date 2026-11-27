;;;; tests/model/tables.lisp
;;;;
;;;; Tests of tables and figures (src/model/build-tables.lisp), on events
;;;; made here and on real lines of the spec.
;;;; Owner: step 3.11 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/tests)

(define-test tables
  :parent model
  :description "Tables and figures: alignments, rows, cells, captions, numbers.")

(defvar *table-handlers*
  (let ((table (model:install-table-handlers
                (model:install-text-handlers (model:make-handler-table)))))
    ;; What other steps build: a paragraph (a caption is set in one).
    (model:register-handler
     :begin :paragraph
     (lambda (builder event span)
       (declare (ignore event))
       (model:open-container builder :paragraph span
                             :node (model:make-builder-node builder :paragraph)
                             :field 'model::content))
     table)
    ;; What 3.8 does with the \write of \DefineFigure.
    (model:register-handler :write nil (lambda (builder event span)
                                         (declare (ignore builder event span)))
                            table)
    table)
  "The handlers of tables and text, a paragraph and a \\write.")

(defun table-nodes (&rest events)
  "The top-level nodes of EVENTS built with the table handlers, as
S-expressions without spans, and the build report."
  (multiple-value-bind (nodes report)
      (model:build-events events :registry model:*registry* :handlers *table-handlers*)
    (values (mapcar (lambda (node)
                      (if (stringp node) node (model:node-sexp node :spans nil)))
                    nodes)
            report)))

(defun table-problems (report)
  "The messages of REPORT's :NODE problems (the events no handler took
are the other steps')."
  (loop for problem in (model:build-report-problems report)
        when (eq (model:problem-kind problem) :node)
          collect (model:problem-message problem)))

(defun tbl-cell (column &rest events)
  "The events of a cell in COLUMN holding EVENTS."
  (append (list (test-event :begin :cell :column column)) events
          (list (test-event :end :cell))))

(defun tbl-row (&rest cells)
  "The events of a row of CELLS."
  (append (list (test-event :begin :row)) (apply #'append cells)
          (list (test-event :end :row))))

(defun rule-token ()
  "The token \vrule."
  (cl-ansi-spec/tex:make-cs-token
   (cl-ansi-spec/tex:make-frozen-control-sequence "vrule")))

(defun tbl-alignment (columns &rest rows)
  "The events of an \halign whose COLUMNS are :TEXT or :RULE (a template
with a \vrule), and ROWS."
  (append (list (test-event :begin :alignment :command "halign"
                            :preamble (mapcar (lambda (column)
                                                (list :u (if (eq column :rule)
                                                             (list (rule-token))
                                                             '())))
                                              columns)))
          (apply #'append rows)
          (list (test-event :end :alignment))))

(defun tbl-bold (text) (txt text "cmbx10"))
(defun tbl-italic (text) (txt text "cmti10"))

;;; Tables

(define-test tables-rows-and-cells
  :parent tables
  (multiple-value-bind (nodes report)
      (apply #'table-nodes
             (tbl-alignment '(:text :text)
                        (tbl-row (tbl-cell 1 (txt "one")) (tbl-cell 2 (txt "two")))
                        (tbl-row (tbl-cell 1 (txt "three")) (tbl-cell 2))))
    (is equal '((:table :rows ((:row :cells ((:cell :content ("one"))
                                             (:cell :content ("two"))))
                               (:row :cells ((:cell :content ("three")) (:cell))))))
        nodes
        "cells hold their text; an empty cell has no content")
    (is equal '() (table-problems report))))

(define-test tables-cell-spaces-and-spans
  :parent tables
  (is equal '((:table :rows ((:row :cells ((:cell :content ("a b") :columns 2))))))
      (apply #'table-nodes
             (tbl-alignment '(:text :text)
                        (tbl-row (append (list (test-event :begin :cell :column 1 :columns 2))
                                     (list (test-event :space nil) (txt "a") (test-event :space nil)
                                           (txt "b") (test-event :space nil))
                                     (list (test-event :end :cell))))))
      "a cell's leading and trailing spaces go, the ones inside stay; \span gives its columns"))

(define-test tables-header-and-spacing-rows
  :parent tables
  (multiple-value-bind (nodes report)
      (apply #'table-nodes
             (tbl-alignment '(:text :text)
                        (tbl-row (tbl-cell 1 (tbl-bold "Name")) (tbl-cell 2 (tbl-bold "Meaning")))
                        (list (test-event :begin :no-align)
                              (test-event :glue nil :glue "2.0pt" :command "vskip")
                              (test-event :end :no-align))
                        (tbl-row (tbl-cell 1) (tbl-cell 2))
                        (tbl-row (tbl-cell 1 (tbl-italic "adj.")) (tbl-cell 2 (txt "adjective")))
                        (tbl-row (tbl-cell 1 (tbl-bold "bold")) (tbl-cell 2 (tbl-bold "too")))))
    (is equal '((:table :rows ((:row :header t
                                :cells ((:cell :content ((:strong :content ("Name"))))
                                        (:cell :content ((:strong :content ("Meaning"))))))
                               (:row :cells ((:cell :content ((:emphasis :content ("adj."))))
                                             (:cell :content ("adjective"))))
                               (:row :cells ((:cell :content ((:strong :content ("bold"))))
                                             (:cell :content ((:strong :content ("too")))))))))
        nodes
        "only the first row can be a heading; a row of empty cells is spacing")
    (is equal '() (table-problems report)
        "a glue between rows is the presentational events' to drop")))

(define-test tables-rule-columns
  :parent tables
  (multiple-value-bind (nodes report)
      (apply #'table-nodes
             (tbl-alignment '(:rule :text :rule :text :rule)
                        (tbl-row (tbl-cell 1) (tbl-cell 2 (txt "a")) (tbl-cell 3) (tbl-cell 4 (txt "b")) (tbl-cell 5))))
    (is equal '((:table :rows ((:row :cells ((:cell :content ("a")) (:cell :content ("b")))))))
        nodes
        "the columns that draw a rule are no cells")
    (is equal '() (table-problems report)))
  ;; A repeating preamble (`&\vrule##&text##'): the columns past it repeat.
  (is equal '((:table :rows ((:row :cells ((:cell :content ("a")) (:cell :content ("b")))))))
      (apply #'table-nodes
             (append (list (test-event :begin :alignment :command "halign" :loop 1
                                       :preamble (list (list :u (list (rule-token)))
                                                       (list :u '()))))
                     (tbl-row (tbl-cell 1) (tbl-cell 2 (txt "a")) (tbl-cell 3) (tbl-cell 4 (txt "b")) (tbl-cell 5))
                     (list (test-event :end :alignment)))))
  ;; A repeat that starts past the preamble is no repeat.
  (multiple-value-bind (nodes report)
      (apply #'table-nodes
             (append (list (test-event :begin :alignment :command "halign" :loop 5
                                       :preamble (list (list :u '()))))
                     (tbl-row (tbl-cell 1 (txt "a")) (tbl-cell 2 (txt "b")))
                     (list (test-event :end :alignment))))
    (is equal '((:table :rows ((:row :cells ((:cell :content ("a")) (:cell :content ("b")))))))
        nodes)
    (is equal '() (table-problems report)))
  (is equal '((:table :rows ((:row :cells ((:cell :content ("kept")))))))
      (apply #'table-nodes
             (tbl-alignment '(:rule) (tbl-row (tbl-cell 1 (txt "kept")))))
      "text in a rule column is kept"))

(define-test tables-valign-reported
  :parent tables
  (multiple-value-bind (nodes report)
      (apply #'table-nodes
             (list (test-event :begin :alignment :command "valign")
                   (test-event :end :alignment)))
    (declare (ignore nodes))
    (true (some (lambda (message) (search "valign" message)) (table-problems report)))))

(define-test tables-reported
  :parent tables
  (multiple-value-bind (nodes report)
      (apply #'table-nodes
             (tbl-alignment '(:text)
                        (list (test-event :begin :no-align)
                              (txt "oops")
                              (test-event :end :no-align))
                        (list (txt "stray"))
                        (tbl-row (tbl-cell 1 (txt "a")))))
    (declare (ignore nodes))
    (is = 2 (length (model:build-report-problems report)))
    (true (search "\\noalign" (first (table-problems report))))
    (true (search "An alignment" (second (table-problems report))) "stray text is reported")))

;;; Figures

(defun caption-events (&rest events)
  "The events of a caption, `Figure 4--7. ...', set in a paragraph."
  (append (list (test-event :begin :caption)
                (test-event :begin :paragraph)
                (txt "Figure" "cmbx9") (test-event :space nil) (txt "4" "cmbx9") (txt "--7." "cmbx9")
                (test-event :space nil))
          events
          (list (test-event :end :paragraph) (test-event :end :caption))))

(defun figure-events (caption &rest content)
  "The events of a figure of CONTENT then CAPTION."
  (append (list (test-event :begin :figure)) (apply #'append content) caption
          (list (test-event :end :figure))))

(define-test tables-figure
  :parent tables
  (multiple-value-bind (nodes report)
      (apply #'table-nodes
             (figure-events (caption-events (txt "Object" "cmbx9") (test-event :space nil)
                                            (txt "Classes" "cmbx9"))
                            (tbl-alignment '(:text) (tbl-row (tbl-cell 1 (txt "class"))))))
    (is equal '((:figure :id "4/fig-7" :number "4-7" :caption ("Object Classes")
                 :content ((:table :rows ((:row :cells ((:cell :content ("class")))))))))
        nodes
        "the number is read from the caption (the dash is an en dash there), its text follows it; without a label the id is made of the chapter and the figure")
    (is equal '() (table-problems report)))
  ;; The label of \DefineFigure, and the number TeX wrote.
  (multiple-value-bind (nodes report)
      (apply #'table-nodes
             (append (list (test-event :mark :define-figure :arguments '("Classes"))
                           (test-event :write nil :stream 4 :tokens "!Classes 4--7"))
                     (figure-events (caption-events (txt "Classes" "cmbx9"))
                                    (tbl-alignment '(:text) (tbl-row (tbl-cell 1 (txt "x")))))))
    (is equal "Classes" (getf (rest (first nodes)) :id))
    (is equal '() (table-problems report)))
  ;; A number that is not the caption's is reported.
  (multiple-value-bind (nodes report)
      (apply #'table-nodes
             (append (list (test-event :mark :define-figure :arguments '("Classes"))
                           (test-event :write nil :stream 4 :tokens "!Classes 4--9"))
                     (figure-events (caption-events (txt "Classes" "cmbx9"))
                                    (tbl-alignment '(:text) (tbl-row (tbl-cell 1 (txt "x")))))))
    (is equal "4-7" (getf (rest (first nodes)) :number) "the caption's number stands")
    (is = 1 (length (table-problems report)))
    (true (search "4-9" (first (table-problems report))))))

(define-test tables-figure-without-caption
  :parent tables
  (multiple-value-bind (nodes report)
      (apply #'table-nodes
             (append (list (test-event :mark :define-figure :arguments '("Bare"))
                           (test-event :write nil :stream 4 :tokens "!Bare 4--3"))
                     (figure-events '() (tbl-alignment '(:text) (tbl-row (tbl-cell 1 (txt "x")))))))
    (is equal "4-3" (getf (rest (first nodes)) :number)
        "without a caption the number TeX wrote is used")
    (is equal "Bare" (getf (rest (first nodes)) :id))
    (is equal '() (table-problems report)))
  (multiple-value-bind (nodes report)
      (apply #'table-nodes (figure-events (list (test-event :begin :caption)
                                                (txt "no number" "cmbx9")
                                                (test-event :end :caption))))
    (declare (ignore nodes))
    (true (some (lambda (message) (search "without its number" message))
                (table-problems report)))))

(define-test tables-next-figure
  :parent tables
  (is equal '((:next-figure))
      (table-nodes (test-event :begin :next-figure)
                   (txt "Figure") (test-event :space nil) (txt "4") (txt "--7")
                   (test-event :end :next-figure))
      "the words of \thenextfigure are the figure's number, which its reference resolves"))

;;; Real lines

(defun spec-nodes (job file first last)
  "The nodes of FILE's lines FIRST to LAST of JOB, as S-expressions."
  (mapcar (lambda (node) (if (stringp node) node (model:node-sexp node :spans nil)))
          (model:build-fixture job :file file :lines (list first last))))

(define-test tables-spec-lines
  :parent tables
  ;; concept-classes.tex:9-16: \DefineFigure and \displaythree.
  (let ((figure (find :figure (spec-nodes "chap-4" "concept-classes.tex" 9 16)
                      :key (lambda (node) (and (consp node) (first node))))))
    (is equal "ObjectSystemClasses" (getf (rest figure) :id))
    (is equal "4-7" (getf (rest figure) :number))
    (is equal '("Object System Classes") (getf (rest figure) :caption))
    (is = 4 (length (getf (rest (first (getf (rest figure) :content))) :rows))))
  ;; concept-bvl.tex:13-47: \tablefigtwo, no \DefineFigure.
  (let* ((figure (find :figure (spec-nodes "chap-3" "concept-bvl.tex" 13 47)
                       :key (lambda (node) (and (consp node) (first node)))))
         (rows (getf (rest (first (getf (rest figure) :content))) :rows)))
    (is equal "3-10" (getf (rest figure) :number))
    (is equal '("What Kind of Lambda Lists to Use") (getf (rest figure) :caption))
    (true (getf (rest (first rows)) :header) "the heading arguments are a header row")
    (false (getf (rest (second rows)) :header))
    (is = 2 (length (getf (rest (second rows)) :cells))))
  ;; concept-glossary.tex:138-151: \tabletwo, rules and spacing around its rows.
  (let* ((table (find :table (spec-nodes "chap-26" "concept-glossary.tex" 138 151)
                      :key (lambda (node) (and (consp node) (first node)))))
         (rows (getf (rest table) :rows)))
    (is = 13 (length rows) "a heading row and the twelve abbreviations")
    (true (getf (rest (first rows)) :header))
    (is = 2 (length (getf (rest (second rows)) :cells))
        "the columns that draw a rule are no cells")))
