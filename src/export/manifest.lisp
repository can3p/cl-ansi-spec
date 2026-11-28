;;;; src/export/manifest.lisp
;;;;
;;;; The export of the whole spec (docs/exports.md, "The whole export"):
;;;; the document's chapter files, the glossary and the index, then
;;;; report.json (the problems of the build) and manifest.json (what the
;;;; export was made from, and the digest of every file).
;;;; Owner: step 3.20 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/export)

;;; The report

(defparameter *export-reference-problem-kinds*
  '(:unresolved-term :ambiguous-term :missing-sense
    :unresolved-reference :ambiguous-reference)
  "The kinds of problem that are references left unresolved or doubtful:
report.json's \"unresolvedReferences\".")

(defparameter *export-tex-problem-kinds* '(:tex-error :fatal-error)
  "The kinds of problem that are TeX errors: report.json's \"texErrors\".")

(defun export-problem-message (problem)
  "The message of PROBLEM, or, when it has none, a description of its event."
  (or (model:problem-message problem)
      (let ((event (model:problem-event problem)))
        (if event
            (format nil "~(~S~@[ ~S~]~)" (model:event-type event) (model:event-key event))
            (format nil "~(~A~)" (model:problem-kind problem))))))

(defun export-problem-object (problem)
  "The JSON object of PROBLEM: its job, span and message, the first two
left out when it has none."
  (let ((span (model:problem-span problem)))
    (json:make-json-object
     (append (when (model:problem-job problem)
               (list (cons "job" (model:problem-job problem))))
             (when span (list (cons "span" (span-object span))))
             (list (cons "message" (export-problem-message problem)))))))

(defun export-problem-groups (problems kinds)
  "The JSON array of one object per kind of KINDS that PROBLEMS has: its
\"kind\", \"description\" (from model:*problem-kinds*), \"count\" and
\"items\", in the order of the problems.  KINDS :ALL takes every kind
there is, in the order of first appearance."
  (let ((kinds (if (eq kinds :all)
                   (remove-duplicates (mapcar #'model:problem-kind problems)
                                      :from-end t)
                   kinds)))
    (schema-arr
     (loop for kind in kinds
           for items = (remove-if-not (lambda (problem) (eq kind (model:problem-kind problem))) problems)
           when items
             collect (schema-obj
                      "kind" (string-downcase (symbol-name kind))
                      "description" (or (second (assoc kind model:*problem-kinds*)) "")
                      "count" (length items)
                      "items" (schema-arr (mapcar #'export-problem-object items)))))))

(defun export-report-object (report schema-version)
  "The JSON object of report.json for the build REPORT: the references
the build could not resolve, by kind with the reason of each; the TeX
errors it recovered from; every other problem, by kind."
  (let* ((problems (model:build-report-problems report))
         (special (append *export-reference-problem-kinds* *export-tex-problem-kinds*))
         (others (remove-if (lambda (problem) (member (model:problem-kind problem) special))
                            problems)))
    (schema-obj
     "schemaVersion" schema-version
     "unresolvedReferences" (export-problem-groups problems *export-reference-problem-kinds*)
     "texErrors" (export-problem-groups problems *export-tex-problem-kinds*)
     "other" (export-problem-groups others :all))))

;;; The manifest

(defun export-generator-commit ()
  "The git commit the working tree is at, or \"unknown\" outside a checkout."
  (or (ignore-errors
       (let ((commit (string-trim '(#\Newline #\Space)
                                  (uiop:run-program
                                   (list "git" "-C"
                                         (namestring (asdf:system-relative-pathname
                                                      "cl-ansi-spec" ""))
                                         "rev-parse" "HEAD")
                                   :output :string :error-output nil))))
         (and (plusp (length commit)) commit)))
      "unknown"))

(defun export-spec-digest ()
  "The SHA-256 of spec/SHA256SUMS, which names the sources by their digests."
  (sha256:sha256-file-hex (asdf:system-relative-pathname "cl-ansi-spec" "spec/SHA256SUMS")))

(defun export-manifest-object (records schema-version &key (patches (patch:applied-patches))
                                                            (commit (export-generator-commit)))
  "The JSON object of manifest.json: the schemaVersion; the generator (its
version and COMMIT); the source (the digest of spec/SHA256SUMS and the
PATCHES, a list of (name sha256), in order); the files of RECORDS, a list of
(path . sha256)."
  (schema-obj
   "schemaVersion" schema-version
   "generator" (schema-obj
                "name" "cl-ansi-spec"
                "version" (asdf:component-version (asdf:find-system "cl-ansi-spec"))
                "commit" commit)
   "source" (schema-obj
             "specSha256" (export-spec-digest)
             "patches" (schema-arr (loop for (name digest) in patches
                                         collect (schema-obj "name" name "sha256" digest))))
   "files" (schema-arr (loop for (path . digest) in records
                             collect (schema-obj "path" path "sha256" digest)))))

;;; The whole export

(defun export-collect (document kind)
  "The nodes of KIND (a node kind) of DOCUMENT, at any depth, in order."
  (let ((found '()))
    (model:walk-nodes (lambda (node) (when (eq (model:node-kind node) kind) (push node found)))
                      (list document))
    (nreverse found)))

(defun export-write-json (directory name object)
  "Write OBJECT as DIRECTORY/NAME (JSON); return (NAME . sha256)."
  (let ((pathname (merge-pathnames name directory)))
    (ensure-directories-exist pathname)
    (json:write-json-file object pathname)
    (cons name (sha256:sha256-file-hex pathname))))

(defun write-whole-export (document report directory &key (formats '(:json :sexp))
                                                         (schema-version (schema-version))
                                                         (patches (patch:applied-patches))
                                                         (commit (export-generator-commit)))
  "Write the whole spec's export under DIRECTORY: the files of DOCUMENT
(WRITE-EXPORT-FILES) with its glossary groups as the glossary and its
index entries as the index, then report.json for the build REPORT, and
manifest.json, which lists them all with their digests.  Return the
manifest's records, (path . sha256)."
  (let* ((records (write-export-files document directory
                                      :glossary (export-collect document :glossary-group)
                                      :index (export-collect document :index-entry)
                                      :formats formats :schema-version schema-version))
         (records (append records
                          (list (export-write-json
                                 directory "report.json"
                                 (export-report-object report schema-version))))))
    (export-write-json directory "manifest.json"
                       (export-manifest-object records schema-version
                                               :patches patches :commit commit))
    records))
