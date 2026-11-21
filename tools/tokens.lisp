;;;; tools/tokens.lisp
;;;;
;;;; Dump the tokens of a spec source file, one per line, for debugging the
;;;; reader:  LINE:COLUMN<tab>TOKEN, where TOKEN is a control sequence as
;;;; written, an active character, or a character followed by its category
;;;; code.  With SKIPS, the input that produces no token is listed too, as
;;;; LINE:COLUMN<tab>-- KIND.
;;;;
;;;; The file is read under plain TeX's category codes without expansion,
;;;; so category code changes made by the sources are not seen.
;;;;
;;;; Usage: make tokens FILE=chap-1 [LINES=10-20] [SKIPS=1]

(load (merge-pathnames "setup.lisp" *load-truename*))

(in-package #:cl-ansi-spec.tools)

(configure-asdf)
;; Keep the dump free of compiler chatter; warnings still reach stderr.
(let ((*standard-output* (make-broadcast-stream)))
  (asdf:load-system "cl-ansi-spec"))

(defun dump-tokens (name &key lines skips)
  "Print the tokens of the spec file NAME within the line range LINES,
and the skipped input too if SKIPS is true."
  (destructuring-bind (first last) (parse-line-range lines)
    (flet ((in-range-p (span)
             (and (>= (cl-ansi-spec/tex:span-line span) first)
                  (or (null last) (<= (cl-ansi-spec/tex:span-line span) last))))
           (location (span)
             (format nil "~D:~D" (cl-ansi-spec/tex:span-line span)
                     (cl-ansi-spec/tex:span-column span))))
      (let ((stack (cl-ansi-spec/tex:make-input-stack
                    (cl-ansi-spec/tex:make-plain-state)
                    :skip-hook (and skips
                                    (lambda (kind span)
                                      (when (in-range-p span)
                                        (format t "~A~C-- ~(~A~)~%"
                                                (location span) #\Tab kind)))))))
        (cl-ansi-spec/tex:push-file stack name)
        (handler-bind ((cl-ansi-spec/tex:invalid-character
                         (lambda (condition)
                           (format t "~A~C!! invalid ~A~%"
                                   (location (cl-ansi-spec/tex:invalid-character-span
                                              condition))
                                   #\Tab
                                   (cl-ansi-spec/tex:character-text
                                    (cl-ansi-spec/tex:invalid-character-code
                                     condition)))
                           (continue condition))))
          (loop for token = (cl-ansi-spec/tex:next-token stack)
                while token
                do (let ((span (cl-ansi-spec/tex:token-span token)))
                     (when (and last (> (cl-ansi-spec/tex:span-line span) last))
                       (return))
                     (when (in-range-p span)
                       (format t "~A~C~A~%" (location span) #\Tab
                               (cl-ansi-spec/tex:token-text token))))))))
    t))

(with-exit-status
  (let ((name (uiop:getenv "FILE"))
        (lines (uiop:getenv "LINES"))
        (skips (uiop:getenv "SKIPS")))
    (unless (and name (string/= name ""))
      (error "Usage: make tokens FILE=<spec file> [LINES=a-b] [SKIPS=1]"))
    (dump-tokens name :lines lines
                      :skips (and skips (string/= skips "") (string/= skips "0")))))
