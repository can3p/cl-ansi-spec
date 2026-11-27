;;;; tests/semantic/vocabulary.lisp
;;;;
;;;; The spec's vocabulary (src/semantic/vocabulary.sexp): it loads, it
;;;; classifies every macro the sources define and use in text, and its
;;;; entries give the expected events on real source lines, read after
;;;; the setup files as a chapter reads them.

(in-package #:cl-ansi-spec/tests)

(define-test spec-vocabulary
  :parent semantic
  :description "The vocabulary of the spec and its events on real lines.")

(defvar *spec-survey* nil
  "The survey of all chapter jobs and plain TeX's, made once per test run.")

(defun spec-survey ()
  "The survey of all chapter jobs, and plain TeX's (two values)."
  (values-list
   (or *spec-survey*
       (setf *spec-survey*
             (list (cl-ansi-spec/inventory:merge-surveys
                    (mapcar #'cl-ansi-spec/inventory:survey-job
                            (cl-ansi-spec/inventory:chapter-jobs)))
                   (cl-ansi-spec/inventory:survey-job "plain"))))))

(defun text-used-macros (survey)
  "The names SURVEY's jobs use in text at least once on a certain line."
  (let ((names (make-hash-table :test #'equal)))
    (dolist (occurrence (cl-ansi-spec/inventory:survey-occurrences survey))
      (when (and (eq (cl-ansi-spec/inventory:occurrence-context occurrence) :text)
                 (not (cl-ansi-spec/inventory:occurrence-uncertain-p occurrence)))
        (setf (gethash (cl-ansi-spec/inventory:occurrence-name occurrence) names) t)))
    (sort (loop for name being the hash-keys of names collect name) #'string<)))

(defun defining-file (survey name)
  "The file of the first definition of NAME in SURVEY, or NIL."
  (let ((definition (find name (cl-ansi-spec/inventory:survey-definitions survey)
                          :key #'cl-ansi-spec/inventory:definition-name
                          :test #'string=)))
    (and definition (cl-ansi-spec/inventory:definition-file definition))))

(define-test vocabulary-classifies-every-macro
  :parent spec-vocabulary
  (let ((vocabulary (semantic:spec-vocabulary)))
    (multiple-value-bind (survey plain) (spec-survey)
      ;; Each entry names a macro the sources or plain TeX define.
      (dolist (entry (semantic:vocabulary-entries vocabulary))
        (let ((name (concatenate 'string "\\" (semantic:entry-name entry))))
          (true (member (cl-ansi-spec/inventory:name-class survey name plain)
                        '(:defined :nested :plain))
                "~A is defined" name)))
      ;; Each macro the sources define and use in text is classified,
      ;; unambiguously.
      (let ((unclassified '()) (ambiguous '()))
        (dolist (name (text-used-macros survey))
          (when (member (cl-ansi-spec/inventory:name-class survey name plain)
                        '(:defined :nested))
            (multiple-value-bind (kind twice)
                (semantic:classify-macro vocabulary name (defining-file survey name))
              (unless kind (push name unclassified))
              (when twice (push name ambiguous)))))
        (is equal '() unclassified)
        (is equal '() ambiguous)))))

;;; Real lines

(defun spec-lines (file first last)
  "Lines FIRST to LAST of the spec file FILE, as one string."
  (format nil "~{~A~%~}"
          (subseq (uiop:read-file-lines (spec-file file)) (1- first) last)))

(defun spec-vocabulary-job (text)
  "A job from plain TeX's format reading the setup files, then TEXT, then
\\end, observing the spec's vocabulary.  Returns the expander and the
observer."
  (let* ((expander (expand:start-job
                    (expand:make-job (plain-format)
                                     :resolver (fallback-resolver
                                                (list (cons "main"
                                                            (format nil "\\input setup~%~A\\end~%"
                                                                    text)))))
                    "main"))
         (observer (semantic:observe-vocabulary expander (semantic:spec-vocabulary))))
    (values expander observer)))

(defun vocabulary-events (expander observer)
  "The events of EXPANDER's job keyed by an entry of OBSERVER's
vocabulary, as SEMANTIC-EVENTS shows them."
  (let ((keys (mapcar #'semantic:entry-key
                      (semantic:vocabulary-entries (semantic:observer-vocabulary observer)))))
    (loop for event in (expand:job-events expander)
          when (and (member (first event) '(:begin :end :mark))
                    (member (second event) keys))
            collect (strip-semantic-event expander event nil))))

(defmacro check-vocabulary (text events &key (reports '((:redefined "item") (:redefined "itemitem"))))
  "Run TEXT after the setup files; check its vocabulary EVENTS and the
kinds and names of its REPORTS (plain's \\item and \\itemitem are always
redefined)."
  `(multiple-value-bind (expander observer) (spec-vocabulary-job ,text)
     (run-job expander)
     (is equal ',events (vocabulary-events expander observer))
     (is equal ',reports (mapcar (lambda (report)
                                   (list (semantic:report-kind report)
                                         (semantic:report-name report)))
                                 (semantic:observer-reports observer)))))

(define-test dictionary-entry-events
  :parent spec-vocabulary
  ;; ENDP, dict-conses.tex:1701-1731: the entry, its labels (one empty,
  ;; with its confidence mark), an issue and code.
  (check-vocabulary (concatenate 'string (spec-lines "dict-conses" 1701 1731) "\\endcom")
                    ((:begin :com :arguments ("endp" "Function"))
                     (:mark :label :arguments ("Syntax" ":"))
                     (:mark :label :arguments ("Arguments and Values" ":"))
                     (:begin :issue :arguments ("DOTTED-LIST-ARGUMENTS:CLARIFY"))
                     (:end :issue :arguments ("DOTTED-LIST-ARGUMENTS:CLARIFY"))
                     (:mark :label :arguments ("Description" ":"))
                     (:mark :label :arguments ("Examples" ":"))
                     (:begin :code :arguments ())
                     (:end :code :arguments ())
                     (:mark :label :arguments ("Side Effects" "\\None "))
                     (:mark :label-confidence :arguments ("."))
                     (:end :com :arguments ()))))

(define-test structure-events
  :parent spec-vocabulary
  ;; chap-1.tex:17-18, a section naming itself; concept-args.tex:15-19,
  ;; a list; concept-organization.tex:31, a section reference.
  (check-vocabulary (concatenate 'string (spec-lines "chap-1" 17 18)
                                 (spec-lines "concept-args" 15 19)
                                 (spec-lines "concept-organization" 31 31))
                    ((:mark :section :arguments ("Definitions"))
                     (:mark :define-section :arguments ("Definitions"))
                     (:begin :list :arguments ())
                     (:mark :item-2 :arguments ("\\bull "))
                     (:mark :item-2 :arguments ("\\bull "))
                     (:mark :item-2 :arguments ("\\bull "))
                     (:end :list :arguments ())
                     (:begin :secref :arguments ("\\LanguageSubsets "))
                     (:end :secref))))

(define-test hidden-note-events
  :parent spec-vocabulary
  ;; concept-bvl.tex:772-778: the options hide editor notes.
  (multiple-value-bind (expander observer)
      (spec-vocabulary-job (spec-lines "concept-bvl" 772 778))
    (run-job expander)
    (let ((events (vocabulary-events expander observer)))
      (is = 1 (length events))
      (is eq :editor-note (second (first events)))
      (is eq t (getf (cddr (first events)) :hidden))
      (true (search "KMP: Apparently" (first (getf (cddr (first events)) :arguments)))))))
