;;;; tests/model/resolve-terms.lisp
;;;;
;;;; Tests of term references (src/model/resolve-terms.lisp): one fixture
;;;; from the sources for each tier and rule, resolved against the
;;;; glossary of concept-glossary.tex; the whole spec's references, the
;;;; ones left unresolved pinned in tests/model/unresolved-terms.sexp.

(in-package #:cl-ansi-spec/tests)

(define-test resolve-terms
  :parent model
  :description "Term references resolved to glossary entries.")

(defvar *terms-glossary* nil
  "The nodes of the glossary of concept-glossary.tex, built once.")

(defun terms-glossary ()
  "The glossary's nodes, built on first use."
  (or *terms-glossary*
      (setf *terms-glossary*
            (model:build-fixture "chap-26" :file "concept-glossary.tex" :lines '(150 nil)))))

(defun terms-references (items)
  "The :TERM-REF nodes of ITEMS, at any depth, in order."
  (let ((found '()))
    (model:walk-nodes (lambda (node) (when (eq (model:node-kind node) :term-ref) (push node found)))
                      items)
    (nreverse found)))

(defun terms-target-id (reference)
  "The id of the glossary entry REFERENCE resolves to, or NIL."
  (let ((target (model:node-field-value reference :target)))
    (and target (model:target-id target))))

(defparameter *terms-fixtures*
  ;; (job file line text entry tier rule): a reference of TEXT on the
  ;; line resolves to ENTRY by TIER and RULE.
  '(("chap-26" "concept-glossary.tex" 299 "condition" "condition" :name :exact)
    ("chap-26" "concept-glossary.tex" 3738 "Lisp Reader" "Lisp reader" :name :exact)
    ("chap-3" "concept-decls.tex" 3 "Declarations" "declaration" :name :exact)
    ("chap-26" "concept-glossary.tex" 1184 "leaves" "leaf" :last-word :irregular)
    ("chap-25" "dict-environment.tex" 272 "\\symbolnamedesignator" "string designator"
     :last-word :irregular)
    ("chap-26" "concept-glossary.tex" 3628 "properties" "property" :last-word :ies)
    ("chap-26" "concept-glossary.tex" 1342 "classes" "class" :last-word :es)
    ("chap-26" "concept-glossary.tex" 362 "objects" "object" :last-word :s)
    ("chap-26" "concept-glossary.tex" 299 "signaled" "signal" :last-word :ed)
    ("chap-26" "concept-glossary.tex" 691 "evaluated" "evaluate" :last-word :d)
    ("chap-6" "concept-loop.tex" 659 "stepped" "step" :last-word :doubled-ed)
    ("chap-26" "concept-glossary.tex" 1035 "signaling" "signal" :last-word :ing)
    ("chap-26" "concept-glossary.tex" 2195 "evaluating" "evaluate" :last-word :ing-e)
    ("chap-6" "concept-loop.tex" 172 "stepping" "step" :last-word :doubled-ing)
    ("chap-14" "dict-conses.tex" 838 "satisfies the test" "satisfy the test" :first-word :ies)
    ("chap-17" "dict-sequences.tex" 1783 "satisfying the test" "satisfy the test"
     :first-word :ing)
    ("chap-5" "concept-places.tex" 559 "written" "write" :last-word :irregular))
  "One real reference for each tier and rule.  concept-decls.tex:3 is
\\newtermidx{Declarations}{declaration}: looked up by its index entry.")

(defun terms-fixture (job file line)
  "The nodes of FILE's LINE in JOB, their term references resolved
against the glossary."
  (let ((nodes (model:build-fixture job :file file :lines (list line line))))
    (model:resolve-terms nodes :glossary (terms-glossary))
    nodes))

(defun terms-with-next (reference nodes)
  "REFERENCE and, when it is one of the top-level NODES, the node after
it (a \\newtermidx's index entry)."
  (let ((tail (member reference nodes)))
    (if tail (subseq tail 0 (min 2 (length tail))) (list reference))))

(define-test resolve-terms-rules
  :parent resolve-terms
  (loop for (job file line text entry tier rule) in *terms-fixtures*
        do (let ((nodes (terms-fixture job file line)))
             (let ((reference (find text (terms-references nodes) :test #'string=
                                    :key (lambda (node) (model:node-field-value node :text)))))
               (true reference "~A:~D has a reference ~S" file line text)
               (when reference
                 (is equal entry (terms-target-id reference) "~A:~D ~S" file line text)
                 ;; The reference alone, with the index entry after it.
                 (is equal (list (cons (cons tier rule) 1))
                     (nth-value 1 (model:resolve-terms (terms-with-next reference nodes)
                                                       :glossary (terms-glossary)))
                     "~A:~D ~S resolves by ~S ~S" file line text tier rule))))))

(define-test resolve-terms-problems
  :parent resolve-terms
  ;; concept-environment.tex:94: no entry for real.
  (let ((nodes (model:build-fixture "chap-25" :file "concept-environment.tex" :lines '(94 94))))
    (let ((problems (model:resolve-terms nodes :glossary (terms-glossary))))
      (is equal '((:unresolved-term "No glossary entry for \"real\"."))
          (mapcar (lambda (problem) (list (model:problem-kind problem) (model:problem-message problem)))
                  problems))
      (is eq nil (terms-target-id (find "real" (terms-references nodes) :test #'string=
                                        :key (lambda (node) (model:node-field-value node :text)))))))
  ;; concept-glossary.tex:1138: \term{syntax type}\meaning{2}, an entry of one sense.
  (let ((problems (model:resolve-terms (terms-glossary))))
    (is equal '((:missing-sense 1138) (:missing-sense 5045))
        (mapcar (lambda (problem)
                  (list (model:problem-kind problem) (model:span-line (model:problem-span problem))))
                (remove :unresolved-term problems :key #'model:problem-kind)))))

;; Built nodes: an irregular written with a capital, a sense of an
;; entry without senses.
(define-test resolve-terms-nodes
  :parent resolve-terms
  (let* ((entry (model:make-node :glossary-entry :id "leaf" :term "leaf"))
         (reference (model:make-node :term-ref :text "Leaves" :sense 1)))
    (multiple-value-bind (problems counts) (model:resolve-terms (list reference)
                                                                :glossary (list entry))
      (is equal "leaf" (terms-target-id reference))
      (is equal '(((:last-word . :irregular) . 1)) counts)
      (is equal '(:missing-sense) (mapcar #'model:problem-kind problems)))))

;;; The whole spec

(defun terms-pinned ()
  "The rows of tests/model/unresolved-terms.sexp."
  (with-open-file (in (asdf:system-relative-pathname "cl-ansi-spec"
                                                     "tests/model/unresolved-terms.sexp"))
    (with-standard-io-syntax
      (let ((*read-eval* nil)) (read in)))))

(defparameter *terms-reasons* '(:no-entry :compound :variant :not-a-term :typo)
  "The reasons of tests/model/unresolved-terms.sexp.")

(defparameter *terms-rule-counts*
  '(((:name . :exact) . 20791) ((:last-word . :s) . 4129)
    ((:last-word . :irregular) . 35) ((:last-word . :d) . 88)
    ((:last-word . :es) . 244) ((:last-word . :ed) . 161)
    ((:last-word . :ing) . 55) ((:last-word . :ing-e) . 39)
    ((:last-word . :ies) . 12) ((:last-word . :doubled-ing) . 17)
    ((:last-word . :doubled-ed) . 3) ((:first-word . :ies) . 12)
    ((:first-word . :ing) . 5))
  "How often each tier and rule resolves a reference of the whole spec,
in the order of first use.
The first word is inflected only in satisfies and satisfying the test.")

(defun terms-unresolved-rows (nodes)
  "(text count) for each text of the references of NODES left without a
target, sorted by text."
  (let ((counts '()))
    (dolist (reference (terms-references nodes))
      (unless (terms-target-id reference)
        (let* ((text (model:node-field-value reference :text))
               (cell (assoc text counts :test #'string=)))
          (if cell (incf (second cell)) (push (list text 1) counts)))))
    (sort counts #'string< :key #'first)))

(defun terms-problem-row (problem)
  "(kind file line message) of PROBLEM."
  (let ((span (model:problem-span problem)))
    (list (model:problem-kind problem) (model:span-file span) (model:span-line span)
          (model:problem-message problem))))

(define-test resolve-terms-whole-spec
  :parent resolve-terms
  (let ((nodes (whole-spec-nodes)))
    (multiple-value-bind (problems counts) (model:resolve-terms nodes)
      (is equal *terms-rule-counts* counts)
      (is equal '() (remove-if-not (lambda (problem) (eq (model:problem-kind problem) :ambiguous-term))
                                   problems)
          "no reference two entries match, no two ids equal but for case")
      (is equal '(("concept-glossary.tex" 1138) ("concept-glossary.tex" 5045))
          (loop for problem in problems
                when (eq (model:problem-kind problem) :missing-sense)
                  collect (list (model:span-file (model:problem-span problem))
                                (model:span-line (model:problem-span problem)))))
      (let ((pinned (terms-pinned)) (rows (terms-unresolved-rows nodes)))
        (is equal (sort (mapcar (lambda (row) (subseq row 0 2)) pinned) #'string< :key #'first)
            rows "the unresolved references are those pinned")
        (is = (reduce #'+ rows :key #'second)
            (count :unresolved-term problems :key #'model:problem-kind)
            "each unresolved reference is reported")
        (is equal '() (remove-if (lambda (row) (member (third row) *terms-reasons*)) pinned)
            "every pinned text has a reason"))
      (let ((targets (mapcar #'terms-target-id (terms-references nodes))))
        (is equal (mapcar #'terms-problem-row problems)
            (mapcar #'terms-problem-row (model:resolve-terms nodes))
            "resolving again gives the same problems, in the same order")
        (is equal targets (mapcar #'terms-target-id (terms-references nodes))
            "resolving again gives the same targets")))))
