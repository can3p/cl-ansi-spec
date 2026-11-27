;;;; tests/export/writers.lisp
;;;;
;;;; Tests of the writers: the omission rules, text merging, targets, the
;;;; S-expression form, the file layout and the schemaVersion, and the round
;;;; trip of a fixture model (written, read back, validated against the
;;;; committed schema).
;;;; Owner: step 3.7 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/tests)

(define-test writers
  :parent cl-ansi-spec
  :description "The S-expression and JSON writers.")

(defun fixture-paragraph ()
  "A paragraph with adjacent text, a resolved and an unresolved term."
  (model:make-node
   :paragraph :span (test-span 3 40 90 "chap-fix.tex")
   :content (list "A " "dotted "
                  (model:make-node :term-ref :span (test-span 3 50 60 "chap-fix.tex")
                                   :text "list" :defining t
                                   :target (model:make-target :glossary "list"))
                  "" " and "
                  (model:make-node :term-ref :span (test-span 3 70 80 "chap-fix.tex")
                                   :text "nothing"))))

(defun fixture-document ()
  "A document of one chapter, with a paragraph and an issue anchor."
  (let ((chapter (model:make-node
                  :chapter :span (test-span 1 0 100 "chap-fix.tex")
                  :id "ChapFix" :number "1" :title (list "Fix" "ture")
                  :children (list (fixture-paragraph)))))
    (model:make-node :document :span (test-span 1 0 100 "chap-fix.tex")
                              :version "1" :chapters (list chapter))))

(defun json-member (object name)
  (cl-ansi-spec/json:json-get object name))

(define-test writer-merges-text
  :parent writers
  (let* ((json (exports:node-json (fixture-paragraph)))
         (content (coerce (json-member json "content") 'list))
         (kinds (mapcar (lambda (item) (json-member item "kind")) content)))
    (is equal '("text" "term-ref" "text" "term-ref") kinds)
    (is equal "A dotted " (json-member (first content) "text"))
    (is equal " and " (json-member (third content) "text"))))

(define-test writer-targets
  :parent writers
  (let* ((content (coerce (json-member (exports:node-json (fixture-paragraph)) "content") 'list))
         (resolved (second content))
         (unresolved (fourth content)))
    (true (cl-ansi-spec/json:json-object-p (json-member resolved "target")))
    (is equal "list" (json-member (json-member resolved "target") "id"))
    (is equal "glossary" (json-member (json-member resolved "target") "kind"))
    (is eq :true (json-member resolved "defining"))
    ;; always present, null when unresolved; a false optional boolean is left out
    (is eq :null (json-member unresolved "target"))
    (false (nth-value 1 (json-member unresolved "defining")))))

(define-test writer-omits-empty
  :parent writers
  (let* ((bare (model:make-node :chapter :span (test-span 1 0 1) :id "X" :title '("T")))
         (json (exports:node-json bare)))
    (is equal '("kind" "span" "id" "title")
        (mapcar #'car (cl-ansi-spec/json:json-object-members json)))))

(define-test writer-member-order
  :parent writers
  (is equal '("kind" "span" "id" "number" "title" "children")
      (mapcar #'car (cl-ansi-spec/json:json-object-members
                     (exports:node-json
                      (first (model:node-field-value (fixture-document) :chapters)))))))

(define-test schema-version-is-schema-digest
  :parent writers
  (is equal (cl-ansi-spec/sha256:sha256-file-hex (exports:schema-pathname))
      (exports:schema-version))
  (is = 64 (length (exports:schema-version))))

(define-test export-file-names
  :parent writers
  (is equal "chapters/ChapOne" (exports:export-file-name :chapter "ChapOne"))
  (is equal "chapters/Cover-Page-" (exports:export-file-name :chapter "Cover Page/"))
  (is equal "glossary" (exports:export-file-name :glossary))
  (is equal "index" (exports:export-file-name :index)))

(define-test writer-exact-values
  :parent writers
  (let* ((json (exports:node-json (fixture-paragraph)))
         (span (json-member json "span"))
         (anchor (exports:node-json
                  (model:make-node :issue-start :span (test-span 5 1 2) :name "X:Y"))))
    (is equal '(("file" . "chap-fix.tex") ("start" . 40) ("end" . 90) ("line" . 3) ("column" . 0))
        (cl-ansi-spec/json:json-object-members span))
    (is equal "X:Y" (json-member anchor "name"))
    (is equal "issue-start" (json-member anchor "kind"))
    ;; a required field without a value is written empty, not hidden
    (is equal 0 (length (json-member (exports:node-json
                                      (model:make-node :paragraph :span (test-span 1 0 1)))
                                     "content")))))

(define-test writer-file-errors
  :parent writers
  (fail (exports:export-file-name :chapter ""))
  (fail (exports:export-file-name :chapter nil))
  (fail (exports:read-sexp-text "(:a) (:b)")))

(define-test sexp-file-round-trip
  :parent writers
  (let* ((chapter (first (model:node-field-value (fixture-document) :chapters)))
         (form (exports:file-sexp "abc" (list :chapter chapter)))
         (read-back (exports:read-sexp-text (exports:sexp-text form))))
    (is equal form read-back)
    (is eq :schema-version (first read-back))
    (is equal "abc" (second read-back))
    (is eq :chapter (third read-back))
    (is eq :chapter (first (fourth read-back)))))

(defun temporary-directory (name)
  (let ((directory (merge-pathnames (format nil "cl-ansi-spec-~A-~D/" name (random (expt 2 40)))
                                    (uiop:temporary-directory))))
    (ensure-directories-exist directory)
    directory))

(define-test json-round-trip-validates
  :parent writers
  (let* ((directory (temporary-directory "writers"))
         (document (fixture-document))
         (records (exports:write-export-files
                        document directory
                        :glossary (list (model:make-node
                                         :glossary-group :span (test-span 1 0 1)
                                         :letter "A"
                                         :entries (list (model:make-node
                                                         :glossary-entry :span (test-span 1 0 1)
                                                         :id "a" :term "a"
                                                         :senses (list (model:make-node
                                                                        :glossary-sense
                                                                        :span (test-span 1 0 1)))))))
                        :index (list (model:make-node :index-entry :span (test-span 2 0 1)
                                                                   :index-kind :term :text "list"))))
         (schema (cl-ansi-spec/json:parse-json-file (exports:schema-pathname)))
         (paths (mapcar #'car records)))
    (unwind-protect
         (progn
           (is equal '("chapters/ChapFix.json" "glossary.json" "index.json"
                       "chapters/ChapFix.sexp" "glossary.sexp" "index.sexp")
               paths)
           (dolist (record records)
             (is equal (cdr record)
                 (cl-ansi-spec/sha256:sha256-file-hex (merge-pathnames (car record) directory))))
           (dolist (entry '(("chapters/ChapFix.json" "chapter")
                            ("glossary.json" "glossary")
                            ("index.json" "index")))
             (let* ((object (cl-ansi-spec/json:parse-json-file
                             (merge-pathnames (first entry) directory)))
                    (content (json-member object (second entry))))
               (is equal (exports:schema-version) (json-member object "schemaVersion"))
               (dolist (node (if (vectorp content) (coerce content 'list) (list content)))
                 (is equal '() (exports:validate-json schema node)))))
           (let ((form (exports:read-sexp-text
                        (uiop:read-file-string (merge-pathnames "chapters/ChapFix.sexp" directory)))))
             (is equal (exports:schema-version) (second form))))
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))
