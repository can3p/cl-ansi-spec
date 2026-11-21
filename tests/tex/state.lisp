;;;; tests/tex/state.lisp

(in-package #:cl-ansi-spec/tests)

(define-test tex-state
  :parent cl-ansi-spec
  :description "Equivalents, initial category codes and the save stack.")

(defun code (designator)
  "Return the character code of DESIGNATOR, a character or an integer."
  (if (characterp designator) (char-code designator) designator))

(define-test initex-catcodes
  :parent tex-state
  (let ((state (make-initex-state)))
    (loop for (char catcode) in `((#\\ ,+escape+) (#\% ,+comment+)
                                  (127 ,+invalid+) (0 ,+ignored+)
                                  (13 ,+end-of-line+) (#\Space ,+space+)
                                  (#\A ,+letter+) (#\z ,+letter+)
                                  (#\{ ,+other+) (#\~ ,+other+) (#\@ ,+other+)
                                  (9 ,+other+) (#\0 ,+other+) (255 ,+other+)
                                  (956 ,+other+))
          do (is = catcode (catcode state (code char))
                 "catcode of ~S" char))
    (is = 13 (endlinechar state))
    (is = (code #\a) (lccode state (code #\A)))
    (is = (code #\A) (uccode state (code #\a)))
    (is = 0 (lccode state (code #\1)))
    (is = 0 (group-level state))))

(define-test plain-catcodes
  :parent tex-state
  (let ((state (make-plain-state)))
    (loop for (char catcode) in `((#\\ ,+escape+) (#\{ ,+begin-group+)
                                  (#\} ,+end-group+) (#\$ ,+math-shift+)
                                  (#\& ,+alignment-tab+) (13 ,+end-of-line+)
                                  (#\# ,+parameter+) (#\^ ,+superscript+)
                                  (11 ,+superscript+) (#\_ ,+subscript+)
                                  (1 ,+subscript+) (0 ,+ignored+)
                                  (9 ,+space+) (#\Space ,+space+)
                                  (#\q ,+letter+) (#\~ ,+active+)
                                  (12 ,+active+) (#\% ,+comment+)
                                  (127 ,+invalid+) (#\@ ,+other+)
                                  (#\| ,+other+))
          do (is = catcode (catcode state (code char))
                 "catcode of ~S" char))))

(define-test catcode-names
  :parent tex-state
  (is eq :escape (catcode-name +escape+))
  (is eq :invalid (catcode-name +invalid+)))

(define-test local-assignment-is-undone
  :parent tex-state
  (let ((state (make-plain-state)))
    (begin-group state)
    (set-catcode state (code #\|) +active+)
    (is = +active+ (catcode state (code #\|)))
    (is = 1 (group-level state))
    (end-group state)
    (is = +other+ (catcode state (code #\|)))
    (is = 0 (group-level state))))

(define-test nested-groups
  :parent tex-state
  (let ((state (make-plain-state))
        (bar (code #\|)))
    (set-catcode state bar 1)
    (begin-group state)
    (set-catcode state bar 2)
    (set-catcode state bar 3)            ; same level: no second save
    (begin-group state)
    (set-catcode state bar 4)
    (end-group state)
    (is = 3 (catcode state bar))
    (end-group state)
    (is = 1 (catcode state bar))
    (is eq nil (cl-ansi-spec/tex::state-save-stack state))))

(define-test global-assignment-survives-groups
  :parent tex-state
  (let ((state (make-plain-state))
        (bar (code #\|)))
    (begin-group state)
    (begin-group state)
    (set-catcode state bar 4)
    (set-catcode state bar +active+ :global t)
    (end-group state)
    (is = +active+ (catcode state bar))
    (end-group state)
    (is = +active+ (catcode state bar))))

(define-test local-after-global-restores-global
  :parent tex-state
  (let ((state (make-plain-state))
        (bar (code #\|)))
    (begin-group state)
    (set-catcode state bar 2 :global t)
    (begin-group state)
    (set-catcode state bar 3)
    (end-group state)
    (is = 2 (catcode state bar))
    (set-catcode state bar 4)
    (end-group state)
    (is = 2 (catcode state bar))))

(define-test outermost-local-assignment-is-permanent
  :parent tex-state
  (let ((state (make-plain-state)))
    (set-catcode state (code #\|) +active+)
    (is eq nil (cl-ansi-spec/tex::state-save-stack state))
    (begin-group state)
    (end-group state)
    (is = +active+ (catcode state (code #\|)))))

(define-test parameters-and-overflow-codes-are-grouped
  :parent tex-state
  (let ((state (make-plain-state)))
    (begin-group state)
    (set-endlinechar state -1)
    (set-catcode state 956 +letter+)
    (set-lccode state 956 956)
    (is = -1 (endlinechar state))
    (is = +letter+ (catcode state 956))
    (end-group state)
    (is = 13 (endlinechar state))
    (is = +other+ (catcode state 956))
    (is = 0 (lccode state 956))))

(define-test group-kinds-are-returned
  :parent tex-state
  (let ((state (make-plain-state)))
    (begin-group state :simple)
    (begin-group state :semi-simple)
    (is eq :semi-simple (end-group state))
    (is eq :simple (end-group state))))

(define-test group-underflow-is-signalled
  :parent tex-state
  (fail (end-group (make-plain-state)) 'group-underflow))

(define-test invalid-assignments-are-rejected
  :parent tex-state
  (let ((state (make-plain-state)))
    (fail (set-catcode state (code #\a) 16) 'type-error)
    (fail (set-catcode state -1 +letter+) 'type-error)
    (fail (set-lccode state (code #\a) -5) 'type-error)))
