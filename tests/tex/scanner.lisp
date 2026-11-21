;;;; tests/tex/scanner.lisp
;;;;
;;;; The scanner, one TeXbook rule at a time, as token dumps: control
;;;; sequences as written, character tokens as "<char> <catcode>".

(in-package #:cl-ansi-spec/tests)

(define-test scanner
  :parent cl-ansi-spec
  :description "Tokenisation of lines (TeXbook chapters 7-8).")

(defun string-stack (text &key (state (make-plain-state)) skip-hook)
  "Return an input stack reading TEXT as the file \"test.tex\"."
  (let ((stack (make-input-stack state :skip-hook skip-hook)))
    (push-source stack (make-line-source "test.tex" text))
    stack))

(defun read-all (stack)
  "Read every remaining token of STACK."
  (loop for token = (next-token stack) while token collect token))

(defun dump (text &key (state (make-plain-state)))
  "Return the TOKEN-TEXT of every token of TEXT."
  (mapcar #'token-text (read-all (string-stack text :state state))))

(defun lines (&rest lines)
  "Join LINES with newlines."
  (format nil "~{~A~^~%~}" lines))

(defun is-dump (expected text &rest keys)
  "Check that TEXT is read as the tokens EXPECTED (see DUMP)."
  (is equal expected (apply #'dump text keys) "Tokens of ~S" text))

(define-test control-words-skip-following-spaces
  :parent scanner
  (is-dump '("\\foo" "b 11" "a 11" "r 11" "  10") "\\foo   bar")
  (is-dump '("\\foo" "\\bar") "\\foo\\bar"))

(define-test control-symbols
  :parent scanner
  (is-dump '("\\1" "  10" "x 11" "  10") "\\1 x")
  (is-dump '("\\ " "x 11" "  10") "\\    x")
  (is-dump '("\\{" "\\%" "\\^^M") "\\{\\%\\"))

(define-test character-categories
  :parent scanner
  (is-dump '("{ 1" "} 2" "$ 3" "& 4" "# 6" "^ 7" "_ 8" "a 11" "@ 12" "~" "  10")
           "{}$&#^_a@~"))

(define-test spaces-collapse-and-new-lines-skip-blanks
  :parent scanner
  (is-dump '("a 11" "  10" "b 11" "  10") "a   b")
  (is-dump '("a 11" "  10") "    a")
  (is-dump '("a 11" "  10" "b 11" "  10") (format nil "a~Cb" #\Tab)))

(define-test empty-lines-are-par
  :parent scanner
  (is-dump '("a 11" "  10" "\\par" "b 11" "  10") (lines "a" "" "b"))
  (is-dump '("a 11" "  10" "\\par" "\\par" "b 11" "  10")
           (lines "a" "   " "" "b")))

(define-test trailing-spaces-are-removed
  :parent scanner
  (is-dump '("\\foo" "a 11" "  10") (lines "\\foo   " "a")))

(define-test comments-swallow-the-line-end
  :parent scanner
  (is-dump '("a 11" "b 11" "  10") (lines "a% comment {" "b"))
  (is-dump '("a 11") "a%"))

(define-test ignored-and-invalid-characters
  :parent scanner
  (is-dump '("a 11" "b 11" "  10") (format nil "a~Cb" (code-char 0)))
  (fail (dump (format nil "a~Cb" (code-char 127))) 'invalid-character)
  (is equal '("a 11" "b 11" "  10")
      (handler-bind ((invalid-character #'continue))
        (dump (format nil "a~Cb" (code-char 127))))))

(define-test superscript-notation
  :parent scanner
  (is-dump '("A 11" "  10") "^^41")
  (is-dump '("^^A 8" "  10") "^^A")       ; code 65 - 64 = 1, a subscript
  (is-dump '("t 11" "A 11" "  10") "^^4A")  ; hex digits are lowercase only
  (is-dump '("\\foo" "x 11" "  10") "^^5cfoo x")
  (is-dump '("A 11" "  10") "^^5e^41")      ; reduced ^ starts another pair
  ;; "^^" at the end of a line pairs with the appended ^^M: 13 + 64 is M.
  (is-dump '("M 11") "^^"))

(define-test superscript-notation-in-names
  :parent scanner
  (is-dump '("\\abc") "\\a^^62c")
  (is-dump '("\\abc") "\\^^61bc")
  (is-dump '("\\^^M" "x 11" "  10") "\\^^Mx")
  (is-dump '("\\a" "^ 7" "  10") "\\a^^5e"))

(define-test end-of-line-character-discards-the-rest
  :parent scanner
  (is-dump '("a 11" "  10" "c 11" "  10") (lines "a^^Mb" "c"))
  (is-dump '("\\par" "c 11" "  10") (lines "^^Mb" "c")))

(define-test endlinechar
  :parent scanner
  (let ((state (make-plain-state)))
    (set-endlinechar state -1)
    (is-dump '("a 11" "b 11") (lines "a" "b") :state state)
    (is-dump '("\\") "\\" :state state))
  (let ((state (make-plain-state)))
    (set-endlinechar state (char-code #\!))
    (is-dump '("a 11" "! 12") "a" :state state)))

(define-test endlinechar-is-read-when-the-line-is
  :parent scanner
  (let* ((state (make-plain-state))
         (stack (string-stack (lines "a" "b" "c") :state state)))
    (is equal "a 11" (token-text (next-token stack)))
    (set-endlinechar state -1)
    (is equal '("  10" "b 11" "c 11") (mapcar #'token-text (read-all stack)))))

(define-test catcodes-are-read-when-the-token-is
  :parent scanner
  (let* ((state (make-plain-state))
         (stack (string-stack "a|b|" :state state)))
    (is equal "a 11" (token-text (next-token stack)))
    (set-catcode state (char-code #\|) +active+)
    (let ((bar (next-token stack)))
      (true (cs-token-p bar))
      (true (control-sequence-active-p (cs-token-control-sequence bar))))
    (is equal "b 11" (token-text (next-token stack)))
    (set-catcode state (char-code #\|) +other+)
    (is equal "| 12" (token-text (next-token stack)))))

(define-test control-sequences-are-interned
  :parent scanner
  (let* ((state (make-plain-state))
         (tokens (read-all (string-stack "\\foo\\foo~~\\par" :state state))))
    (true (token= (first tokens) (second tokens)))
    (true (token= (third tokens) (fourth tokens)))
    (is eq (intern-control-sequence state "par")
        (cs-token-control-sequence (fifth tokens)))
    (false (token= (first tokens) (third tokens)))
    (is eq (intern-active-character state (char-code #\~))
        (cs-token-control-sequence (third tokens)))
    (false (eq (intern-active-character state (char-code #\a))
               (intern-control-sequence state "a")))))

(define-test token-spans
  :parent scanner
  (let ((tokens (read-all (string-stack (lines "\\foo  x" "  ^^41")))))
    (is equal '((1 0 0 4) (1 6 6 7) (1 7 7 8) (2 2 10 14) (2 6 14 14))
        (mapcar (lambda (token)
                  (let ((span (token-span token)))
                    (list (span-line span) (span-column span)
                          (span-start span) (span-end span))))
                tokens))
    (is equal "test.tex" (span-file (token-span (first tokens))))))

(define-test spans-after-rewriting-names
  :parent scanner
  (flet ((spans (text)
           (mapcar (lambda (token)
                     (let ((span (token-span token)))
                       (list (token-text token) (span-start span) (span-end span)
                             (span-column span))))
                   (read-all (string-stack text)))))
    (is equal '(("\\abc" 0 7 0) ("d 11" 8 9 8) ("  10" 9 9 9))
        (spans "\\a^^62c d"))
    (is equal '(("x 11" 0 1 0) ("\\ab" 1 10 1) ("y 11" 11 12 11) ("  10" 12 12 12))
        (spans "x\\^^61^^62 y"))
    ;; ^^ at the end of a name pairs with the appended ^^M.
    (is equal '(("\\aM" 0 4 0)) (spans "\\a^^"))))

;;; Coverage: tokens and skipped input together cover every file exactly.

(defun coverage-gaps (name text)
  "Read TEXT as file NAME and return a description of the first place
where token and skip spans fail to tile it, or NIL if they tile it."
  (let ((spans '()))
    (let ((stack (string-stack text :skip-hook (lambda (kind span)
                                                 (declare (ignore kind))
                                                 (push span spans)))))
      (loop for token = (next-token stack)
            while token
            do (push (token-span token) spans)))
    (let ((position 0)
          (line 1)
          (line-start 0))
      (dolist (span (nreverse spans))
        ;; Track the line and column the span should start at.
        (loop for i from line-start below (span-start span)
              when (char= (char text i) #\Newline)
                do (incf line) (setf line-start (1+ i)))
        (unless (and (= (span-start span) position)
                     (<= (span-start span) (span-end span))
                     (= (span-line span) line)
                     (= (span-column span) (- (span-start span) line-start)))
          (return-from coverage-gaps
            (format nil "~A: expected offset ~D (line ~D), got ~A"
                    name position line span)))
        (setf position (span-end span)))
      (unless (= position (length text))
        (format nil "~A: covered up to ~D of ~D" name position (length text))))))

(define-test coverage-of-fixtures
  :parent scanner
  (dolist (text (list "" "a" (lines "a" "") (lines "a  " "" "  b  % c  " "")
                      (lines "\\foo^^M rest  " "\\" "^^41^^5cbar")
                      (format nil "a~C~Cb   " (code-char 0) #\Tab)
                      ;; ^^ rewritten inside names shifts buffer offsets.
                      (lines "\\a^^62c d" "\\^^61bc  " "x\\a^^")))
    (false (coverage-gaps "fixture" text)))
  (let ((state (make-plain-state)))
    (set-endlinechar state -1)
    (let ((spans '()))
      (read-all (string-stack (lines "a  " "b") :state state
                                                :skip-hook (lambda (kind span)
                                                             (push (cons kind span) spans))))
      (is equal '(:line-end) (mapcar #'car spans)))))

(define-test coverage-of-every-source-file
  :parent scanner
  :description "Under plain catcodes, the spans of tokens and skipped input
tile every spec/tex/*.tex file exactly, with correct lines and columns."
  (dolist (pathname (spec-files))
    (let ((name (file-namestring pathname)))
      (false (coverage-gaps name (read-spec-file pathname))))))
