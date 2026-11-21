;;;; src/tex/scanner.lisp
;;;;
;;;; TeX's input scanner for one file (TeXbook chapters 7-8): turns the
;;;; characters of successive lines into tokens, consulting the category
;;;; codes and \endlinechar of the state at the moment each token (and
;;;; each line) is read.  The scanner is in one of three modes: new line,
;;;; middle of line, skipping blanks.
;;;;
;;;; Everything the scanner reads ends up either in a token's span or in a
;;;; span reported to the reader's skip hook, in file order; together they
;;;; cover the file exactly.

(in-package #:cl-ansi-spec/tex)

(define-condition invalid-character (error)
  ((code :initarg :code :reader invalid-character-code)
   (span :initarg :span :reader invalid-character-span))
  (:report (lambda (condition stream)
             (format stream "Text line contains an invalid character ~A at ~A."
                     (character-text (invalid-character-code condition))
                     (invalid-character-span condition))))
  (:documentation "Signalled for a character of category 15.  The
CONTINUE restart skips it, as TeX does after reporting the error."))

(defstruct (file-reader (:constructor %make-file-reader (source skip-hook)))
  "Scanner state for one file being read.  SKIP-HOOK, if not NIL, is
called with a kind keyword and a span for every piece of input that
produces no token: :COMMENT, :SPACE, :IGNORED, :END-OF-LINE (a category 5
character skipped while skipping blanks), :DISCARDED (the rest of a line
after a category 5 character), :INVALID and :LINE-END (trailing spaces
and newline not represented by an \\endlinechar)."
  (source nil :type line-source :read-only t)
  (skip-hook nil :type (or null function) :read-only t)
  (line nil :type (or null line))
  (loc 0 :type fixnum)
  (mode :new-line :type (member :new-line :mid-line :skip-blanks))
  ;; TeX's force_eof: \endinput ends the file with its current line.
  (force-eof nil :type boolean))

(defun make-file-reader (source state &key skip-hook)
  "Return a reader of SOURCE.  Its first line is read at once, with the
\\endlinechar of STATE, as TeX does when it starts reading a file."
  (let ((reader (%make-file-reader source skip-hook)))
    (setf (file-reader-line reader) (read-source-line source state))
    reader))

(defun file-reader-name (reader)
  "Return the name of the file READER reads."
  (line-source-name (file-reader-source reader)))

(defun skip (reader kind from to)
  "Report buffer elements FROM..TO of the current line as skipped."
  (let ((hook (file-reader-skip-hook reader)))
    (when (and hook (< from to))
      (funcall hook kind (line-span (file-reader-source reader)
                                    (file-reader-line reader) from to)))))

(defun skip-rest-of-line (reader kind from)
  "Skip the current line from buffer element FROM to its end."
  (let ((limit (line-limit (file-reader-line reader))))
    (skip reader kind from limit)
    (setf (file-reader-loc reader) limit)))

(defun span-of (reader from to)
  "Return the span of elements FROM..TO of the reader's current line."
  (line-span (file-reader-source reader) (file-reader-line reader) from to))

(defun hex-digit-value (code)
  "Return the value of CODE as one of TeX's lowercase hex digits, or NIL."
  (cond ((<= 48 code 57) (- code 48))
        ((<= 97 code 102) (- code 87))))

(defun expanded-code (char codes index limit)
  "If ^^ notation begins with the superscript character CHAR, standing
just before element INDEX of CODES (whose first LIMIT elements are valid),
return the character it stands for and the number of elements from INDEX
on that it occupies; else NIL."
  (when (and (< (1+ index) limit)
             (= (aref codes index) char)
             (< (aref codes (1+ index)) 128))
    (let* ((c (aref codes (1+ index)))
           (high (hex-digit-value c))
           (low (and high (< (+ index 2) limit)
                     (hex-digit-value (aref codes (+ index 2))))))
      (if low
          (values (+ (* 16 high) low) 3)
          (values (if (< c 64) (+ c 64) (- c 64)) 2)))))

(defun read-character (reader state index)
  "Return the character at INDEX of the current line, with ^^ notation
reduced (repeatedly, as TeX does), its category code, and the index after
it.  The buffer is not changed."
  (let* ((line (file-reader-line reader))
         (codes (line-codes line))
         (limit (line-limit line))
         (code (aref codes index))
         (next (1+ index)))
    (loop
      (let ((catcode (catcode state code)))
        (multiple-value-bind (reduced width)
            (and (= catcode +superscript+)
                 (expanded-code code codes next limit))
          (unless reduced
            (return (values code catcode next)))
          (setf code reduced
                next (+ next width)))))))

(defun reduce-name-expansion (line k)
  "If ^^ notation starts at element K - 1 of LINE, inside a control
sequence name being scanned, rewrite it in the buffer and return true."
  (let ((codes (line-codes line)))
    (multiple-value-bind (code width)
        (expanded-code (aref codes (1- k)) codes k (line-limit line))
      (when code
        (reduce-in-buffer line (1- k) (1+ width) code)
        t))))

(defun scan-control-sequence (reader state escape-index)
  "Scan the name of a control sequence whose escape character ends just
before ESCAPE-INDEX; return the control sequence and set the reader's
location and mode (TeX's procedure, including the rewriting of ^^
notation in names)."
  (let* ((line (file-reader-line reader))
         (start escape-index))
    (when (>= start (line-limit line))
      ;; An escape character at the end of a line: the null control sequence.
      (setf (file-reader-loc reader) start)
      (return-from scan-control-sequence (intern-control-sequence state "")))
    (loop
      (let* ((codes (line-codes line))
             (limit (line-limit line))
             (k start)
             (code (aref codes k))
             (catcode (catcode state code)))
        (incf k)
        (setf (file-reader-mode reader)
              (if (or (= catcode +letter+) (= catcode +space+))
                  :skip-blanks
                  :mid-line))
        (when (and (= catcode +letter+) (< k limit))
          (loop do (setf code (aref codes k)
                         catcode (catcode state code))
                   (incf k)
                while (and (= catcode +letter+) (< k limit))))
        (unless (and (= catcode +superscript+)
                     (reduce-name-expansion line k))
          (when (and (/= catcode +letter+) (> k (1+ start)))
            (decf k))
          (setf (file-reader-loc reader) k)
          (return
            (intern-control-sequence
             state
             (map 'string #'code-char (subseq codes start k)))))))))

(defun next-file-token (reader state)
  "Return the next token of the file READER reads, or NIL at its end."
  (loop
    (let ((line (file-reader-line reader)))
      (cond
        ((null line)
         (return nil))
        ((>= (file-reader-loc reader) (line-limit line))
         (let ((hook (file-reader-skip-hook reader))
               (span (line-end-span (file-reader-source reader) line)))
           (when (and hook (< (span-start span) (span-end span)))
             (funcall hook :line-end span)))
         (setf (file-reader-line reader)
               (and (not (file-reader-force-eof reader))
                    (read-source-line (file-reader-source reader) state))
               (file-reader-loc reader) 0
               (file-reader-mode reader) :new-line))
        (t
         (let ((token (scan-at-location reader state)))
           (when token
             (return token))))))))

(defun scan-at-location (reader state)
  "Scan the input at the reader's location; return a token, or NIL if the
input there produces none."
  (let ((index (file-reader-loc reader))
        (mode (file-reader-mode reader)))
    (multiple-value-bind (code catcode next) (read-character reader state index)
      (setf (file-reader-loc reader) next)
      (flet ((character-token (code catcode)
               (setf (file-reader-mode reader) :mid-line)
               (make-character-token code catcode (span-of reader index next))))
        (ecase catcode
          (#.+escape+
           (let ((cs (scan-control-sequence reader state next)))
             (make-cs-token cs (span-of reader index
                                        (file-reader-loc reader)))))
          ((#.+begin-group+ #.+end-group+ #.+math-shift+ #.+alignment-tab+
            #.+parameter+ #.+superscript+ #.+subscript+ #.+letter+ #.+other+)
           (character-token code catcode))
          (#.+active+
           (setf (file-reader-mode reader) :mid-line)
           (make-cs-token (intern-active-character state code)
                          (span-of reader index next)))
          (#.+end-of-line+
           (prog1 (ecase mode
                    (:new-line
                     (make-cs-token (intern-control-sequence state "par")
                                    (span-of reader index next)))
                    (:mid-line
                     (make-character-token 32 +space+ (span-of reader index next)))
                    (:skip-blanks
                     (skip reader :end-of-line index next)
                     nil))
             (skip-rest-of-line reader :discarded next)))
          (#.+space+
           (if (eq mode :mid-line)
               (progn (setf (file-reader-mode reader) :skip-blanks)
                      (make-character-token 32 +space+ (span-of reader index next)))
               (progn (skip reader :space index next)
                      nil)))
          (#.+ignored+
           (skip reader :ignored index next)
           nil)
          (#.+comment+
           (skip-rest-of-line reader :comment index)
           nil)
          (#.+invalid+
           (cerror "Ignore the character." 'invalid-character
                   :code code :span (span-of reader index next))
           (skip reader :invalid index next)
           nil))))))
