;;;; src/model/build-tables.lisp
;;;;
;;;; The handlers that build tables and figures from their events
;;;; (docs/model.md, "Tables and figures").
;;;; Owner: step 3.11 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/model)

(defun weak-table ()
  "A table keyed by object identity that does not keep its keys alive."
  (make-hash-table :test 'eq
                   #+sbcl :weakness #+sbcl :key #+sbcl :synchronized #+sbcl t))

;;; Helpers on the items of a container

(defun blank-string-p (item)
  "True when ITEM is a string of nothing but spaces."
  (and (stringp item) (every (lambda (char) (char= char #\Space)) item)))

(defun trim-inlines (items)
  "ITEMS, a list of strings and nodes, without the spaces before the first
and after the last of them, and without empty strings."
  (let ((items (remove "" items :test #'equal)))
    (loop while (and items (stringp (first items)))
          do (let ((text (string-left-trim " " (first items))))
               (if (string= text "")
                   (pop items)
                   (progn (setf (first items) text) (return)))))
    (setf items (reverse items))
    (loop while (and items (stringp (first items)))
          do (let ((text (string-right-trim " " (first items))))
               (if (string= text "")
                   (pop items)
                   (progn (setf (first items) text) (return)))))
    (nreverse items)))

(defun report-stray-items (builder container what &optional keep)
  "Report each of CONTAINER's items that is not blank space, nor a node
of the kind KEEP, as a problem of kind :NODE: WHAT (a string) says where
it stood."
  (dolist (item (container-contents container))
    (unless (or (blank-string-p item)
                (and keep (not (stringp item)) (eq (node-kind item) keep)))
      (report-problem builder :node (container-span container)
                      :message (format nil "~A holds ~S, which the model drops."
                                       what
                                       (if (stringp item) item (node-kind item)))))))

;;; Alignments, rows and cells

(defvar *alignment-columns* (weak-table)
  "For each open alignment container, its rule columns: a list of the
preamble's columns that draw a rule (its template has a \\vrule) as
indices from 0, the preamble's length, and the column its repeat starts
at (from 1) or NIL.")

(defun preamble-index (length loop column)
  "The index from 0 into a preamble of LENGTH columns, whose columns from
the LOOP-th on (from 1; NIL for none) repeat, of the column COLUMN (from
1) of a row; NIL when the row has more columns than a preamble that does
not repeat."
  (cond ((<= column length) (1- column))
        (loop (let ((start (1- loop)))
                (+ start (mod (- (1- column) start) (- length start)))))))

(defun rule-template-p (builder template)
  "True when TEMPLATE, a token list, names \\vrule."
  (declare (ignore builder))
  (some (lambda (token)
          (and (cl-ansi-spec/tex:cs-token-p token)
               (string= (cl-ansi-spec/tex:control-sequence-name
                         (cl-ansi-spec/tex:cs-token-control-sequence token))
                        "vrule")))
        template))

(defun alignment-rule-columns (builder event)
  "The rule columns of the alignment EVENT (see *ALIGNMENT-COLUMNS*)."
  (let* ((preamble (event-property event :preamble))
         (loop (event-property event :loop)))
    (list (loop for column in preamble
                for index from 0
                when (rule-template-p builder (getf column :u))
                  collect index)
          (length preamble)
          loop)))

(defun rule-column-p (container column)
  "True when the COLUMN (from 1) of a row of the alignment CONTAINER draws
a rule, so that its cells hold no text."
  (destructuring-bind (rules length loop)
      (or (gethash container *alignment-columns*) (list '() 0 nil))
    (let ((index (and column (plusp length) (preamble-index length loop column))))
      (and index (member index rules) t))))

(defun alignment-container (builder)
  "The innermost open alignment container of BUILDER, or NIL."
  (find :alignment (builder-stack builder) :key #'container-key))

(defun finish-table (builder container)
  "Keep as the rows of CONTAINER's table its rows, less those whose cells
are all empty (the spacing rows a table sets between its rules); mark
the first one a heading row when its cells are all bold.  Anything else
the alignment holds is reported."
  (let* ((node (container-node container))
         (rows (remove-if (lambda (row)
                            (every (lambda (cell) (null (node-field-value cell :content)))
                                   (node-field-value row :cells)))
                          (remove-if-not (lambda (item)
                                           (and (not (stringp item)) (eq (node-kind item) :row)))
                                         (container-contents container)))))
    (report-stray-items builder container "An alignment" :row)
    (when (and rows (header-row-p (first rows)))
      (setf (node-field-value (first rows) :header) t))
    (setf (container-items container) (reverse rows)
          (node-field-value node :rows) rows)))

(defun begin-alignment-handler (builder event span)
  "An alignment opens a table; its rows come as its events do."
  (let ((container (open-container builder :alignment span
                                   :node (make-builder-node builder :table)
                                   :field 'rows
                                   :on-close #'finish-table)))
    (unless (let ((command (event-property event :command)))
              (or (null command) (string-equal (string command) "halign")))
      (report-problem builder :node span
                      :message (format nil "A ~A alignment is read as a table of rows."
                                       (event-property event :command))))
    (setf (gethash container *alignment-columns*)
          (alignment-rule-columns builder event))))

(defun begin-no-align-handler (builder event span)
  "The material between two rows is rules and spacing; it is dropped."
  (declare (ignore event))
  (open-container builder :no-align span
                  :on-close (lambda (builder container)
                              (report-stray-items builder container "A \\noalign")
                              (setf (container-items container) '()))))

(defun header-row-p (row)
  "True when every cell of ROW that has content holds nothing but bold
text, and one has: the heading row of a table (its first row)."
  (let ((contents (remove nil (mapcar (lambda (cell) (node-field-value cell :content))
                                      (node-field-value row :cells)))))
    (and contents
         (every (lambda (content)
                  (and (null (rest content))
                       (not (stringp (first content)))
                       (eq (node-kind (first content)) :strong)))
                contents))))

(defun finish-row (builder container)
  "Keep as the items of the row CONTAINER its cells."
  (let ((node (container-node container)))
    (report-stray-items builder container "A row" :cell)
    (let ((cells (remove-if-not (lambda (item) (and (not (stringp item))
                                                    (eq (node-kind item) :cell)))
                                (container-contents container))))
      (setf (container-items container) (reverse cells)
            (node-field-value node :cells) cells))))

(defun begin-row-handler (builder event span)
  "A row of the table whose alignment is open."
  (declare (ignore event))
  (open-container builder :row span
                  :node (make-builder-node builder :row)
                  :field 'cells
                  :on-close #'finish-row))

(defun finish-cell (builder container)
  "Trim the content of the cell CONTAINER; a cell in a rule column is
dropped when it holds nothing but spaces."
  (declare (ignore builder))
  (let ((node (container-node container)))
    (let ((content (trim-inlines (container-contents container))))
      (setf (container-items container) (reverse content)
            (node-field-value node :content) content))))

(defun finish-rule-cell (builder container)
  "A cell in a rule column holds no text; if it does, it is a cell."
  (let ((content (trim-inlines (container-contents container))))
    (setf (container-items container)
          (and content
               (list (make-builder-node builder :cell :content content
                                                      :span (container-span container)))))))

(defun begin-cell-handler (builder event span)
  "A cell of the row that is open."
  (let* ((alignment (alignment-container builder))
         (column (event-property event :column))
         (columns (event-property event :columns)))
    (if (and alignment (rule-column-p alignment column))
        (open-container builder :cell span :on-close #'finish-rule-cell)
        (open-container builder :cell span
                        :node (apply #'make-builder-node builder :cell
                                     (and columns (> columns 1) (list :columns columns)))
                        :field 'content
                        :on-close #'finish-cell))))

;;; Figures

(defvar *pending-figures* (weak-table)
  "For each builder, the label and the number TeX wrote of the
\\DefineFigure that precedes the figure about to begin: (LABEL NUMBER).")

(defvar *figure-states* (weak-table)
  "For each open figure container, a list of the label and the number of
its \\DefineFigure (or NIL for each) and, once its caption closed, the
number and the text the caption gives.")

(defun written-number (builder label)
  "The number TeX wrote for the figure LABEL in the :WRITE event that
follows \\DefineFigure, which is left for its owner, or NIL.  TeX writes
`!label N--M'."
  (let ((event (peek-event builder)))
    (when (and event (eq (event-type event) :write))
      (let* ((text (argument-text builder (event-property event :tokens)))
             (prefix (format nil "!~A " label)))
        (when (and (> (length text) (length prefix))
                   (string= prefix text :end2 (length prefix)))
          (normalise-number (subseq text (length prefix))))))))

(defun normalise-number (text)
  "The number `N--M' (or with an en dash) of a figure as `N-M'."
  (with-output-to-string (out)
    (let ((i 0))
      (loop while (< i (length text))
            do (let ((char (char text i)))
                 (cond ((and (char= char #\-) (< (1+ i) (length text))
                             (char= (char text (1+ i)) #\-))
                        (write-char #\- out)
                        (incf i 2))
                       ((char= char (code-char #x2013)) (write-char #\- out) (incf i))
                       (t (write-char char out) (incf i))))))))

(defun mark-define-figure-handler (builder event span)
  "\\DefineFigure names the figure that follows, and TeX writes its number."
  (declare (ignore span))
  (let ((label (first (event-argument-texts builder event))))
    (setf (gethash builder *pending-figures*)
          (list label (and label (written-number builder label))))))

(defun parse-caption (items)
  "The number and the text of a figure's caption ITEMS (strings and
nodes): `Figure N-M. text'.  Return the number as `N-M' and the text
after it, a list of strings and nodes, or NIL for both when the caption
does not start so."
  (let ((first (first items)))
    (when (stringp first)
      (let* ((prefix "Figure ")
             (start (length prefix)))
        (when (and (> (length first) start) (string= prefix first :end2 start))
          (let ((dot (position #\. first :start start)))
            (when dot
              (let ((number (normalise-number (subseq first start dot))))
                (when (and (find #\- number)
                           (every (lambda (char) (or (digit-char-p char) (char= char #\-)))
                                  number))
                  (values number
                          (trim-inlines (cons (subseq first (1+ dot)) (rest items)))))))))))))

(defun caption-items (items)
  "ITEMS of a caption with its paragraphs flattened to their content and
its bold runs to their text: a caption is set in the bold font, so
bold is no emphasis there."
  (loop for item in items
        append (cond ((stringp item) (list item))
                     ((eq (node-kind item) :paragraph)
                      (caption-items (node-field-value item :content)))
                     ((eq (node-kind item) :strong)
                      (caption-items (node-field-value item :content)))
                     (t (list item)))))

(defun finish-caption (builder container)
  "Hand the number and the text of the caption CONTAINER to the figure
it is in, and take them out of the figure's items."
  (let* ((figure (current-container builder))
         (state (and (eq (container-key figure) :figure)
                     (gethash figure *figure-states*)))
         (items (trim-inlines (caption-items (container-contents container)))))
    (cond ((null state)
           (report-problem builder :node (container-span container)
                           :message "A caption outside a figure."))
          ((null items))
          (t (multiple-value-bind (number text) (parse-caption items)
               (unless number
                 (report-problem builder :node (container-span container)
                                 :message (format nil "A caption without its number: ~S."
                                                  (first items))))
               (setf (third state) (or number "")
                     (fourth state) (if number text items)))))
    (setf (container-items container) '())))

(defun chapter-number-of (number)
  "The chapter part of the figure NUMBER `N-M'."
  (subseq number 0 (position #\- number)))

(defun make-figure-id (builder label number)
  "The id of a figure: its LABEL, else `<chapter-id>/fig-<m>' of its NUMBER
`N-M', the chapter's id being that of the chapter built around it when
it has one, else N."
  (or label
      (let* ((chapter (or (find-container builder :chapter)
                          (find-container builder :simple-chapter)))
             (node (and chapter (container-node chapter)))
             (id (and node (find-field (node-kind node) :id) (node-field-value node :id)))
             (position (position #\- number)))
        (format nil "~A/fig-~A" (or id (chapter-number-of number))
                (if position (subseq number (1+ position)) number)))))

(defun finish-figure (builder container)
  "Fill the figure CONTAINER's number, caption and id from its caption
and its \\DefineFigure, check one against the other, and keep as its
content the blocks."
  (destructuring-bind (label written &optional number text)
      (gethash container *figure-states*)
    (let* ((node (container-node container))
           (content (remove-if #'blank-string-p (container-contents container))))
      (dolist (item content)
        (when (stringp item)
          (report-problem builder :node (container-span container)
                          :message (format nil "A figure holds the text ~S, which the model drops."
                                           item))))
      (setf content (remove-if #'stringp content))
      (when (and number (string= number ""))
        (setf number nil))
      (when (and number written (string/= number written))
        (report-problem builder :node (container-span container)
                        :message (format nil "Figure ~A by its caption, ~A by \\DefineFigure ~A."
                                         number written label)))
      (setf number (or number written))
      (setf (container-items container) (reverse content)
            (node-field-value node :content) content
            (node-field-value node :number) number
            (node-field-value node :caption) text)
      (when number
        (setf (node-field-value node :id) (make-figure-id builder label number)))
      (when (and (null number) label)
        (setf (node-field-value node :id) label)))))

(defun begin-figure-handler (builder event span)
  "A figure, with the label the \\DefineFigure before it gave."
  (declare (ignore event))
  (destructuring-bind (&optional label written)
      (shiftf (gethash builder *pending-figures*) nil)
    (let ((container (open-container builder :figure span
                                     :node (make-builder-node builder :figure)
                                     :field 'content
                                     :on-close #'finish-figure)))
      (setf (gethash container *figure-states*) (list label written nil nil)))))

(defun begin-caption-handler (builder event span)
  "The caption of the figure that is open, `Figure N--M. text'."
  (declare (ignore event))
  (open-container builder :caption span :on-close #'finish-caption))

(defun begin-next-figure-handler (builder event span)
  "\\thenextfigure: the words are the figure's number, which a reference
resolves (3.17); they are dropped."
  (declare (ignore event))
  (open-container builder :next-figure span
                  :node (make-builder-node builder :next-figure)
                  :on-close (lambda (builder container)
                              (declare (ignore builder))
                              (setf (container-items container) '()))))

;;; Registration

(defun install-table-handlers (table)
  "Register the handlers of step 3.11 in the handler table TABLE."
  (register-handler :begin :alignment #'begin-alignment-handler table)
  (register-handler :begin :no-align #'begin-no-align-handler table)
  (register-handler :begin :row #'begin-row-handler table)
  (register-handler :begin :cell #'begin-cell-handler table)
  (register-handler :mark :define-figure #'mark-define-figure-handler table)
  (register-handler :begin :figure #'begin-figure-handler table)
  (register-handler :begin :caption #'begin-caption-handler table)
  (register-handler :begin :next-figure #'begin-next-figure-handler table)
  table)

(install-table-handlers *handlers*)
