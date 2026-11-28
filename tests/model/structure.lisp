;;;; tests/model/structure.lisp
;;;;
;;;; Tests of structure (src/model/build-structure.lisp): chapters and
;;;; sections nested by level, their numbers counted and checked, their ids,
;;;; the standard; on events made here and on real jobs of the spec.
;;;; Owner: step 3.8 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/tests)

(define-test model-structure
  :parent model
  :description "Chapters and sections: nesting, numbers, ids and the standard.")

(defparameter *structure-handlers*
  (let ((table (model:make-handler-table)))
    (model:install-text-handlers table)
    (model:install-structure-handlers table)
    table)
  "The handlers of text and structure.")

(defun structure-sexps (&rest events)
  "The top-level nodes of EVENTS as S-expressions without spans, and the
build report."
  (multiple-value-bind (nodes report)
      (model:build-events events :registry model:*registry* :handlers *structure-handlers*)
    (values (mapcar #'structure-strip-spans (mapcar #'model:node-sexp nodes)) report)))

(defun structure-strip-spans (sexp)
  "SEXP, a node as an S-expression, without the :SPAN of it and of the
nodes inside."
  (cond ((atom sexp) sexp)
        ((keywordp (first sexp))
         (cons (first sexp)
               (loop for (key value) on (rest sexp) by #'cddr
                     unless (eq key :span)
                       append (list key (if (listp value) (mapcar #'structure-strip-spans value) value)))))
        (t (mapcar #'structure-strip-spans sexp))))

(defun mark (key &rest arguments)
  "A mark event of KEY with ARGUMENTS (strings)."
  (test-event :mark key :arguments arguments))

(defun heading (number title &optional (style "cmbx10"))
  "The events of a heading paragraph TeX makes for a section: the hang of
the number, the box of the number, the title."
  (list (test-event :begin :paragraph) (test-event :indent nil)
        (test-event :begin :math) (test-event :end :math)
        (test-event :begin :box)
        (test-event :text number :style style) (test-event :space nil)
        (test-event :end :box)
        (test-event :space nil) (test-event :text title :style style)
        (test-event :end :paragraph)))

(defun section-events (key title number &rest more)
  "The events of a section: its mark, the :write of the table of
contents, the heading, then MORE."
  (append (list (mark key title) (test-event :write nil :stream 0 :tokens "!2toc"))
          (heading number title)
          more))

(defun problem-messages (report)
  "The messages of REPORT's problems of kind :NODE, in order."
  (loop for problem in (model:build-report-problems report)
        when (eq (model:problem-kind problem) :node)
          collect (model:problem-message problem)))

(defun chapter-events (number title id &rest more)
  "The events of a chapter: its mark, its definition and the lines TeX
writes for it, the two heading paragraphs, then MORE."
  (append (list (mark :chapter number title id title)
                (mark :define-chapter id title number title)
                (test-event :write nil :stream 5 :tokens (format nil "!~A Chapter ~A ~A" id number title))
                (test-event :write nil :stream 5 :tokens (format nil "!~A Chapter ~A ~A" title number title))
                (test-event :begin :paragraph) (test-event :text "Programming" :style "cmbx10")
                (test-event :end :paragraph)
                (test-event :write nil :stream 0 :tokens "!1toc")
                (test-event :begin :paragraph) (test-event :text number :style "cmbx10")
                (test-event :text "." :style "cmbx10") (test-event :text title :style "cmbx10")
                (test-event :end :paragraph))
          more))

;;; Nesting, numbers and ids

(define-test structure-nesting
  :parent model-structure
  (multiple-value-bind (nodes report)
      (apply #'structure-sexps
             (append (chapter-events "3" "Evaluation" "ChapThree")
                     (section-events :section "One" "3.1")
                     (section-events :subsection "One-One" "3.1.1")
                     (section-events :subsubsection "Deep" "3.1.1.1")
                     (section-events :subsection "One-Two" "3.1.2")
                     (section-events :section "Two" "3.2")))
    (is equal '((:chapter :id "ChapThree" :aliases ("Evaluation") :number "3" :title ("Evaluation")
                 :children
                 ((:section :id "ChapThree/1" :number "3.1" :level 1 :title ("One")
                   :children
                   ((:section :id "ChapThree/1/1" :number "3.1.1" :level 2 :title ("One-One")
                     :children ((:section :id "ChapThree/1/1/1" :number "3.1.1.1" :level 3
                                 :title ("Deep"))))
                    (:section :id "ChapThree/1/2" :number "3.1.2" :level 2 :title ("One-Two"))))
                  (:section :id "ChapThree/2" :number "3.2" :level 1 :title ("Two")))))
        nodes)
    ;; The end of the input closes the chapter and its last section quietly.
    (is equal '() (problem-kinds report))
    (is equal '() (problem-messages report))))

(define-test structure-skipped-level
  :parent model-structure
  ;; A subsubsection straight under a section: TeX's counter of the level
  ;; between stays zero.
  (multiple-value-bind (nodes report)
      (apply #'structure-sexps
             (append (chapter-events "4" "Types" "ChapFour")
                     (section-events :section "A" "4.1")
                     (section-events :subsubsection "B" "4.1.0.1")))
    (is equal "4.1.0.1" (getf (rest (first (getf (rest (first (getf (rest (first nodes)) :children)))
                                                  :children)))
                              :number))
    (is equal '() (problem-messages report))))

(define-test structure-number-mismatch
  :parent model-structure
  ;; TeX typeset 4.3 where the builder counted 4.2: the build is told.
  (multiple-value-bind (nodes report)
      (apply #'structure-sexps
             (append (chapter-events "4" "Types" "ChapFour")
                     (section-events :section "A" "4.1")
                     (section-events :section "B" "4.3")))
    (declare (ignore nodes))
    (is equal '("Section counted 4.2, but TeX typeset 4.3.") (problem-messages report))))

(define-test structure-define-section
  :parent model-structure
  (multiple-value-bind (nodes report)
      (apply #'structure-sexps
             (append (chapter-events "1" "Introduction" "ChapOne")
                     (section-events :section "Definitions" "1.1"
                                     (mark :define-section "Definitions")
                                     (test-event :write nil :stream 5
                                                 :tokens "!Definitions Section 1.1\\ Definitions"))
                     (section-events :section "Conformance" "1.2"
                                     (mark :define-section "Conformance")
                                     ;; TeX wrote another number than the one counted.
                                     (test-event :write nil :stream 5
                                                 :tokens "!Conformance Section 1.3\\ Conformance"))))
    (is equal '("Definitions" "Conformance")
        (mapcar (lambda (section) (getf (rest section) :id))
                (getf (rest (first nodes)) :children)))
    (is equal '("Section Conformance counted 1.2, but TeX wrote 1.3.") (problem-messages report))))

(define-test structure-aliases
  :parent model-structure
  ;; A chapter keeps the short name of its \\DefineChapter; a section named
  ;; twice keeps the label that is not its id, once.
  (multiple-value-bind (nodes report)
      (apply #'structure-sexps
             (append (chapter-events "2" "Syntax" "ChapTwo")
                     (section-events :section "Character Syntax" "2.1"
                                     (mark :define-section "CharacterSyntax")
                                     (test-event :write nil :stream 5
                                                 :tokens "!CharacterSyntax Section 2.1\\ Character Syntax")
                                     (mark :define-section "TheStandardSyntax")
                                     (test-event :write nil :stream 5
                                                 :tokens "!TheStandardSyntax Section 2.1\\ Character Syntax")
                                     (mark :define-section "TheStandardSyntax")
                                     (test-event :write nil :stream 5
                                                 :tokens "!TheStandardSyntax Section 2.1\\ Character Syntax"))))
    (is equal '() (problem-messages report))
    (let ((chapter (first nodes)) (section (first (getf (rest (first nodes)) :children))))
      (is equal '("Syntax") (getf (rest chapter) :aliases))
      (is equal "TheStandardSyntax" (getf (rest section) :id))
      (is equal '("CharacterSyntax") (getf (rest section) :aliases))))
  ;; A, B, A: the id is not its own alias; a label shaped like a generated
  ;; id is kept.
  (let* ((nodes (apply #'structure-sexps
                       (append (chapter-events "2" "Syntax" "ChapTwo")
                               (section-events :section "S" "2.1"
                                               (mark :define-section "section-2.1")
                                               (mark :define-section "B")
                                               (mark :define-section "section-2.1")))))
         (section (first (getf (rest (first nodes)) :children))))
    (is equal "section-2.1" (getf (rest section) :id))
    (is equal '("B") (getf (rest section) :aliases))))

(define-test structure-write-lines
  :parent model-structure
  (is equal '("Definitions" "1.4")
      (multiple-value-list (model:parse-reference-write "!Definitions Section 1.4\\ Definitions"
                                                         "Section")))
  (is equal '("ChapOne" "1")
      (multiple-value-list (model:parse-reference-write "!ChapOne Chapter 1 Introduction" "Chapter")))
  (false (model:parse-reference-write "!0Programming Language !!\\pagenumber " "Section"))
  (false (model:parse-reference-write "" "Section")))

(define-test structure-dictionary-and-simple-chapter
  :parent model-structure
  (multiple-value-bind (nodes report)
      (apply #'structure-sexps
             (append (chapter-events "15" "Arrays" "ChapFifteen")
                     (list (mark :dictionary "dict-arrays")
                           (test-event :write nil :stream 0 :tokens "!215.1 Arrays Dictionary"))))
    (is equal '((:chapter :id "ChapFifteen" :aliases ("Arrays") :number "15" :title ("Arrays")
                 :children ((:section :id "ChapFifteen/1" :number "15.1" :level 1
                             :dictionary t :title ("Arrays Dictionary")))))
        nodes)
    (is equal '() (problem-messages report)))
  (multiple-value-bind (nodes)
      (structure-sexps (mark :simple-chapter "Credits")
                       (test-event :begin :paragraph) (test-event :text "Credits" :style "cmbx10")
                       (test-event :end :paragraph))
    (is equal '((:chapter :id "Credits" :title ("Credits"))) nodes)))

(define-test structure-headings
  :parent model-structure
  ;; A heading's fonts are not read: bold text stays plain, a nested
  ;; mark's text (a \keyref) is kept by the handlers of its own.
  (multiple-value-bind (nodes)
      (apply #'structure-sexps
             (append (chapter-events "1" "Introduction" "ChapOne")
                     (section-events :section "Specifiers for aux" "1.1")))
    (is equal '("Specifiers for aux")
        (getf (rest (first (getf (rest (first nodes)) :children))) :title)))
  ;; No heading after the mark: reported, the section kept.
  (multiple-value-bind (nodes report)
      (structure-sexps (mark :section "Lost") (test-event :text "text" :style "cmr10"))
    (declare (ignore nodes))
    (true (member "No heading follows :SECTION." (problem-messages report) :test #'string=))))

(define-test structure-other-writes
  :parent model-structure
  ;; Every other \write is dropped, and builds nothing.
  (multiple-value-bind (nodes report)
      (structure-sexps (test-event :write nil :stream 0 :tokens "!1toc"))
    (is equal '() nodes)
    (is equal '() (problem-kinds report))))

(define-test structure-unterminated-heading
  :parent model-structure
  ;; A number box with no end does not eat the rest of the job.
  (multiple-value-bind (nodes report)
      (structure-sexps (mark :section "A")
                       (test-event :begin :paragraph) (test-event :begin :box)
                       (test-event :text "1.1" :style "cmbx10")
                       (test-event :end :paragraph)
                       (test-event :begin :paragraph) (test-event :text "after" :style "cmr10")
                       (test-event :end :paragraph))
    (declare (ignore nodes))
    (true (member "A heading's number box has no end." (problem-messages report)
                  :test #'string=))))

;;; The standard

(define-test structure-standard
  :parent model-structure
  (let* ((front (model:make-node :chapter :id "Credits" :title '("Credits")))
         (one (model:make-node :chapter :id "ChapOne" :number "1" :title '("Introduction")))
         (standard (model:build-standard (list front one) :version "15.17")))
    (is equal "15.17" (model:node-field-value standard :version))
    (is equal (list front) (model:node-field-value standard :front-matter))
    (is equal (list one) (model:node-field-value standard :chapters))
    (is equal '() (model:node-problems standard))))

(define-test structure-version
  :parent model-structure
  (let ((run (model::memoised-run "chap-1")))
    (is equal "15.17" (model:job-version (model::job-run-expander run)))))

;;; Real jobs

(defun spec-chapter (job)
  "The chapter node of the chapter job JOB, built whole with the
handlers of text and structure (all the files it reads, which a fixture
of the job's own file would not hold), and the report."
  (multiple-value-bind (nodes report)
      (model:build-job job :handlers *structure-handlers*)
    (values (find :chapter nodes :key #'model:node-kind) report)))

(defun section-list (node)
  "The sections among NODE's children, in order."
  (remove-if-not (lambda (child) (and (typep child 'model:node) (eq (model:node-kind child) :section)))
                 (model:node-field-value node :children)))

(defun count-sections (node)
  "The sections below NODE, at every depth."
  (loop for section in (section-list node)
        sum (1+ (count-sections section))))

(defun number-problems (report)
  "The problems of REPORT about numbers, labels and headings."
  (remove-if-not (lambda (message)
                   (some (lambda (word) (search word message))
                         '("counted" "TeX wrote" "No heading" "No Section" "No Chapter"
                           "DefineSection" "DefineChapter")))
                 (problem-messages report)))

(define-test structure-spec-chapter-1
  :parent model-structure
  (multiple-value-bind (chapter report) (spec-chapter "chap-1")
    (is equal "ChapOne" (model:node-field-value chapter :id))
    (is equal "1" (model:node-field-value chapter :number))
    (is equal '("Introduction") (model:node-field-value chapter :title))
    (is equal '("1.1" "1.2" "1.3" "1.4" "1.5" "1.6" "1.7" "1.8" "1.9")
        (mapcar (lambda (section) (model:node-field-value section :number))
                (section-list chapter)))
    (is equal '("ChapOne/1" "ChapOne/2" "ChapOne/3" "Definitions" "Conformance"
                "LanguageExtensions" "LanguageSubsets" "DeprecatedFeatures" "CLsymbols")
        (mapcar (lambda (section) (model:node-field-value section :id))
                (section-list chapter)))
    ;; Every number counted equals the one TeX typeset and wrote.
    (is equal '() (number-problems report))))

(define-test structure-spec-chapter-15
  :parent model-structure
  ;; Subsections to the fifth level, and a dictionary section.
  (multiple-value-bind (chapter report) (spec-chapter "chap-15")
    (is equal "15" (model:node-field-value chapter :number))
    (let* ((sections (section-list chapter))
           (concepts (first sections))
           (dictionary (find t sections :key (lambda (s) (model:node-field-value s :dictionary)))))
      (is equal "15.1" (model:node-field-value concepts :number))
      (is equal "ArrayConcepts" (model:node-field-value concepts :id))
      (true dictionary)
      (is equal "15.2" (model:node-field-value dictionary :number))
      (is equal '("Arrays Dictionary") (model:node-field-value dictionary :title))
      (let ((deep (find "ArrayElements/3/2/1" (list-sections concepts)
                        :key (lambda (s) (model:node-field-value s :id)) :test #'string=)))
        (true deep)
        (is equal 5 (model:node-field-value deep :level))))
    (is equal '() (number-problems report))))

(defun list-sections (node)
  "Every section below NODE, in order."
  (loop for section in (section-list node)
        collect section
        append (list-sections section)))

(define-test structure-spec-front-matter
  :parent model-structure
  (let ((nodes (model:build-fixture "chap-0" :file "chap-0.tex" :lines '(15 20)
                                             :handlers *structure-handlers*)))
    (is equal '("Figures") (model:node-field-value (first nodes) :title))
    (is eq nil (model:node-field-value (first nodes) :number))))

(define-test structure-spec-numbers-in-all-chapters
  :parent model-structure
  ;; The numbers of every section of a sample of chapters, counted and
  ;; checked against TeX's own.
  (dolist (job (quote ("chap-2" "chap-4")))
    (multiple-value-bind (chapter report) (spec-chapter job)
      (true (plusp (count-sections chapter)) "~A has sections" job)
      (is equal '() (number-problems report) "~A: numbers agree with TeX's" job))))
