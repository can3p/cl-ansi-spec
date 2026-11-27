;;;; tests/expand/format.lisp
;;;;
;;;; Formats and jobs (src/expand/format.lisp; docs/tex-fidelity.md,
;;;; "Jobs"): plain TeX's format loads clean and equals a fresh run, jobs
;;;; from one format are isolated, \everyjob, and source lines on plain's
;;;; own macros.

(in-package #:cl-ansi-spec/tests)

(define-test formats
  :parent cl-ansi-spec
  :description "Plain TeX's format and the jobs started from it.")

(defvar *plain-format* nil
  "Plain TeX's format, loaded once per test run by PLAIN-FORMAT.")

(defun plain-format ()
  (or *plain-format* (setf *plain-format* (expand:load-plain-format))))

(defun make-format-job (text &key (format (plain-format)) (job-name "main"))
  "A job from FORMAT (plain TeX's by default) whose file is TEXT."
  (expand:start-job (expand:make-job format :job-name job-name
                                            :resolver (alist-resolver
                                                       (list (cons "main" text))))
                    "main"))

(defun messages-of (expander)
  "The texts of EXPANDER's \\message log entries, oldest first."
  (loop for (kind text) in (log-of expander)
        when (eq kind :message) collect text))

(defun fallback-resolver (files)
  "A resolver serving FILES (an alist of (name . text)), then the source
search path."
  (let ((alist (alist-resolver files))
        (path (apply #'directory-resolver (source-search-path))))
    (lambda (name) (or (funcall alist name) (funcall path name)))))

;;; Loading

(defparameter *format-probes*
  "\\message{\\meaning\\bigl|\\meaning\\quad|\\meaning\\newcount|\\fmtname}%
\\message{\\the\\mathcode`\\x|\\the\\mathcode`\\a|\\the\\delcode`\\(|\\the\\catcode`\\@}%
\\message{\\the\\count10|\\the\\count20|\\the\\baselineskip|\\the\\parindent}%
\\message{\\the\\hyphenchar\\tentt|\\the\\skewchar\\teni|\\fontname\\tenrm|\\the\\textfont1}%
\\message{\\meaning\\strutbox|\\the\\everypar|\\the\\lccode`\\A}%
\\end"
  "Probes of what plain.tex defines and assigns, as \\message texts.")

(define-test format-equals-a-fresh-run
  :parent formats
  ;; A job from the format sees what an INITEX job sees after \input plain.
  (let ((job (make-format-job *format-probes*))
        (fresh (expand:make-expander
                :job-name "main"
                :resolver (fallback-resolver
                           (list (cons "main" (concatenate 'string "\\input plain "
                                                           *format-probes*)))))))
    (push-file (expand:expander-input fresh) "main")
    (run-job job)
    (run-job fresh)
    (let ((messages (messages-of job)))
      (is = 5 (length messages))
      (is equal (last (messages-of fresh) 5) messages)
      (is string= "plain" (subseq (first messages) (1+ (position #\| (first messages)
                                                                 :from-end t)))))))

(defparameter *braces* "\\catcode`\\{=1 \\catcode`\\}=2 "
  "Braces for fixture formats, which INITEX reads.")

(defun meaning-texts (expander names)
  "\\meaning of each control sequence of NAMES in EXPANDER's job."
  (let ((state (expand:expander-state expander)))
    (mapcar (lambda (name)
              (let ((cs (intern-control-sequence (expand:es-tex state) name)))
                (expand:meaning-text expander (make-cs-token cs)
                                     (expand:meaning state cs))))
            names)))

(define-test format-state-equals-a-fresh-run
  :parent formats
  ;; Every control sequence plain.tex interned has the same meaning in a
  ;; job and after a fresh \input plain; so has every \count register.
  (let ((job (make-format-job ""))
        (fresh (expand:make-expander
                :job-name "main"
                :resolver (fallback-resolver '(("main" . "\\input plain \\end"))))))
    (push-file (expand:expander-input fresh) "main")
    (run-job fresh)
    (let* ((job-state (expand:expander-state job))
           (fresh-state (expand:expander-state fresh))
           (names (interned-names (expand:es-tex job-state))))
      (true (< 900 (length names)))
      (is equal (meaning-texts fresh names) (meaning-texts job names))
      (is equal (loop for n below 256 collect (expand:register fresh-state :count n))
          (loop for n below 256 collect (expand:register job-state :count n))))))

(define-test format-errors
  :parent formats
  (flet ((loads (text)
           (handler-case
               (progn (expand:load-plain-format
                       :resolver (alist-resolver
                                  (list (cons "plain" (concatenate 'string *braces*
                                                                   text)))))
                      t)
             (expand:format-error () nil))))
    (true (loads "\\def\\x{}"))
    (false (loads "\\undefined"))            ; a TeX error
    (false (loads "\\begingroup"))           ; \dump inside a group: fatal
    (false (loads "\\iftrue"))               ; final_cleanup's note
    (false (loads "\\end"))))                ; not dumped

(define-test everyjob
  :parent formats
  (let ((format (expand:load-plain-format
                 :resolver (alist-resolver
                            (list (cons "plain"
                                        (concatenate 'string *braces*
                                                     "\\everyjob{\\message{job \\jobname}}")))))))
    (dolist (name '("first" "second"))
      (let ((job (make-format-job "\\message{file}\\end" :format format
                                                         :job-name name)))
        (run-job job)
        (is equal (list (format nil "job ~A" name) "file") (messages-of job))))))

;;; Isolation

(defun strutbox-contents (expander)
  "The kinds of the nodes in EXPANDER's \\strutbox register."
  (let* ((state (expand:expander-state expander))
         (n (expand:shorthand-value
             (expand:meaning state (intern-control-sequence (expand:es-tex state)
                                                            "strutbox")))))
    (mapcar #'expand:node-kind
            (expand:tex-box-contents (expand:register state :box n)))))

(define-test jobs-are-isolated
  :parent formats
  (let ((probe "\\message{\\meaning\\fmtname|\\the\\catcode`\\@|\\the\\hyphenchar\\tentt|\\the\\count20|\\the\\fontdimen1\\tenrm}\\end"))
    (flet ((probe ()
             (let ((job (make-format-job probe)))
               (run-job job)
               (values (first (messages-of job)) (strutbox-contents job)))))
      (multiple-value-bind (before before-box) (probe)
        (is string= "macro:->plain|12|45|253|0.0pt" before)
        (is equal '(:rule) before-box)
        ;; Global assignments of every kind a job can make to what it
        ;; got from the format.
        (let ((job (make-format-job "\\def\\fmtname{changed}\\global\\catcode`\\@=11
\\global\\hyphenchar\\tentt=45 \\global\\advance\\count20 by 1
\\fontdimen1\\tenrm=3pt \\font\\x=cmr10 at 5pt \\global\\setbox\\strutbox\\hbox{x}
\\end")))
          (run-job job)
          (is equal '(:text) (strutbox-contents job))
          (multiple-value-bind (after after-box) (probe)
            (is string= before after)
            (is equal before-box after-box)))))))

(define-test patterns-are-too-late-in-a-job
  :parent formats
  (let ((job (make-format-job "\\patterns{a1b}\\hyphenation{ta-ble}\\end")))
    (multiple-value-bind (output errors) (run-job job)
      (declare (ignore output))
      (is equal '("Too late for \\patterns") errors)
      (let ((format-exceptions (expand:expander-hyphenation-exceptions
                                (make-format-job ""))))
        (is = (1+ (length format-exceptions))
            (length (expand:expander-hyphenation-exceptions job)))
        ;; The format's own list is unchanged.
        (is eq format-exceptions (rest (expand:expander-hyphenation-exceptions job)))))))

;;; Source lines on plain's own macros

(defparameter *spec-stubs*
  "\\def\\i#1{{\\it #1}}\\def\\ff#1{\\hbox{{\\tt #1} }}\\def\\sub#1{_{#1}}%
\\def\\term#1{{\\it #1\\/}}%
"
  "Stand-ins for the spec's own macros around the lines below.")

(define-test math-source-lines
  :parent formats
  (dolist (line '(;; dict-numbers.tex:1173
                  "(that is, it has the form \\i{integer}+$1\\over2$),"
                  ;; dict-numbers.tex:1411
                  "$$ \\ff{arcsin} z = -i\\ \\ff{log} \\Bigl(iz+\\sqrt{1-z^2}\\Bigr) $$"
                  ;; dict-arrays.tex:27
                  "$\\left\\{i\\sub{0},i\\sub{1},\\dots,i\\sub{r-1}\\right\\}$ to corresponding \\term{elements}"))
    (let ((job (make-format-job (concatenate 'string *spec-stubs* line "\\par\\end"))))
      (multiple-value-bind (output errors) (run-job job)
        (declare (ignore output))
        (is equal '() errors "errors of ~S" line)
        (true (find :math (expand:job-events job) :key #'second)
              "math in ~S" line)))))

(define-test plain-macro-spans
  :parent formats
  ;; \bigl's \hbox comes from plain.tex's \big, and says so.
  (let ((job (make-format-job "$\\bigl($\\par\\end")))
    (run-job job)
    (let ((box (find-if (lambda (event)
                          (and (eq (first event) :begin) (eq (second event) :box)))
                        (expand:job-events job))))
      (true box)
      (is string= "plain.tex" (span-file (getf (cddr box) :span))))))

(define-test alignment-source-lines
  :parent formats
  (flet ((shapes (text)
           (let ((job (make-format-job (concatenate 'string text "\\end"))))
             (multiple-value-bind (output errors) (run-job job)
               (declare (ignore output))
               (is equal '() errors "errors of ~S" text))
             (alignment-shapes job))))
    ;; setup-document.tex:132-134, with plain's \quad.
    (is equal '(((1 2) (1 2)))
        (shapes "\\def\\function{}\\def\\arg{}\\def\\EV{}%
\\def\\D#1#2#3{\\def\\entry##1{##1&\\cr}%
\\halign{\\hskip\\leftskip\\function ## {\\arg #1}\\hfil&\\quad\\EV\\ {\\arg #2}##\\cr#3}}%
\\D{x}{y}{\\entry{a}\\entry{b}}"))
    ;; setup-document.tex:320-324, with plain's fonts and \hsize.
    (is equal '(((1 2 3) :no-align (1 2 3) :no-align (1 2 3)))
        (shapes "\\def\\arg{}\\def\\param#1{#1}%
\\def\\auxbnf#1#2{{\\vskip 4pt\\def\\CR{\\cr\\noalign{\\penalty1000\\vskip 4pt\\penalty1000}&&}\\arg
\\halign to \\hsize{\\hskip\\leftskip\\quad##&\\hfil##& ##\\hfil\\cr
&\\param{#1}::$=$& #2\\cr}}}
\\auxbnf{name}{a\\CR b\\CR c}"))
    ;; setup-tables.tex:4-11.
    (is equal '((:no-align (1 2) (1 2) :no-align))
        (shapes "\\def\\misc#1{#1}%
\\def\\displaytwo #1#2{{\\dimen0=.75pc
\\tabskip \\dimen0 plus .5 fil
\\halign to \\hsize {\\misc{##}\\hfil\\tabskip \\dimen0 plus 1fil&
\\misc{##}\\hfil\\cr
\\noalign{\\vskip -9pt}
#2
\\noalign{\\vskip -9pt}
}}}\\displaytwo{T}{a&b\\cr c&d\\cr}"))
    ;; plain's own \settabs and \+ (an \halign of plain.tex's).
    (true (shapes "\\settabs 2 \\columns \\+a&b\\cr"))))
