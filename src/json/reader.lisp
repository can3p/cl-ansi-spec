;;;; src/json/reader.lisp
;;;;
;;;; The JSON reader: strict RFC 8259 text to the representation described
;;;; in package.lisp.  Duplicate object keys, floats, lone surrogates and
;;;; trailing text are errors.

(in-package #:cl-ansi-spec/json)

(define-condition json-error (error) ()
  (:documentation "Root of the errors of this package."))

(define-condition json-parse-error (json-error)
  ((message :initarg :message :reader json-parse-error-message)
   (position :initarg :position :reader json-parse-error-position
             :documentation "Character offset in the text where it went wrong."))
  (:report (lambda (condition stream)
             (format stream "JSON parse error at offset ~D: ~A"
                     (json-parse-error-position condition)
                     (json-parse-error-message condition)))))

(defun make-json-object (members)
  "Return the JSON object with MEMBERS, an alist of (key . value)."
  (cons :object members))

(defun json-object-p (value)
  "True if VALUE is a JSON object in the representation of this package."
  (and (consp value) (eq (car value) :object)))

(defun json-object-members (object)
  "The (key . value) alist of OBJECT, in order."
  (cdr object))

(defun json-get (object key)
  "Return the value of KEY in OBJECT and true, or NIL and false."
  (check-type object (satisfies json-object-p))
  (let ((member (assoc key (json-object-members object) :test #'string=)))
    (if member (values (cdr member) t) (values nil nil))))

(defparameter *maximum-depth* 512
  "Nesting depth of arrays and objects beyond which the reader and the
writer give up, so that hostile input cannot exhaust the stack.")

(defstruct (cursor (:conc-name cur-))
  (text "" :type (simple-array character (*)))
  (pos 0 :type fixnum)
  (depth 0 :type fixnum))

(defun parse-fail (cursor control &rest arguments)
  (error 'json-parse-error :position (cur-pos cursor)
                           :message (apply #'format nil control arguments)))

(defun peek (cursor)
  (when (< (cur-pos cursor) (length (cur-text cursor)))
    (char (cur-text cursor) (cur-pos cursor))))

(defun advance (cursor)
  (prog1 (peek cursor) (incf (cur-pos cursor))))

(defun skip-whitespace (cursor)
  (loop for char = (peek cursor)
        while (member char '(#\Space #\Tab #\Newline #\Return))
        do (advance cursor)))

(defun expect-literal (cursor word value)
  (loop for char across word do
    (unless (eql (peek cursor) char)
      (parse-fail cursor "expected ~S" word))
    (advance cursor))
  value)

(defun read-hex4 (cursor)
  (let ((code 0))
    (dotimes (i 4 code)
      (let ((digit (and (peek cursor) (digit-char-p (peek cursor) 16))))
        (unless digit (parse-fail cursor "expected four hex digits after \\u"))
        (setf code (+ (* code 16) digit))
        (advance cursor)))))

(defun read-unicode-escape (cursor)
  "After \\u: the character, combining a surrogate pair."
  (let ((code (read-hex4 cursor)))
    (cond ((<= #xD800 code #xDBFF)
           (unless (and (eql (peek cursor) #\\)
                        (< (1+ (cur-pos cursor)) (length (cur-text cursor)))
                        (char= (char (cur-text cursor) (1+ (cur-pos cursor))) #\u))
             (parse-fail cursor "high surrogate without a low surrogate"))
           (advance cursor) (advance cursor)
           (let ((low (read-hex4 cursor)))
             (unless (<= #xDC00 low #xDFFF)
               (parse-fail cursor "high surrogate followed by a non-low surrogate"))
             (code-char (+ #x10000 (ash (- code #xD800) 10) (- low #xDC00)))))
          ((<= #xDC00 code #xDFFF) (parse-fail cursor "lone low surrogate"))
          (t (code-char code)))))

(defun read-string-body (cursor)
  "Read a string; the opening quote is the next character."
  (advance cursor)
  (with-output-to-string (out)
    (loop
      (let ((char (advance cursor)))
        (cond ((null char) (parse-fail cursor "unterminated string"))
              ((char= char #\") (return))
              ((< (char-code char) #x20)
               (decf (cur-pos cursor))
               (parse-fail cursor "unescaped control character"))
              ((char= char #\\)
               (let ((escape (advance cursor)))
                 (case escape
                   (#\" (write-char #\" out))
                   (#\\ (write-char #\\ out))
                   (#\/ (write-char #\/ out))
                   (#\b (write-char #\Backspace out))
                   (#\f (write-char #\Page out))
                   (#\n (write-char #\Newline out))
                   (#\r (write-char #\Return out))
                   (#\t (write-char #\Tab out))
                   (#\u (write-char (read-unicode-escape cursor) out))
                   (t (decf (cur-pos cursor))
                      (parse-fail cursor "invalid escape")))))
              (t (write-char char out)))))))

(defun read-number (cursor)
  (let ((start (cur-pos cursor)))
    (when (eql (peek cursor) #\-) (advance cursor))
    (let ((first-digit (cur-pos cursor)))
      (loop while (and (peek cursor) (digit-char-p (peek cursor)))
            do (advance cursor))
      (let ((count (- (cur-pos cursor) first-digit)))
        (when (zerop count) (parse-fail cursor "expected a digit"))
        (when (and (> count 1) (char= (char (cur-text cursor) first-digit) #\0))
          (setf (cur-pos cursor) first-digit)
          (parse-fail cursor "leading zero"))))
    (when (member (peek cursor) '(#\. #\e #\E))
      (parse-fail cursor "floating-point numbers are not supported"))
    (parse-integer (cur-text cursor) :start start :end (cur-pos cursor))))

(defun enter (cursor)
  (when (> (incf (cur-depth cursor)) *maximum-depth*)
    (parse-fail cursor "nesting deeper than ~D" *maximum-depth*)))

(defun read-array (cursor)
  (enter cursor)
  (advance cursor)
  (skip-whitespace cursor)
  (if (eql (peek cursor) #\])
      (progn (advance cursor) (decf (cur-depth cursor)) (vector))
      (let ((items '()))
        (loop
          (push (read-value cursor) items)
          (skip-whitespace cursor)
          (case (advance cursor)
            (#\,)
            (#\] (decf (cur-depth cursor))
                  (return (coerce (nreverse items) 'simple-vector)))
            (t (decf (cur-pos cursor))
               (parse-fail cursor "expected , or ]")))))))

(defun read-object (cursor)
  (enter cursor)
  (advance cursor)
  (skip-whitespace cursor)
  (if (eql (peek cursor) #\})
      (progn (advance cursor) (decf (cur-depth cursor)) (make-json-object '()))
      (let ((members '()))
        (loop
          (skip-whitespace cursor)
          (unless (eql (peek cursor) #\") (parse-fail cursor "expected a string key"))
          (let ((key (read-string-body cursor)))
            (when (assoc key members :test #'string=)
              (parse-fail cursor "duplicate key ~S" key))
            (skip-whitespace cursor)
            (unless (eql (advance cursor) #\:)
              (decf (cur-pos cursor))
              (parse-fail cursor "expected :"))
            (push (cons key (read-value cursor)) members))
          (skip-whitespace cursor)
          (case (advance cursor)
            (#\,)
            (#\} (decf (cur-depth cursor))
                  (return (make-json-object (nreverse members))))
            (t (decf (cur-pos cursor))
               (parse-fail cursor "expected , or }")))))))

(defun read-value (cursor)
  (skip-whitespace cursor)
  (let ((char (peek cursor)))
    (cond ((null char) (parse-fail cursor "unexpected end of text"))
          ((char= char #\{) (read-object cursor))
          ((char= char #\[) (read-array cursor))
          ((char= char #\") (read-string-body cursor))
          ((char= char #\t) (expect-literal cursor "true" :true))
          ((char= char #\f) (expect-literal cursor "false" :false))
          ((char= char #\n) (expect-literal cursor "null" :null))
          ((or (char= char #\-) (digit-char-p char)) (read-number cursor))
          (t (parse-fail cursor "unexpected character ~S" char)))))

(defun parse-json (text)
  "Parse the JSON document in the string TEXT; signal JSON-PARSE-ERROR
if it is not exactly one well-formed value."
  (let ((cursor (make-cursor :text (coerce text '(simple-array character (*))))))
    (prog1 (read-value cursor)
      (skip-whitespace cursor)
      (when (peek cursor) (parse-fail cursor "trailing text after the value")))))

(defun read-json (stream)
  "Parse the JSON document that is the rest of the character STREAM;
signal JSON-PARSE-ERROR as PARSE-JSON does."
  (parse-json (with-output-to-string (out)
                (loop with buffer = (make-string 4096)
                      for count = (read-sequence buffer stream)
                      while (plusp count)
                      do (write-string buffer out :end count)))))

(defun parse-json-file (pathname)
  "Parse the UTF-8 file PATHNAME."
  (with-open-file (stream pathname :external-format :utf-8)
    (read-json stream)))
