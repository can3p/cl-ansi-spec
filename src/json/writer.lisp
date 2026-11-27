;;;; src/json/writer.lisp
;;;;
;;;; The JSON writer.  Deterministic: two-space indentation, one member or
;;;; element per line, empty containers as {} and [], LF line endings and a
;;;; final newline.  Strings are escaped per RFC 8259 (only ", \ and the
;;;; control characters), everything else is written as is, in UTF-8.

(in-package #:cl-ansi-spec/json)

(define-condition json-write-error (json-error)
  ((value :initarg :value :reader json-write-error-value))
  (:documentation "VALUE has no JSON form (a float, a lone surrogate, a foreign object, too deep).")
  (:report (lambda (condition stream)
             (format stream "Cannot write ~S as JSON (integers only, no floats)."
                     (json-write-error-value condition)))))

(defun write-json-string (string stream)
  (when (find-if (lambda (char) (<= #xD800 (char-code char) #xDFFF)) string)
    (error 'json-write-error :value string))
  (write-char #\" stream)
  (loop for char across string
        for code = (char-code char)
        do (case char
             (#\" (write-string "\\\"" stream))
             (#\\ (write-string "\\\\" stream))
             (#\Backspace (write-string "\\b" stream))
             (#\Page (write-string "\\f" stream))
             (#\Newline (write-string "\\n" stream))
             (#\Return (write-string "\\r" stream))
             (#\Tab (write-string "\\t" stream))
             (t (if (< code #x20)
                    (format stream "\\u~(~4,'0x~)" code)
                    (write-char char stream)))))
  (write-char #\" stream))

(defun write-indent (depth stream)
  (write-char #\Newline stream)
  (loop repeat (* 2 depth) do (write-char #\Space stream)))

(defun write-value (value stream depth)
  (when (> depth *maximum-depth*)
    (error 'json-write-error :value "nesting too deep"))
  (cond ((eq value :true) (write-string "true" stream))
        ((eq value :false) (write-string "false" stream))
        ((eq value :null) (write-string "null" stream))
        ((integerp value) (format stream "~D" value))
        ((stringp value) (write-json-string value stream))
        ((json-object-p value)
         (let ((members (json-object-members value)))
           (if (null members)
               (write-string "{}" stream)
               (progn
                 (write-char #\{ stream)
                 (loop for (key . member) in members
                       for first = t then nil
                       do (unless first (write-char #\, stream))
                          (write-indent (1+ depth) stream)
                          (write-json-string key stream)
                          (write-string ": " stream)
                          (write-value member stream (1+ depth)))
                 (write-indent depth stream)
                 (write-char #\} stream)))))
        ((and (vectorp value) (not (stringp value)))
         (if (zerop (length value))
             (write-string "[]" stream)
             (progn
               (write-char #\[ stream)
               (loop for element across value
                     for first = t then nil
                     do (unless first (write-char #\, stream))
                        (write-indent (1+ depth) stream)
                        (write-value element stream (1+ depth)))
               (write-indent depth stream)
               (write-char #\] stream))))
        (t (error 'json-write-error :value value))))

(defun write-json (value stream)
  "Write VALUE to the character STREAM as JSON, ending with a newline."
  (write-value value stream 0)
  (write-char #\Newline stream)
  value)

(defun write-json-to-string (value)
  "WRITE-JSON to a fresh string and return it."
  (with-output-to-string (out) (write-json value out)))

(defun write-json-file (value pathname)
  "Write VALUE to PATHNAME as UTF-8, replacing the file; LF endings."
  (with-open-file (stream pathname :direction :output :if-exists :supersede
                                   :external-format :utf-8)
    (write-json value stream)))
