;;;; src/model/package.lisp
;;;;
;;;; Phase 4, the model builder (docs/architecture.md, docs/model.md):
;;;; the node declarations (define-node and the registry), the builder
;;;; that turns the event streams of the chapter jobs into the document
;;;; model, and the resolution of its references.  Owner: 3.0; each step
;;;; of docs/plan/m3.md adds the exports of the files it owns.

(defpackage #:cl-ansi-spec/model
  (:use #:cl)
  (:export
   ;; The ownership table (owners.lisp)
   #:load-owners #:owners #:owner #:owner-step #:owner-file
   #:owner-vocabulary #:owner-events #:owner-why))
