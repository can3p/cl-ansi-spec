;;;; tests/expand/main-control.lisp
;;;;
;;;; Main control (src/expand/commands.lisp, groups.lisp, modes.lisp,
;;;; boxes.lisp, main-control.lisp): the disposition of every primitive,
;;;; groups and \aftergroup, modes and their errors, boxes, math shifts,
;;;; and the end of a job (TeX: The Program, §§1029-1200, 1335).  A job's
;;;; output is what main control hands on (events and alignments).

(in-package #:cl-ansi-spec/tests)

(define-test main-control
  :parent cl-ansi-spec
  :description "Main control: dispositions, groups, modes, boxes, math.")

(defun token-display (token)
  "TOKEN as EXPANSION-OF shows it."
  (if (character-token-p token)
      (string (code-char (character-token-code token)))
      (format nil "\\~A " (control-sequence-name (cs-token-control-sequence token)))))

(defun run-job (expander &optional reports)
  "With REPORTS a function, it is called on every TEX-REPORT."
  (handler-bind ((expand:tex-report (lambda (condition)
                                      (when reports (funcall reports condition)))))
    (run-main-control expander)))

(defun run-main-control (expander)
  "Run EXPANDER's job with main control, recovering from TeX errors.
Returns the characters, spaces, boxes ([hbox] ...) and the math characters
of noads appended to lists,
with the handed-on commands, as a string, the error messages, their contexts, the modes of
the handed-on commands, and the message of a fatal error or NIL."
  (let ((errors '()) (contexts '()) (modes '()) (fatal nil))
    (let ((output
            (with-output-to-string (out)
              (handler-case
                  (handler-bind ((expand:unhandled-command
                                   (lambda (condition)
                                     (write-string (token-display
                                                    (expand:unhandled-command-token condition))
                                                   out)
                                     (push (expand:unhandled-command-mode condition) modes)))
                                 (expand:job-output
                                   (lambda (condition)
                                     (let ((node (expand:job-output-item condition)))
                                       (when (expand:node-p node)
                                         (case (expand:node-kind node)
                                           (:text (let ((text (expand:node-value node)))
                                                    (write-char (char text (1- (length text)))
                                                                out)))
                                           (:space (write-char #\Space out))
                                           (:noad (let* ((nucleus (first (expand:node-children node)))
                                                         (char (and nucleus
                                                                    (first (expand:node-children nucleus)))))
                                                    (when (and char (eq (expand:node-kind char) :math-char))
                                                      (write-char (code-char (getf (expand:node-properties char) :code))
                                                                  out))))
                                           (:box (format out "[~A]"
                                                         (getf (expand:node-properties node)
                                                               :command)))))))))
                    (expand:call-recovering-tex-errors
                     (lambda () (expand:main-control expander))
                     (lambda (condition)
                       (push (expand:tex-error-message condition) errors)
                       (push (expand:tex-error-context condition) contexts))))
                (expand:tex-fatal-error (condition)
                  (setf fatal (expand:tex-error-message condition)))))))
      (values output (reverse errors) (reverse contexts) (reverse modes) fatal))))

(defmacro check-job (text expected &key setup (errors '()) contexts modes
                                     (fatal nil fatal-p))
  "Run TEXT (ended by \\end unless FATAL is given) after SETUP (forms run
with EXPANDER bound), and check the output, the error messages and, if
given, their CONTEXTS, the MODES of the handed-on commands and the
FATAL message."
  `(let ((expander (make-test-expander ,(if fatal-p text `(concatenate 'string ,text "\\end")))))
     (declare (ignorable expander))
     ,@setup
     (multiple-value-bind (output messages error-contexts command-modes fatal-message)
         (run-job expander)
       (declare (ignorable error-contexts command-modes))
       (is string= ,expected output "output of ~S" ,text)
       (is equal ',errors messages "errors of ~S" ,text)
       ,@(when contexts `((is equal ',contexts error-contexts "contexts of ~S" ,text)))
       ,@(when modes `((is equal ',modes command-modes "modes of ~S" ,text)))
       (is equal ,(if fatal-p fatal nil) fatal-message "fatal error of ~S" ,text))))

(defun job-state (text)
  "Run TEXT\\end; return the expander, for its state."
  (let ((expander (make-test-expander (concatenate 'string text "\\end"))))
    (run-job expander)
    expander))

(defparameter *math-fonts*
  "\\font\\f=cmr10 \\textfont2=\\f \\scriptfont2=\\f \\scriptscriptfont2=\\f
\\textfont3=\\f \\scriptfont3=\\f \\scriptscriptfont3=\\f "
  "Families 2 and 3 with fonts of unknown parameter count, so that math
needs no fonts' metrics.")

(defun with-math-fonts (text)
  (concatenate 'string *math-fonts* text))

;;; Dispositions

(defparameter *pending-event-commands*
  '()
  "The :EVENT primitives whose operations have not landed: they are still
handed on.")

(define-test dispositions
  :parent main-control
  (let ((names (append (expand:tex82-command-names) (expand:tex82-expandable-names)
                       (loop for kind in '(:integer :dimen :glue :muglue :tokens)
                             append (mapcar (lambda (name)
                                              (string-downcase (symbol-name name)))
                                            (expand:parameter-names kind))))))
    (dolist (name names)
      (let ((disposition (expand:command-disposition name))
            (operation (expand:primitive-operation (expand:find-primitive name))))
        (true disposition "~S has a disposition" name)
        (when (eq disposition :main-control)
          (true operation "~S has an operation" name))
        (when (eq disposition :alignment)
          (false operation "~S is handed on" name))
        (when (eq disposition :event)
          (if (member name *pending-event-commands* :test #'string=)
              (false operation "~S is handed on" name)
              (true operation "~S has an operation" name))))))
  (dolist (name (expand:input-output-command-names))
    (is eq :main-control (expand:command-disposition name)))
  (is eq :event (expand:command-disposition "hskip"))
  (is eq :alignment (expand:command-disposition "halign"))
  (is eq :main-control (expand:command-disposition "def"))
  (is eq :main-control (expand:command-disposition "tolerance"))
  (is eq :expandable (expand:command-disposition "ifx"))
  (is eq nil (expand:command-disposition "frob")))

(define-test handed-on-commands
  :parent main-control
  (check-job "\\halign" "\\halign ")
  (check-job "a&" "a&" :modes (:horizontal))
  (check-job "\\relax  " ""))

;;; Groups

(define-test groups-and-aftergroup
  :parent main-control
  (let* ((expander (job-state "\\count1=5 {\\count1=7 \\global\\count2=3 }"))
         (state (expand:expander-state expander)))
    (is = 5 (expand:register state :count 1))
    (is = 3 (expand:register state :count 2)))
  (let ((state (expand:expander-state
                (job-state "\\begingroup\\count1=3 \\endgroup"))))
    (is = 0 (expand:register state :count 1)))
  (check-job "{\\aftergroup a\\aftergroup b}" "ab")
  (check-job "{\\aftergroup a{\\aftergroup b}c}" "bca")
  (check-job "\\aftergroup a" "")
  (check-job "\\begingroup}\\endgroup" "" :errors ("Extra }, or forgotten")
                                         :contexts ("\\endgroup"))
  (check-job "{\\endgroup}" "" :errors ("Missing } inserted" "Extra" "Too many }'s"))
  (check-job "\\begingroup{\\endgroup" "" :errors ("Missing } inserted"))
  (check-job "}" "" :errors ("Too many }'s"))
  (check-job "\\endgroup" "" :errors ("Extra") :contexts ("\\endgroup"))
  (check-job "\\endcsname" "" :errors ("Extra") :contexts ("\\endcsname")))

(define-test end-of-job
  :parent main-control
  (flet ((reports (text)
           (let ((reports '()))
             (run-job (make-test-expander text)
                      (lambda (condition)
                        (push (list (expand:tex-report-message condition)
                                    (expand:tex-report-context condition))
                              reports)))
             (reverse reports))))
    (is equal '(("\\end occurred" "inside a group at level 1")) (reports "{\\end"))
    (is equal '(("\\end occurred" "when \\iftrue on line 1 was incomplete"))
        (reports "\\iftrue\\end")))
  (check-job "{\\iftrue" "")
  (check-job "x" "x" :fatal "*** (job aborted, no legal \\end found)")
  (check-job "\\vbox{\\end}" "[vbox]" :errors ("You can't use")
                                     :contexts ("`\\end' in internal vertical mode"))
  ;; \end in a paragraph ends it first.
  (let ((expander (job-state "x")))
    (is eq :end (expand:expander-ended expander))
    (is eq :vertical (expand:list-state-mode (expand:current-list expander))))
  (let ((expander (make-test-expander "\\dump")))
    (run-job expander)
    (is eq :dump (expand:expander-ended expander))
    (false (expand:expander-trie-not-ready expander)))
  (check-job "{\\dump" "" :fatal "You can't dump inside a group"))

;;; Modes

(define-test paragraphs
  :parent main-control
  (check-job "\\everypar{p}x\\par y" "pxpy")
  (check-job "\\noindent\\par\\ifnum\\prevgraf=0 y\\fi" "y")
  (check-job "\\indent\\par\\ifnum\\prevgraf=1 y\\fi" "y")
  (check-job "\\ifvmode\\noindent\\ifhmode\\ifinner\\else y\\fi\\fi\\fi" "y")
  (check-job "x\\indent\\noindent" "x")
  ;; normal_paragraph
  (let ((state (expand:expander-state
                (job-state "\\hangindent=3pt \\looseness=2 \\hangafter=5
\\parshape 1 1pt 2pt \\indent\\par"))))
    (is = 0 (expand:parameter state :hangindent))
    (is = 0 (expand:parameter state :looseness))
    (is = 1 (expand:parameter state :hangafter))
    (is eq nil (expand:par-shape state)))
  ;; A vertical command ends the paragraph; \par is inserted.
  (check-job "x\\vskip1pt\\ifvmode v\\fi" "xv")
  (check-job "x\\hrule\\ifvmode v\\fi" "xv")
  ;; A paragraph starts before \hskip; \end ends it.
  (check-job "\\hskip 3pt\\ifhmode h\\fi" "h"))

(define-test mode-errors
  :parent main-control
  (check-job "\\raise" "" :errors ("You can't use")
                          :contexts ("`\\raise' in vertical mode"))
  (check-job "#" "" :errors ("You can't use")
                    :contexts ("`macro parameter character #' in vertical mode"))
  (check-job "\\lastskip" "" :errors ("You can't use"))
  (check-job "x\\moveleft" "x" :errors ("You can't use")
                               :contexts ("`\\moveleft' in horizontal mode"))
  (check-job "\\hbox{\\hrule}" "[hbox]" :errors ("You can't use")
                                       :contexts ("`\\hrule' here except with leaders"))
  (check-job "\\hbox{\\vskip1pt}\\ifvmode v\\fi" "[hbox]v"
             :errors ("Missing } inserted" "Too many }'s"))
  (check-job "\\eqno" "" :errors ("You can't use"))
  (check-job (with-math-fonts "$\\eqno$") "" :errors ("You can't use")
             :contexts ("`\\eqno' in math mode"))
  (check-job (with-math-fonts "$$\\eqno$$") ""))

;;; Boxes

(define-test boxes
  :parent main-control
  (check-job "\\hbox{\\ifinner i\\fi}" "i[hbox]")
  (check-job "\\vbox{x\\ifhmode y\\fi}" "xy[vbox]")
  (check-job "\\everyhbox{h}\\everyvbox{v}\\hbox{}\\vtop{}" "h[hbox]v[vtop]")
  (check-job "\\setbox1\\hbox{}\\ifhbox1 h\\fi\\setbox2\\vtop{}\\ifvbox2 v\\fi
\\setbox3\\box1 \\ifvoid1 e\\fi\\ifhbox3 m\\fi" "hvem")
  (check-job "{\\setbox1\\hbox{}}\\ifvoid1 y\\fi" "y")
  (check-job "{\\global\\setbox1\\hbox{}}\\ifhbox1 y\\fi" "y")
  (check-job "\\setbox1\\hbox{}\\setbox2\\copy1 \\ifhbox1 a\\fi\\ifhbox2 b\\fi" "ab")
  (check-job "\\setbox1\\hbox{}\\wd1=5pt \\ifdim\\wd1=5pt y\\fi" "y")
  (check-job "\\wd1=5pt \\ifdim\\wd1=0pt y\\fi" "y")
  (check-job "\\setbox1\\vbox{}\\setbox2\\vsplit1 to 3pt \\ifvoid1 a\\fi\\ifvbox2 b\\fi" "ab")
  (check-job "\\setbox1\\hbox{}\\setbox2\\vsplit1 to 3pt\\ifhbox1 a\\fi\\ifvoid2 b\\fi" "ab"
             :errors ("\\vsplit needs a \\vbox"))
  (check-job "\\setbox1=x" "x" :errors ("A <box> was supposed to be here"))
  (check-job "\\setbox1\\hbox{}\\box1 \\box1 " "[hbox]")
  (check-job "\\lastbox" "" :errors ("You can't use"))
  (check-job "\\setbox1\\vbox{}\\setbox2\\vsplit1 3pt" "" :errors ("Missing `to' inserted"))
  ;; Placing a box sets the list's space factor and depth (§§1076, 679).
  (check-job "x\\spacefactor=3 \\hbox{}\\ifnum\\spacefactor=1000 y\\fi" "x[hbox]y")
  (check-job "\\setbox1\\hbox{}\\dp1=2pt \\box1 \\ifdim\\prevdepth=2pt y\\fi" "[hbox]y")
  (check-job "x\\spacefactor=3 \\indent\\ifnum\\spacefactor=1000 y\\fi" "xy")
  ;; \afterassignment's token comes before \everyhbox (§1279).
  (check-job "\\everyhbox{b}\\def\\a{a}\\afterassignment\\a\\setbox0\\hbox{c}" "abc")
  (let ((box (expand:register (expand:expander-state
                               (job-state "\\setbox3\\hbox to 5pt{}"))
                              :box 3)))
    (is eq :hbox (expand:tex-box-kind box))
    (is equal (list :exactly (* 5 65536)) (expand:tex-box-spec box))))

;;; Math

(define-test math-shifts
  :parent main-control
  (check-job (with-math-fonts "a$b$$$c$$\\par d") "abcd")
  (check-job (with-math-fonts "$$x$$\\par\\ifnum\\prevgraf=4 y\\fi") "xy")
  (check-job (with-math-fonts "$$x$y") "xy" :errors ("Display math should end with $$"))
  (check-job (with-math-fonts "\\noindent$$\\ifdim\\predisplaysize<-16000pt y\\fi$$") "y")
  (check-job (with-math-fonts "\\hsize=100pt \\hangindent=10pt \\hangafter=0
\\noindent$$\\ifdim\\displaywidth=90pt w\\fi\\ifdim\\displayindent=10pt i\\fi$$")
             "wi")
  (check-job (with-math-fonts "$\\ifinner a\\fi{\\ifinner b\\fi}$") "ab")
  (check-job (with-math-fonts "$$\\ifinner\\else a\\fi{\\ifinner b\\fi}$$") "ab")
  (check-job (with-math-fonts "\\everymath{m}\\everydisplay{d}$x$$$y$$") "mxdy")
  ;; $$ in restricted horizontal mode is an empty formula.
  (check-job (with-math-fonts "\\hbox{$$x$$}") "x[hbox]")
  (check-job (with-math-fonts "\\fam=3 $\\ifnum\\fam=-1 y\\fi$\\ifnum\\fam=3 z\\fi") "yz")
  ;; `^' then \end: no nucleus, so a subformula is begun (§1151).
  (check-job (with-math-fonts "^") ""
             :errors ("Missing $ inserted" "Missing { inserted" "Missing $ inserted"
                      "Missing } inserted"))
  (check-job (with-math-fonts "$\\par$") "" :errors ("Missing $ inserted" "Missing $ inserted"))
  (check-job (with-math-fonts "$}$") "" :errors ("Extra }, or forgotten"))
  (check-job (with-math-fonts "$\\begingroup$") "" :errors ("Missing \\endgroup inserted"))
  (check-job "$x$" "x" :errors ("Math formula deleted: Insufficient symbol fonts")))
