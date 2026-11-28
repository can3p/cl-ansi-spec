;;;; tests/export/sample.lisp
;;;;
;;;; Tests of the sample export: the files, the manifest and the digests
;;;; on the real model, every entry valid against the schema.
;;;; Owner: step 3.22 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/tests)

(define-test sample-export
  :parent exports
  :description "The sample export: a few entries with their manifest.")

(define-test sample-export-files
  :parent sample-export
  (let ((directory (temporary-directory "sample"))
        (schema (cl-ansi-spec/json:parse-json-file (exports:schema-pathname)))
        (ids exports:*sample-entry-ids*))
    (model:forget-job-runs)
    (setf *whole-spec* nil)
    (unwind-protect
         (let* ((records (exports:write-sample-export (model:build-document) directory))
                (manifest (cl-ansi-spec/json:parse-json-file
                           (merge-pathnames "manifest.json" directory))))
           ;; One file per entry and format; the manifest lists them all.
           (is = (* 2 (length ids)) (length records))
           (is equal records
               (map 'list (lambda (file) (cons (json-member file "path")
                                               (json-member file "sha256")))
                    (json-member manifest "files")))
           (is equal (exports:schema-version) (json-member manifest "schemaVersion"))
           (true (member "entries/endp.json" (mapcar #'car records) :test #'string=))
           (dolist (record records)
             (is equal (cdr record)
                 (cl-ansi-spec/sha256:sha256-file-hex (merge-pathnames (car record) directory))
                 (format nil "digest of ~A" (car record))))
           ;; Each JSON file holds its entry, valid against the schema.
           (dolist (id ids)
             (let* ((object (cl-ansi-spec/json:parse-json-file
                             (merge-pathnames (format nil "~A.json" (exports:sample-file-name id))
                                              directory)))
                    (entry (json-member object "entry")))
               (is equal (exports:schema-version) (json-member object "schemaVersion"))
               (is equal "dictionary-entry" (json-member entry "kind"))
               (is equal id (json-member entry "id"))
               (is equal '() (exports:validate-json schema entry) (format nil "~A is valid" id))))
           ;; The S-expression files read back, with the same entry ids.
           (dolist (id ids)
             (let ((form (exports:read-sexp-text
                          (uiop:read-file-string
                           (merge-pathnames (format nil "~A.sexp" (exports:sample-file-name id))
                                            directory)))))
               (is eq :schema-version (first form))
               (is equal (exports:schema-version) (second form))
               (is eq :entry (third form))
               (is equal id (getf (rest (fourth form)) :id)))))
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))

(define-test sample-entry-missing-is-an-error
  :parent sample-export
  (let ((document (fixture-document)))
    (fail (exports:sample-entry document "no-such-entry") error)))
