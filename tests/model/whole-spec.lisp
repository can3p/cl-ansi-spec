;;;; tests/model/whole-spec.lisp
;;;;
;;;; The whole spec's model: every chapter job built once per test run,
;;;; its ids settled (ASSIGN-IDS); the build report pinned, the
;;;; invariants checked, and each job's model kept as a snapshot
;;;; (tests/model-snapshots.sexp, written by `make snapshots').
;;;; Owner: step 3.16 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/tests)

(define-test whole-spec
  :parent model
  :description "The model of every chapter job of the spec.")

(defstruct (whole-spec (:constructor make-whole-spec (jobs report renamed)))
  "The whole spec built: JOBS, an alist from each chapter job to its
top-level nodes; the merged build REPORT; the ids ASSIGN-IDS RENAMED."
  jobs report renamed)

(defvar *whole-spec* nil
  "The whole spec's model, built once per test run (WHOLE-SPEC-BUILD).")

(defun whole-spec-build ()
  "The whole spec's model, built on first use.  The job runs the
fixtures keep are forgotten first: with them, the jobs built here would
not fit in the heap."
  (or *whole-spec*
      (setf *whole-spec*
            (let* ((reports (progn (model:forget-job-runs) '()))
                   (jobs (loop for job in (cl-ansi-spec:chapter-jobs)
                               collect (multiple-value-bind (nodes report) (model:build-job job)
                                         (push report reports)
                                         (cons job nodes))))
                   (nodes (mapcan (lambda (job) (copy-list (cdr job))) jobs)))
              (multiple-value-bind (renamed collisions) (model:assign-ids nodes)
                (push (model:make-build-report collisions) reports)
                (make-whole-spec jobs (model:merge-build-reports (nreverse reports)) renamed))))))

(defun whole-spec-nodes ()
  "Every top-level node of the whole spec, in order."
  (mapcan (lambda (job) (copy-list (cdr job))) (whole-spec-jobs (whole-spec-build))))

(defun whole-spec-all (kind)
  "Every node of KIND in the whole spec, at any depth, in order."
  (let ((found '()))
    (model:walk-nodes (lambda (node) (when (eq (model:node-kind node) kind) (push node found)))
                      (whole-spec-nodes))
    (nreverse found)))

;;; The build report

(defparameter *whole-spec-problems*
  (let ((sub-sense "a sense the glossary numbers only as a whole: \\meaning
names its sub-sense (1a, 2b), which the reference keeps as the sense's
number (docs/model.md, \"Glossary\")"))
    `(("chap-3" :diagnostic "dict-eval-compile.tex" 4092
       "The sense \"1a\" is a sub-sense of 1, kept as 1." ,sub-sense)
      ("chap-12" :node "concept-numbers.tex" 580 nil
       "the quadrant diagram of the branch cuts, drawn as an \\halign inside a
cell of another: a cell holds inlines, not a table")
      ("chap-26" :diagnostic "concept-glossary.tex" 131 "The sense \"n\" is not a number."
       "the glossary's own explanation of the notation, \\term{something}\\meaning{n}")
      ("chap-26" :diagnostic "concept-glossary.tex" 270
       "The sense \"2a\" is a sub-sense of 2, kept as 2." ,sub-sense)
      ("chap-26" :diagnostic "concept-glossary.tex" 1138
       "The sense \"1a\" is a sub-sense of 1, kept as 1." ,sub-sense)
      ("chap-26" :diagnostic "concept-glossary.tex" 1139
       "The sense \"1b\" is a sub-sense of 1, kept as 1." ,sub-sense)
      ("chap-26" :diagnostic "concept-glossary.tex" 2788
       "The sense \"1b\" is a sub-sense of 1, kept as 1." ,sub-sense)
      ("chap-26" :diagnostic "concept-glossary.tex" 4711
       "The sense \"1b\" is a sub-sense of 1, kept as 1." ,sub-sense)
      ("chap-26" :diagnostic "concept-glossary.tex" 5045
       "The sense \"2a\" is a sub-sense of 2, kept as 2." ,sub-sense)
      ("chap-26" :diagnostic "concept-glossary.tex" 5046
       "The sense \"2b\" is a sub-sense of 2, kept as 2." ,sub-sense)))
  "The problems of the whole spec's build, (job kind file line message
why): a construct the model does not hold or a diagnostic of a rule,
with the reason.  A NIL message
stands for any (one too long to pin, holding a node's printed form).")

(defun whole-spec-problem-row (problem)
  "PROBLEM as a row of *WHOLE-SPEC-PROBLEMS*."
  (let ((span (model:problem-span problem)))
    (list (model:problem-job problem) (model:problem-kind problem)
          (and span (model:span-file span)) (and span (model:span-line span))
          (model:problem-message problem))))

(define-test whole-spec-report
  :parent whole-spec
  ;; Every job builds; no event is unhandled; the only problems are those
  ;; listed, with their reasons.
  (let ((rows (mapcar #'whole-spec-problem-row
                      (model:build-report-problems (whole-spec-report (whole-spec-build))))))
    (is equal '() (remove-if-not (lambda (row) (member (second row) '(:unhandled :fatal-error)))
                                 rows))
    (is equal (mapcar (lambda (row) (subseq row 0 4)) *whole-spec-problems*)
        (mapcar (lambda (row) (subseq row 0 4)) rows))
    (loop for expected in *whole-spec-problems*
          for row in rows
          when (fifth expected)
            do (is equal (fifth expected) (fifth row)))))

;;; Invariants

(define-test whole-spec-chapters
  :parent whole-spec
  ;; Each job builds its chapters, and chap-0 its cover's three paragraphs
  ;; before them, so the document (BUILD-DOCUMENT) drops nothing: the cover
  ;; and the front matter of chap-0, then the 26 chapters and the appendix.
  (let* ((items (whole-spec-nodes))
         (chapters (remove-if-not (lambda (item)
                                    (and (typep item 'model:node)
                                         (eq (model:node-kind item) :chapter)))
                                  items)))
    (is equal '(:paragraph :paragraph :paragraph)
        (mapcar #'model:node-kind (ldiff items (member (first chapters) items))))
    (is = (+ 3 (length chapters)) (length items))
    ;; chap-0's four unnumbered chapters, then one numbered chapter a job.
    (is = 4 (count-if-not (lambda (chapter) (model:node-field-value chapter :number)) chapters))
    (is equal (append (loop for n from 1 to 26 collect (princ-to-string n)) '("A"))
        (remove nil (mapcar (lambda (chapter) (model:node-field-value chapter :number))
                            chapters)))))

(define-test whole-spec-issues
  :parent whole-spec
  ;; Every issue anchor pairs: each start is ended later by an end of its
  ;; name, and no end comes without its start.
  (let ((open '()) (unpaired '()))
    (model:walk-nodes
     (lambda (node)
       (case (model:node-kind node)
         (:issue-start (push (model:node-field-value node :name) open))
         (:issue-end (let ((name (model:node-field-value node :name)))
                       (if (member name open :test #'string=)
                           (setf open (remove name open :test #'string= :count 1))
                           (push (list :end name) unpaired))))))
     (whole-spec-nodes))
    (is equal '() (append unpaired (mapcar (lambda (name) (list :start name)) open)))))

(defparameter *whole-spec-renamed*
  '("lambda/symbol" "lambda/macro" "nil/type" "nil/constant-variable"
    "function/system-class" "function/special-operator" "t/system-class"
    "t/constant-variable" "member/type-specifier" "member/function"
    "not/type-specifier" "not/function" "and/type-specifier" "and/macro"
    "or/type-specifier" "or/macro" "values/type-specifier" "values/accessor"
    "eql/type-specifier" "eql/function" "error/condition-type" "error/function"
    "abort/restart" "abort/function" "complex/system-class" "complex/function"
    "float/system-class" "float/function" "rational/system-class"
    "rational/function" "mod/type-specifier" "mod/function" "bit/type"
    "bit/accessor" "*/function" "*/variable" "+/function" "+/variable"
    "-/function" "-/variable" "//function" "//variable"
    "character/system-class" "character/function" "list/system-class"
    "list/function" "null/system-class" "null/function" "cons/system-class"
    "cons/function" "atom/type" "atom/function" "vector/system-class"
    "vector/function" "string/system-class" "string/function"
    "pathname/system-class" "pathname/function" "logical-pathname/system-class"
    "logical-pathname/function")
  "The ids the collision rule gives, in document order: the dictionary
entries whose first name another entry shares (the names \\begincom's
first argument repeats in the sources).")

(define-test whole-spec-ids
  :parent whole-spec
  ;; The collision rule renames the entries that share a first name;
  ;; every node has an id (the collisions left are problems of the report,
  ;; pinned there).
  (is equal *whole-spec-renamed* (whole-spec-renamed (whole-spec-build)))
  (dolist (kind '(:chapter :section :dictionary-entry :glossary-entry :figure))
    (true (every (lambda (node) (plusp (length (model:node-field-value node :id))))
                 (whole-spec-all kind))
          "every ~(~A~) has an id" kind)))

(defparameter *whole-spec-unlabelled-sections* 456
  "How many sections have no \\DefineSection, so no label of their own:
their id is <parent-id>/<n> and their number, counted, is checked against
no write.")

(define-test whole-spec-sections
  :parent whole-spec
  ;; Sections without a \DefineSection are numbered, unchecked.
  (let ((unlabelled (remove-if-not (lambda (section)
                                     (let ((id (model:node-field-value section :id)))
                                       (and (find #\/ id)
                                            (every #'digit-char-p
                                                   (subseq id (1+ (position #\/ id :from-end t)))))))
                                   (whole-spec-all :section))))
    (is = *whole-spec-unlabelled-sections* (length unlabelled))
    (true (every (lambda (section) (model:node-field-value section :number)) unlabelled))))

;;; Snapshots: each job's model printed and hashed

(defun whole-spec-snapshot (job nodes)
  "(JOB count hash): the number of nodes of NODES at any depth and the
FNV-1a hash of their S-expressions (NODE-SEXP, full spans) printed one
per line."
  (let ((count 0) (hash #xcbf29ce484222325))
    (model:walk-nodes (lambda (node) (declare (ignore node)) (incf count)) nodes)
    (with-standard-io-syntax
      (let ((*print-readably* nil) (*print-pretty* nil))
        (dolist (node nodes)
          (setf hash (fnv-1a (prin1-to-string (if (stringp node) node (model:node-sexp node)))
                             hash)
                hash (fnv-1a (string #\Newline) hash)))))
    (list job count (format nil "~16,'0X" hash))))

(defun model-snapshot-pathname ()
  "The file of the model snapshots, tests/model-snapshots.sexp."
  (asdf:system-relative-pathname "cl-ansi-spec" "tests/model-snapshots.sexp"))

(defun current-model-snapshots ()
  "Each job's model snapshot, from this run."
  (mapcar (lambda (job) (whole-spec-snapshot (car job) (cdr job)))
          (whole-spec-jobs (whole-spec-build))))

(defun read-model-snapshots ()
  "The model snapshots kept in the file, or NIL when there is none."
  (let ((pathname (model-snapshot-pathname)))
    (and (probe-file pathname)
         (with-open-file (in pathname)
           (with-standard-io-syntax
             (let ((*read-eval* nil)) (read in)))))))

(defun write-model-snapshots ()
  "Rewrite the model snapshot file from this run (`make snapshots'),
printing each job whose model changed, with its old and new node counts."
  (let ((old (read-model-snapshots))
        (new (current-model-snapshots)))
    (dolist (snapshot new)
      (let ((before (assoc (first snapshot) old :test #'string=)))
        (unless (equal before snapshot)
          (format t "~A: ~:[new~;~:*~D nodes~] -> ~D nodes~%"
                  (first snapshot) (second before) (second snapshot)))))
    (uiop:with-staging-pathname (staging (model-snapshot-pathname))
      (with-open-file (out staging :direction :output :if-exists :supersede)
        (with-standard-io-syntax
          (let ((*print-readably* nil))
            (format out ";;;; tests/model-snapshots.sexp~%;;;;~%;;;; Each chapter job's ~
node count and the FNV-1a hash of its model printed~%;;;; ~
(tests/model/whole-spec.lisp).  Written by `make snapshots';~%;;;; ~
regenerate it in the commit that changes the model.~%~%(")
            (format out "~{~S~^~% ~})~%" new)))))
    new))

(define-test whole-spec-snapshots
  :parent whole-spec
  ;; The model of every job is the one kept.
  (let ((kept (read-model-snapshots)))
    (dolist (snapshot (current-model-snapshots))
      (is equal (assoc (first snapshot) kept :test #'string=) snapshot
          "the model of ~A changed: if meant, run make snapshots" (first snapshot)))))
