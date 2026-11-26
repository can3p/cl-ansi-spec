;;;; src/expand/conditionals.lisp
;;;;
;;;; TeX's conditionals (TeX: The Program, §§487-510): the condition
;;;; stack, skipping (pass_text) with nested conditionals counted, every
;;;; TeX82 test, \ifcase, and \fi, \else and \or with their recovery.
;;;;
;;;; The stack holds one CONDITIONAL per open conditional, innermost
;;;; first; its LIMIT is TeX's if_limit while it is innermost (TeX saves
;;;; it in the next node otherwise, which changes nothing observable).

(in-package #:cl-ansi-spec/expand)

(defstruct (conditional (:constructor make-conditional (kind line)))
  "An open conditional.  KIND is the name of its test (\"ifx\"), LINE the
line where it began (if_line).  LIMIT is what may end it next (§489):
:IF while its test is read, :ELSE after a true test (an \\else or \\fi
may come), :OR in \\ifcase, :FI after \\else, never :NORMAL."
  (kind "" :type string :read-only t)
  (line 0 :type integer :read-only t)
  (limit :if :type (member :if :fi :else :or)))

(defun limit-rank (limit)
  "TeX's codes for if_limit and \\fi, \\else, \\or (§489): normal 0, if 1,
fi 2, else 3, or 4."
  (position limit '(:normal :if :fi :else :or)))

(defun if-limit (expander)
  "TeX's if_limit: the limit of the innermost conditional, :NORMAL when
none is open."
  (let ((top (first (expander-conditionals expander))))
    (if top (conditional-limit top) :normal)))

(defun if-test-names ()
  "The names of TeX82's conditionals (if_test, §487)."
  '("if" "ifcat" "ifnum" "ifdim" "ifodd" "ifvmode" "ifhmode" "ifmmode"
    "ifinner" "ifvoid" "ifhbox" "ifvbox" "ifx" "ifeof" "iftrue" "iffalse"
    "ifcase"))

(defvar *conditional-codes*
  (let ((table (make-hash-table :test 'equal)))
    (dolist (name (if-test-names))
      (setf (gethash name table) :if))
    (loop for (name . code) in '(("fi" . :fi) ("else" . :else) ("or" . :or))
          do (setf (gethash name table) code))
    table)
  "Primitive name to :IF for a conditional (if_test), or :FI, :ELSE, :OR
(fi_or_else): what skipping looks at in every token.  Never modified.")

(defun conditional-code (meaning)
  "The entry of *CONDITIONAL-CODES* for MEANING, or NIL."
  (and (primitive-p meaning)
       (values (gethash (primitive-name meaning) *conditional-codes*))))

(defun if-test-p (meaning)
  "True when MEANING is a conditional (cur_cmd = if_test)."
  (eq (conditional-code meaning) :if))

(defun fi-or-else-code (meaning)
  "The code (:FI, :ELSE or :OR) of MEANING when it is \\fi, \\else or \\or
(cur_cmd = fi_or_else), else NIL."
  (let ((code (conditional-code meaning)))
    (and (not (eq code :if)) code)))

(defun pass-text (expander)
  "TeX's pass_text (§494): skip tokens without expansion, counting nested
conditionals, up to a \\fi, \\else or \\or at this level.  Returns its code;
:FI at the end of all input."
  (let ((saved (expander-scanner-status expander))
        (level 0))
    (setf (expander-scanner-status expander) :skipping
          (expander-skip-line expander) (current-line-number (expander-input expander)))
    (unwind-protect
         (loop
           (multiple-value-bind (token meaning) (get-next expander)
             (when (null token)
               (return :fi))
             (let ((code (fi-or-else-code meaning)))
               (cond (code
                      (when (zerop level)
                        (return code))
                      (when (eq code :fi)
                        (decf level)))
                     ((if-test-p meaning) (incf level))))))
      (setf (expander-scanner-status expander) saved))))

(defun incomplete-conditional-text (expander)
  "What TeX says of the conditional being skipped when a runaway ends it
(§336): `\\ifx; all text was ignored after line 3'."
  (let ((top (first (expander-conditionals expander))))
    (format nil "~A; all text was ignored after line ~D"
            (esc expander (if top (conditional-kind top) "if"))
            (expander-skip-line expander))))

;;; The tests (§§497-508)

(defun x-token-or-active-character (expander)
  "The next token with expansion, as \\if and \\ifcat see it (§506,
get_x_token_or_active_char): its command and character, the category and
code of a character (also of a control sequence \\let to one, or of a
\\noexpand-ed active character), else 0 (\\relax) and 256."
  (multiple-value-bind (token meaning) (get-x-token expander)
    (cond ((null token) (values 0 256))
          ((character-token-p token)
           (values (character-token-catcode token) (character-token-code token)))
          ((character-meaning-p meaning)
           (values (character-meaning-catcode meaning) (character-meaning-code meaning)))
          ((and (eq meaning (dont-expand-meaning))
                (control-sequence-active-p (cs-token-control-sequence token)))
           (values 13 (char-code (char (control-sequence-name
                                        (cs-token-control-sequence token))
                                       0))))
          (t (values 0 256)))))

(defun ifx-meaning (token meaning)
  "What \\ifx compares of TOKEN with MEANING (§507): a character token as
the character it is, a control sequence by its meaning."
  (if (character-token-p token)
      (make-character-meaning (character-token-code token)
                              (character-token-catcode token))
      meaning))

(defun ifx-equal (a b)
  "True when \\ifx finds the meanings A and B equal.  A \\noexpand-ed
token is \\relax with a character of its own (no_expand_flag), so it
equals only another one."
  (let ((dont (dont-expand-meaning)))
    (if (or (eq a dont) (eq b dont))
        (and (eq a dont) (eq b dont))
        (meaning= a b))))

(defun test-ifx (expander)
  "\\ifx (§507): compare the next two tokens, read without expansion and
with \\outer macros allowed."
  (let ((saved (expander-scanner-status expander)))
    (setf (expander-scanner-status expander) :normal)
    (unwind-protect
         (multiple-value-bind (first first-meaning) (get-next expander)
           (multiple-value-bind (second second-meaning) (get-next expander)
             (ifx-equal (ifx-meaning first first-meaning)
                        (ifx-meaning second second-meaning))))
      (setf (expander-scanner-status expander) saved))))

(defun test-relation (expander name)
  "\\ifnum or \\ifdim (§503): a quantity, a relation `<', `=' or `>' of
category 12 (else `Missing = inserted'), a quantity."
  (flet ((quantity ()
           (if (string= name "ifnum") (scan-int expander) (values (scan-dimen expander)))))
    (let* ((left (quantity))
           (relation (multiple-value-bind (token) (get-x-nonblank expander)
                      (cond ((other-character-p token #\<) #\<)
                            ((other-character-p token #\=) #\=)
                            ((other-character-p token #\>) #\>)
                            (t (back-token expander token)
                               (tex-error "Missing = inserted for"
                                          :context (esc expander name)
                                          :span (and token (token-span token)))
                               #\=)))))
      (let ((right (quantity)))
        (ecase relation
          (#\< (< left right))
          (#\= (= left right))
          (#\> (> left right)))))))

(defgeneric box-kind (box)
  (:documentation "The kind of BOX, the contents of a box register, as
\\ifvoid, \\ifhbox and \\ifvbox test it: NIL when void, else :HBOX or
:VBOX.")
  (:method ((box null)) nil))

(defun test-condition (expander name)
  "The truth of the conditional NAME, other than \\ifcase (§497)."
  (let ((mode (list-state-mode (current-list expander))))
    (cond
      ((or (string= name "if") (string= name "ifcat"))
       (multiple-value-bind (cmd-1 chr-1) (x-token-or-active-character expander)
         (multiple-value-bind (cmd-2 chr-2) (x-token-or-active-character expander)
           (if (string= name "if") (= chr-1 chr-2) (= cmd-1 cmd-2)))))
      ((or (string= name "ifnum") (string= name "ifdim"))
       (test-relation expander name))
      ((string= name "ifodd") (oddp (scan-int expander)))
      ((string= name "ifvmode") (eq (mode-kind mode) :vertical))
      ((string= name "ifhmode") (eq (mode-kind mode) :horizontal))
      ((string= name "ifmmode") (eq (mode-kind mode) :math))
      ((string= name "ifinner")
       (and (member mode '(:internal-vertical :restricted-horizontal :math)) t))
      ((member name '("ifvoid" "ifhbox" "ifvbox") :test #'string=)
       (let ((kind (box-kind (register (expander-state expander) :box
                                       (scan-eight-bit-int expander)))))
         (cond ((string= name "ifvoid") (null kind))
               ((string= name "ifhbox") (eq kind :hbox))
               (t (eq kind :vbox)))))
      ((string= name "ifx") (test-ifx expander))
      ((string= name "ifeof")
       (eq :closed (aref (expander-read-streams expander) (scan-four-bit-int expander))))
      ((string= name "iftrue") t)
      ((string= name "iffalse") nil)
      (t (error "~S is not a conditional." name)))))

;;; Conditionals and \fi, \else, \or (§§498-500, 509-510)

(defun begin-conditional (expander name)
  "TeX's conditional (§498) for the test NAME: push the condition stack,
decide, and either go on (waiting for \\else, \\or or \\fi) or skip."
  (let ((ours (make-conditional name (current-line-number (expander-input expander)))))
    (push ours (expander-conditionals expander))
    (flet ((skip-until (accept)
             ;; pass_text until ACCEPT says a code at our level ends the
             ;; skipping; nested conditionals left open by the test are
             ;; closed by their \fi on the way.
             (loop
               (let ((code (pass-text expander)))
                 (cond ((eq (first (expander-conditionals expander)) ours)
                        (when (funcall accept code)
                          (return code)))
                       ((eq code :fi)
                        (pop (expander-conditionals expander)))))))
           (common-ending (code)
             (if (eq code :fi)
                 (pop (expander-conditionals expander))
                 (setf (conditional-limit ours) :fi))))
      (if (string= name "ifcase")
          (let ((n (scan-int expander)))
            (loop until (zerop n)
                  do (let ((code (skip-until (constantly t))))
                       (if (eq code :or)
                           (decf n)
                           (progn (common-ending code)
                                  (return-from begin-conditional (values))))))
            (setf (conditional-limit ours) :or))
          (if (test-condition expander name)
              (setf (conditional-limit ours) :else)
              (common-ending
               (skip-until (lambda (code)
                             (or (not (eq code :or))
                                 (progn (tex-error "Extra" :context (esc expander "or"))
                                        nil)))))))))
  (values))

(defun insert-relax (expander token)
  "TeX's insert_relax (§379): TOKEN is read again after a frozen \\relax."
  (back-token expander token)
  (back-token expander (make-cs-token (frozen-control-sequence expander "relax")
                                      (token-span token))))

(defun fi-or-else (expander token code name)
  "\\fi, \\else or \\or (CODE) met while expanding (§510): ends the
innermost conditional, skipping to its \\fi; inserts \\relax while its
test is still being read; otherwise `Extra \\fi' and the like."
  (let ((limit (if-limit expander)))
    (cond ((<= (limit-rank code) (limit-rank limit))
           (loop until (eq code :fi)
                 do (setf code (pass-text expander)))
           (pop (expander-conditionals expander)))
          ((eq limit :if) (insert-relax expander token))
          (t (tex-error "Extra" :context (esc expander name)
                                :span (token-span token))))))

(dolist (name (if-test-names))
  (let ((name name))
    (define-expandable name
      (lambda (expander token)
        (declare (ignore token))
        (begin-conditional expander name)))))

(dolist (code '(:fi :else :or))
  (let ((code code)
        (name (string-downcase (symbol-name code))))
    (define-expandable name
      (lambda (expander token)
        (fi-or-else expander token code name)))))
