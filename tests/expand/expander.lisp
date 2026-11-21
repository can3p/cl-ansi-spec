;;;; tests/expand/expander.lisp
;;;;
;;;; The expansion core (src/expand/expander.lisp, macro.lisp,
;;;; expandable.lisp, show.lisp): macro calls with TeX's matching rules,
;;;; runaways and their recovery, and the expandable primitives.  Inputs
;;;; are strings under plain TeX's catcodes, read without \endlinechar.

(in-package #:cl-ansi-spec/tests)

(define-test expansion
  :parent cl-ansi-spec
  :description "get_x_token, macro calls and the expandable primitives.")

(defun make-test-expander (text &key files (job-name "main"))
  "An expander over the plain catcodes reading TEXT, with FILES (an alist
of (name . text)) available to \\input."
  (let* ((state (expand:make-expander-state :tex (make-plain-state)))
         (expander (expand:make-expander
                    :state state :job-name job-name
                    :resolver (alist-resolver (acons "main" text files)))))
    (set-endlinechar (expand:es-tex state) -1)
    (push-file (expand:expander-input expander) "main")
    expander))

(defun test-tokens (expander string)
  "The tokens of STRING under EXPANDER's current catcodes."
  (let ((stack (make-input-stack (expand:es-tex (expand:expander-state expander))
                                 :resolver (alist-resolver
                                            (list (cons "string" string))))))
    (push-file stack "string")
    (loop for token = (next-token stack) while token collect token)))

(defun define-test-macro (expander name parameters body &key long outer)
  "Define the macro \\NAME as \\def would: PARAMETERS and BODY are TeX
source, #n and ## as in a definition."
  (let ((parameter-text
          (loop with tokens = (test-tokens expander parameters)
                while tokens
                collect (let ((token (pop tokens)))
                          ;; #n is one match token: drop the digit.
                          (when (and (character-token-p token)
                                     (= (character-token-catcode token) +parameter+)
                                     tokens
                                     (character-token-p (first tokens))
                                     (digit-char-p (code-char (character-token-code
                                                               (first tokens)))))
                            (pop tokens))
                          token)))
        (body (loop with tokens = (test-tokens expander body)
                    while tokens
                    collect (let ((token (pop tokens)))
                              (if (and (character-token-p token)
                                       (= (character-token-catcode token) +parameter+))
                                  (let ((next (pop tokens)))
                                    (if (and (character-token-p next)
                                             (digit-char-p (code-char (character-token-code next))))
                                        (digit-char-p (code-char (character-token-code next)))
                                        next))
                                  token)))))
    (expand:set-meaning (expand:expander-state expander)
                        (intern-control-sequence
                         (expand:es-tex (expand:expander-state expander)) name)
                        (expand:make-macro parameter-text body
                                           :long-p long :outer-p outer))))

(defun expansion-of (expander)
  "Run EXPANDER to the end with get_x_token, recovering from TeX errors.
Returns a string (a character as itself, a control sequence as its name
and a space) and the list of error messages."
  (let ((errors '()))
    (values
     (with-output-to-string (out)
       (expand:call-recovering-tex-errors
        (lambda ()
          (loop for token = (expand:get-x-token expander)
                while token
                do (if (character-token-p token)
                       (write-char (code-char (character-token-code token)) out)
                       (format out "\\~A "
                               (control-sequence-name
                                (cs-token-control-sequence token))))))
        (lambda (condition)
          (push (expand:tex-error-message condition) errors))))
     (reverse errors))))

(defmacro check-expansion (text expected &key setup (errors '()) files)
  "Expand TEXT after SETUP (forms run with EXPANDER bound) and check the
output string and error messages."
  `(let ((expander (make-test-expander ,text :files ,files)))
     (declare (ignorable expander))
     ,@setup
     (multiple-value-bind (output messages) (expansion-of expander)
       (is string= ,expected output "expansion of ~S" ,text)
       (is equal ',errors messages "errors of ~S" ,text))))

;;; Macro calls

(define-test undelimited-parameters
  :parent expansion
  (flet ((setup (e) (define-test-macro e "a" "#1#2" "(#2,#1)")))
    (check-expansion "\\a xy" "(y,x)" :setup ((setup expander)))
    (check-expansion "\\a{xy} z" "(z,xy)" :setup ((setup expander)))
    (check-expansion "\\a x  {y}" "(y,x)" :setup ((setup expander)))
    ;; Braces are stripped from a single group only.
    (check-expansion "\\a{{x}}{}" "(,{x})" :setup ((setup expander)))))

(define-test delimited-parameters
  :parent expansion
  (flet ((setup (e) (define-test-macro e "b" "#1." "[#1]")))
    (check-expansion "\\b{x}." "[x]" :setup ((setup expander)))
    (check-expansion "\\b{x}{y}." "[{x}{y}]" :setup ((setup expander)))
    (check-expansion "\\b ab." "[ab]" :setup ((setup expander)))
    (check-expansion "\\b{x}y." "[{x}y]" :setup ((setup expander)))
    (check-expansion "\\b." "[]" :setup ((setup expander))))
  ;; A delimiter before the first parameter, and between parameters.
  (check-expansion "\\c<1>2|" "1:2"
                   :setup ((define-test-macro expander "c" "<#1>#2|" "#1:#2")))
  ;; \par may be a delimiter even for a macro that is not \long.
  (check-expansion "\\d x\\par" "[x]"
                   :setup ((define-test-macro expander "d" "#1\\par" "[#1]"))))

(define-test partial-delimiter-matches
  :parent expansion
  ;; §397: tokens of a failed partial match go into the argument one by
  ;; one, and matching resumes on the rest.
  (check-expansion "\\c aab" "[a]"
                   :setup ((define-test-macro expander "c" "#1ab" "[#1]")))
  (check-expansion "\\c aaab" "[a]"
                   :setup ((define-test-macro expander "c" "#1aab" "[#1]")))
  (check-expansion "\\c abaabab" "[aba]"
                   :setup ((define-test-macro expander "c" "#1abab" "[#1]")))
  (check-expansion "\\c xababx" "[xab]"
                   :setup ((define-test-macro expander "c" "#1abx" "[#1]"))))

(define-test brace-delimiter
  :parent expansion
  ;; \def\g#1#{[#1]}: the brace ends the argument and is put back.
  (let ((expander (make-test-expander "\\g ab{c}")))
    (let ((hash (first (test-tokens expander "#")))
          (brace (first (test-tokens expander "{"))))
      (expand:set-meaning (expand:expander-state expander)
                          (intern-control-sequence
                           (expand:es-tex (expand:expander-state expander)) "g")
                          (expand:make-macro (list hash brace)
                                             (append (test-tokens expander "[")
                                                     (list 1)
                                                     (test-tokens expander "]")
                                                     (list brace)))))
    (is string= "[ab]{c}" (expansion-of expander))))

(define-test runaway-arguments
  :parent expansion
  (flet ((setup (e &key long) (define-test-macro e "f" "#1" "[#1]" :long long)))
    ;; \par ends a non-\long call; it is read again.
    (check-expansion "\\f\\par x" "\\par x" :setup ((setup expander))
                     :errors ("Paragraph ended before macro was complete"))
    (check-expansion "\\f{a\\par b}" "\\par b}" :setup ((setup expander))
                     :errors ("Paragraph ended before macro was complete"))
    (check-expansion "\\f{a\\par b}" "[a\\par b]" :setup ((setup expander :long t)))
    ;; An extra } inserts \par, which then ends the call (§395).
    (check-expansion "\\f}" "\\par }" :setup ((setup expander))
                     :errors ("Argument of macro has an extra }"
                              "Paragraph ended before macro was complete"))
    ;; A missing delimiter before the first parameter drops the call.
    (check-expansion "\\e x y" " y"
                     :setup ((define-test-macro expander "e" ".#1" "[#1]"))
                     :errors ("Use of macro doesn't match its definition"))))

(define-test outer-macros-and-file-ends
  :parent expansion
  (flet ((setup (e)
           (define-test-macro e "f" "#1" "[#1]")
           (define-test-macro e "o" "" "O" :outer t)))
    ;; An \outer macro in an argument: reported, \par inserted to end the
    ;; call silently, and the macro read again (§§336-339).
    (check-expansion "\\f\\o" "O" :setup ((setup expander))
                     :errors ("Forbidden control sequence found"))
    ;; Outside of matching, \outer macros expand freely.
    (check-expansion "\\o\\f x" "O[x]" :setup ((setup expander)))
    ;; The file ends inside an argument.
    (check-expansion "\\f" "" :setup ((setup expander))
                     :errors ("File ended"))
    ;; \noexpand does not act while an argument is read.
    (check-expansion "\\f{\\noexpand\\o}" "O}" :setup ((setup expander))
                     :errors ("Forbidden control sequence found"))))

(define-test undefined-control-sequences
  :parent expansion
  (check-expansion "\\undefined x" "x" :errors ("Undefined control sequence")))

(define-test macro-tail-calls-keep-the-stack-flat
  :parent expansion
  ;; \m expands to \ma, \ma to \maa, ... 500 times.
  (let ((expander (make-test-expander "\\m")))
    (flet ((name (i) (concatenate 'string "m" (make-string i :initial-element #\a))))
      (loop for i from 0 below 500
            do (define-test-macro expander (name i) ""
                                  (concatenate 'string "\\" (name (1+ i)))))
      (define-test-macro expander (name 500) "" "x"))
    (let ((token (expand:get-x-token expander)))
      (is = (char-code #\x) (character-token-code token))
      (true (<= (input-depth (expand:expander-input expander)) 2)))))

;;; Expandable primitives

(define-test expandafter-and-noexpand
  :parent expansion
  (flet ((setup (e) (define-test-macro e "a" "" "A")))
    (check-expansion "\\expandafter\\string\\a" "A" :setup ((setup expander)))
    (check-expansion "\\string\\a" "\\a" :setup ((setup expander)))
    (check-expansion "\\expandafter\\expandafter\\expandafter\\string\\a" "A"
                     :setup ((setup expander)))
    ;; A \noexpand-ed token comes out unexpanded, meaning \relax.
    (let ((expander (make-test-expander "\\noexpand\\a\\noexpand x\\a")))
      (setup expander)
      (multiple-value-bind (token meaning) (expand:get-x-token expander)
        (is string= "a" (control-sequence-name (cs-token-control-sequence token)))
        (is eq (expand:dont-expand-meaning) meaning)
        (true (expand:meaning= meaning (expand:find-primitive "relax"))))
      (is = (char-code #\x) (character-token-code (expand:get-x-token expander)))
      (is = (char-code #\A) (character-token-code (expand:get-x-token expander))))
    ;; \noexpand on an undefined name is no error.
    (check-expansion "\\noexpand\\nothing" "\\nothing ")))

(define-test csname
  :parent expansion
  (check-expansion "\\csname a\\endcsname" "A"
                   :setup ((define-test-macro expander "a" "" "A")))
  (check-expansion "\\csname a\\b\\endcsname" "A"
                   :setup ((define-test-macro expander "ax b" "" "A")
                           (define-test-macro expander "b" "" "x b")))
  (check-expansion "\\csname zz\\endcsname" "\\zz ")
  (check-expansion "\\csname a\\relax" "A\\relax "
                   :setup ((define-test-macro expander "a" "" "A"))
                   :errors ("Missing \\endcsname inserted"))
  ;; An undefined name becomes \relax locally, whatever \globaldefs says.
  (let* ((expander (make-test-expander "\\csname zz\\endcsname"))
         (state (expand:expander-state expander))
         (zz (intern-control-sequence (expand:es-tex state) "zz")))
    (expand:set-parameter state :globaldefs 1)
    (begin-group (expand:es-tex state))
    (expansion-of expander)
    (is eq (expand:find-primitive "relax") (expand:meaning state zz))
    (end-group (expand:es-tex state))
    (is eq nil (expand:meaning state zz))))

(defun expansion-tokens (expander)
  (loop for token = (expand:get-x-token expander) while token collect token))

(define-test string-primitive
  :parent expansion
  (check-expansion "\\string\\foo" "\\foo")
  (check-expansion "\\string~" "~")
  (check-expansion "\\string a" "a")
  (check-expansion "\\string\\ x" "\\ x")
  ;; Trailing spaces are not part of a line: a final \ is \csname\endcsname.
  (check-expansion "\\string\\ " "\\csname\\endcsname")
  (check-expansion "\\expandafter\\string\\csname\\endcsname" "\\csname\\endcsname")
  (check-expansion "\\string\\foo" "foo"
                   :setup ((expand:set-parameter (expand:expander-state expander)
                                                 :escapechar -1)))
  (check-expansion "\\string\\foo" "/foo"
                   :setup ((expand:set-parameter (expand:expander-state expander)
                                                 :escapechar (char-code #\/))))
  ;; Category 12, except spaces (10).
  (let ((tokens (expansion-tokens (make-test-expander "\\string\\ab\\string\\ x"))))
    (is equal (list +other+ +other+ +other+ +other+ +space+ +letter+)
        (mapcar #'character-token-catcode tokens))))

(define-test meaning-primitive
  :parent expansion
  (let ((state nil))
    (flet ((meaning-of (text &rest setup)
             (let ((expander (make-test-expander (concatenate 'string "\\meaning" text))))
               (setf state (expand:expander-state expander))
               (dolist (function setup) (funcall function expander))
               (values (expansion-of expander))))
           (cs (name) (intern-control-sequence (expand:es-tex state) name)))
      (is string= "macro:#1#2->x#1y##"
          (meaning-of "\\a" (lambda (e) (define-test-macro e "a" "#1#2" "x#1y##"))))
      (is string= "macro:#1.#2->\\b #2"
          (meaning-of "\\a" (lambda (e) (define-test-macro e "a" "#1.#2" "\\b #2"))))
      (is string= "\\long\\outer macro:->"
          (meaning-of "\\a" (lambda (e) (define-test-macro e "a" "" "" :long t :outer t))))
      (is string= "\\long macro:->\\x "
          (meaning-of "\\a" (lambda (e) (define-test-macro e "a" "" "\\x" :long t))))
      (is string= "\\outer macro:->a\\b "
          (meaning-of "\\a" (lambda (e) (define-test-macro e "a" "" "a\\b" :outer t))))
      ;; The space after a one-letter name depends on its catcode.
      (is string= "macro:->\\x \\1"
          (meaning-of "\\a" (lambda (e) (define-test-macro e "a" "" "\\x\\1"))))
      (is string= "the letter a" (meaning-of " a"))
      (is string= "the character 1" (meaning-of " 1"))
      (is string= "begin-group character {" (meaning-of "{"))
      (is string= "math shift character $" (meaning-of "$"))
      (is string= "undefined" (meaning-of "\\undefined"))
      (is string= "\\relax" (meaning-of "\\relax"))
      (is string= "\\count" (meaning-of "\\count"))
      (is string= "\\topmark:" (meaning-of "\\topmark"))
      (is string= "select font nullfont" (meaning-of "\\nullfont"))
      (is string= "\\char\"41"
          (meaning-of "\\x" (lambda (e)
                              (expand:set-meaning (expand:expander-state e) (cs "x")
                                                  (expand:make-shorthand :char 65)))))
      (is string= "\\mathchar\"7161"
          (meaning-of "\\x" (lambda (e)
                              (expand:set-meaning (expand:expander-state e) (cs "x")
                                                  (expand:make-shorthand :mathchar #x7161)))))
      (is string= "\\count12"
          (meaning-of "\\x" (lambda (e)
                              (expand:set-meaning (expand:expander-state e) (cs "x")
                                                  (expand:make-shorthand :count 12)))))
      (is string= "end-group character }"
          (meaning-of "\\x" (lambda (e)
                              (expand:set-meaning (expand:expander-state e) (cs "x")
                                                  (expand:make-character-meaning
                                                   125 +end-group+)))))
      (is string= "select font cmr10 at 12.0pt"
          (meaning-of "\\x" (lambda (e)
                              (let ((state (expand:expander-state e)))
                                (expand:set-meaning
                                 state (cs "x")
                                 (expand:load-font state "cmr10"
                                                   :size (list :at (* 12 expand:+unity+)))))))))))

(define-test jobname
  :parent expansion
  (let ((expander (make-test-expander "\\jobname" )))
    (is string= "main" (expansion-of expander))))

(define-test input-and-endinput
  :parent expansion
  (check-expansion "\\input sub A" "BA" :files (list (cons "sub" "B")))
  (check-expansion "\\input sub\\relax A" "B\\relax A" :files (list (cons "sub" "B")))
  (check-expansion "\\input  \\name\\space A" "BA"
                   :files (list (cons "sub" "B"))
                   :setup ((define-test-macro expander "name" "" "sub")
                           (expand:set-meaning (expand:expander-state expander)
                                               (intern-control-sequence
                                                (expand:es-tex (expand:expander-state expander))
                                                "space")
                                               (expand:make-character-meaning 32 +space+))))
  ;; \endinput ends the file after the current line.
  (check-expansion "\\input sub A" "BCA"
                   :files (list (cons "sub" (format nil "B\\endinput C~%D"))))
  (let ((expander (make-test-expander "\\input nosuchfile ")))
    (fail (expansion-of expander) 'expand:tex-fatal-error)))
