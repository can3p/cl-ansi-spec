;;;; src/export/validate.lisp
;;;;
;;;; The validator of the JSON Schema subset of docs/exports.md ("Validation").
;;;; It works on parsed JSON (cl-ansi-spec/json) and reports every error with
;;;; the JSON Pointer (RFC 6901) of the offending part of the instance.
;;;;
;;;; Subset: `type`, `const`, `enum`, `required`, `properties`,
;;;; `additionalProperties`, `items`, `$ref` (to `#` or a JSON Pointer
;;;; fragment of the same schema) and `oneOf`.  Annotation keywords
;;;; (`title`, `description`, `examples`, ...) and `$defs` are accepted and
;;;; ignored; any other keyword is an error, so the generator cannot drift
;;;; out of the subset unnoticed.

(in-package #:cl-ansi-spec/export)

(define-condition unsupported-schema-keyword (error)
  ((pointer :initarg :pointer :reader unsupported-schema-keyword-pointer
            :documentation "JSON Pointer of the keyword in the schema.")
   (keyword :initarg :keyword :reader unsupported-schema-keyword-keyword))
  (:report (lambda (condition stream)
             (format stream "Schema keyword ~S at ~A is outside the supported subset."
                     (unsupported-schema-keyword-keyword condition)
                     (unsupported-schema-keyword-pointer condition))))
  (:documentation "The schema uses a keyword the validator does not implement."))

(define-condition unresolved-schema-reference (error)
  ((reference :initarg :reference :reader unresolved-schema-reference-reference))
  (:report (lambda (condition stream)
             (format stream "Cannot resolve schema reference ~S."
                     (unresolved-schema-reference-reference condition))))
  (:documentation "A `$ref` does not lead to a subschema of the same schema."))

(define-condition circular-schema-reference (error)
  ((reference :initarg :reference :reader circular-schema-reference-reference))
  (:report (lambda (condition stream)
             (format stream "Schema reference ~S leads back to itself without consuming any data."
                     (circular-schema-reference-reference condition))))
  (:documentation "A chain of `$ref`s that never reaches a validating keyword."))

(defvar *active-references* '()
  "The (REFERENCE . INSTANCE-POINTER) pairs being followed, to detect cycles.")

(defstruct (validation-error (:conc-name validation-error-))
  "One violation: POINTER locates it in the instance, MESSAGE says what is wrong."
  (pointer "" :type string)
  (message "" :type string))

(defmethod print-object ((error validation-error) stream)
  (format stream "~A: ~A" (validation-error-pointer error)
          (validation-error-message error)))

;;; JSON Pointers

(defun escape-pointer-token (token)
  "TOKEN with `~` and `/` escaped as RFC 6901 asks."
  (with-output-to-string (out)
    (loop for char across token
          do (case char
               (#\~ (write-string "~0" out))
               (#\/ (write-string "~1" out))
               (t (write-char char out))))))

(defun unescape-pointer-token (token)
  (with-output-to-string (out)
    (loop with i = 0
          while (< i (length token))
          do (let ((char (char token i)))
               (if (and (char= char #\~) (< (1+ i) (length token)))
                   (let ((next (char token (1+ i))))
                     (case next
                       (#\0 (write-char #\~ out) (incf i 2))
                       (#\1 (write-char #\/ out) (incf i 2))
                       (t (write-char char out) (incf i))))
                   (progn (write-char char out) (incf i)))))))

(defun pointer-child (pointer token)
  "The pointer to TOKEN (a string or an array index) below POINTER."
  (format nil "~A/~A" pointer
          (escape-pointer-token (if (integerp token) (princ-to-string token) token))))

(defun split-pointer (pointer)
  "The unescaped tokens of POINTER, the empty string meaning the whole document."
  (when (plusp (length pointer))
    (unless (char= (char pointer 0) #\/)
      (error 'unresolved-schema-reference :reference pointer))
    (loop with start = 1
          for slash = (position #\/ pointer :start start)
          collect (unescape-pointer-token (subseq pointer start slash))
          while slash
          do (setf start (1+ slash)))))

(defun resolve-reference (root reference)
  "The subschema of ROOT that REFERENCE (\"#\" or \"#/json/pointer\") names."
  (unless (and (plusp (length reference)) (char= (char reference 0) #\#))
    (error 'unresolved-schema-reference :reference reference))
  (let ((node root))
    (dolist (token (split-pointer (subseq reference 1)) node)
      (setf node
            (cond ((json-object-p node)
                   (multiple-value-bind (value found) (json-get node token)
                     (if found
                         value
                         (error 'unresolved-schema-reference :reference reference))))
                  ((and (vectorp node) (not (stringp node))
                        (every #'digit-char-p token) (plusp (length token))
                        (< (parse-integer token) (length node)))
                   (aref node (parse-integer token)))
                  (t (error 'unresolved-schema-reference :reference reference)))))))

;;; The subset

(defparameter *annotation-keywords*
  '("$schema" "$id" "$comment" "title" "description" "examples" "default")
  "Keywords that say something about the data but never reject any.")

(defparameter *supported-keywords*
  '("type" "const" "enum" "required" "properties" "additionalProperties"
    "items" "$ref" "oneOf" "$defs")
  "The validating keywords of the subset (`$defs` only holds subschemas).")

(defun map-subschemas (function schema pointer)
  "Call FUNCTION with each direct subschema of SCHEMA and its pointer."
  (flet ((member-of (keyword)
           (and (json-object-p schema) (nth-value 0 (json-get schema keyword)))))
    (let ((properties (member-of "properties"))
          (defs (member-of "$defs"))
          (additional (member-of "additionalProperties"))
          (items (member-of "items"))
          (one-of (member-of "oneOf")))
      (when (json-object-p properties)
        (loop for (key . value) in (json-object-members properties)
              do (funcall function value
                          (pointer-child (pointer-child pointer "properties") key))))
      (when (json-object-p defs)
        (loop for (key . value) in (json-object-members defs)
              do (funcall function value
                          (pointer-child (pointer-child pointer "$defs") key))))
      (when (json-object-p additional)
        (funcall function additional (pointer-child pointer "additionalProperties")))
      (when (json-object-p items)
        (funcall function items (pointer-child pointer "items")))
      (when (and (vectorp one-of) (not (stringp one-of)))
        (loop for branch across one-of
              for index from 0
              do (funcall function branch
                          (pointer-child (pointer-child pointer "oneOf") index)))))))

(defun arrayp* (value)
  (and (vectorp value) (not (stringp value))))

(defun keyword-value-ok-p (keyword value)
  "True if VALUE has the form the validator expects for the supported KEYWORD."
  (flet ((schema-p (v) (or (json-object-p v) (member v '(:true :false)))))
    (cond ((string= keyword "type")
           (or (stringp value) (and (arrayp* value) (every #'stringp value))))
          ((string= keyword "required") (and (arrayp* value) (every #'stringp value)))
          ((string= keyword "enum") (arrayp* value))
          ((string= keyword "$ref") (stringp value))
          ((string= keyword "oneOf") (and (arrayp* value) (every #'schema-p value)))
          ((member keyword '("properties" "$defs") :test #'string=)
           (and (json-object-p value)
                (every (lambda (member) (schema-p (cdr member)))
                       (json-object-members value))))
          ((member keyword '("additionalProperties" "items") :test #'string=)
           (schema-p value))
          (t t))))

(defun schema-subset-violations (schema)
  "The keywords of SCHEMA (a parsed JSON object) outside the supported subset,
as a list of (POINTER . KEYWORD), in document order.  A supported keyword
whose value has the wrong form (`items` as an array, say) counts too."
  (let ((violations '()))
    (labels ((walk (node pointer)
               (when (json-object-p node)
                 (loop for (key . value) in (json-object-members node)
                       unless (and (or (member key *supported-keywords* :test #'string=)
                                       (member key *annotation-keywords* :test #'string=))
                                   (keyword-value-ok-p key value))
                         do (push (cons (pointer-child pointer key) key) violations))
                 (map-subschemas #'walk node pointer))))
      (walk schema ""))
    (nreverse violations)))

;;; Validation

(defun json-equal (a b)
  "Structural equality of two parsed JSON values; object member order is free."
  (cond ((and (stringp a) (stringp b)) (string= a b))
        ((and (integerp a) (integerp b)) (= a b))
        ((and (keywordp a) (keywordp b)) (eq a b))
        ((and (json-object-p a) (json-object-p b))
         (let ((ma (json-object-members a)) (mb (json-object-members b)))
           (and (= (length ma) (length mb))
                (every (lambda (member)
                         (multiple-value-bind (value found) (json-get b (car member))
                           (and found (json-equal (cdr member) value))))
                       ma))))
        ((and (vectorp a) (vectorp b) (not (stringp a)) (not (stringp b)))
         (and (= (length a) (length b)) (every #'json-equal a b)))
        (t nil)))

(defun json-type-name (value)
  (cond ((json-object-p value) "object")
        ((stringp value) "string")
        ((integerp value) "integer")
        ((vectorp value) "array")
        ((member value '(:true :false)) "boolean")
        ((eq value :null) "null")
        (t "unknown")))

(defun has-type-p (value type)
  (cond ((string= type "number") (integerp value))
        (t (string= type (json-type-name value)))))

(defun describe-json (value)
  "A short rendering of VALUE for messages."
  (let ((text (substitute-if #\Space (lambda (char) (char= char #\Newline))
                             (handler-case (cl-ansi-spec/json:write-json-to-string value)
                               (error () (princ-to-string value))))))
    (string-right-trim " " (if (> (length text) 60)
                                        (concatenate 'string (subseq text 0 57) "...")
                                        text))))

(defun branch-discriminant (root branch &optional seen)
  "The constant `kind` a oneOf BRANCH requires, or NIL.  A BRANCH that is a
bare `$ref` is looked through; SEEN are the references already followed."
  (when (json-object-p branch)
    (multiple-value-bind (reference found) (json-get branch "$ref")
      (when found
        (when (member reference seen :test #'string=)
          (error 'circular-schema-reference :reference reference))
        (return-from branch-discriminant
          (branch-discriminant root (resolve-reference root reference)
                               (cons reference seen)))))
    (let ((properties (json-get branch "properties")))
      (when (json-object-p properties)
        (let ((kind (json-get properties "kind")))
          (when (json-object-p kind)
            (let ((const (json-get kind "const")))
              (and (stringp const) const))))))))

(defun validate-instance (root schema instance pointer)
  "The list of validation errors of INSTANCE against SCHEMA, in order."
  (cond
    ((eq schema :true) '())
    ((eq schema :false)
     (list (make-validation-error :pointer pointer :message "no value is allowed here")))
    ((not (json-object-p schema)) '())
    (t
     (let ((errors '()))
       (flet ((fail (control &rest arguments)
                (push (make-validation-error
                       :pointer pointer
                       :message (apply #'format nil control arguments))
                      errors))
              (keyword (name) (json-get schema name)))
         ;; type
         (multiple-value-bind (type found) (keyword "type")
           (when found
             (let ((types (if (stringp type) (list type) (coerce type 'list))))
               (unless (some (lambda (name) (has-type-p instance name)) types)
                 (fail "expected ~{~A~^ or ~}, found ~A" types (json-type-name instance))
                 (return-from validate-instance (nreverse errors))))))
         ;; const, enum
         (multiple-value-bind (const found) (keyword "const")
           (when (and found (not (json-equal const instance)))
             (fail "expected the constant ~A, found ~A"
                   (describe-json const) (describe-json instance))))
         (multiple-value-bind (enum found) (keyword "enum")
           (when (and found (notany (lambda (value) (json-equal value instance)) enum))
             (fail "~A is not one of the enumerated values" (describe-json instance))))
         ;; objects
         (when (json-object-p instance)
           (multiple-value-bind (required found) (keyword "required")
             (when found
               (loop for name across required
                     unless (nth-value 1 (json-get instance name))
                       do (fail "missing required property ~S" name))))
           (let ((properties (keyword "properties"))
                 (additional (multiple-value-list (keyword "additionalProperties"))))
             (loop for (key . value) in (json-object-members instance)
                   for property = (and (json-object-p properties)
                                       (multiple-value-list (json-get properties key)))
                   do (cond ((and property (second property))
                             (setf errors
                                   (revappend (validate-instance
                                               root (first property) value
                                               (pointer-child pointer key))
                                              errors)))
                            ((second additional)
                             (setf errors
                                   (revappend (validate-instance
                                               root (first additional) value
                                               (pointer-child pointer key))
                                              errors)))))))
         ;; arrays
         (when (and (vectorp instance) (not (stringp instance)))
           (multiple-value-bind (items found) (keyword "items")
             (when found
               (loop for element across instance
                     for index from 0
                     do (setf errors
                              (revappend (validate-instance
                                          root items element (pointer-child pointer index))
                                         errors))))))
         ;; $ref
         (multiple-value-bind (reference found) (keyword "$ref")
           (when found
             (let ((active (cons reference pointer)))
               (when (member active *active-references* :test #'equal)
                 (error 'circular-schema-reference :reference reference))
               (let ((*active-references* (cons active *active-references*)))
                 (setf errors
                       (revappend (validate-instance
                                   root (resolve-reference root reference) instance pointer)
                                  errors))))))
         ;; oneOf
         (multiple-value-bind (branches found) (keyword "oneOf")
           (when found
             (let* ((kind (and (json-object-p instance)
                               (let ((value (json-get instance "kind")))
                                 (and (stringp value) value))))
                    (discriminants (map 'list (lambda (branch) (branch-discriminant root branch))
                                        branches))
                    (chosen (let ((index (and kind (position kind discriminants :test #'equal))))
                              (and index (elt branches index))))
                    ;; A branch whose constant kind differs from the
                    ;; instance's cannot match: it is not validated (the
                    ;; cost of a oneOf of every node kind is otherwise a
                    ;; validation of the whole instance per kind).
                    (results (map 'list (lambda (branch discriminant)
                                          (if (and kind discriminant
                                                   (not (string= kind discriminant)))
                                              (list :other-kind)
                                              (validate-instance root branch instance pointer)))
                                  branches discriminants))
                    (matching (count nil results)))
               (cond ((= matching 1))
                     ((and chosen (zerop matching))
                      (setf errors (revappend (nth (position chosen branches) results)
                                              errors)))
                     ((and kind (some #'identity discriminants))
                      (fail "unknown kind ~S" kind))
                     ((zerop matching)
                      (fail "~A matches none of the ~D alternatives"
                            (describe-json instance) (length branches)))
                     (t (fail "~A matches ~D alternatives, exactly one is allowed"
                              (describe-json instance) matching)))))))
       (nreverse errors)))))

(defvar *checked-schema* nil
  "The last schema found to be within the subset: validating many
instances against one schema checks it once.  It assumes a schema is not
changed after its first use.")

(defun validate-json (schema instance)
  "Validate INSTANCE, parsed JSON, against SCHEMA, a parsed schema of the subset.
Return the list of `validation-error`s, in document order; NIL means valid.
Signal `unsupported-schema-keyword` if SCHEMA leaves the subset and
`unresolved-schema-reference` for a `$ref` that leads nowhere."
  (unless (eq schema *checked-schema*)
    (let ((violations (schema-subset-violations schema)))
      (when violations
        (error 'unsupported-schema-keyword
               :pointer (car (first violations)) :keyword (cdr (first violations)))))
    (setf *checked-schema* schema))
  (validate-instance schema schema instance ""))

(defun json-valid-p (schema instance)
  "True if INSTANCE is valid against SCHEMA (see `validate-json`)."
  (null (validate-json schema instance)))
