;;;; tests/model/bnf.lisp
;;;;
;;;; Tests of BNF.
;;;; Owner: step 3.15 of docs/plan/m3.md.  Reserved by 3.0: no code yet.

(in-package #:cl-ansi-spec/tests)

(define-test bnf
  :parent model
  :description "BNF rules and the notation of syntax descriptions.")

(defvar *bnf-handlers*
  (let ((table (model:install-bnf-handlers (model:make-handler-table))))
    (model:install-text-handlers table)
    table)
  "BNF's handlers and the text handlers.")

(defun bnf-nodes (&rest events)
  "The top-level nodes of EVENTS built with the BNF handlers, as
S-expressions with the spans left out, and the build report."
  (multiple-value-bind (nodes report)
      (model:build-events events :registry model:*registry* :handlers *bnf-handlers*)
    (values (mapcar (lambda (node)
                      (if (stringp node) node (model:node-sexp node :spans nil)))
                    nodes)
            report)))

(defun bnf-text (text)
  "A :text event of TEXT in the roman font."
  (test-event :text text :style "cmr10"))

(defun begin (key &rest arguments)
  "A :begin event of KEY, with ARGUMENTS."
  (test-event :begin key :arguments arguments))

(defun end (key)
  "An :end event of KEY."
  (test-event :end key))

(define-test bnf-rule
  :parent bnf
  (multiple-value-bind (nodes report)
      (bnf-nodes (begin :bnf-rule "reqvars" "\\star ...")
                 (bnf-text "reqvars::")
                 (begin :zero-or-more) (begin :group) (bnf-text "var") (end :group)
                 (bnf-text "*") (end :zero-or-more)
                 (test-event :mark :bnf-break)
                 (end :bnf-rule))
    (is equal '((:bnf-rule :name "reqvars"
                 :definition ((:bnf-zero-or-more :content ((:bnf-group :content ("var"))))
                              (:bnf-break))))
        nodes)
    (is equal '() (problem-kinds report))))

(define-test bnf-glyphs
  :parent bnf
  (is equal '((:bnf-parenthesized :content ("var")))
      (bnf-nodes (begin :parenthesized) (bnf-text "(var") (bnf-text ")") (end :parenthesized)))
  (is equal '((:bnf-optional :content ("a " (:bnf-optional :content ("b")))))
      (bnf-nodes (begin :optional) (bnf-text "[a ")
                 (begin :optional) (bnf-text "[b]") (end :optional)
                 (bnf-text "]") (end :optional))
      "an optional part's brackets are the node's, and not its text")
  (is equal '((:bnf-bracketed :content ("&key")))
      (bnf-nodes (begin :bracketed) (bnf-text "[&key]") (end :bracketed)))
  (is equal '((:bnf-zero-or-more :content ((:bnf-group :content ("x")))))
      (bnf-nodes (begin :zero-or-more) (begin :group) (bnf-text "x") (end :group)
                 (bnf-text "*") (end :zero-or-more)))
  (is equal '((:bnf-group :content ("a, b")))
      (bnf-nodes (begin :group) (bnf-text "a, b") (end :group))
      "braces are math characters: no text to remove")
  (is equal '((:bnf-optional :content ("a")))
      (bnf-nodes (begin :optional) (bnf-text "[") (bnf-text "a]") (end :optional))
      "a glyph that is an item of its own goes")
  (is equal '((:bnf-optional))
      (bnf-nodes (begin :optional) (bnf-text "[]") (end :optional))
      "nothing is left of an empty notation")
  (is equal '((:bnf-rule :name "r" :definition ("x")))
      (bnf-nodes (begin :bnf-rule "r") (bnf-text "r::") (bnf-text "x") (end :bnf-rule)))
  (is equal '((:bnf-parenthesized :content ((:bnf-group :content ("x")))))
      (bnf-nodes (begin :parenthesized) (bnf-text "(") (begin :group) (bnf-text "x")
                 (end :group) (bnf-text ")") (end :parenthesized))
      "a glyph that is a string of its own goes with it"))

(define-test bnf-leaves
  :parent bnf
  (is equal '((:bnf-indirection :name "pattern"))
      (bnf-nodes (begin :indirection "pattern") (end :indirection)))
  (is equal '((:angle-name :name "Newline"))
      (bnf-nodes (begin :angle "Newline") (bnf-text "Newline") (end :angle))
      "what the container shows is dropped")
  (is equal '((:bnf-caret))
      (bnf-nodes (begin :caret) (bnf-text "^") (end :caret)))
  (is equal '((:bnf-repeat-previous))
      (bnf-nodes (test-event :mark :repeat-previous)))
  (is equal '((:bnf-required :content ("A")))
      (bnf-nodes (begin :required "A") (bnf-text "A") (end :required))))

(define-test bnf-interleave
  :parent bnf
  ;; \interleave calls \begininterleave: the notation is reported twice.
  (multiple-value-bind (nodes report)
      (bnf-nodes (begin :interleave "A | B") (begin :interleave)
                 (begin :required "A") (bnf-text "A") (end :required)
                 (bnf-text " B") (end :interleave) (end :interleave))
    (is equal '((:bnf-interleave :content ((:bnf-required :content ("A")) " B")))
        nodes)
    (is equal '() (problem-kinds report)))
  (is equal '((:bnf-interleave :content ("a" (:bnf-interleave :content ("x")))))
      (bnf-nodes (begin :interleave) (bnf-text "a") (begin :interleave) (bnf-text "x")
                 (end :interleave) (end :interleave))
      "a second interleaving after content is a nested one"))

(define-test bnf-unclosed
  :parent bnf
  (multiple-value-bind (nodes report)
      (bnf-nodes (begin :optional) (bnf-text "x"))
    (declare (ignore nodes))
    (is equal '(:unclosed) (problem-kinds report))))

(define-test bnf-spec
  :parent bnf
  ;; concept-bvl.tex:586, run as the chapter job does.
  (multiple-value-bind (nodes report)
      (model:build-fixture "chap-3" :file "concept-bvl.tex" :lines '(586 586)
                                    :handlers *bnf-handlers*)
    (is equal '() (remove :unhandled (problem-kinds report)))
    (is = 1 (length nodes))
    (is eq :bnf-rule (model:node-kind (first nodes)))
    (is string= "wholevar" (model:bnf-rule-name (first nodes)))
    (is eq :bnf-bracketed (model:node-kind (first (model:bnf-rule-definition (first nodes)))))))
