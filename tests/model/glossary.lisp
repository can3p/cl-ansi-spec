;;;; tests/model/glossary.lisp
;;;;
;;;; Tests of the glossary (src/model/build-glossary.lisp): the notation of
;;;; entries, their senses, and the real lines of the spec.
;;;; Owner: step 3.14 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/tests)

(define-test glossary
  :parent model
  :description "The glossary: groups, entries, senses and their notation.")

;;; Handlers of the tests: the glossary's, text, and a stand-in for the
;;; references and bold text that other steps build.

(defvar *glossary-handlers*
  (let ((table (model:install-glossary-handlers
                (model:install-text-handlers (model:make-handler-table)))))
    (model:register-handler
     :begin :term
     (lambda (builder event span)
       (let ((text (first (model:event-argument-texts builder event))))
         (model:open-container
          builder :term span
          :on-close (lambda (builder container)
                      (setf (model:container-items container) '())
                      (model:add-item builder
                                      (model:make-builder-node builder :term-ref
                                                               :span span :text text))))))
     table)
    (model:register-handler
     :begin :strong
     (lambda (builder event span)
       (declare (ignore event))
       (model:open-container builder :strong span
                             :node (model:make-builder-node builder :strong)
                             :field 'model::content))
     table)
    (model:register-handler
     :begin :section
     (lambda (builder event span)
       (declare (ignore event))
       (model:open-container builder :section span))
     table)
    table)
  "The glossary's and text's handlers, and :term, :strong and :section containers.")

(defun glossary-nodes (&rest events)
  "The top-level nodes of EVENTS built with the glossary handlers, as
S-expressions, and the report."
  (multiple-value-bind (nodes report)
      (model:build-events events :registry model:*registry* :handlers *glossary-handlers*)
    (values (mapcar (lambda (node) (if (stringp node) node (model:node-sexp node))) nodes)
            report)))

(defun entry-events (term &rest body)
  "The events of a \\gentry for TERM, its bold heading, then BODY."
  (append (list (test-event :mark :glossary-entry :arguments (list term))
                (test-event :begin :strong :arguments (list term))
                (txt term "cmbx10")
                (test-event :end :strong))
          body))

(defun notation (key text)
  "The events of a part of speech or usage notation KEY showing TEXT."
  (list (test-event :begin key :arguments (list text))
        (txt text "cmti10")
        (test-event :end key)))

(defun sexp-field (sexp field)
  "The value of FIELD in the node S-expression SEXP."
  (getf (rest sexp) field))

;;; Notation

(define-test glossary-notation-texts
  :parent glossary
  (is equal '(:noun :verb :transitive-verb :adjective :adverb)
      (mapcar #'cdr model:*part-of-speech-texts*))
  (is equal '(:ansi :ieee :iso :traditional :mathematics :idiomatic :computers)
      (mapcar #'cdr model:*usage-texts*))
  ;; Every value is a value of the enum the model declares.
  (dolist (enum '(part-of-speech usage))
    (let ((values (mapcar #'first (model:enum-values (model:find-enum enum)))))
      (dolist (entry (if (eq enum 'part-of-speech)
                         model:*part-of-speech-texts*
                         model:*usage-texts*))
        (true (member (cdr entry) values) "~S is a ~(~A~)" (cdr entry) enum)))))

(define-test glossary-entry-parts
  :parent glossary
  (let* ((nodes (glossary-nodes
                 (test-event :mark :glossary-letter :arguments '("A"))
                 (test-event :mark :glossary-entry :arguments '("access"))
                 (test-event :begin :strong :arguments '("access"))
                 (txt "access" "cmbx10")
                 (test-event :end :strong)
                 (test-event :space nil)
                 (test-event :begin :pronunciation :arguments '("x"))
                 (txt "ak" "cmbx10")
                 (test-event :end :pronunciation)
                 (txt "," "cmr10")
                 (test-event :space nil)
                 (test-event :begin :part-of-speech :arguments '("n."))
                 (txt "n." "cmti10")
                 (test-event :end :part-of-speech)
                 (txt "," "cmr10")
                 (test-event :space nil)
                 (test-event :begin :part-of-speech :arguments '("v.t."))
                 (txt "v.t." "cmti10")
                 (test-event :end :part-of-speech)
                 (test-event :space nil)
                 (test-event :begin :usage :arguments '("Idiom."))
                 (txt "Idiom." "cmti10")
                 (test-event :end :usage)
                 (txt "1." "cmr10") (test-event :space nil)
                 (txt "to read" "cmr10") (test-event :space nil)
                 (txt "2." "cmr10") (test-event :space nil)
                 (test-event :begin :usage :arguments '("Math."))
                 (txt "Math." "cmti10")
                 (test-event :end :usage)
                 (test-event :space nil)
                 (txt "a way in." "cmr10")))
         (group (first nodes))
         (entry (first (sexp-field group :entries))))
    (is = 1 (length nodes))
    (is equal "A" (sexp-field group :letter))
    (is equal "access" (sexp-field entry :id))
    (is equal "access" (sexp-field entry :term))
    (is equal '("ak") (sexp-field entry :pronunciation))
    (is equal '(:noun :transitive-verb) (sexp-field entry :parts-of-speech))
    (is equal '(:idiomatic) (sexp-field entry :usages))
    (let ((senses (sexp-field entry :senses)))
      (is = 2 (length senses))
      (is equal '(1 2) (mapcar (lambda (sense) (sexp-field sense :number)) senses))
      (is equal '(("to read") ("a way in."))
          (mapcar (lambda (sense) (sexp-field sense :content)) senses))
      (is equal '(nil (:mathematics))
          (mapcar (lambda (sense) (sexp-field sense :usages)) senses)))))

(define-test glossary-unnumbered-and-context
  :parent glossary
  ;; One definition, no number: one sense without a number.
  (let* ((entry (first (sexp-field
                        (first (glossary-nodes
                                (test-event :mark :glossary-letter :arguments '("B"))
                                (test-event :mark :glossary-entry :arguments '("bar"))
                                (txt "a" "cmr10") (test-event :space nil) (txt "bar." "cmr10")))
                        :entries)))
         (senses (sexp-field entry :senses)))
    (is = 1 (length senses))
    (is eq nil (sexp-field (first senses) :number))
    (is equal '("a bar.") (sexp-field (first senses) :content)))
  ;; Text before `1.' is the context all the senses share: a sense of its own.
  (let* ((entry (first (sexp-field
                        (first (glossary-nodes
                                (test-event :mark :glossary-letter :arguments '("B"))
                                (test-event :mark :glossary-entry :arguments '("baz"))
                                (txt "(of a" "cmr10") (test-event :space nil) (txt "baz)" "cmr10")
                                (test-event :space nil)
                                (txt "1." "cmr10") (test-event :space nil) (txt "one" "cmr10")
                                (test-event :space nil)
                                (txt "2." "cmr10") (test-event :space nil) (txt "two" "cmr10")))
                        :entries)))
         (senses (sexp-field entry :senses)))
    (is equal '(nil 1 2) (mapcar (lambda (sense) (sexp-field sense :number)) senses))
    (is equal '("(of a baz)") (sexp-field (first senses) :content))))

(define-test glossary-separators
  :parent glossary
  ;; The comma between notations goes, the comma between references stays.
  (let* ((nodes (glossary-nodes
                 (test-event :mark :glossary-letter :arguments '("A"))
                 (test-event :mark :glossary-entry :arguments '("x"))
                 (test-event :begin :part-of-speech :arguments '("n."))
                 (txt "n." "cmti10") (test-event :end :part-of-speech)
                 (txt "," "cmr10") (test-event :space nil)
                 (test-event :begin :term :arguments '("a")) (test-event :end :term)
                 (txt "," "cmr10") (test-event :space nil)
                 (test-event :begin :term :arguments '("b")) (test-event :end :term)))
         (sense (first (sexp-field (first (sexp-field (first nodes) :entries)) :senses))))
    (is equal '(", ") (remove-if-not #'stringp (sexp-field sense :content)))))

(define-test glossary-pronunciation-layout
  :parent glossary
  ;; The brackets \\pronounced sets in a formula are notation: the
  ;; formula is unwrapped, its bracket noads dropped, empty formulas
  ;; (stress marks) dropped.
  (flet ((noad (class &rest nucleus)
           (model:make-node :math-noad :class class :nucleus nucleus))
         (char-node (text) (model:make-node :math-char :text text)))
    (let* ((strong (model:make-node :strong
                                    :content (list (model:make-node :math) "nil")))
           (formula (model:make-node
                     :math :content (list (noad :open (char-node "["))
                                          (noad :ord strong)
                                          (noad :close (char-node "]")))))
           (result (model::pronunciation-inlines (list formula " " (char-node "x")))))
      (is = 3 (length result))
      (is eq strong (first result))
      (is equal '("nil") (model:node-field-value strong :content))
      (is equal '(" " "x") (rest result)))))

(define-test glossary-sense-numbers
  :parent glossary
  ;; A number is a sense's when it follows the one before: `integer 1.'
  ;; ends a sentence, `2.' in sense 1 is not sense 2 until 1 has begun.
  (let ((segments (model::split-segments
                   '("(1.5 of" " 1. the integer 1. and 2. also 2. other"))))
    (is equal '(nil 1 2) (mapcar #'car segments))
    (is equal '("(1.5 of" "the integer 1. and" "also 2. other")
        (mapcar (lambda (segment)
                  (string-trim " " (apply #'concatenate 'string (cdr segment))))
                segments)))
  (is equal '(nil) (mapcar #'car (model::split-segments '("the integer 0 or the integer 1."))))
  (is equal '(nil) (mapcar #'car (model::split-segments '("version 2. of x"))))
  (is equal '(nil 1) (mapcar #'car (model::split-segments '("1. a")))))

;;; Examples, meanings, the heading

(define-test glossary-examples-and-meanings
  :parent glossary
  (let* ((nodes (glossary-nodes
                 (test-event :mark :glossary-letter :arguments '("C"))
                 (test-event :mark :glossary-entry :arguments '("car"))
                 (txt "a" "cmr10") (test-event :space nil)
                 (test-event :begin :term :arguments '("list"))
                 (test-event :end :term)
                 (test-event :begin :sense :arguments '("2a"))
                 (txt "2a" "cmr10")
                 (test-event :end :sense)
                 (test-event :space nil)
                 (test-event :begin :glossary-example :arguments '("x"))
                 (txt "Look." "cmr10")
                 (test-event :end :glossary-example)))
         (sense (first (sexp-field (first (sexp-field (first nodes) :entries)) :senses))))
    (is equal "list" (sexp-field (first (rest (sexp-field sense :content))) :text))
    (is = 2 (sexp-field (first (rest (sexp-field sense :content))) :sense)
        "the sense of a term reference is its meaning's number")
    (is equal '("Look.") (sexp-field (first (sexp-field sense :examples)) :content)
        "an example is not part of the definition")
    (is equal 1 (length (sexp-field sense :examples)))))

(define-test glossary-problems
  :parent glossary
  ;; A \meaning after nothing, a notation of an unknown text, a notation
  ;; outside an entry (text stays, in italics).
  (multiple-value-bind (nodes report)
      (glossary-nodes (test-event :begin :sense :arguments '("1")) (test-event :end :sense)
                      (test-event :begin :part-of-speech :arguments '("n."))
                      (txt "n." "cmti10")
                      (test-event :end :part-of-speech))
    (is = 1 (length nodes))
    (is eq :emphasis (first (first nodes)))
    (is equal '(:diagnostic) (problem-kinds report)))
  (multiple-value-bind (nodes report)
      (glossary-nodes (test-event :mark :glossary-entry :arguments '("x"))
                      (test-event :begin :usage :arguments '("Odd."))
                      (txt "Odd." "cmti10")
                      (test-event :end :usage)
                      (txt "def" "cmr10"))
    (is equal '("def") (sexp-field (first (sexp-field (first nodes) :senses)) :content))
    (is equal '(:diagnostic) (problem-kinds report))))

(define-test glossary-ends-with-its-container
  :parent glossary
  ;; The last entry runs to the end of the container that holds the
  ;; glossary, and nothing is reported unclosed.
  (multiple-value-bind (nodes report)
      (glossary-nodes (test-event :begin :section :arguments '("Glossary"))
                      (test-event :mark :glossary-letter :arguments '("A"))
                      (test-event :mark :glossary-entry :arguments '("a"))
                      (txt "x" "cmr10")
                      (test-event :mark :glossary-letter :arguments '("B"))
                      (test-event :mark :glossary-entry :arguments '("b"))
                      (txt "y" "cmr10")
                      (test-event :end :section))
    (is equal '() (problem-kinds report))
    (is equal '(:glossary-group :glossary-group) (mapcar #'first nodes))
    (is equal '("a" "b") (mapcar (lambda (group)
                                   (sexp-field (first (sexp-field group :entries)) :id))
                                 nodes))))

;;; Real lines

(defun glossary-fixture (first last)
  "The nodes of concept-glossary.tex's lines FIRST to LAST, as S-expressions."
  (mapcar (lambda (node) (if (stringp node) node (model:node-sexp node)))
          (model:build-fixture "chap-26" :file "concept-glossary.tex" :lines (list first last))))

(defun group-entries (nodes)
  "The entries of the groups among NODES."
  (loop for node in nodes
        when (and (consp node) (eq (first node) :glossary-group))
          append (sexp-field node :entries)))

(define-test glossary-spec-lines
  :parent glossary
  ;; concept-glossary.tex:163: absolute, two numbered senses.
  (let* ((entry (find "absolute" (group-entries (glossary-fixture 161 169))
                      :key (lambda (entry) (sexp-field entry :id)) :test #'equal))
         (senses (sexp-field entry :senses)))
    (is equal '(:adjective) (sexp-field entry :parts-of-speech))
    (is equal '(1 2) (mapcar (lambda (sense) (sexp-field sense :number)) senses))
    (true (find-if (lambda (item) (and (stringp item) (search "specific point in time" item)))
                   (sexp-field (first senses) :content))))
  ;; :170: access, two parts of speech, a part of speech in each sense.
  (let ((entry (find "access" (group-entries (glossary-fixture 161 177))
                     :key (lambda (entry) (sexp-field entry :id)) :test #'equal)))
    (is equal '(:noun :transitive-verb) (sexp-field entry :parts-of-speech))
    (is equal '((:transitive-verb) (:noun))
        (mapcar (lambda (sense) (sexp-field sense :parts-of-speech))
                (sexp-field entry :senses))))
  ;; :157: the first group, a pronunciation, \Stress{nil}.
  (let* ((entry (first (group-entries (glossary-fixture 155 160))))
         (strong (first (sexp-field entry :pronunciation))))
    (is equal "()" (sexp-field entry :id))
    (is eq :strong (first strong) "the pronunciation is set in bold")
    (is equal '((:stress :level :primary) "nil")
        (mapcar (lambda (item) (if (consp item) (subseq item 0 3) item))
                (sexp-field strong :content))
        "the syllable follows its primary stress mark")))

(define-test glossary-whole
  :parent glossary
  (let* ((nodes (model:build-fixture "chap-26" :file "concept-glossary.tex" :lines '(150 nil)))
         (groups (remove-if-not (lambda (node) (and (typep node 'model:node)
                                                    (eq (model:node-kind node) :glossary-group)))
                                nodes))
         ;; A group's entries, without the anchors between them.
         (entries (loop for group in groups
                        append (remove-if-not (lambda (node)
                                                (eq (model:node-kind node) :glossary-entry))
                                              (model:node-field-value group :entries))))
         (senses (loop for entry in entries
                       append (model:node-field-value entry :senses))))
    (is = 24 (length groups) "Non-alphabetic and 23 letters")
    (is = 692 (length entries) "every \\gentry of the glossary")
    (is equal '() (remove-if (lambda (entry) (model:node-field-value entry :term)) entries))
    (true (> (length senses) 800))
    (is equal '() (loop for entry in entries
                        append (model:node-problems entry)))
    (is = 0 (count-if-not (lambda (sense) (model:node-field-value sense :content)) senses))
    (is = 0 (count-if (lambda (entry)
                        (and (rest (model:node-field-value entry :senses))
                             (some (lambda (sense) (null (model:node-field-value sense :number)))
                                   (rest (model:node-field-value entry :senses)))))
                      entries)
        "only a first sense has no number")))
