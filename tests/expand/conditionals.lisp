;;;; tests/expand/conditionals.lisp
;;;;
;;;; Conditionals (src/expand/conditionals.lisp): every TeX82 test, the
;;;; condition stack, skipping of nested conditionals, \ifcase, and \fi,
;;;; \else and \or with TeX's errors and recovery (TeX: The Program,
;;;; §§487-510; TeXbook, chapter 20).

(in-package #:cl-ansi-spec/tests)

(define-test conditionals
  :parent cl-ansi-spec
  :description "\\if... tests, skipping and the condition stack.")

(defun let-character (expander name char catcode)
  "Give \\NAME the meaning of the character CHAR of CATCODE, as \\let."
  (expand:set-meaning (state-of expander) (cs (state-of expander) name)
                      (expand:make-character-meaning (char-code char) catcode)))

(defun set-mode (expander mode)
  (setf (expand:list-state-mode (expand:current-list expander)) mode))

(define-test branches-and-nesting
  :parent conditionals
  (check-expansion "\\iftrue a\\else b\\fi c" "ac")
  (check-expansion "\\iffalse a\\else b\\fi c" "bc")
  (check-expansion "\\iffalse a\\fi c" "c")
  (check-expansion "\\iffalse \\iftrue a\\else b\\fi c\\else d\\fi" "d")
  (check-expansion "\\iftrue a\\else \\iffalse\\fi b\\fi c" "ac")
  (check-expansion "\\iftrue\\iffalse a\\else b\\fi\\else c\\fi d" "bd")
  ;; A conditional opened by the test is closed on the way.
  (check-expansion "\\ifnum\\iftrue 1\\else 2\\fi=1 a\\fi" "a")
  (check-expansion "\\ifnum\\iffalse 2\\else 1\\fi=1 a\\fi" "a")
  (let ((expander (make-test-expander "\\iftrue\\iffalse\\else")))
    (expansion-of expander)
    (is equal '("iffalse" "iftrue")
        (mapcar #'expand:conditional-kind (expand:expander-conditionals expander)))
    (is eq :fi (expand:if-limit expander))))

(define-test ifcase
  :parent conditionals
  (check-expansion "\\ifcase 0 a\\or b\\fi" "a")
  (check-expansion "\\ifcase 2 a\\or b\\or c\\else d\\fi" "c")
  (check-expansion "\\ifcase 5 a\\or b\\else d\\fi" "d")
  (check-expansion "\\ifcase 5 a\\or b\\fi c" "c")
  (check-expansion "\\ifcase -1 a\\or b\\fi c" "c")
  (check-expansion "\\ifcase 1 a\\or b\\else c\\fi" "b")
  ;; Only the \or of this \ifcase counts.
  (check-expansion "\\ifcase 1 \\ifcase 0 x\\or y\\fi\\or z\\fi" "z")
  (check-expansion "\\ifcase 1 \\iffalse\\or\\fi\\or z\\fi" "z"))

(define-test relations
  :parent conditionals
  (check-expansion "\\ifnum 1<2 a\\fi" "a")
  (check-expansion "\\ifnum 3 = 3 a\\fi" "a")
  (check-expansion "\\ifnum 3>3 a\\else b\\fi" "b")
  (check-expansion "\\ifnum 1 2 a\\else b\\fi" "b" :errors ("Missing = inserted for"))
  (check-expansion "\\ifdim 1in>72pt a\\fi" "a")
  (check-expansion "\\ifdim 1pt=65536sp a\\fi" "a")
  (check-expansion "\\ifdim -1pt<0pt a\\fi" "a")
  (check-expansion "\\ifodd 3 a\\fi" "a")
  (check-expansion "\\ifodd -3 a\\fi" "a")
  (check-expansion "\\ifodd 0 a\\else b\\fi" "b"))

(define-test character-tests
  :parent conditionals
  (check-expansion "\\if aax\\fi" "x")
  (check-expansion "\\if aa x\\fi" " x")
  (check-expansion "\\if ab x\\else y\\fi" "y")
  (check-expansion "\\if a\\relax x\\else y\\fi" "y")
  (check-expansion "\\if\\relax\\relax x\\fi" "x")
  (check-expansion "\\if\\relax\\par x\\fi" "x")
  (check-expansion "\\ifcat abx\\fi" "x")
  (check-expansion "\\ifcat a1x\\else y\\fi" "y")
  (check-expansion "\\ifcat{\\bgroup x\\fi" "x"
                   :setup ((let-character expander "bgroup" #\{ +begin-group+)))
  (check-expansion "\\if\\x ay\\fi" "y"
                   :setup ((let-character expander "x" #\a +letter+)))
  ;; The test expands: \m gives `ab'.
  (check-expansion "\\if\\m x\\else y\\fi" "y"
                   :setup ((define-test-macro expander "m" "" "ab")))
  ;; A \noexpand-ed active character is that character, category 13.
  (check-expansion "\\if\\noexpand~\\noexpand~x\\fi" "x")
  (check-expansion "\\ifcat\\noexpand~\\noexpand~x\\fi" "x")
  (check-expansion "\\ifcat\\noexpand\\m\\relax x\\fi" "x"
                   :setup ((define-test-macro expander "m" "" "ab"))))

(define-test ifx
  :parent conditionals
  (check-expansion "\\ifx aax\\fi" "x")
  (check-expansion "\\ifx ab x\\else y\\fi" "y")
  (check-expansion "\\ifx a1x\\else y\\fi" "y")
  (check-expansion "\\ifx\\undefined\\alsoundefined x\\fi" "x")
  (check-expansion "\\ifx\\relax\\relax x\\fi" "x")
  (check-expansion "\\ifx\\relax\\par x\\else y\\fi" "y")
  (check-expansion "\\ifx\\x ay\\fi" "y"
                   :setup ((let-character expander "x" #\a +letter+)))
  (check-expansion "\\ifx\\a\\b x\\fi" "x"
                   :setup ((define-test-macro expander "a" "#1" "X#1")
                           (define-test-macro expander "b" "#1" "X#1")))
  (check-expansion "\\ifx\\a\\b x\\else y\\fi" "y"
                   :setup ((define-test-macro expander "a" "#1" "X#1")
                           (define-test-macro expander "b" "#1" "X#1" :long t)))
  (check-expansion "\\ifx\\a\\b x\\else y\\fi" "y"
                   :setup ((define-test-macro expander "a" "#1" "X#1")
                           (define-test-macro expander "b" "#1." "X#1")))
  ;; \outer macros may be compared.
  (check-expansion "\\ifx\\o\\o x\\fi" "x"
                   :setup ((define-test-macro expander "o" "" "O" :outer t)))
  ;; A \noexpand-ed macro is not \relax for \ifx (§507).
  (check-expansion "\\expandafter\\ifx\\noexpand\\a\\relax x\\else y\\fi" "y"
                   :setup ((define-test-macro expander "a" "" "A"))))

(define-test mode-and-box-tests
  :parent conditionals
  (check-expansion "\\ifvmode a\\fi\\ifhmode b\\fi\\ifmmode c\\fi\\ifinner d\\fi" "a")
  (check-expansion "\\ifvmode a\\fi\\ifhmode b\\fi\\ifmmode c\\fi\\ifinner d\\fi" "ad"
                   :setup ((set-mode expander :internal-vertical)))
  (check-expansion "\\ifvmode a\\fi\\ifhmode b\\fi\\ifmmode c\\fi\\ifinner d\\fi" "bd"
                   :setup ((set-mode expander :restricted-horizontal)))
  (check-expansion "\\ifvmode a\\fi\\ifhmode b\\fi\\ifmmode c\\fi\\ifinner d\\fi" "cd"
                   :setup ((set-mode expander :math)))
  (check-expansion "\\ifvmode a\\fi\\ifhmode b\\fi\\ifmmode c\\fi\\ifinner d\\fi" "c"
                   :setup ((set-mode expander :display-math)))
  (check-expansion "\\ifvmode a\\fi\\ifhmode b\\fi\\ifmmode c\\fi\\ifinner d\\fi" ""
                   :setup ((set-mode expander :none)))
  (check-expansion "\\ifvoid0 a\\fi\\ifhbox0 b\\fi\\ifvbox0 c\\fi" "a")
  (check-expansion "\\ifvoid256 a\\fi" "a" :errors ("Bad register code"))
  (check-expansion "\\ifeof3 a\\fi" "a")
  (check-expansion "\\ifeof3 a\\else b\\fi" "b"
                   :setup ((setf (aref (expand:expander-read-streams expander) 3) :open)))
  (check-expansion "\\ifeof16 a\\fi" "a" :errors ("Bad number")))

(define-test fi-else-or-recovery
  :parent conditionals
  (check-expansion "a\\fi b" "ab" :errors ("Extra"))
  (check-expansion "a\\else b" "ab" :errors ("Extra"))
  (check-expansion "\\iftrue a\\or b\\fi c" "abc" :errors ("Extra"))
  (check-expansion "\\iffalse a\\or b\\else c\\fi" "c" :errors ("Extra"))
  (check-expansion "\\iftrue a\\else b\\fi\\fi" "a" :errors ("Extra"))
  ;; \fi while the test is read: \relax is inserted before it.
  (check-expansion "\\ifnum 1=1\\fi a" "\\relax a")
  ;; ...and is then the second operand: the test is false and ends at
  ;; that \fi, so the \else and \fi after are extra.
  (check-expansion "\\if a\\fi x\\else y\\fi" "xy" :errors ("Extra" "Extra")))

(define-test incomplete-conditionals
  :parent conditionals
  ;; An \outer macro while skipping: a \fi is inserted before it.
  (check-expansion "\\iffalse \\o\\fi" "O" :errors ("Incomplete" "Extra")
                   :setup ((define-test-macro expander "o" "" "O" :outer t)))
  ;; The end of the file while skipping.
  (check-expansion "\\iffalse a" "" :errors ("Incomplete"))
  (let ((expander (make-test-expander (format nil "~%\\ifx ab~%c"))))
    (let ((contexts '()))
      (expand:call-recovering-tex-errors
       (lambda () (loop while (expand:get-x-token expander)))
       (lambda (condition) (push (expand:tex-error-context condition) contexts)))
      (is equal '("\\ifx; all text was ignored after line 2") contexts))))
