;;;; tests/semantic/observe.lisp
;;;;
;;;; The vocabulary mechanism (src/semantic/; docs/vocabulary.md): entries
;;;; recognised by their meanings, inline and block placement,
;;;; environments, marks, replace handlers, redefinition reports, and the
;;;; code round-trip fixture.  Jobs run from plain TeX's format.

(in-package #:cl-ansi-spec/tests)

(define-test semantic
  :parent cl-ansi-spec
  :description "The semantic layer: vocabulary entries and their events.")

(defun test-vocabulary (specs)
  "A vocabulary of SPECS, each (name key . make-entry options)."
  (semantic:make-vocabulary
   (loop for (name key . options) in specs
         collect (apply #'semantic:make-entry name key options))))

(defun semantic-job (text specs)
  "A job from plain TeX's format reading TEXT\\end, observing the entries
SPECS (see TEST-VOCABULARY).  Returns the expander and the observer."
  (let ((expander (make-format-job (concatenate 'string text "\\end"))))
    (values expander (semantic:observe-vocabulary expander (test-vocabulary specs)))))

(defun semantic-events (expander &key (text-only nil))
  "EXPANDER's events without spans, the parskip glue and indentation;
:ARGUMENTS shown as texts.  With TEXT-ONLY, a :TEXT event is just its
kind and text."
  (loop for event in (expand:job-events expander)
        for (kind) = event
        unless (or (eq kind :indent)
                   (and (eq kind :glue)
                        (equal (getf (rest event) :command) "parskip")))
          collect (strip-semantic-event expander event text-only)))

(defun strip-semantic-event (expander event text-only)
  "EVENT as SEMANTIC-EVENTS shows it."
  (let* ((stripped (if (eq (first event) :mark)
                       (cons :mark (rest (strip-event expander (cons :begin (rest event)))))
                       (strip-event expander event)))
         (head (if (member (first event) '(:begin :end :mark :text)) 2 1))
         (arguments (getf (nthcdr head stripped) :arguments)))
    (cond ((and text-only (eq (first event) :text)) (subseq stripped 0 2))
          ((and (= head 2) arguments)
           (append (subseq stripped 0 2)
                   (list :arguments (mapcar (lambda (tokens)
                                              (expand:token-list-text expander tokens))
                                            arguments))
                   (let ((rest (copy-list (nthcdr 2 stripped))))
                     (remf rest :arguments)
                     rest)))
          (t stripped))))

(defmacro check-semantic (text specs events &key (reports '()))
  "Run TEXT observing SPECS; check its EVENTS (text events shown by their
text only) and the kinds and names of its REPORTS."
  `(multiple-value-bind (expander observer) (semantic-job ,text ',specs)
     (run-job expander)
     (is equal ',events (semantic-events expander :text-only t) "events of ~S" ,text)
     (is equal ',reports (mapcar (lambda (report)
                                   (list (semantic:report-kind report)
                                         (semantic:report-name report)))
                                 (semantic:observer-reports observer))
         "reports of ~S" ,text)))

;;; Vocabularies

(define-test vocabularies
  :parent semantic
  (let ((vocabulary (test-vocabulary '(("a" :a) ("b" :b :kind :open)
                                       ("c" :c :kind :close :closes :b)))))
    (is eq :a (semantic:entry-key (semantic:find-entry vocabulary "a")))
    (is eq nil (semantic:find-entry vocabulary "z"))
    (is eq :observe (semantic:entry-mode (semantic:find-entry vocabulary "a"))))
  (is eq :replace (semantic:entry-mode (semantic:make-entry "x" :x :handler 'identity)))
  (fail (test-vocabulary '(("a" :a) ("a" :b))))
  (let ((expander (make-format-job "")))
    (semantic:observe-vocabulary expander (test-vocabulary '()))
    (fail (semantic:observe-vocabulary expander (test-vocabulary '()))))
  (fail (test-vocabulary '(("c" :c :kind :close :closes :b))))
  (fail (test-vocabulary '(("a" :a :closes :b) ("b" :b :kind :open)))))

;;; Placement

(define-test placement
  :parent semantic
  ;; An inline entry begins with its content: inside the paragraph it
  ;; starts, after the indentation; it ends after its body.
  (check-semantic "\\def\\tm#1{{\\it #1\\/}}\\tm{word} and more\\par"
                  (("tm" :term))
                  ((:begin :paragraph)
                   (:begin :term :arguments ("word")) (:text "word")
                   (:kern :width "0.0pt" :italic t) (:end :term)
                   (:space) (:text "and") (:space) (:text "more")
                   (:end :paragraph)))
  ;; A block entry is placed at once, where it is called.
  (check-semantic "\\def\\tm#1{#1\\par}\\tm{word}"
                  (("tm" :term :placement :block))
                  ((:begin :term :arguments ("word"))
                   (:begin :paragraph) (:text "word") (:end :paragraph) (:end :term)))
  ;; An inline entry with no content is placed with its end; pending
  ;; begins keep their order.
  (check-semantic "\\def\\e{}\\def\\oo{\\e!}x\\oo\\e\\par"
                  (("e" :e) ("oo" :o))
                  ((:begin :paragraph) (:text "x")
                   (:begin :o :arguments ()) (:begin :e :arguments ()) (:end :e)
                   (:text "!") (:end :o)
                   (:begin :e :arguments ()) (:end :e)
                   (:end :paragraph)))
  ;; An end in another list than its begin is reported: a body that
  ;; opens a box it does not close, or ends the paragraph.
  (check-semantic "\\def\\bx#1{\\hbox{#1}}\\bx{a}"
                  (("bx" :bx))
                  ((:begin :box :kind :hbox :command "hbox")
                   (:begin :bx :arguments ("a")) (:text "a")
                   (:end :box)
                   (:end :bx))
                  :reports ((:unbalanced "bx")))
  (check-semantic "\\def\\pp#1{#1\\par}x\\pp{y}"
                  (("pp" :pp))
                  ((:begin :paragraph) (:text "x") (:begin :pp :arguments ("y"))
                   (:text "y") (:end :paragraph) (:end :pp))
                  :reports ((:unbalanced "pp")))
  ;; A body that opens with a formula begins before it, in the list
  ;; that holds it, in a paragraph or in the paragraph it starts.
  (check-semantic "\\def\\an#1{{$<$}#1}x\\an{y}\\par\\an{z}\\par"
                  (("an" :an))
                  ((:begin :paragraph) (:text "x")
                   (:begin :an :arguments ("y"))
                   (:begin :math) (:begin :noad :class :rel) (:begin :nucleus)
                   (:math-char :fam 1 :code 60) (:end :nucleus) (:end :noad) (:end :math)
                   (:text "y") (:end :an) (:end :paragraph)
                   (:begin :paragraph)
                   (:begin :an :arguments ("z"))
                   (:begin :math) (:begin :noad :class :rel) (:begin :nucleus)
                   (:math-char :fam 1 :code 60) (:end :nucleus) (:end :noad) (:end :math)
                   (:text "z") (:end :an) (:end :paragraph)))
  ;; A macro of an alignment's first cell is expanded before the row
  ;; and the cell open; its begin goes into the cell.
  (check-semantic "\\def\\tm#1{{\\it #1\\/}}\\halign{#\\cr\\tm{a}\\cr}"
                  (("tm" :term))
                  ((:begin :alignment :command "halign" :tabskip "0.0pt"
                    :preamble (("" "" "0.0pt")))
                   (:begin :row) (:begin :cell :column 1)
                   (:begin :term :arguments ("a")) (:text "a")
                   (:kern :width "0.0pt" :italic t) (:end :term)
                   (:end :cell) (:end :row) (:end :alignment)))
  ;; A penalty in a vertical list does not end the wait (\\EV opens with
  ;; one at the start of a code line); one in a paragraph does.
  (check-semantic "\\def\\ev{{\\penalty20000}{$<$}}\\ev y\\par\\def\\pe{\\penalty5 z}a\\pe\\par"
                  (("ev" :ev) ("pe" :pe))
                  ((:penalty :value 20000)
                   (:begin :paragraph)
                   (:begin :ev :arguments ())
                   (:begin :math) (:begin :noad :class :rel) (:begin :nucleus)
                   (:math-char :fam 1 :code 60) (:end :nucleus) (:end :noad) (:end :math)
                   (:end :ev)
                   (:text "y") (:end :paragraph)
                   (:begin :paragraph) (:text "a")
                   (:begin :pe :arguments ()) (:penalty :value 5) (:text "z") (:end :pe)
                   (:end :paragraph)))
  ;; A call made in a paragraph its body ends waits for content after
  ;; it (a figure set in a paragraph).
  (check-semantic "\\def\\fg{\\par\\vfil\\relax}x\\fg"
                  (("fg" :fg))
                  ((:begin :paragraph) (:text "x") (:end :paragraph)
                   (:begin :fg :arguments ())
                   (:glue :glue "0.0pt plus 1.0fil" :command "vfil")
                   (:end :fg)))
  ;; With no content after the paragraph, it is placed with its end.
  (check-semantic "\\def\\fg{\\par}x\\fg\\relax"
                  (("fg" :fg))
                  ((:begin :paragraph) (:text "x") (:end :paragraph)
                   (:begin :fg :arguments ()) (:end :fg)))
  ;; The end of a call whose body is read as the argument of a wrapper's
  ;; tail call does not drop the wrapper (TeX expands a cell's first
  ;; macro before the template that wraps it).
  (check-semantic "\\def\\cl#1{(#1)}\\def\\w{\\cl}\\def\\e#1{#1}x\\expandafter\\w\\e{z}\\par"
                  (("cl" :cl) ("w" :w :kind :wrapper) ("e" :e))
                  ((:begin :paragraph) (:text "x")
                   (:begin :e :arguments ("z")) (:end :e)
                   (:begin :w :arguments ("z") :through :cl) (:text "(z") (:text ")") (:end :w)
                   (:end :paragraph)))
  ;; The end's span is the body's last token, here an argument's.
  (multiple-value-bind (expander) (semantic-job "\\def\\tm#1{(#1}\\tm{ab}\\par" '(("tm" :t)))
    (run-job expander)
    (let ((end (find :end (expand:job-events expander)
                     :key (lambda (event) (and (eq (second event) :t) (first event))))))
      (is = 19 (span-column (getf (cddr end) :span))))))

;;; Keyed on meanings

(define-test meanings
  :parent semantic
  ;; \let copies share the meaning; a \def wrapper is another macro, and
  ;; the entry it calls is observed inside it; \csname-built calls and
  ;; tokens from an alignment template are recognised too.
  (check-semantic "\\def\\r#1{#1}\\let\\s=\\r \\def\\w#1{(\\r{#1})}%
\\s{ab}\\w{b}\\csname r\\endcsname{c}\\par
\\halign{\\r{#}\\cr d\\cr}"
                  (("r" :ref))
                  ((:begin :paragraph)
                   (:begin :ref :arguments ("ab")) (:text "ab") (:end :ref)
                   (:text "(") (:begin :ref :arguments ("b")) (:text "b") (:end :ref)
                   (:text ")")
                   (:begin :ref :arguments ("c")) (:text "c") (:end :ref)
                   (:end :paragraph)
                   (:begin :alignment :command "halign" :tabskip "0.0pt"
                    :preamble (("\\r {" "}" "0.0pt")))
                   (:begin :row)
                   (:begin :cell :column 1)
                   (:begin :ref :arguments ("d")) (:text "d") (:end :ref)
                   (:end :cell)
                   (:end :row)
                   (:end :alignment)))
  ;; A macro the format defines is an entry from the job's start.
  (check-semantic "\\centerline{x}"
                  (("centerline" :centerline :placement :block))
                  ((:begin :centerline :arguments ("x"))
                   (:begin :box :kind :hbox :command "hbox" :spec (:exactly "469.75499pt"))
                   (:glue :glue "0.0pt plus 1.0fil minus 1.0fil" :command "hss")
                   (:text "x")
                   (:glue :glue "0.0pt plus 1.0fil minus 1.0fil" :command "hss")
                   (:end :box)
                   (:end :centerline))))

(define-test redefinitions
  :parent semantic
  ;; Redefining an entry's macro is reported, with both spans; the new
  ;; meaning is attached, and so is the old.
  (multiple-value-bind (expander observer)
      (semantic-job "\\def\\mycap#1{#1}
\\def\\mycap#1{[#1]}\\mycap{x}\\par
\\def\\line{}"
                    '(("mycap" :caption) ("line" :line)))
    (run-job expander)
    (let ((reports (semantic:observer-reports observer)))
      (is equal '((:redefined "mycap" 2 1) (:redefined "line" 3 nil))
          (mapcar (lambda (report)
                    (list (semantic:report-kind report) (semantic:report-name report)
                          (span-line (semantic:report-span report))
                          (and (semantic:report-previous-span report)
                               (span-line (semantic:report-previous-span report)))))
                  reports)))
    (is equal '((:begin :paragraph) (:begin :caption :arguments ("x")) (:text "[x")
                (:text "]") (:end :caption) (:end :paragraph))
        (semantic-events expander :text-only t)))
  ;; A definition a macro makes each time it is called is not reported.
  (check-semantic "\\def\\mk#1{\\def\\sr{#1}}\\mk{a}\\mk{b}x\\sr"
                  (("sr" :sr))
                  ((:begin :paragraph) (:text "x") (:begin :sr :arguments ()) (:text "b") (:end :sr)
                   (:end :paragraph)))
  ;; Giving two entries one meaning is reported; the first keeps it.
  (check-semantic "\\def\\xa{}\\let\\xb=\\xa \\xb"
                  (("xa" :a) ("xb" :b))
                  ((:begin :a :arguments ()) (:end :a))
                  :reports ((:shared "xb"))))

;;; Wrappers

(define-test wrappers
  :parent semantic
  ;; As setup-document.tex:62-79: a wrapper gives its key and arguments
  ;; to its tail call, whose arguments follow its own; the outermost of
  ;; a chain keeps them; a wrapper with no entry call before content is
  ;; reported and dropped.
  (check-semantic "\\def\\clref#1{{#1}}\\def\\funref{\\clref}\\def\\kwd#1{\\clref{:#1}}%
\\def\\keyref{\\funref}\\def\\odd{x}%
a\\clref{b}\\funref{c}\\kwd{d}\\keyref{e}\\odd\\par"
                  (("clref" :clref) ("funref" :funref :kind :wrapper)
                   ("kwd" :kwd :kind :wrapper) ("keyref" :keyref :kind :wrapper)
                   ("odd" :odd :kind :wrapper))
                  ((:begin :paragraph) (:text "a")
                   (:begin :clref :arguments ("b")) (:text "b") (:end :clref)
                   (:begin :funref :arguments ("c") :through :clref) (:text "c") (:end :funref)
                   (:begin :kwd :arguments ("d" ":d") :through :clref) (:text ":d") (:end :kwd)
                   (:begin :keyref :arguments ("e") :through :clref) (:text "e") (:end :keyref)
                   (:text "x")
                   (:end :paragraph))
                  :reports ((:unbalanced "odd")))
  ;; Only the call of the wrapper body's first token is its tail call.
  (check-semantic "\\def\\clref#1{{#1}}\\def\\funref{\\relax\\clref}%
x\\funref{y}\\par"
                  (("clref" :clref) ("funref" :funref :kind :wrapper))
                  ((:begin :paragraph) (:text "x") (:begin :clref :arguments ("y"))
                   (:text "y") (:end :clref) (:end :paragraph))
                  :reports ((:unbalanced "funref"))))

;;; Environments and marks

(define-test environments
  :parent semantic
  (check-semantic "\\def\\issue#1{}\\def\\endissue#1{}\\def\\label#1:{}%
x\\issue{I}y\\par\\label Syntax:z\\endissue{I}\\par"
                  (("issue" :issue :kind :open)
                   ("endissue" :endissue :kind :close :closes :issue)
                   ("label" :label :kind :mark))
                  ((:begin :paragraph) (:text "x") (:begin :issue :arguments ("I"))
                   (:text "y") (:end :paragraph)
                   (:mark :label :arguments ("Syntax"))
                   (:begin :paragraph) (:text "z") (:end :issue :arguments ("I"))
                   (:end :paragraph))))

;;; Replace handlers

(define-test replace-handlers
  :parent semantic
  ;; setup-document.tex:417-419 and setup-options.tex:23: the note is
  ;; hidden by the options, yet kept.
  (check-semantic "\\newif \\ifeditornotes  \\editornotestrue
\\def\\lbr{[}\\def\\rbr{]}
\\def\\editornote#1{\\ifeditornotes{\\bf\\lbr{#1}\\rbr}\\fi\\ignorespaces}
\\editornotesfalse
x\\editornote{KMP: check this.} y\\par"
                  (("editornote" :editor-note :handler semantic:hidden-note))
                  ((:begin :paragraph) (:text "x")
                   (:mark :editor-note :arguments ("KMP: check this.") :hidden t)
                   (:text "y") (:end :paragraph))))

;;; Code round-trip

(defparameter *code-lines*
  '("(defun f (x)" "  (* x  2))" "" "   ; done")
  "The lines of the code round-trip fixture.")

(defun code-text (events)
  "The source lines that EVENTS, the events between a code environment's
begin and end, typeset: a paragraph per line, characters and spaces."
  (let ((lines '()) (line nil))
    (dolist (event events (nreverse lines))
      (case (first event)
        (:begin (when (eq (second event) :paragraph)
                  (setf line (make-string-output-stream))))
        (:end (when (eq (second event) :paragraph)
                (push (get-output-stream-string line) lines)))
        (:text (write-string (second event) line))
        (:space (write-char #\Space line))))))

(define-test code-round-trip
  :parent semantic
  ;; An environment set as the spec sets code (\screen!,
  ;; setup-aux.tex:584, 592-606): each line a paragraph, every space an
  ;; interword space.
  (multiple-value-bind (expander)
      (semantic-job (format nil "{\\obeyspaces\\global\\let =\\ }
\\def\\code{\\begingroup\\parskip0pt\\def\\par{\\leavevmode\\endgraf}%
\\obeyspaces\\obeylines\\eatcr}
{\\catcode`\\^^M=\\active\\gdef\\eatcr#1^^M{}}
\\def\\endcode{\\endgraf\\endgroup}
\\code
~{~A~%~}\\endcode"
                            *code-lines*)
                    '(("code" :code :kind :open)
                      ("endcode" :endcode :kind :close :closes :code)))
    (run-job expander)
    (let* ((events (semantic-events expander))
           (begin (position :code events :key #'second))
           (end (position :code events :key #'second :start (1+ begin))))
      (is equal '(:begin :end) (list (first (nth begin events)) (first (nth end events))))
      (is equal *code-lines* (code-text (subseq events (1+ begin) end))))))
