;;;; tests/model/inlines.lisp
;;;;
;;;; Tests of semantic inlines (src/model/build-inlines.lisp): each
;;;; macro's node from events made here, then real lines of the spec.
;;;; Owner: step 3.13 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/tests)

(define-test inlines
  :parent model
  :description "Semantic inlines: references, names, notation, anchors.")

(defparameter *inline-handlers*
  (let ((table (model:make-handler-table)))
    (model:install-text-handlers table)
    (model:install-inline-handlers table)
    (model:register-handler :begin :paragraph
                            (lambda (builder event span)
                              (declare (ignore event))
                              (model:open-container
                               builder :paragraph span
                               :node (model:make-builder-node builder :paragraph)
                               :field 'model::content))
                            table)
    table)
  "The text and inline handlers, and a paragraph to hold them.")

(defun inline-items (&rest events)
  "The inlines EVENTS build inside a paragraph, as S-expressions with
the spans left out, and the build report."
  (multiple-value-bind (nodes report)
      (model:build-events (append (list (test-event :begin :paragraph))
                                  events (list (test-event :end :paragraph)))
                          :registry model:*registry* :handlers *inline-handlers*)
    (labels ((strip (item)
               (if (stringp item)
                   item
                   (cons (first item)
                         (loop for (key value) on (rest item) by #'cddr
                               unless (eq key :span)
                                 append (list key (if (and value (listp value) (listp (first value)))
                                                      (mapcar #'strip value)
                                                      value)))))))
      (values (mapcar #'strip (getf (rest (model:node-sexp (first nodes))) :content))
              report))))

(defun inline-events (key arguments &rest content)
  "INLINE-ITEMS of one KEY entry with ARGUMENTS around the typewriter
text CONTENT."
  (apply #'inline-items
         (append (list (test-event :begin key :arguments arguments))
                 (mapcar (lambda (text) (txt text "cmtt9")) content)
                 (list (test-event :end key)))))

(define-test inlines-terms
  :parent inlines
  (multiple-value-bind (items report)
      (inline-events :term '("dotted list") "dotted lists")
    (is equal '((:term-ref :text "dotted list")) items "the text is the argument, not the typeset")
    (is equal '() (problem-kinds report)))
  (is equal '((:term-ref :text "list" :defining t))
      (inline-events :new-term '("list " "list") "list")
      "\\newtermidx: its first argument")
  (is equal '((:param :name "list")) (inline-events :param '("list") "list"))
  (is equal '((:metavariable :name "var")) (inline-events :metavariable '("var") "var"))
  (is equal '((:format-directive :name "A")) (inline-events :format-directive '("A") "A")))

(define-test inlines-fonts
  :parent inlines
  (is equal '((:emphasis :content ("true"))) (inline-events :emphasis '() "true"))
  (is equal '((:strong :content ("Examples:"))) (inline-events :strong '() "Examples:"))
  (is equal '((:code :content ("(car)"))) (inline-events :inline-code '() "(car)"))
  (is equal '((:citation :content ("CLtL"))) (inline-events :cite '() "CLtL"))
  (is equal '((:input :content ("(read)"))) (inline-events :input '() "(read)")))

(define-test inlines-lambda-list-keywords
  :parent inlines
  (multiple-value-bind (items report)
      (inline-events :lambda-list-keyword '() "&opt" "ional")
    (is equal '((:lambda-list-keyword :name "&optional")) items
        "the name is what the macro typeset")
    (is equal '() (problem-kinds report))))

(define-test inlines-references
  :parent inlines
  (is equal '((:operator-ref :text "endp" :via :function))
      (inline-events :funref '("endp") "endp"))
  (is equal '((:operator-ref :text "car" :via :any)) (inline-events :clref '("car") "car"))
  (is equal '((:operator-ref :text ":test" :via :keyword))
      (inline-items (test-event :begin :kwd :arguments '("test" ":test") :through :ttref)
                    (test-event :end :kwd))
      "a wrapper: its own key says the kind, the last argument the text")
  (is equal '((:operator-ref :text "\\&key" :via :lambda-list-keyword))
      (inline-events :keyref '("key" "\\&key") "&key")
      "the real arguments of \\keyref{key}: the name, then the name with its ampersand")
  (loop for (key . via) in model::*reference-vias*
        do (is eq via (getf (rest (first (inline-events key '("x")))) :via)
               "~S is a ~S" key via))
  (is equal '((:section-ref :label "OrdinaryLambdaLists"))
      (inline-events :secref '("OrdinaryLambdaLists ") "2.4"))
  (is equal '((:figure-ref :label "FigConses"))
      (inline-events :figref '("FigConses") "14-1"))
  (is equal '((:this-section)) (inline-events :this-section '())))

(define-test inlines-reference-texts
  :parent inlines
  ;; The `\\fi's a cell's active first character leaves, with the spaces TeX
  ;; skips after them, are not part of the name.
  (is equal "*package*" (model::reference-text "*\\fi \\fi package*"))
  (is equal "-" (model::reference-text "-\\fi"))
  (is equal "*" (model::reference-text "*\\fi \\fi"))
  (is equal "\\fiasco" (model::reference-text " \\fiasco ")
      "a control word that only begins with fi is kept")
  (is equal ">=" (model::reference-text "{$\\spGT $}\\fi \\fi ="))
  (is equal "<" (model::reference-text "{$\\spLT $}\\fi \\fi"))
  (is equal '((:operator-ref :text "*print-base*" :via :misc))
      (inline-events :misc '("*\\fi \\fi print-base*") "*print-base*"))
  ;; A reference with no name (an empty table cell) is no node.
  (is equal '() (inline-events :misc '("")))
  ;; \\f marks code: a type specifier is no name of an entry.
  (is equal '((:code :content ("(eql't)")))
      (inline-events :typeref '("\\f {(eql 't)}") "(eql't)")))

(define-test inlines-notation
  :parent inlines
  (is equal '((:evaluates-to)) (inline-events :evaluates-to '()))
  (is equal '((:may-evaluate-to)) (inline-events :may-evaluate-to '()))
  (is equal '((:does-not-evaluate-to)) (inline-events :does-not-evaluate-to '()))
  (is equal '((:equivalent)) (inline-events :equivalent '()))
  (is equal '("a " (:output) " b")
      (inline-items (txt "a ") (test-event :begin :output) (test-event :end :output) (txt " b"))))

(define-test inlines-anchors
  :parent inlines
  (is equal '((:index-entry :index-kind :ref :text "endp"))
      (inline-items (test-event :mark :index-ref :arguments '("endp"))))
  (loop for (key . kind) in model::*index-kinds*
        do (is eq kind (getf (rest (first (inline-items (test-event :mark key :arguments '("x")))))
                             :index-kind)))
  (multiple-value-bind (items report)
      (inline-items (test-event :begin :issue :arguments '("DOTTED-LIST:CLARIFY"))
                    (txt "text")
                    (test-event :end :issue :arguments '("DOTTED-LIST:CLARIFY")))
    (is equal '((:issue-start :name "DOTTED-LIST:CLARIFY") "text"
                (:issue-end :name "DOTTED-LIST:CLARIFY"))
        items "an issue is two anchors around its text, not a container")
    (is equal '() (problem-kinds report))))

(define-test inlines-keys-are-handled
  :parent inlines
  "Every key 3.13 owns has a handler of its own."
  (let ((owned (model:owner-vocabulary
                (find "3.13" (model:owners) :key #'model:owner-step :test #'string=)))
        (handled (mapcar #'second (model:handled-events *inline-handlers*))))
    (dolist (key (remove :endissue owned))
      (true (member key handled) "~S has a handler" key))
    (true (member :issue handled) "\\endissue ends :issue, which has its own :end handler")))

;;; Real lines

(defun node-kinds-within (item)
  "The kinds of the node ITEM (a node, a string or a list of them) and of
every node its fields hold, in document order."
  (typecase item
    (model:node
     (cons (model:node-kind item)
           (loop for field in (model:node-fields (model:node-kind item))
                 append (node-kinds-within
                         (model:node-field-value item (model:field-name field))))))
    (cons (mapcan #'node-kinds-within item))
    (t '())))

(defun fixture-kinds (job file first last)
  "The kinds of the nodes in the model of FILE's lines FIRST to LAST of
JOB, nested ones included (inlines sit in paragraphs), in order."
  (node-kinds-within
   (model:build-fixture job :file file :lines (list first last))))

(define-test inlines-spec-lines
  :parent inlines
  ;; \endp's Arguments and Values and Description (dict-conses.tex).
  (let ((kinds (fixture-kinds "chap-14" "dict-conses.tex" 1702 1730)))
    (true (member :param kinds))
    (true (member :term-ref kinds))
    (true (member :issue-start kinds))
    (true (member :issue-end kinds))
    (true (member :evaluates-to kinds))
    (is = 4 (count :param kinds) "four \\param in those lines")
    (is = 11 (count :term-ref kinds)))
  (let ((kinds (fixture-kinds "chap-3" "concept-bvl.tex" 281 288)))
    (true (member :operator-ref kinds) "\\keyref and \\kwd")))
