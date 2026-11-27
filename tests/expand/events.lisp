;;;; tests/expand/events.lisp
;;;;
;;;; The nodes main control appends and the job's events
;;;; (src/expand/nodes.lisp, list-commands.lisp; docs/events.md):
;;;; characters and text runs, spaces, paragraphs, glue, kerns, penalties,
;;;; rules, the italic correction and the removal of the last node.

(in-package #:cl-ansi-spec/tests)

(define-test events
  :parent cl-ansi-spec
  :description "The nodes of lists and the job's events.")

(defun strip-event (expander event)
  "EVENT without its :SPAN and :VIA, its token lists shown as text."
  (let ((head (if (member (first event) '(:begin :end :text)) 2 1)))
    (append (subseq event 0 head)
            (loop for (key value) on (nthcdr head event) by #'cddr
                  unless (member key '(:span :via))
                    append (list key (if (eq key :tokens)
                                         (expand:token-list-text expander value)
                                         value))))))

(defmacro check-events (text events &key (errors '()) (log nil log-p))
  "Run TEXT\\end and check the job's EVENTS (as EVENTS-OF shows them), its
ERRORS and, when given, its LOG (as LOG-OF shows it)."
  `(let ((expander (make-test-expander (concatenate 'string ,text "\\end"))))
     (multiple-value-bind (output messages) (run-job expander)
       (declare (ignore output))
       (is equal ',events (mapcar (lambda (event) (strip-event expander event))
                                   (expand:job-events expander))
           "events of ~S" ,text)
       (is equal ',errors messages "errors of ~S" ,text)
       ,@(when log-p `((is equal ',log (log-of expander) "log of ~S" ,text))))))

(defparameter *parskip* '(:glue :glue "0.0pt" :command "parskip")
  "The \\parskip glue before a paragraph, at its INITEX value.")

;;; Text

(define-test text-runs
  :parent events
  (check-events "ab c\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph) (:indent)
                 (:text "ab" :style "nullfont") (:space) (:text "c" :style "nullfont")
                 (:end :paragraph)))
  ;; A font change; a macro body read earlier in the file starts a new
  ;; run, which \char and \chardef characters read later extend.
  (check-events "\\font\\a=cmr10 \\noindent x\\a y\\nullfont z\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:text "x" :style "nullfont") (:text "y" :style "cmr10")
                 (:text "z" :style "nullfont") (:end :paragraph)))
  (check-events "\\def\\m{yz}\\noindent x\\m\\char`w\\chardef\\c=`v\\c\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:text "x" :style "nullfont") (:text "yzwv" :style "nullfont")
                 (:end :paragraph)))
  (check-events "\\font\\a=cmr10 at 12pt \\font\\b=cmr10 scaled 1200 \\noindent\\a x\\b y\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:text "x" :style "cmr10 at 12.0pt") (:text "y" :style "cmr10 scaled 1200")
                 (:end :paragraph)))
  ;; A \let character and \noboundary.
  (check-events "\\let\\a=b\\noindent\\a\\noboundary c\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:text "bc" :style "nullfont") (:end :paragraph)))
  ;; The language of a paragraph's characters (§§1034, 1376): only in
  ;; unrestricted horizontal mode.
  (check-events "\\noindent a\\language=3 b\\hbox{c}d\\language=300 e\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:text "a" :style "nullfont")
                 (:language :number 3 :left-hyphen-min 1 :right-hyphen-min 1)
                 (:text "b" :style "nullfont")
                 (:begin :box :kind :hbox :command "hbox") (:text "c" :style "nullfont")
                 (:end :box)
                 (:text "d" :style "nullfont")
                 (:language :number 0 :left-hyphen-min 1 :right-hyphen-min 1)
                 (:text "e" :style "nullfont") (:end :paragraph)))
  (check-events "\\language=2 \\lefthyphenmin=2 \\noindent a\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:text "a" :style "nullfont") (:end :paragraph))))

(define-test space-factor
  :parent events
  (check-job "\\noindent\\sfcode`a=999 a\\ifnum\\spacefactor=999 y\\fi" "ay")
  (check-job "\\noindent\\sfcode`a=0 \\spacefactor=5 a\\ifnum\\spacefactor=5 y\\fi" "ay")
  (check-job "\\noindent\\sfcode`a=3000 \\spacefactor=999 a\\ifnum\\spacefactor=1000 y\\fi" "ay")
  (check-job "\\noindent\\sfcode`a=3000 \\spacefactor=1000 a\\ifnum\\spacefactor=3000 y\\fi" "ay"))

;;; Spaces (§§1041-1044)

(defparameter *space-font*
  "\\font\\f=cmr10 \\f \\fontdimen2\\f=3pt \\fontdimen3\\f=1pt \\fontdimen4\\f=1pt
\\fontdimen7\\f=2pt \\sfcode`\\.=3000 \\sfcode`\\,=1500 \\noindent "
  "A font with interword glue 3pt plus 1pt minus 1pt and extra space 2pt.")

(defmacro check-space (text glue)
  "Check that the space ending *SPACE-FONT* and TEXT has GLUE."
  `(check-log (concatenate 'string *space-font* ,text "\\message{\\the\\lastskip}")
              ((:message ,glue))))

(define-test spaces
  :parent events
  (check-space "a " "3.0pt plus 1.0pt minus 1.0pt")
  (check-space "a, " "3.0pt plus 1.5pt minus 0.66666pt")
  (check-space "a. " "5.0pt plus 3.0pt minus 0.33333pt")
  (check-space "a.\\ " "3.0pt plus 1.0pt minus 1.0pt")
  (check-space "\\spaceskip=4pt plus 2pt a, " "4.0pt plus 3.0pt")
  (check-space "\\spaceskip=4pt plus 2pt a " "4.0pt plus 2.0pt")
  (check-space "\\xspaceskip=6pt a. " "6.0pt")
  (check-space "\\xspaceskip=6pt a, " "3.0pt plus 1.5pt minus 0.66666pt")
  (check-space "\\spaceskip=0pt plus 0fil a " "3.0pt plus 1.0pt minus 1.0pt")
  (check-space "\\spaceskip=4pt a\\ " "4.0pt")
  ;; Spaces are skipped in vertical mode; \  begins a paragraph.
  (check-events "  \\ x\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph) (:indent)
                 (:space) (:text "x" :style "nullfont") (:end :paragraph))))

;;; Paragraphs (§§816, 1091-1096)

(define-test paragraph-nodes
  :parent events
  (check-events "\\noindent\\par" ((:glue :glue "0.0pt" :command "parskip")))
  (check-events "\\indent\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph) (:indent)
                 (:end :paragraph)))
  ;; The final glue goes; \parskip comes before every paragraph of the
  ;; outer list and after the first of a box.
  (check-events "\\parskip=1pt\\noindent a\\hskip 2pt\\hskip 3pt\\par\\vbox{\\noindent b \\par}"
                ((:glue :glue "1.0pt" :command "parskip") (:begin :paragraph)
                 (:text "a" :style "nullfont") (:glue :glue "2.0pt" :command "hskip")
                 (:end :paragraph)
                 (:begin :box :kind :vbox :command "vbox") (:begin :paragraph)
                 (:text "b" :style "nullfont") (:end :paragraph) (:end :box)))
  (check-events "\\vbox{\\noindent a\\par\\noindent b\\par}"
                ((:begin :box :kind :vbox :command "vbox") (:begin :paragraph)
                 (:text "a" :style "nullfont") (:end :paragraph)
                 (:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:text "b" :style "nullfont") (:end :paragraph) (:end :box)))
  ;; \end ends the paragraph; \indent inside one is an indentation node.
  (check-events "\\noindent a\\indent"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:text "a" :style "nullfont") (:indent) (:end :paragraph)))
  ;; A display ends the paragraph before it; another one follows.
  (check-events (with-math-fonts "\\noindent a$$ $$ b\\par")
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:text "a" :style "nullfont") (:end :paragraph)
                 (:begin :math :display t) (:end :math)
                 (:begin :paragraph) (:text "b" :style "nullfont") (:end :paragraph)))
  (check-events (with-math-fonts "\\noindent a$\\hskip1pt$b\\par")
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:text "a" :style "nullfont")
                 (:begin :math) (:glue :glue "1.0pt" :command "hskip") (:end :math)
                 (:text "b" :style "nullfont") (:end :paragraph))))

;;; Glue, kerns, penalties and rules

(define-test glue-kerns-penalties
  :parent events
  (check-events "\\vskip 1pt plus 2fil\\vfil\\vfill\\vss\\vfilneg\\kern-3pt\\penalty-5"
                ((:glue :glue "1.0pt plus 2.0fil" :command "vskip")
                 (:glue :glue "0.0pt plus 1.0fil" :command "vfil")
                 (:glue :glue "0.0pt plus 1.0fill" :command "vfill")
                 (:glue :glue "0.0pt plus 1.0fil minus 1.0fil" :command "vss")
                 (:glue :glue "0.0pt plus -1.0fil" :command "vfilneg")
                 (:kern :width "-3.0pt") (:penalty :value -5)))
  (check-events "\\noindent\\hskip1pt\\hfil\\hfill\\hss\\hfilneg x\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:glue :glue "1.0pt" :command "hskip")
                 (:glue :glue "0.0pt plus 1.0fil" :command "hfil")
                 (:glue :glue "0.0pt plus 1.0fill" :command "hfill")
                 (:glue :glue "0.0pt plus 1.0fil minus 1.0fil" :command "hss")
                 (:glue :glue "0.0pt plus -1.0fil" :command "hfilneg")
                 (:text "x" :style "nullfont") (:end :paragraph)))
  ;; What \lastskip, \lastkern and \lastpenalty see (§424).
  (check-log "\\vskip 2pt\\message{\\the\\lastskip,\\the\\lastkern}\\kern 3pt
\\message{\\the\\lastkern,\\the\\lastskip}\\penalty 7 \\message{\\the\\lastpenalty}
\\noindent a\\message{\\the\\lastskip}"
             ((:message "2.0pt,0.0pt") (:message "3.0pt,0.0pt") (:message "7")
              (:message "0.0pt"))))

(define-test rules
  :parent events
  (check-events "\\hrule\\hrule width 2pt depth 1pt height 3pt depth 4pt"
                ((:rule :kind :hrule :width :running :height "0.4pt" :depth "0.0pt")
                 (:rule :kind :hrule :width "2.0pt" :height "3.0pt" :depth "4.0pt")))
  (check-events "\\noindent\\vrule\\vrule height 1pt x\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:rule :kind :vrule :width "0.4pt" :height :running :depth :running)
                 (:rule :kind :vrule :width "0.4pt" :height "1.0pt" :depth :running)
                 (:text "x" :style "nullfont") (:end :paragraph)))
  ;; After a rule: \prevdepth is ignore_depth, \spacefactor 1000 (§1056).
  (check-job "\\prevdepth=3pt\\hrule\\relax\\ifdim\\prevdepth=-1000pt y\\fi" "y")
  (check-job "x\\spacefactor=3 \\vrule\\relax\\ifnum\\spacefactor=1000 y\\fi" "xy"))

(define-test italic-correction
  :parent events
  (check-events "\\noindent a\\/ \\/\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:text "a" :style "nullfont") (:kern :width "0.0pt" :italic t)
                 (:end :paragraph)))
  (check-job "\\/" "" :errors ("You can't use")))

;;; Removing the last node (§1105)

(define-test removing-nodes
  :parent events
  (check-events "\\noindent a \\unskip\\kern1pt\\unkern\\penalty1\\unpenalty\\unskip\\par"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:text "a" :style "nullfont") (:end :paragraph)))
  ;; Only a node of the command's kind goes.
  (check-events "\\kern1pt\\unskip\\unpenalty"
                ((:kern :width "1.0pt")))
  ;; From an empty outer vertical list nothing can be taken.
  (check-events "\\unskip" ())
  (check-events "\\unkern\\unpenalty" () :errors ("You can't use" "You can't use")))

;;; Whatsits in lists

(define-test whatsits-in-lists
  :parent events
  (check-events "\\setbox0\\hbox{\\write1{x}}" ())
  (check-events "\\hbox{\\write1{x}\\immediate\\openout2=f }"
                ((:openout :stream 2 :file "f" :immediate t)
                 (:begin :box :kind :hbox :command "hbox") (:write :stream 1 :tokens "x")
                 (:end :box))))

;;; The page builder's traces (§§994-996)

(define-test build-page
  :parent events
  ;; After a paragraph, a box or a penalty in the outer vertical list
  ;; TeX's contributions are on the page: nothing can be taken, and
  ;; \lastskip and friends read the page's last node.
  (check-events "\\noindent a\\par\\unkern"
                ((:glue :glue "0.0pt" :command "parskip") (:begin :paragraph)
                 (:text "a" :style "nullfont") (:end :paragraph))
                :errors ("You can't use"))
  (check-events "\\vskip1pt\\penalty5 \\unpenalty\\unskip"
                ((:glue :glue "1.0pt" :command "vskip") (:penalty :value 5))
                :errors ("You can't use"))
  (check-log "\\vskip1pt\\penalty5 \\message{\\the\\lastpenalty}\\vskip2pt
\\message{\\the\\lastskip}\\unskip\\message{\\the\\lastpenalty}"
             ((:message "5") (:message "2.0pt") (:message "5")))
  ;; Inside a box the list is the box's own.
  (check-events "\\vbox{\\penalty5 \\unpenalty}"
                ((:begin :box :kind :vbox :command "vbox") (:end :box))))
