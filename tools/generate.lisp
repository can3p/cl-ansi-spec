;;;; tools/generate.lisp
;;;;
;;;; Rewrite the generated files of the repository (docs/exports.md, "One
;;;; definition, everything generated") from the node registry: every
;;;; generator registered with DEFINE-GENERATOR (src/export/generate.lisp),
;;;; printing the paths whose contents changed.  `make test' fails while
;;;; one is stale.
;;;;
;;;; Usage: make generate

(load (merge-pathnames "setup.lisp" *load-truename*))

(in-package #:cl-ansi-spec.tools)

(configure-asdf)

(with-exit-status
  ;; Built as `make test' builds, so that no file comes from a build the
  ;; suite would reject.
  (handler-bind ((warning (lambda (condition)
                            (unless (typep condition sb-ext:*muffled-warnings*)
                              (error "Build warning: ~A" condition)))))
    (let ((*standard-output* (make-broadcast-stream)))
      (asdf:load-system "cl-ansi-spec" :force '("cl-ansi-spec"))))
  (let ((written (uiop:symbol-call '#:cl-ansi-spec/export '#:write-generated-files
                                   (asdf:system-relative-pathname "cl-ansi-spec" ""))))
    (format t "~:[No generated file changed.~;~:*~{Wrote ~A~%~}~]~%" written))
  t)
