;;;; tests/expand/state.lisp
;;;;
;;;; The expander state (src/expand/state.lisp, meaning.lisp, font.lisp,
;;;; parameters.lisp): INITEX defaults, grouping of every table through the
;;;; reader's save stack, \globaldefs, meanings and fonts.

(in-package #:cl-ansi-spec/tests)

(define-test expander-state
  :parent cl-ansi-spec
  :description "Meanings, registers, parameters, codes and fonts.")

(defun cs (state name)
  "The control sequence NAME of the reader state under STATE."
  (intern-control-sequence (expand:es-tex state) name))

(defun letter-token (char)
  (make-character-token (char-code char) +letter+ nil))

(define-test parameter-inventory
  :parent expander-state
  ;; TeX82 has 55 integer, 21 dimen, 15 glue, 3 mu glue and 9 token
  ;; parameters (§§224, 230, 236, 247).
  (is equal '(55 21 15 3 9)
      (mapcar (lambda (kind) (length (expand:parameter-names kind)))
              '(:integer :dimen :glue :muglue :tokens)))
  (is eq :dimen (expand:parameter-kind :parindent))
  (is eq :muglue (expand:parameter-kind :thickmuskip))
  (false (expand:parameter-kind :parskipp)))

(define-test initex-defaults
  :parent expander-state
  (let ((state (expand:make-expander-state)))
    (is = 1000 (expand:parameter state :mag))
    (is = 10000 (expand:parameter state :tolerance))
    (is = 1 (expand:parameter state :hangafter))
    (is = 25 (expand:parameter state :maxdeadcycles))
    (is = 92 (expand:parameter state :escapechar))
    (is = 13 (expand:parameter state :endlinechar))
    (is = 13 (endlinechar (expand:es-tex state)))
    (is equal '(720 4 7 1776)
        (mapcar (lambda (name) (expand:parameter state name))
                '(:time :day :month :year)))
    (is = 0 (expand:parameter state :pretolerance))
    (is = 0 (expand:parameter state :hsize))
    (true (expand:glue= (expand:make-glue) (expand:parameter state :baselineskip)))
    (true (expand:glue-mu-p (expand:parameter state :medmuskip)))
    (is eq nil (expand:parameter state :everypar))
    (is = 0 (expand:register state :count 255))
    (is = 0 (expand:register state :dimen 0))
    (true (expand:glue-mu-p (expand:register state :muskip 3)))
    (is eq nil (expand:register state :box 0))
    (is eq nil (expand:meaning state (cs state "relax")))
    (is eq (expand:es-null-font state) (expand:current-font state))
    (is eq (expand:es-null-font state) (expand:family-font state 2 15))
    (is eq nil (expand:par-shape state))
    (fail (expand:parameter state :nosuchparameter))
    (fail (expand:register state :count 256))))

(define-test initex-codes
  :parent expander-state
  (let ((state (expand:make-expander-state)))
    (flet ((code (kind char)
             (expand:code state kind (if (characterp char) (char-code char) char))))
      (is = #x7141 (code :mathcode #\A))
      (is = #x7161 (code :mathcode #\a))
      (is = #x7030 (code :mathcode #\0))
      (is = (char-code #\+) (code :mathcode #\+))
      (is = 999 (code :sfcode #\Z))
      (is = 1000 (code :sfcode #\z))
      (is = 0 (code :delcode #\.))
      (is = -1 (code :delcode #\())
      (is = +letter+ (code :catcode #\q))
      (is = (char-code #\q) (code :lccode #\Q))
      (is = (char-code #\Q) (code :uccode #\q))
      ;; Codes beyond 255 follow the same rules.
      (is = 1000 (code :sfcode 955))
      (is = 955 (code :mathcode 955)))))

(define-test grouping-restores-every-table
  :parent expander-state
  (let* ((state (expand:make-expander-state))
         (tex (expand:es-tex state))
         (relax (cs state "relax"))
         (font (expand:load-font state "cmr10" :identifier "tenrm"))
         (skip (expand:make-glue :width 1 :stretch 2 :stretch-order 1)))
    (flet ((snapshot ()
             (list (expand:meaning state relax)
                   (expand:register state :count 1)
                   (expand:register state :dimen 2)
                   (expand:register state :skip 3)
                   (expand:register state :toks 4)
                   (expand:register state :box 5)
                   (expand:parameter state :tolerance)
                   (expand:parameter state :hsize)
                   (expand:parameter state :parskip)
                   (expand:parameter state :everypar)
                   (expand:code state :mathcode 65)
                   (expand:code state :catcode 64)
                   (expand:current-font state)
                   (expand:family-font state 1 3)
                   (expand:par-shape state))))
      (let ((before (snapshot)))
        (begin-group tex)
        (expand:set-meaning state relax (expand:make-primitive "relax"))
        (expand:set-register state :count 1 7)
        (expand:set-register state :dimen 2 8)
        (expand:set-register state :skip 3 skip)
        (expand:set-register state :toks 4 (list (letter-token #\a)))
        (expand:set-register state :box 5 :some-box)
        (expand:set-parameter state :tolerance 200)
        (expand:set-parameter state :hsize 300)
        (expand:set-parameter state :parskip skip)
        (expand:set-parameter state :everypar (list (letter-token #\b)))
        (expand:set-code state :mathcode 65 #x8000)
        (expand:set-code state :catcode 64 +letter+)
        (expand:set-current-font state font)
        (expand:set-family-font state 1 3 font)
        (expand:set-par-shape state '((0 . 100)))
        (true (notany #'eql before (snapshot)) "every value changed in the group")
        (end-group tex)
        (is equal before (snapshot))))))

(define-test global-assignments-and-globaldefs
  :parent expander-state
  (let* ((state (expand:make-expander-state))
         (tex (expand:es-tex state)))
    ;; \global inside a group survives it.
    (begin-group tex)
    (expand:set-register state :count 0 5 :global t)
    (end-group tex)
    (is = 5 (expand:register state :count 0))
    ;; A local assignment after a global one in the same group restores
    ;; the global value.
    (begin-group tex)
    (expand:set-register state :count 0 6 :global t)
    (expand:set-register state :count 0 7)
    (end-group tex)
    (is = 6 (expand:register state :count 0))
    ;; \globaldefs > 0: every assignment global.
    (begin-group tex)
    (expand:set-parameter state :globaldefs 1)
    (expand:set-register state :dimen 0 9)
    (expand:set-code state :sfcode 65 1)
    (end-group tex)
    (is = 9 (expand:register state :dimen 0))
    (is = 1 (expand:code state :sfcode 65))
    ;; ... but not the \globaldefs assignment itself: \globaldefs was 0
    ;; when it was made (§1214 looks before assigning).
    (is = 0 (expand:parameter state :globaldefs))
    ;; \globaldefs < 0: \global is ignored.
    (expand:set-parameter state :globaldefs -1)
    (begin-group tex)
    (expand:set-register state :dimen 0 10 :global t)
    (end-group tex)
    (is = 9 (expand:register state :dimen 0))))

(define-test register-values-are-checked
  :parent expander-state
  (let ((state (expand:make-expander-state)))
    (fail (expand:set-register state :count 0 (expt 2 31)))
    (fail (expand:set-register state :skip 0 (expand:make-glue :mu-p t)))
    (fail (expand:set-register state :muskip 0 (expand:make-glue)))
    (fail (expand:set-register state :dimen 0 (expand:make-glue)))
    (fail (expand:set-parameter state :thinmuskip (expand:make-glue)))
    (fail (expand:set-register state :frob 0 0))
    (fail (expand:set-meaning state (cs state "x") 42))))

(define-test meaning-equality
  :parent expander-state
  (let* ((state (expand:make-expander-state))
         (a (letter-token #\a))
         (a-elsewhere (make-character-token (char-code #\a) +letter+
                                            (make-span "x.tex" 0 1 1 0)))
         (body (list a 1))
         (macro (expand:make-macro (list 1) body)))
    (true (expand:meaning= nil nil))
    (false (expand:meaning= nil macro))
    (true (expand:meaning= macro (expand:make-macro (list 1) (list a-elsewhere 1))))
    (false (expand:meaning= macro (expand:make-macro (list 1) body :long-p t)))
    (false (expand:meaning= macro (expand:make-macro (list 1) body :outer-p t)))
    (false (expand:meaning= macro (expand:make-macro (list 1 :brace) body)))
    (false (expand:meaning= macro (expand:make-macro (list 1) (list a 2))))
    (true (expand:meaning= (expand:make-primitive "relax")
                           (expand:make-primitive "relax")))
    (false (expand:meaning= (expand:make-primitive "relax")
                            (expand:make-primitive "par")))
    (true (expand:meaning= (expand:make-character-meaning 123 +begin-group+)
                           (expand:make-character-meaning 123 +begin-group+)))
    (false (expand:meaning= (expand:make-character-meaning 123 +begin-group+)
                            (expand:make-character-meaning 123 +other+)))
    (true (expand:meaning= (expand:make-shorthand :count 5)
                           (expand:make-shorthand :count 5)))
    (false (expand:meaning= (expand:make-shorthand :count 5)
                            (expand:make-shorthand :dimen 5)))
    (false (expand:meaning= (expand:make-shorthand :char 65)
                            (expand:make-character-meaning 65 +letter+)))
    ;; Fonts compare by identity: two loads of one font are one font.
    (let ((font (expand:load-font state "cmr10")))
      (true (expand:meaning= font (expand:load-font state "cmr10"
                                                    :size '(:scaled 1000))))
      (false (expand:meaning= font (expand:load-font state "cmr10"
                                                     :size '(:at 655360)))))
    ;; \let shares the meaning: both names then compare equal.
    (expand:set-meaning state (cs state "a") macro)
    (expand:set-meaning state (cs state "b") (expand:meaning state (cs state "a")))
    (is eq macro (expand:meaning state (cs state "b")))
    ;; Active characters have meanings too.
    (let ((tilde (intern-active-character (expand:es-tex state) (char-code #\~))))
      (expand:set-meaning state tilde macro)
      (is eq macro (expand:meaning state tilde))
      (is eq nil (expand:meaning state (cs state "~"))))))

(define-test fonts
  :parent expander-state
  (let* ((state (expand:make-expander-state))
         (tex (expand:es-tex state)))
    (expand:set-parameter state :defaulthyphenchar 45)
    (let ((font (expand:load-font state "cmr10" :identifier "tenrm")))
      (is string= "tenrm" (expand:tex-font-identifier font))
      (is = 45 (expand:tex-font-hyphen-char font))
      (is = 0 (expand:tex-font-skew-char font))
      (is = 0 (expand:font-dimen font 6))
      ;; \fontdimen assignments are global, even inside a group.
      (begin-group tex)
      (expand:set-font-dimen font 6 (* 10 expand:+unity+))
      (end-group tex)
      (is = (* 10 expand:+unity+) (expand:font-dimen font 6))
      (is = 0 (expand:font-dimen font 5))
      (is = 0 (expand:font-dimen font 7))
      ;; A second \font of the same file and size is the same font.
      (is eq font (expand:load-font state "cmr10" :identifier "rm"))
      (true (not (eq font (expand:load-font state "cmr10" :size '(:at 1)))))
      (fail (expand:font-dimen font 0)))))
