;;;; src/patch/conditions.lisp
;;;;
;;;; What can go wrong reading or applying a patch.  Every condition names
;;;; the patch, the hunk (its number in the patch, from 1) and a line: the
;;;; line of the patch text for reading errors, the line of the pristine
;;;; file for application errors.

(in-package #:cl-ansi-spec/patch)

(define-condition patch-error (error)
  ((patch :initarg :patch :initform nil :reader patch-error-patch
          :documentation "The patch's name (a file name), or NIL.")
   (hunk :initarg :hunk :initform nil :reader patch-error-hunk
         :documentation "The hunk's number in its patch, from 1, or NIL.")
   (line :initarg :line :initform nil :reader patch-error-line
         :documentation "A line number, from 1: in the patch text for a
syntax error, in the pristine file otherwise."))
  (:documentation "Base of every failure to read or apply a patch."))

(defun report-patch-location (condition stream)
  (format stream "patch ~A" (or (patch-error-patch condition) "<unnamed>"))
  (when (patch-error-hunk condition)
    (format stream ", hunk ~D" (patch-error-hunk condition)))
  (when (patch-error-line condition)
    (format stream ", line ~D" (patch-error-line condition)))
  (write-string ": " stream))

(define-condition patch-syntax-error (patch-error)
  ((reason :initarg :reason :reader patch-syntax-error-reason))
  (:report (lambda (condition stream)
             (report-patch-location condition stream)
             (write-string (patch-syntax-error-reason condition) stream)))
  (:documentation "The patch text is not a well-formed unified diff."))

(define-condition unsafe-patch-path (patch-syntax-error)
  ((path :initarg :path :reader unsafe-patch-path-path))
  (:report (lambda (condition stream)
             (report-patch-location condition stream)
             (format stream "path ~S is empty, absolute or has a \"..\" component."
                     (unsafe-patch-path-path condition))))
  (:documentation "A file path of the patch could leave the source tree."))

(define-condition patch-file-missing (patch-error)
  ((path :initarg :path :reader patch-file-missing-path))
  (:report (lambda (condition stream)
             (report-patch-location condition stream)
             (format stream "the file ~S to patch does not exist."
                     (patch-file-missing-path condition))))
  (:documentation "The file a patch names is not in the tree."))

(define-condition hunk-mismatch (patch-error)
  ((reason :initarg :reason :reader hunk-mismatch-reason)
   (expected :initarg :expected :initform nil :reader hunk-mismatch-expected)
   (actual :initarg :actual :initform nil :reader hunk-mismatch-actual))
  (:report (lambda (condition stream)
             (report-patch-location condition stream)
             (write-string (hunk-mismatch-reason condition) stream)
             (when (hunk-mismatch-expected condition)
               (format stream "; expected ~S, found ~S"
                       (hunk-mismatch-expected condition)
                       (hunk-mismatch-actual condition)))))
  (:documentation "A hunk's context or deleted lines are not the file's
lines at the hunk's pristine position, or it reaches past the file's end."))

(define-condition hunk-overlap (patch-error)
  ((other-patch :initarg :other-patch :reader hunk-overlap-other-patch)
   (other-hunk :initarg :other-hunk :reader hunk-overlap-other-hunk))
  (:report (lambda (condition stream)
             (report-patch-location condition stream)
             (format stream "overlaps or touches hunk ~D of patch ~A."
                     (hunk-overlap-other-hunk condition)
                     (hunk-overlap-other-patch condition))))
  (:documentation "Two hunks of one file share a line of the pristine file
(context included) or are adjacent, so the result would depend on order."))
