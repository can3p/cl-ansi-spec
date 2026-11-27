;;;; src/export/package.lisp
;;;;
;;;; Phase 5, the exports (docs/exports.md): the generated files (JSON
;;;; Schema, reference doc), the schema validator and the S-expression
;;;; and JSON writers, all driven by the node registry of
;;;; cl-ansi-spec/model.  Owner: 3.0; each step of docs/plan/m3.md adds
;;;; the imports and exports of the files it owns.

(defpackage #:cl-ansi-spec/export
  (:use #:cl)
  (:export
   ;; Generated files (generate.lisp)
   #:define-generator #:generators #:generator-name #:generator-path
   #:generator-thunk #:generated-text #:write-generated-files
   #:stale-generated-files))
