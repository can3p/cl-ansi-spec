;;;; src/expand/streams.lisp
;;;;
;;;; TeX's input and output streams (TeX: The Program, §§480-486, 1225,
;;;; 1275, 1340-1375).  \openin finds its file through the input stack's
;;;; resolver, as \input does; \read reads it a line at a time, with the
;;;; category codes in force (read_toks).  A job has no terminal: a \read
;;;; from it is TeX's fatal error in its nonstop modes.
;;;;
;;;; \openout, \write and \closeout make whatsits: here events
;;;; (docs/events.md) carrying the file name or the token list as scanned.
;;;; TeX carries them out when their page is shipped out, so a \write's
;;;; tokens stay unexpanded.  After \immediate they are carried
;;;; out at once (out_what): a write stream is opened or closed (nothing
;;;; is written to disk), and the text of a \write is expanded (write_out)
;;;; and is an event when its stream is open, an entry of the job's log
;;;; otherwise.

(in-package #:cl-ansi-spec/expand)

;;; \openin, \closein and \read

(defun close-read-stream (expander n)
  "Close the \\read stream N of EXPANDER (TeX's a_close)."
  (setf (aref (expander-read-streams expander) n) :closed))

(define-command ("openin" "closein") (expander token meaning)
  ;; open_or_close_in (§1275): a file that is not found leaves the stream
  ;; closed, without an error, for \ifeof to test.
  (let ((n (scan-four-bit-int expander)))
    (close-read-stream expander n)
    (when (string= name "openin")
      (scan-optional-equals expander)
      (let ((source (resolve-input (expander-input expander) (scan-file-name expander))))
        (when source
          (setf (aref (expander-read-streams expander) n) source))))))

(defun read-stream-line (expander m)
  "The tokens of the next line of the \\read stream M (16 for the
terminal), closing the stream at its end (§§484-486)."
  (let ((source (and (< m 16) (aref (expander-read-streams expander) m))))
    (when (or (null source) (eq source :closed))
      (tex-fatal-error "*** (cannot \\read from terminal in nonstop modes)"))
    (multiple-value-bind (tokens end-of-file)
        (read-line-tokens source (expander-tex expander))
      (when end-of-file
        (close-read-stream expander m)
        (unless (= (expander-align-state expander) 1000000)
          (setf (expander-align-state expander) 1000000)
          (tex-error "File ended within" :context (esc expander "read"))))
      tokens)))

(defun read-line-into (expander tokens)
  "Read the line just pushed onto EXPANDER's input, without expansion,
pushing its tokens onto TOKENS, up to its end or to a right brace that
ends more groups than were begun (§483): the rest of the line is then
skipped.  Returns the new TOKENS."
  (loop
    (let ((token (get-token expander)))
      (unless token
        (return tokens))
      (when (< (expander-align-state expander) 1000000)
        (loop while (get-token expander))
        (setf (expander-align-state expander) 1000000)
        (return tokens))
      (push token tokens))))

(defun read-toks (expander n cs)
  "TeX's read_toks (§482): read from the \\read stream N, for CS, whole
lines until their braces balance; return the macro without parameters
whose body they are."
  (let ((input (expander-input expander))
        (m (if (<= 0 n 15) n 16))
        (saved-status (expander-scanner-status expander))
        (saved-warning (expander-warning-index expander))
        (saved-align (expander-align-state expander))
        (tokens '()))
    (setf (expander-scanner-status expander) :defining
          (expander-warning-index expander) cs
          (expander-align-state expander) 1000000)
    (unwind-protect
         (loop
           (push-read-line input (read-stream-line expander m))
           (setf tokens (read-line-into expander tokens))
           (end-read-line input)
           (when (= (expander-align-state expander) 1000000)
             (return)))
      (setf (expander-scanner-status expander) saved-status
            (expander-warning-index expander) saved-warning
            (expander-align-state expander) saved-align))
    (make-macro '() (nreverse tokens))))

(define-assignment "read" (expander token meaning global)
  ;; read_to_cs (§1225)
  (let ((n (scan-int expander)))
    (unless (scan-keyword expander "to")
      (tex-error "Missing `to' inserted" :span (token-span token)))
    (let ((cs (get-r-token expander)))
      (set-meaning (expander-state expander) cs (read-toks expander n cs)
                   :global global))))

;;; \openout, \write, \closeout and \immediate

(defun scan-write-stream (expander name)
  "The stream number of the whatsit NAME (§1350): 0-15 for \\openout; for
\\write and \\closeout any integer, with 17 for a negative one and 16
for one above 15."
  (if (string= name "openout")
      (scan-four-bit-int expander)
      (let ((n (scan-int expander)))
        (cond ((minusp n) 17)
              ((> n 15) 16)
              (t n)))))

(defun end-write-control-sequence (expander)
  "TeX's frozen \\endwrite (§1369): an \\outer macro, so that a \\write
text with more left braces than right ones is a runaway."
  (let ((table (expander-frozen expander)))
    (or (gethash "endwrite" table)
        (let ((cs (make-frozen-control-sequence "endwrite")))
          (set-meaning (expander-state expander) cs
                       (make-macro '() '() :outer-p t) :global t)
          (setf (gethash "endwrite" table) cs)))))

(defun expand-write-text (expander tokens span)
  "TeX's write_out (§1370), the expansion: TOKENS in braces, then
\\endwrite, expanded as for \\edef with the mode :NONE and \\setbox not
allowed.  Returns the expanded tokens."
  (let* ((end-write (end-write-control-sequence expander))
         (list (current-list expander))
         (old-mode (list-state-mode list))
         (old-allowed (expander-set-box-allowed expander)))
    (flet ((end-write-p (token)
             (or (null token)
                 (and (cs-token-p token)
                      (eq (cs-token-control-sequence token) end-write)))))
      (insert-tokens expander (list (make-character-token (char-code #\}) +end-group+ span)
                                    (make-cs-token end-write span)))
      (push-tokens (expander-input expander) tokens :write-text)
      (insert-tokens expander (list (make-character-token (char-code #\{) +begin-group+ span)))
      (setf (list-state-mode list) :none
            (expander-set-box-allowed expander) nil)
      (unwind-protect
           (let ((expanded (scan-toks expander :xpand t
                                               :warning-index (intern-control-sequence
                                                               (expander-tex expander)
                                                               "write"))))
             (unless (end-write-p (get-token expander))
               (tex-error "Unbalanced write command" :span span)
               (loop until (end-write-p (get-token expander))))
             expanded)
        (setf (list-state-mode list) old-mode
              (expander-set-box-allowed expander) old-allowed)))))

(defun write-out (expander stream tokens span)
  "Carry out a \\write to STREAM of TOKENS now (§1370): an event when
the stream is open, else an entry of the job's log."
  (let* ((expanded (expand-write-text expander tokens span))
         (text (token-list-text expander expanded)))
    (if (and (< stream 16) (aref (expander-write-streams expander) stream))
        (emit-event expander (list :write :stream stream :tokens expanded
                                          :text text :immediate t :span span))
        (log-message expander :write text :stream stream :span span))))

(defun out-what (expander name stream argument span)
  "TeX's out_what (§1373) for the whatsit NAME on STREAM, with the file
name or token list ARGUMENT: what \\immediate carries out at once."
  (if (string= name "write")
      (write-out expander stream argument span)
      (when (< stream 16)
        (setf (aref (expander-write-streams expander) stream)
              (and (string= name "openout") argument))
        (emit-event expander
                    (if (string= name "openout")
                        (list :openout :stream stream :file argument :immediate t
                                       :span span)
                        (list :closeout :stream stream :immediate t :span span))))))

(defun do-extension (expander token name immediate)
  "TeX's do_extension (§1348) for \\openout, \\write or \\closeout NAME,
read from TOKEN: scan the whatsit, then carry it out at once when
IMMEDIATE, else make it an event of the current list."
  (let* ((stream (scan-write-stream expander name))
         (span (token-span token))
         (argument (cond ((string= name "openout")
                          (scan-optional-equals expander)
                          (scan-file-name expander))
                         ((string= name "write")
                          (scan-toks expander
                                     :warning-index (cs-token-control-sequence token))))))
    (if immediate
        (out-what expander name stream argument span)
        (progn
          (emit-event expander
                      (cond ((string= name "openout")
                             (list :openout :stream stream :file argument :span span))
                            ((string= name "write")
                             (list :write :stream stream :tokens argument :span span))
                            (t (list :closeout :stream stream :span span))))))))

(define-command ("openout" "write" "closeout") (expander token meaning)
  (do-extension expander token name nil))

(define-command "immediate" (expander token meaning)
  ;; §1375: anything but \openout, \write or \closeout is read again.
  (multiple-value-bind (next next-meaning) (get-x-token expander)
    (let ((name (and (primitive-p next-meaning) (primitive-name next-meaning))))
      (if (member name '("openout" "write" "closeout") :test #'equal)
          (do-extension expander next name t)
          (back-token expander next)))))
