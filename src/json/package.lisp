;;;; src/json/package.lisp
;;;;
;;;; A small JSON reader and writer (RFC 8259) with no dependency.  Used by
;;;; the exports, the schema generator and the validator (docs/exports.md,
;;;; "JSON shape").  Not a phase of the pipeline: it knows nothing of TeX.
;;;;
;;;; Lisp representation of a JSON value:
;;;;   object  -> (:object (key . value) ...)   keys are strings, order kept
;;;;   array   -> a simple-vector
;;;;   string  -> a string
;;;;   number  -> an integer (the model has no floats; a float is an error)
;;;;   true, false, null -> :true, :false, :null

(defpackage #:cl-ansi-spec/json
  (:use #:cl)
  (:export
   #:json-error #:json-parse-error #:json-parse-error-position
   #:json-write-error
   #:make-json-object #:json-object-p #:json-object-members #:json-get
   #:parse-json #:read-json #:parse-json-file
   #:write-json #:write-json-to-string #:write-json-file))
