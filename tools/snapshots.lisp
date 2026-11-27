;;;; tools/snapshots.lisp
;;;;
;;;; Rewrite tests/snapshots.sexp: run every chapter job, observing the
;;;; spec's vocabulary, and keep each one's event count and hash
;;;; (tests/semantic/spec-jobs.lisp), printing the jobs whose events
;;;; changed.  Run it in the commit that changes the events.
;;;;
;;;; Usage: make snapshots

(load (merge-pathnames "setup.lisp" *load-truename*))

(in-package #:cl-ansi-spec.tools)

(configure-asdf)

(with-exit-status
  ;; Built as `make test' builds, so that no snapshot comes from a build
  ;; the suite would reject.
  (asdf:load-system "parachute")
  (handler-bind ((warning (lambda (condition)
                            (unless (typep condition sb-ext:*muffled-warnings*)
                              (error "Build warning: ~A" condition)))))
    (let ((*standard-output* (make-broadcast-stream)))
      (asdf:load-system "cl-ansi-spec/tests"
                        :force '("cl-ansi-spec" "cl-ansi-spec/tests"))))
  (uiop:symbol-call '#:cl-ansi-spec/tests '#:write-snapshots)
  t)
