;;;; tools/export.lisp
;;;;
;;;; Write the export of the whole spec to build/export/ (docs/exports.md,
;;;; "The whole export"): the model of every chapter job, as JSON and as
;;;; S-expressions, with report.json and manifest.json.  Prints the number
;;;; of files and the problems of the build by kind.
;;;;
;;;; Usage: make export [OUT=build/export/]

(load (merge-pathnames "setup.lisp" *load-truename*))

(in-package #:cl-ansi-spec.tools)

(configure-asdf)
(let ((*standard-output* (make-broadcast-stream)))
  (asdf:load-system "cl-ansi-spec"))

(with-exit-status
  (let* ((out (let ((given (uiop:getenv "OUT")))
                (if (and given (string/= given ""))
                    (uiop:ensure-directory-pathname given)
                    (merge-pathnames "build/export/" *root*))))
         (counts '()))
    ;; Only a previous export is replaced: never an arbitrary directory.
    (when (and (probe-file out) (not (probe-file (merge-pathnames "manifest.json" out))))
      (error "~A exists and holds no manifest.json: not an export, left alone." out))
    (uiop:delete-directory-tree out :validate t :if-does-not-exist :ignore)
    (multiple-value-bind (document report) (cl-ansi-spec/model:build-document)
      (let ((records (cl-ansi-spec/export:write-whole-export document report out)))
        (dolist (problem (cl-ansi-spec/model:build-report-problems report))
          (incf (getf counts (cl-ansi-spec/model:problem-kind problem) 0)))
        (format t "Wrote ~D files and manifest.json to ~A~%" (length records) out)
        (loop for (kind count) on counts by #'cddr
              do (format t "-- ~(~A~) x~D~%" kind count))))
    t))
