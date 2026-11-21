;;;; src/tex/token.lisp
;;;;
;;;; Tokens and their source spans.  A token is either a character token
;;;; (character code + category code) or a symbolic token naming a
;;;; CONTROL-SEQUENCE.  Control sequences and active characters are
;;;; interned in one namespace per state, so that later stages compare
;;;; meanings and tokens with EQ.

(in-package #:cl-ansi-spec/tex)

;;; Source spans.

(defstruct (span (:constructor make-span (file start end line column)))
  "Where a token came from: FILE (a name relative to the source tree), the
character offsets START (inclusive) and END (exclusive) in that file, and
the LINE (from 1) and COLUMN (from 0) of START."
  (file nil :read-only t)
  (start 0 :type (integer 0) :read-only t)
  (end 0 :type (integer 0) :read-only t)
  (line 1 :type (integer 1) :read-only t)
  (column 0 :type (integer 0) :read-only t))

(defmethod print-object ((span span) stream)
  (print-unreadable-object (span stream :type t)
    (format stream "~A:~D:~D [~D,~D)" (span-file span) (span-line span)
            (span-column span) (span-start span) (span-end span))))

;;; The namespace of control sequences and active characters.

(defstruct (control-sequence (:constructor %make-control-sequence (name active-p)))
  "An interned control sequence, or an active character when ACTIVE-P.
NAME is a string (a single character for an active character)."
  (name "" :type string :read-only t)
  (active-p nil :type boolean :read-only t))

(defmethod print-object ((cs control-sequence) stream)
  (print-unreadable-object (cs stream :type t)
    (write-string (control-sequence-text cs) stream)))

(defun intern-control-sequence (state name)
  "Return the unique control sequence called NAME (a string) in STATE."
  (let ((names (state-names state)))
    (or (gethash name names)
        (let ((name (coerce (copy-seq name) 'simple-string)))
          (setf (gethash name names) (%make-control-sequence name nil))))))

(defun intern-active-character (state code)
  "Return the unique active character with character code CODE in STATE."
  (let ((names (state-names state)))
    (or (gethash code names)
        (setf (gethash code names)
              (%make-control-sequence (string (code-char code)) t)))))

;;; Printing characters the way TeX shows them.

(defun character-text (code)
  "Return a printable representation of character CODE: the character
itself if it is printable ASCII, otherwise TeX's ^^ notation."
  (cond ((<= 32 code 126) (string (code-char code)))
        ((< code 64) (format nil "^^~C" (code-char (+ code 64))))
        ((= code 127) "^^?")
        ((< code 256) (format nil "^^~(~2,'0X~)" code))
        (t (string (code-char code)))))

(defun control-sequence-text (cs)
  "Return how CS is written: a backslash and its name, or the active
character itself."
  (let ((name (with-output-to-string (stream)
                (loop for char across (control-sequence-name cs)
                      do (write-string (character-text (char-code char))
                                       stream)))))
    (if (control-sequence-active-p cs)
        name
        (concatenate 'string "\\" name))))

;;; Tokens.

(defstruct (token (:constructor nil) (:copier nil))
  "A TeX token.  SPAN tells where it was read, or is NIL for a token that
was not read from a file."
  (span nil :type (or null span) :read-only t))

(defstruct (character-token
            (:include token)
            (:constructor make-character-token (code catcode &optional span)))
  "A character token: character CODE with category CATCODE."
  (code 0 :type character-code :read-only t)
  (catcode +other+ :type catcode-value :read-only t))

(defstruct (cs-token
            (:include token)
            (:constructor make-cs-token (control-sequence &optional span)))
  "A token naming a control sequence or an active character."
  (control-sequence nil :type control-sequence :read-only t))

(defun token= (a b)
  "True if tokens A and B are the same TeX token; spans are ignored."
  (etypecase a
    (character-token
     (and (character-token-p b)
          (= (character-token-code a) (character-token-code b))
          (= (character-token-catcode a) (character-token-catcode b))))
    (cs-token
     (and (cs-token-p b)
          (eq (cs-token-control-sequence a) (cs-token-control-sequence b))))))

(defun token-text (token)
  "Return a compact representation of TOKEN: a control sequence or active
character as written, a character token as its character followed by its
category code."
  (etypecase token
    (cs-token (control-sequence-text (cs-token-control-sequence token)))
    (character-token (format nil "~A ~D"
                             (character-text (character-token-code token))
                             (character-token-catcode token)))))

(defmethod print-object ((token token) stream)
  (print-unreadable-object (token stream :type t)
    (write-string (token-text token) stream)))
