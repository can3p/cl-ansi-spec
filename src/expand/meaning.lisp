;;;; src/expand/meaning.lisp
;;;;
;;;; Meanings of control sequences and active characters: what TeX keeps
;;;; in eqtb's eq_type and equiv fields (§§222-223).  NIL is `undefined';
;;;; every other meaning is an immutable object, so that \let shares it.
;;;; A font's meaning is the TEX-FONT itself.

(in-package #:cl-ansi-spec/expand)

(defstruct (meaning (:constructor nil) (:copier nil))
  "The common type of every defined meaning except fonts.")

(defstruct (macro (:include meaning)
                  (:constructor make-macro
                      (parameter-text body &key long-p outer-p))
                  (:copier nil))
  "A macro defined by \\def and its relatives, as TeX stores it (§§473-476).
PARAMETER-TEXT is a list of tokens in which every parameter-character
token (category 6) stands for the next parameter, #1, #2, ... in order:
TeX's match tokens, which keep the character for \\meaning.  Every other
token is a delimiter; a `#{' ending is the begin-group token, which BODY
then repeats at its end.  BODY is a list of tokens and parameter numbers
1-9 (where an argument is substituted); `##' in the source is a single
parameter-character token."
  (parameter-text '() :type list :read-only t)
  (body '() :type list :read-only t)
  (long-p nil :type boolean :read-only t)
  (outer-p nil :type boolean :read-only t))

(defstruct (primitive (:include meaning)
                      (:constructor make-primitive
                          (name &key operation expandable-p))
                      (:copier nil))
  "A primitive command.  NAME is the name TeX gives it (\"count\").
OPERATION is what the expander runs for it: for an EXPANDABLE-P primitive
a function of the expander and the token, NIL for a command not yet
implemented."
  (name "" :type string :read-only t)
  (operation nil :read-only t)
  (expandable-p nil :type boolean :read-only t))

(defstruct (character-meaning (:include meaning)
                              (:constructor make-character-meaning (code catcode))
                              (:copier nil))
  "The meaning of a control sequence \\let to a character token, e.g.
\\let\\bgroup={ gives code 123, catcode 1."
  (code 0 :type character-code :read-only t)
  (catcode 0 :type catcode-value :read-only t))

(deftype shorthand-kind ()
  "What a shorthand definition stands for: \\chardef (:CHAR),
\\mathchardef (:MATHCHAR), or a register by \\countdef, \\dimendef,
\\skipdef, \\muskipdef or \\toksdef."
  '(member :char :mathchar :count :dimen :skip :muskip :toks))

(defstruct (shorthand (:include meaning)
                      (:constructor make-shorthand (kind value))
                      (:copier nil))
  "A control sequence made by \\chardef, \\mathchardef or a register
definition (TeX's char_given, math_given, assign_int, ...).  VALUE is the
character code, math code or register number."
  (kind :char :type shorthand-kind :read-only t)
  (value 0 :type integer :read-only t))

(defun body-element= (a b)
  "True when two elements of a parameter text or body are the same: equal
tokens (spans ignored) or parameter numbers."
  (if (and (typep a 'token) (typep b 'token))
      (token= a b)
      (eql a b)))

(defun element-lists= (a b)
  "True when the lists A and B have pairwise BODY-ELEMENT= elements."
  (and (= (length a) (length b))
       (every #'body-element= a b)))

(defun meaning= (a b)
  "True when the meanings A and B are the same, as \\ifx compares them
(§507): macros by flags and token lists, the rest by what they stand for."
  (typecase a
    (null (null b))
    (macro (and (macro-p b)
                (eq (macro-long-p a) (macro-long-p b))
                (eq (macro-outer-p a) (macro-outer-p b))
                (element-lists= (macro-parameter-text a) (macro-parameter-text b))
                (element-lists= (macro-body a) (macro-body b))))
    (primitive (and (primitive-p b)
                    (string= (primitive-name a) (primitive-name b))))
    (character-meaning (and (character-meaning-p b)
                            (= (character-meaning-code a) (character-meaning-code b))
                            (= (character-meaning-catcode a)
                               (character-meaning-catcode b))))
    (shorthand (and (shorthand-p b)
                    (eq (shorthand-kind a) (shorthand-kind b))
                    (= (shorthand-value a) (shorthand-value b))))
    (t (eq a b))))
