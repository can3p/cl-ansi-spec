;;;; tests/json.lisp
;;;;
;;;; The JSON reader and writer (src/json/): RFC 8259's examples, escapes,
;;;; errors and the byte format of the writer.

(in-package #:cl-ansi-spec/tests)

(define-test json
  :parent cl-ansi-spec
  :description "Reading and writing JSON.")

(defun obj (&rest members)
  "An object from alternating keys and values."
  (cl-ansi-spec/json:make-json-object
   (loop for (key value) on members by #'cddr collect (cons key value))))

(defun json-of (text) (cl-ansi-spec/json:parse-json text))

(defun json-error-p (text)
  (handler-case (progn (json-of text) nil)
    (cl-ansi-spec/json:json-parse-error () t)))

(define-test json-scalars
  :parent json
  (is eq :true (json-of "true"))
  (is eq :false (json-of " false "))
  (is eq :null (json-of (format nil "~%null~%")))
  (is = 0 (json-of "0"))
  (is = -17 (json-of "-17"))
  (is = 123456789012345678901234567890 (json-of "123456789012345678901234567890"))
  (is string= "" (json-of "\"\""))
  (is string= "héllo ☃" (json-of "\"héllo ☃\"")))

(define-test json-escapes
  :parent json
  (is string= (coerce '(#\" #\\ #\/ #\Backspace #\Page #\Newline #\Return #\Tab) 'string)
      (json-of "\"\\\"\\\\\\/\\b\\f\\n\\r\\t\""))
  (is string= "é" (json-of "\"\\u00e9\""))
  (is string= "é" (json-of "\"\\u00E9\""))
  ;; RFC 8259 section 7: U+1D11E as a surrogate pair.
  (is equal (list (code-char #x1D11E)) (coerce (json-of "\"\\uD834\\uDD1E\"") 'list))
  (is string= (format nil "\\u~4,'0x" 1) "\\u0001")
  (is string= (string (code-char 1)) (json-of "\"\\u0001\"")))

(define-test json-rfc-examples
  :parent json
  ;; RFC 8259 section 13, example 1.
  (let ((value (json-of "{
        \"Image\": {
            \"Width\":  800,
            \"Height\": 600,
            \"Title\":  \"View from 15th Floor\",
            \"Thumbnail\": {
                \"Url\":    \"http://www.example.com/image/481989943\",
                \"Height\": 125,
                \"Width\":  100
            },
            \"Animated\" : false,
            \"IDs\": [116, 943, 234, 38793]
          }
      }")))
    (let ((image (cl-ansi-spec/json:json-get value "Image")))
      (is = 800 (cl-ansi-spec/json:json-get image "Width"))
      (is equal '("Width" "Height" "Title" "Thumbnail" "Animated" "IDs")
          (mapcar #'car (cl-ansi-spec/json:json-object-members image)))
      (is equalp #(116 943 234 38793) (cl-ansi-spec/json:json-get image "IDs"))
      (is eq :false (cl-ansi-spec/json:json-get image "Animated"))))
  ;; Example 2: an array of objects.
  (let ((value (json-of "[{\"precision\": \"zip\", \"Zip\": \"94107\"},
                          {\"precision\": \"zip\", \"Zip\": \"94085\"}]")))
    (is = 2 (length value))
    (is string= "94085" (cl-ansi-spec/json:json-get (aref value 1) "Zip")))
  ;; Examples 3 and 4: bare values.
  (is string= "Hello world!" (json-of "\"Hello world!\""))
  (is = 42 (json-of "42"))
  (true (eq :true (json-of "true")))
  ;; Key lookup misses.
  (is equal '(nil nil)
      (multiple-value-list (cl-ansi-spec/json:json-get (obj) "x"))))

(define-test json-rejects
  :parent json
  (dolist (text '("" "   " "{" "[1,]" "[1 2]" "{\"a\":1,}" "{\"a\" 1}" "{a:1}"
                  "\"abc" "'a'" "tru" "nul" "01" "-" "-a" "1.5" "1e3" "1E3" "2.0"
                  "+1" "[1] x" "{\"a\":1,\"a\":2}" "\"\\x\"" "\"\\u12\""
                  "\"\\uD834\"" "\"\\uDD1E\"" "\"\\uD834\\u0041\""))
    (true (json-error-p text) "~S should not parse" text))
  (true (json-error-p (format nil "\"a~Cb\"" (code-char 10))) "raw newline in string")
  (true (json-error-p (format nil "\"a~Cb\"" (code-char 9))) "raw tab in string")
  (let ((condition (handler-case (json-of "[1, ?]")
                     (cl-ansi-spec/json:json-parse-error (c) c))))
    (is = 4 (cl-ansi-spec/json:json-parse-error-position condition))))

(define-test json-writes
  :parent json
  (is string= (format nil "true~%") (cl-ansi-spec/json:write-json-to-string :true))
  (is string= (format nil "null~%") (cl-ansi-spec/json:write-json-to-string :null))
  (is string= (format nil "-5~%") (cl-ansi-spec/json:write-json-to-string -5))
  (is string= (format nil "{}~%") (cl-ansi-spec/json:write-json-to-string (obj)))
  (is string= (format nil "[]~%") (cl-ansi-spec/json:write-json-to-string (vector)))
  (is string= (format nil "\"a\\\"b\\\\c\\nd\\te\\u0001f\\u001fg é ☃ 𝄞 /\"~%")
      (cl-ansi-spec/json:write-json-to-string
       (format nil "a\"b\\c~Cd~Ce~Cf~Cg é ☃ ~C /" #\Newline #\Tab (code-char 1)
               (code-char 31) (code-char #x1D11E))))
  (is string= (format nil "{~%  \"b\": 1,~%  \"a\": [~%    1,~%    {~%      \"c\": []~%    }~%  ],~%  \"d\": {}~%}~%")
      (cl-ansi-spec/json:write-json-to-string
       (obj "b" 1 "a" (vector 1 (obj "c" (vector))) "d" (obj)))))

(define-test json-write-errors
  :parent json
  (fail (cl-ansi-spec/json:write-json-to-string 1.5) 'cl-ansi-spec/json:json-write-error)
  (fail (cl-ansi-spec/json:write-json-to-string 'foo) 'cl-ansi-spec/json:json-write-error)
  (fail (cl-ansi-spec/json:write-json-to-string (vector 1 2.0d0))
        'cl-ansi-spec/json:json-write-error))

(define-test json-round-trip
  :parent json
  (let* ((value (obj "z" (vector 1 2 (obj "k" "v\"\\")) "a" :null "é" (vector :true :false)
                     "n" (obj) "e" (vector) "s" (format nil "line~%tab~C" #\Tab)))
         (text (cl-ansi-spec/json:write-json-to-string value)))
    (is equalp value (json-of text))
    (is string= text (cl-ansi-spec/json:write-json-to-string (json-of text)))))

(define-test json-files
  :parent json
  (let ((path (merge-pathnames "cl-ansi-spec-json-test.json" (uiop:temporary-directory)))
        (value (obj "name" "naïve ☃" "list" (vector 1 2 3))))
    (unwind-protect
         (progn
           (cl-ansi-spec/json:write-json-file value path)
           (is equalp value (cl-ansi-spec/json:parse-json-file path))
           (let ((bytes (with-open-file (in path :element-type '(unsigned-byte 8))
                          (let ((v (make-array (file-length in) :element-type '(unsigned-byte 8))))
                            (read-sequence v in) v))))
             (false (find 13 bytes) "LF endings only")
             (is = 10 (aref bytes (1- (length bytes))))
             (true (search #(#xc3 #xaf) bytes) "UTF-8")))
      (uiop:delete-file-if-exists path))))

(define-test json-limits
  :parent json
  (let ((deep (concatenate 'string (make-string 600 :initial-element #\[)
                           (make-string 600 :initial-element #\]))))
    (true (json-error-p deep) "too deep to read"))
  (let ((ok (concatenate 'string (make-string 100 :initial-element #\[)
                         (make-string 100 :initial-element #\]))))
    (false (json-error-p ok)))
  (let ((value (vector)))
    (dotimes (i 600) (setf value (vector value)))
    (fail (cl-ansi-spec/json:write-json-to-string value)
          'cl-ansi-spec/json:json-write-error))
  (fail (cl-ansi-spec/json:write-json-to-string (string (code-char #xD800)))
        'cl-ansi-spec/json:json-write-error)
  (is = 0 (json-of "-0"))
  (true (json-error-p "-1 2"))
  ;; A non-simple input string reads like a simple one.
  (is = 7 (json-of (make-array 1 :element-type 'character :initial-element #\7
                                  :adjustable t :fill-pointer t))))
