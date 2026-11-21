;;;; src/expand/state.lisp
;;;;
;;;; The expander's state: the reader's TEX-STATE (catcodes, case codes,
;;;; integer parameters, the save stack) plus the rest of TeX's table of
;;;; equivalents (§§220-247): meanings, registers, the other parameters,
;;;; math/space-factor/delimiter codes, the current and family fonts and
;;;; \parshape.  Every table lives under the reader's save stack, so one
;;;; END-GROUP restores them all.  Every assignment goes through STORE,
;;;; which applies \globaldefs (§1214).
;;;;
;;;; Defaults are not stored: an entry never assigned reads as INITEX's
;;;; value, so tables stay small and characters beyond 255 get TeX's rule.

(in-package #:cl-ansi-spec/expand)

(deftype register-kind ()
  "The six kinds of TeX's registers."
  '(member :count :dimen :skip :muskip :toks :box))

(deftype register-number ()
  "TeX82's register numbers."
  '(integer 0 255))

(deftype code-kind ()
  "The character code tables: the reader's (:CATCODE, :LCCODE, :UCCODE)
and the expander's (:MATHCODE, :SFCODE, :DELCODE)."
  '(member :catcode :lccode :uccode :mathcode :sfcode :delcode))

(deftype math-size ()
  "A math size for \\textfont (0), \\scriptfont (1), \\scriptscriptfont (2)."
  '(integer 0 2))

(deftype family-number ()
  "A math family."
  '(integer 0 15))

(defun make-table (name)
  "An empty table of equivalents NAME whose keys below 256 live in vectors."
  (make-equivalents name :default nil :size 256))

(defstruct (expander-state (:constructor %make-expander-state (tex null-font))
                           (:conc-name es-)
                           (:copier nil))
  "Everything an expander job assigns.  TEX is the reader's state, whose
save stack serves every table here."
  (tex nil :type tex-state :read-only t)
  (meanings (make-equivalents 'meaning :default nil) :read-only t)
  (registers (list :count (make-table 'count) :dimen (make-table 'dimen)
                   :skip (make-table 'skip) :muskip (make-table 'muskip)
                   :toks (make-table 'toks) :box (make-table 'box))
   :read-only t)
  (parameters (make-equivalents 'parameter :default nil) :read-only t)
  (codes (list :mathcode (make-table 'mathcode) :sfcode (make-table 'sfcode)
               :delcode (make-table 'delcode))
   :read-only t)
  ;; The family fonts (key 16 * size + family) and the current font (key
  ;; :CURRENT).
  (fonts (make-equivalents 'font :default nil :size 48) :read-only t)
  ;; \parshape, under the key :PARSHAPE.
  (shapes (make-equivalents 'parshape :default nil) :read-only t)
  (null-font nil :type tex-font :read-only t)
  ;; Every font loaded so far, newest first: \font reuses a match.
  (loaded-fonts '() :type list))

(defun make-expander-state (&key (tex (make-initex-state)))
  "A state with INITEX's equivalents on top of the reader state TEX (by
default a fresh INITEX state): every meaning undefined, registers zero,
empty or void, parameters as INITEX sets them, every font \\nullfont.
INITEX's nonzero integer parameters are assigned globally, so TEX should
have no open group."
  (let ((state (%make-expander-state
                tex (make-tex-font "nullfont" :identifier "nullfont"))))
    (loop for (name value) on (initex-integer-parameters) by #'cddr
          do (set-integer-parameter tex name value :global t))
    state))

(defun effective-global (state global)
  "Whether an assignment asked to be global iff GLOBAL is global: a
positive \\globaldefs makes every assignment global, a negative one every
assignment local (§1214)."
  (let ((globaldefs (integer-parameter (es-tex state) :globaldefs)))
    (cond ((plusp globaldefs) t)
          ((minusp globaldefs) nil)
          (t global))))

(defun store (state table key value global)
  "Assign VALUE to KEY of TABLE in STATE, globally if GLOBAL, subject to
\\globaldefs."
  (assign (es-tex state) table key value (effective-global state global)))

;;; Meanings

(defun meaning (state control-sequence)
  "The meaning of CONTROL-SEQUENCE (or active character) in STATE: NIL for
undefined, else a MEANING or a TEX-FONT."
  (equivalent (es-meanings state) control-sequence))

(defun set-meaning (state control-sequence meaning &key global)
  "Give CONTROL-SEQUENCE the MEANING (NIL makes it undefined)."
  (check-type control-sequence control-sequence)
  (check-type meaning (or null meaning tex-font))
  (store state (es-meanings state) control-sequence meaning global))

;;; Registers

(defun zero-glue ()
  "TeX's zero_glue, shared (glue is immutable)."
  (load-time-value (make-glue) t))

(defun zero-mu-glue ()
  "Zero mu glue, the initial value of \\muskip registers and mu parameters."
  (load-time-value (make-glue :mu-p t) t))

(defun quantity-default (kind)
  "The initial value of a register or parameter of KIND."
  (ecase kind
    ((:count :integer :dimen) 0)
    ((:skip :glue) (zero-glue))
    ((:muskip :muglue) (zero-mu-glue))
    ((:toks :tokens :box) nil)))

(defun check-quantity (kind value)
  "Signal a TYPE-ERROR unless VALUE suits a register or parameter of KIND."
  (unless (ecase kind
            ((:count :integer) (typep value 'tex-integer))
            (:dimen (typep value 'scaled))
            ((:skip :glue) (and (glue-p value) (not (glue-mu-p value))))
            ((:muskip :muglue) (and (glue-p value) (glue-mu-p value)))
            ((:toks :tokens) (listp value))
            (:box t))
    (error 'type-error :datum value
                       :expected-type (ecase kind
                                        ((:count :integer) 'tex-integer)
                                        (:dimen 'scaled)
                                        ((:skip :glue :muskip :muglue) 'glue)
                                        ((:toks :tokens) 'list)))))

(defun register-table (state kind)
  "The table of STATE holding the registers of KIND."
  (check-type kind register-kind)
  (getf (es-registers state) kind))

(defun register (state kind n)
  "Register N of KIND (\\count, \\dimen, \\skip, \\muskip, \\toks, \\box).
A token register holds a list of tokens, a box register its contents (NIL
when void)."
  (check-type n register-number)
  (let ((value (equivalent (register-table state kind) n)))
    (if (null value) (quantity-default kind) value)))

(defun set-register (state kind n value &key global)
  "Assign VALUE to register N of KIND."
  (check-type n register-number)
  (check-quantity kind value)
  (store state (register-table state kind) n value global))

;;; Parameters

(defun parameter-kind-or-lose (name)
  "The kind of the TeX82 parameter NAME; an error if there is none."
  (or (parameter-kind name)
      (error "~S is not a TeX82 parameter." name)))

(defun parameter (state name)
  "The value of the TeX82 parameter NAME (:TOLERANCE for \\tolerance)."
  (let ((kind (parameter-kind-or-lose name)))
    (if (eq kind :integer)
        (integer-parameter (es-tex state) name)
        (let ((value (equivalent (es-parameters state) name)))
          (if (null value) (quantity-default kind) value)))))

(defun set-parameter (state name value &key global)
  "Assign VALUE to the TeX82 parameter NAME."
  (let ((kind (parameter-kind-or-lose name)))
    (check-quantity kind value)
    (if (eq kind :integer)
        (set-integer-parameter (es-tex state) name value
                               :global (effective-global state global))
        (store state (es-parameters state) name value global))))

;;; Character codes

(defun code (state kind code)
  "The KIND code (see CODE-KIND) of the character CODE."
  (check-type code character-code)
  (ecase kind
    (:catcode (catcode (es-tex state) code))
    (:lccode (lccode (es-tex state) code))
    (:uccode (uccode (es-tex state) code))
    ((:mathcode :sfcode :delcode)
     (or (equivalent (getf (es-codes state) kind) code)
         (initex-code kind code)))))

(defun set-code (state kind code value &key global)
  "Assign VALUE to the KIND code of character CODE.  The range checks
of §1232 (\"Invalid code\") are the scanner's; here VALUE need only be an
integer."
  (check-type code character-code)
  (check-type value integer)
  (ecase kind
    ((:catcode :lccode :uccode)
     (funcall (ecase kind
                (:catcode #'set-catcode)
                (:lccode #'set-lccode)
                (:uccode #'set-uccode))
              (es-tex state) code value :global (effective-global state global)))
    ((:mathcode :sfcode :delcode)
     (store state (getf (es-codes state) kind) code value global))))

;;; Fonts and \parshape

(defun current-font (state)
  "The current font (\\nullfont initially)."
  (or (equivalent (es-fonts state) :current) (es-null-font state)))

(defun set-current-font (state font &key global)
  "Select FONT."
  (check-type font tex-font)
  (store state (es-fonts state) :current font global))

(defun family-font (state size family)
  "The font of FAMILY in math SIZE (\\textfont, \\scriptfont,
\\scriptscriptfont), \\nullfont initially."
  (check-type size math-size)
  (check-type family family-number)
  (or (equivalent (es-fonts state) (+ (* 16 size) family))
      (es-null-font state)))

(defun set-family-font (state size family font &key global)
  "Assign FONT to FAMILY in math SIZE."
  (check-type size math-size)
  (check-type family family-number)
  (check-type font tex-font)
  (store state (es-fonts state) (+ (* 16 size) family) font global))

(defun par-shape (state)
  "\\parshape as a list of (indent . length) pairs in sp; NIL when unset."
  (equivalent (es-shapes state) :parshape))

(defun set-par-shape (state shape &key global)
  "Assign SHAPE, a list of (indent . length) pairs, to \\parshape."
  (check-type shape list)
  (store state (es-shapes state) :parshape shape global))

(defun load-font (state file &key size (identifier file))
  "The font \\font gets for FILE at SIZE (see NORMALIZE-FONT-SIZE): one
loaded before with the same file and size, else a new font whose
\\hyphenchar and \\skewchar are \\defaulthyphenchar and \\defaultskewchar
(§§1260, 576).  IDENTIFIER names the control sequence being defined."
  (let ((size (normalize-font-size size)))
    (or (find-if (lambda (font)
                   (and (string= file (tex-font-file font))
                        (equal size (tex-font-size font))))
                 (es-loaded-fonts state))
        (let ((font (make-tex-font
                     file :size size :identifier identifier
                     :hyphen-char (parameter state :defaulthyphenchar)
                     :skew-char (parameter state :defaultskewchar))))
          (push font (es-loaded-fonts state))
          font))))
