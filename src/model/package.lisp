;;;; src/model/package.lisp
;;;;
;;;; Phase 4, the model builder (docs/architecture.md, docs/model.md):
;;;; the node declarations (define-node and the registry), the builder
;;;; that turns the event streams of the chapter jobs into the document
;;;; model, and the resolution of its references.  Owner: 3.0; each step
;;;; of docs/plan/m3.md adds the exports of the files it owns.

(defpackage #:cl-ansi-spec/model
  (:use #:cl)
  (:import-from #:cl-ansi-spec/tex #:span)
  (:export
   ;; The ownership table (owners.lisp)
   #:load-owners #:owners #:owner #:owner-step #:owner-file
   #:owner-vocabulary #:owner-events #:owner-why
   ;; Declarations and the registry (define-node.lisp)
   #:declaration-error
   #:*areas* #:define-node #:define-enum #:define-target-kind #:define-category
   #:node #:node-kind #:node-span #:node-field-value #:make-node #:find-field
   #:registry #:make-registry #:*registry*
   #:definition-name #:definition-area #:definition-doc
   #:node-declaration #:node-declaration-kind #:node-declaration-categories
   #:node-declaration-fields #:node-declaration-example
   #:node-declaration-example-p
   #:field #:field-name #:field-type #:field-required #:field-repeated
   #:field-doc #:field-example #:field-example-p #:field-type-p
   #:enum #:enum-values #:target-kind-declaration #:target-kind-node #:category
   #:node-kinds #:find-node-declaration #:node-fields
   #:enums #:find-enum #:target-kinds #:find-target-kind
   #:categories #:find-category #:category-kinds #:expand-kinds
   #:registry-problems #:node-problems
   #:target #:make-target #:target-p #:target-kind #:target-id
   #:undocumented-items))
