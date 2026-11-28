;;;; src/model/print.lisp
;;;;
;;;; A generic S-expression printer of nodes over the registry: a node is
;;;; written (kind :field value ... :span span), its fields in the order
;;;; of its declaration, as docs/model.md writes nodes.  Used by `make
;;;; model' and the tests; the export writers are in cl-ansi-spec/export.

(in-package #:cl-ansi-spec/model)

(defun span-sexp (span &optional (style :full))
  "SPAN as a list: (file start end line column) when STYLE is :FULL, as
the S-expression export writes it (docs/exports.md, \"JSON shape\"), or
(file line) when STYLE is :LINE, as docs/model.md shortens it."
  (ecase style
    (:full (list (span-file span) (span-start span) (span-end span)
                 (span-line span) (span-column span)))
    (:line (list (span-file span) (span-line span)))))

(defun value-sexp (value registry spans)
  "VALUE, a field's value, as an S-expression: a node as NODE-SEXP
writes it, a target as (kind id), a span as SPAN-SEXP writes it in the
style SPANS, a list item by item, anything else as it is."
  (typecase value
    (node (node-sexp value :registry registry :spans spans))
    (target (list (target-kind value) (target-id value)))
    (span (span-sexp value spans))
    (cons (mapcar (lambda (item) (value-sexp item registry spans)) value))
    (t value)))

(defun node-sexp (node &key (registry *registry*) (spans :full))
  "NODE as an S-expression, (kind :field value ...), its fields in the
order of its declaration in REGISTRY, those without a value (NIL, false
or an empty list) left out, then its :SPAN in the style SPANS (see
SPAN-SEXP; NIL leaves spans out)."
  (append (list (node-kind node))
          (loop for field in (node-fields (node-kind node) registry)
                for value = (node-field-value node field registry)
                when value
                  append (list (keyword-of (field-name field))
                               (value-sexp value registry spans)))
          (and spans (node-span node)
               (list :span (span-sexp (node-span node) spans)))))

(defun print-node (item &key (stream *standard-output*) (registry *registry*)
                             (spans :full))
  "Print ITEM, a node (as NODE-SEXP makes it, with REGISTRY and SPANS)
or a string, on STREAM, readably and pretty-printed, keywords in lower
case, followed by a newline."
  (with-standard-io-syntax
    (let ((*print-case* :downcase)
          (*print-pretty* t)
          (*print-right-margin* 100)
          (*print-readably* nil))
      (prin1 (if (stringp item) item (node-sexp item :registry registry :spans spans))
             stream)
      (terpri stream))))
