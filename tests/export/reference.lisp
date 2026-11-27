;;;; tests/export/reference.lisp
;;;;
;;;; Tests of the reference doc generator (src/export/reference.lisp).
;;;; The layout is checked on fixture declarations in a registry of
;;;; their own, so it does not depend on the kinds the model declares;
;;;; the real reference is checked only for having a section per kind.
;;;; Owner: step 3.5 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/tests)

(defvar *reference-fixtures* (model:make-registry)
  "The declarations the reference doc's tests read, apart from the model's.")

(model:define-category :ref-block (:area :entries :registry *reference-fixtures*)
  "Block kinds of the fixture.")

(model:define-enum ref-fixture-mode (:area :entries :registry *reference-fixtures*)
  "How the fixture is kept."
  (:fast "Kept in memory.")
  (:slow))

(model:define-target-kind :ref-target (:area :entries :node :ref-fixture-entry
                                       :registry *reference-fixtures*)
  "Points at an entry.")

(model:define-node ref-fixture-entry
    (:area :entries :categories (:ref-block)
     :example (:ref-fixture-entry :title "Fixture")
     :registry *reference-fixtures*)
  "A fixture entry."
  (title :string :required t :doc "The title | with a pipe.")
  (mode (:enum ref-fixture-mode) :required t :doc "How kept.")
  (parts (:node :ref-fixture-part) :repeated t :doc "Its parts.")
  (points-to (:target :ref-target) :doc "What it points at."))

(model:define-node ref-fixture-part (:area :entries :registry *reference-fixtures*)
  "A part."
  (text :string :required t :doc "Its text."))

(model:define-node ref-fixture-bare (:area :structure :registry *reference-fixtures*)
  (value :integer))

(defun reference-lines (&rest lines)
  "LINES joined, each followed by a newline: the text a Markdown block is."
  (format nil "~{~A~%~}" lines))

(define-test reference-doc
  :parent exports
  :description "The reference doc generator (src/export/reference.lisp).")

(define-test reference-doc-generator
  :parent reference-doc
  ;; The generator is registered under its file, in the default registry.
  (let ((generator (find 'exports::reference (exports:generators)
                         :key #'exports:generator-name)))
    (true generator "The reference generator is registered")
    (is equal "docs/model-reference.md" (exports:generator-path generator)
        "The reference is written to docs/model-reference.md")))

(define-test reference-doc-sections
  :parent reference-doc
  ;; The sections of the fixture's entries area, golden: node kinds in
  ;; declaration order, then enumerations, target kinds and categories.
  (let* ((text (exports:reference-text *reference-fixtures*))
         (start (search "## Entries" text))
         (end (search "## Blocks" text)))
    (true (and start end (< start end)) "The entries and blocks sections")
    (is string= (reference-lines
                 "## Entries"
                 ""
                 "### Node kind `:ref-fixture-entry`"
                 ""
                 "A fixture entry."
                 ""
                 "Categories: `:ref-block`."
                 ""
                 "| Field | Type | Required | Description |"
                 "|---|---|---|---|"
                 "| `title` | string | yes | The title \\| with a pipe. |"
                 "| `mode` | enumeration `ref-fixture-mode` | yes | How kept. |"
                 "| `parts` | list of node of kind or category `:ref-fixture-part` | no | Its parts. |"
                 "| `points-to` | reference (target `:ref-target`) | no | What it points at. |"
                 ""
                 "Example:"
                 ""
                 "```lisp"
                 "(:ref-fixture-entry :title \"Fixture\")"
                 "```"
                 ""
                 "### Node kind `:ref-fixture-part`"
                 ""
                 "A part."
                 ""
                 "| Field | Type | Required | Description |"
                 "|---|---|---|---|"
                 "| `text` | string | yes | Its text. |"
                 ""
                 "### Enumeration `ref-fixture-mode`"
                 ""
                 "How the fixture is kept."
                 ""
                 "- `:fast` - Kept in memory."
                 "- `:slow` - _No description yet._"
                 ""
                 "### Target kind `:ref-target`"
                 ""
                 "Points at an entry."
                 ""
                 "A reference of this kind points to a node of kind `:ref-fixture-entry`."
                 ""
                 "### Category `:ref-block`"
                 ""
                 "Block kinds of the fixture."
                 ""
                 "Kinds: `:ref-fixture-entry`."
                 "")
            (subseq text start end)
            "The entries section of the fixture")))

(define-test reference-doc-undocumented
  :parent reference-doc
  ;; A kind, field or enumeration value without a docstring says so, and
  ;; a kind without fields says so too.
  (let ((text (exports:reference-text *reference-fixtures*)))
    (true (search (reference-lines
                   "### Node kind `:ref-fixture-bare`"
                   ""
                   "_No description yet._"
                   ""
                   "| Field | Type | Required | Description |"
                   "|---|---|---|---|"
                   "| `value` | integer | no | _No description yet._ |"
                   "")
                  text)
          "The bare kind is listed with its undocumented field")))

(define-test reference-doc-empty
  :parent reference-doc
  ;; An area without declarations says so: every area has a section.
  (let ((text (exports:reference-text (model:make-registry))))
    (dolist (area model:*areas*)
      (true (search (format nil "## ~A~%~%_No declarations yet._~%~%"
                            (exports::area-title area))
                    text)
            "Every area has a section, empty or not"))))

(define-test reference-doc-real-model
  :parent reference-doc
  ;; The reference of the model has a section for every area, and a
  ;; heading for every node kind, enumeration, target kind and category
  ;; it declares (none is missing, none is extra).
  (let* ((text (exports:reference-text))
         (marker (format nil "~%### "))
         (headings (loop for pos = (search marker text)
                           then (search marker text :start2 (1+ pos))
                         while pos count t)))
    (dolist (area model:*areas*)
      (true (search (format nil "## ~A~%" (exports::area-title area)) text)
            "Every area has a section"))
    (is = (+ (length (model:node-kinds)) (length (model:enums))
             (length (model:target-kinds)) (length (model:categories)))
        headings
        "One heading per declaration")))
