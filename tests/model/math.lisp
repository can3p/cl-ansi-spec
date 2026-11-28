;;;; tests/model/math.lisp
;;;;
;;;; Tests of math (src/model/build-math.lisp): the character tables, the
;;;; handlers on events made here, and real formulas of the spec.

(in-package #:cl-ansi-spec/tests)

(define-test math
  :parent model
  :description "Math lists: noads, characters, fractions, delimiters and styles.")

;;; The tables

(define-test math-tables
  :parent math
  ;; Every row of every table has a code, a text and a reason, and codes are unique.
  (loop for (table . rows) in model:*math-tables*
        do (is = (length rows) (length (remove-duplicates rows :key #'first))
               "~S has no code twice" table)
           (dolist (row rows)
             (is = 3 (length row) "~S in ~S" row table)
             (true (and (stringp (second row)) (plusp (length (second row)))))
             (true (and (stringp (third row)) (plusp (length (third row)))))))
  ;; cmmi and cmsy have every slot.
  (is = 128 (length (cdr (assoc :cmmi model:*math-tables*))))
  (is = 128 (length (cdr (assoc :cmsy model:*math-tables*))))
  ;; Every family the jobs use has a font.
  (dolist (family '(0 1 2 3 4 5 6 7 8))
    (true (assoc family model:*math-families*)))
  (is equal '("π" t) (multiple-value-list (model:math-family-text 1 25)))
  (is equal '("α" t) (multiple-value-list (model:math-family-text 1 11)))
  (is equal '("ϵ" t) (multiple-value-list (model:math-family-text 1 15)))
  (is equal '("ε" t) (multiple-value-list (model:math-family-text 1 34)))
  ;; plain.tex:763,772: \phi is slot 30 (the stroked form), \varphi slot 39.
  (is equal '("ϕ" t) (multiple-value-list (model:math-family-text 1 30)))
  (is equal '("φ" t) (multiple-value-list (model:math-family-text 1 39)))
  ;; plain.tex:817-831: the big operators, text size, and the display size 8 after.
  (loop for (code text) in '((#x46 "⨆") (#x48 "∮") (#x4A "⨀") (#x4C "⨁") (#x4E "⨂")
                             (#x50 "∑") (#x51 "∏") (#x52 "∫") (#x53 "⋃") (#x54 "⋂")
                             (#x55 "⨄") (#x56 "⋀") (#x57 "⋁") (#x60 "∐"))
        do (is equal text (model:math-family-text 3 code) "cmex ~X" code)
           (is equal text (model:math-family-text 3 (if (= code #x60) #x61 (+ code (if (< code #x50) 1 8))))
               "cmex ~X, the next size" code))
  (is equal '("x" t) (multiple-value-list (model:math-family-text 1 120)))
  (is equal '("/" t) (multiple-value-list (model:math-family-text 1 61)))
  (is equal '("=" t) (multiple-value-list (model:math-family-text 0 61)))
  (is equal '("2" t) (multiple-value-list (model:math-family-text 0 50)))
  (is equal '("−" t) (multiple-value-list (model:math-family-text 2 0)))
  (is equal '("∈" t) (multiple-value-list (model:math-family-text 2 50)))
  (is equal '("𝒫" t) (multiple-value-list (model:math-family-text 2 80)))
  (is equal '("∧" t) (multiple-value-list (model:math-family-text 2 94)))
  (is equal '("⋃" t) (multiple-value-list (model:math-family-text 3 83)))
  (is equal '("<" t) (multiple-value-list (model:math-family-text 7 60)))
  (is equal '("∗" t) (multiple-value-list (model:math-family-text 8 3)))
  (is equal '("a" t) (multiple-value-list (model:math-family-text 5 97)))
  (is equal '(nil nil) (multiple-value-list (model:math-family-text 3 40)))
  (is equal '(nil nil) (multiple-value-list (model:math-family-text 9 0))))

;;; Events

(defvar *math-handlers*
  (model:install-math-handlers (model:make-handler-table))
  "Math's handlers only.")

(defun math-nodes (&rest events)
  "The top-level nodes of EVENTS built with the math handlers, as
S-expressions without spans, and the build report."
  (multiple-value-bind (nodes report)
      (model:build-events events :registry model:*registry* :handlers *math-handlers*)
    (values (mapcar (lambda (node) (math-strip-spans (model:node-sexp node))) nodes)
            report)))

(defun math-strip-spans (form)
  "FORM without its :SPAN entries."
  (cond ((atom form) form)
        ((eq (first form) :span) (math-strip-spans (cddr form)))
        (t (cons (math-strip-spans (first form)) (math-strip-spans (rest form))))))

(defun mchar (fam code)
  (test-event :math-char nil :fam fam :code code))

(defun noad (class &rest events)
  "A noad of CLASS whose nucleus holds EVENTS."
  (append (list (test-event :begin :noad :class class) (test-event :begin :nucleus))
          events
          (list (test-event :end :nucleus) (test-event :end :noad))))

(defun ord-char (fam code)
  (noad :ord (mchar fam code)))

(define-test math-noads
  :parent math
  (is equal '((:math :display t
               :content ((:math-noad :class :ord :nucleus ((:math-char :text "π"))
                          :superscript ((:math-char :text "2"))
                          :subscript ((:math-char :text "i"))))))
      (math-nodes (test-event :begin :math :display t)
                  (test-event :begin :noad :class :ord)
                  (test-event :begin :nucleus) (mchar 1 25) (test-event :end :nucleus)
                  (test-event :begin :superscript) (mchar 0 50) (test-event :end :superscript)
                  (test-event :begin :subscript) (mchar 1 105) (test-event :end :subscript)
                  (test-event :end :noad)
                  (test-event :end :math)))
  ;; An inline formula; an empty nucleus ({}) has no field; an empty formula no content.
  (is equal '((:math-noad :class :ord)) (math-nodes (test-event :begin :noad :class :ord)
                                                    (test-event :begin :nucleus)
                                                    (test-event :end :nucleus)
                                                    (test-event :end :noad)))
  (is equal '((:math)) (math-nodes (test-event :begin :math) (test-event :end :math)))
  ;; Operators with their limits, a radical and an accent.
  (is equal '((:math-noad :class :op :limits :no-limits :nucleus ((:math-char :text "∑"))))
      (math-nodes (test-event :begin :noad :class :op :limits :no-limits)
                  (test-event :begin :nucleus) (mchar 3 88) (test-event :end :nucleus)
                  (test-event :end :noad)))
  (is equal '((:math-noad :class :op :limits :limits))
      (math-nodes (test-event :begin :noad :class :op :limits :limits)
                  (test-event :end :noad)))
  (is equal '((:math-noad :class :radical :delimiter "√"))
      (math-nodes (test-event :begin :noad :class :radical :delimiter '(2 112 3 112))
                  (test-event :end :noad)))
  (is equal '((:math-noad :class :accent :delimiter "ˆ"))
      (math-nodes (test-event :begin :noad :class :accent :fam 0 :code 94)
                  (test-event :end :noad))))

(define-test math-fractions
  :parent math
  (flet ((fraction (&rest properties)
           (math-nodes (apply #'test-event :begin :fraction properties)
                       (test-event :begin :numerator) (mchar 0 49) (test-event :end :numerator)
                       (test-event :begin :denominator) (mchar 0 50) (test-event :end :denominator)
                       (test-event :end :fraction))))
    (is equal '((:math-fraction :numerator ((:math-char :text "1"))
                 :denominator ((:math-char :text "2"))))
        (fraction :command "over" :thickness :default))
    (is equal '((:math-fraction :numerator ((:math-char :text "1"))
                 :denominator ((:math-char :text "2")) :no-rule t))
        (fraction :command "atop" :thickness "0.0pt"))
    (is equal '((:math-fraction :numerator ((:math-char :text "1"))
                 :denominator ((:math-char :text "2")) :thickness "2.0pt"))
        (fraction :command "above" :thickness "2.0pt"))
    (is equal '((:math-fraction :numerator ((:math-char :text "1"))
                 :denominator ((:math-char :text "2")) :thickness "1.0pt"))
        (fraction :command "above" :thickness "1.0pt"))
    (is equal '((:math-fraction :numerator ((:math-char :text "1"))
                 :denominator ((:math-char :text "2"))
                 :left-delimiter "(" :right-delimiter ")"))
        (fraction :command "overwithdelims" :thickness :default
                  :left-delimiter '(0 40 3 0) :right-delimiter '(0 41 3 1)))))

(define-test math-delimiter-codes
  :parent math
  ;; The small character when there is one, else the large; zero is the null delimiter.
  (flet ((shown (delimiter)
           (getf (rest (first (math-nodes (test-event :left nil :delimiter delimiter))))
                 :text)))
    (is equal "(" (shown '(0 40 3 0)))
    (is equal ")" (shown '(0 41 3 1)))
    (is equal "{" (shown '(2 102 3 8)))
    (is equal "}" (shown '(2 103 3 9)))
    (is equal "|" (shown '(2 106 3 12)))
    (is eq nil (shown '(0 0 0 0)))
    ;; The large slot when the small one has no text (cmex 40 has none, 8 is {).
    (is equal "{" (shown '(3 40 3 8)))
    (is equal "∑" (shown '(0 0 3 88)))))

(define-test math-delimiters-styles-choices
  :parent math
  (is equal '((:math-noad :class :inner
               :nucleus ((:math-delimiter :text "(") (:math-char :text "x")
                         (:math-delimiter :right t))))
      (math-nodes (test-event :begin :noad :class :inner) (test-event :begin :nucleus)
                  (test-event :left nil :delimiter '(0 40 3 0)) (mchar 1 120)
                  (test-event :right nil :delimiter '(0 0 0 0))
                  (test-event :end :nucleus) (test-event :end :noad)))
  (is equal '((:math-style-change :style :script))
      (math-nodes (test-event :math-style nil :style :script)))
  (is equal '((:math-choice :display ((:math-char :text "A")) :text ((:math-char :text "a"))))
      (math-nodes (test-event :begin :math-choice)
                  (test-event :begin :choice :style :display) (mchar 1 65)
                  (test-event :end :choice)
                  (test-event :begin :choice :style :text) (mchar 1 97)
                  (test-event :end :choice)
                  (test-event :begin :choice :style :script) (test-event :end :choice)
                  (test-event :begin :choice :style :scriptscript) (test-event :end :choice)
                  (test-event :end :math-choice))))

(define-test math-equation-numbers
  :parent math
  (is equal '((:math :display t :content ((:math-char :text "x"))
               :equation-number ((:math-char :text "1"))))
      (math-nodes (test-event :begin :math :display t) (mchar 1 120)
                  (test-event :begin :eqno :command "eqno") (mchar 0 49)
                  (test-event :end :eqno) (test-event :end :math)))
  (is equal '((:math :display t :equation-number ((:math-char :text "1")) :number-left t))
      (math-nodes (test-event :begin :math :display t)
                  (test-event :begin :eqno :command "leqno") (mchar 0 49)
                  (test-event :end :eqno) (test-event :end :math))))

(defun math-string-nodes (&rest events)
  "The nodes of EVENTS built with the math handlers and a :SPACE handler
that leaves the string \" \" in the list, as a control space does."
  (let ((table (model:install-math-handlers (model:make-handler-table))))
    (model:register-handler :space nil
                            (lambda (builder event span)
                              (declare (ignore event span))
                              (model:add-item builder " "))
                            table)
    (model:build-events events :registry model:*registry* :handlers table)))

(defun math-span-range (node)
  "(start end) of NODE's span."
  (list (model:span-start (model:node-span node)) (model:span-end (model:node-span node))))

(define-test math-strings-and-problems
  :parent math
  ;; A control space reaches the list as a string: it becomes a character
  ;; with the span of its list, the string keeping no span of its own.
  (let* ((nodes (math-string-nodes (test-event :begin :noad :class :ord)
                                   (test-event :begin :nucleus :span (test-span 1 2 3))
                                   (test-event :space nil :span (test-span 1 3 4))
                                   (test-event :end :nucleus :span (test-span 1 5 6))
                                   (test-event :end :noad)))
         (char (first (model:node-field-value (first nodes) :nucleus))))
    (is equal '((:math-noad :class :ord :nucleus ((:math-char :text " "))))
        (mapcar (lambda (node) (math-strip-spans (model:node-sexp node))) nodes))
    (is equal '(2 6) (math-span-range char))
    (is equal '() (model:node-problems char)))
  ;; The same in the formula's own list.
  (let* ((nodes (math-string-nodes (test-event :begin :math :span (test-span 1 2 3))
                                   (test-event :space nil :span (test-span 1 3 4))
                                   (test-event :end :math :span (test-span 1 7 8))))
         (char (first (model:node-field-value (first nodes) :content))))
    (is equal '((:math :content ((:math-char :text " "))))
        (mapcar (lambda (node) (math-strip-spans (model:node-sexp node))) nodes))
    (is equal '(2 8) (math-span-range char)))
  ;; A slot without Unicode is reported, and shown as U+FFFD.
  (multiple-value-bind (nodes report) (math-nodes (mchar 3 40))
    (is equal (list (list :math-char :text (string (code-char #xFFFD)))) nodes)
    (is = 1 (length (model:build-report-problems report))))
  ;; A nucleus outside a noad is reported.
  (multiple-value-bind (nodes report)
      (math-nodes (test-event :begin :nucleus) (mchar 0 49) (test-event :end :nucleus))
    (declare (ignore nodes))
    (is = 1 (length (model:build-report-problems report)))))

;;; Real lines

(defun math-fixture (job file first last)
  "The nodes of JOB built from lines FIRST to LAST of FILE, as S-expressions."
  (mapcar (lambda (node) (if (stringp node) node (math-strip-spans (model:node-sexp node))))
          (model:build-fixture job :file file :lines (list first last))))

(define-test math-real-fraction
  :parent math
  ;; dict-numbers.tex:1435: $$ \ff{arccos} z = {\pi\over2}- \ff{arcsin} z$$
  (let* ((nodes (math-fixture "chap-12" "dict-numbers.tex" 1435 1435))
         (formula (find :math nodes :key #'first)))
    (true formula)
    (is eq t (getf (rest formula) :display))
    (let ((text (with-output-to-string (out) (prin1 formula out))))
      (true (search "(:MATH-FRACTION" text))
      (true (search "\"π\"" text))
      (true (search "\"−\"" text))
      (true (search "\"=\"" text)))))

(define-test math-real-left-right
  :parent math
  ;; dict-arrays.tex:27: $\left\{i\sub{0},i\sub{1},\dots,i\sub{r-1}\right\}$
  (let* ((nodes (math-fixture "chap-15" "dict-arrays.tex" 27 27))
         (text (with-output-to-string (out) (prin1 nodes out))))
    (true (search "(:MATH-DELIMITER :TEXT \"{\")" text))
    (true (search "(:MATH-DELIMITER :RIGHT T :TEXT \"}\")" text))
    (true (search ":CLASS :INNER" text))))
