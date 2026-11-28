;;;; tools/model.lisp
;;;;
;;;; Print the model built from a spec file's lines (BUILD-FIXTURE,
;;;; src/model/build.lisp): the top-level nodes, one S-expression each,
;;;; spans shortened to (file line), then the build report: the events no
;;;; handler took, by type and key with their count and first location,
;;;; then every other problem, `-- kind at FILE:LINE:COL message'.
;;;;
;;;; FILE is a spec file; the job that reads it is FILE itself when it is
;;;; a chapter job, else JOB, else the first chapter job whose survey
;;;; (cl-ansi-spec/inventory) reads it.
;;;;
;;;; Usage: make model FILE=chap-1 [LINES=10-20] [JOB=chap-14]

(load (merge-pathnames "setup.lisp" *load-truename*))

(in-package #:cl-ansi-spec.tools)

(configure-asdf)
;; Keep the output free of compiler chatter; warnings still reach stderr.
(let ((*standard-output* (make-broadcast-stream)))
  (asdf:load-system "cl-ansi-spec"))

(defun location (span)
  "FILE:LINE:COLUMN of SPAN, or - without one."
  (if span
      (format nil "~A:~D:~D" (cl-ansi-spec/tex:span-file span)
              (cl-ansi-spec/tex:span-line span) (cl-ansi-spec/tex:span-column span))
      "-"))

(defun job-of-file (file)
  "The chapter job that reads FILE (a name with its type)."
  (or (find-if (lambda (job)
                 (member file (cl-ansi-spec/inventory:survey-files
                               (cl-ansi-spec/inventory:survey-job job))
                         :test #'string=))
               (cl-ansi-spec:chapter-jobs))
      (error "No chapter job reads ~A." file)))

(defun print-report (report)
  "Print REPORT's unhandled events by type and key, then its other
problems."
  (let ((unhandled '()))
    (dolist (problem (cl-ansi-spec/model:build-report-problems report))
      (let ((event (cl-ansi-spec/model:problem-event problem)))
        (if (eq (cl-ansi-spec/model:problem-kind problem) :unhandled)
            (let* ((key (list (cl-ansi-spec/model:event-type event)
                              (cl-ansi-spec/model:event-key event)))
                   (cell (assoc key unhandled :test #'equal)))
              (if cell
                  (incf (second cell))
                  (push (list key 1 (cl-ansi-spec/model:problem-span problem)) unhandled)))
            (format t "-- ~(~A~) at ~A~@[ ~A~]~@[ ~(~S~)~]~%"
                    (cl-ansi-spec/model:problem-kind problem)
                    (location (cl-ansi-spec/model:problem-span problem))
                    (cl-ansi-spec/model:problem-message problem)
                    (and (null (cl-ansi-spec/model:problem-message problem)) event)))))
    (loop for ((type key) count span) in (reverse unhandled)
          do (format t "-- unhandled (~(~S~@[ ~S~]~)) ×~D, first at ~A~%"
                     type key count (location span)))))

(with-exit-status
  (let* ((name (uiop:getenv "FILE"))
         (job (uiop:getenv "JOB"))
         (file (format nil "~A.tex" name)))
    (unless (and name (string/= name ""))
      (error "Usage: make model FILE=<spec file> [LINES=a-b] [JOB=<chapter job>]"))
    (multiple-value-bind (nodes report)
        (cl-ansi-spec/model:build-fixture
         (cond ((and job (string/= job "")) job)
               ((member name (cl-ansi-spec:chapter-jobs) :test #'string=) name)
               (t (job-of-file file)))
         :file file :lines (parse-line-range (uiop:getenv "LINES")))
      (dolist (node nodes)
        (cl-ansi-spec/model:print-node node :spans :line))
      (print-report report))
    t))
