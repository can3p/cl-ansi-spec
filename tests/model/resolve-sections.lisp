;;;; tests/model/resolve-sections.lisp
;;;;
;;;; Tests of section and figure references.
;;;; Owner: step 3.17 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/tests)

(define-test resolve-sections
  :parent model
  :description "Section, chapter and figure references, the table of
contents and the list of figures.")

(defun secref-fixture ()
  "A small model: chapter ChapOne holding sections A (with subsection B)
and a figure F, and a chapter ChapTwo; references to each, to a missing
label and to a label two nodes share."
  (flet ((ref (kind label) (model:make-node kind :label label))
         (section (id number level &rest children)
           (model:make-node :section :id id :number number :level level
                                     :title (list id) :children children)))
    (list (model:make-node
           :chapter :id "ChapOne" :number "1" :title '("One")
           :children
           (list (section "A" "1.1" 1
                          (model:make-node :paragraph
                                           :content (list (ref :section-ref "\\B")
                                                          (ref :figure-ref "\\F")
                                                          (ref :section-ref "\\ChapTwo")
                                                          (ref :section-ref "\\Missing")
                                                          (ref :figure-ref "\\A")
                                                          (ref :section-ref "\\Dup")))
                          (section "B" "1.1.1" 2))
                 (model:make-node :figure :id "F" :number "1-1" :caption '("Fig")
                                          :content (list (model:make-node :paragraph :content '("x"))))
                 (section "Dup" "1.2" 1)))
          (model:make-node :chapter :id "ChapTwo" :number "2" :title '("Two")
                           :children (list (section "Dup" "2.1" 1))))))

(defun secref-refs (model)
  "The reference nodes of MODEL, in order."
  (let ((found '()))
    (model:walk-nodes (lambda (node)
                        (when (member (model:node-kind node) '(:section-ref :figure-ref))
                          (push node found)))
                      model)
    (nreverse found)))

(defun secref-target (node)
  (let ((target (model:node-field-value node :target)))
    (and target (list (model:target-kind target) (model:target-id target)))))

(define-test resolve-sections-lookup
  :parent resolve-sections
  (let* ((model (secref-fixture))
         (problems (model:resolve-section-references model))
         (targets (mapcar #'secref-target (secref-refs model))))
    (is equal '((:section "B") (:figure "F") (:chapter "ChapTwo") nil nil nil) targets)
    (is equal '(:unresolved-reference :unresolved-reference :unresolved-reference)
        (mapcar #'model:problem-kind problems))
    (true (search "No chapter or section has the label \"Missing\"" (model:problem-message (first problems))))
    (true (search "No figure has the label \"A\"" (model:problem-message (second problems))))
    (true (search "ambiguous" (model:problem-message (third problems))))))

(define-test resolve-sections-label-forms
  :parent resolve-sections
  (is equal "Abc" (model::secref-label-id "\\Abc"))
  (is equal "Abc" (model::secref-label-id " \\Abc "))
  (is equal "Abc" (model::secref-label-id "Abc"))
  (is eq nil (model::secref-label-id "\\"))
  (is eq nil (model::secref-label-id "")))

(define-test resolve-sections-toc
  :parent resolve-sections
  (let ((toc (model:table-of-contents (secref-fixture))))
    (is equal '("ChapOne" "ChapTwo") (mapcar #'model:secref-toc-entry-id toc))
    (is equal '("A" "Dup") (mapcar #'model:secref-toc-entry-id
                                   (model:secref-toc-entry-children (first toc))))
    (is equal '("B") (mapcar #'model:secref-toc-entry-id
                             (model:secref-toc-entry-children
                              (first (model:secref-toc-entry-children (first toc))))))
    (is equal "1.1.1" (model:secref-toc-entry-number
                       (first (model:secref-toc-entry-children
                               (first (model:secref-toc-entry-children (first toc)))))))))

(define-test resolve-sections-figures
  :parent resolve-sections
  (let ((figures (model:list-of-figures (secref-fixture))))
    (is = 1 (length figures))
    (is equal '("F" "1-1" ("Fig") "ChapOne")
        (let ((figure (first figures)))
          (list (model:secref-figure-entry-id figure) (model:secref-figure-entry-number figure)
                (model:secref-figure-entry-caption figure) (model:secref-figure-entry-chapter figure))))))

;;; The whole spec

(defvar *secref-whole* nil
  "The problems of resolving the whole spec's references, once per run.")

(defun secref-whole-problems ()
  (or *secref-whole*
      (setf *secref-whole*
            (list (model:resolve-section-references (whole-spec-nodes))))))

(define-test resolve-sections-whole-spec
  :parent resolve-sections
  (let ((problems (first (secref-whole-problems))))
    (is equal '() (mapcar (lambda (p) (list (model:span-file (model:problem-span p))
                                            (model:span-line (model:problem-span p))
                                            (model:problem-message p)))
                          problems))))
