;;;; tests/model/blocks.lisp
;;;;
;;;; Tests of blocks (src/model/build-blocks.lisp): paragraphs, code, lists
;;;; with their items at three levels, notes and the dropped events, on
;;;; events made here and on real lines of the spec.

(in-package #:cl-ansi-spec/tests)

(define-test blocks
  :parent model
  :description "Blocks: paragraphs, code, lists, notes, and what is dropped.")

(defun built (events)
  "The S-expressions of the nodes built from EVENTS, and the problem kinds."
  (multiple-value-bind (nodes report) (model:build-events events)
    (values (mapcar (lambda (node) (if (stringp node) node (model:node-sexp node))) nodes)
            ;; Text made here has no font: the one :diagnostic that says so is no matter.
            (remove :diagnostic (mapcar #'model:problem-kind
                                        (model:build-report-problems report))))))

(defun strip-spans (form)
  "FORM without its :span properties."
  (cond ((atom form) form)
        ((eq (first form) :span) (strip-spans (cddr form)))
        (t (cons (strip-spans (first form)) (strip-spans (rest form))))))

(defun plain-paragraph (&rest words)
  "The events of a paragraph of WORDS."
  `((:begin :paragraph) ,@(mapcar (lambda (word) `(:text ,word)) words) (:end :paragraph)))

(define-test blocks-paragraphs
  :parent blocks
  (multiple-value-bind (forms problems)
      (built `(,@(plain-paragraph "one")
               (:glue :glue "0.0pt" :command "parskip")
               (:begin :paragraph) (:indent) (:end :paragraph)
               (:begin :paragraph) (:indent) (:space) (:end :paragraph)
               (:kern :width "1.0pt") (:penalty :value 10) (:rule :kind :hrule)
               (:begin :insert :number 100) ,@(plain-paragraph "footnote") (:end :insert)
               ,@(plain-paragraph "two")))
    (is equal '((:paragraph :content ("one")) (:paragraph :content ("two")))
        (strip-spans forms) "empty paragraphs, spacing and inserts leave no node")
    (is equal '() problems)))

(define-test blocks-dropped-reasons
  :parent blocks
  (dolist (row (append model::*dropped-events* model::*discarded-containers*))
    (true (stringp (second row)) "~S has a reason" (first row)))
  (let ((owner (find "3.10" (model:owners) :key #'model:owner-step :test #'string=)))
    (dolist (type (model:owner-events owner))
      (true (or (assoc type model::*dropped-events*)
                (assoc type model::*discarded-containers*)
                (member type '(:paragraph :box)))
            "~S is dropped for a reason or built" type))))

(define-test blocks-notes
  :parent blocks
  (multiple-value-bind (forms problems)
      (built '((:mark :editor-note :arguments ("KMP: fix this.") :hidden t)
               (:begin :paragraph) (:text "a")
               (:mark :reviewer-note :arguments (" Is it? ") :hidden t)
               (:end :paragraph)))
    (is equal '((:editor-note :content ("KMP: fix this.") :hidden t)
                (:paragraph :content ("a" (:reviewer-note :content ("Is it?") :hidden t))))
        (strip-spans forms) "a note between blocks and one inside a paragraph")
    (is equal '() problems))
  (is equal '(:node)
      (nth-value 1 (built '((:mark :editor-note :arguments ("x") :hidden nil))))
      "a visible note is reported: its typeset copy is also in the text"))

(define-test blocks-code
  :parent blocks
  (multiple-value-bind (forms problems)
      (built '((:begin :code)
               (:begin :paragraph) (:indent) (:space) (:text "(f") (:space) (:text "x)") (:end :paragraph)
               (:begin :paragraph) (:indent) (:end :paragraph)
               (:begin :paragraph) (:indent) (:text "y") (:end :paragraph)
               (:end :code)))
    (is equal '((:code-block :lines ((:code-line :content (" (f x)")) (:code-line) (:code-line :content ("y")))))
        (strip-spans forms) "lines in order, a blank line kept")
    (is equal '() problems)))

;;; Lists: the item's mark comes while the previous item's paragraph is open.

(defun list-events (&rest items)
  "The events of a list of ITEMS, (LEVEL LABEL TEXT) each, as TeX emits
them: a mark, then the end of the previous paragraph, then the paragraph
that holds the label box and the text."
  (let ((events '()))
    (flet ((emit (&rest more) (dolist (event more) (push event events))))
      (emit '(:begin :list))
      (loop for (level label text) in items
            for first = t then nil
            do (unless first (emit '(:end :paragraph)))
               (emit `(:mark ,(ecase level (1 :item) (2 :item-2) (3 :item-3)) :arguments (,label))
                     '(:glue :glue "5.0pt" :command "vskip") '(:begin :paragraph)
                     '(:begin :box :kind :hbox) `(:text ,label) '(:end :box)
                     `(:text ,text)))
      (emit '(:end :list) '(:end :paragraph)))
    (nreverse events)))

(define-test blocks-lists
  :parent blocks
  (multiple-value-bind (forms problems) (built (list-events '(1 "a." "one") '(1 "b." "two")))
    (is equal '((:item-list
                 :items ((:item :label ("a.") :content ((:paragraph :content ("one"))))
                         (:item :label ("b.") :content ((:paragraph :content ("two")))))))
        (strip-spans forms) "the list ends after the paragraph its end came in")
    (is equal '() problems))
  (multiple-value-bind (forms problems)
      (built (list-events '(1 "1" "a") '(2 "x" "b") '(3 "y" "c") '(2 "z" "d") '(1 "2" "e")))
    (is equal '((:item-list
                 :items ((:item :label ("1")
                          :content ((:paragraph :content ("a"))
                                    (:item-list
                                     :items ((:item :label ("x")
                                              :content ((:paragraph :content ("b"))
                                                        (:item-list
                                                         :items ((:item :label ("y")
                                                                  :content ((:paragraph :content ("c"))))))))
                                             (:item :label ("z") :content ((:paragraph :content ("d"))))))))
                         (:item :label ("2") :content ((:paragraph :content ("e")))))))
        (strip-spans forms) "items of a lower level nest, a higher one closes them")
    (is equal '() problems))
  (is equal '((:item-list :items ((:item :label ("x") :content ((:paragraph :content ("b")))))))
      (strip-spans (built (list-events '(2 "x" "b"))))
      "an \\itemitem straight in a list is an item of it (concept-args.tex:15)")
  (is equal '((:item-list :items ((:item :label ("y") :content ((:paragraph :content ("c")))))))
      (strip-spans (built (list-events '(3 "y" "c"))))
      "an \\itemitemitem straight in a list is an item of it")
  (true (member :node
                (nth-value 1 (built '((:mark :item :arguments ("x")) (:begin :paragraph) (:text "a")
                                      (:end :paragraph)))))
        "an item outside a list is reported"))

(define-test blocks-list-after-open-paragraph
  :parent blocks
  ;; \beginlist right after text, no blank line (concept-args.tex:14): the paragraph ends after.
  (multiple-value-bind (forms problems)
      (built `((:begin :paragraph) (:text "text:") (:begin :list) (:end :paragraph)
               ,@(rest (list-events '(1 "a." "one")))))
    (is equal '((:paragraph :content ("text:"))
                (:item-list :items ((:item :label ("a.") :content ((:paragraph :content ("one")))))))
        (strip-spans forms))
    (is equal '() problems)))

;;; Real lines

(defun fixture-sexps (job file first last)
  "The S-expressions of the nodes JOB builds from FILE's lines FIRST to LAST."
  (mapcar (lambda (node) (if (stringp node) node (strip-spans (model:node-sexp node))))
          (model:build-fixture job :file file :lines (list first last))))

(define-test blocks-spec-lists
  :parent blocks
  ;; concept-eval.tex:54: a list of two items, whose labels are the bullet of math (3.15m).
  (let* ((forms (fixture-sexps "chap-3" "concept-eval.tex" 54 58))
         (list (find :item-list forms :key #'first)))
    (true list)
    (is = 2 (length (getf (rest list) :items)))
    (is eq :paragraph (first (first (getf (rest (first (getf (rest list) :items))) :content)))))
  ;; concept-args.tex:15: \itemitem directly in \beginlist, after a paragraph with no blank line.
  (let ((forms (fixture-sexps "chap-3" "concept-args.tex" 11 20)))
    (is equal '(:paragraph :item-list) (mapcar #'first forms))
    (is = 3 (length (getf (rest (second forms)) :items)))))

(define-test blocks-spec-code
  :parent blocks
  ;; concept-eval.tex:389: seven lines, indentation kept.
  (let* ((forms (fixture-sexps "chap-3" "concept-eval.tex" 389 397))
         (code (find :code-block forms :key #'first))
         (lines (getf (rest code) :lines)))
    (true code)
    (is = 7 (length lines))
    (true (every (lambda (line) (eq :code-line (first line))) lines))
    (is string= " (let ((x 1))" (subseq (first (getf (rest (first lines)) :content)) 0 13))))

(define-test blocks-spec-notes
  :parent blocks
  ;; concept-bvl.tex:772: an \editornote, hidden by setup-options.tex.
  (let ((notes (loop for form in (fixture-sexps "chap-3" "concept-bvl.tex" 760 782)
                     when (eq (first form) :paragraph)
                       append (remove-if-not (lambda (item) (and (consp item) (eq (first item) :editor-note)))
                                             (getf (rest form) :content)))))
    (is = 1 (length notes))
    (true (getf (rest (first notes)) :hidden))
    (true (search "KMP: Apparently" (first (getf (rest (first notes)) :content))))))
