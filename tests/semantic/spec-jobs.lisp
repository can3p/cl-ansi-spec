;;;; tests/semantic/spec-jobs.lisp
;;;;
;;;; The whole spec: every chapter job runs from plain TeX's format,
;;;; observing the spec's vocabulary, once per test run; its errors and
;;;; reports are checked here.

(in-package #:cl-ansi-spec/tests)

(define-test spec-jobs
  :parent semantic
  :description "Every chapter job of the spec, observing the vocabulary.")

(defstruct (spec-run (:constructor make-spec-run (job errors fatal reports)))
  "What running the chapter job JOB gave: its ERRORS, (message file line)
in order, the message of a FATAL error or NIL, and the REPORTS of its
observer."
  job errors fatal reports)

(defvar *spec-runs* nil
  "The runs of every chapter job, made once per test run.")

(defun run-spec-job (job)
  "Run the chapter job JOB as `make events' does, observing the spec's
vocabulary; return its SPEC-RUN."
  (let* ((expander (expand:make-job (plain-format) :job-name job))
         (observer (semantic:observe-vocabulary expander (semantic:spec-vocabulary)))
         (errors '())
         (fatal nil))
    (expand:start-job expander job)
    (handler-case
        (handler-bind ((expand:job-output (lambda (condition) (declare (ignore condition))))
                       (expand:tex-report (lambda (condition) (declare (ignore condition)))))
          (expand:call-recovering-tex-errors
           (lambda () (expand:main-control expander))
           (lambda (condition)
             (let ((span (expand:tex-error-span condition)))
               (push (list (expand:tex-error-message condition)
                           (and span (span-file span))
                           (and span (span-line span)))
                     errors)))))
      (expand:tex-fatal-error (condition)
        (setf fatal (expand:tex-error-message condition))))
    (make-spec-run job (nreverse errors) fatal (semantic:observer-reports observer))))

(defun spec-runs ()
  "The SPEC-RUNs of every chapter job."
  (or *spec-runs*
      (setf *spec-runs* (mapcar #'run-spec-job (cl-ansi-spec/inventory:chapter-jobs)))))

(defparameter *source-error-lines* '("concept-syntax.tex" 279 302)
  "Where the sources themselves are wrong, so that TeX reports errors too:
the table of concept-syntax.tex:279-302 uses \\w, \\c, \\SE ... whose
definitions, and the group they open, are commented out (:271-278),
while the group's closing brace (:302) is not.  A patch will restore
them (M4).")

(define-test spec-jobs-run
  :parent spec-jobs
  ;; No job stops, and the only errors are the sources' own: chap-2's,
  ;; reading the table, at its lines or in the macros it calls.
  (destructuring-bind (file first last) *source-error-lines*
    (dolist (run (spec-runs))
      (false (spec-run-fatal run) "~A stops: ~A" (spec-run-job run) (spec-run-fatal run))
      (if (string= (spec-run-job run) "chap-2")
          (progn
            ;; 127: each row of the table meets undefined \\w, \\c ...
            ;; and misplaced &s; any change of the expander's error
            ;; recovery shows here.
            (is = 127 (length (spec-run-errors run)))
            (dolist (error (spec-run-errors run))
              (destructuring-bind (message error-file line) error
                (true (or (and (equal error-file file) (<= first line last))
                          ;; \\tablefigfour, which sets the table, and
                          ;; plain's \\cr and \\c it meets.
                          (and (equal error-file "setup-tables.tex") (<= 177 line 207))
                          (equal error-file "plain.tex"))
                      "chap-2: ~A at ~A:~A" message error-file line))))
          (is equal '() (spec-run-errors run) "errors of ~A" (spec-run-job run))))))
