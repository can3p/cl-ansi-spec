;;;; src/export/sample.lisp
;;;;
;;;; The sample export (docs/exports.md, "The sample export"): a few
;;;; dictionary entries of the model, each as a file of its own in both
;;;; formats, with a manifest, so that code reading the exports can be
;;;; written and tested without running the parser.
;;;; Owner: step 3.22 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/export)

(defparameter *sample-entry-ids*
  '("endp" "boolean" "type-error" "when" "car" "*print-base*")
  "The ids of the dictionary entries of the sample, in order: a function
(the worked example of docs/consuming.md), a system class, a condition
type, a macro, an accessor and a variable.  Each is valid against the
schema (the suite checks it).")

(defun sample-entry (document id)
  "The dictionary entry of DOCUMENT whose id is ID; an error when there is
not exactly one."
  (let ((found (remove-if-not (lambda (entry) (equal id (model:node-field-value entry :id)))
                              (export-collect document :dictionary-entry))))
    (unless (= 1 (length found))
      (error "The sample wants one dictionary entry with id ~S, the model has ~D."
             id (length found)))
    (first found)))

(defun sample-file-name (id)
  "The name, without extension, of the sample file of the entry ID."
  (format nil "entries/~A" (safe-file-stem id)))

(defun write-sample-export (document directory &key (ids *sample-entry-ids*)
                                                    (formats '(:json :sexp))
                                                    (schema-version (schema-version))
                                                    (patches (patch:applied-patches))
                                                    (commit (export-generator-commit)))
  "Write the sample export under DIRECTORY: for each of IDS the dictionary
entry of DOCUMENT as entries/<id>.json and .sexp (FORMATS), a file whose
content is `entry', then manifest.json listing them with their digests.
Return the manifest's records, (path . sha256)."
  (let* ((entries (mapcar (lambda (id) (sample-entry document id)) ids))
         (records (loop for format in formats
                        append (loop for id in ids
                                     for entry in entries
                                     collect (write-export-file directory (sample-file-name id)
                                                                format (list :entry entry)
                                                                schema-version)))))
    (export-write-json directory "manifest.json"
                       (export-manifest-object records schema-version
                                               :patches patches :commit commit))
    records))
