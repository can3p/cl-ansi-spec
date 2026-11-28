;;;; tests/model/resolve-operators.lisp
;;;;
;;;; Tests of operator references (src/model/resolve-operators.lisp): each
;;;; rule on a small model made here, then the whole spec's counts.
;;;; Owner: step 3.18 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/tests)

(define-test resolve-operators
  :parent model
  :description "Operator references resolved to dictionary entries.")

(defun clref-entry (id kind &rest names)
  "A dictionary entry node for the tests."
  (model:make-node :dictionary-entry :id id :entry-kind kind :names names))

(defun clref-ref (via text)
  "An operator reference node for the tests."
  (model:make-node :operator-ref :via via :text text))

(defun clref-model ()
  "The entries the tests resolve against, as a model (a list of nodes)."
  (list (clref-entry "endp" :function "endp")
        (clref-entry "list/system-class" :system-class "list")
        (clref-entry "list/function" :function "list")
        (clref-entry "caar" :function "caar" "cdar")
        (clref-entry "and/macro" :macro "and")
        (clref-entry "and/type-specifier" :type-specifier "and")
        (clref-entry "*/function" :function "*")
        (clref-entry "*/variable" :variable "*")))

(defun clref-outcome (via text)
  "The outcome, ids and message of resolving a VIA reference to TEXT
against the test model."
  (model:clref-resolve via text (model:clref-index (clref-model))))

(define-test clref-normalise
  :parent resolve-operators
  (is equal "endp" (model:clref-normalise "  endp "))
  (is equal "&key" (model:clref-normalise "\\&key"))
  (is equal "a&b" (model:clref-normalise "a\\&b"))
  (is equal "\\fi" (model:clref-normalise "\\fi")))

(define-test clref-index
  :parent resolve-operators
  (let ((index (model:clref-index (clref-model))))
    (is equal '((:function . "caar")) (gethash "cdar" index))
    (is equal '((:system-class . "list/system-class") (:function . "list/function"))
        (gethash "list" index))
    (is equal '() (gethash "nothing" index))))

(define-test clref-rules
  :parent resolve-operators
  ;; One entry: resolved, whatever the wrapper (a mismatch of kind is no error).
  (is equal '(:resolved ("endp") nil) (multiple-value-list (clref-outcome :any "endp")))
  (is eql :resolved (clref-outcome :macro "endp"))
  (is equal '("caar") (nth-value 1 (clref-outcome :function "cdar")))
  ;; Several: the wrapper's kind decides, else the name is ambiguous.
  (is equal '("list/system-class") (nth-value 1 (clref-outcome :type "list")))
  (is equal '("list/function") (nth-value 1 (clref-outcome :function "list")))
  (is equal '("and/macro") (nth-value 1 (clref-outcome :macro "and")))
  (is equal '("*/variable") (nth-value 1 (clref-outcome :variable "*")))
  (is eql :ambiguous (clref-outcome :any "list"))
  (is equal '("list/system-class" "list/function") (nth-value 1 (clref-outcome :any "list")))
  (is eql :ambiguous (clref-outcome :misc "*"))
  ;; None.
  (is eql :unresolved (clref-outcome :function "nothing"))
  (is eql :unresolved (clref-outcome :misc ""))
  (is eql :entryless (clref-outcome :keyword ""))
  ;; Names no entry can have.
  (is eql :entryless (clref-outcome :keyword "list"))
  (is eql :entryless (clref-outcome :package "list"))
  (is eql :entryless (clref-outcome :loop-keyword "and"))
  (is eql :entryless (clref-outcome :any ":test"))
  (is eql :entryless (clref-outcome :any "\\&key")))

(define-test clref-resolve-model
  :parent resolve-operators
  (let* ((good (clref-ref :function "cdar"))
         (kind (clref-ref :type "list"))
         (vague (clref-ref :any "list"))
         (lost (clref-ref :function "nothing"))
         (keyword (clref-ref :keyword ":test"))
         (model (append (clref-model)
                        (list (model:make-node :paragraph
                                               :content (list "see " good kind vague lost keyword))))))
    (multiple-value-bind (resolved findings) (model:resolve-operator-refs model)
      (is = 2 resolved)
      (is equal '(:ambiguous :unresolved) (mapcar #'model:clref-finding-outcome findings))
      (is eq vague (model:clref-finding-node (first findings)))
      (is eq lost (model:clref-finding-node (second findings)))
      (is equal '("list/system-class" "list/function")
          (model:clref-finding-entries (first findings))))
    (let ((target (model:node-field-value good :target)))
      (is eql :entry (model:target-kind target))
      (is equal "caar" (model:target-id target)))
    (is equal "list/system-class"
        (model:target-id (model:node-field-value kind :target)))
    (false (model:node-field-value vague :target))
    (false (model:node-field-value lost :target))
    (false (model:node-field-value keyword :target))))

(define-test clref-apply-nil
  :parent resolve-operators
  (let* ((ref (clref-ref :function "endp"))
         (model (append (clref-model) (list (model:make-node :paragraph :content (list ref))))))
    (is = 1 (model:resolve-operator-refs model :apply nil))
    (false (model:node-field-value ref :target))))

;;; The whole spec

(defparameter *whole-spec-operator-findings*
  '(:resolved 12434 :ambiguous 273 :unresolved 89)
  "What resolving the whole spec's operator references finds; change it
deliberately, with the reason.  The unresolved ones are names the
dictionary has no entry for (`safety', `speed': declaration identifiers;
`variable', `structure': documentation types), and a few cells of
concept-pprint.tex and concept-arrays.tex whose argument holds markup
(`string{\\tt >=}').  The ambiguous ones grew by the cells that now
name `*', `-' or `/' (the function or the variable) once their `\\fi's are gone.")

(define-test clref-whole-spec
  :parent resolve-operators
  (let ((nodes (whole-spec-nodes)))
    (multiple-value-bind (resolved findings) (model:resolve-operator-refs nodes :apply nil)
      (let ((count (lambda (outcome)
                     (count outcome findings :key #'model:clref-finding-outcome))))
        (is equal *whole-spec-operator-findings*
            (list :resolved resolved :ambiguous (funcall count :ambiguous)
                  :unresolved (funcall count :unresolved))))
      ;; Whatever is left, every other kind of reference found its entry.
      (is equal '()
          (remove-if (lambda (via) (or (eq via :any)
                                       (assoc via model:*clref-preferred-kinds*)))
                     (mapcar (lambda (finding)
                               (model:node-field-value (model:clref-finding-node finding) :via))
                             findings))))))
