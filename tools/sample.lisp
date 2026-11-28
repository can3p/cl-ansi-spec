;;;; tools/sample.lisp
;;;;
;;;; Write the sample export (docs/exports.md, "The sample export"): a few
;;;; dictionary entries of the model as JSON and S-expressions, with their
;;;; manifest.json.  Builds the whole model first, so it takes as long as
;;;; `make export' to build it.
;;;;
;;;; Usage: make sample [OUT=build/sample/]

(load (merge-pathnames "setup.lisp" *load-truename*))

(in-package #:cl-ansi-spec.tools)

(configure-asdf)
(let ((*standard-output* (make-broadcast-stream)))
  (asdf:load-system "cl-ansi-spec"))

(with-exit-status
  (let ((out (let ((given (uiop:getenv "OUT")))
               (if (and given (string/= given ""))
                   (uiop:ensure-directory-pathname given)
                   (merge-pathnames "build/sample/" *root*)))))
    ;; Only what a sample consists of is replaced, never the rest of OUT.
    (uiop:delete-directory-tree (merge-pathnames "entries/" out)
                                :validate t :if-does-not-exist :ignore)
    (uiop:delete-file-if-exists (merge-pathnames "manifest.json" out))
    (let ((records (cl-ansi-spec/export:write-sample-export
                    (cl-ansi-spec/model:build-document) out)))
      (format t "Wrote ~D files and manifest.json to ~A~%" (length records) out))
    t))
