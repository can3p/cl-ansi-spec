;;;; tests/model/text.lisp
;;;;
;;;; Tests of text and fonts (src/model/build-text.lisp): the layout tables
;;;; and ligatures, the font classes, accents, discretionaries and the text
;;;; segments, on events made here, and on real lines of the spec.

(in-package #:cl-ansi-spec/tests)

(define-test text
  :parent model
  :description "Text and fonts: characters to Unicode, font runs to inlines.")

;;; The tables

(defun shown (file raw)
  "The text RAW typed in the font FILE shows."
  (values (model:convert-text file raw)))

(define-test text-layout-tables
  :parent text
  ;; Every font the 24 chapter jobs set text in (a survey of their :text events).
  (dolist (file '("cmr10" "cmr7" "cmtt9" "cmbx9" "cmbx10" "cmbxsl10" "cmti10" "cmssi10"))
    (true (model:font-entry file) "~A has a layout" file))
  (false (model:font-entry "amr10"))
  (is equal "cmbx10" (model:font-file "cmbx10 scaled 1728"))
  (is equal "cmr10" (model:font-file "cmr10"))
  (is eq nil (model:font-file nil))
  ;; The codes the jobs use that are not ASCII's, from the survey.
  (is string= "¸" (shown "cmr10" (string (code-char 24))))
  (is string= "¯" (shown "cmbx10" (string (code-char 22))))
  (is string= "¨" (shown "cmbx10" (string (code-char 127))))
  (is string= "’" (shown "cmr10" "'"))
  (is string= "‘" (shown "cmr10" "`"))
  (is string= "$" (shown "cmr10" "$"))
  (is string= "£" (shown "cmti10" "$"))
  (is string= "<" (shown "cmtt9" "<"))
  (is string= "¡" (shown "cmr10" "<"))
  (is string= "\\{}|~" (shown "cmtt9" "\\{}|~"))
  (is string= "fi" (shown "cmr10" "fi") "f ligatures are not applied")
  ;; Each slot of a layout names its reason.
  (loop for (layout . rows) in model:*layout-codes*
        do (dolist (row rows)
             (is = 3 (length row) "~S in ~S has a code, a text and a reason" row layout)
             (true (stringp (third row))))))

(define-test text-ligatures
  :parent text
  (is string= "“a”" (shown "cmr10" "``a''"))
  (is string= "N–M" (shown "cmr10" "N--M"))
  (is string= "a—b" (shown "cmr10" "a---b"))
  (is string= "—-" (shown "cmr10" "----"))
  (is string= "¡¿" (shown "cmr10" "!`?`"))
  (is string= "“a”" (shown "cmti10" "``a''"))
  (is string= "``a''--" (shown "cmtt9" "``a''--") "the code font has no ligatures")
  (is string= "a-b" (shown "cmr10" "a-b")))

(define-test text-font-classes
  :parent text
  (is eq :code (model:font-class "cmtt9"))
  (is eq :emphasis (model:font-class "cmti10"))
  (is eq :emphasis (model:font-class "cmssi10"))
  (is eq :strong (model:font-class "cmbx9"))
  (is eq :strong (model:font-class "cmbxsl10"))
  (is eq :strong (model:font-class "cmbx10"))
  (is eq nil (model:font-class "cmr10"))
  (is eq nil (model:font-class "cmr7"))
  (is eq nil (model:font-class "unknown10")))

;;; Events

(defvar *text-handlers*
  (let ((table (model:install-text-handlers (model:make-handler-table))))
    (flet ((container (key node-kind &optional field)
             (model:register-handler
              :begin key
              (lambda (builder event span)
                (declare (ignore event))
                (model:open-container
                 builder key span
                 :node (and node-kind (model:make-builder-node builder node-kind))
                 :field field))
              table)))
      (container :paragraph :paragraph 'model::content)
      (container :term nil)
      (container :section nil))
    table)
  "Text's handlers, and a paragraph and a pass-through :TERM container.")

(defun text-nodes (&rest events)
  "The top-level nodes of EVENTS, built with the text handlers, as
S-expressions (strings stay strings), and the build report."
  (multiple-value-bind (nodes report)
      (model:build-events events :registry model:*registry* :handlers *text-handlers*)
    (values (mapcar (lambda (node) (if (stringp node) node (model:node-sexp node))) nodes)
            report)))

(defun txt (text &optional (style "cmr10"))
  "A :text event."
  (test-event :text text :style style))

(defun paragraph-content (&rest events)
  "The content of the paragraph the EVENTS make, as S-expressions with
the spans left out, and the build report."
  (multiple-value-bind (nodes report)
      (apply #'text-nodes (append (list (test-event :begin :paragraph))
                                  events (list (test-event :end :paragraph))))
    (values (labels ((strip (item)
                       (if (stringp item)
                           item
                           (cons (first item)
                                 (loop for (key value) on (rest item) by #'cddr
                                       unless (eq key :span)
                                         append (list key (if (listp value) (mapcar #'strip value) value)))))))
              (let ((paragraph (first nodes)))
                (mapcar #'strip (getf (rest paragraph) :content))))
            report)))

(define-test text-runs
  :parent text
  (is equal '("The " (:code :content ("car")) " of " (:emphasis :content ("a list")) ".")
      (paragraph-content (txt "The ") (txt "car" "cmtt9") (txt " of ") (txt "a list" "cmti10")
                         (txt ".")))
  (is equal '("see " (:strong :content ("Syntax")) ":")
      (paragraph-content (txt "see ") (txt "Syntax" "cmbx9") (txt ":")))
  (is equal '("“quoted” N–M")
      (paragraph-content (txt "``quoted'' N") (txt "--M")))
  ;; Spaces: a space between runs of one class stays inside, else it is plain.
  (is equal '((:emphasis :content ("a b")) " c")
      (paragraph-content (txt "a" "cmti10") (test-event :space nil) (txt "b" "cmti10")
                         (test-event :space nil) (txt "c")))
  (is equal '("a" (:code :content ("b")) " ")
      (paragraph-content (txt "a") (txt "b" "cmtt9") (test-event :space nil)))
  (is equal '("a" (:code :content ("b")) "  c")
      (paragraph-content (txt "a") (txt "b" "cmtt9") (test-event :space nil)
                         (test-event :space nil) (txt "c"))))

(define-test text-in-entries
  :parent text
  (is equal '("a " "plain" " b")
      (paragraph-content (txt "a ") (test-event :begin :term) (txt "plain" "cmtt9")
                         (test-event :end :term) (txt " b"))
      "text of an entry's own container is not read by font")
  (is equal '("x")
      (text-nodes (test-event :begin :section) (txt "x" "cmbx10 scaled 1728")
                  (test-event :end :section))
      "a heading, in its section's container, keeps the characters")
  (true (model:plain-text-container-p :term))
  (true (model:plain-text-container-p :section))
  (false (model:plain-text-container-p :paragraph)))

(define-test text-segments
  :parent text
  ;; An item another handler adds ends the segment: no ligature across it.
  (is equal '("a-" "b" "-c")
      (let ((table (model:make-handler-table)))
        (model:install-text-handlers table)
        (model:register-handler :mark :stop
                                (lambda (builder event span)
                                  (declare (ignore event span))
                                  (model:add-item builder "b"))
                                table)
        (model:build-events (list (txt "a-") (test-event :mark :stop) (txt "-c"))
                            :registry model:*registry* :handlers table)))
  (multiple-value-bind (nodes report)
      (text-nodes (txt "x" "amr10"))
    (is equal '("x") nodes)
    (is equal '(:diagnostic) (problem-kinds report)))
  (multiple-value-bind (nodes report)
      (text-nodes (txt "x" "amr10") (txt "y" "amr10") (txt "z" "amr10"))
    (is equal '("xyz") nodes)
    (is equal '(:diagnostic) (problem-kinds report) "one report per font")))

(define-test text-accents
  :parent text
  (is equal '("é") (text-nodes (test-event :begin :accent) (txt (string (code-char 19)))
                               (txt "e") (test-event :end :accent)))
  (is equal '("ç") (text-nodes (test-event :begin :accent) (txt (string (code-char 24)))
                               (txt "c") (test-event :end :accent)))
  (is equal (list (format nil "u~C" (code-char #x307)))
      (text-nodes (test-event :begin :accent) (txt "_") (txt "u")
                  (test-event :end :accent))
      "no precomposed u with dot above: the combining mark follows")
  (is equal '("´") (text-nodes (test-event :begin :accent) (txt (string (code-char 19)))
                               (test-event :end :accent))
      "an accent without a character shows its spacing form")
  (is equal '("x") (text-nodes (test-event :begin :accent) (txt "x") (test-event :end :accent))
      "an unknown accent keeps the characters")
  ;; The accent's font and the character's may differ; the result has the character's.
  (is equal '("a " (:code :content ("é")))
      (paragraph-content (txt "a ") (test-event :begin :accent) (txt (string (code-char 19)))
                         (txt "e" "cmtt9") (test-event :end :accent))))

(define-test text-discretionaries
  :parent text
  (is equal '("ab")
      (text-nodes (test-event :begin :discretionary :command "discretionary")
                  (test-event :begin :pre-break) (txt "-") (test-event :end :pre-break)
                  (test-event :begin :post-break) (txt "+") (test-event :end :post-break)
                  (test-event :begin :no-break) (txt "ab") (test-event :end :no-break)
                  (test-event :end :discretionary)))
  (is equal '("ab")
      (text-nodes (txt "a") (test-event :begin :discretionary :command "-")
                  (test-event :begin :pre-break) (txt "-") (test-event :end :pre-break)
                  (test-event :end :discretionary) (txt "b"))
      "a dropped list leaves nothing, and the text goes on")
  (is equal '()
      (text-nodes (test-event :begin :discretionary :command "-")
                  (test-event :begin :pre-break) (txt "-") (test-event :end :pre-break)
                  (test-event :end :discretionary))))

;;; Real lines

(defun fixture-strings (job file first last)
  "The strings among the nodes of FILE's lines FIRST to LAST of JOB."
  (remove-if-not #'stringp (model:build-fixture job :file file :lines (list first last))))

(define-test text-spec-lines
  :parent text
  ;; concept-bvl.tex:1061: `` and '' quotes.
  (true (find-if (lambda (string) (search "(sometimes called a “boa constructor”)." string))
                 (fixture-strings "chap-3" "concept-bvl.tex" 1061 1061)))
  ;; dict-conses.tex:445: \.u, a dot above, in the code and bold fonts.  The
  ;; line is a pronunciation, which the sources set inside a formula (3.15m),
  ;; so the string is looked for at any depth.
  (true (find-if (lambda (string) (search (format nil "u~C" (code-char #x307)) string))
                 (sexp-strings (mapcar (lambda (node) (if (stringp node) node (model:node-sexp node)))
                                       (model:build-fixture "chap-14" :file "dict-conses.tex"
                                                                      :lines '(445 445)))))))

(defun sexp-strings (form)
  "Every string in the tree FORM."
  (cond ((stringp form) (list form))
        ((consp form) (append (sexp-strings (car form)) (sexp-strings (cdr form))))))
