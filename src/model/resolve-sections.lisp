;;;; src/model/resolve-sections.lisp
;;;;
;;;; Section, chapter and figure references resolved through the labels of the events; TOC and figure lists.
;;;;
;;;; A \secref, \chapref or \figref holds its label as written
;;;; ("\\OrdinaryLambdaLists").  The model's ids are the labels the sources
;;;; define (\DefineChapter, \DefineSection, \DefineFigure, checked by the
;;;; structure and table builders), so resolving is a lookup by id among
;;;; the chapters, sections and figures of the model; the generated
;;;; setup-sections.tex and setup-figures.tex are never read.

(in-package #:cl-ansi-spec/model)

(defun secref-label-id (label)
  "The id a reference LABEL names: the label without its control-sequence
backslash and surrounding white space, or NIL when nothing is left."
  (let ((id (string-trim '(#\Space #\Tab #\Newline) label)))
    (when (and (plusp (length id)) (char= (char id 0) #\\))
      (setf id (string-trim '(#\Space #\Tab #\Newline) (subseq id 1))))
    (and (plusp (length id)) id)))

(defun secref-labels (node registry)
  "Every label that names NODE: its id and, for a chapter or section, its
aliases."
  (let ((id (node-field-value node :id registry)))
    (remove-duplicates
     (remove nil (cons id (and (member (node-kind node) '(:chapter :section))
                               (node-field-value node :aliases registry))))
     :test #'equal)))

(defun secref-index (items kind registry)
  "A hash table from label to the list of nodes of kind KIND in ITEMS that
it names, in document order."
  (let ((table (make-hash-table :test 'equal)))
    (walk-nodes (lambda (node)
                  (when (eq (node-kind node) kind)
                    (dolist (label (secref-labels node registry))
                      (push node (gethash label table)))))
                items registry)
    (maphash (lambda (id nodes) (setf (gethash id table) (nreverse nodes))) table)
    table))

(defun secref-span-text (node)
  "Where NODE was built, as file:line, for a message."
  (let ((span (node-span node)))
    (if span (format nil "~A:~D" (span-file span) (span-line span)) "-")))

(defun secref-resolve-one (node candidates registry)
  "Set the :TARGET of the reference NODE from CANDIDATES, an alist
(target-kind . nodes of that kind with the label's id), one cell for each
kind the reference may name; return a problem or NIL.  A label no node
has is unresolved; one that two nodes share is ambiguous, and left
unresolved too."
  (let* ((label (node-field-value node :label registry))
         (id (secref-label-id label))
         (found (loop for (kind . nodes) in candidates
                      append (mapcar (lambda (n) (cons kind n)) nodes))))
    (flet ((problem (control &rest arguments)
             (make-problem :unresolved-reference (node-span node)
                           :message (apply #'format nil control arguments))))
      (cond ((null id) (problem "The ~(~A~) ~S names nothing." (node-kind node) label))
            ((null found) (problem "No ~{~(~A~)~^ or ~} has the label ~S."
                                   (mapcar #'car candidates) id))
            ((rest found) (problem "The label ~S is ambiguous: ~{~(~A~) at ~A~^, ~}."
                                   id (loop for (kind . n) in found
                                            collect kind collect (secref-span-text n))))
            (t (setf (node-field-value node :target registry)
                     (make-target (caar found) (node-field-value (cdar found) :id registry)))
               nil)))))

(defun resolve-section-references (items &key (registry *registry*))
  "Resolve the :SECTION-REF and :FIGURE-REF nodes of ITEMS, a built
model: a label \\X names the chapter or section whose id is X (a
:SECTION-REF), or the figure whose id is X (a :FIGURE-REF).  Set each
:TARGET found; return the problems, one :UNRESOLVED-REFERENCE for each
reference with no target or with several, in document order."
  (let ((indexes (list (cons :chapter (secref-index items :chapter registry))
                       (cons :section (secref-index items :section registry))
                       (cons :figure (secref-index items :figure registry))))
        (problems '()))
    (flet ((candidates (kinds id)
             (loop for kind in kinds
                   collect (cons kind (and id (gethash id (cdr (assoc kind indexes))))))))
      (walk-nodes
       (lambda (node)
         (let* ((kinds (case (node-kind node)
                         (:section-ref '(:chapter :section))
                         (:figure-ref '(:figure))))
                (problem (and kinds
                              (secref-resolve-one
                               node
                               (candidates kinds (secref-label-id (node-field-value node :label registry)))
                               registry))))
           (when problem (push problem problems))))
       items registry))
    (nreverse problems)))

;;; Tables of contents and lists of figures

(defstruct (secref-toc-entry (:constructor make-toc-entry (kind id number title children)))
  "A line of the table of contents: a :CHAPTER or :SECTION with its ID,
NUMBER (NIL for an unnumbered chapter), TITLE (inlines) and its CHILDREN,
the entries of its sections."
  kind id number title children)

(defstruct (secref-figure-entry (:constructor make-figure-entry (id number caption chapter)))
  "A line of the list of figures: the figure's ID, NUMBER and CAPTION
(inlines or NIL), and the id of the CHAPTER it is in (NIL outside one)."
  id number caption chapter)

(defun secref-toc-section (section registry)
  "The SECREF-TOC-ENTRY of SECTION and, below it, of its subsections."
  (make-toc-entry :section (node-field-value section :id registry)
                  (node-field-value section :number registry)
                  (node-field-value section :title registry)
                  (secref-toc-children (node-field-value section :children registry) registry)))

(defun secref-toc-children (children registry)
  "The entries of the sections among CHILDREN, in order."
  (loop for child in children
        when (and (typep child 'node) (eq (node-kind child) :section))
          collect (secref-toc-section child registry)))

(defun table-of-contents (items &key (registry *registry*))
  "The table of contents of ITEMS, a built model: a list of
SECREF-TOC-ENTRYs, one for each chapter (front matter and numbered, in
document order), each holding its sections as CHILDREN, to any depth."
  (let ((entries '()))
    (walk-nodes (lambda (node)
                  (when (eq (node-kind node) :chapter)
                    (push (make-toc-entry :chapter (node-field-value node :id registry)
                                          (node-field-value node :number registry)
                                          (node-field-value node :title registry)
                                          (secref-toc-children
                                           (node-field-value node :children registry) registry))
                          entries)))
                items registry)
    (nreverse entries)))

(defun list-of-figures (items &key (registry *registry*))
  "The list of figures of ITEMS, a built model: a list of
SECREF-FIGURE-ENTRYs in document order."
  (let ((entries '()) (chapter nil))
    (walk-nodes (lambda (node)
                  (case (node-kind node)
                    (:chapter (setf chapter (node-field-value node :id registry)))
                    (:figure (push (make-figure-entry (node-field-value node :id registry)
                                                      (node-field-value node :number registry)
                                                      (node-field-value node :caption registry)
                                                      chapter)
                                   entries))))
                items registry)
    (nreverse entries)))
