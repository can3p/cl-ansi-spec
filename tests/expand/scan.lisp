;;;; tests/expand/scan.lisp
;;;;
;;;; Scanning (src/expand/scan.lisp, internal.lisp, dimen-scan.lisp,
;;;; toks.lisp): keywords, integers, dimensions, glue, internal
;;;; quantities, token lists, \the, \number, \romannumeral and \fontname,
;;;; each with TeX's errors and recovery.  Expected values follow TeX:
;;;; The Program and the TeXbook (chapters 10, 20 and 24).

(in-package #:cl-ansi-spec/tests)

(define-test scanning
  :parent cl-ansi-spec
  :description "TeX's scanners and the conversions built on them.")

(defun scanned (text function &key setup)
  "Run FUNCTION on an expander reading TEXT (after SETUP, a function of
the expander), recovering from TeX errors.  Returns FUNCTION's first
value, the expansion of the rest of the input and every error message."
  (let ((expander (make-test-expander text))
        (errors '())
        (value nil))
    (when setup (funcall setup expander))
    (expand:call-recovering-tex-errors
     (lambda () (setf value (funcall function expander)))
     (lambda (condition) (push (expand:tex-error-message condition) errors)))
    (multiple-value-bind (rest more) (expansion-of expander)
      (values value rest (append (reverse errors) more)))))

(defmacro check-scan (text function expected-value expected-rest
                      &key setup (errors '()) (test 'equal))
  "Check FUNCTION's value on TEXT, the rest of the input and the errors."
  `(multiple-value-bind (value rest messages)
       (scanned ,text ,function :setup ,setup)
     (is ,test ,expected-value value "value of ~S" ,text)
     (is string= ,expected-rest rest "rest of ~S" ,text)
     (is equal ',errors messages "errors of ~S" ,text)))

(defun state-of (expander)
  (expand:expander-state expander))

(defun set-count (expander n value)
  (expand:set-register (state-of expander) :count n value))

(defun pt (x)
  "X points in sp (X a rational with an exact sp value)."
  (* x expand:+unity+))

(defun scan-dimen-text (expander)
  (expand:format-dimen (expand:scan-dimen expander)))

(defun scan-glue-text (expander)
  (expand:format-glue (expand:scan-glue expander :glue)))

;;; Keywords and small scanners

(define-test keywords
  :parent scanning
  (flet ((plus (e) (expand:scan-keyword e "plus")))
    (check-scan "  PlUs x" #'plus t " x")
    ;; A partial match is put back with the blank that ended it...
    (check-scan "pl x" #'plus nil "pl x")
    ;; ...but blanks before a mismatch are lost.
    (check-scan "  x" #'plus nil "x")
    ;; Any category counts: an `other' letter matches.
    (check-scan "\\catcode`p=12 x" (lambda (e) (expand:scan-keyword e "\\catcode")) nil
                "\\catcode `p=12 x"))
  (check-scan " = x" (lambda (e) (expand:scan-optional-equals e) t) t " x")
  (check-scan " x" (lambda (e) (expand:scan-optional-equals e) t) t "x")
  (check-scan " \\relax{x}" (lambda (e) (expand:scan-left-brace e) t) t "x}")
  (check-scan "x}" (lambda (e) (expand:scan-left-brace e) t) t "x}"
              :errors ("Missing { inserted")))

(define-test bounded-integers
  :parent scanning
  (check-scan "255" #'expand:scan-eight-bit-int 255 "")
  (check-scan "256" #'expand:scan-eight-bit-int 0 "" :errors ("Bad register code"))
  (check-scan "-1" #'expand:scan-char-num 0 "" :errors ("Bad character code"))
  (check-scan "16" #'expand:scan-four-bit-int 0 "" :errors ("Bad number"))
  (check-scan "\"7FFF" #'expand:scan-fifteen-bit-int #x7FFF "")
  (check-scan "\"8000" #'expand:scan-fifteen-bit-int 0 "" :errors ("Bad mathchar"))
  (check-scan "\"7FFFFFF" #'expand:scan-twenty-seven-bit-int #x7FFFFFF "")
  (check-scan "\"8000000" #'expand:scan-twenty-seven-bit-int 0 ""
              :errors ("Bad delimiter code")))

;;; Integers

(define-test integer-constants
  :parent scanning
  (check-expansion "\\number 42" "42")
  (check-expansion "\\number 007 x" "7x")
  ;; The reader drops the second space.
  (check-expansion "\\number 7  x" "7x")
  (check-expansion "\\number'17" "15")
  (check-expansion "\\number\"1F" "31")
  ;; Lowercase is no hexadecimal digit.
  (check-expansion "\\number\"1f" "1f")
  (check-expansion "\\number`a" "97")
  (check-expansion "\\number`\\a" "97")
  (check-expansion "\\number`\\%" "37")
  (check-expansion "\\number`{}" "123}")
  (check-expansion "\\number`a b" "97b")
  (check-expansion "\\number - - + -5" "-5")
  (check-expansion "\\number-0" "0")
  (check-expansion "\\number 2147483647" "2147483647")
  (check-expansion "\\number-2147483647" "-2147483647")
  (check-expansion "\\number 2147483648" "2147483647" :errors ("Number too big"))
  (check-expansion "\\number 99999999999" "2147483647" :errors ("Number too big"))
  (check-expansion "\\number'17777777777" "2147483647")
  (check-expansion "\\number'20000000000" "2147483647" :errors ("Number too big"))
  (check-expansion "\\number\"7FFFFFFF" "2147483647")
  (check-expansion "\\number x" "0x" :errors ("Missing number, treated as zero"))
  (check-expansion "\\number'8" "08" :errors ("Missing number, treated as zero"))
  ;; TeX's value after the error is the code of `0'.
  (check-expansion "\\number`\\relax" "48\\relax "
                   :errors ("Improper alphabetic constant")))

(define-test integer-internal-quantities
  :parent scanning
  (check-expansion "\\number\\count0" "-7" :setup ((set-count expander 0 -7)))
  (check-expansion "\\number-\\count0 x" "7x" :setup ((set-count expander 0 -7)))
  (check-expansion "\\number\\tolerance" "10000")
  (check-expansion "\\number\\catcode`\\a" "11")
  (check-expansion "\\number\\dimen0" "65536"
                   :setup ((expand:set-register (state-of expander) :dimen 0 (pt 1))))
  (check-expansion "\\number\\skip0" "131072"
                   :setup ((expand:set-register (state-of expander) :skip 0
                                                (expand:make-glue :width (pt 2)
                                                                  :stretch (pt 1)))))
  (check-expansion "\\number\\muskip0" "3"
                   :setup ((expand:set-register (state-of expander) :muskip 0
                                                (expand:make-glue :width 3 :mu-p t)))
                   :errors ("Incompatible glue units"))
  (check-expansion "\\number\\toks0" "0\\toks 0"
                   :errors ("Missing number, treated as zero"))
  (check-expansion "\\number\\relax" "0\\relax "
                   :errors ("Missing number, treated as zero"))
  (check-expansion "\\number\\x" "65"
                   :setup ((expand:set-meaning (state-of expander)
                                               (cs (state-of expander) "x")
                                               (expand:make-shorthand :char 65)))))

(define-test roman-numerals
  :parent scanning
  (loop for (n roman) in '((1 "i") (4 "iv") (9 "ix") (14 "xiv") (40 "xl")
                           (90 "xc") (400 "cd") (1990 "mcmxc") (2026 "mmxxvi")
                           (3999 "mmmcmxcix") (4000 "mmmm") (0 "") (-5 ""))
        do (is string= roman (expand:format-roman n) "roman of ~D" n))
  ;; setup-aux.tex:249 shows negative page numbers in roman.
  (check-expansion "\\romannumeral-\\count0" "xii" :setup ((set-count expander 0 -12)))
  (check-expansion "\\romannumeral 0 x" "x"))

;;; Dimensions

(define-test dimension-constants
  :parent scanning
  (check-scan "1in" #'scan-dimen-text "72.26999pt" "")
  (check-scan "3.5 pt" #'scan-dimen-text "3.5pt" "")
  (check-scan ".5pt" #'scan-dimen-text "0.5pt" "")
  (check-scan "1,5pt" #'scan-dimen-text "1.5pt" "")
  (check-scan "--1pt x" #'scan-dimen-text "1.0pt" "x")
  (check-scan "- 2pc" #'scan-dimen-text "-24.0pt" "")
  (check-scan "1PT" #'scan-dimen-text "1.0pt" "")
  (check-scan "1 bp" #'scan-dimen-text "1.00374pt" "")
  (check-scan "1cm" #'scan-dimen-text "28.45274pt" "")
  (check-scan "10mm" #'scan-dimen-text "28.45274pt" "")
  (check-scan "1dd" #'scan-dimen-text "1.07pt" "")
  (check-scan "1cc" #'scan-dimen-text "12.8401pt" "")
  (check-scan "1.5sp" #'expand:scan-dimen 1 "")
  (check-scan "'10pt" #'scan-dimen-text "8.0pt" "")
  ;; No fraction after a hexadecimal constant.
  (check-scan "\"A.5pt" #'scan-dimen-text "10.0pt" ".5pt"
              :errors ("Illegal unit of measure (pt inserted)"))
  (check-scan "16383.99999pt" #'expand:scan-dimen expand:+max-dimen+ "")
  (check-scan "16384pt" #'expand:scan-dimen expand:+max-dimen+ ""
              :errors ("Dimension too large"))
  (check-scan "3xx" #'scan-dimen-text "3.0pt" "xx"
              :errors ("Illegal unit of measure (pt inserted)"))
  (check-scan "1fil" #'scan-dimen-text "1.0pt" "fil"
              :errors ("Illegal unit of measure (pt inserted)")))

(define-test dimension-units
  :parent scanning
  (flet ((setup (e)
           (set-count e 0 3)
           (expand:set-register (state-of e) :dimen 0 (pt 2))
           (expand:set-register (state-of e) :skip 0 (expand:make-glue :width (pt 5)))))
    (check-scan "2\\dimen0" #'scan-dimen-text "4.0pt" "" :setup #'setup)
    (check-scan "-.5\\dimen0" #'scan-dimen-text "-1.0pt" "" :setup #'setup)
    (check-scan "2\\count0" #'expand:scan-dimen 6 "" :setup #'setup)
    (check-scan "\\count0 pt" #'scan-dimen-text "3.0pt" "" :setup #'setup)
    (check-scan "-\\dimen0" #'scan-dimen-text "-2.0pt" "" :setup #'setup)
    (check-scan "\\skip0" #'scan-dimen-text "5.0pt" "" :setup #'setup)
    (check-scan "1\\skip0" #'scan-dimen-text "5.0pt" "" :setup #'setup))
  (flet ((setup (e)
           (let ((font (expand:current-font (state-of e))))
             (expand:set-font-dimen font 6 (pt 10))
             (expand:set-font-dimen font 5 (pt 4)))))
    (check-scan "1.5em x" #'scan-dimen-text "15.0pt" "x" :setup #'setup)
    (check-scan "2ex" #'scan-dimen-text "8.0pt" "" :setup #'setup))
  (flet ((fil (e) (multiple-value-list (expand:scan-dimen e :inf t))))
    (check-scan "2fil" #'fil (list (pt 2) 1) "")
    (check-scan "2fil L l" #'fil (list (pt 2) 3) "")
    (check-scan "2fillll" #'fil (list (pt 2) 3) ""
                :errors ("Illegal unit of measure (replaced by filll)"))
    (check-scan "2pt" #'fil (list (pt 2) 0) "")))

(define-test true-dimensions
  :parent scanning
  (flet ((mag (n) (lambda (e) (set-integer-parameter (expand:es-tex (state-of e)) :mag n))))
    (check-scan "10truept" #'scan-dimen-text "5.0pt" "" :setup (mag 2000))
    (check-scan "10 true pt" #'scan-dimen-text "10.0pt" "")
    (check-scan "10truept" #'scan-dimen-text "10.0pt" "" :setup (mag 0)
                :errors ("Illegal magnification has been changed to 1000"))
    (check-scan "10truept" #'scan-dimen-text "5.0pt" ""
                :setup (lambda (e)
                         (funcall (mag 1000) e)
                         (setf (expand:expander-mag-set e) 2000))
                :errors ("Incompatible magnification"))))

(define-test mu-dimensions
  :parent scanning
  (flet ((mu (e) (expand:scan-dimen e :mu t)))
    (check-scan "3mu" #'mu (pt 3) "")
    (check-scan "3pt" #'mu (pt 3) "pt" :errors ("Illegal unit of measure (mu inserted)"))
    (check-scan "2\\muskip0" #'mu (pt 6) ""
                :setup (lambda (e)
                         (expand:set-register (state-of e) :muskip 0
                                              (expand:make-glue :width (pt 3) :mu-p t))))
    (check-scan "\\muskip0" #'mu (pt 3) ""
                :setup (lambda (e)
                         (expand:set-register (state-of e) :muskip 0
                                              (expand:make-glue :width (pt 3) :mu-p t))))))

;;; Glue

(define-test glue-scanning
  :parent scanning
  (check-scan "1pt plus 2fil minus 3pt" #'scan-glue-text
              "1.0pt plus 2.0fil minus 3.0pt" "")
  (check-scan "1pt minus 1fill x" #'scan-glue-text "1.0pt minus 1.0fill" "x")
  (check-scan "-1pt plus -2pt" #'scan-glue-text "-1.0pt plus -2.0pt" "")
  (check-scan "1pt pluto" #'scan-glue-text "1.0pt" "pluto")
  (flet ((setup (e)
           (set-count e 0 3)
           (expand:set-register (state-of e) :dimen 0 (pt 2))
           (expand:set-register (state-of e) :skip 0
                                (expand:make-glue :width (pt 5) :stretch (pt 1)))))
    (check-scan "\\skip0 plus 3pt" #'scan-glue-text "5.0pt plus 1.0pt" "plus 3pt"
                :setup #'setup)
    (check-scan "-\\skip0" #'scan-glue-text "-5.0pt plus -1.0pt" "" :setup #'setup)
    (check-scan "\\dimen0 plus 1fil" #'scan-glue-text "2.0pt plus 1.0fil" ""
                :setup #'setup)
    (check-scan "-\\count0 pt" #'scan-glue-text "-3.0pt" "" :setup #'setup)
    (check-scan "\\skip0" (lambda (e) (expand:format-glue (expand:scan-glue e :mu)))
                "5.0mu plus 1.0mu" "" :setup #'setup
                :errors ("Incompatible glue units")))
  (check-scan "1mu plus 2fill" (lambda (e) (expand:format-glue (expand:scan-glue e :mu)))
              "1.0mu plus 2.0fill" ""))

;;; \the

(defun load-test-font (expander name file &rest size)
  "Load FILE as \\font\\NAME would, at SIZE."
  (let* ((state (state-of expander))
         (font (expand:load-font state file :size size :identifier name)))
    (expand:set-meaning state (cs state name) font)
    font))

(define-test the-quantities
  :parent scanning
  (check-expansion "\\the\\count0" "-7" :setup ((set-count expander 0 -7)))
  (check-expansion "\\the\\hsize" "0.0pt")
  (check-expansion "\\the\\dimen0" "72.26999pt"
                   :setup ((expand:set-register (state-of expander) :dimen 0
                                                (expand:scan-dimen
                                                 (make-test-expander "1in")))))
  (check-expansion "\\the\\skip0" "1.0pt plus 2.0fil"
                   :setup ((expand:set-register (state-of expander) :skip 0
                                                (expand:make-glue :width (pt 1)
                                                                  :stretch (pt 2)
                                                                  :stretch-order 1))))
  (check-expansion "\\the\\muskip0" "1.0mu"
                   :setup ((expand:set-register (state-of expander) :muskip 0
                                                (expand:make-glue :width (pt 1) :mu-p t))))
  (check-expansion "\\the\\thinmuskip" "0.0mu")
  (check-expansion "\\the\\toks0" "a\\relax "
                   :setup ((expand:set-register (state-of expander) :toks 0
                                                (test-tokens expander "a\\relax"))))
  (check-expansion "\\the\\everypar" "")
  (check-expansion "\\the\\catcode`\\\\" "0")
  (check-expansion "\\the\\mathcode`a" "29025")
  (check-expansion "\\the\\delcode`." "0")
  (check-expansion "\\the\\parshape" "0")
  (check-expansion "\\the\\relax" "0" :errors ("You can't use"))
  (check-expansion "\\the\\inputlineno" "1")
  (check-expansion "\\the\\badness" "0")
  (check-expansion "\\the\\wd0" "0.0pt")
  (check-expansion "\\the\\wd256" "0.0pt" :errors ("Bad register code"))
  (check-expansion "\\the\\deadcycles" "0")
  (check-expansion "\\the\\x" "5"
                   :setup ((set-count expander 3 5)
                           (expand:set-meaning (state-of expander)
                                               (cs (state-of expander) "x")
                                               (expand:make-shorthand :count 3)))))

(define-test the-list-and-page-quantities
  :parent scanning
  (check-expansion "\\the\\prevdepth" "-1000.0pt")
  (check-expansion "\\the\\spacefactor" "0" :errors ("Improper"))
  (check-expansion "\\the\\spacefactor" "1000"
                   :setup ((setf (expand:list-state-mode (expand:current-list expander))
                                 :horizontal)))
  (check-expansion "\\the\\prevgraf" "0")
  (check-expansion "\\the\\pagegoal" "16383.99998pt")
  (check-expansion "\\the\\pagetotal" "0.0pt")
  (check-expansion "\\the\\lastpenalty" "0")
  (check-expansion "\\the\\lastskip" "0.0pt")
  (flet ((last-node (expander node)
           ;; A node whose last item (§424) is NODE, a cons (KIND . VALUE).
           (expand:append-node expander
                               (expand:make-node (if (eq (car node) :character)
                                                     :text
                                                     (car node))
                                                 :value (or (cdr node) "x")
                                                 :properties (list :style "x")))))
    (check-expansion "\\the\\lastpenalty" "50"
                     :setup ((last-node expander '(:penalty . 50))))
    (check-expansion "\\the\\lastkern" "0.0pt"
                     :setup ((last-node expander '(:penalty . 50))))
    (check-expansion "\\the\\lastkern" "2.0pt"
                     :setup ((last-node expander (cons :kern (pt 2)))))
    (check-expansion "\\the\\lastskip" "3.0mu"
                     :setup ((last-node expander
                                        (cons :glue (expand:make-glue :width (pt 3)
                                                                      :mu-p t)))))
    (check-expansion "\\the\\lastskip" "0.0pt"
                     :setup ((last-node expander '(:character))))
    ;; An empty main vertical list shows what the page builder saw last.
    (check-expansion "\\the\\lastpenalty" "-10"
                     :setup ((setf (expand:page-state-last-penalty
                                    (expand:expander-page expander))
                                   -10)))))

(define-test the-inputlineno
  :parent scanning
  (check-expansion (format nil "a~%~%\\the\\inputlineno") "a3"))

(define-test the-fonts
  :parent scanning
  (check-expansion "\\the\\font" "\\nullfont ")
  (check-expansion "\\the\\textfont1" "\\nullfont ")
  (check-expansion "\\the\\fontdimen6\\nullfont" "0.0pt")
  (check-expansion "\\the\\hyphenchar\\font" "45")
  (check-expansion "\\the\\tenrm" "\\tenrm "
                   :setup ((load-test-font expander "tenrm" "cmr10")))
  (check-expansion "\\fontname\\tenrm" "cmr10 at 5.0pt"
                   :setup ((load-test-font expander "tenrm" "cmr10" :at (pt 5))))
  (check-expansion "\\fontname\\font" "nullfont")
  (check-expansion "\\fontname\\relax" "nullfont\\relax "
                   :errors ("Missing font identifier"))
  (check-expansion "\\the\\fontdimen22\\tenrm" "0.0pt"
                   :setup ((load-test-font expander "tenrm" "cmr10")))
  (check-expansion "\\the\\fontdimen0\\tenrm" "0.0pt"
                   :setup ((load-test-font expander "tenrm" "cmr10"))
                   :errors ("Font \\tenrm has only 0 fontdimen parameters"))
  ;; \nullfont has 7 parameters, and grows only while it is the last font.
  (check-expansion "\\the\\fontdimen8\\nullfont" "0.0pt")
  (check-expansion "\\the\\fontdimen8\\nullfont" "0.0pt"
                   :setup ((load-test-font expander "tenrm" "cmr10"))
                   :errors ("Font \\nullfont has only 7 fontdimen parameters"))
  ;; The identifier keeps meaning the font.
  (multiple-value-bind (value rest)
      (scanned "\\the\\tenrm"
               (lambda (e)
                 (load-test-font e "tenrm" "cmr10")
                 (let ((token (first (expand:the-toks e))))
                   (expand:set-meaning (state-of e) (cs (state-of e) "tenrm") nil)
                   (multiple-value-list
                    (expand:get-next
                     (progn (expand:back-token e token) e))))))
    (true (expand:tex-font-p (second value)))
    (is string= "" rest)))

;;; Token lists

(defun definition-text (text &key xpand setup)
  "Scan TEXT as a definition (after \\def\\x) and show the macro as
\\meaning does, plus the rest of the input and the errors."
  (scanned text
           (lambda (e)
             (multiple-value-bind (parameters body)
                 (expand:scan-toks e :macro-def t :xpand xpand
                                     :warning-index (cs (state-of e) "x"))
               (expand:meaning-text e (make-cs-token (cs (state-of e) "x") nil)
                                    (expand:make-macro parameters body))))
           :setup setup))

(defmacro check-definition (text expected &key xpand setup (rest "") (errors '()))
  `(multiple-value-bind (value remaining messages)
       (definition-text ,text :xpand ,xpand :setup ,setup)
     (is string= ,expected value "definition ~S" ,text)
     (is string= ,rest remaining "rest of ~S" ,text)
     (is equal ',errors messages "errors of ~S" ,text)))

(define-test definitions
  :parent scanning
  (check-definition "#1#2{(#2,#1)}x" "macro:#1#2->(#2,#1)" :rest "x")
  (check-definition "#1.#2\\par{#1{#2}}" "macro:#1.#2\\par ->#1{#2}")
  (check-definition "#1#{x}" "macro:#1{->x{")
  (check-definition "#{}" "macro:{->{")
  (check-definition "{a##b}" "macro:->a##b")
  ;; The wrong digit is put back and read as a delimiter.
  (check-definition "#1#3{#1}" "macro:#1#23->#1"
                    :errors ("Parameters must be numbered consecutively"))
  (check-definition "#1{#2}" "macro:#1->##2"
                    :errors ("Illegal parameter number in definition of"))
  (check-definition "#1#2#3#4#5#6#7#8#9#0{}" "macro:#1#2#3#4#5#6#7#8#9->"
                    :errors ("You already have nine parameters"))
  (check-definition "a}b" "macro:a->" :rest "b" :errors ("Missing { inserted"))
  (check-definition "{a{b}c}d" "macro:->a{b}c" :rest "d"))

(define-test general-texts
  :parent scanning
  (flet ((text (e) (token-list-of e (expand:scan-toks e)))
         (expanded (e) (token-list-of e (expand:scan-toks e :xpand t)))
         (setup (e)
           (define-test-macro e "a" "" "X")
           (expand:set-register (state-of e) :toks 0 (test-tokens e "\\a"))))
    (check-scan " \\relax{a{b}\\a}d" #'text "a{b}\\a " "d")
    (check-scan "{\\a\\noexpand\\a}" #'expanded "X\\a " "" :setup #'setup)
    (check-scan "{\\the\\toks0}" #'expanded "\\a " "" :setup #'setup)
    (check-scan "{\\the\\font}" #'expanded "\\nullfont " "")
    (check-scan "x}" #'text "x" "" :errors ("Missing { inserted"))))

(defun token-list-of (expander tokens)
  "TOKENS as EXPANSION-OF shows them."
  (declare (ignore expander))
  (with-output-to-string (out)
    (dolist (token tokens)
      (if (character-token-p token)
          (write-char (code-char (character-token-code token)) out)
          (format out "\\~A " (control-sequence-name
                               (cs-token-control-sequence token)))))))
