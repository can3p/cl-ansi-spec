;;;; src/expand/assignments.lisp
;;;;
;;;; The assignments of prefixed_command other than meanings (TeX: The
;;;; Program, §§1226-1264): token lists, parameters and registers with
;;;; \advance, \multiply and \divide, character codes, family fonts,
;;;; \font and font parameters, \setbox, \parshape, the quantities of the
;;;; nest, the page and the boxes, hyphenation data, and the interaction
;;;; modes.  Each follows TeX's scanning order and errors.
;;;;
;;;; A location is where a quantity lives: (:REGISTER kind n) or
;;;; (:PARAMETER keyword).

(in-package #:cl-ansi-spec/expand)

;;; Locations

(defun location-value (state location)
  "The value at LOCATION."
  (ecase (first location)
    (:register (register state (second location) (third location)))
    (:parameter (parameter state (second location)))))

(defun set-location (state location value global)
  "Assign VALUE at LOCATION."
  (ecase (first location)
    (:register (set-register state (second location) (third location) value
                             :global global))
    (:parameter (set-parameter state (second location) value :global global))))

(defun location-level (location)
  "The value level of LOCATION: :INT, :DIMEN, :GLUE, :MU or :TOK."
  (ecase (first location)
    (:register (ecase (second location)
                 (:count :int) (:dimen :dimen) (:skip :glue) (:muskip :mu)
                 (:toks :tok)))
    (:parameter (ecase (parameter-kind (second location))
                  (:integer :int) (:dimen :dimen) (:glue :glue) (:muglue :mu)
                  (:tokens :tok)))))

(defun quantity-location (meaning)
  "The location MEANING names by itself (TeX's assign_int ...
assign_toks): a parameter or a register shorthand; NIL otherwise."
  (typecase meaning
    (primitive (let ((keyword (parameter-keyword (primitive-name meaning))))
                 (and keyword (list :parameter keyword))))
    (shorthand (and (member (shorthand-kind meaning)
                            '(:count :dimen :skip :muskip :toks))
                    (list :register (shorthand-kind meaning)
                          (shorthand-value meaning))))))

(defun register-primitive-kind (meaning)
  "The register kind of \\count, \\dimen, \\skip, \\muskip or \\toks, or NIL."
  (and (primitive-p meaning)
       (cdr (assoc (primitive-name meaning)
                   '(("count" . :count) ("dimen" . :dimen) ("skip" . :skip)
                     ("muskip" . :muskip) ("toks" . :toks))
                   :test #'string=))))

(defun scan-value (expander level)
  "Scan a value of LEVEL (:INT, :DIMEN, :GLUE or :MU)."
  (ecase level
    (:int (scan-int expander))
    (:dimen (values (scan-dimen expander)))
    ((:glue :mu) (scan-glue expander level))))

;;; Token lists (§1226)

(defun assign-token-list (expander token location global)
  "Assign the token list after `=' to LOCATION: another token register or
parameter, or a general text (\\output's in braces).  TOKEN is the
command, for the runaway messages."
  (let ((state (expander-state expander)))
    (scan-optional-equals expander)
    (multiple-value-bind (next meaning) (get-x-nonblank-nonrelax expander)
      (unless (eql (command-catcode next meaning) +begin-group+)
        (let ((source (if (eq (register-primitive-kind meaning) :toks)
                          (list :register :toks (scan-eight-bit-int expander))
                          (let ((other (quantity-location meaning)))
                            (and other (eq (location-level other) :tok) other)))))
          (when source
            (set-location state location (location-value state source) global)
            (return-from assign-token-list))))
      (back-token expander next)
      (let ((tokens (scan-toks expander
                               :warning-index (and (cs-token-p token)
                                                   (cs-token-control-sequence token)))))
        (when (and tokens (equal location '(:parameter :output)))
          (let ((span (token-span token)))
            (setf tokens (append (list (make-character-token
                                        (char-code #\{) +begin-group+ span))
                                 tokens
                                 (list (make-character-token
                                        (char-code #\}) +end-group+ span))))))
        (set-location state location tokens global)))))

(defun assign-parameter (expander token meaning global long outer)
  "A parameter or register shorthand as a command (§§1226-1228): its value
after an optional `='."
  (declare (ignore long outer))
  (let ((location (quantity-location meaning)))
    (if (eq (location-level location) :tok)
        (assign-token-list expander token location global)
        (progn
          (scan-optional-equals expander)
          (set-location (expander-state expander) location
                        (scan-value expander (location-level location))
                        global)))))

(define-assignment "toks" (expander token meaning global)
  (assign-token-list expander token
                     (list :register :toks (scan-eight-bit-int expander))
                     global))

;;; Every parameter is an assignment command.
(dolist (kind '(:integer :dimen :glue :muglue :tokens))
  (dolist (parameter (parameter-names kind))
    (define-primitive (string-downcase (symbol-name parameter))
      :operation #'prefixed-command)))

;;; Registers and arithmetic (§§1235-1240)

(defun register-location (expander command token meaning)
  "The register or parameter TOKEN with MEANING names, reading the
register number of \\count ... \\muskip.  COMMAND names the
\\advance, \\multiply or \\divide it follows, if any, for TeX's `You
can't use x after y'; then the result is NIL."
  (let ((location (quantity-location meaning))
        (kind (register-primitive-kind meaning)))
    (cond ((and location (not (eq (location-level location) :tok))) location)
          ((and kind (not (eq kind :toks)))
           (list :register kind (scan-eight-bit-int expander)))
          (t (tex-error "You can't use"
                        :context (format nil "`~A' after ~A"
                                         (if token
                                             (meaning-text expander token meaning)
                                             "the end of the input")
                                         (esc expander command))
                        :span (and token (token-span token)))
             nil))))

(defun register-arithmetic (old level operation by)
  "OLD at LEVEL after OPERATION (:ADVANCE, :MULTIPLY or :DIVIDE) by BY.
Returns the result and whether the arithmetic overflowed."
  (ecase operation
    (:advance (ecase level
                (:int (integer-advance old by))
                (:dimen (dimen-advance old by))
                ((:glue :mu) (glue-advance old by))))
    (:multiply (ecase level
                 (:int (integer-multiply old by))
                 (:dimen (dimen-multiply old by))
                 ((:glue :mu) (glue-multiply old by))))
    (:divide (ecase level
               (:int (integer-divide old by))
               (:dimen (dimen-divide old by))
               ((:glue :mu) (glue-divide old by))))))

(defun do-register-command (expander token meaning operation global)
  "TeX's do_register_command (§1236): \\count ... \\muskip when OPERATION
is NIL, else \\advance, \\multiply or \\divide (with an optional `by')."
  (let ((location (if operation
                      (multiple-value-bind (next meaning) (get-x-token expander)
                        (register-location expander
                                           (string-downcase (symbol-name operation))
                                           next meaning))
                      (register-location expander nil token meaning)))
        (state (expander-state expander)))
    (when location
      (let ((level (location-level location)))
        (if operation
            (scan-keyword expander "by")
            (scan-optional-equals expander))
        (multiple-value-bind (value overflow)
            (if (null operation)
                (scan-value expander level)
                (register-arithmetic (location-value state location) level operation
                                     (if (eq operation :advance)
                                         (scan-value expander level)
                                         (scan-int expander))))
          (if overflow
              (tex-error "Arithmetic overflow")
              (set-location state location value global)))))))

(define-assignment ("count" "dimen" "skip" "muskip") (expander token meaning global)
  (do-register-command expander token meaning nil global))

(define-assignment ("advance" "multiply" "divide") (expander token meaning global)
  (do-register-command expander token meaning
                       (find-symbol (string-upcase name) :keyword) global))

;;; Character codes and family fonts (§§1230-1234)

(defun code-limit (kind)
  "The largest value of a code of KIND (§1232)."
  (ecase kind
    (:catcode 15) (:mathcode #o100000) (:sfcode #o77777) (:delcode #o77777777)
    ((:lccode :uccode) 255)))

(define-assignment ("catcode" "mathcode" "lccode" "uccode" "sfcode" "delcode")
    (expander token meaning global)
  (let* ((kind (find-symbol (string-upcase name) :keyword))
         (limit (code-limit kind))
         (char (scan-char-num expander)))
    (scan-optional-equals expander)
    (let ((value (scan-int expander)))
      (when (or (and (minusp value) (not (eq kind :delcode))) (> value limit))
        (tex-error "Invalid code"
                   :context (format nil (if (eq kind :delcode)
                                            "(~D), should be at most ~D"
                                            "(~D), should be in the range 0..~D")
                                    value limit))
        (setf value 0))
      (set-code (expander-state expander) kind char value :global global))))

(define-assignment ("textfont" "scriptfont" "scriptscriptfont")
    (expander token meaning global)
  (let ((family (scan-four-bit-int expander)))
    (scan-optional-equals expander)
    (set-family-font (expander-state expander) (family-size name) family
                     (scan-font-ident expander) :global global)))

;;; Fonts (§§1253-1260)

(defun select-font (expander token meaning global long outer)
  "A font identifier as a command: select the font (§1217)."
  (declare (ignore token long outer))
  (set-current-font (expander-state expander) meaning :global global))

(defun font-identifier-name (cs)
  "The identifier \\font gives a font named by CS (§1257): its name, or
`FONT' and the character for an active character, `FONT' for the empty
control sequence."
  (cond ((control-sequence-active-p cs)
         (concatenate 'string "FONT" (control-sequence-name cs)))
        ((string= (control-sequence-name cs) "") "FONT")
        (t (control-sequence-name cs))))

(defun scan-font-size (expander)
  "The size after \\font's file name (§1258): (:AT sp), (:SCALED n) or
NIL, with TeX's errors and replacements."
  (setf (expander-name-in-progress expander) t)
  (unwind-protect
       (cond ((scan-keyword expander "at")
              (let ((size (scan-dimen expander)))
                (unless (< 0 size (* 2048 +unity+))
                  (tex-error (format nil "Improper `at' size (~Apt), replaced by 10pt"
                                     (format-scaled size)))
                  (setf size (* 10 +unity+)))
                (list :at size)))
             ((scan-keyword expander "scaled")
              (let ((scale (scan-int expander)))
                (unless (<= 1 scale 32768)
                  (tex-error "Illegal magnification has been changed to 1000"
                             :context (int-error-context scale))
                  (setf scale 1000))
                (list :scaled scale))))
    (setf (expander-name-in-progress expander) nil)))

(define-assignment "font" (expander token meaning global)
  ;; new_font (§1257): the name means \nullfont while the file and size
  ;; are read; the font takes the name as its identifier.
  (let* ((state (expander-state expander))
         (cs (get-r-token expander))
         (identifier (font-identifier-name cs)))
    (set-meaning state cs (es-null-font state) :global global)
    (scan-optional-equals expander)
    (let* ((file (scan-file-name expander))
           (font (load-font state file :size (scan-font-size expander)
                                       :identifier identifier)))
      (setf (tex-font-identifier font) identifier)
      (set-meaning state cs font :global global))))

(define-assignment "fontdimen" (expander token meaning global)
  (multiple-value-bind (font n) (find-font-dimen expander)
    (scan-optional-equals expander)
    (let ((value (scan-dimen expander)))
      (when font
        (set-font-dimen font n value)))))

(define-assignment ("hyphenchar" "skewchar") (expander token meaning global)
  (let ((font (scan-font-ident expander)))
    (scan-optional-equals expander)
    (let ((value (scan-int expander)))
      (if (string= name "hyphenchar")
          (setf (tex-font-hyphen-char font) value)
          (setf (tex-font-skew-char font) value)))))

;;; Boxes, \parshape, the nest and the page (§§1241-1248)

(define-assignment "setbox" (expander token meaning global)
  (let ((n (scan-eight-bit-int expander)))
    (scan-optional-equals expander)
    (if (expander-set-box-allowed expander)
        (scan-box expander (list :setbox n global))
        ;; §1241: not while a \write is expanded (streams.lisp).
        (tex-error "Improper" :context (esc expander "setbox")
                              :span (token-span token)))))

(define-assignment ("wd" "ht" "dp") (expander token meaning global)
  ;; Box dimensions are changed in place, never saved (§1247).
  (let ((box (register (expander-state expander) :box (scan-eight-bit-int expander))))
    (scan-optional-equals expander)
    (let ((value (scan-dimen expander)))
      (setf (box-dimension box (cdr (assoc name '(("wd" . :width) ("ht" . :height)
                                                  ("dp" . :depth))
                                           :test #'string=)))
            value))))

(define-assignment "parshape" (expander token meaning global)
  (scan-optional-equals expander)
  (let ((n (scan-int expander)))
    (set-par-shape (expander-state expander)
                   (loop repeat (max n 0)
                         collect (let ((indent (scan-dimen expander)))
                                   (cons indent (values (scan-dimen expander)))))
                   :global global)))

(define-assignment ("spacefactor" "prevdepth") (expander token meaning global)
  ;; alter_aux (§1243): only in its own mode, and never saved.
  (let ((list (current-list expander))
        (vertical (string= name "prevdepth")))
    (if (not (eq (mode-kind (list-state-mode list)) (if vertical :vertical :horizontal)))
        (report-illegal-case expander token meaning)
        (progn
          (scan-optional-equals expander)
          (if vertical
              (setf (list-state-prev-depth list) (values (scan-dimen expander)))
              (let ((value (scan-int expander)))
                (if (<= 1 value 32767)
                    (setf (list-state-space-factor list) value)
                    (tex-error "Bad space factor"
                               :context (int-error-context value)))))))))

(define-assignment "prevgraf" (expander token meaning global)
  ;; alter_prev_graf (§1244): the enclosing vertical list's.
  (scan-optional-equals expander)
  (let ((value (scan-int expander))
        (list (enclosing-vertical-list expander)))
    (cond ((minusp value)
           (tex-error (format nil "Bad ~A" (esc expander "prevgraf"))
                      :context (int-error-context value)))
          (list (setf (list-state-prev-graf list) value)))))

(define-assignment ("pagegoal" "pagetotal" "pagestretch" "pagefilstretch"
                    "pagefillstretch" "pagefilllstretch" "pageshrink" "pagedepth")
    (expander token meaning global)
  (scan-optional-equals expander)
  (setf (aref (page-state-so-far (expander-page expander)) (page-dimen-index name))
        (values (scan-dimen expander))))

(define-assignment ("deadcycles" "insertpenalties") (expander token meaning global)
  (scan-optional-equals expander)
  (let ((value (scan-int expander))
        (page (expander-page expander)))
    (if (string= name "deadcycles")
        (setf (page-state-dead-cycles page) value)
        (setf (page-state-insert-penalties page) value))))

;;; Hyphenation data (§§934-963), kept as read

(defun letter-command (token meaning)
  "The character code of a letter or other character command, or NIL."
  (let ((catcode (command-catcode token meaning)))
    (and (member catcode (list +letter+ +other+))
         (if (character-token-p token)
             (character-token-code token)
             (character-meaning-code meaning)))))

(defun scan-patterns (expander)
  "TeX's new_patterns (§§961-963) while the trie is not ready: the
patterns of the current language, as (language letters levels), letters
lowercased by \\lccode and 0 for `.'."
  (let* ((state (expander-state expander))
         (language (current-language expander))
         (seen (make-hash-table :test 'equal)))
    (dolist (pattern (expander-patterns expander))
      (setf (gethash (list (first pattern) (second pattern)) seen) t))
    (scan-left-brace expander)
    (let ((letters '()) (levels (list 0)) (digit-sensed nil))
      (loop
        (multiple-value-bind (token meaning) (get-x-token expander)
          (let ((code (letter-command token meaning))
                (catcode (command-catcode token meaning)))
            (cond
              (code
               (if (or digit-sensed (not (<= (char-code #\0) code (char-code #\9))))
                   (let ((letter (if (= code (char-code #\.)) 0 (code state :lccode code))))
                     (when (and (/= code (char-code #\.)) (zerop letter))
                       (tex-error "Nonletter"))
                     (when (< (length letters) 63)
                       (push letter letters)
                       (push 0 levels)
                       (setf digit-sensed nil)))
                   (when (< (length letters) 63)
                     (setf (first levels) (- code (char-code #\0))
                           digit-sensed t))))
              ((or (null token) (eql catcode +space+) (eql catcode +end-group+))
               (when letters
                 (let ((key (list language (reverse letters))))
                   (if (gethash key seen)
                       (tex-error "Duplicate pattern")
                       (let ((levels (reverse levels)))
                         ;; No hyphen at the edge of a word (§963).
                         (when (zerop (first letters))
                           (setf (car (last levels)) 0))
                         (when (zerop (car (last letters)))
                           (setf (first levels) 0))
                         (setf (gethash key seen) t)
                         (push (list language (reverse letters) levels)
                               (expander-patterns expander))))))
               (when (or (null token) (eql catcode +end-group+))
                 (return))
               (setf letters '() levels (list 0) digit-sensed nil))
              (t (tex-error (format nil "Bad ~A" (esc expander "patterns")))))))))))

(defun scan-hyphenation (expander)
  "TeX's new_hyph_exceptions (§§934-939): words of the current language
with their hyphen positions, as (language letters positions)."
  (let ((state (expander-state expander))
        (language (current-language expander))
        (letters '()) (positions '()))
    (scan-left-brace expander)
    (loop
      (multiple-value-bind (token meaning) (get-x-token expander)
        (let* ((catcode (command-catcode token meaning))
               (code (or (letter-command token meaning)
                         (and (shorthand-p meaning) (eq (shorthand-kind meaning) :char)
                              (shorthand-value meaning))
                         (and (primitive-named-p meaning "char")
                              (scan-char-num expander)))))
          (cond
            ((and code (= code (char-code #\-)))
             (push (length letters) positions))
            (code
             (let ((letter (code state :lccode code)))
               (cond ((zerop letter) (tex-error "Not a letter"))
                     ((< (length letters) 63) (push letter letters)))))
            ((or (null token) (eql catcode +space+) (eql catcode +end-group+))
             (when (> (length letters) 1)
               (push (list language (reverse letters) (reverse positions))
                     (expander-hyphenation-exceptions expander)))
             (when (or (null token) (eql catcode +end-group+))
               (return))
             (setf letters '() positions '()))
            (t (tex-error (format nil "Improper ~A will be flushed"
                                  (esc expander "hyphenation"))))))))))

(define-assignment ("hyphenation" "patterns") (expander token meaning global)
  (cond ((string= name "hyphenation") (scan-hyphenation expander))
        ((expander-trie-not-ready expander) (scan-patterns expander))
        (t
         ;; §960: the patterns are read and forgotten.
         (tex-error (format nil "Too late for ~A" (esc expander "patterns")))
         (scan-toks expander :warning-index (cs-token-control-sequence token)))))

;;; Interaction (§1264)

(define-assignment ("batchmode" "nonstopmode" "scrollmode" "errorstopmode")
    (expander token meaning global)
  (setf (expander-interaction expander)
        (cdr (assoc name '(("batchmode" . :batch) ("nonstopmode" . :nonstop)
                           ("scrollmode" . :scroll) ("errorstopmode" . :error-stop))
                    :test #'string=))))
