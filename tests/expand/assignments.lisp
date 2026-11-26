;;;; tests/expand/assignments.lisp
;;;;
;;;; prefixed_command (src/expand/prefixed.lisp, assignments.lisp): the
;;;; prefixes and \globaldefs, definitions, \let and \futurelet,
;;;; shorthands, token lists, registers and their arithmetic, codes,
;;;; fonts, \parshape, the quantities of the nest and the page,
;;;; hyphenation data and \afterassignment (TeX: The Program,
;;;; §§1208-1280).  Jobs run through main control (main-control.lisp).

(in-package #:cl-ansi-spec/tests)

(define-test assignments
  :parent cl-ansi-spec
  :description "prefixed_command: every assignment, its errors and prefixes.")

(defun job-value (text function)
  "Run TEXT\\end and call FUNCTION on the expander's state."
  (funcall function (expand:expander-state (job-state text))))

(defun count-after (text n)
  "\\count N after the job TEXT."
  (job-value text (lambda (state) (expand:register state :count n))))

(define-test prefixes
  :parent assignments
  (is = 1 (count-after "{\\global\\relax\\count1=1 }" 1))
  (is = 1 (count-after "{\\global\\global\\count1=1 }" 1))
  (check-job "\\global x" "x" :errors ("You can't use a prefix with")
                              :contexts ("`the letter x'"))
  (check-job "\\long\\count1=1 \\ifnum\\count1=1 y\\fi" "y"
             :errors ("You can't use `\\long' or `\\outer' with")
             :contexts ("`\\count'"))
  (let ((macro (job-value "\\long\\outer\\def\\a{}"
                          (lambda (state) (expand:meaning state (cs state "a"))))))
    (true (expand:macro-long-p macro))
    (true (expand:macro-outer-p macro))))

(define-test definitions-and-globaldefs
  :parent assignments
  (check-job "{\\gdef\\a{x}}\\a" "x")
  (check-job "{\\def\\a{x}}\\a" "" :errors ("Undefined control sequence"))
  (check-job "{\\globaldefs=1 \\def\\a{x}}\\a" "x")
  (check-job "{\\globaldefs=-1 \\gdef\\a{x}}\\a" "" :errors ("Undefined control sequence"))
  (check-job "\\def\\b{y}\\edef\\a{\\b}\\def\\b{z}\\a" "y")
  (check-job "\\def\\b{y}{\\xdef\\a{\\b}}\\a" "y")
  (check-job "\\def\\a#1{(#1)}\\a x" "(x)")
  ;; get_r_token
  (check-job "\\def x{}" "" :errors ("Missing control sequence inserted"))
  (check-job "\\def~{t}~" "t")
  (check-job "\\expandafter\\def\\csname\\endcsname{e}\\csname\\endcsname" "e"))

(define-test let-and-futurelet
  :parent assignments
  (check-job "\\let\\a=b\\a" "\\a ")
  (check-job "\\let\\a=\\relax\\ifx\\a\\relax y\\fi" "y")
  (check-job "\\let\\a\\undefined\\a" "" :errors ("Undefined control sequence"))
  (check-job "\\let\\a={\\a\\aftergroup x}" "x")
  (check-job "\\def\\b{\\ifx\\c x(y)\\fi}\\futurelet\\c\\b x" "(y)x")
  (check-job "\\def\\a{A}{\\let\\b\\a}\\ifx\\b\\undefined u\\fi" "u"))

(define-test shorthands
  :parent assignments
  (is = 65 (count-after "\\chardef\\c=65 \\count1=\\c" 1))
  (check-job "\\chardef\\c=65 \\c" "\\c ")
  (is = 7 (count-after "\\countdef\\c=5 \\c=7 " 5))
  (is = (* 3 65536)
      (job-value "\\dimendef\\d=2 \\d=3pt"
                 (lambda (state) (expand:register state :dimen 2))))
  (is = #x7161 (count-after "\\mathchardef\\m=\"7161 \\count1=\\m" 1))
  (check-job "\\chardef\\c=256 " "" :errors ("Bad character code")))

(define-test token-lists
  :parent assignments
  (check-job "\\toks0={ab}\\toks1=\\toks0 \\toksdef\\t=2 \\t=\\toks1 \\the\\t" "ab")
  ;; The paragraph that "a" begins inserts \\everypar first.
  (check-job "\\everypar={a}\\toks0=\\everypar \\the\\toks0" "aa")
  (check-job "\\toks0 x}\\the\\toks0" "x" :errors ("Missing { inserted"))
  (is = 3 (job-value "\\output={x}"
                     (lambda (state) (length (expand:parameter state :output)))))
  (is eq nil (job-value "\\toks0={a}\\toks0={}"
                        (lambda (state) (expand:register state :toks 0)))))

(define-test registers-and-arithmetic
  :parent assignments
  (is = 4 (count-after "\\count1=5 \\advance\\count1 by 3 \\multiply\\count1 2
\\divide\\count1 by 4 " 1))
  (is = (* 9 65536)
      (job-value "\\dimen0=1pt \\advance\\dimen0 2pt \\multiply\\dimen0 3 "
                 (lambda (state) (expand:register state :dimen 0))))
  (let ((glue (job-value "\\skip0=1pt plus 2fil \\advance\\skip0 by 3pt minus 1pt "
                         (lambda (state) (expand:register state :skip 0)))))
    (is = (* 4 65536) (expand:glue-width glue))
    (is = (* 2 65536) (expand:glue-stretch glue))
    (is = 1 (expand:glue-stretch-order glue))
    (is = 65536 (expand:glue-shrink glue)))
  (true (expand:glue-mu-p (job-value "\\muskip0=3mu \\divide\\muskip0 3 "
                                     (lambda (state) (expand:register state :muskip 0)))))
  (is = 2147483647 (count-after "\\count1=2147483647 \\multiply\\count1 2 " 1))
  (check-job "\\count1=1 \\divide\\count1 0 " "" :errors ("Arithmetic overflow"))
  (check-job "\\advance\\toks0" "0" :errors ("You can't use")
                                  :contexts ("`\\toks' after \\advance"))
  (is = 70000 (job-value "\\parindent=1pt \\advance\\parindent by 4464sp "
                         (lambda (state) (expand:parameter state :parindent))))
  (is = 200 (job-value "\\tolerance=200 " (lambda (state) (expand:parameter state :tolerance))))
  (true (expand:glue-mu-p (job-value "\\thinmuskip=3mu "
                                     (lambda (state) (expand:parameter state :thinmuskip))))))

(define-test codes-and-families
  :parent assignments
  (check-job "\\catcode`\\@=11 \\def\\a@b{x}\\a@b" "x")
  (check-job "\\catcode65=16 " "" :errors ("Invalid code")
                                 :contexts ("(16), should be in the range 0..15"))
  (check-job "\\delcode`(=-5 \\sfcode1=32768 " "" :errors ("Invalid code")
                                               :contexts ("(32768), should be in the range 0..32767"))
  (check-job "\\delcode1=\"8000000 " "" :errors ("Invalid code")
                                      :contexts ("(134217728), should be at most 16777215"))
  (is = -5 (job-value "\\delcode`(=-5 "
                      (lambda (state) (expand:code state :delcode (char-code #\()))))
  (is = 32768 (job-value "\\mathcode1=\"8000 "
                         (lambda (state) (expand:code state :mathcode 1))))
  (is string= "f" (job-value "\\font\\f=cmr10 \\textfont3=\\f"
                             (lambda (state)
                               (expand:tex-font-identifier (expand:family-font state 0 3))))))

(define-test fonts-as-assignments
  :parent assignments
  (let ((state (expand:expander-state
                (job-state "\\font\\f=cmr10 at 12pt \\font\\g=cmr10 at 12pt \\f"))))
    (let ((font (expand:current-font state)))
      (is equal (list :at (* 12 65536)) (expand:tex-font-size font))
      ;; The last name defined for the font is its identifier.
      (is string= "g" (expand:tex-font-identifier font))
      (is eq font (expand:meaning state (cs state "g")))))
  (check-job "\\font\\f=cmr10 at -1pt " ""
             :errors ("Improper `at' size (-1.0pt), replaced by 10pt"))
  (check-job "\\font\\f=cmr10 scaled 0 " ""
             :errors ("Illegal magnification has been changed to 1000"))
  (check-job "\\font\\f=cmr10 \\fontdimen5\\f=3pt \\ifdim\\fontdimen5\\f=3pt y\\fi" "y")
  (check-job "\\fontdimen8\\nullfont=1pt\\fontdimen5\\font=2pt \\ifdim\\fontdimen5\\nullfont=2pt y\\fi"
             "y")
  (check-job "\\font\\f=cmr10 \\fontdimen8\\nullfont=1pt" ""
             :errors ("Font \\nullfont has only 7 fontdimen parameters"))
  (is = 45 (job-value "\\hyphenchar\\font=45 "
                      (lambda (state) (expand:tex-font-hyphen-char (expand:current-font state)))))
  (is = 7 (job-value "\\font\\f=cmr10 \\skewchar\\f=7 "
                     (lambda (state) (expand:tex-font-skew-char
                                      (expand:meaning state (cs state "f")))))))

(define-test nest-page-and-shape
  :parent assignments
  (check-job "\\parshape 2 1pt 2pt 3pt 4pt \\ifnum\\parshape=2 y\\fi" "y")
  (is equal (list (cons 65536 (* 2 65536)))
      (job-value "\\parshape 1 1pt 2pt " #'expand:par-shape))
  (check-job "\\spacefactor=5 " "=5 " :errors ("You can't use")
                                 :contexts ("`\\spacefactor' in vertical mode"))
  (check-job "x\\spacefactor=0 " "x" :errors ("Bad space factor"))
  (check-job "x\\spacefactor=2000 \\ifnum\\spacefactor=2000 y\\fi" "xy")
  (check-job "\\prevdepth=3pt \\ifdim\\prevdepth=3pt y\\fi" "y")
  (check-job "\\prevgraf=-1 " "" :errors ("Bad \\prevgraf"))
  (check-job "\\prevgraf=3 \\ifnum\\prevgraf=3 y\\fi" "y")
  (let ((page (expand:expander-page (job-state "\\pagegoal=5pt \\deadcycles=3
\\insertpenalties=2 "))))
    (is = (* 5 65536) (aref (expand:page-state-so-far page) 0))
    (is = 3 (expand:page-state-dead-cycles page))
    (is = 2 (expand:page-state-insert-penalties page)))
  (is eq :batch (expand:expander-interaction (job-state "\\scrollmode\\batchmode"))))

(define-test hyphenation-data
  :parent assignments
  (let ((expander (job-state "\\patterns{.a1b 2b}")))
    (is equal (list (list 0 (list 98) (list 2 0))
                    (list 0 (list 0 97 98) (list 0 0 1 0)))
        (expand:expander-patterns expander)))
  (check-job "\\patterns{a1b a1b}" "" :errors ("Duplicate pattern"))
  (check-job "\\patterns{a\\relax}" "" :errors ("Bad \\patterns"))
  (check-job "\\patterns{a-}" "" :errors ("Nonletter"))
  (check-job "\\patterns{a}" "" :errors ("Too late for \\patterns")
             :setup ((setf (expand:expander-trie-not-ready expander) nil)))
  (let ((expander (job-state "\\language=3 \\hyphenation{as-so-Ciate x}")))
    (is equal (list (list 3 (map 'list #'char-code "associate") (list 2 4)))
        (expand:expander-hyphenation-exceptions expander)))
  (check-job "\\hyphenation{a1}" "" :errors ("Not a letter"))
  (check-job "\\hyphenation{a\\relax}" "" :errors ("Improper \\hyphenation will be flushed")))

(define-test after-assignment
  :parent assignments
  (check-job "\\def\\a{x}\\afterassignment\\a\\count1=1 " "x")
  (check-job "\\def\\a{x}\\afterassignment\\a\\def\\b{}" "x")
  ;; Only one token is kept, and only until the next assignment.
  (check-job "\\afterassignment a\\afterassignment b\\count1=1 \\count2=2 " "b")
  (check-job "\\afterassignment a\\relax" ""))
