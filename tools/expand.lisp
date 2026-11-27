;;;; tools/expand.lisp
;;;;
;;;; Run a spec file as a TeX job through main control.  Two views of the
;;;; lines LINES (the output produced while the file itself is read
;;;; within them; the job stops at the first output after the last one):
;;;;
;;;; `make expand' prints, in order, the nodes appended to lists other
;;;; than text and spaces: FILE:LINE:COLUMN<tab>== kind, then its
;;;; properties (a composite node, a paragraph or a box, when it is
;;;; complete), where the location is where its command was read (a
;;;; macro body's token points into its definition); TeX
;;;; errors as `!! message context' (recovered from as TeX does; a fatal
;;;; error ends the run); what TeX only notes (an \end inside a group) as
;;;; `-- (note)'; what the job prints (\message, \show, ...) as
;;;; `>> kind[ stream]: text'.
;;;;
;;;; `make events' prints the events of the nodes appended within LINES
;;;; (a composite node is appended where it ends: a paragraph ended there
;;;; is shown whole, one begun there shows the nodes appended in LINES),
;;;; flattened as docs/events.md says, once the job stops:
;;;; FILE:LINE:COLUMN<tab>EVENT, nested events indented, long texts cut.
;;;; The lists still open then (a paragraph not ended) are shown last,
;;;; each after a `-- open <mode> list' line.  Errors and notes are
;;;; printed as they happen, as for `make expand'.
;;;;
;;;; The job starts from plain TeX's format (LOAD-PLAIN-FORMAT), as every
;;;; chapter job does.
;;;;
;;;; Usage: make expand FILE=chap-1 [LINES=10-20]
;;;;        make events FILE=chap-1 [LINES=10-20]

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

(defparameter *text-limit* 60
  "The longest text `make events' shows of a :TEXT event.")

(defun show-value (expander key value)
  "VALUE of the property KEY as the tools show it."
  (case key
    (:tokens (cl-ansi-spec/expand:token-list-text expander value))
    (:via (mapcar #'span-location value))
    (t value)))

(defun event-head-length (event)
  "How many elements of EVENT come before its properties."
  (if (member (first event) '(:begin :end :text)) 2 1))

(defun show-event (expander event)
  "EVENT (a list) without its :SPAN, as one line of text."
  (let* ((head (event-head-length event))
         (fixed (subseq event 0 head)))
    (when (and (eq (first event) :text) (> (length (second event)) *text-limit*))
      (setf fixed (list :text (concatenate 'string (subseq (second event) 0 *text-limit*)
                                           "…"))))
    (let ((*print-case* :downcase))
      (format nil "(~{~S~^ ~}~{ ~S ~S~})" fixed
              (loop for (key value) on (nthcdr head event) by #'cddr
                    unless (eq key :span)
                      append (list key (show-value expander key value)))))))

(defun print-events (expander nodes depth shown)
  "Print the events of NODES (oldest first) at DEPTH; only the nodes in
the table SHOWN and everything inside them, unless SHOWN is T."
  (dolist (node nodes)
    (let ((all (or (eq shown t) (gethash node shown))))
      (if all
          (let ((events (cl-ansi-spec/expand:flatten-nodes (list node)))
                (level depth))
            (dolist (event events)
              (when (eq (first event) :end) (decf level))
              (format t "~A~C~A~A~%"
                      (span-location (getf (nthcdr (event-head-length event) event) :span))
                      #\Tab (make-string (* 2 level) :initial-element #\Space)
                      (show-event expander event))
              (when (eq (first event) :begin) (incf level))))
          (when (cl-ansi-spec/expand:node-composite node)
            (print-events expander (cl-ansi-spec/expand:node-children node)
                          depth shown))))))

(defun print-open-lists (expander shown)
  "Print the events of every list of EXPANDER's nest, outermost first."
  (let ((nest (reverse (cl-ansi-spec/expand:expander-nest expander))))
    (print-events expander (cl-ansi-spec/expand:list-nodes (first nest)) 0 shown)
    (dolist (list (rest nest))
      (format t "-- open ~(~A~) list~%" (cl-ansi-spec/expand:list-state-mode list))
      (print-events expander (cl-ansi-spec/expand:list-nodes list) 1 shown))))

(defun expand-file (name &key lines events)
  "Run the job NAME and print what happens within LINES: the nodes
appended (EVENTS false), or the events (EVENTS true)."
  (destructuring-bind (first last) (parse-line-range lines)
    (let* ((expander (cl-ansi-spec/expand:make-job
                      (cl-ansi-spec/expand:load-plain-format)
                      :job-name (pathname-name name)))
           (in-range (= first 1))
           (shown (make-hash-table :test 'eq))
           (file nil))
      (cl-ansi-spec/expand:start-job expander name)
      (setf file (cl-ansi-spec/tex:current-file-name
                  (cl-ansi-spec/expand:expander-input expander)))
      (block job
        (labels ((locate (span)
                   ;; Update IN-RANGE from SPAN; stop the job when past LINES.
                   (when (and span (string= (cl-ansi-spec/tex:span-file span) file))
                     (let ((line (cl-ansi-spec/tex:span-line span)))
                       (when (and last (> line last))
                         (return-from job))
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
                 (log-entry (item)
                   (let ((span (cl-ansi-spec/expand:log-entry-span item)))
                     (locate span)
                     (when in-range
                       (format t ">> ~(~A~)~@[ ~D~]: ~A~%"
                               (cl-ansi-spec/expand:log-entry-kind item)
                               (cl-ansi-spec/expand:log-entry-stream item)
                               (cl-ansi-spec/expand:log-entry-text item)))))
                 (node (item)
                   ;; A composite node is appended when it ends.
                   (let ((span (if (cl-ansi-spec/expand:node-composite item)
                                   (or (cl-ansi-spec/expand:node-end-span item)
                                       (cl-ansi-spec/expand:node-span item))
                                   (cl-ansi-spec/expand:node-span item))))
                     (locate span)
                     (when in-range
                       (if events
                           (setf (gethash item shown) t)
                           (unless (member (cl-ansi-spec/expand:node-kind item)
                                           '(:text :space))
                             (format t "~A~C== ~A~%" (span-location span) #\Tab
                                     (show-event expander
                                                 (first (cl-ansi-spec/expand:flatten-nodes
                                                         (list item))))))))))
                 (output (condition)
                   (let ((item (cl-ansi-spec/expand:job-output-item condition)))
                     (if (cl-ansi-spec/expand:log-entry-p item)
                         (log-entry item)
                         (node item)))))
          (handler-case
              (handler-bind ((cl-ansi-spec/expand:job-output #'output)
                             (cl-ansi-spec/expand:tex-report
                               (lambda (condition) (format t "-- ~A~%" condition))))
                (cl-ansi-spec/expand:call-recovering-tex-errors
                 (lambda () (cl-ansi-spec/expand:main-control expander))
                 #'report))
            (cl-ansi-spec/expand:tex-fatal-error (condition)
              (format t "!! fatal: ~A~@[ ~A~]~%"
                      (cl-ansi-spec/expand:tex-error-message condition)
                      (cl-ansi-spec/expand:tex-error-context condition))))))
      (when events
        (print-open-lists expander shown)))
    t))

(with-exit-status
  (let ((name (uiop:getenv "FILE"))
        (lines (uiop:getenv "LINES"))
        (events (equal (uiop:getenv "EVENTS") "1")))
    (unless (and name (string/= name ""))
      (error "Usage: make ~:[expand~;events~] FILE=<spec file> [LINES=a-b]" events))
    (expand-file name :lines lines :events events)))
