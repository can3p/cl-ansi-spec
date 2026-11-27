;;;; tests/export/schema.lisp
;;;;
;;;; Tests of the JSON Schema generator (src/export/schema.lisp), on kinds
;;;; declared here in a registry of their own, and on the model's registry.
;;;; Owner: step 3.4 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/tests)

(defvar *schema-registry* (model:make-registry)
  "The registry of the kinds these tests declare.")

(model:define-category :block (:area :blocks :registry *schema-registry*)
  "A block.")
(model:define-category :inline (:area :inlines :registry *schema-registry*)
  "An inline.")

(model:define-enum flavor (:area :entries :registry *schema-registry*)
  "The flavors of an entry."
  (:function "A function.")
  (:macro))

(model:define-target-kind :glossary (:area :glossary :node :term
                                     :registry *schema-registry*)
  "A glossary term, by its id.")

(model:define-node term (:area :glossary :registry *schema-registry*
                         :example (:term :id "list"))
  "A glossary term."
  (id :string :required t :doc "Its id." :example "list"))

(model:define-node emphasis (:area :inlines :categories (:inline)
                             :registry *schema-registry*)
  "Emphasised text."
  (text :inlines :doc "What is emphasised." :example ("x")))

(model:define-node entry (:area :entries :categories (:block)
                          :registry *schema-registry*
                          :example (:entry :id "endp" :flavor :function
                                    :see (:glossary "list")
                                    :parts ((:emphasis :text ("a " (:emphasis :text ("b")))))))
  "A dictionary entry."
  (id :string :required t :doc "Its id." :example "endp")
  (flavor (:enum flavor) :required t :doc "Its flavor." :example :function)
  (count :integer :doc "A number.")
  (flag :boolean)
  (parts (:node :inline :block) :repeated t :doc "Its parts." :example ())
  (text :inlines :doc "Its text.")
  (see (:target :glossary) :doc "A reference." :example nil))

(defun schema-of-tests ()
  (exports:model-schema *schema-registry*))

(defun schema-path (value &rest keys)
  "The member of the JSON VALUE reached through KEYS (strings or indexes)."
  (dolist (key keys value)
    (setf value (if (integerp key)
                    (aref value key)
                    (json:json-get value key)))))

(define-test schema
  :parent exports
  :description "The JSON Schema generator.")

(define-test schema-shape
  :parent schema
  (let ((schema (schema-of-tests)))
    (is string= "https://json-schema.org/draft/2020-12/schema"
        (schema-path schema "$schema"))
    (is equal '("span" "text" "enum-flavor" "target-glossary" "term" "emphasis" "entry")
        (mapcar #'car (json:json-object-members (schema-path schema "$defs"))))
    (is equalp #("#/$defs/term" "#/$defs/emphasis" "#/$defs/entry")
        (map 'vector (lambda (alternative) (schema-path alternative "$ref"))
             (schema-path schema "oneOf")))
    ;; A node kind: constant kind, closed, required fields, example.
    (let ((entry (schema-path schema "$defs" "entry")))
      (is string= "A dictionary entry." (schema-path entry "description"))
      (is eq :false (schema-path entry "additionalProperties"))
      (is equalp #("kind" "span" "id" "flavor" "see") (schema-path entry "required"))
      (is string= "entry" (schema-path entry "properties" "kind" "const"))
      (is string= "#/$defs/span" (schema-path entry "properties" "span" "$ref"))
      (is string= "integer" (schema-path entry "properties" "count" "type"))
      (is string= "boolean" (schema-path entry "properties" "flag" "type"))
      (is string= "#/$defs/enum-flavor" (schema-path entry "properties" "flavor" "$ref"))
      (is string= "Its id." (schema-path entry "properties" "id" "description"))
      (is equalp #("endp") (schema-path entry "properties" "id" "examples")))))

(define-test schema-field-types
  :parent schema
  (let ((entry (schema-path (schema-of-tests) "$defs" "entry")))
    ;; Several kinds and categories: one oneOf, repeated: an array of it.
    (let ((parts (schema-path entry "properties" "parts")))
      (is string= "array" (schema-path parts "type"))
      (is equalp #("#/$defs/emphasis" "#/$defs/entry")
          (map 'vector (lambda (a) (schema-path a "$ref"))
               (schema-path parts "items" "oneOf")))
      (is equalp #(#()) (schema-path parts "examples")))
    ;; Inlines: text objects and the inline kinds.
    (let ((text (schema-path entry "properties" "text")))
      (is string= "array" (schema-path text "type"))
      (is equalp #("#/$defs/text" "#/$defs/emphasis")
          (map 'vector (lambda (a) (schema-path a "$ref"))
               (schema-path text "items" "oneOf"))))
    ;; A target: the target kind or null; the example nil is null.
    (let ((see (schema-path entry "properties" "see")))
      (is equalp #("#/$defs/target-glossary" nil)
          (map 'vector (lambda (a) (json:json-get a "$ref")) (schema-path see "oneOf")))
      (is equalp #(:null) (schema-path see "examples")))))

(define-test schema-definitions
  :parent schema
  (let* ((schema (schema-of-tests))
         (enum (schema-path schema "$defs" "enum-flavor"))
         (target (schema-path schema "$defs" "target-glossary")))
    ;; An enumeration: each value keeps its meaning (a value without one
    ;; has none to keep).
    (is string= "function" (schema-path enum "oneOf" 0 "const"))
    (is string= "A function." (schema-path enum "oneOf" 0 "description"))
    (is equal '(("const" . "macro")) (json:json-object-members (schema-path enum "oneOf" 1)))
    (is string= "glossary" (schema-path target "properties" "kind" "const"))
    (is equalp #("kind" "id") (schema-path target "required"))))

(define-test schema-examples
  :parent schema
  (let ((example (schema-path (schema-of-tests) "$defs" "entry" "examples" 0)))
    (is equal '("kind" "id" "flavor" "see" "parts")
        (mapcar #'car (json:json-object-members example)))
    (is string= "function" (schema-path example "flavor"))
    (is equal '(("kind" . "glossary") ("id" . "list"))
        (json:json-object-members (schema-path example "see")))
    ;; Strings of inlines become text objects.
    (is equal '(("kind" . "text") ("text" . "a "))
        (json:json-object-members (schema-path example "parts" 0 "text" 0)))
    (is string= "emphasis" (schema-path example "parts" 0 "text" 1 "kind")))
  ;; An example that does not fit its kind is an error, not a silent gap.
  (let ((registry (model:make-registry)))
    (eval `(model:define-node bad (:area :blocks :registry ,registry
                                   :example (:bad :nowhere 1))
             "A bad one."))
    (fail (exports:model-schema registry))))

(define-test schema-text
  :parent schema
  (let ((text (exports:model-schema-text *schema-registry*)))
    (true (char= #\Newline (char text (1- (length text)))))
    (is string= text (exports:model-schema-text *schema-registry*))
    (is equalp (exports:model-schema *schema-registry*)
        (json:parse-json text))))

(define-test schema-registry-errors
  :parent schema
  ;; A field naming a kind nobody declares stops the generator.
  (let ((registry (model:make-registry)))
    (eval `(model:define-node dangling (:area :blocks :registry ,registry)
             "Points nowhere."
             (child (:node :missing))))
    (fail (exports:model-schema registry))))

(defun sort-items (items)
  "ITEMS in a fixed order, to compare lists made in different orders."
  (sort (copy-list items) #'string< :key #'prin1-to-string))

(define-test schema-undescribed
  :parent schema
  ;; What lacks a description is what UNDOCUMENTED-ITEMS lists as lacking a doc.
  (let ((registry (model:make-registry)))
    (eval `(progn
             (model:define-enum shade (:area :entries :registry ,registry)
               (:dark) (:light "Light."))
             (model:define-target-kind :tint (:area :entries :node :paint
                                              :registry ,registry))
             (model:define-node paint (:area :entries :registry ,registry)
               (name :string :doc "Its name.")
               (shade (:enum shade))
               (via (:target :tint)))))
    (is equal '((:doc :enum :shade) (:doc :enum-value :shade :dark)
                (:doc :target-kind :tint) (:doc :node :paint)
                (:doc :field :paint :shade) (:doc :field :paint :via))
        (exports:schema-undescribed (exports:model-schema registry)))
    (is equal (sort-items (remove-if-not (lambda (item) (eq :doc (first item)))
                                         (model:undocumented-items :entries registry)))
        (sort-items (exports:schema-undescribed (exports:model-schema registry))))))

(define-test schema-outside-subset
  :parent schema
  (is equal '() (exports:schema-outside-subset (schema-of-tests)))
  (is equal '("/$defs/x: minLength" "/$defs/y: type \"float\"")
      (exports:schema-outside-subset
       (json:parse-json "{\"$defs\": {\"x\": {\"minLength\": 1}, \"y\": {\"type\": \"float\"}}}"))))

;;; The model's own schema, whatever the registry holds

(define-test model-schema-current
  :parent schema
  ;; The committed schema is checked by generated-files-current.  Here: it
  ;; stays in the subset, and describes everything the ratchet does not list.
  (let ((schema (exports:model-schema)))
    (is equal '() (exports:schema-outside-subset schema))
    (is equal (sort-items (loop for area in model:*areas*
                                append (remove-if-not
                                        (lambda (item) (eq :doc (first item)))
                                        (model:undocumented-items area))))
        (sort-items (exports:schema-undescribed schema)))))
