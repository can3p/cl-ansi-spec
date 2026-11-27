;;;; src/export/package.lisp
;;;;
;;;; Phase 5, the exports (docs/exports.md): the generated files (JSON
;;;; Schema, reference doc), the schema validator and the S-expression
;;;; and JSON writers, all driven by the node registry of
;;;; cl-ansi-spec/model.  Owner: 3.0; each step of docs/plan/m3.md adds
;;;; the imports and exports of the files it owns.

(defpackage #:cl-ansi-spec/export
  (:use #:cl)
  (:local-nicknames (#:model #:cl-ansi-spec/model)
                    (#:json #:cl-ansi-spec/json))
  (:import-from #:cl-ansi-spec/json
                #:json-object-p #:json-object-members #:json-get)
  ;; The declarations the reference doc reads (reference.lisp)
  (:import-from #:cl-ansi-spec/model
   #:*registry* #:*areas* #:node-kinds #:find-node-declaration
   #:node-declaration-kind #:node-declaration-fields
   #:node-declaration-categories #:node-declaration-example
   #:node-declaration-example-p #:definition-name #:definition-area
   #:definition-doc #:field-name #:field-type #:field-required
   #:field-repeated #:field-doc #:enums #:enum-values #:target-kinds
   #:target-kind-node #:categories #:category-kinds)
  (:export
   ;; Generated files (generate.lisp)
   #:define-generator #:generators #:generator-name #:generator-path
   #:generator-thunk #:generated-text #:write-generated-files
   #:stale-generated-files
   ;; The reference doc (reference.lisp)
   #:reference-text
   ;; JSON Schema generator (schema.lisp)
   #:model-schema #:model-schema-text #:schema-undescribed
   #:schema-outside-subset
   ;; Schema validator (validate.lisp)
   #:validate-json #:json-valid-p #:schema-subset-violations
   #:validation-error #:validation-error-pointer #:validation-error-message
   #:unsupported-schema-keyword #:unsupported-schema-keyword-pointer
   #:unsupported-schema-keyword-keyword
   #:unresolved-schema-reference #:unresolved-schema-reference-reference
   #:circular-schema-reference #:circular-schema-reference-reference))
