;;;; tests/export/whole-spec.lisp
;;;;
;;;; Tests of the exports of the whole spec: the report and the manifest
;;;; on fixtures, then the real export, written once to a temporary
;;;; directory: every file listed in the manifest with its digest, every
;;;; node of the JSON files valid against the schema, the S-expression
;;;; files read back, and the report pinned.

(in-package #:cl-ansi-spec/tests)

(define-test whole-spec-export
  :parent exports
  :description "The export of the whole spec: files, manifest, report.")

;;; The report and the manifest on fixtures

(defun export-fixture-report ()
  "A build report with a problem of each class of the report."
  (model:make-build-report
   (list (model:make-problem :unresolved-term (test-span 4 10 20 "a.tex")
                             :message "No glossary entry for \"x\"." :job "chap-1")
         (model:make-problem :tex-error (test-span 9 0 5 "b.tex")
                             :message "Undefined control sequence." :job "chap-2")
         (model:make-problem :unresolved-term nil :message "Again.")
         (model:make-problem :diagnostic nil :message "Unknown.")
         (model:make-problem :unhandled (test-span 1 0 1 "c.tex")
                             :event '(:begin :frob)))))

(define-test export-report-groups-by-kind
  :parent whole-spec-export
  (let* ((report (exports:export-report-object (export-fixture-report) "v"))
         (references (coerce (json-member report "unresolvedReferences") 'list))
         (errors (coerce (json-member report "texErrors") 'list))
         (other (coerce (json-member report "other") 'list)))
    (is equal "v" (json-member report "schemaVersion"))
    (is equal '("unresolved-term") (mapcar (lambda (g) (json-member g "kind")) references))
    (is = 2 (json-member (first references) "count"))
    (is equal '("No glossary entry for \"x\"." "Again.")
        (map 'list (lambda (item) (json-member item "message"))
             (json-member (first references) "items")))
    (is equal "chap-1" (json-member (aref (json-member (first references) "items") 0) "job"))
    (is = 4 (json-member (json-member (aref (json-member (first references) "items") 0) "span")
                         "line"))
    (is equal '("tex-error") (mapcar (lambda (g) (json-member g "kind")) errors))
    (is equal '("diagnostic" "unhandled") (mapcar (lambda (g) (json-member g "kind")) other))
    (true (plusp (length (json-member (first other) "description"))))))

(define-test export-manifest-object
  :parent whole-spec-export
  (let ((manifest (exports:export-manifest-object
                   '(("a.json" . "11") ("b.json" . "22")) "v"
                   :patches '(("0001-x.patch" "33")) :commit "abc")))
    (is equal '("schemaVersion" "generator" "source" "files")
        (mapcar #'car (cl-ansi-spec/json:json-object-members manifest)))
    (is equal "abc" (json-member (json-member manifest "generator") "commit"))
    (is equal "0.0.1" (json-member (json-member manifest "generator") "version"))
    (is = 64 (length (json-member (json-member manifest "source") "specSha256")))
    (let ((patch (aref (json-member (json-member manifest "source") "patches") 0)))
      (is equal "0001-x.patch" (json-member patch "name"))
      (is equal "33" (json-member patch "sha256")))
    (is equal '("a.json" "b.json")
        (map 'list (lambda (file) (json-member file "path")) (json-member manifest "files")))))

;;; The real export

(defparameter *export-problem-counts*
  '(("unresolved-term" . 199) ("unresolved-reference" . 92) ("ambiguous-reference" . 273)
    ("missing-sense" . 2))
  "The unresolved references of the whole spec by kind, pinned: a
change in a count is either a fix, to be recorded here, or a regression.")

(defparameter *export-other-counts* '(("diagnostic" . 9))
  "The problems of the whole spec that are neither references nor TeX
errors, by kind (tests/model/whole-spec.lisp pins each).")

(defun export-group-counts (groups)
  "The (kind . count) of each of the report's GROUPS, a JSON array."
  (map 'list (lambda (group) (cons (json-member group "kind") (json-member group "count")))
       groups))

(defun export-json-at (node pointer)
  "The value of the parsed JSON NODE at the JSON POINTER, or NIL."
  (let ((value node))
    (dolist (token (cl-ansi-spec/export::split-pointer pointer) value)
      (setf value (cond ((cl-ansi-spec/json:json-object-p value)
                         (json-member value token))
                        ((and (vectorp value) (not (stringp value)))
                         (aref value (parse-integer token)))
                        (t (return nil)))))))

(defun export-violation-key (node error)
  "(message kind) of the validation ERROR of NODE, kind that of the node
the error is at."
  (let ((at (export-json-at node (exports:validation-error-pointer error))))
    (list (exports:validation-error-message error)
          (and at (cl-ansi-spec/json:json-object-p at) (json-member at "kind")))))

(defun export-check-files (directory records schema)
  "Check the files of an export under DIRECTORY, listed by RECORDS: the
digests, the JSON nodes against SCHEMA (what they break is the second
value, ((message kind) . count), kind that of the node at the error), the
S-expression forms.  The first value is the number of nodes checked."
  (dolist (record records)
    (is equal (cdr record)
        (cl-ansi-spec/sha256:sha256-file-hex (merge-pathnames (car record) directory))
        (format nil "digest of ~A" (car record))))
  (let ((version (exports:schema-version)) (nodes 0) (violations '()))
    (dolist (record records)
      (let ((path (car record)))
        (cond ((string= path "report.json"))
              ((string= (pathname-type path) "json")
               (let* ((object (cl-ansi-spec/json:parse-json-file (merge-pathnames path directory)))
                      (key (if (eql 0 (search "chapters/" path))
                               "chapter"
                               (pathname-name path)))
                      (content (json-member object key)))
                 (is equal version (json-member object "schemaVersion"))
                 (true content (format nil "~A has ~A" path key))
                 (dolist (node (if (vectorp content) (coerce content 'list) (list content)))
                   (incf nodes)
                   (dolist (error (exports:validate-json schema node))
                     (let ((cell (assoc (export-violation-key node error) violations
                                        :test #'equal)))
                       (if cell
                           (incf (cdr cell))
                           (push (cons (export-violation-key node error) 1) violations)))))))
              (t
               (let ((form (exports:read-sexp-text
                            (uiop:read-file-string (merge-pathnames path directory)))))
                 (is equal :schema-version (first form))
                 (is equal version (second form)))))))
    (values nodes (nreverse violations))))

(define-test whole-spec-export-files
  :parent whole-spec-export
  (let ((directory (temporary-directory "export"))
        (schema (cl-ansi-spec/json:parse-json-file (exports:schema-pathname))))
    (model:forget-job-runs)
    (setf *whole-spec* nil)
    (unwind-protect
         (multiple-value-bind (document report) (model:build-document)
           (let* ((records (exports:write-whole-export document report directory))
                  (manifest (cl-ansi-spec/json:parse-json-file
                             (merge-pathnames "manifest.json" directory)))
                  (paths (mapcar #'car records)))
             ;; 31 chapters (front matter included), glossary, index, in
             ;; both formats, and the report.
             (is = (+ (* 2 (+ 31 2)) 1) (length records))
             (is = (length paths) (length (remove-duplicates paths :test #'string=)))
             (true (member "report.json" paths :test #'string=))
             (true (member "glossary.sexp" paths :test #'string=))
             ;; The manifest lists exactly the files written, with digests.
             (is equal records
                 (map 'list (lambda (file) (cons (json-member file "path")
                                                 (json-member file "sha256")))
                      (json-member manifest "files")))
             (is equal (exports:schema-version) (json-member manifest "schemaVersion"))
             (is equal (mapcar #'first (cl-ansi-spec/patch:applied-patches))
                 (map 'list (lambda (patch) (json-member patch "name"))
                      (json-member (json-member manifest "source") "patches")))
             (multiple-value-bind (nodes violations) (export-check-files directory records schema)
               (true (plusp nodes))
               (is equal '() violations "the export breaks the schema"))
             ;; The report is pinned.
             (let ((report (cl-ansi-spec/json:parse-json-file
                            (merge-pathnames "report.json" directory))))
               (is equal (exports:schema-version) (json-member report "schemaVersion"))
               (is equal (sort (copy-list *export-problem-counts*) #'string< :key #'car)
                   (sort (export-group-counts (json-member report "unresolvedReferences"))
                         #'string< :key #'car))
               (is equal '() (export-group-counts (json-member report "texErrors")))
               (is equal *export-other-counts*
                   (export-group-counts (json-member report "other"))))))
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))
