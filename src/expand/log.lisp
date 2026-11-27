;;;; src/expand/log.lisp
;;;;
;;;; What a job prints and what it emits.  TeX prints \message,
;;;; \errmessage, \show, \showthe and the \write's that go to no open file
;;;; on the terminal and in the log; here each is a LOG-ENTRY in the job's
;;;; log (JOB-LOG), nothing is printed.  The writes and the opening and
;;;; closing of write streams become nodes (nodes.lisp), so events of the
;;;; job (JOB-EVENTS); nothing is written to disk.  Each entry, like each
;;;; node, is also signalled as a JOB-OUTPUT, so that an observer (`make
;;;; expand') sees it in order among the other conditions of the job.

(in-package #:cl-ansi-spec/expand)

(defstruct (log-entry (:constructor make-log-entry (kind text &key stream help span))
                      (:copier nil))
  "One thing the job printed.  KIND is :MESSAGE (\\message), :ERRMESSAGE
(\\errmessage, whose HELP is the text of \\errhelp, or NIL when it is
empty: TeX's fixed help texts are not kept), :SHOW
(\\show and \\showthe, which TeX reports as errors; here they are only
logged)
or :WRITE (an \\immediate\\write to no open file, STREAM being its
number: 17 for a negative one, which goes to the log only, else to the
terminal and the log).  TEXT is what TeX prints, as one string: for
:SHOW, what follows `> ', without the error's final `.'.  SPAN is the
span of the command's token."
  (kind nil :type (member :message :errmessage :show :write) :read-only t)
  (text "" :type string :read-only t)
  (stream nil :type (or null integer) :read-only t)
  (help nil :type (or null string) :read-only t)
  (span nil :read-only t))

(define-condition job-output (condition)
  ((item :initarg :item :reader job-output-item
         :documentation "A LOG-ENTRY or a NODE."))
  (:report (lambda (condition stream)
             (format stream "Job output ~S" (job-output-item condition))))
  (:documentation "Signalled for every entry of the job's log and every
node appended to a list, as it is made (a :TEXT node for each character
appended to it).  Nothing needs to handle it."))

(defun log-message (expander kind text &rest keys &key stream help span)
  "Add an entry of KIND with TEXT (see LOG-ENTRY) to EXPANDER's log."
  (declare (ignore stream help span))
  (let ((entry (apply #'make-log-entry kind text keys)))
    (push entry (expander-log expander))
    (signal 'job-output :item entry)
    entry))

(defun emit-event (expander event)
  "Make EVENT, a list (KIND . PROPERTIES) as docs/events.md describes it,
a node: of the outer vertical list when it was carried out at once
(:IMMEDIATE), else of the current list, as TeX's whatsits."
  (destructuring-bind (kind &rest properties) event
    (append-node expander
                 (make-node kind :properties (loop for (key value) on properties by #'cddr
                                                   unless (eq key :span)
                                                     append (list key value))
                                 :span (getf properties :span))
                 :list (if (getf properties :immediate)
                           (outer-list expander)
                           (current-list expander)))))

(defun job-log (expander)
  "The entries of EXPANDER's log, oldest first."
  (reverse (expander-log expander)))
