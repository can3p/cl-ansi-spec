;;;; tools/model.lisp
;;;;
;;;; Print the model nodes built from a spec file's lines, and the build
;;;; report.  Reserved by step 3.0 of docs/plan/m3.md; step 3.3 writes it.
;;;;
;;;; Usage: make model FILE=chap-1 [LINES=10-20]

(load (merge-pathnames "setup.lisp" *load-truename*))

(in-package #:cl-ansi-spec.tools)

(with-exit-status
  (error "make model is not written yet (step 3.3 of docs/plan/m3.md)."))
