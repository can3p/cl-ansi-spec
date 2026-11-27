;;;; tests/expand/alignments.lisp
;;;;
;;;; Alignments (src/expand/alignments.lisp; docs/events.md): the
;;;; preamble, templates, \span, \omit, \noalign, \cr and \crcr, \everycr,
;;;; \valign, display alignments, what migrates out of entries, and TeX's
;;;; errors (TeX: The Program, §§768-812, 1126-1131, 1206).

(in-package #:cl-ansi-spec/tests)

(define-test alignments
  :parent cl-ansi-spec
  :description "\\halign and \\valign.")

;;; The preamble

(define-test preamble
  :parent alignments
  (check-events "\\halign{#\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")))
                 (:end :alignment)))
  ;; Leading blanks of a u template are dropped; \tabskip set in the
  ;; preamble is the glue after the column, and local to the alignment.
  (check-events "\\tabskip=1pt\\halign to 3pt{ (# )\\tabskip=2pt& [#]\\cr}\\kern\\tabskip"
                ((:begin :alignment :command "halign" :spec (:exactly "3.0pt")
                  :tabskip "1.0pt" :preamble (("(" " )" "2.0pt") ("[" "]" "2.0pt")))
                 (:end :alignment)
                 (:kern :width "1.0pt")))
  ;; \span expands the next token once; `&&' repeats.
  (check-events "\\def\\p{(##)}\\halign spread 1pt{\\span\\p&&[#]&\\span\\relax{#}\\cr}"
                ((:begin :alignment :command "halign" :spec (:additional "1.0pt")
                  :tabskip "0.0pt"
                  :preamble (("(" ")" "0.0pt") ("[" "]" "0.0pt") ("\\relax {" "}" "0.0pt"))
                  :loop 2)
                 (:end :alignment)))
  (check-events "\\halign{&#\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")) :loop 1)
                 (:end :alignment)))
  ;; The braces of a template are its own.
  (check-events "\\halign{{&}#\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("{&}" "" "0.0pt")))
                 (:end :alignment)))
  (check-events "\\halign{a&#\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("a" "" "0.0pt") ("" "" "0.0pt")))
                 (:end :alignment))
                :errors ("Missing # inserted in alignment preamble"))
  (check-events "\\halign{#a#b\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" "ab" "0.0pt")))
                 (:end :alignment))
                :errors ("Only one # is allowed per tab"))
  ;; An \outer macro in the preamble ends it.
  (check-events "\\outer\\def\\o{}\\halign{#\\o\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" " " "0.0pt")))
                 (:end :alignment))
                :errors ("Forbidden control sequence found" "Misplaced" "Too many }'s")))

;;; Rows and entries

(define-test rows-and-cells
  :parent alignments
  (check-events "\\halign{(#)&[#]\\cr a&b\\cr c\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("(" ")" "0.0pt") ("[" "]" "0.0pt")))
                 (:begin :row)
                 (:begin :cell :column 1) (:text "(a" :style "nullfont") (:text ")" :style "nullfont") (:end :cell)
                 (:begin :cell :column 2) (:text "[b" :style "nullfont") (:text "]" :style "nullfont") (:end :cell)
                 (:end :row)
                 (:begin :row)
                 (:begin :cell :column 1) (:text "(c" :style "nullfont") (:text ")" :style "nullfont") (:end :cell)
                 (:end :row)
                 (:end :alignment)))
  ;; \omit, \span, \crcr; \relax begins a row; blanks before an entry are
  ;; skipped.
  (check-events "\\halign{(#)&[#]\\cr\\omit a& \\omit\\cr\\crcr a\\span b\\crcr
\\relax\\span\\omit\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("(" ")" "0.0pt") ("[" "]" "0.0pt")))
                 (:begin :row)
                 (:begin :cell :column 1 :omit (1)) (:text "a" :style "nullfont") (:end :cell)
                 (:begin :cell :column 2 :omit (2)) (:end :cell)
                 (:end :row)
                 (:begin :row)
                 (:begin :cell :column 1 :columns 2) (:text "(a" :style "nullfont") (:text ")[b" :style "nullfont") (:text "]" :style "nullfont")
                 (:end :cell)
                 (:end :row)
                 (:begin :row)
                 (:begin :cell :column 1 :columns 2 :omit (2)) (:text "()" :style "nullfont")
                 (:end :cell)
                 (:end :row)
                 (:end :alignment)))
  ;; A repeating preamble grows; without one, an extra `&' is \cr.
  (check-events "\\halign{#&&[#]&(#)\\cr a&b&c&d&e\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt") ("[" "]" "0.0pt") ("(" ")" "0.0pt"))
                  :loop 2)
                 (:begin :row)
                 (:begin :cell :column 1) (:text "a" :style "nullfont") (:end :cell)
                 (:begin :cell :column 2) (:text "[b" :style "nullfont") (:text "]" :style "nullfont") (:end :cell)
                 (:begin :cell :column 3) (:text "(c" :style "nullfont") (:text ")" :style "nullfont") (:end :cell)
                 (:begin :cell :column 4) (:text "[d" :style "nullfont") (:text "]" :style "nullfont") (:end :cell)
                 (:begin :cell :column 5) (:text "(e" :style "nullfont") (:text ")" :style "nullfont") (:end :cell)
                 (:end :row)
                 (:end :alignment)))
  ;; \span at the end of a repeating preamble lengthens it.
  (check-events "\\halign{#&&#\\cr a\\span b\\span c\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt") ("" "" "0.0pt")) :loop 2)
                 (:begin :row)
                 (:begin :cell :column 1 :columns 3) (:text "abc" :style "nullfont")
                 (:end :cell)
                 (:end :row)
                 (:end :alignment)))
  (check-events "\\halign{#\\cr a&b\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")))
                 (:begin :row)
                 (:begin :cell :column 1) (:text "a" :style "nullfont") (:end :cell)
                 (:end :row)
                 (:begin :row)
                 (:begin :cell :column 1) (:text "b" :style "nullfont") (:end :cell)
                 (:end :row)
                 (:end :alignment))
                :errors ("Extra alignment tab has been changed to \\cr"))
  ;; A cell's groups are its own; `&' in braces needs them closed.
  (check-events "\\halign{#&#\\cr{a&b}\\cr}\\par"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt") ("" "" "0.0pt")))
                 (:begin :row)
                 (:begin :cell :column 1) (:text "a" :style "nullfont") (:end :cell)
                 (:begin :cell :column 2) (:text "b" :style "nullfont") (:end :cell)
                 (:end :row)
                 (:end :alignment))
                :errors ("Missing } inserted" "Missing \\cr inserted" "Misplaced"
                         "Too many }'s"))
  (check-events "\\halign{#&#\\cr a\\iffalse}\\fi&b\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt") ("" "" "0.0pt")))
                 (:begin :row)
                 (:begin :cell :column 1) (:text "a" :style "nullfont") (:end :cell)
                 (:begin :cell :column 2) (:text "b" :style "nullfont") (:end :cell)
                 (:end :row)
                 (:end :alignment))
                :errors ("Missing { inserted" "Missing } inserted"))
  ;; A cell's assignments are local to it.
  (check-events "\\halign{#&#\\cr\\kern1pt\\dimen0=2pt&\\kern\\dimen0\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt") ("" "" "0.0pt")))
                 (:begin :row)
                 (:begin :cell :column 1) (:kern :width "1.0pt") (:end :cell)
                 (:begin :cell :column 2) (:kern :width "0.0pt") (:end :cell)
                 (:end :row)
                 (:end :alignment))))

(define-test no-align-and-everycr
  :parent alignments
  (check-events "\\halign{#\\cr\\noalign{\\kern1pt}a\\cr\\noalign{\\kern2pt}\\noalign{\\kern3pt}%
\\noalign{}}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")))
                 (:begin :no-align) (:kern :width "1.0pt") (:end :no-align)
                 (:begin :row)
                 (:begin :cell :column 1) (:text "a" :style "nullfont") (:end :cell)
                 (:end :row)
                 (:begin :no-align) (:kern :width "2.0pt") (:kern :width "3.0pt")
                 (:end :no-align)
                 (:end :alignment)))
  ;; \everycr after the preamble and every \cr; an empty \noalign is
  ;; kept.
  (check-events "\\everycr{\\noalign{}}\\halign{#\\cr a\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")))
                 (:begin :no-align) (:end :no-align)
                 (:begin :row)
                 (:begin :cell :column 1) (:text "a" :style "nullfont") (:end :cell)
                 (:end :row)
                 (:begin :no-align) (:end :no-align)
                 (:end :alignment)))
  ;; \noalign material sees the alignment's list.
  (check-events "\\halign{#\\cr\\noalign{\\kern1pt}\\noalign{\\unkern\\kern2pt}}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")))
                 (:begin :no-align) (:kern :width "2.0pt") (:end :no-align)
                 (:end :alignment)))
  (check-events "\\halign{#\\cr\\noalign{\\cr}}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")))
                 (:begin :no-align) (:end :no-align)
                 (:end :alignment))
                :errors ("Misplaced")))

(define-test valign-and-modes
  :parent alignments
  ;; \valign: in a paragraph; its entries are vertical lists.
  (check-events "\\noindent\\valign{#\\cr\\kern1pt\\cr}\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:begin :alignment :command "valign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")))
                 (:begin :row)
                 (:begin :cell :column 1) (:kern :width "1.0pt") (:end :cell)
                 (:end :row)
                 (:end :alignment)
                 (:end :paragraph)))
  ;; In vertical mode \valign begins a paragraph, in a paragraph
  ;; \halign ends it.
  (check-events "\\valign{#\\cr}x\\halign{#\\cr}"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph) (:indent)
                 (:begin :alignment :command "valign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")))
                 (:end :alignment)
                 (:text "x" :style "nullfont")
                 (:end :paragraph)
                 (:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")))
                 (:end :alignment)))
  ;; A text entry of a \valign is a paragraph; an alignment in an entry.
  (check-events "\\valign{#\\cr a\\cr}\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph) (:indent)
                 (:begin :alignment :command "valign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")))
                 (:begin :row)
                 (:begin :cell :column 1)
                 (:begin :paragraph) (:indent) (:text "a" :style "nullfont") (:end :paragraph)
                 (:end :cell)
                 (:end :row)
                 (:end :alignment)
                 (:end :paragraph)))
  (check-events "\\halign{#\\cr\\vbox{\\halign{[#]\\cr b\\cr}}\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")))
                 (:begin :row)
                 (:begin :cell :column 1)
                 (:begin :box :kind :vbox :command "vbox")
                 (:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("[" "]" "0.0pt")))
                 (:begin :row)
                 (:begin :cell :column 1) (:text "[b" :style "nullfont") (:text "]" :style "nullfont") (:end :cell)
                 (:end :row)
                 (:end :alignment)
                 (:end :box)
                 (:end :cell)
                 (:end :row)
                 (:end :alignment)))
  ;; Misplaced commands.
  (check-events "\\noindent a&\\cr\\span\\noalign\\omit\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:text "a" :style "nullfont") (:end :paragraph))
                :errors ("Misplaced" "Misplaced" "Misplaced" "Misplaced" "Misplaced"))
  (check-job "\\noindent&\\par" "" :errors ("Misplaced")
                                   :contexts ("alignment tab character &"))
  (check-job (with-math-fonts "$\\halign{}$") ""
             :errors ("You can't use")
             :contexts ("`\\halign' in math mode")))

(define-test display-alignments
  :parent alignments
  (check-events (with-math-fonts "\\noindent$$\\halign{#\\cr a\\cr}$$\\par")
                ((:glue :glue "0.0pt" :command "parskip")
                 (:begin :alignment :command "halign" :display t :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")))
                 (:begin :row)
                 (:begin :cell :column 1) (:text "a" :style "nullfont") (:end :cell)
                 (:end :row)
                 (:end :alignment)))
  ;; Assignments may follow; then `$$'.
  (check-events (with-math-fonts "\\noindent$$\\halign{#\\cr}\\dimen0=1pt$x\\par")
                ((:glue :glue "0.0pt" :command "parskip")
                 (:begin :alignment :command "halign" :display t :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")))
                 (:end :alignment)
                 (:begin :paragraph) (:text "x" :style "nullfont") (:end :paragraph))
                :errors ("Display math should end with $$"))
  (check-events (with-math-fonts "\\noindent$$\\halign{#\\cr}x\\par")
                ((:glue :glue "0.0pt" :command "parskip")
                 (:begin :alignment :command "halign" :display t :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")))
                 (:end :alignment)
                 (:begin :paragraph) (:text "x" :style "nullfont") (:end :paragraph))
                :errors ("Missing $$ inserted"))
  (check-events (with-math-fonts "\\noindent$$x\\halign{#\\cr}$$")
                ((:glue :glue "0.0pt" :command "parskip")
                 (:begin :alignment :command "halign" :display t :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")))
                 (:end :alignment))
                :errors ("Improper \\halign inside $$'s"))
  ;; In a group of the display, what ends the group comes first; in a
  ;; subformula it is inner math.
  (check-job (with-math-fonts "\\noindent$$\\begingroup\\halign{#\\cr}$$") ""
             :errors ("Missing \\endgroup inserted"))
  (check-job (with-math-fonts "\\noindent$${\\halign{}}$$") ""
             :errors ("You can't use")
             :contexts ("`\\halign' in math mode")))

;;; Templates and the input stack

(define-test templates
  :parent alignments
  ;; Templates may open and close the entry's groups.
  (check-events "\\let\\bgroup={\\let\\egroup=}\\halign{\\hbox\\bgroup#\\egroup\\cr a\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("\\hbox \\bgroup " "\\egroup " "0.0pt")))
                 (:begin :row)
                 (:begin :cell :column 1)
                 (:begin :box :kind :hbox :command "hbox") (:text "a" :style "nullfont")
                 (:end :box)
                 (:end :cell)
                 (:end :row)
                 (:end :alignment)))
  ;; A u template ending in `{': back_input ends the template before it
  ;; counts the brace again, so that the entry's `&' is at level 0 inside
  ;; it (§325).
  (check-events "\\halign{\\hbox{#}\\cr a\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("\\hbox {" "}" "0.0pt")))
                 (:begin :row)
                 (:begin :cell :column 1)
                 (:begin :box :kind :hbox :command "hbox") (:text "a" :style "nullfont")
                 (:end :box)
                 (:end :cell)
                 (:end :row)
                 (:end :alignment)))
  ;; \endtemplate ends a macro's argument as an \outer macro would.
  (check-events "\\def\\x#1{}\\halign{#\\cr\\relax\\x\\cr}"
                ((:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")))
                 (:begin :row) (:begin :cell :column 1) (:end :cell) (:end :row)
                 (:end :alignment))
                :errors ("Forbidden control sequence found"))
  ;; Templates out of step are TeX's fatal error.
  (check-job "\\let\\bgroup={\\halign{\\valign\\bgroup#\\cr a\\cr}" ""
             :fatal "(interwoven alignment preambles are not allowed)")
  (let ((expander (make-test-expander "")))
    (is string= "\\outer endtemplate"
        (expand:meaning-text expander nil (expand::end-template-meaning)))
    (is string= "end of alignment template"
        (expand:meaning-text expander nil (expand::endv-meaning)))))

;;; What migrates out of an \halign's entries

(define-test alignment-migration
  :parent alignments
  (check-log "\\setbox1\\vbox{\\halign{#\\cr\\mark{a}\\cr\\noalign{\\mark{b}}}}%
\\setbox2\\vsplit1 to0pt \\message{\\splitfirstmark,\\splitbotmark}"
             ((:message "a,b")))
  (check-events "\\immediate\\openout1=f \\shipout\\vbox{\\halign{#\\cr\\vadjust{\\write1{q}}\\write1{p}\\cr}}"
                ((:openout :stream 1 :file "f" :immediate t)
                 (:begin :shipout) (:begin :box :kind :vbox :command "vbox")
                 (:begin :alignment :command "halign" :tabskip "0.0pt"
                  :preamble (("" "" "0.0pt")))
                 (:begin :row) (:begin :cell :column 1)
                 (:begin :vadjust) (:write :stream 1 :tokens "q") (:end :vadjust)
                 (:write :stream 1 :tokens "p")
                 (:end :cell) (:end :row)
                 (:end :alignment)
                 (:end :box) (:end :shipout)
                 (:write :stream 1 :tokens "p" :text "p" :shipout t)
                 (:write :stream 1 :tokens "q" :text "q" :shipout t))))

;;; The sources' alignments, with what they need defined

(defun alignment-shapes (expander)
  "The alignments of EXPANDER's job, outermost and first first, each as
the list of its children: :NO-ALIGN, or a row as the columns its cells
begin in."
  (let ((shapes '()))
    (labels ((walk (nodes)
               (dolist (node nodes)
                 (when (eq (expand:node-kind node) :alignment)
                   (push (mapcar (lambda (child)
                                   (if (eq (expand:node-kind child) :row)
                                       (mapcar (lambda (cell)
                                                 (getf (expand:node-properties cell) :column))
                                               (expand:node-children child))
                                       :no-align))
                                 (expand:node-children node))
                         shapes))
                 (when (expand:node-composite node)
                   (walk (expand:node-children node))))))
      (walk (expand:list-nodes (expand:outer-list expander))))
    (nreverse shapes)))

(defmacro check-shapes (text shapes &key (errors '()))
  "Run TEXT\\end and check the SHAPES of its alignments and its ERRORS."
  `(let ((expander (make-test-expander (concatenate 'string ,text "\\end"))))
     (multiple-value-bind (output messages) (run-job expander)
       (declare (ignore output))
       (is equal ',shapes (alignment-shapes expander) "alignments of ~S" ,text)
       (is equal ',errors messages "errors of ~S" ,text))))

(define-test source-alignments
  :parent alignments
  ;; setup-document.tex:132-134 and :139-141 (inside a \vbox): entries
  ;; from a macro whose `&' and \cr come from another one.
  (check-shapes "\\def\\function{}\\def\\arg{}\\def\\EV{}\\def\\quad{\\hskip1em}%
\\def\\D#1#2#3{\\def\\entry##1{##1&\\cr}%
\\halign{\\hskip\\leftskip\\function ## {\\arg #1}\\hfil&\\quad\\EV\\ {\\arg #2}##\\cr#3}}%
\\D{x}{y}{\\entry{a}\\entry{b}}%
\\def\\V#1#2#3{\\hskip\\leftskip\\hbox{{\\def\\entry##1{##1&\\cr}%
\\vbox{\\halign{\\function ## {\\arg #1}\\hfil&\\quad\\EV\\ {\\arg #2}##\\cr#3}}}}}%
\\V{x}{y}{\\entry{c}}\\par"
                (((1 2) (1 2)) ((1 2))))
  ;; setup-document.tex:320-324: \CR is `\cr\noalign{...}&&'.
  (check-shapes (with-math-fonts "\\hsize=100pt \\def\\arg{}\\def\\param#1{#1}%
\\def\\auxbnf#1#2{{\\vskip 4pt\\def\\CR{\\cr\\noalign{\\penalty1000\\vskip 4pt\\penalty1000}&&}\\arg
\\halign to \\hsize{\\hskip\\leftskip\\quad##&\\hfil##& ##\\hfil\\cr
&\\param{#1}::$=$& #2\\cr}}}
\\def\\quad{\\hskip1em}\\auxbnf{name}{a\\CR b\\CR c}")
                (((1 2 3) :no-align (1 2 3) :no-align (1 2 3))))
  ;; setup-tables.tex:4-11: \tabskip before and in the preamble,
  ;; \noalign before the first row and after the last.
  (let ((text "\\hsize=100pt \\def\\misc#1{#1}%
\\def\\displaytwo #1#2{{\\dimen0=.75pc
\\tabskip \\dimen0 plus .5 fil
\\halign to \\hsize {\\misc{##}\\hfil\\tabskip \\dimen0 plus 1fil&
\\misc{##}\\hfil\\cr
\\noalign{\\vskip -9pt}
#2
\\noalign{\\vskip -9pt}
}}}\\displaytwo{T}{a&b\\cr c&d\\cr}"))
    (check-shapes text ((:no-align (1 2) (1 2) :no-align)))
    (let* ((expander (make-test-expander (concatenate 'string text "\\end")))
           (node (progn (run-job expander)
                        (first (expand:list-nodes (expand:outer-list expander)))))
           (properties (expand:node-properties node)))
      (is equal '(:exactly "100.0pt") (getf properties :spec))
      (is string= "9.0pt plus 0.5fil" (getf properties :tabskip))
      (is equal '("9.0pt plus 1.0fil" "9.0pt plus 1.0fil")
          (mapcar (lambda (column) (getf column :tabskip)) (getf properties :preamble)))))
  ;; setup-boxfig.tex:168-177: \everycr's \noalign, a preamble that
  ;; begins with `&'.
  (check-shapes "\\def\\he{height}\\def\\wi{width}\\def\\de{depth}\\chardef\\x=1 \\chardef\\z=2
\\def\\ShiftBox#1{\\setbox\\x
\\vbox{  \\everycr{\\noalign{{\\global\\setbox\\z\\hbox{}}}}
        \\halign{&\\setbox\\x\\hbox{##}
        \\global \\setbox\\z\\hbox{\\unhbox\\z\\vrule\\he\\ht\\x\\de\\dp\\x\\wi0pt}
                \\unhbox\\x
                \\cr
                #1}}\\box\\x}\\ShiftBox{a&b&c\\cr}"
                ((:no-align (1 2 3) :no-align))))
