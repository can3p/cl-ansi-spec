;;;; tests/expand/other-nodes.lisp
;;;;
;;;; The other nodes (src/expand/discretionaries.lisp, inserts.lisp,
;;;; whatsits.lisp, show-lists.lisp; docs/events.md): discretionaries,
;;;; accents, inserts and \vadjust, \special, \setlanguage, \shipout,
;;;; \showbox and \showlists.

(in-package #:cl-ansi-spec/tests)

;;; Discretionaries (§§1117-1121)

(define-test hyphen-discretionaries
  :parent events
  ;; \- pre-breaks the font's \hyphenchar (INITEX's nullfont: `-'), none
  ;; when it is no character code; a character after it begins a new run.
  (check-events "\\noindent a\\-b\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:text "a" :style "nullfont")
                 (:begin :discretionary :command "-") (:begin :pre-break)
                 (:text "-" :style "nullfont") (:end :pre-break) (:end :discretionary)
                 (:text "b" :style "nullfont") (:end :paragraph)))
  (check-events "\\hyphenchar\\font=-1 \\-\\hyphenchar\\font=256 \\-\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph) (:indent)
                 (:begin :discretionary :command "-") (:end :discretionary)
                 (:begin :discretionary :command "-") (:end :discretionary)
                 (:end :paragraph)))
  (check-events "\\font\\a=cmr10 \\hyphenchar\\a=`+ \\noindent\\a\\-\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:begin :discretionary :command "-") (:begin :pre-break)
                 (:text "+" :style "cmr10") (:end :pre-break) (:end :discretionary)
                 (:end :paragraph))))

(define-test explicit-discretionaries
  :parent events
  ;; Three lists, blanks and \relax before each `{', empty ones left out.
  (check-events "\\noindent\\discretionary{a\\kern1pt}\\relax {\\hbox{}b} {cd\\vrule}e\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:begin :discretionary :command "discretionary")
                 (:begin :pre-break) (:text "a" :style "nullfont") (:kern :width "1.0pt")
                 (:end :pre-break)
                 (:begin :post-break) (:begin :box :kind :hbox :command "hbox") (:end :box)
                 (:text "b" :style "nullfont") (:end :post-break)
                 (:begin :no-break) (:text "cd" :style "nullfont")
                 (:rule :kind :vrule :width "0.4pt" :height :running :depth :running)
                 (:end :no-break)
                 (:end :discretionary) (:text "e" :style "nullfont") (:end :paragraph)))
  (check-events "\\discretionary{}{}{}\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph) (:indent)
                 (:begin :discretionary :command "discretionary") (:end :discretionary)
                 (:end :paragraph)))
  ;; setup-aux.tex:855, \specialcomma, with stand-ins.
  (check-events "\\dimen1=2pt \\noindent\\discretionary{\\kern\\dimen1\\vrule width0pt}{}{,\\kern\\fontdimen2
\\nullfont}\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:begin :discretionary :command "discretionary")
                 (:begin :pre-break) (:kern :width "2.0pt")
                 (:rule :kind :vrule :width "0.0pt" :height :running :depth :running)
                 (:end :pre-break)
                 (:begin :no-break) (:text "," :style "nullfont") (:kern :width "0.0pt")
                 (:end :no-break) (:end :discretionary) (:end :paragraph))))

(define-test improper-discretionaries
  :parent events
  ;; §1121: the first node a discretionary may not hold and the rest of
  ;; its list are deleted, and shown in the log.
  (check-events "\\noindent\\discretionary{a\\penalty5 b\\kern1pt}{\\indent\\ }{x}\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:begin :discretionary :command "discretionary")
                 (:begin :pre-break) (:text "a" :style "nullfont") (:end :pre-break)
                 (:begin :post-break) (:indent) (:end :post-break)
                 (:begin :no-break) (:text "x" :style "nullfont") (:end :no-break)
                 (:end :discretionary) (:end :paragraph))
                :errors ("Improper discretionary list" "Improper discretionary list")
                :log ((:diagnostic "The following discretionary sublist has been deleted:
(:penalty :value 5)
(:text \"b\" :style \"nullfont\")
(:kern :width \"1.0pt\")")
                      (:diagnostic "The following discretionary sublist has been deleted:
(:space)")))
  ;; In math the no-break list is illegal and dropped.
  (check-events "\\noindent$\\discretionary{a}{}{x}$\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph) (:begin :math)
                 (:begin :discretionary :command "discretionary")
                 (:begin :pre-break) (:text "a" :style "nullfont") (:end :pre-break)
                 (:end :discretionary) (:end :math) (:end :paragraph))
                :errors ("Illegal math \\discretionary"
                         "Math formula deleted: Insufficient symbol fonts")))

(define-test long-discretionaries
  :parent events
  ;; At most 255 nodes, one per character; a longer no-break list
  ;; follows the disc node as ordinary nodes.
  (flet ((job (n)
           (let ((expander (make-test-expander
                            (format nil "\\noindent\\discretionary{}{}{~A}\\par\\end"
                                    (make-string n :initial-element #\a)))))
             (values expander (nth-value 1 (run-job expander))))))
    (multiple-value-bind (expander errors) (job 255)
      (is equal '() errors)
      (is equal `((:begin :discretionary :command "discretionary") (:begin :no-break)
                  (:text ,(make-string 255 :initial-element #\a) :style "nullfont")
                  (:end :no-break) (:end :discretionary))
          (mapcar (lambda (event) (strip-event expander event))
                  (subseq (expand:job-events expander) 2 7))))
    (multiple-value-bind (expander errors) (job 256)
      (is equal '("Discretionary list is too long") errors)
      (is equal `((:begin :discretionary :command "discretionary") (:end :discretionary)
                  (:text ,(make-string 256 :initial-element #\a) :style "nullfont")
                  (:end :paragraph))
          (mapcar (lambda (event) (strip-event expander event))
                  (subseq (expand:job-events expander) 2 6))))))

(define-test discretionary-tails
  :parent events
  ;; The end of a no-break list is the list's end for \lastkern and \/
  ;; (§424), but \unkern and \lastbox do not take it (§§1080, 1105).
  (check-events "\\noindent\\discretionary{}{}{x\\kern2pt}\\showthe\\lastkern\\unkern
\\showthe\\lastkern\\/\\discretionary{}{}{x}\\/\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:begin :discretionary :command "discretionary")
                 (:begin :no-break) (:text "x" :style "nullfont") (:kern :width "2.0pt")
                 (:end :no-break) (:end :discretionary)
                 (:begin :discretionary :command "discretionary")
                 (:begin :no-break) (:text "x" :style "nullfont") (:end :no-break)
                 (:end :discretionary) (:kern :width "0.0pt" :italic t) (:end :paragraph))
                :log ((:show "2.0pt") (:show "2.0pt")))
  (check-log "\\setbox2\\hbox{\\discretionary{}{}{\\hbox{}}\\global\\setbox1\\lastbox}%
\\showbox1"
             ((:show "\\box1=void"))))

;;; Accents (§§1122-1125)

(define-test accents
  :parent events
  ;; The accent alone, from vertical mode (a new paragraph).
  (check-events "\\accent`^\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph) (:indent)
                 (:begin :accent) (:text "^" :style "nullfont") (:end :accent)
                 (:end :paragraph)))
  ;; The accent's font is the one before the assignments, the
  ;; character's the one after; \/ follows the character.
  (check-events "\\font\\a=cmr10 \\noindent\\accent`~\\a\\count1=2 \\relax o\\/\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:begin :accent) (:text "~" :style "nullfont") (:text "o" :style "cmr10")
                 (:end :accent) (:kern :width "0.0pt" :italic t) (:end :paragraph)))
  ;; \char and \chardef characters; anything else is read again.
  (check-events "\\chardef\\c=`y \\noindent\\accent`'\\char`x\\accent`'\\c\\accent`'\\hbox{}\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:begin :accent) (:text "'" :style "nullfont") (:text "x" :style "nullfont")
                 (:end :accent)
                 (:begin :accent) (:text "'" :style "nullfont") (:text "y" :style "nullfont")
                 (:end :accent)
                 (:begin :accent) (:text "'" :style "nullfont") (:end :accent)
                 (:begin :box :kind :hbox :command "hbox") (:end :box) (:end :paragraph)))
  ;; \setbox is no assignment there (`Improper'); the space factor is
  ;; 1000.
  (check-events "\\sfcode`x=999 \\noindent x\\accent`^\\showthe\\spacefactor
\\accent`^\\setbox0\\hbox{}\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:text "x" :style "nullfont")
                 (:begin :accent) (:text "^" :style "nullfont") (:end :accent)
                 (:begin :accent) (:text "^" :style "nullfont") (:end :accent)
                 (:begin :box :kind :hbox :command "hbox") (:end :box) (:end :paragraph))
                :errors ("Improper")
                :log ((:show "1000")))
  (check-events "\\hbox{\\accent`^a}"
                ((:begin :box :kind :hbox :command "hbox")
                 (:begin :accent) (:text "^" :style "nullfont") (:text "a" :style "nullfont")
                 (:end :accent) (:end :box))))

;;; Inserts and \vadjust (§§1097-1100)

(define-test inserts
  :parent events
  ;; \insert255 is \insert0; the parameters are those inside the group.
  (check-events "\\floatingpenalty=9 \\insert255{a}\\insert100{\\splittopskip=3pt
\\splitmaxdepth=1pt\\floatingpenalty=7 \\noindent x\\par}"
                ((:begin :insert :number 0 :split-top-skip "0.0pt" :split-max-depth "0.0pt"
                  :floating-penalty 9)
                 (:begin :paragraph) (:indent) (:text "a" :style "nullfont") (:end :paragraph)
                 (:end :insert)
                 (:begin :insert :number 100 :split-top-skip "3.0pt"
                  :split-max-depth "1.0pt" :floating-penalty 7)
                 (:begin :paragraph) (:text "x" :style "nullfont") (:end :paragraph)
                 (:end :insert))
                :errors ("You can't \\insert255"))
  ;; normal_paragraph on entry, undone at the end of the group.
  (check-log "\\hangindent=5pt \\insert1{\\message{\\the\\hangindent}}\\message{\\the\\hangindent}"
             ((:message "0.0pt") (:message "5.0pt")))
  ;; In the outer vertical list the page builder runs: \unkern cannot
  ;; take anything, \unskip finds no glue on the page and is silent.
  (check-events "\\vskip1pt\\insert1{}\\unkern\\unskip"
                ((:glue :glue "1.0pt" :command "vskip")
                 (:begin :insert :number 1 :split-top-skip "0.0pt" :split-max-depth "0.0pt"
                  :floating-penalty 0)
                 (:end :insert))
                :errors ("You can't use")))

(define-test vadjusts
  :parent events
  (check-events "\\noindent a\\vadjust{\\mark{m}}\\par\\vadjust{}"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:text "a" :style "nullfont") (:begin :vadjust) (:tex-mark :tokens "m")
                 (:end :vadjust) (:end :paragraph))
                :errors ("You can't use"))
  ;; \vsplit's marks: those at the top of a \vadjust's list in a
  ;; paragraph or adjusted \hbox (§655), in order.
  (check-log "\\setbox1\\vbox{\\noindent a\\vadjust{\\mark{p}\\hbox{\\mark{q}}}\\mark{r}\\par
\\moveright0pt\\hbox{\\vadjust{\\mark{s}}}\\setbox3\\hbox{\\vadjust{\\mark{t}}}\\box3}%
\\setbox2\\vsplit1 to0pt \\message{\\splitfirstmark,\\splitbotmark}"
             ((:message "p,s")))
  ;; Math in a paragraph is part of its line.
  (check-log "\\setbox1\\vbox{\\noindent$\\mark{a}\\vadjust{\\mark{b}}$\\par}%
\\setbox2\\vsplit1 to0pt \\message{\\splitfirstmark,\\splitbotmark}"
             ((:message "a,b"))
             :errors ("Math formula deleted: Insufficient symbol fonts")))

;;; Whatsits (§§1354, 1377)

(define-test special-and-setlanguage
  :parent events
  ;; \special's text is expanded; \setlanguage clamps its number and
  ;; makes it the paragraph's language, which the next character's
  ;; \language then changes again (fix_language).
  (check-events "\\noindent\\special{a\\the\\count0}\\setlanguage300 \\setlanguage5 x\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:special :tokens "a0")
                 (:language :number 0 :left-hyphen-min 1 :right-hyphen-min 1)
                 (:language :number 5 :left-hyphen-min 1 :right-hyphen-min 1)
                 (:language :number 0 :left-hyphen-min 1 :right-hyphen-min 1)
                 (:text "x" :style "nullfont") (:end :paragraph)))
  (check-events "\\hbox{\\setlanguage2}\\setlanguage3"
                ((:begin :box :kind :hbox :command "hbox")
                 (:language :number 2 :left-hyphen-min 1 :right-hyphen-min 1) (:end :box)
                 (:glue :glue "0.0pt" :command "parskip") (:begin :paragraph) (:indent)
                 (:text "3" :style "nullfont") (:end :paragraph))
                :errors ("You can't use")))

;;; \shipout (§§638-640, 1366-1374)

(define-test shipout
  :parent events
  ;; The box goes to the outer list; its writes are carried out after
  ;; it, depth first, a \vadjust's after its paragraph or adjusted box,
  ;; not in leaders or inserts, under the state of the moment.
  (check-events "\\immediate\\openout1=f \\count1=3 \\hbox{\\shipout\\vbox{\\noindent
\\vadjust{\\write1{a}}\\write1{b\\the\\count1}\\par\\moveright0pt\\hbox{\\vadjust{\\write1{c}}%
\\write1{d}\\leaders\\hbox{\\write1{l}}\\hfil}\\insert1{\\write1{e}}}}\\count1=4"
                ((:openout :stream 1 :file "f" :immediate t)
                 (:begin :shipout) (:begin :box :kind :vbox :command "vbox")
                 (:begin :paragraph) (:begin :vadjust) (:write :stream 1 :tokens "a")
                 (:end :vadjust) (:write :stream 1 :tokens "b\\the \\count 1") (:end :paragraph)
                 (:begin :box :kind :hbox :command "hbox" :shift "0.0pt")
                 (:begin :vadjust) (:write :stream 1 :tokens "c") (:end :vadjust)
                 (:write :stream 1 :tokens "d")
                 (:begin :leaders :kind :leaders :glue "0.0pt plus 1.0fil" :command "hfil")
                 (:begin :box :kind :hbox :command "hbox") (:write :stream 1 :tokens "l")
                 (:end :box) (:end :leaders) (:end :box)
                 (:begin :insert :number 1 :split-top-skip "0.0pt" :split-max-depth "0.0pt"
                  :floating-penalty 0)
                 (:write :stream 1 :tokens "e") (:end :insert) (:end :box) (:end :shipout)
                 (:write :stream 1 :tokens "b3" :text "b3" :shipout t)
                 (:write :stream 1 :tokens "a" :text "a" :shipout t)
                 (:write :stream 1 :tokens "d" :text "d" :shipout t)
                 (:write :stream 1 :tokens "c" :text "c" :shipout t)
                 (:begin :box :kind :hbox :command "hbox") (:end :box)))
  ;; A plain \hbox keeps its \vadjust; a discretionary's no-break list is
  ;; carried out, its break lists not; a write to no open file is logged;
  ;; \openout and \closeout open and close.
  (check-events "\\shipout\\hbox{\\discretionary{\\hbox{\\write1{x}}}{}{\\hbox{\\write1{y}}}%
\\vadjust{\\write1{z}}\\openout2=g\\write2{w}\\closeout2\\write2{v}}\\shipout\\box3"
                ((:begin :shipout) (:begin :box :kind :hbox :command "hbox")
                 (:begin :discretionary :command "discretionary")
                 (:begin :pre-break) (:begin :box :kind :hbox :command "hbox")
                 (:write :stream 1 :tokens "x") (:end :box) (:end :pre-break)
                 (:begin :no-break) (:begin :box :kind :hbox :command "hbox")
                 (:write :stream 1 :tokens "y") (:end :box) (:end :no-break)
                 (:end :discretionary)
                 (:begin :vadjust) (:write :stream 1 :tokens "z") (:end :vadjust)
                 (:openout :stream 2 :file "g") (:write :stream 2 :tokens "w")
                 (:closeout :stream 2) (:write :stream 2 :tokens "v")
                 (:end :box) (:end :shipout)
                 (:openout :stream 2 :file "g" :shipout t)
                 (:write :stream 2 :tokens "w" :text "w" :shipout t)
                 (:closeout :stream 2 :shipout t))
                :log ((:write "y" 1) (:write "v" 2)))
  ;; Math in a paragraph is part of its line: its \vadjust comes after.
  (check-events "\\immediate\\openout1=f \\shipout\\vbox{\\noindent$\\vadjust{\\write1{q}}$\\write1{p}\\par}"
                ((:openout :stream 1 :file "f" :immediate t)
                 (:begin :shipout) (:begin :box :kind :vbox :command "vbox")
                 (:begin :paragraph) (:begin :math) (:begin :vadjust)
                 (:write :stream 1 :tokens "q") (:end :vadjust) (:end :math)
                 (:write :stream 1 :tokens "p") (:end :paragraph) (:end :box) (:end :shipout)
                 (:write :stream 1 :tokens "p" :text "p" :shipout t)
                 (:write :stream 1 :tokens "q" :text "q" :shipout t))
                :errors ("Math formula deleted: Insufficient symbol fonts"))
  ;; \deadcycles becomes 0; \tracingoutput shows the box; only a box will do.
  (check-events "\\tracingoutput=1 \\deadcycles=3 \\shipout\\hbox{a}\\message{\\the\\deadcycles}%
\\shipout\\vrule"
                ((:begin :shipout) (:begin :box :kind :hbox :command "hbox")
                 (:text "a" :style "nullfont") (:end :box) (:end :shipout)
                 (:glue :glue "0.0pt" :command "parskip") (:begin :paragraph) (:indent)
                 (:rule :kind :vrule :width "0.4pt" :height :running :depth :running)
                 (:end :paragraph))
                :errors ("A <box> was supposed to be here")
                :log ((:diagnostic "Completed box being shipped out
(:box :kind :hbox :command \"hbox\") []")
                      (:message "0"))))

;;; \showbox and \showlists (§§180-198, 218-219, 1293-1298)

(define-test show-box
  :parent events
  (check-log "\\showboxdepth=1 \\setbox1\\hbox{a\\hbox{b}c}\\showbox1 \\showbox2"
             ((:show "\\box1=
(:box :kind :hbox :command \"hbox\")
.(:text \"a\" :style \"nullfont\")
.(:box :kind :hbox :command \"hbox\") []
.(:text \"c\" :style \"nullfont\")")
              (:show "\\box2=void")))
  (check-log "\\showboxdepth=2 \\showboxbreadth=2 \\setbox1\\hbox to 3pt{a\\kern1pt\\hbox{b}}%
\\showbox1 \\showboxbreadth=-1 \\showboxdepth=-1 \\showbox1"
             ((:show "\\box1=
(:box :kind :hbox :command \"hbox\" :spec (:exactly \"3.0pt\"))
.(:text \"a\" :style \"nullfont\")
.(:kern :width \"1.0pt\")
.etc.")
              (:show "\\box1= []"))))

(define-test show-lists
  :parent events
  ;; Innermost list first, with the line it began on; of the outer list
  ;; only what is not on the page yet.
  (check-log "\\vskip1pt\\penalty0 \\vskip2pt\\lefthyphenmin=2 \\righthyphenmin=3
\\noindent a\\hbox{b\\showlists}\\par\\vbox{\\noindent\\par\\showlists}"
             ((:show "### restricted horizontal mode entered at line 2
(:text \"b\" :style \"nullfont\")
spacefactor 1000
### horizontal mode entered at line 2
(:text \"a\" :style \"nullfont\")
spacefactor 1000
### vertical mode entered at line 0
### recent contributions:
(:glue :glue \"2.0pt\" :command \"vskip\")
(:glue :glue \"0.0pt\" :command \"parskip\")
prevdepth ignored")
              (:show "### internal vertical mode entered at line 2
prevdepth ignored
### vertical mode entered at line 0
prevdepth 0.0pt, prevgraf 1 line")))
  (check-log "\\lefthyphenmin=4 \\language=7 \\noindent\\showlists"
             ((:show "### horizontal mode entered at line 1 (language7:hyphenmin4,1)
spacefactor 1000, current language 7
### vertical mode entered at line 0
### recent contributions:
(:glue :glue \"0.0pt\" :command \"parskip\")
prevdepth ignored"))))
