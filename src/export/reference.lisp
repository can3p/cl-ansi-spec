;;;; src/export/reference.lisp
;;;;
;;;; The reference doc generator: docs/model-reference.md from the node
;;;; registry (docs/exports.md, "Documentation of every definition").
;;;; Every node kind, enumeration, target kind and category declared
;;;; with cl-ansi-spec/model is listed under its area, with its
;;;; docstring; a node kind also gets its field table (type, required,
;;;; description) and its example.  Registered as the generator
;;;; `reference' (`make generate'); the suite fails while the file is
;;;; stale (tests/export/generate.lisp) and checks the layout on fixture
;;;; declarations (tests/export/reference.lisp).

(in-package #:cl-ansi-spec/export)

;;; Text helpers

(defparameter *reference-whitespace* '(#\Space #\Tab #\Newline #\Return)
  "The characters one-line text is made of, where runs collapse.")

(defun one-line (text)
  "TEXT (a string, or NIL) with each run of white space made one space,
and its ends trimmed: the form a table cell takes."
  (let ((out (make-string-output-stream))
        (pending nil)
        (started nil))
    (loop for char across (or text "")
          do (if (member char *reference-whitespace*)
                 (when started (setf pending t))
                 (progn
                   (when pending (write-char #\Space out))
                   (setf pending nil started t)
                   (write-char char out))))
    (get-output-stream-string out)))

(defun table-cell (text)
  "TEXT (a string, or NIL) on one line, with its pipes escaped."
  (with-output-to-string (out)
    (loop for char across (one-line text)
          do (when (char= char #\|) (write-char #\\ out))
             (write-char char out))))

(defun doc-paragraph (doc)
  "DOC (a docstring, or NIL) as Markdown, its ends trimmed."
  (let ((text (string-trim *reference-whitespace* (or doc ""))))
    (if (string= text "")
        "_No description yet._"
        text)))

(defun keyword-text (keyword)
  "KEYWORD as code, lower case: `:glossary-entry`."
  (format nil "`:~(~A~)`" (symbol-name keyword)))

(defun keyword-list-text (keywords)
  "KEYWORDS as code, comma separated, or NIL when there are none."
  (when keywords
    (format nil "~{~A~^, ~}" (mapcar #'keyword-text keywords))))

(defun lisp-text (value)
  "VALUE as the S-expression it is written as: symbols of the keyword
package, lower case, pretty printed, so that the text does not depend on
the package the generator runs in."
  (let ((*package* (find-package '#:keyword))
        (*print-pretty* t)
        (*print-right-margin* 72)
        (*print-case* :downcase)
        (*print-circle* nil)
        (*print-readably* nil)
        (*print-length* nil)
        (*print-level* nil)
        (*print-lines* nil)
        (*print-base* 10)
        (*print-radix* nil))
    (with-output-to-string (out)
      (prin1 value out))))

;;; Field types

(defun field-type-text (type)
  "TYPE (see FIELD-TYPE-P) as the words a field table gives it."
  (cond ((eq type :string) "string")
        ((eq type :integer) "integer")
        ((eq type :boolean) "boolean")
        ((eq type :span) "span")
        ((eq type :inlines) "inline list")
        ((not (consp type)) (error "Not a field type: ~S." type))
        ((eq (first type) :enum)
         (format nil "enumeration `~(~A~)`" (symbol-name (second type))))
        ((eq (first type) :node)
         (format nil "node of kind or category ~A" (keyword-list-text (rest type))))
        ((eq (first type) :target)
         (format nil "reference (target ~A)" (keyword-list-text (rest type))))
        (t (error "Not a field type: ~S." type))))

(defun field-type-cell (field)
  "The type column of FIELD: a list when it is repeated."
  (if (field-repeated field)
      (format nil "list of ~A" (field-type-text (field-type field)))
      (field-type-text (field-type field))))

;;; Sections

(defun write-node-section (declaration out)
  "Write the section of the node kind DECLARATION to OUT."
  (let ((kind (node-declaration-kind declaration))
        (fields (node-declaration-fields declaration)))
    (format out "~&### Node kind ~A~%~%" (keyword-text kind))
    (format out "~A~%~%" (doc-paragraph (definition-doc declaration)))
    (when (node-declaration-categories declaration)
      (format out "Categories: ~A.~%~%"
              (keyword-list-text (node-declaration-categories declaration))))
    (if (null fields)
        (format out "_No fields._~%~%")
        (progn
          (format out "| Field | Type | Required | Description |~%")
          (format out "|---|---|---|---|~%")
          (dolist (field fields)
            (format out "| `~(~A~)` | ~A | ~:[no~;yes~] | ~A |~%"
                    (symbol-name (field-name field))
                    (table-cell (field-type-cell field))
                    (field-required field)
                    (table-cell (doc-paragraph (field-doc field)))))
          (terpri out)))
    (when (node-declaration-example-p declaration)
      (format out "Example:~%~%```lisp~%~A~%```~%~%"
              (lisp-text (node-declaration-example declaration))))))

(defun write-enum-section (enum out)
  "Write the section of the enumeration ENUM to OUT."
  (format out "~&### Enumeration `~(~A~)`~%~%"
          (symbol-name (definition-name enum)))
  (format out "~A~%~%" (doc-paragraph (definition-doc enum)))
  (dolist (value (enum-values enum))
    (destructuring-bind (keyword doc) value
      (format out "- ~A - ~A~%" (keyword-text keyword) (doc-paragraph doc))))
  (terpri out))

(defun write-target-section (target out)
  "Write the section of the target kind TARGET to OUT."
  (format out "~&### Target kind ~A~%~%"
          (keyword-text (definition-name target)))
  (format out "~A~%~%" (doc-paragraph (definition-doc target)))
  (format out "A reference of this kind points to a node of kind ~A.~%~%"
          (keyword-text (target-kind-node target))))

(defun write-category-section (category registry out)
  "Write the section of the category CATEGORY, its kinds in REGISTRY, to OUT."
  (format out "~&### Category ~A~%~%"
          (keyword-text (definition-name category)))
  (format out "~A~%~%" (doc-paragraph (definition-doc category)))
  (format out "Kinds: ~A.~%~%"
          (or (keyword-list-text (category-kinds (definition-name category) registry))
              "none yet")))

(defun area-title (area)
  "The heading of AREA in the reference doc."
  (or (cdr (assoc area '((:structure . "Structure") (:entries . "Entries")
                         (:blocks . "Blocks") (:tables . "Tables")
                         (:inlines . "Inlines") (:glossary . "Glossary")
                         (:bnf . "BNF") (:math . "Math"))))
      (error "No heading for the area ~S." area)))

(defun write-area-section (area registry out)
  "Write the section of AREA, with the declarations of REGISTRY in it,
to OUT: node kinds, enumerations, target kinds, then categories, each in
declaration order."
  (format out "~&## ~A~%~%" (area-title area))
  (let ((nodes (remove-if-not (lambda (kind)
                                (eq area (definition-area
                                          (find-node-declaration kind registry))))
                              (node-kinds registry)))
        (enums (remove-if-not (lambda (enum) (eq area (definition-area enum)))
                              (enums registry)))
        (targets (remove-if-not (lambda (target) (eq area (definition-area target)))
                                (target-kinds registry)))
        (categories (remove-if-not (lambda (category)
                                     (eq area (definition-area category)))
                                   (categories registry))))
    (if (not (or nodes enums targets categories))
        (format out "_No declarations yet._~%~%")
        (progn
          (dolist (kind nodes)
            (write-node-section (find-node-declaration kind registry) out))
          (dolist (enum enums) (write-enum-section enum out))
          (dolist (target targets) (write-target-section target out))
          (dolist (category categories)
            (write-category-section category registry out))))))

(defun reference-text (&optional (registry *registry*))
  "The text of docs/model-reference.md, from the declarations of REGISTRY
(the model's by default): one section per area, in *AREAS* order."
  (with-output-to-string (out)
    (format out "~A~%~%"
            "<!-- Generated by make generate from the node declarations in src/model/ (src/export/reference.lisp). Do not edit: make test fails while this file is stale. -->")
    (format out "# Model reference~%~%")
    (format out "~A~%~%"
            "This is the reference of the document model: every node kind, enumeration, target kind and category declared with the model's declaration forms, by area. Field names are their JSON names. A required field is present in every node of its kind. Examples are written as S-expressions.")
    (dolist (area *areas*)
      (write-area-section area registry out))))

(define-generator reference "docs/model-reference.md" #'reference-text)
