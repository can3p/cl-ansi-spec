;;;; tests/package.lisp

(defpackage #:cl-ansi-spec/tests
  (:use #:cl #:cl-ansi-spec #:cl-ansi-spec/tex)
  (:import-from #:parachute
                #:define-test #:test #:status #:is #:true #:false #:fail)
  (:local-nicknames (#:expand #:cl-ansi-spec/expand)
                    (#:semantic #:cl-ansi-spec/semantic))
  (:export #:run-tests #:write-snapshots))

(in-package #:cl-ansi-spec/tests)

(define-test cl-ansi-spec
  :description "Root suite of cl-ansi-spec.")

(defun run-tests ()
  "Run the whole test suite, print a report, and return true iff it passed."
  (eq :passed (status (test 'cl-ansi-spec :report 'parachute:plain))))
