;;;; tests/tex/input-stack.lisp

(in-package #:cl-ansi-spec/tests)

(define-test input-stack
  :parent cl-ansi-spec
  :description "TeX's input stack: files, token lists, back-input.")

(defun alist-resolver (files)
  "Return a resolver serving FILES, an alist of (name . text)."
  (lambda (name)
    (let ((entry (assoc name files :test #'string=)))
      (and entry (make-line-source name (cdr entry))))))

(defun texts (tokens)
  (mapcar #'token-text tokens))

(define-test empty-stack-has-no-tokens
  :parent input-stack
  (let ((stack (make-input-stack (make-plain-state))))
    (is eq nil (next-token stack))
    (is eq nil (peek-token stack))
    (is = 0 (input-depth stack))))

(define-test nested-files
  :parent input-stack
  (let ((stack (make-input-stack (make-plain-state)
                                 :resolver (alist-resolver
                                            '(("outer.tex" . "a")
                                              ("inner.tex" . "b"))))))
    (push-file stack "outer.tex")
    (is equal "outer.tex" (current-file-name stack))
    (is equal "a 11" (token-text (next-token stack)))
    (push-file stack "inner.tex")
    (is equal "inner.tex" (current-file-name stack))
    (is equal '("b 11" "  10" "  10") (texts (read-all stack)))
    (is = 0 (input-depth stack))
    (is eq nil (current-file-name stack))))

(define-test end-of-input-is-sticky
  :parent input-stack
  (let ((stack (string-stack "a")))
    (read-all stack)
    (is eq nil (next-token stack))
    (is eq nil (next-token stack))
    (is eq nil (peek-token stack))))

(define-test skips-follow-file-order-across-files
  :parent input-stack
  (let* ((events '())
         (state (make-plain-state))
         (stack (make-input-stack
                 state
                 :resolver (alist-resolver '(("outer.tex" . "a % x
b")
                                             ("inner.tex" . "c%y
")))
                 :skip-hook (lambda (kind span)
                              (push (list kind (span-file span) (span-start span))
                                    events)))))
    (set-endlinechar state -1)
    (push-file stack "outer.tex")
    (next-token stack)                  ; a
    (push-file stack "inner.tex")
    (read-all stack)
    ;; Outer's space after "a" is a token: it is read after inner ends.
    (is equal '((:comment "inner.tex" 1) (:line-end "inner.tex" 3)
                (:comment "outer.tex" 2) (:line-end "outer.tex" 5))
        (reverse events))))

(define-test back-input-keeps-exhausted-files
  :parent input-stack
  (let ((stack (make-input-stack (make-plain-state)
                                 :resolver (alist-resolver
                                            '(("outer.tex" . "a")
                                              ("inner.tex" . "b"))))))
    (push-file stack "outer.tex")
    (push-file stack "inner.tex")
    (let ((b (next-token stack)))
      (next-token stack)                ; inner's end-of-line space
      (back-input stack b)
      (is = 3 (input-depth stack))
      (is equal '("b 11" "a 11" "  10") (texts (read-all stack))))))

(define-test unsafe-names-are-not-resolved
  :parent input-stack
  (let ((resolver (directory-resolver (spec-directory))))
    (false (funcall resolver "/etc/passwd"))
    (false (funcall resolver "../SHA256SUMS"))
    (false (funcall resolver ""))
    (true (funcall resolver "chap-1"))))

(define-test missing-files-are-signalled
  :parent input-stack
  (let ((stack (make-input-stack (make-plain-state)
                                 :resolver (alist-resolver '()))))
    (fail (push-file stack "nothing.tex") 'input-file-missing)))

(define-test spec-files-are-resolved-with-default-type
  :parent input-stack
  (let ((stack (make-input-stack (make-plain-state))))
    (push-file stack "chap-0")
    (is equal "chap-0.tex" (current-file-name stack))
    (true (next-token stack))
    (push-file stack "setup.tex")
    (is equal "setup.tex" (current-file-name stack))
    (push-file stack "hyphen")
    (is equal "hyphen.tex" (current-file-name stack))))

(define-test token-lists-are-read-before-files
  :parent input-stack
  (let ((stack (string-stack "c")))
    (push-tokens stack (list (make-character-token (char-code #\a) +letter+)
                             (make-character-token (char-code #\b) +other+)))
    (is equal '("a 11" "b 12" "c 11" "  10") (texts (read-all stack)))))

(define-test back-input-and-peek
  :parent input-stack
  (let ((stack (string-stack "ab")))
    (let ((a (next-token stack)))
      (is equal "b 11" (token-text (peek-token stack)))
      (is equal "b 11" (token-text (peek-token stack)))
      (back-input stack a)
      (is equal '("a 11" "b 11" "  10") (texts (read-all stack))))))

(define-test back-input-removes-exhausted-token-lists
  :parent input-stack
  (let ((stack (string-stack "")))
    (push-tokens stack (list (make-character-token (char-code #\x) +letter+)))
    (let ((x (next-token stack)))
      (is = 2 (input-depth stack))       ; exhausted list still on the stack
      (back-input stack x)
      (is = 2 (input-depth stack))       ; ... replaced by the backed-up level
      (is equal '("x 11") (texts (read-all stack))))))

(define-test pushed-token-lists-are-copied
  :parent input-stack
  (let* ((stack (string-stack ""))
         (list (list (make-character-token (char-code #\x) +letter+))))
    (push-tokens stack list)
    (read-all stack)
    (is = 1 (length list))))
