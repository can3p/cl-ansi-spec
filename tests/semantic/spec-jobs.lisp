;;;; tests/semantic/spec-jobs.lisp
;;;;
;;;; The whole spec: every chapter job runs from plain TeX's format,
;;;; observing the spec's vocabulary, once per test run; its errors and
;;;; reports are checked here.

(in-package #:cl-ansi-spec/tests)

(define-test spec-jobs
  :parent semantic
  :description "Every chapter job of the spec, observing the vocabulary.")

(defstruct (spec-run (:constructor make-spec-run
                         (job errors fatal reports balance calls count hash)))
  "What running the chapter job JOB gave: its ERRORS, (message file line)
in order, the message of a FATAL error or NIL, the REPORTS of its
observer, BALANCE, an alist from each vocabulary key to its :BEGIN
events minus its :END events, CALLS, an alist from each entry's name to
the calls of it observed, and the COUNT of its events and their HASH
(SNAPSHOT-HASH)."
  job errors fatal reports balance calls count hash)

(defvar *spec-runs* nil
  "The runs of every chapter job, made once per test run.")

;;; Snapshots: a job's events printed canonically and hashed

(defun span-text (span)
  "SPAN as FILE:LINE:COL."
  (format nil "~A:~D:~D" (span-file span) (span-line span) (span-column span)))

(defun canonical-event (expander event)
  "EVENT as a snapshot prints it: token lists as text (STRIP-SEMANTIC-EVENT),
its span and its :VIA spans as FILE:LINE:COL."
  (let* ((properties (nthcdr (if (member (first event) '(:begin :end :mark :text)) 2 1)
                             event))
         (span (getf properties :span))
         (via (getf properties :via)))
    (append (strip-semantic-event expander event nil)
            (and span (list :span (span-text span)))
            (and via (list :via (mapcar #'span-text via))))))

(defun fnv-1a (string &optional (hash #xcbf29ce484222325))
  "The 64-bit FNV-1a hash of the character codes of STRING, continuing
from HASH."
  (loop for char across string
        do (setf hash (ldb (byte 64 0)
                           (* (logxor hash (char-code char)) #x100000001b3))))
  hash)

(defun snapshot-hash (expander events)
  "The hash of EVENTS, EXPANDER's, each printed canonically on a line,
as a hexadecimal string.  Canonical events hold only keywords, strings,
integers and lists of them, so the printer variables bound here fix
their text."
  (let ((hash #xcbf29ce484222325))
    (with-standard-io-syntax
      (let ((*print-readably* nil) (*print-pretty* nil))
        (dolist (event events)
          (setf hash (fnv-1a (prin1-to-string (canonical-event expander event)) hash)
                hash (fnv-1a (string #\Newline) hash)))))
    (format nil "~16,'0X" hash)))

;;; Running the jobs

(defun key-balance (vocabulary events)
  "An alist from each key of VOCABULARY's entries met in EVENTS to its
:BEGIN events minus its :END events."
  (let ((keys (mapcar #'semantic:entry-key (semantic:vocabulary-entries vocabulary)))
        (balance '()))
    (dolist (event events)
      (when (and (member (first event) '(:begin :end)) (member (second event) keys))
        (let ((cell (or (assoc (second event) balance)
                        (first (push (cons (second event) 0) balance)))))
          (if (eq (first event) :begin) (incf (cdr cell)) (decf (cdr cell))))))
    (sort balance #'string< :key #'car)))

(defun run-spec-job (job)
  "Run the chapter job JOB as `make events' does, observing the spec's
vocabulary; return its SPEC-RUN."
  (let* ((vocabulary (semantic:spec-vocabulary))
         (expander (expand:make-job (plain-format) :job-name job))
         (observer (semantic:observe-vocabulary expander vocabulary))
         (errors '())
         (fatal nil))
    (expand:start-job expander job)
    (handler-case
        (handler-bind ((expand:job-output (lambda (condition) (declare (ignore condition))))
                       (expand:tex-report (lambda (condition) (declare (ignore condition)))))
          (expand:call-recovering-tex-errors
           (lambda () (expand:main-control expander))
           (lambda (condition)
             (let ((span (expand:tex-error-span condition)))
               (push (list (expand:tex-error-message condition)
                           (and span (span-file span))
                           (and span (span-line span)))
                     errors)))))
      (expand:tex-fatal-error (condition)
        (setf fatal (expand:tex-error-message condition))))
    (let ((events (expand:job-events expander)))
      (make-spec-run job (nreverse errors) fatal (semantic:observer-reports observer)
                     (key-balance vocabulary events)
                     (loop for entry in (semantic:vocabulary-entries vocabulary)
                           for name = (semantic:entry-name entry)
                           collect (cons name (semantic:observer-call-count observer name)))
                     (length events)
                     (snapshot-hash expander events)))))

(defun spec-runs ()
  "The SPEC-RUNs of every chapter job."
  (or *spec-runs*
      (setf *spec-runs* (mapcar #'run-spec-job (cl-ansi-spec:chapter-jobs)))))

(define-test spec-jobs-run
  :parent spec-jobs
  ;; No job stops, and none has a TeX error.
  (dolist (run (spec-runs))
    (false (spec-run-fatal run) "~A stops: ~A" (spec-run-job run) (spec-run-fatal run))
    (is equal '() (spec-run-errors run) "errors of ~A" (spec-run-job run))))

(defparameter *expected-reports* '()
  "The reports of the whole spec besides *SETUP-REDEFINITIONS*: (job kind
name why); none now that the sources' unbalanced groups are patched.")

(define-test spec-jobs-reports
  :parent spec-jobs
  ;; Every job reports the setup files' redefinitions, and only the
  ;; reports listed besides.
  (dolist (run (spec-runs))
    (is equal (append *setup-redefinitions*
                      (loop for (job kind name) in *expected-reports*
                            when (string= job (spec-run-job run))
                              collect (list kind name)))
        (mapcar (lambda (report)
                  (list (semantic:report-kind report) (semantic:report-name report)))
                (spec-run-reports run))
        "reports of ~A" (spec-run-job run))))

;;; Invariants

(defparameter *expected-imbalance* '()
  "Keys whose :BEGIN and :END events differ in a job because the sources
leave something open: (job key difference why); none now that the sources'
unclosed groups are patched.")

(define-test spec-jobs-balance
  :parent spec-jobs
  ;; Each key has as many :END events as :BEGIN events in every job (a
  ;; :CLOSE entry's call is the :END of the key it closes).
  (dolist (run (spec-runs))
    (is equal (loop for (job key difference) in *expected-imbalance*
                    when (string= job (spec-run-job run)) collect (cons key difference))
        (remove 0 (spec-run-balance run) :key #'cdr)
        "unbalanced keys of ~A" (spec-run-job run))))

(defparameter *call-exceptions*
  '(("chap-4" "keyref" "dict-types.tex:858: inside a \\reviewer note, whose
body the options skip")
    ("chap-19" "f" "dict-pathnames.tex:690-691: inside a \\reviewer note,
whose body the options skip"))
  "Entries called fewer times in a job than the survey counts certain
text uses of them: (job name why).")

(defun certain-text-uses (survey name)
  "How many times SURVEY's job uses NAME as text on a certain line."
  (count-if (lambda (occurrence)
              (and (string= (cl-ansi-spec/inventory:occurrence-name occurrence) name)
                   (eq (cl-ansi-spec/inventory:occurrence-context occurrence) :text)
                   (not (cl-ansi-spec/inventory:occurrence-uncertain-p occurrence))))
            (cl-ansi-spec/inventory:survey-occurrences survey)))

(define-test spec-jobs-calls
  :parent spec-jobs
  ;; Each entry is called at least as often as the survey sees it used
  ;; in text (more: macros call it too), but for the exceptions listed.
  (dolist (run (spec-runs))
    (let ((survey (cl-ansi-spec/inventory:survey-job (spec-run-job run)))
          (short '()))
      (loop for (name . calls) in (spec-run-calls run)
            for uses = (certain-text-uses survey (concatenate 'string "\\" name))
            when (< calls uses)
              do (push (list name calls uses) short))
      (is equal (loop for (job name) in *call-exceptions*
                      when (string= job (spec-run-job run)) collect name)
          (mapcar #'first (reverse short))
          "entries called less than used in ~A: ~S" (spec-run-job run) (reverse short)))))

;;; Snapshots

(defun snapshot-pathname ()
  "The file of the snapshots, tests/snapshots.sexp."
  (asdf:system-relative-pathname "cl-ansi-spec" "tests/snapshots.sexp"))

(defun current-snapshots ()
  "Each job's (job count hash), from this run."
  (mapcar (lambda (run) (list (spec-run-job run) (spec-run-count run) (spec-run-hash run)))
          (spec-runs)))

(defun read-snapshots ()
  "The snapshots kept in the file, or NIL when there is none."
  (let ((pathname (snapshot-pathname)))
    (and (probe-file pathname)
         (with-open-file (in pathname)
           (with-standard-io-syntax
             (let ((*read-eval* nil)) (read in)))))))

(defun write-snapshots ()
  "Rewrite the snapshot file from this run (`make snapshots'), printing
each job whose events changed, with its old and new event counts."
  (let ((old (read-snapshots))
        (new (current-snapshots)))
    (dolist (snapshot new)
      (let ((before (assoc (first snapshot) old :test #'string=)))
        (unless (equal before snapshot)
          (format t "~A: ~:[new~;~:*~D events~] -> ~D events~%"
                  (first snapshot) (second before) (second snapshot)))))
    (uiop:with-staging-pathname (staging (snapshot-pathname))
      (with-open-file (out staging :direction :output :if-exists :supersede)
        (with-standard-io-syntax
          (let ((*print-readably* nil))
            (format out ";;;; tests/snapshots.sexp~%;;;;~%;;;; Each chapter job's event ~
count and the FNV-1a hash of its events printed~%;;;; canonically ~
(tests/semantic/spec-jobs.lisp).  Written by `make snapshots';~%;;;; ~
regenerate it in the commit that changes the events.~%~%(")
            (format out "~{~S~^~% ~})~%" new)))))
    new))

(define-test spec-jobs-snapshots
  :parent spec-jobs
  ;; The events of every job are those kept; hashing a job again gives
  ;; the same hash.
  (let ((kept (read-snapshots)))
    (dolist (snapshot (current-snapshots))
      (is equal (assoc (first snapshot) kept :test #'string=) snapshot
          "events of ~A changed: if meant, run make snapshots" (first snapshot))))
  ;; In one image: the kept file already checks fresh images.
  (let ((run (find "chap-24" (spec-runs) :key #'spec-run-job :test #'string=))
        (again (run-spec-job "chap-24")))
    (is = (spec-run-count run) (spec-run-count again))
    (is string= (spec-run-hash run) (spec-run-hash again))))
