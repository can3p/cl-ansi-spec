;;;; tools/expand.lisp
;;;;
;;;; Run a spec file as a TeX job through main control and print what
;;;; it hands on to the steps that have not landed (events, alignments,
;;;; input and output), one per line: FILE:LINE:COLUMN<tab>TOKEN<tab>MODE,
;;;; where the location is where the token was read (a macro body's token
;;;; points into its definition).  Assignments, groups and mode changes
;;;; are carried out silently.  TeX errors are printed as `!! message
;;;; context' and recovered from as TeX does; a fatal error ends the run.
;;;; What TeX only notes (an \end inside a group) is printed as `-- (note)'.
;;;;
;;;; The job starts from INITEX with plain TeX's category codes.  Only the
;;;; output produced while the file itself is read within LINES is shown;
;;;; the job stops at the first output after the last of those lines.
;;;;
;;;; Usage: make expand FILE=chap-1 [LINES=10-20]

(load (merge-pathnames "setup.lisp" *load-truename*))

(in-package #:cl-ansi-spec.tools)

(configure-asdf)
;; Keep the dump free of compiler chatter; warnings still reach stderr.
(let ((*standard-output* (make-broadcast-stream)))
  (asdf:load-system "cl-ansi-spec"))

(defun span-location (span)
  "FILE:LINE:COLUMN of SPAN, or - for a token that was not read."
  (if span
      (format nil "~A:~D:~D" (cl-ansi-spec/tex:span-file span)
              (cl-ansi-spec/tex:span-line span) (cl-ansi-spec/tex:span-column span))
      "-"))

(defun expand-file (name &key lines)
  "Run the job NAME and print what main control hands on within LINES."
  (destructuring-bind (first last) (parse-line-range lines)
    (let* ((state (cl-ansi-spec/expand:make-expander-state
                   :tex (cl-ansi-spec/tex:make-plain-state)))
           (expander (cl-ansi-spec/expand:make-expander
                      :state state :job-name (pathname-name name)))
           (in-range (= first 1))
           (file nil))
      (cl-ansi-spec/tex:push-file (cl-ansi-spec/expand:expander-input expander) name)
      (setf file (cl-ansi-spec/tex:current-file-name
                  (cl-ansi-spec/expand:expander-input expander)))
      (labels ((locate (span)
                 ;; Update IN-RANGE from SPAN; true when past LINES.
                 (when (and span (string= (cl-ansi-spec/tex:span-file span) file))
                   (let ((line (cl-ansi-spec/tex:span-line span)))
                     (when (and last (> line last))
                       (return-from expand-file t))
                     (setf in-range (and (>= line first)
                                         (or (null last) (<= line last)))))))
               (report (condition)
                 (let ((span (cl-ansi-spec/expand:tex-error-span condition)))
                   (locate span)
                   (when in-range
                     (format t "!! ~A~@[ ~A~]~@[ at ~A~]~%"
                             (cl-ansi-spec/expand:tex-error-message condition)
                             (cl-ansi-spec/expand:tex-error-context condition)
                             (and span (span-location span))))))
               (hand-on (condition)
                 (let* ((token (cl-ansi-spec/expand:unhandled-command-token condition))
                        (span (cl-ansi-spec/tex:token-span token)))
                   (locate span)
                   (when in-range
                     (format t "~A~C~A~C~(~A~)~%" (span-location span) #\Tab
                             (cl-ansi-spec/tex:token-text token) #\Tab
                             (cl-ansi-spec/expand:unhandled-command-mode condition))))))
        (handler-case
            (handler-bind ((cl-ansi-spec/expand:unhandled-command #'hand-on)
                           (cl-ansi-spec/expand:tex-report
                             (lambda (condition) (format t "-- ~A~%" condition))))
              (cl-ansi-spec/expand:call-recovering-tex-errors
               (lambda () (cl-ansi-spec/expand:main-control expander))
               #'report))
          (cl-ansi-spec/expand:tex-fatal-error (condition)
            (format t "!! fatal: ~A~@[ ~A~]~%"
                    (cl-ansi-spec/expand:tex-error-message condition)
                    (cl-ansi-spec/expand:tex-error-context condition))))))
    t))

(with-exit-status
  (let ((name (uiop:getenv "FILE"))
        (lines (uiop:getenv "LINES")))
    (unless (and name (string/= name ""))
      (error "Usage: make expand FILE=<spec file> [LINES=a-b]"))
    (expand-file name :lines lines)))
