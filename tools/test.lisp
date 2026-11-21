;;;; tools/test.lisp
;;;;
;;;; Build the project with warnings treated as errors and run the test
;;;; suite.  Exits non-zero on failure.  Usage: make test

(load (merge-pathnames "setup.lisp" *load-truename*))

(in-package #:cl-ansi-spec.tools)

(configure-asdf)

(with-exit-status
  ;; Third-party code is built with ASDF's default (lenient) settings ...
  (asdf:load-system "parachute")
  ;; ... our own code must compile from scratch without any warning,
  ;; style-warnings (e.g. undefined functions) included.  The only
  ;; exception is what SBCL itself muffles as uninteresting
  ;; (sb-ext:*muffled-warnings*): loading a file just compiled in this
  ;; image "redefines" each of its macros.
  (handler-bind ((warning (lambda (condition)
                            (unless (typep condition sb-ext:*muffled-warnings*)
                              (error "Build warning: ~A" condition)))))
    (asdf:load-system "cl-ansi-spec/tests"
                      :force '("cl-ansi-spec" "cl-ansi-spec/tests")))
  (uiop:symbol-call '#:cl-ansi-spec/tests '#:run-tests))
