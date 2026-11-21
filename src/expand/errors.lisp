;;;; src/expand/errors.lisp
;;;;
;;;; TeX's errors as conditions.  TeX reports an error and then recovers
;;;; in a fixed way (inserting or dropping tokens), as it does in
;;;; \batchmode; here TEX-ERROR signals a condition with a RECOVER restart
;;;; that takes that way.  A handler decides: log and recover (what every
;;;; job does, see CALL-RECOVERING-TEX-ERRORS) or stop.  Errors TeX cannot
;;;; recover from (a missing input file in nonstop mode) are
;;;; TEX-FATAL-ERRORs, with no restart.

(in-package #:cl-ansi-spec/expand)

(define-condition tex-error (error)
  ((message :initarg :message :reader tex-error-message
            :documentation "TeX's error message, e.g. \"Undefined control
sequence\".")
   (context :initarg :context :initform nil :reader tex-error-context
            :documentation "Extra detail TeX prints with the message, e.g.
the control sequence concerned, or NIL.")
   (span :initarg :span :initform nil :reader tex-error-span
         :documentation "The span of the token being read, or NIL."))
  (:report (lambda (condition stream)
             (format stream "! ~A~@[ ~A~]~@[ (~A)~]"
                     (tex-error-message condition)
                     (tex-error-context condition)
                     (tex-error-span condition))))
  (:documentation "An error TeX reports and recovers from."))

(define-condition tex-fatal-error (tex-error)
  ()
  (:documentation "An error that ends the TeX job."))

(defun tex-error (message &key context span)
  "Signal a TEX-ERROR with MESSAGE, CONTEXT and SPAN.  Returns NIL when a
handler invokes the RECOVER restart; the caller then recovers as TeX
does."
  (restart-case (error 'tex-error :message message :context context :span span)
    (recover ()
      :report "Continue as TeX does after this error."
      nil)))

(defun tex-fatal-error (message &key context span)
  "Signal a TEX-FATAL-ERROR; there is no way to continue."
  (error 'tex-fatal-error :message message :context context :span span))

(defun call-recovering-tex-errors (function &optional (report (constantly nil)))
  "Call FUNCTION; every TEX-ERROR it signals is passed to REPORT and then
recovered from as TeX does.  Fatal errors are not caught."
  (handler-bind ((tex-error
                   (lambda (condition)
                     (let ((restart (find-restart 'recover condition)))
                       (when restart
                         (funcall report condition)
                         (invoke-restart restart))))))
    (funcall function)))
