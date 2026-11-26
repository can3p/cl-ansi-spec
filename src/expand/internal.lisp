;;;; src/expand/internal.lisp
;;;;
;;;; TeX's internal quantities (TeX: The Program, §§410-427,
;;;; scan_something_internal): every command that can be read as a value,
;;;; at its level (integer, dimen, glue, mu glue, font identifier, token
;;;; list), with TeX's coercion to a lower level and its negation; font
;;;; identifiers (§577) and \fontdimen (§578).
;;;;
;;;; Values: an integer for :INT, sp for :DIMEN, a GLUE for :GLUE and :MU,
;;;; a TEX-FONT for :IDENT, a token list for :TOK.  What belongs to lists
;;;; and pages is read from the nest (nest.lisp); a box's dimensions
;;;; through BOX-DIMENSION, whose methods the box layer adds.

(in-package #:cl-ansi-spec/expand)

(defun level-rank (level)
  "TeX's order of the value levels (int_val ... tok_val, §410)."
  (position level '(:int :dimen :glue :mu :ident :tok)))

(defgeneric box-dimension (box which)
  (:documentation "The WHICH (:WIDTH, :HEIGHT or :DEPTH) of BOX, the
contents of a box register, in sp, as \\wd, \\ht and \\dp read it.")
  (:method ((box null) which)
    (declare (ignore which))
    0))

(defgeneric (setf box-dimension) (value box which)
  (:documentation "Set the WHICH dimension of BOX to VALUE (sp), as
\\wd, \\ht and \\dp assign it.")
  (:method (value (box null) which)
    ;; A void box has no dimensions to change (§1247).
    (declare (ignore which))
    value))

;;; Font identifiers (§577) and \fontdimen (§578)

(defun font-identifier-token (expander font &optional span)
  "The token \\the gives for FONT: a frozen control sequence named by the
font's identifier whose meaning is FONT whatever that name later means
(TeX's font_id_base + f)."
  (let ((table (expander-font-identifiers expander))
        (key (cons font (tex-font-identifier font))))
    ;; Keyed on the identifier too: TeX prints the font's current one.
    (make-cs-token
     (or (gethash key table)
         (let ((cs (make-frozen-control-sequence (tex-font-identifier font))))
           (set-meaning (expander-state expander) cs font :global t
                                                          :globaldefs nil)
           (setf (gethash key table) cs)))
     span)))

(defun family-size (name)
  "The math size of \\textfont (0), \\scriptfont (1), \\scriptscriptfont
(2), or NIL."
  (position name '("textfont" "scriptfont" "scriptscriptfont") :test #'string=))

(defun scan-font-ident (expander)
  "TeX's scan_font_ident (§577): a font named by \\font (the current
font), a font identifier, or a family font (\\textfont 3); otherwise
`Missing font identifier' and \\nullfont."
  (multiple-value-bind (token meaning) (get-x-nonblank expander)
    (let ((state (expander-state expander)))
      (cond ((primitive-named-p meaning "font") (current-font state))
            ((tex-font-p meaning) meaning)
            ((and (primitive-p meaning) (family-size (primitive-name meaning)))
             (family-font state (family-size (primitive-name meaning))
                          (scan-four-bit-int expander)))
            (t (back-token expander token)
               (tex-error "Missing font identifier"
                          :span (and token (token-span token)))
               (es-null-font state))))))

(defun find-font-dimen (expander)
  "TeX's find_font_dimen (§578): scan \\fontdimen's number and font.
Returns the font and the parameter number, or NIL and NIL after TeX's
error for a number the font does not have.  Without metrics only
\\nullfont's count is known (7, growing while no other font is
loaded); a font loaded by \\font takes any number from 1."
  (let* ((n (scan-int expander))
         (font (scan-font-ident expander))
         (count (tex-font-parameter-count font)))
    (cond ((and (plusp n) (or (null count) (<= n count)))
           (values font n))
          ((and (plusp n)
                (eq font (es-null-font (expander-state expander)))
                (null (es-loaded-fonts (expander-state expander))))
           ;; The last font loaded grows (§580).
           (setf (tex-font-parameter-count font) n)
           (values font n))
          (t
           (tex-error (format nil "Font ~A has only ~D fontdimen parameters"
                              (esc expander (tex-font-identifier font))
                              (or count (length (tex-font-dimens font)))))
           (values nil nil)))))

;;; The internal commands

(defun list-quantity-error (expander token level)
  "TeX's `Improper \\spacefactor' or `Improper \\prevdepth' (§418):
the quantity is read outside its mode; it is 0."
  (tex-error "Improper" :context (meaning-text expander token
                                               (meaning (expander-state expander)
                                                        (cs-token-control-sequence token)))
                        :span (token-span token))
  (values 0 (if (eq level :tok) :int :dimen)))

(defun enclosing-vertical-list (expander)
  "The innermost list of the nest in vertical mode (§422)."
  (find :vertical (expander-nest expander)
        :key (lambda (list) (mode-kind (list-state-mode list)))))

(defun last-item (expander name)
  "\\lastpenalty, \\lastkern, \\lastskip, \\inputlineno or \\badness
(§424).  Returns the value and its level."
  (let* ((list (current-list expander))
         (mode (list-state-mode list))
         (last (list-state-last-node list))
         (page (expander-page expander)))
    (flet ((last-of (kind level initial page-value)
             (cond ((and last (not (eq mode :none)))
                    (if (eq (car last) kind)
                        (values (cdr last)
                                (if (and (eq kind :glue) (glue-mu-p (cdr last)))
                                    :mu
                                    level))
                        (values initial level)))
                   ;; An empty list in (outer) vertical mode: what the
                   ;; page builder last saw (§424).
                   ((and (null last) (eq mode :vertical))
                    (values (or page-value initial) level))
                   (t (values initial level)))))
      (cond ((string= name "lastpenalty")
             (last-of :penalty :int 0 (page-state-last-penalty page)))
            ((string= name "lastkern")
             (last-of :kern :dimen 0 (page-state-last-kern page)))
            ((string= name "lastskip")
             (last-of :glue :glue (zero-glue) (page-state-last-glue page)))
            ((string= name "inputlineno")
             (values (current-line-number (expander-input expander)) :int))
            (t (values (expander-last-badness expander) :int))))))

(defvar *internal-commands* (make-hash-table :test 'equal)
  "TeX's internal commands (min_internal to max_internal, §209) by
primitive name: a function of the expander, the command's token and the
level wanted, returning the value and its level (§413).  Global data,
filled while the system loads by DEFINE-INTERNAL; never rebound.")

(defmacro define-internal (names (expander token level) &body body)
  "Register BODY as the reader of the internal command(s) NAMES (a string
or a list of strings); inside it NAME is bound to the command's name."
  `(dolist (name ',(if (listp names) names (list names)))
     (setf (gethash name *internal-commands*)
           (let ((name name))
             (declare (ignorable name))
             (lambda (,expander ,token ,level)
               (declare (ignorable ,expander ,token ,level))
               ,@body)))))

(defun missing-number (expander token)
  "TeX's `Missing number, treated as zero' for a token list or font where
a number is wanted (§428): TOKEN is put back; the value is 0."
  (back-token expander token)
  (tex-error "Missing number, treated as zero" :span (token-span token))
  (values 0 :dimen))

(defun token-list-value (expander token level value)
  "VALUE, a token list, when LEVEL asks for one; else `Missing number'."
  (if (eq level :tok)
      (values value :tok)
      (missing-number expander token)))

;;; Every parameter reads its value.
(dolist (kind '(:integer :dimen :glue :muglue :tokens))
  (dolist (parameter (parameter-names kind))
    (let ((parameter parameter)
          (level (ecase kind
                   (:integer :int) (:dimen :dimen) (:glue :glue)
                   (:muglue :mu) (:tokens :tok))))
      (setf (gethash (string-downcase (symbol-name parameter)) *internal-commands*)
            (lambda (expander token wanted)
              (let ((value (parameter (expander-state expander) parameter)))
                (if (eq level :tok)
                    (token-list-value expander token wanted value)
                    (values value level))))))))

(define-internal ("catcode" "lccode" "uccode" "sfcode" "mathcode" "delcode")
    (expander token level)
  (values (code (expander-state expander) (intern (string-upcase name) :keyword)
                (scan-char-num expander))
          :int))

(define-internal ("count" "dimen" "skip" "muskip") (expander token level)
  (let ((kind (intern (string-upcase name) :keyword)))
    (values (register (expander-state expander) kind (scan-eight-bit-int expander))
            (ecase kind (:count :int) (:dimen :dimen) (:skip :glue) (:muskip :mu)))))

(define-internal "toks" (expander token level)
  (if (eq level :tok)
      (values (register (expander-state expander) :toks (scan-eight-bit-int expander))
              :tok)
      (missing-number expander token)))

(define-internal ("font" "textfont" "scriptfont" "scriptscriptfont")
    (expander token level)
  (cond ((eq level :tok)
         (back-token expander token)
         (values (scan-font-ident expander) :ident))
        (t (missing-number expander token))))

(define-internal "spacefactor" (expander token level)
  (let ((list (current-list expander)))
    (if (eq (mode-kind (list-state-mode list)) :horizontal)
        (values (list-state-space-factor list) :int)
        (list-quantity-error expander token level))))

(define-internal "prevdepth" (expander token level)
  (let ((list (current-list expander)))
    (if (eq (mode-kind (list-state-mode list)) :vertical)
        (values (list-state-prev-depth list) :dimen)
        (list-quantity-error expander token level))))

(define-internal "prevgraf" (expander token level)
  (values (if (eq (list-state-mode (current-list expander)) :none)
              0
              (list-state-prev-graf (enclosing-vertical-list expander)))
          :int))

(define-internal "deadcycles" (expander token level)
  (values (page-state-dead-cycles (expander-page expander)) :int))

(define-internal "insertpenalties" (expander token level)
  (values (page-state-insert-penalties (expander-page expander)) :int))

(define-internal ("pagegoal" "pagetotal" "pagestretch" "pagefilstretch"
                  "pagefillstretch" "pagefilllstretch" "pageshrink" "pagedepth")
    (expander token level)
  (let ((page (expander-page expander))
        (index (page-dimen-index name)))
    (values (cond ((or (not (eq (page-state-contents page) :empty))
                       (page-state-output-active page))
                   (aref (page-state-so-far page) index))
                  ((zerop index) +max-dimen+)
                  (t 0))
            :dimen)))

(define-internal "parshape" (expander token level)
  (values (length (par-shape (expander-state expander))) :int))

(define-internal ("wd" "ht" "dp") (expander token level)
  (values (box-dimension (register (expander-state expander) :box
                                   (scan-eight-bit-int expander))
                         (cdr (assoc name '(("wd" . :width) ("ht" . :height)
                                            ("dp" . :depth))
                                     :test #'string=)))
          :dimen))

(define-internal "fontdimen" (expander token level)
  (multiple-value-bind (font n) (find-font-dimen expander)
    (values (if font (font-dimen font n) 0) :dimen)))

(define-internal "hyphenchar" (expander token level)
  (values (tex-font-hyphen-char (scan-font-ident expander)) :int))

(define-internal "skewchar" (expander token level)
  (values (tex-font-skew-char (scan-font-ident expander)) :int))

(define-internal ("lastpenalty" "lastkern" "lastskip" "inputlineno" "badness")
    (expander token level)
  (last-item expander name))

(defun read-internal (expander token meaning level)
  "The value and level of the internal command TOKEN with MEANING
(§413), before coercion; NIL and NIL when MEANING is not internal."
  (let ((state (expander-state expander)))
    (typecase meaning
      (tex-font (if (eq level :tok)
                    (values meaning :ident)
                    (missing-number expander token)))
      (shorthand
       (let ((value (shorthand-value meaning)))
         (ecase (shorthand-kind meaning)
           ((:char :mathchar) (values value :int))
           (:count (values (register state :count value) :int))
           (:dimen (values (register state :dimen value) :dimen))
           (:skip (values (register state :skip value) :glue))
           (:muskip (values (register state :muskip value) :mu))
           (:toks (token-list-value expander token level
                                    (register state :toks value))))))
      (primitive
       (let ((reader (gethash (primitive-name meaning) *internal-commands*)))
         (if reader
             (funcall reader expander token level)
             (values nil nil))))
      (t (values nil nil)))))

(defun internal-command-p (meaning)
  "True when MEANING is one of TeX's internal quantities (min_internal to
max_internal, §209): what scan_int and scan_dimen read as a value."
  (typecase meaning
    ((or tex-font shorthand) t)
    (primitive (and (gethash (primitive-name meaning) *internal-commands*) t))))

(defun retag-glue (glue mu-p)
  "GLUE as glue (MU-P false) or mu glue: TeX does not tell them apart once
an error has been reported."
  (if (eq (glue-mu-p glue) mu-p)
      glue
      (make-glue :width (glue-width glue) :stretch (glue-stretch glue)
                 :shrink (glue-shrink glue)
                 :stretch-order (glue-stretch-order glue)
                 :shrink-order (glue-shrink-order glue) :mu-p mu-p)))

(defun mu-error ()
  "TeX's mu_error (§408)."
  (tex-error "Incompatible glue units"))

(defun scan-something-internal (expander token meaning level negative)
  "TeX's scan_something_internal (§413): the value of the internal
quantity TOKEN with MEANING, read at most at LEVEL (:INT, :DIMEN, :GLUE,
:MU or :TOK), coerced down as TeX does (glue to its width, mu glue after
`Incompatible glue units') and negated if NEGATIVE.  A command that is
no quantity is `You can't use x after \\the' and 0.  Returns the value
and its level."
  (multiple-value-bind (value got) (read-internal expander token meaning level)
    (unless got
      (tex-error "You can't use"
                 :context (format nil "`~A' after ~A"
                                  (if token
                                      (meaning-text expander token meaning)
                                      "the end of the input")
                                  (esc expander "the"))
                 :span (and token (token-span token)))
      (setf value 0 got (if (eq level :tok) :int :dimen)))
    (loop while (> (level-rank got) (level-rank level))
          do (ecase got
               (:glue (setf value (glue-width value) got :dimen))
               (:mu (mu-error) (setf value (retag-glue value nil) got :glue))
               (:dimen (setf got :int))))
    (when negative
      (setf value (case got
                    ((:glue :mu) (glue-negate value))
                    ((:int :dimen) (- value))
                    (t value))))
    (values value got)))
