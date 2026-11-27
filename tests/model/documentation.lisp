;;;; tests/model/documentation.lisp
;;;;
;;;; The documentation of every declaration (docs/exports.md,
;;;; "Documentation of every definition"), with a ratchet: what still
;;;; lacks a docstring or an example is listed, area by area, in
;;;; tests/model/undocumented-<area>.sexp; an undocumented item missing
;;;; from its list fails, and so does a listed item that is now
;;;; documented or gone.  The lists are empty when the milestone closes.
;;;; Owner: step 3.1.

(in-package #:cl-ansi-spec/tests)

(defun ratchet-pathname (area)
  "The ratchet file of AREA."
  (asdf:system-relative-pathname
   "cl-ansi-spec" (format nil "tests/model/undocumented-~(~A~).sexp" area)))

(defun read-ratchet (area)
  "The items the ratchet file of AREA lists: its forms, read without
evaluation."
  (with-open-file (in (ratchet-pathname area) :external-format :utf-8)
    (with-standard-io-syntax
      (let ((*read-eval* nil))
        (loop for form = (read in nil in)
              until (eq form in)
              collect form)))))

(define-test model-documentation
  :parent model
  (is equal '() (model:registry-problems) "The model's declarations name what exists")
  (dolist (area model:*areas*)
    (let ((listed (read-ratchet area))
          (missing (model:undocumented-items area)))
      (is equal '() (set-difference missing listed :test #'equal)
          "Undocumented in ~(~A~), not in its ratchet file" area)
      (is equal '() (set-difference listed missing :test #'equal)
          "Listed in the ratchet of ~(~A~), but documented or gone" area))))

(define-test model-documentation-ratchet
  :parent model
  ;; UNDOCUMENTED-ITEMS on the kinds of tests/model/define-node.lisp.
  (let ((model:*registry* *test-registry*))
    (is equal '((:doc :node :test-ref) (:example :node :test-ref)
                (:doc :field :test-ref :to) (:example :field :test-ref :to))
        (model:undocumented-items :inlines))
    (is equal '((:example :field :test-entry :names)
                (:doc :field :test-entry :flavor)
                (:doc :field :test-entry :count) (:example :field :test-entry :count)
                (:doc :enum-value :test-kind :macro))
        (model:undocumented-items :entries))
    (is equal '() (model:undocumented-items :blocks))
    (fail (model:undocumented-items :nowhere))))
