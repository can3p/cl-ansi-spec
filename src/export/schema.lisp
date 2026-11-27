;;;; src/export/schema.lisp
;;;;
;;;; The JSON Schema generator: schema/model.schema.json from the node
;;;; registry (docs/exports.md, "One definition" and "Validation").
;;;; Draft 2020-12, restricted to the subset the validator implements
;;;; (type, const, enum, required, properties, additionalProperties,
;;;; items, $ref, oneOf), plus the annotations $schema, $defs, title,
;;;; description and examples.  One $defs entry per node kind, named as
;;;; the kind, picked out by a constant "kind".  Besides them: "span",
;;;; "text" (unless a kind :text is declared), "enum-<name>" and
;;;; "target-<name>".  Owner: step 3.4 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/export)

(defparameter +schema-draft+ "https://json-schema.org/draft/2020-12/schema"
  "The value of \"$schema\".")

(defparameter *subset-keywords*
  '("type" "const" "enum" "required" "properties" "additionalProperties"
    "items" "$ref" "oneOf")
  "The JSON Schema keywords the generator may emit (docs/exports.md,
\"Validation\").")

(defparameter *annotation-keywords*
  '("$schema" "$defs" "title" "description" "examples")
  "The keywords that annotate or hold definitions and validate nothing.")

;;; JSON building

(defun obj (&rest members)
  "The JSON object of the alternating keys and values MEMBERS."
  (json:make-json-object
   (loop for (key value) on members by #'cddr collect (cons key value))))

(defun arr (list)
  "The JSON array of the elements of LIST."
  (coerce list 'simple-vector))

(defun lowercase (symbol)
  "The name of SYMBOL in lower case: its JSON name."
  (string-downcase (symbol-name symbol)))

(defun documented-p (doc)
  "True when the docstring DOC is not blank."
  (and doc (string/= "" (string-trim '(#\Space #\Newline #\Tab) doc))))

(defun with-description (members doc)
  "The alist MEMBERS with a description appended when DOC is there."
  (if (documented-p doc)
      (append members (list (cons "description" doc)))
      members))

(defun ref (name)
  "A reference to the definition NAME."
  (obj "$ref" (format nil "#/$defs/~A" name)))

(defun one-of (alternatives)
  "A schema accepting any of the schemas ALTERNATIVES (one means itself)."
  (if (rest alternatives)
      (obj "oneOf" (arr alternatives))
      (first alternatives)))

;;; Example values

(defun example-error (control &rest arguments)
  "Signal that an example cannot be written as JSON."
  (error "Cannot write an example as JSON: ~?" control arguments))

(defun text-json (string)
  "The JSON text object of STRING."
  (obj "kind" "text" "text" string))

(declaim (ftype function node-example-json))

(defun item-json (item registry)
  "The JSON of a string or node ITEM of an example."
  (if (stringp item) (text-json item) (node-example-json item registry)))

(defun value-json (value type registry)
  "The JSON of VALUE, one value of the field type TYPE."
  (ecase (if (consp type) (first type) type)
    (:string (if (stringp value) value (example-error "~S is not a string." value)))
    (:integer (if (integerp value) value (example-error "~S is not an integer." value)))
    (:boolean (if value :true :false))
    (:span (if (and (listp value) (= 5 (length value)))
               (destructuring-bind (file start end line column) value
                 (obj "file" file "start" start "end" end "line" line "column" column))
               (example-error "~S is not a span (file start end line column)." value)))
    (:inlines (arr (mapcar (lambda (item) (item-json item registry)) value)))
    (:enum (if (keywordp value)
               (lowercase value)
               (example-error "~S is not an enumeration keyword." value)))
    (:node (item-json value registry))
    (:target (if (null value)
                 :null
                 (destructuring-bind (kind id) value
                   (obj "kind" (lowercase kind) "id" id))))))

(defun field-value-json (value field registry)
  "The JSON of VALUE for FIELD: a list of values when the field is repeated."
  (let ((type (model:field-type field)))
    (if (model:field-repeated field)
        (arr (mapcar (lambda (v) (value-json v type registry)) value))
        (value-json value type registry))))

(defun node-example-json (example registry)
  "The JSON of the node EXAMPLE, an S-expression (:kind :field value ...)."
  (unless (and (consp example) (keywordp (first example)))
    (example-error "~S is not a node." example))
  (let ((kind (first example)))
    (unless (model:find-node-declaration kind registry)
      (example-error "~S is not a declared node kind." kind))
    (json:make-json-object
     (cons (cons "kind" (lowercase kind))
           (loop for (key value) on (rest example) by #'cddr
                 for field = (model:find-field kind key registry)
                 unless field
                   do (example-error "~S has no field ~S." kind key)
                 collect (cons (lowercase (model:field-name field))
                               (field-value-json value field registry)))))))

;;; Definitions

(defun inline-kinds (registry)
  "The kinds an inline list holds besides text."
  (remove :text (model:category-kinds :inline registry)))

(defun kinds-schema (names registry)
  "The schema of a node of any of the kinds or categories NAMES."
  (let ((kinds (model:expand-kinds names registry)))
    (unless kinds
      (error "No node kind is declared for ~S." names))
    (one-of (loop for kind in kinds collect (ref (lowercase kind))))))

(defun type-schema (type registry)
  "The schema of one value of the field type TYPE."
  (ecase (if (consp type) (first type) type)
    (:string (obj "type" "string"))
    (:integer (obj "type" "integer"))
    (:boolean (obj "type" "boolean"))
    (:span (ref "span"))
    (:inlines (obj "type" "array"
                   "items" (one-of (cons (ref "text")
                                         (loop for kind in (inline-kinds registry)
                                               collect (ref (lowercase kind)))))))
    (:enum (ref (format nil "enum-~A" (lowercase (second type)))))
    (:node (kinds-schema (rest type) registry))
    (:target (obj "oneOf"
                  (arr (append (loop for name in (rest type)
                                     collect (ref (format nil "target-~A" (lowercase name))))
                               (list (obj "type" "null"))))))))

(defun target-field-p (field)
  "True when FIELD is a reference: always present, null when unresolved."
  (let ((type (model:field-type field)))
    (and (consp type) (eq :target (first type)))))

(defun field-schema (field registry)
  "The property schema of FIELD, with its title, description and example."
  (let* ((one (type-schema (model:field-type field) registry))
         (base (if (model:field-repeated field)
                   (obj "type" "array" "items" one)
                   one)))
    (json:make-json-object
     (append (json:json-object-members base)
             (list (cons "title" (lowercase (model:field-name field))))
             (with-description '() (model:field-doc field))
             (when (model:field-example-p field)
               (list (cons "examples"
                           (arr (list (field-value-json (model:field-example field)
                                                        field registry))))))))))

(defun node-schema (declaration registry)
  "The $defs entry of the node DECLARATION."
  (let* ((kind (model:node-declaration-kind declaration))
         (fields (model:node-declaration-fields declaration))
         (required (append '("kind" "span")
                           (loop for field in fields
                                 when (or (model:field-required field)
                                          (target-field-p field))
                                   collect (lowercase (model:field-name field))))))
    (json:make-json-object
     (append
      (list (cons "type" "object")
            (cons "title" (lowercase kind)))
      (with-description '() (model:definition-doc declaration))
      (list (cons "properties"
                  (json:make-json-object
                   (append (list (cons "kind"
                                       (obj "const" (lowercase kind)
                                            "description"
                                            "The node kind; picks this definition out."))
                                 (cons "span" (ref "span")))
                           (loop for field in fields
                                 collect (cons (lowercase (model:field-name field))
                                               (field-schema field registry))))))
            (cons "required" (arr required))
            (cons "additionalProperties" :false))
      (when (and (model:node-declaration-example-p declaration)
                 (model:node-declaration-example declaration))
        (list (cons "examples"
                    (arr (list (node-example-json
                                (model:node-declaration-example declaration)
                                registry))))))))))

(defun enum-schema (enum)
  "The $defs entry of ENUM: a oneOf of its values, each with its meaning."
  (json:make-json-object
   (append
    (list (cons "title" (lowercase (model:definition-name enum))))
    (with-description '() (model:definition-doc enum))
    (list (cons "oneOf"
                (arr (loop for (value doc) in (model:enum-values enum)
                           collect (json:make-json-object
                                    (with-description
                                        (list (cons "const" (lowercase value)))
                                      doc)))))))))

(defun target-schema (target)
  "The $defs entry of the target kind TARGET: a kind and an id."
  (json:make-json-object
   (append
    (list (cons "type" "object")
          (cons "title" (lowercase (model:definition-name target))))
    (with-description '() (model:definition-doc target))
    (list (cons "properties"
                (obj "kind" (obj "const" (lowercase (model:definition-name target))
                                 "description"
                                 "The target kind: which sort of node the id names.")
                     "id" (obj "type" "string"
                               "description"
                               "The id of the node pointed to, unique among its target kind.")))
          (cons "required" (arr '("kind" "id")))
          (cons "additionalProperties" :false)))))

(defun builtin-definitions (registry)
  "The definitions every schema has: the span, and the text object unless
REGISTRY declares a node kind :TEXT."
  (append
   (list (cons "span"
               (obj "type" "object"
                    "title" "span"
                    "description"
                    "Where a node came from in the sources: a file, character offsets (end exclusive), a line from 1 and a column from 0."
                    "properties"
                    (obj "file" (obj "type" "string"
                                     "description" "The source file name, without directory.")
                         "start" (obj "type" "integer"
                                      "description" "Character offset of the first character.")
                         "end" (obj "type" "integer"
                                    "description" "Character offset after the last character.")
                         "line" (obj "type" "integer"
                                     "description" "Line of the first character, counted from 1.")
                         "column" (obj "type" "integer"
                                       "description" "Column of the first character, counted from 0."))
                    "required" (arr '("file" "start" "end" "line" "column"))
                    "additionalProperties" :false)))
   (unless (model:find-node-declaration :text registry)
     (list (cons "text"
                 (obj "type" "object"
                      "title" "text"
                      "description"
                      "A run of plain text; adjacent text is merged into one object."
                      "properties"
                      (obj "kind" (obj "const" "text"
                                       "description" "The node kind.")
                           "text" (obj "type" "string"
                                       "description" "The text."))
                      "required" (arr '("kind" "text"))
                      "additionalProperties" :false))))))

(defun model-schema (&optional (registry model:*registry*))
  "The JSON Schema (a JSON value, see cl-ansi-spec/json) of every node of
REGISTRY: any node kind may be the root."
  (let ((problems (model:registry-problems registry)))
    (when problems
      (error "The registry is inconsistent: ~{~A~^ ~}" problems)))
  (json:make-json-object
   (list (cons "$schema" +schema-draft+)
         (cons "title" "cl-ansi-spec document model")
         (cons "description"
               "The semantic model of the standard, one definition per node kind. Generated from the node declarations (make generate); do not edit.")
         (cons "oneOf"
               (arr (loop for kind in (model:node-kinds registry)
                          collect (ref (lowercase kind)))))
         (cons "$defs"
               (json:make-json-object
                (append
                 (builtin-definitions registry)
                 (loop for enum in (model:enums registry)
                       collect (cons (format nil "enum-~A" (lowercase (model:definition-name enum)))
                                     (enum-schema enum)))
                 (loop for target in (model:target-kinds registry)
                       collect (cons (format nil "target-~A" (lowercase (model:definition-name target)))
                                     (target-schema target)))
                 (loop for kind in (model:node-kinds registry)
                       collect (cons (lowercase kind)
                                     (node-schema (model:find-node-declaration kind registry)
                                                  registry)))))))))

(defun model-schema-text (&optional (registry model:*registry*))
  "The text of schema/model.schema.json for REGISTRY."
  (json:write-json-to-string (model-schema registry)))

;;; Checks the suite makes

(defun schema-undescribed (schema)
  "What in the generated SCHEMA lacks a description, as the items
UNDOCUMENTED-ITEMS reports for docstrings: (:DOC :NODE kind), (:DOC
:FIELD kind field), (:DOC :ENUM name), (:DOC :ENUM-VALUE name value),
(:DOC :TARGET-KIND name).  The built-in definitions are always described."
  (let ((items '()))
    (flet ((described-p (object) (nth-value 1 (json:json-get object "description")))
           (key (string) (intern (string-upcase string) '#:keyword))
           (prefixed-p (prefix name)
             (and (> (length name) (length prefix))
                  (string= prefix name :end2 (length prefix)))))
      (loop for (name . definition) in (json:json-object-members (json:json-get schema "$defs"))
            do (cond
                 ((member name '("span" "text") :test #'string=))
                 ((prefixed-p "enum-" name)
                  (let ((enum (key (subseq name 5))))
                    (unless (described-p definition)
                      (push (list :doc :enum enum) items))
                    (loop for alternative across (json:json-get definition "oneOf")
                          unless (described-p alternative)
                            do (push (list :doc :enum-value enum
                                           (key (json:json-get alternative "const")))
                                     items))))
                 ((prefixed-p "target-" name)
                  (unless (described-p definition)
                    (push (list :doc :target-kind (key (subseq name 7))) items)))
                 (t
                  (unless (described-p definition)
                    (push (list :doc :node (key name)) items))
                  (loop for (field . property)
                          in (json:json-object-members (json:json-get definition "properties"))
                        unless (or (described-p property)
                                   (member field '("kind" "span") :test #'string=))
                          do (push (list :doc :field (key name) (key field)) items))))))
    (nreverse items)))

(defun schema-outside-subset (schema)
  "The places in SCHEMA that use a keyword outside the subset of
docs/exports.md, \"Validation\", as strings \"pointer: keyword\", and the
\"type\" values that are no JSON type."
  (let ((problems '()))
    (labels ((walk (value pointer)
               (when (json:json-object-p value)
                 (loop for (key . child) in (json:json-object-members value)
                       for here = (format nil "~A/~A" pointer key)
                       do (cond
                            ((member key '("properties" "$defs") :test #'string=)
                             (loop for (name . definition)
                                     in (json:json-object-members child)
                                   do (walk definition (format nil "~A/~A" here name))))
                            ((member key *annotation-keywords* :test #'string=))
                            ((not (member key *subset-keywords* :test #'string=))
                             (push (format nil "~A: ~A" pointer key) problems))
                            ((string= key "items") (walk child here))
                            ((string= key "oneOf")
                             (loop for alternative across child for i from 0
                                   do (walk alternative (format nil "~A/~D" here i))))
                            ((and (string= key "type")
                                  (not (member child '("string" "integer" "boolean"
                                                       "object" "array" "null")
                                               :test #'equal)))
                             (push (format nil "~A: type ~S" pointer child) problems)))))))
      (walk schema ""))
    (nreverse problems)))

(define-generator model-schema "schema/model.schema.json" 'model-schema-text)
