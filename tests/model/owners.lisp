;;;; tests/model/owners.lisp
;;;;
;;;; The model builder's suite, and its ownership table
;;;; (src/model/owners.sexp): every vocabulary key and every event kind
;;;; of docs/events.md has exactly one owner, whose handler file exists.
;;;; Owner: step 3.0.

(in-package #:cl-ansi-spec/tests)

(define-test model
  :parent cl-ansi-spec
  :description "Phase 4, the model builder.")

(defparameter *event-kinds*
  '(:text :space :paragraph :indent :glue :kern :penalty :rule :language
    :box :leaders :tex-mark :discretionary :pre-break :post-break :no-break
    :accent :insert :vadjust :special :shipout
    :math :eqno :noad :nucleus :superscript :subscript :math-char
    :fraction :numerator :denominator :left :right :math-style
    :math-choice :choice
    :alignment :row :cell :no-align
    :write :openout :closeout :diagnostic)
  "The event kinds of docs/events.md other than the vocabulary's
:BEGIN, :END and :MARK, whose keys are the vocabulary's.")

(defun owned-items (owners reader)
  "Every item READER gives of OWNERS, with repetitions."
  (loop for owner in owners append (funcall reader owner)))

(defun duplicates (items)
  "The items occurring more than once in ITEMS."
  (remove-duplicates
   (loop for (item . rest) on items when (member item rest) collect item)))

(define-test model-owners
  :parent model
  (let* ((owners (model:owners))
         (keys (remove-duplicates
                (mapcar #'semantic:entry-key
                        (semantic:vocabulary-entries (semantic:spec-vocabulary)))))
         (owned-keys (owned-items owners #'model:owner-vocabulary))
         (owned-kinds (owned-items owners #'model:owner-events)))
    (is equal '() (duplicates owned-keys) "Keys owned twice")
    (is equal '() (duplicates owned-kinds) "Event kinds owned twice")
    (is equal '() (set-difference keys owned-keys) "Keys without an owner")
    (is equal '() (set-difference owned-keys keys) "Owned keys not in the vocabulary")
    (is equal '() (set-difference *event-kinds* owned-kinds) "Event kinds without an owner")
    (is equal '() (set-difference owned-kinds *event-kinds*) "Owned kinds not events")
    (dolist (owner owners)
      (true (probe-file (asdf:system-relative-pathname
                         "cl-ansi-spec"
                         (concatenate 'string "src/model/" (model:owner-file owner))))
            "~A's handler file ~A exists" (model:owner-step owner)
            (model:owner-file owner)))))

(define-test model-event-kinds-documented
  :parent model
  ;; Each kind the table owns is named in docs/events.md as an event,
  ;; `(:kind', `(:begin :kind' or `:kind' in a code span, so the list
  ;; above follows the doc.
  (let ((doc (uiop:read-file-string
              (asdf:system-relative-pathname "cl-ansi-spec" "docs/events.md"))))
    (dolist (kind *event-kinds*)
      (true (some (lambda (form) (search (format nil form kind) doc))
                  '("(:~(~A~)" "(:begin :~(~A~)" "`:~(~A~)`"))
            "docs/events.md names ~S as an event" kind))))
