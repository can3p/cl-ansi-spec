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
                            (cl-ansi-spec:chapter-jobs)))
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

(defun vocabulary-events (expander observer &optional keys)
  "The events of EXPANDER's job keyed by an entry of OBSERVER's
vocabulary, or by one of KEYS when given, as SEMANTIC-EVENTS shows them."
  (let ((keys (or keys
                  (mapcar #'semantic:entry-key
                          (semantic:vocabulary-entries
                           (semantic:observer-vocabulary observer))))))
    (loop for event in (expand:job-events expander)
          when (and (member (first event) '(:begin :end :mark))
                    (member (second event) keys))
            collect (strip-semantic-event expander event nil))))

(defparameter *setup-redefinitions*
  '((:redefined "item") (:redefined "itemitem") (:redefined "b")
    (:redefined "i") (:redefined "j") (:redefined "hat") (:redefined "star")
    (:redefined "meaning"))
  "The reports of every job: the setup files redefine plain's \\item,
\\itemitem, \\b, \\i, \\j, \\hat and \\star, and the primitive
\\meaning, which are entries.")

(defmacro check-vocabulary (text events &key (reports '*setup-redefinitions*) keys)
  "Run TEXT after the setup files; check its vocabulary EVENTS (only
those keyed by one of KEYS, when given) and the kinds and names of its
REPORTS (a form, by default *SETUP-REDEFINITIONS*)."
  `(multiple-value-bind (expander observer) (spec-vocabulary-job ,text)
     (run-job expander)
     (is equal ',events (vocabulary-events expander observer ',keys))
     (is equal ,reports (mapcar (lambda (report)
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
                     (:end :com :arguments ()))
                    :keys (:com :label :label-confidence :issue :code)))

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
                     (:end :secref))
                    :keys (:section :define-section :list :item-2 :secref)))

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

(define-test inline-events
  :parent spec-vocabulary
  ;; concept-args.tex:11 and :160, terms, a new term and its index mark,
  ;; wrappers with no argument of their own; appendix-removed.tex:114-117,
  ;; \\packref keeps its argument as written; a keyword, a cited book, a
  ;; phrase (appendix-implem-defined.tex:68, concept-history.tex:193,
  ;; concept-args.tex:142).
  (check-vocabulary (concatenate 'string (spec-lines "concept-args" 11 11)
                                 (spec-lines "concept-args" 160 160))
                    ((:begin :term :arguments ("call"))
                     (:end :term)
                     (:begin :new-term :arguments ("safe call"))
                     (:end :new-term)
                     (:mark :index-term :arguments ("safe call"))
                     (:begin :keyref :arguments ("rest" "\\&rest") :through :clref)
                     (:end :keyref)
                     (:begin :keyref :arguments ("key" "\\&key") :through :clref)
                     (:end :keyref)))
  (check-vocabulary (spec-lines "appendix-removed" 114 116)
                    ((:begin :term :arguments ("packages"))
                     (:end :term)
                     (:begin :packref :arguments ("lisp" "\\uppercase {lisp}") :through :ttref)
                     (:end :packref)
                     (:mark :index-package :arguments ("lisp"))
                     (:begin :packref :arguments ("user" "\\uppercase {user}") :through :ttref)
                     (:end :packref)
                     (:mark :index-package :arguments ("user"))))
  (check-vocabulary (concatenate 'string (spec-lines "appendix-implem-defined" 68 68)
                                 (spec-lines "concept-history" 193 193)
                                 (spec-lines "concept-args" 142 142))
                    ((:begin :term :arguments ("sequence"))
                     (:end :term)
                     (:begin :kwd :arguments ("initial-element" ":initial-element")
                      :through :ttref)
                     (:end :kwd)
                     (:begin :cite :arguments ())
                     (:end :cite)
                     (:begin :term :arguments ("type"))
                     (:end :term)
                     (:begin :typeref :arguments ("program-error") :through :clref)
                     (:end :typeref))))

(define-test code-and-emphasis-events
  :parent spec-vocabulary
  ;; concept-bvl.tex:360-362, an arrow in code; concept-bvl.tex:1117,
  ;; emphasis nested in inline code; concept-definitions.tex:1069,
  ;; lambda-list keywords and parameters.
  (check-vocabulary (concatenate 'string (spec-lines "concept-bvl" 360 362) "\\endcode
" (spec-lines "concept-bvl" 1117 1117) (spec-lines "concept-definitions" 1069 1069))
                    ((:begin :code :arguments ())
                     (:begin :evaluates-to :arguments ())
                     (:end :evaluates-to)
                     (:end :code :arguments ())
                     (:begin :inline-code :arguments
                      ("((\\i {key} \\i {var}) \\brac {\\i {default} \\brac {\\i {svar}}})"))
                     (:begin :emphasis :arguments ("key"))
                     (:end :emphasis)
                     (:begin :emphasis :arguments ("var"))
                     (:end :emphasis)
                     (:begin :optional :arguments ("\\i {default} \\brac {\\i {svar}}"))
                     (:begin :emphasis :arguments ("default"))
                     (:end :emphasis)
                     (:begin :optional :arguments ("\\i {svar}"))
                     (:begin :emphasis :arguments ("svar"))
                     (:end :emphasis)
                     (:end :optional)
                     (:end :optional)
                     (:end :inline-code)
                     (:begin :lambda-list-keyword :arguments ())
                     (:end :lambda-list-keyword)
                     (:begin :param :arguments ("z"))
                     (:end :param)
                     (:begin :lambda-list-keyword :arguments ())
                     (:end :lambda-list-keyword)
                     (:begin :param :arguments ("k"))
                     (:end :param))))

(define-test paragraph-starting-with-a-term
  :parent spec-vocabulary
  ;; concept-classes.tex:70: an inline entry used in vertical mode begins
  ;; inside the paragraph it starts, before its first character.
  (multiple-value-bind (expander observer)
      (spec-vocabulary-job (spec-lines "concept-classes" 70 70))
    (declare (ignore observer))
    (run-job expander)
    (let ((events (semantic-events expander :text-only t)))
      (is equal '((:begin :paragraph)
                  (:begin :new-term :arguments ("local precedence order"))
                  (:text "local"))
          (subseq (member '(:begin :paragraph) events :test #'equal) 0 3)))))

(define-test syntax-events
  :parent spec-vocabulary
  ;; dict-conses.tex:1123, a signature with a BNF operator in a formula;
  ;; dict-conditions.tex:370-374, its values on a second line;
  ;; dict-arrays.tex:2521-2526, several names (\\entry, defined anew by
  ;; each macro, is not reported).
  (check-vocabulary (spec-lines "dict-conses" 1123 1123)
                    ((:begin :defun :arguments ("list*" "{\\rest } \\plus {objects}" "result"))
                     (:begin :one-or-more :arguments ("objects"))
                     (:end :one-or-more)
                     (:end :defun))
                    :keys (:defun :one-or-more))
  (check-vocabulary (spec-lines "dict-conditions" 370 374)
                    ((:begin :defmac :arguments
                      ("assert"
                       "test-form \\brac {\\paren {\\starparam {place}} \\brac {datum-form \\starparam {argument-form}}}"
                       "\\nil "))
                     (:begin :evaluates-to :arguments ())
                     (:end :evaluates-to)
                     (:end :defmac))
                    :keys (:defmac :evaluates-to))
  (check-vocabulary (spec-lines "dict-arrays" 2521 2526)
                    ((:begin :defun-multi :arguments
                      ("bit-array {\\rest } subscripts" "bit" "\\entry {bit} \\entry {sbit}"))
                     (:mark :entry :arguments ("bit"))
                     (:mark :entry :arguments ("sbit"))
                     (:end :defun-multi)
                     (:begin :defsetf-multi :arguments
                      ("bit-array {\\rest } subscripts" "new-bit" "\\entry {bit} \\entry {sbit}"))
                     (:mark :entry :arguments ("bit"))
                     (:mark :entry :arguments ("sbit"))
                     (:end :defsetf-multi))
                    :keys (:defun-multi :defsetf-multi :entry)))

(define-test bnf-events
  :parent spec-vocabulary
  ;; concept-bvl.tex:545-550: a rule split over lines by \\CR, literal
  ;; parentheses opened and closed in different cells; the \\xparen
  ;; spacers leave no event.
  (check-vocabulary (spec-lines "concept-bvl" 545 550)
                    ((:begin :bnf-rule :arguments
                      ("lambda-list"
                       "\\lparen \\star {\\SpecializedVar }\\CR \\xparen \\ttbrac {{\\opt } \\star {\\VarValueSuppliedP }}\\CR \\xparen \\ttbrac {{\\rest } \\param {var}}\\CR \\xparen \\ttbrac {{\\key } \\star {\\KeyVarValueSuppliedP } \\brac {\\allowotherkeys }}\\CR \\xparen \\ttbrac {{\\aux } \\star {\\VarValue }}\\rparen \\CR "))
                     (:begin :parenthesized :arguments ())
                     (:begin :parenthesized :arguments ("{\\TVar } \\brac {\\param {specializer}}"))
                     (:end :parenthesized)
                     (:mark :bnf-break :arguments ())
                     (:begin :bracketed :arguments ("{\\opt } \\star {\\VarValueSuppliedP }"))
                     (:begin :parenthesized :arguments
                      ("{\\TVar } \\brac {init-form \\brac {supplied-p-parameter}}"))
                     (:end :parenthesized)
                     (:end :bracketed)
                     (:mark :bnf-break :arguments ())
                     (:begin :bracketed :arguments ("{\\rest } \\param {var}"))
                     (:end :bracketed)
                     (:mark :bnf-break :arguments ())
                     (:begin :bracketed :arguments
                      ("{\\key } \\star {\\KeyVarValueSuppliedP } \\brac {\\allowotherkeys }"))
                     (:begin :parenthesized :arguments
                      ("\\curly {\\param {var} | \\paren {\\param {keyword-name} {\\TVar }}} \\brac {init-form \\brac {supplied-p-parameter}}"))
                     (:begin :parenthesized :arguments ("\\param {keyword-name} {\\TVar }"))
                     (:end :parenthesized)
                     (:end :parenthesized)
                     (:end :bracketed)
                     (:mark :bnf-break :arguments ())
                     (:begin :bracketed :arguments ("{\\aux } \\star {\\VarValue }"))
                     (:begin :parenthesized :arguments ("{\\TVar } \\brac {\\param {init-form}}"))
                     (:end :parenthesized)
                     (:end :bracketed)
                     (:end :parenthesized :arguments ())
                     (:mark :bnf-break :arguments ())
                     (:end :bnf-rule))
                    :keys (:bnf-rule :bnf-break :bracketed :parenthesized))
  ;; dict-arrays.tex:47-49: a type specifier (a mark: its alignment is
  ;; followed by a paragraph) and a rule; the first cell's macros are
  ;; expanded before the cell opens, their begins go into it.
  (check-vocabulary (spec-lines "dict-arrays" 47 49)
                    ((:mark :deftype :arguments
                      ("array" "\\ttbrac {\\curly {element-type | \\misc {*}} \\brac {dimension-spec}}"))
                     (:begin :bracketed :arguments
                      ("\\curly {element-type | \\misc {*}} \\brac {dimension-spec}"))
                     (:begin :group :arguments ("element-type | \\misc {*}"))
                     (:end :group)
                     (:begin :optional :arguments ("dimension-spec"))
                     (:end :optional)
                     (:end :bracketed)
                     (:begin :bnf-rule :arguments
                      ("dimension-spec" "rank | \\misc {*} | \\paren {\\star {\\curly {dimension | \\misc {*}}}}"))
                     (:begin :parenthesized :arguments ("\\star {\\curly {dimension | \\misc {*}}}"))
                     (:begin :zero-or-more :arguments ("\\curly {dimension | \\misc {*}}"))
                     (:begin :group :arguments ("dimension | \\misc {*}"))
                     (:end :group)
                     (:end :zero-or-more)
                     (:end :parenthesized)
                     (:end :bnf-rule))
                    :keys (:deftype :bnf-rule :bracketed :group :optional :parenthesized
                           :zero-or-more))
  ;; dict-iteration.tex:658-663: indirections; an interleaving split over
  ;; lines, then repeated (its \\extrainterleave spacers leave no event).
  (check-vocabulary (spec-lines "dict-iteration" 658 663)
                    ((:begin :bnf-rule :arguments
                      ("for-as-arithmetic-subclause"
                       "\\down {arithmetic-up} | \\down {arithmetic-downto} | \\down {arithmetic-downfrom}"))
                     (:begin :indirection :arguments ("arithmetic-up"))
                     (:end :indirection)
                     (:begin :indirection :arguments ("arithmetic-downto"))
                     (:end :indirection)
                     (:begin :indirection :arguments ("arithmetic-downfrom"))
                     (:end :indirection)
                     (:end :bnf-rule)
                     (:begin :bnf-rule :arguments
                      ("arithmetic-up"
                       "\\begininterleave \\curly {\\loopref {from} | \\loopref {upfrom}} \\param {form1} | \\extrainterleave \\curly {\\loopref {to} | \\loopref {upto} | \\loopref {below}} \\param {form2} | \\extrainterleave \\loopref {by} \\param {form3}\\endinterleave \\prevplus "))
                     (:begin :interleave :arguments ())
                     (:end :interleave :arguments ())
                     (:mark :repeat-previous :arguments ())
                     (:end :bnf-rule))
                    :keys (:bnf-rule :indirection :interleave :repeat-previous)))

(define-test formula-first-bodies
  :parent spec-vocabulary
  ;; concept-definitions.tex:354-360 and :378: bodies that open with a
  ;; formula (\\IN, \\OUT, \\ang) begin before it, in the list that
  ;; holds it, so they end in the same list: no :unbalanced report.
  (check-vocabulary (concatenate 'string (spec-lines "concept-definitions" 354 360)
                                 (spec-lines "concept-definitions" 378 378))
                    ((:begin :input :arguments ("this notation"))
                     (:end :input)
                     (:begin :code :arguments ())
                     (:begin :output :arguments ())
                     (:end :output)
                     (:begin :input :arguments ("9 16 "))
                     (:end :input)
                     (:begin :angle :arguments ("Newline"))
                     (:end :angle))))

(define-test glossary-events
  :parent spec-vocabulary
  ;; concept-glossary.tex:49-67 defines the glossary's macros; :155-163,
  ;; the first entries: letters, entries, a pronunciation, parts of
  ;; speech (wrappers of \\i).  concept-bvl.tex:113, a sense.
  (check-vocabulary (concatenate 'string (spec-lines "concept-glossary" 49 67)
                                 (spec-lines "concept-glossary" 155 163))
                    ((:mark :glossary-letter :arguments ("Non-alphabetic"))
                     (:mark :glossary-entry :arguments ("()"))
                     (:mark :index-term :arguments ("()"))
                     (:begin :pronunciation :arguments ("\\Stress {nil}"))
                     (:end :pronunciation)
                     (:begin :part-of-speech :arguments ("n.") :through :emphasis)
                     (:end :part-of-speech)
                     (:mark :glossary-letter :arguments ("A"))
                     (:mark :glossary-entry :arguments ("absolute"))
                     (:mark :index-term :arguments ("absolute"))
                     (:begin :part-of-speech :arguments ("adj.") :through :emphasis)
                     (:end :part-of-speech))
                    :keys (:glossary-letter :glossary-entry :index-term :pronunciation
                           :part-of-speech))
  ;; :106-107, an example; :217, a usage after a part of speech.
  (check-vocabulary (concatenate 'string (spec-lines "concept-glossary" 49 67)
                                 (spec-lines "concept-glossary" 106 107)
                                 (spec-lines "concept-glossary" 217 217))
                    ((:begin :glossary-example :arguments ("This is an example of an example."))
                     (:end :glossary-example)
                     (:mark :glossary-entry :arguments ("actual argument"))
                     (:begin :part-of-speech :arguments ("n.") :through :emphasis)
                     (:end :part-of-speech)
                     (:begin :usage :arguments ("Trad.") :through :emphasis)
                     (:end :usage))
                    :keys (:glossary-example :glossary-entry :part-of-speech :usage))
  ;; concept-arrays.tex:3: \\beginsubsection is a \\let copy of
  ;; \\beginSubsection, observed as it.
  (check-vocabulary (spec-lines "concept-arrays" 3 3)
                    ((:mark :subsection :arguments ("Array Elements"))))
  (check-vocabulary (spec-lines "concept-bvl" 113 113)
                    ((:begin :term :arguments ("keyword"))
                     (:end :term)
                     (:begin :sense :arguments ("1"))
                     (:end :sense))))

(define-test figure-events
  :parent spec-vocabulary
  ;; concept-conses.tex:6-9: a figure of references; its content, set
  ;; aside in box 1, and its caption come between its ends.
  (check-vocabulary (spec-lines "concept-conses" 6 9)
                    ((:begin :figure :arguments ())
                     (:begin :misc :arguments ("car") :through :clref) (:end :misc)
                     (:begin :misc :arguments ("cons") :through :clref) (:end :misc)
                     (:begin :misc :arguments ("rplacd") :through :clref) (:end :misc)
                     (:begin :misc :arguments ("cdr") :through :clref) (:end :misc)
                     (:begin :misc :arguments ("rplaca") :through :clref) (:end :misc)
                     (:begin :misc :arguments ("") :through :clref) (:end :misc)
                     (:begin :caption :arguments ())
                     (:end :caption)
                     (:end :figure)))
  ;; concept-glossary.tex:138-140: \\tabletwo's rows are \\entry marks.
  (check-vocabulary (concatenate 'string (spec-lines "concept-glossary" 49 67)
                                 (spec-lines "concept-glossary" 138 140) "}
")
                    ((:mark :entry :arguments ("\\Adjective " "adjective"))
                     (:mark :entry :arguments ("\\Adverb " "adverb")))
                    :keys (:entry)))

(defun why-place (why)
  "The first FILE.tex:LINE that WHY names, as (FILE LINE), or NIL: the
place of the definition, by the convention of the data file (later
places a reason names are not checked)."
  (let ((dot (search ".tex:" why)))
    (when dot
      (let ((start (1+ (or (position-if-not (lambda (char)
                                              (or (alphanumericp char) (char= char #\-)))
                                            why :end dot :from-end t)
                           -1)))
            (end (or (position-if-not #'digit-char-p why :start (+ dot 5))
                     (length why))))
        (list (subseq why start (+ dot 4))
              (parse-integer why :start (+ dot 5) :end end))))))

(defun defines-name-p (line name)
  "True when LINE, a source line, defines the control sequence NAME with
\\def, \\gdef, \\edef, \\xdef or \\let (a space may follow the
command): some occurrence is not followed by a letter, which would make
it another name."
  (flet ((defined-by-p (command)
           (let ((target (concatenate 'string command "\\" name)))
             (loop for at = (search target line) then (search target line :start2 (1+ at))
                   while at
                   thereis (let ((after (+ at (length target))))
                             (or (= after (length line))
                                 (not (alpha-char-p (char line after)))))))))
    (some #'defined-by-p '("\\def" "\\gdef" "\\edef" "\\xdef" "\\let"
                           "\\def " "\\let "))))

(define-test vocabulary-reasons-name-definitions
  :parent spec-vocabulary
  ;; Each entry's reason names the line of the setup files that defines
  ;; its macro.
  (let ((files (make-hash-table :test #'equal)))
    (flet ((source-line (file line)
             (nth (1- line)
                  (or (gethash file files)
                      (setf (gethash file files)
                            (uiop:read-file-lines
                             (spec-file (subseq file 0 (- (length file) 4)))))))))
      (dolist (entry (semantic:vocabulary-entries (semantic:spec-vocabulary)))
        (let ((name (semantic:entry-name entry))
              (place (why-place (semantic:entry-why entry))))
          (true place "\\~A's reason names a place" name)
          (when place
            (destructuring-bind (file line) place
              (true (defines-name-p (source-line file line) name)
                    "~A:~D defines \\~A" file line name))))))))
