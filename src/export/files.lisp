;;;; src/export/files.lisp
;;;;
;;;; The file layout of an export (docs/exports.md, "Files"): one file per
;;;; chapter under chapters/, then glossary and index, each as JSON and as an
;;;; S-expression, every one stating the schemaVersion: the SHA-256 of the
;;;; committed schema.  The manifest and the report are step 3.20's.
;;;; Owner: step 3.7 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/export)

(defun schema-pathname ()
  "The committed JSON Schema."
  (asdf:system-relative-pathname "cl-ansi-spec" "schema/model.schema.json"))

(defun schema-version (&optional (pathname (schema-pathname)))
  "The schemaVersion: the lowercase hex SHA-256 of the bytes of the schema
file PATHNAME."
  (sha256:sha256-file-hex pathname))

(defun safe-file-stem (id)
  "ID as a file name: letters, digits, dots, underscores and hyphens kept,
every other run of characters one hyphen."
  (with-output-to-string (out)
    (let ((gap nil))
      (loop for char across id
            do (cond ((or (alphanumericp char) (find char "._"))
                      (when gap (write-char #\- out) (setf gap nil))
                      (write-char char out))
                     (t (setf gap t))))
      (when gap (write-char #\- out)))))

(defun chapter-file-stem (id)
  "The file stem of the chapter id ID; an id that leaves none stops the export."
  (let ((stem (and (stringp id) (safe-file-stem id))))
    (when (or (null stem) (zerop (length stem)))
      (error "A chapter with id ~S cannot be named as a file." id))
    stem))

(defun export-file-name (kind &optional id)
  "The name, without extension, of the file of KIND: :chapter with the
chapter's ID is chapters/<id>, :glossary and :index are themselves."
  (ecase kind
    (:chapter (format nil "chapters/~A" (chapter-file-stem id)))
    (:glossary "glossary")
    (:index "index")))

(defun format-extension (format)
  "The file extension of the export FORMAT, :json or :sexp."
  (ecase format (:json "json") (:sexp "sexp")))

(defun file-object (schema-version content registry)
  "The JSON object of a file: schemaVersion, then CONTENT, a plist of keys
(keywords) and their nodes or lists of nodes."
  (json:make-json-object
   (cons (cons "schemaVersion" schema-version)
         (loop for (key node) on content by #'cddr
               collect (cons (json-name key)
                             (if (listp node)
                                 (schema-arr (mapcar (lambda (n) (node-json n registry)) node))
                                 (node-json node registry)))))))

(defun write-export-file (directory name format content schema-version
                          &optional (registry model:*registry*))
  "Write the file NAME (see EXPORT-FILE-NAME) under DIRECTORY in FORMAT with
CONTENT; return its path relative to DIRECTORY and its SHA-256, as a cons."
  (let* ((relative (format nil "~A.~A" name (format-extension format)))
         (pathname (merge-pathnames relative directory)))
    (ensure-directories-exist pathname)
    (ecase format
      (:json (json:write-json-file (file-object schema-version content registry) pathname))
      (:sexp (with-open-file (out pathname :direction :output :if-exists :supersede
                                           :external-format :utf-8)
               (write-string (sexp-text (file-sexp schema-version content registry)) out))))
    (cons relative (sha256:sha256-file-hex pathname))))

(defun write-export-files (document directory &key glossary index
                                                  (formats '(:json :sexp))
                                                  (schema-version (schema-version))
                                                  (registry model:*registry*))
  "Write the files of the model DOCUMENT under DIRECTORY, in each of FORMATS:
a file per chapter (front matter included), then glossary and index when
their nodes, lists of nodes, are given.  Return the (path . sha256) of
every file written, in order, for the manifest.  Two chapters whose ids
name one file stop the export."
  (let ((chapters (append (model:node-field-value document :front-matter registry)
                          (model:node-field-value document :chapters registry)))
        (names '()))
    (dolist (chapter chapters)
      (let ((name (export-file-name :chapter (model:node-field-value chapter :id registry))))
        (when (member name names :test #'string-equal)
          (error "Two chapters are exported as ~A (names compare without case)." name))
        (push name names)))
    (loop for format in formats
          append (append
                  (loop for chapter in chapters
                        collect (write-export-file
                                 directory
                                 (export-file-name :chapter
                                                   (model:node-field-value chapter :id registry))
                                 format (list :chapter chapter) schema-version registry))
                  (when glossary
                    (list (write-export-file directory (export-file-name :glossary) format
                                             (list :glossary glossary) schema-version registry)))
                  (when index
                    (list (write-export-file directory (export-file-name :index) format
                                             (list :index index) schema-version registry)))))))
