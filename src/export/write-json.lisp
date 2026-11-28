;;;; src/export/write-json.lisp
;;;;
;;;; The JSON writer over the node registry (docs/exports.md, "JSON shape"):
;;;; a node is an object with "kind", "span", then its fields in declaration
;;;; order; text is an object, adjacent text merged; an optional field
;;;; without a value, and an empty array, are omitted, except that a
;;;; reference's "target" is always there (null when unresolved).  A file is
;;;; an object with "schemaVersion" and its content (see files.lisp).

(in-package #:cl-ansi-spec/export)

(defun merge-adjacent-text (items)
  "The list ITEMS of strings and nodes with each run of strings joined into
one string and the empty strings dropped."
  (let ((merged '()) (run '()))
    (flet ((flush ()
             (when run
               (let ((text (apply #'concatenate 'string (nreverse run))))
                 (when (plusp (length text))
                   (push text merged)))
               (setf run '()))))
      (dolist (item items)
        (if (stringp item)
            (push item run)
            (progn (flush) (push item merged))))
      (flush))
    (nreverse merged)))

(defun span-object (span)
  "The JSON object of the span SPAN."
  (schema-obj "file" (model:span-file span)
              "start" (model:span-start span)
              "end" (model:span-end span)
              "line" (model:span-line span)
              "column" (model:span-column span)))

(declaim (ftype function node-json))

(defun field-value-object (value type registry)
  "The JSON of VALUE, one value of the field type TYPE, a node of REGISTRY."
  (ecase (if (consp type) (first type) type)
    ((:string :integer) value)
    (:boolean (if value :true :false))
    (:span (span-object value))
    (:inlines (schema-arr
               (loop for item in (merge-adjacent-text value)
                     collect (if (stringp item)
                                 (text-json item)
                                 (node-json item registry)))))
    (:enum (json-name value))
    (:node (node-json value registry))
    (:target (if value
                 (schema-obj "kind" (json-name (model:target-kind value))
                             "id" (model:target-id value))
                 :null))))

(defun field-member (field value registry)
  "The (name . json) member of FIELD holding VALUE in a node, or NIL when the
field is omitted: no value, or an empty array; except a target, always
written, and a required field, which is written empty rather than hidden
(the validator then reports what the builder left out)."
  (let* ((type (model:field-type field))
         (kind (if (consp type) (first type) type))
         (name (json-name (model:field-name field)))
         (required (model:field-required field)))
    (cond ((model:field-repeated field)
           (when (or value required (eq kind :target))
             (cons name (schema-arr (loop for item in value
                                          collect (field-value-object item type registry))))))
          ((eq kind :target)
           (cons name (field-value-object value type registry)))
          ((eq kind :boolean)
           (when (or value required)
             (cons name (field-value-object value type registry))))
          ((eq kind :inlines)
           (when (or (merge-adjacent-text value) required)
             (cons name (field-value-object value type registry))))
          ((null value) nil)
          (t (cons name (field-value-object value type registry))))))

(defun node-json (node &optional (registry model:*registry*))
  "The JSON object of NODE: \"kind\", \"span\" (left out of a node the
builder made without one), then its fields in declaration order."
  (json:make-json-object
   (append (list (cons "kind" (json-name (model:node-kind node))))
           (when (model:node-span node)
             (list (cons "span" (span-object (model:node-span node)))))
           (loop for field in (model:node-fields (model:node-kind node) registry)
                 for member = (field-member field
                                            (model:node-field-value node field registry)
                                            registry)
                 when member collect member))))
