;;;; src/expand/scan.lisp
;;;;
;;;; TeX's basic scanners (TeX: The Program, §§402-410, 433-445):
;;;; keywords, optional `=' and spaces, the compulsory left brace, and
;;;; integers with their bounded variants (registers, characters, families,
;;;; math characters, delimiters).  Every scanner reads with expansion and
;;;; reports TeX's errors with TeX's recovery.
;;;;
;;;; TeX compares tokens here in two ways, and so do these functions: by
;;;; the token itself (cur_tok: `-', digits, `=', the keyword letters), so
;;;; that only real character tokens count, or by the command (cur_cmd:
;;;; spaces, braces, \relax), so that a control sequence \let to the
;;;; character counts too.

(in-package #:cl-ansi-spec/expand)

(defun primitive-named-p (meaning name)
  "True when MEANING is the primitive NAME (\"relax\")."
  (and (primitive-p meaning) (string= (primitive-name meaning) name)))

(defun command-catcode (token meaning)
  "The category of the character command TOKEN with MEANING stands for
(cur_cmd for characters): a character token's own, or that of the
character a control sequence was \\let to; NIL otherwise."
  (cond ((character-token-p token) (character-token-catcode token))
        ((character-meaning-p meaning) (character-meaning-catcode meaning))))

(defun other-character-p (token char)
  "True when TOKEN is the character CHAR of category 12 (TeX's
other_token + CHAR)."
  (and (character-catcode-p token +other+)
       (= (character-token-code token) (char-code char))))

(defun int-error-context (n)
  "The context TeX's int_error prints: the offending value."
  (format nil "(~D)" n))

;;; Skipping

(defun get-x-nonblank (expander)
  "The next token and meaning that is not a blank, with expansion (TeX's
`Get the next non-blank non-call token', §406)."
  (loop
    (multiple-value-bind (token meaning) (get-x-token expander)
      (unless (and token (blank-p token meaning))
        (return (values token meaning))))))

(defun get-x-nonblank-nonrelax (expander)
  "The next token and meaning that is neither a blank nor \\relax, with
expansion (§404).  A \\noexpand-ed token counts as \\relax."
  (loop
    (multiple-value-bind (token meaning) (get-x-token expander)
      (unless (and token (or (blank-p token meaning)
                             (primitive-named-p meaning "relax")))
        (return (values token meaning))))))

(defun scan-optional-space (expander)
  "Skip one blank, with expansion, if one comes next (§443)."
  (multiple-value-bind (token meaning) (get-x-token expander)
    (when (and token (not (blank-p token meaning)))
      (back-token expander token))))

(defun scan-optional-equals (expander)
  "TeX's scan_optional_equals (§405): skip blanks and one `=' of category
12."
  (let ((token (get-x-nonblank expander)))
    (when (and token (not (other-character-p token #\=)))
      (back-token expander token))))

(defun scan-keyword (expander keyword)
  "TeX's scan_keyword (§407): true, having read it, when the next
character tokens spell KEYWORD (a lowercase string) in either case,
with expansion and after any blanks.  Otherwise the result is NIL and
the letters matched so far and the token that failed are put back; the
blanks before the first letter are lost."
  (let ((matched '())
        (k 0))
    (loop while (< k (length keyword))
          do (multiple-value-bind (token meaning) (get-x-token expander)
               (let ((char (char keyword k)))
                 (cond ((and (character-token-p token)
                             (let ((code (character-token-code token)))
                               (or (= code (char-code char))
                                   (= code (char-code (char-upcase char))))))
                        (push token matched)
                        (incf k))
                       ((or (null token) (not (blank-p token meaning)) matched)
                        (back-token expander token)
                        (when matched
                          (push-tokens (expander-input expander)
                                       (reverse matched) :backed-up))
                        (return-from scan-keyword nil))))))
    t))

(defun scan-left-brace (expander)
  "TeX's scan_left_brace (§403): skip blanks and \\relax and read a left
brace; anything else is put back and a `{' is assumed."
  (multiple-value-bind (token meaning) (get-x-nonblank-nonrelax expander)
    (unless (eql (command-catcode token meaning) +begin-group+)
      (back-token expander token)
      (tex-error "Missing { inserted" :span (and token (token-span token)))
      (incf (expander-align-state expander)))))

;;; Integers (§§440-445)

(defun scan-signs (expander)
  "Read blanks and signs `+' and `-' of category 12, with expansion
(§441).  Returns the next token, its meaning, and whether the signs make
the number negative."
  (let ((negative nil))
    (loop
      (multiple-value-bind (token meaning) (get-x-nonblank expander)
        (cond ((other-character-p token #\-) (setf negative (not negative)))
              ((other-character-p token #\+))
              (t (return (values token meaning negative))))))))

(defun alphabetic-constant (expander)
  "The character code after ``' (§442): of a character token, an active
character or a control sequence named by one character, read without
expansion.  Returns it, or 48 (`0') after `Improper alphabetic constant'."
  (let* ((token (get-token expander))
         (code (cond ((null token) 256)
                     ((character-token-p token)
                      ;; Undo the change get_next made to align_state.
                      (case (character-token-catcode token)
                        (#.+begin-group+ (decf (expander-align-state expander)))
                        (#.+end-group+ (incf (expander-align-state expander))))
                      (character-token-code token))
                     (t (let ((name (control-sequence-name
                                     (cs-token-control-sequence token))))
                          (if (= (length name) 1)
                              (char-code (char name 0))
                              256))))))
    (cond ((> code 255)
           (back-token expander token)
           (tex-error "Improper alphabetic constant"
                      :span (and token (token-span token)))
           (char-code #\0))
          (t (scan-optional-space expander)
             code))))

(defun digit-value (token radix)
  "The value of TOKEN as a digit in RADIX (§§444-445): `0'-`9' of category
12, and for radix 16 `A'-`F' of category 11 or 12; NIL otherwise."
  (when (character-token-p token)
    (let ((code (character-token-code token))
          (catcode (character-token-catcode token)))
      (cond ((and (= catcode +other+) (<= 48 code 57) (< (- code 48) radix))
             (- code 48))
            ((and (= radix 16) (or (= catcode +other+) (= catcode +letter+))
                  (<= 65 code 70))
             (- code 55))))))

(defun scan-digits (expander token meaning radix)
  "Accumulate the digits of RADIX starting with TOKEN, whose meaning is
MEANING (§§444-445).  Returns the value, true when no digit was read, and
the token after the digits with its meaning (read, not yet put back)."
  (let ((value 0) (vacuous t) (ok t)
        (limit (ecase radix (10 214748364) (8 (expt 2 28)) (16 (expt 2 27)))))
    (loop for digit = (digit-value token radix)
          while digit
          do (setf vacuous nil)
             (cond ((and (>= value limit)
                         (or (> value limit) (> digit 7) (/= radix 10)))
                    (when ok
                      (tex-error "Number too big" :span (token-span token))
                      (setf value +infinity+ ok nil)))
                   (t (setf value (+ (* value radix) digit))))
             (multiple-value-setq (token meaning) (get-x-token expander)))
    (values value vacuous token meaning)))

(defun scan-constant (expander token meaning)
  "The rest of an integer constant whose first token is TOKEN (§444).
Returns the value, the radix, and the token that ended it."
  (let ((radix 10))
    (cond ((other-character-p token #\')
           (setf radix 8)
           (multiple-value-setq (token meaning) (get-x-token expander)))
          ((other-character-p token #\")
           (setf radix 16)
           (multiple-value-setq (token meaning) (get-x-token expander))))
    (multiple-value-bind (value vacuous next next-meaning)
        (scan-digits expander token meaning radix)
      (cond (vacuous
             (back-token expander next)
             (tex-error "Missing number, treated as zero"
                        :span (and next (token-span next))))
            ((not (and next (blank-p next next-meaning)))
             (back-token expander next)))
      (values value radix next))))

(defun %scan-int (expander)
  "TeX's scan_int (§440).  Returns the value, the radix (0 for an
alphabetic constant or an internal integer, else 8, 10 or 16) and the
token that ended a constant (TeX's cur_tok, already put back or
consumed), which scan_dimen looks at for a decimal point."
  (multiple-value-bind (token meaning negative) (scan-signs expander)
    (multiple-value-bind (value radix last)
        (cond ((other-character-p token #\`)
               (values (alphabetic-constant expander) 0 nil))
              ((internal-command-p meaning)
               (values (scan-something-internal expander token meaning :int nil)
                       0 nil))
              (t (scan-constant expander token meaning)))
      (values (if negative (- value) value) radix last))))

(defun scan-int (expander)
  "TeX's scan_int (§440): an integer, with expansion: signs, then a
decimal, octal (') or hexadecimal (\") constant followed by one optional
space, an alphabetic constant (`), or an internal quantity coerced to an
integer."
  (values (%scan-int expander)))

(defun scan-bounded-int (expander max message)
  "An integer in 0..MAX; outside, TeX's MESSAGE and 0."
  (let ((n (scan-int expander)))
    (cond ((<= 0 n max) n)
          (t (tex-error message :context (int-error-context n))
             0))))

(defun scan-eight-bit-int (expander)
  "TeX's scan_eight_bit_int (§433): a register number, 0-255."
  (scan-bounded-int expander 255 "Bad register code"))

(defun scan-char-num (expander)
  "TeX's scan_char_num (§434): a character code, 0-255."
  (scan-bounded-int expander 255 "Bad character code"))

(defun scan-four-bit-int (expander)
  "TeX's scan_four_bit_int (§435): a family number, 0-15."
  (scan-bounded-int expander 15 "Bad number"))

(defun scan-fifteen-bit-int (expander)
  "TeX's scan_fifteen_bit_int (§436): a math character, 0-\"7FFF."
  (scan-bounded-int expander #x7FFF "Bad mathchar"))

(defun scan-twenty-seven-bit-int (expander)
  "TeX's scan_twenty_seven_bit_int (§437): a delimiter code, 0-\"7FFFFFF."
  (scan-bounded-int expander #x7FFFFFF "Bad delimiter code"))
