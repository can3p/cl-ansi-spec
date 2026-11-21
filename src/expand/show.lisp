;;;; src/expand/show.lisp
;;;;
;;;; How TeX shows control sequences, token lists and meanings (TeX: The
;;;; Program, §§262-263 print_cs/sprint_cs, §§292-296 show_token_list and
;;;; print_meaning, §§227-1346 print_cmd_chr), as strings; and the
;;;; tokens TeX makes of a string (§464, str_toks).  Strings are built as
;;;; TeX builds them for \string and \meaning (selector new_string):
;;;; characters are never shown in ^^ notation.

(in-package #:cl-ansi-spec/expand)

(defun escape-text (expander)
  "The \\escapechar as a string, empty when it is outside 0..255."
  (let ((code (parameter (expander-state expander) :escapechar)))
    (if (<= 0 code 255) (string (code-char code)) "")))

(defun esc (expander name)
  "TeX's print_esc: the escape character, then NAME."
  (concatenate 'string (escape-text expander) name))

(defun cs-name-text (expander cs)
  "TeX's sprint_cs: CS as \\string shows it."
  (let ((name (control-sequence-name cs)))
    (cond ((control-sequence-active-p cs) name)
          ((string= name "") (concatenate 'string (esc expander "csname")
                                          (esc expander "endcsname")))
          (t (esc expander name)))))

(defun cs-print-text (expander cs)
  "TeX's print_cs: CS as a token list shows it, with a space after a
multi-letter name, and after a one-letter name whose character is a
letter now."
  (let ((name (control-sequence-name cs)))
    (cond ((control-sequence-active-p cs) name)
          ((string= name "")
           (concatenate 'string (cs-name-text expander cs) " "))
          ((= 1 (length name))
           (if (= (catcode (expander-tex expander) (char-code (char name 0)))
                  +letter+)
               (concatenate 'string (esc expander name) " ")
               (esc expander name)))
          (t (concatenate 'string (esc expander name) " ")))))

(defun token-text-for-list (expander token)
  "One token as show_token_list shows it: a control sequence by
CS-PRINT-TEXT, a parameter character doubled, any other character itself."
  (etypecase token
    (cs-token (cs-print-text expander (cs-token-control-sequence token)))
    (character-token
     (let ((char (string (code-char (character-token-code token)))))
       (if (= (character-token-catcode token) +parameter+)
           (concatenate 'string char char)
           char)))))

(defun token-list-text (expander tokens)
  "TOKENS as show_token_list shows them."
  (with-output-to-string (out)
    (dolist (token tokens)
      (write-string (token-text-for-list expander token) out))))

(defun macro-text (expander macro)
  "The parameter text and body of MACRO as \\meaning shows them (§294):
each match token as its character and its number, `->', then the body,
with parameters shown by the last match character."
  (let ((match-char #\#)
        (n 0))
    (with-output-to-string (out)
      (dolist (token (macro-parameter-text macro))
        (cond ((character-catcode-p token +parameter+)
               (setf match-char (code-char (character-token-code token)))
               (format out "~C~D" match-char (incf n)))
              (t (write-string (token-text-for-list expander token) out))))
      (write-string "->" out)
      (dolist (element (macro-body macro))
        (if (integerp element)
            (format out "~C~D" match-char element)
            (write-string (token-text-for-list expander element) out))))))

(defun character-command-text (catcode code)
  "TeX's print_cmd_chr for a character command (§298)."
  (concatenate 'string
               (ecase catcode
                 (#.+begin-group+ "begin-group character ")
                 (#.+end-group+ "end-group character ")
                 (#.+math-shift+ "math shift character ")
                 (#.+alignment-tab+ "alignment tab character ")
                 (#.+parameter+ "macro parameter character ")
                 (#.+superscript+ "superscript character ")
                 (#.+subscript+ "subscript character ")
                 (#.+space+ "blank space ")
                 (#.+letter+ "the letter ")
                 (#.+other+ "the character "))
               (string (code-char code))))

(defun mark-index (name)
  "The index of the mark primitive NAME in an expander's marks, or NIL."
  (position name '("topmark" "firstmark" "botmark" "splitfirstmark"
                   "splitbotmark")
            :test #'string=))

(defun macro-prefix-text (expander macro)
  "\"macro\", \"\\long macro\", \"\\outer macro\" or \"\\long\\outer
macro\" (§1295)."
  (cond ((and (macro-long-p macro) (macro-outer-p macro))
         (concatenate 'string (esc expander "long") (esc expander "outer macro")))
        ((macro-long-p macro) (esc expander "long macro"))
        ((macro-outer-p macro) (esc expander "outer macro"))
        (t "macro")))

(defun font-meaning-text (font)
  "TeX's print_cmd_chr for a font (§1261): `select font', the file, and
the size when it is not the design size.  Without metrics a `scaled' size
cannot be turned into points, so only `at' sizes are shown."
  (let ((size (tex-font-size font)))
    (format nil "select font ~A~@[ at ~A~]" (tex-font-file font)
            (and (eq (first size) :at) (format-dimen (second size))))))

(defun meaning-text (expander token meaning)
  "TeX's print_meaning (§296) for TOKEN with MEANING, as \\meaning shows it."
  (if (character-token-p token)
      (character-command-text (character-token-catcode token)
                              (character-token-code token))
      (etypecase meaning
        (null "undefined")
        (macro (concatenate 'string (macro-prefix-text expander meaning) ":"
                            (macro-text expander meaning)))
        (primitive
         (let* ((name (primitive-name meaning))
                (mark (mark-index name)))
           (if mark
               (concatenate 'string (esc expander name) ":"
                            (token-list-text
                             expander (aref (expander-marks expander) mark)))
               (esc expander name))))
        (character-meaning
         (character-command-text (character-meaning-catcode meaning)
                                 (character-meaning-code meaning)))
        (shorthand
         (let ((value (shorthand-value meaning)))
           (ecase (shorthand-kind meaning)
             (:char (format nil "~A\"~X" (esc expander "char") value))
             (:mathchar (format nil "~A\"~X" (esc expander "mathchar") value))
             ((:count :dimen :skip :muskip :toks)
              (format nil "~A~D"
                      (esc expander (string-downcase
                                     (symbol-name (shorthand-kind meaning))))
                      value)))))
        (tex-font (font-meaning-text meaning)))))

(defun string-tokens (string &optional span)
  "TeX's str_toks: the characters of STRING as tokens, spaces of category
10 and all others of category 12, each with SPAN."
  (map 'list (lambda (char)
               (if (char= char #\Space)
                   (make-character-token 32 +space+ span)
                   (make-character-token (char-code char) +other+ span)))
       string))
