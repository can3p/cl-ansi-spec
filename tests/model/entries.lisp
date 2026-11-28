;;;; tests/model/entries.lisp
;;;;
;;;; Tests of dictionary entries (src/model/build-entries.lisp): names,
;;;; kinds, parts and signatures, on events made here and on the real lines
;;;; of the spec.  The handlers are the entry handlers and the text
;;;; handlers in a table of their own, with a paragraph and a parameter
;;;; made here, so that the tests do not depend on the other builder steps.

(in-package #:cl-ansi-spec/tests)

(define-test entries
  :parent model
  :description "Dictionary entries: names, kinds, parts and signatures.")

(defvar *entry-handlers*
  (let ((table (model:install-entry-handlers
                (model:install-text-handlers (model:make-handler-table)))))
    (model:register-handler
     :begin :paragraph
     (lambda (builder event span)
       (declare (ignore event))
       (model:open-container builder :paragraph span
                             :node (model:make-builder-node builder :paragraph)
                             :field 'model::content))
     table)
    (model:register-handler
     :begin :param
     (lambda (builder event span)
       (model:open-container
        builder :param span
        :node (model:make-builder-node
               builder :param :name (first (model:event-argument-texts builder event)))))
     table)
    table)
  "The entry handlers, the text handlers, a paragraph and a parameter.")

(defun entries-strip-spans (item)
  "ITEM, a string or the S-expression of a node, without its spans."
  (if (atom item)
      item
      (cons (first item)
            (loop for (key value) on (rest item) by #'cddr
                  unless (eq key :span)
                    append (list key (if (consp value) (mapcar #'entries-strip-spans value) value))))))

(defun entry-sexps (&rest events)
  "The nodes the EVENTS build with the entry handlers, as S-expressions
without spans, and the build report."
  (multiple-value-bind (nodes report)
      (model:build-events events :registry model:*registry* :handlers *entry-handlers*)
    (values (mapcar (lambda (node) (entries-strip-spans (if (stringp node) node (model:node-sexp node))))
                    nodes)
            report)))

(defun entries-problem-messages (report &optional (kinds '(:node :unclosed :underflow :unmatched-end)))
  "The messages of REPORT's problems of KINDS."
  (loop for problem in (model:build-report-problems report)
        when (member (model:problem-kind problem) kinds)
          collect (or (model:problem-message problem) (model:problem-kind problem))))

(defun ev (type head &rest properties)
  "An event for the tests (TEST-EVENT)."
  (apply #'test-event type head properties))

(defun args (&rest texts)
  "The :ARGUMENTS property of a test event: its argument texts."
  (list :arguments texts))

(defun begin-event (key &rest texts) (ev :begin key :arguments texts))
(defun mark-event (key &rest texts) (ev :mark key :arguments texts))

(defun signature-events (key texts head &optional tail)
  "The events of a signature of KEY with arguments TEXTS: the words HEAD
(strings), then the arrow and the words TAIL when there is TAIL."
  (append (list (apply #'begin-event key texts))
                        (loop for text in head collect (ev :text text :style "cmbx10"))
                        (when tail
                          (list (ev :begin :evaluates-to) (ev :begin :math) (ev :end :math)
                                (ev :end :evaluates-to)))
                        (loop for text in tail collect (ev :text text :style "cmr10"))
                        (list (ev :end key))))

;;; Names and kinds

(define-test entries-names-and-kinds
  :parent entries
  (is equal '("car" "cdr" "caar") (model::split-names "car,  cdr,
   caar,"))
  (is equal '("char=" "char/=") (model::split-names " char= , char/=  "))
  (is eq :system-class (model::entry-kind-keyword "System Class"))
  (is eq :standard-generic-function (model::entry-kind-keyword "  Standard Generic
 Function  "))
  (is eq :function (model::entry-kind-keyword "Function")))

;;; Entries and parts, on events made here

(define-test entries-parts
  :parent entries
  (multiple-value-bind (nodes report)
      (entry-sexps (begin-event :com "car, cdr" "Accessor")
                   (ev :begin :paragraph) (ev :text "car cdr Accessor") (ev :end :paragraph)
                   (mark-event :label "Syntax" ":")
                   (ev :begin :box) (ev :text "Syntax:") (ev :end :box)
                   (ev :begin :paragraph) (ev :text "one") (ev :end :paragraph)
                   (mark-event :label "Side Effects" "\\None")
                   (mark-event :label-confidence ".")
                   (mark-event :label "Notes" ":")
                   (ev :begin :paragraph) (ev :text "two") (ev :end :paragraph)
                   (ev :end :com))
    (is equal '((:dictionary-entry
                 :id "car" :names ("car" "cdr") :entry-kind :accessor
                 :parts ((:part :title "Syntax"
                          :content ((:paragraph :content ("one"))))
                         (:part :title "Side Effects" :none t :confidence ".")
                         (:part :title "Notes"
                          :content ((:paragraph :content ("two")))))))
        nodes)
    (is equal '() (entries-problem-messages report)
        "The heading and the label boxes are dropped without a report."))
  ;; A kind outside the enum is reported, and the entry has none.
  (multiple-value-bind (nodes report)
      (entry-sexps (begin-event :com "x" "Special Form") (ev :end :com))
    (is equal '((:dictionary-entry :id "x" :names ("x"))) nodes)
    (is = 2 (length (entries-problem-messages report))
        "An unknown kind, and the entry's missing required kind."))
  ;; Something with a meaning in a heading is not dropped silently.
  (multiple-value-bind (nodes report)
      (entry-sexps (begin-event :com "x" "Function")
                   (ev :begin :paragraph) (mark-event :label "Odd" ":") (ev :end :paragraph)
                   (ev :end :com))
    (declare (ignore nodes))
    (true (some (lambda (message) (search "The heading of an entry holds" message))
                (entries-problem-messages report))))
  ;; A label outside an entry, and a stray end.
  (multiple-value-bind (nodes report)
      (entry-sexps (mark-event :label "Syntax" ":") (ev :end :com))
    (declare (ignore nodes))
    (true (some (lambda (message) (search "outside any entry" message))
                (entries-problem-messages report)))
    (true (member :underflow (mapcar #'model:problem-kind (model:build-report-problems report)))))
  ;; What stands between the entry's start and its first label is its
  ;; content; text there is no block, which the entry's check reports.
  (multiple-value-bind (nodes report)
      (entry-sexps (begin-event :com "x" "Function")
                   (ev :begin :paragraph) (ev :text "x Function") (ev :end :paragraph)
                   (ev :text "stray")
                   (ev :end :com))
    (is equal '((:dictionary-entry :id "x" :names ("x") :entry-kind :function
                 :content ("stray")))
        nodes)
    (true (some (lambda (message) (search "content" message))
                (entries-problem-messages report)))))

(define-test entries-end-inside-a-paragraph
  :parent entries
  ;; \endcom inside the entry's last paragraph (dict-conses.tex:201): the
  ;; paragraph closes where TeX closed it, with no problem.
  (multiple-value-bind (nodes report)
      (entry-sexps (begin-event :com "cons" "Function")
                   (mark-event :label "Notes" ":")
                   (ev :begin :paragraph) (ev :text "last" :style "cmr10") (ev :end :com)
                   (ev :glue nil :glue "1.0pt" :command "vskip") (ev :end :paragraph)
                   (ev :begin :paragraph) (ev :text "next" :style "cmr10") (ev :end :paragraph))
    (is equal '((:dictionary-entry
                 :id "cons" :names ("cons") :entry-kind :function
                 :parts ((:part :title "Notes" :content ((:paragraph :content ("last"))))))
                (:paragraph :content ("next")))
        nodes)
    (is equal '() (entries-problem-messages report))
    (is equal '(:unhandled) (mapcar #'model:problem-kind (model:build-report-problems report))
        "Only the glue, which no handler of this table takes.")))

;;; Signatures, on events made here

(defun signature-of (key texts head &optional tail)
  "The signature node (its S-expression) of KEY built from the words HEAD
and TAIL, and the report."
  (multiple-value-bind (nodes report)
      (apply #'entry-sexps (signature-events key texts head tail))
    (values (first nodes) report)))

(define-test entries-operator-signatures
  :parent entries
  (loop for (key operator no-return) in '((:defun :function) (:defmac :macro)
                                          (:defspec :special-operator) (:defgen :generic-function)
                                          (:defmeth :method) (:defun-no-return :function t)
                                          (:defmac-no-return :macro t)
                                          (:defspec-no-return :special-operator t))
        do (multiple-value-bind (node report)
               (signature-of key '("find" "list {\\opt} test") '("find " "list &optional test")
                             (unless no-return '("item")))
             (is equal `(:operator-signature :operator ,operator :names ("find")
                                             :lambda-list ("list &optional test")
                                             ,@(unless no-return '(:values ("item")))
                                             ,@(when no-return '(:no-return t)))
                 node)
             (is equal '() (entries-problem-messages report))))
  ;; A no-return signature has the arrow, and no values.
  (is equal '(:operator-signature :operator :function :names ("error") :no-return t)
      (signature-of :defun-no-return '("error") '("error")
                    '("ignored")))
  ;; No lambda list, no values.
  (is equal '(:operator-signature :operator :method :names ("describe-object")
              :lambda-list ("(object standard-object) stream"))
      (signature-of :defmeth '("describe-object")
                    '("describe-object (object standard-object) stream")))
  ;; Parameters stand as nodes in the lambda list and the values.
  (multiple-value-bind (nodes report)
      (entry-sexps (begin-event :defun "endp" "list" "boolean")
                   (ev :text "endp ") (ev :begin :param :arguments '("list")) (ev :end :param)
                   (ev :begin :evaluates-to) (ev :end :evaluates-to)
                   (ev :begin :param :arguments '("boolean")) (ev :end :param)
                   (ev :end :defun))
    (is equal '((:operator-signature :operator :function :names ("endp")
                 :lambda-list ((:param :name "list")) :values ((:param :name "boolean"))))
        nodes)
    (is equal '() (entries-problem-messages report)))
  ;; A signature that does not start with its name is reported, and kept.
  (multiple-value-bind (node report) (signature-of :defun '("f") '("g x"))
    (is equal '(:operator-signature :operator :function :names ("f")
                :lambda-list ("g x"))
        node)
    (is = 1 (length (entries-problem-messages report)))))

(define-test entries-setf-variable-and-type-signatures
  :parent entries
  (is equal '(:setf-signature :names ("nth") :lambda-list ("n list") :new-value ("new-object"))
      (signature-of :defsetf '("nth" "n list" "new-object") '("(setf (nth n list) new-object)")))
  ;; Parentheses in the lambda list do not end it.
  (is equal '(:setf-signature :names ("f") :lambda-list ("(a b) c") :new-value ("v"))
      (signature-of :defsetf '("f") '("(setf (f (a b) c) v)")))
  (multiple-value-bind (node report)
      (signature-of :defsetf '("f") '("f x"))
    (is equal '(:setf-signature :names ("f") :new-value ("f x")) node)
    (true (entries-problem-messages report)))
  (is equal '(:variable-signature :name "*print-pretty*")
      (signature-of :defvar '("print-pretty") '("*print-pretty*")))
  (is equal '(:variable-signature :name "pi" :constant t)
      (signature-of :defcon '("pi") '("pi")))
  ;; \Deftype: the name, and one line of syntax per row.
  (multiple-value-bind (nodes report)
      (entry-sexps (mark-event :deftype "cons" "...")
                   (ev :begin :alignment)
                   (ev :begin :row) (ev :begin :cell) (ev :text "(cons ") (ev :text "car-typespec")
                   (ev :text ")") (ev :end :cell) (ev :end :row)
                   (ev :begin :row) (ev :begin :cell) (ev :text "(cons ") (ev :text "x")
                   (ev :text ")") (ev :end :cell) (ev :end :row)
                   (ev :begin :row) (ev :begin :cell) (ev :end :cell) (ev :end :row)
                   (ev :end :alignment))
    (is equal '((:type-signature :name "cons"
                 :syntax ("car-typespec" (:bnf-break) "x")))
        nodes)
    (is equal '() (entries-problem-messages report)))
  ;; A type specifier with no syntax.
  (is equal '((:type-signature :name "null"))
      (entry-sexps (mark-event :deftype "null" "..."))))

(define-test entries-multi-signatures
  :parent entries
  (flet ((rows (&rest rows)
           ;; Each row is its name then its words (a list of strings).
           (loop for (name . words) in rows
                 append (append (list (mark-event :entry name) (ev :begin :row) (ev :begin :cell))
                                (loop for word in words collect (ev :text word))
                                (list (ev :end :cell) (ev :end :row))))))
    (multiple-value-bind (nodes report)
        (apply #'entry-sexps
               (append (list (begin-event :defun-multi "x" "v" "...") (ev :begin :alignment))
                       (rows '("bit" "bit " "a"))
                       (list (ev :begin :cell) (ev :begin :evaluates-to) (ev :end :evaluates-to)
                             (ev :text "bit") (ev :end :cell))
                       (rows '("sbit" "sbit " "a"))
                       (list (ev :end :alignment) (ev :end :defun-multi))))
      (declare (ignore report))
      (is equal '((:operator-signature :operator :function :names ("bit" "sbit")
                   :lambda-list ("a") :values ("bit")))
          nodes))
    ;; An accessor sets a second table with the setf forms; the names repeat.
    (multiple-value-bind (nodes report)
        (apply #'entry-sexps
               (append (list (begin-event :defun-multi-accessor "x" "o" "n") (ev :begin :alignment))
                       (rows '("car" "car " "x"))
                       (list (ev :begin :evaluates-to) (ev :end :evaluates-to) (ev :text "o"))
                       (rows '("cdr" "cdr " "x"))
                       (rows '("car" "(setf (car " "x" ") " "n" ")"))
                       (rows '("cdr" "(setf (cdr " "x" ") " "n" ")"))
                       (list (ev :end :alignment) (ev :end :defun-multi-accessor))))
      (is equal '((:operator-signature :operator :function :names ("car" "cdr")
                   :lambda-list ("x") :values ("o"))
                  (:setf-signature :names ("car" "cdr") :lambda-list ("x") :new-value ("n")))
          nodes)
      (is equal '() (entries-problem-messages report)))
    (multiple-value-bind (nodes report)
        (apply #'entry-sexps
               (append (list (begin-event :defsetf-multi "x" "n") (ev :begin :alignment))
                       (rows '("bit" "(setf (bit " "a" ") " "n" ")"))
                       (rows '("sbit" "(setf (sbit " "a" ") " "n" ")"))
                       (list (ev :end :alignment) (ev :end :defsetf-multi))))
      (is equal '((:setf-signature :names ("bit" "sbit") :lambda-list ("a") :new-value ("n")))
          nodes)
      (is equal '() (entries-problem-messages report)))
    ;; A multi signature without a name is reported.
    (is = 1 (length (entries-problem-messages
                     (nth-value 1 (entry-sexps (begin-event :defun-multi "x" "v" "...")
                                               (ev :end :defun-multi))))))
    ;; \entry outside a signature (a row of \tabletwo) builds nothing, reports nothing.
    (multiple-value-bind (nodes report) (entry-sexps (mark-event :entry "a" "b"))
      (is equal '() nodes)
      (is equal '() (model:build-report-problems report)))))

;;; Real lines

(defun job-of-file (file)
  "The chapter job that reads FILE (a name with its type)."
  (find-if (lambda (job)
             (member file (cl-ansi-spec/inventory:survey-files
                           (cl-ansi-spec/inventory:survey-job job))
                     :test #'string=))
           (cl-ansi-spec:chapter-jobs)))

(defun spec-nodes (file first last)
  "The nodes the entry handlers build from FILE's lines FIRST to LAST, as
S-expressions without spans, and the report."
  (multiple-value-bind (nodes report)
      (model:build-fixture (job-of-file file) :file file :lines (list first last)
                                              :handlers *entry-handlers*)
    (values (mapcar (lambda (node) (entries-strip-spans (if (stringp node) node (model:node-sexp node))))
                    nodes)
            report)))

(defparameter *entry-problem-texts*
  '("The entry" "The signature" "The label" "The setf" "A syntax" "A label confidence"
    "The syntax of" "The paragraph of a signature" "The heading" "stands in the entry"
    "has the kind")
  "What the messages of the problems the entry handlers report contain.")

(defun entry-problems (report &key (labels t))
  "The problems of REPORT the entry handlers decide: their own reports
and the containers they leave open (not the events other steps take, nor
what this file's paragraph makes of a range of lines).  Without LABELS,
a part cut off by the range's start or end is not one."
  (loop for problem in (model:build-report-problems report)
        for message = (model:problem-message problem)
        when (case (model:problem-kind problem)
               ((:unclosed :underflow :unmatched-end)
                (or labels (not (search ":LABEL" (or message "")))))
               (:node (and message
                           (some (lambda (text) (search text message)) *entry-problem-texts*)
                           (or labels (not (search "The label" message))))))
          collect problem))

(define-test entries-spec-endp
  :parent entries
  (multiple-value-bind (nodes report) (spec-nodes "dict-conses.tex" 1702 1760)
    (let ((entry (find :dictionary-entry nodes :key #'first)))
      (is equal '(:dictionary-entry :id "endp" :names ("endp") :entry-kind :function)
          (subseq entry 0 7))
      (is equal '("Syntax" "Arguments and Values" "Description" "Examples" "Side Effects"
                  "Affected By" "Exceptional Situations" "See Also" "Notes")
          (loop for part in (getf (rest entry) :parts) collect (getf (rest part) :title)))
      (let ((syntax (first (getf (rest entry) :parts))))
        (is equal '(:part :title "Syntax"
                    :content ((:operator-signature :operator :function :names ("endp")
                               :lambda-list ("list") :values ("generalized-boolean"))))
            syntax))
      (let ((side-effects (fifth (getf (rest entry) :parts))))
        (is equal '(:part :title "Side Effects" :none t :confidence ".") side-effects)))
    (is equal '() (entry-problems report))))

;; The first entry of each kind: its file, the lines of the entry.
(defparameter *kind-fixtures*
  '((:function "dict-arrays.tex" 512 838) (:system-class "dict-arrays.tex" 11 165)
    (:macro "dict-conditions.tex" 366 499) (:condition-type "dict-conditions.tex" 17 102)
    (:variable "dict-conditions.tex" 1582 1658) (:type "dict-arrays.tex" 167 264)
    (:accessor "dict-arrays.tex" 1266 1342)
    (:standard-generic-function "dict-environment.tex" 430 525)
    (:special-operator "dict-eval-compile.tex" 448 788)
    (:type-specifier "dict-numbers.tex" 651 681)
    (:constant-variable "dict-arrays.tex" 2069 2093)
    (:declaration "dict-eval-compile.tex" 2765 2871) (:restart "dict-conditions.tex" 3666 3693)
    (:local-macro "dict-iteration.tex" 819 941) (:class "dict-types.tex" 562 604)
    (:symbol "dict-eval-compile.tex" 12 64) (:local-function "dict-objects.tex" 3597 3642))
  "For each entry kind, an entry of the spec of that kind.")

(define-test entries-spec-kinds
  :parent entries
  (is equal (sort (mapcar #'first (copy-list *kind-fixtures*)) #'string<)
      (sort (mapcar #'first (model:enum-values (model:find-enum 'model::entry-kind))) #'string<)
      "Every entry kind has a fixture.")
  (loop for (kind file first last) in *kind-fixtures*
        do (multiple-value-bind (nodes report) (spec-nodes file first last)
             (let ((entry (find :dictionary-entry nodes :key #'first)))
               (is eq kind (getf (rest entry) :entry-kind) "~S: the kind" kind)
               (true (getf (rest entry) :names) "~S: names" kind)
               (true (getf (rest entry) :parts) "~S: parts" kind)
               (is equal '() (entry-problems report) "~S: no problem" kind)))))

(defparameter *signature-fixtures*
  '((:defun "dict-conditions.tex" 2728 2729 :operator-signature)
    (:defun-with-values "dict-arrays.tex" 1209 1210 :operator-signature)
    (:defun-with-values-newline "dict-arrays.tex" 516 525 :operator-signature)
    (:defun-no-return "dict-conditions.tex" 506 507 :operator-signature)
    (:defmac-with-values "dict-conditions.tex" 807 808 :operator-signature)
    (:defmac-with-values-newline "dict-conditions.tex" 370 378 :operator-signature)
    (:defmac-no-return "dict-flow.tex" 2770 2771 :operator-signature)
    (:defspec "dict-eval-compile.tex" 18 19 :operator-signature)
    (:defspec-with-values "dict-eval-compile.tex" 452 455 :operator-signature)
    (:defspec-with-values-newline "dict-eval-compile.tex" 2227 2236 :operator-signature)
    (:defspec-no-return "dict-flow.tex" 2471 2472 :operator-signature)
    (:defgen-with-values "dict-environment.tex" 436 438 :operator-signature)
    (:defgen-with-values-newline "dict-objects.tex" 616 624 :operator-signature)
    (:defmeth "dict-environment.tex" 440 441 :operator-signature)
    (:defsetf "dict-arrays.tex" 1271 1272 :setf-signature)
    (:defsetf-multi "dict-arrays.tex" 2521 2535 :setf-signature)
    (:defun-multi "dict-arrays.tex" 2521 2535 :operator-signature)
    (:defun-multi-accessor "dict-conses.tex" 405 445 :setf-signature)
    (:deftype "dict-conses.tex" 104 106 :type-signature))
  "A use of each signature macro the sources use: its lines, the kind of
node it builds (Defmac, Defgen, Defvar and Defcon are not used by any
entry: their events are made above).")

(define-test entries-spec-signatures
  :parent entries
  (loop for (name file first last kind) in *signature-fixtures*
        do (multiple-value-bind (nodes report) (spec-nodes file first last)
             (let ((node (find kind nodes :key #'first)))
               (true node "~S: a ~S" name kind)
               (when node
                 (true (or (getf (rest node) :name) (getf (rest node) :names))
                       "~S: named" name))
               (is equal '() (entry-problems report :labels nil) "~S: no problem" name)))))

(define-test entries-spec-signature-shapes
  :parent entries
  ;; \DefunMultiAccessorWithValues: the readers and the setf forms of car … cddddr.
  (let* ((nodes (spec-nodes "dict-conses.tex" 405 445))
         (operator (find :operator-signature nodes :key #'first))
         (setf-form (find :setf-signature nodes :key #'first)))
    (is = 30 (length (getf (rest operator) :names)))
    (is equal '("car" "cdr") (subseq (getf (rest operator) :names) 0 2))
    (is equal '("x") (getf (rest operator) :lambda-list))
    (is equal '("object") (getf (rest operator) :values))
    (is equal '("x") (getf (rest setf-form) :lambda-list))
    (is equal '("new-object") (getf (rest setf-form) :new-value)))
  ;; \DefunNoReturn: no values.
  (let ((node (find :operator-signature (spec-nodes "dict-conditions.tex" 506 507) :key #'first)))
    (is equal '("error") (getf (rest node) :names))
    (is eq t (getf (rest node) :no-return))
    (false (getf (rest node) :values)))
  ;; \Deftype{cons}: the syntax line.
  (let ((node (find :type-signature (spec-nodes "dict-conses.tex" 104 106) :key #'first)))
    (is equal "cons" (getf (rest node) :name))
    (true (getf (rest node) :syntax))))

(define-test entries-spec-patched-kinds
  :parent entries
  ;; The three \ftype variants the sources spelled otherwise are patches 0004-0006.
  (loop for (kind file line) in '((:function "dict-environment.tex" 83)
                                  (:special-operator "dict-flow.tex" 2048)
                                  (:macro "dict-streams.tex" 2802))
        do (let ((entry (find :dictionary-entry (spec-nodes file line (+ line 1)) :key #'first)))
             (is eq kind (getf (rest entry) :entry-kind)))))

(define-test entries-spec-ends-inside-paragraph
  :parent entries
  ;; dict-conses.tex:201 and :4021: \endcom ends the last paragraph.
  (loop for (first last) in '((151 206) (3873 4026))
        do (multiple-value-bind (nodes report) (spec-nodes "dict-conses.tex" first last)
             (declare (ignore nodes))
             (is equal '() (entry-problems report)))))
