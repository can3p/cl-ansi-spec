;;;; tools/expand.lisp
;;;;
;;;; Run a spec file as a TeX job through the expander and print the
;;;; unexpandable tokens it yields (get_x_token), one per line:
;;;; FILE:LINE:COLUMN<tab>TOKEN, where the location is where the token was
;;;; read (a macro body's token points into its definition).  TeX errors
;;;; are printed as `!! message context' and recovered from as TeX does;
;;;; a fatal error ends the run.
;;;;
;;;; The job starts from INITEX with plain TeX's category codes.  Only the
;;;; output produced while the file itself is read within LINES is shown;
;;;; the job stops after the last of those lines.
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
  "Run the job NAME and print its expanded tokens within LINES."
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
      (flet ((report (condition)
               (when in-range
                 (format t "!! ~A~@[ ~A~]~@[ at ~A~]~%"
                         (cl-ansi-spec/expand:tex-error-message condition)
                         (cl-ansi-spec/expand:tex-error-context condition)
                         (let ((span (cl-ansi-spec/expand:tex-error-span condition)))
                           (and span (span-location span)))))))
        (handler-case
            (cl-ansi-spec/expand:call-recovering-tex-errors
             (lambda ()
               (loop for token = (cl-ansi-spec/expand:get-x-token expander)
                     while token
                     do (let ((span (cl-ansi-spec/tex:token-span token)))
                          (when (and span (string= (cl-ansi-spec/tex:span-file span) file))
                            (let ((line (cl-ansi-spec/tex:span-line span)))
                              (when (and last (> line last))
                                (return))
                              (setf in-range (and (>= line first)
                                                  (or (null last) (<= line last))))))
                          (when in-range
                            (format t "~A~C~A~%" (span-location span) #\Tab
                                    (cl-ansi-spec/tex:token-text token))))))
             #'report)
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
