;;;; src/expand/math-lists.lisp
;;;;
;;;; Math lists (TeX: The Program, §§1136-1193; their end, §§1194-1197,
;;;; is AFTER-MATH's in modes.lisp): the noads main control
;;;; appends in math mode, without TeX's conversion to boxes
;;;; (mlist_to_hlist), which needs metrics.  A noad is a :NOAD node of a
;;;; :CLASS; its children are its non-empty fields, :NUCLEUS, :SUPERSCRIPT
;;;; and :SUBSCRIPT (*NOAD-FIELDS*), each holding a :MATH-CHAR, a box
;;;; node or the nodes of a sub-mlist (docs/events.md).  SCAN-MATH fills a
;;;; field (§1151): a math character at once, a subformula in braces in a
;;;; math group whose context is (noad field span).  Generalized
;;;; fractions are the list's incompleat noad until FIN-MLIST (§1184);
;;;; \left opens a math-left group closed by \right (§1191), \mathchoice
;;;; four math-choice groups (§§1172-1174), \vcenter a vcenter group
;;;; (§§1167-1168).

(in-package #:cl-ansi-spec/expand)

(defconstant +var-code+ #x7000
  "TeX's var_code: math codes from here use \\fam (§232).")

(defparameter *noad-fields* '(:nucleus :superscript :subscript)
  "The fields of a noad, in their order among its children.")

(defparameter *math-classes* #(:ord :op :bin :rel :open :close :punct)
  "The classes of math codes 0-6 (§1155); class 7 is :ORD.")

;;; Noads and fields

(defun make-noad (class span &optional properties)
  "A noad of CLASS read at SPAN with PROPERTIES after its class, and no
fields yet."
  (make-node :noad :properties (list* :class class properties) :children '() :span span))

(defun noad-class (node)
  "The class of NODE when it is a noad, else NIL."
  (and (eq (node-kind node) :noad) (getf (node-properties node) :class)))

(defun noad-field (node kind)
  "The field KIND of the noad or fraction NODE, or NIL when it is empty."
  (find kind (node-children node) :key #'node-kind))

(defun set-noad-field (noad kind contents &key span end-span)
  "Make the field KIND of NOAD hold CONTENTS (nodes), in its place among
the fields; returns the field."
  (let ((field (make-node kind :children contents :span span :end-span end-span)))
    (setf (node-children noad)
          (stable-sort (cons field (remove kind (node-children noad) :key #'node-kind))
                       #'< :key (lambda (node)
                                  (or (position (node-kind node) *noad-fields*) 0))))
    field))

(defun box-noad (node)
  "An ord noad whose nucleus is the box (or indentation) NODE: a box in a
math list (§§1076, 1093)."
  (let ((noad (make-noad :ord (node-span node))))
    (set-noad-field noad :nucleus (list node) :span (node-span node))
    noad))

;;; Math characters (§§1151-1155)

(defun character-code (token meaning)
  "The character code TOKEN with MEANING stands for: a letter or other
character, one \\let to it, or a \\chardef."
  (cond ((shorthand-p meaning) (shorthand-value meaning))
        ((character-meaning-p meaning) (character-meaning-code meaning))
        (t (character-token-code token))))

(defun math-char-node (expander c span)
  "The :MATH-CHAR of the math code C (15 bits) read at SPAN: its family,
\\fam for a variable code when \\fam is 0-15, and its character."
  (let ((fam (parameter (expander-state expander) :fam)))
    (make-node :math-char
               :properties (list :fam (if (and (>= c +var-code+) (<= 0 fam 15))
                                          fam
                                          (mod (floor c 256) 16))
                                 :code (mod c 256))
               :span span)))

(defun treat-as-active (expander code span)
  "§1152: the character CODE, of math code \"8000, read again as an
active character; returns its token."
  (make-cs-token (intern-active-character (expander-tex expander) code) span))

(defun set-math-char (expander c code span)
  "TeX's set_math_char (§1155) for the math code C of the character CODE
read at SPAN: a noad of the code's class whose nucleus is the character;
\"8000 reads CODE again as an active character."
  (if (>= c #x8000)
      (back-token expander (treat-as-active expander code span))
      (let ((noad (make-noad (if (>= c +var-code+) :ord (aref *math-classes* (floor c #x1000)))
                             span)))
        (set-noad-field noad :nucleus (list (math-char-node expander c span)) :span span)
        (append-node expander noad))))

(defun math-char-code (expander key token meaning)
  "The math code of the math character that the command KEY (TOKEN with
MEANING) begins (§§1151, 1154), its operand scanned: a character's or
\\char's \\mathcode, \\mathchar's number, a \\mathchardef's, or
\\delimiter's divided by 4096.  The second value is the character's code,
for a math code of \"8000.  NIL when KEY is no math character."
  (flet ((by-math-code (code)
           (values (code (expander-state expander) :mathcode code) code)))
    (cond ((member key '(:letter :other-char :char-given))
           (by-math-code (character-code token meaning)))
          ((equal key "char") (by-math-code (scan-char-num expander)))
          ((equal key "mathchar") (values (scan-fifteen-bit-int expander) 0))
          ((eq key :math-given) (values (shorthand-value meaning) 0))
          ((equal key "delimiter")
           (values (floor (scan-twenty-seven-bit-int expander) #o10000) 0)))))

(defun math-character (expander key token meaning)
  "Main control's math character (§1154) for the command KEY: a character,
\\char, \\mathchar, a \\mathchardef or \\delimiter."
  (multiple-value-bind (c code) (math-char-code expander key token meaning)
    (set-math-char expander c code (token-span token))))

(define-command ("mathchar" "delimiter") (expander token meaning)
  (math-character expander name token meaning))

(defun scan-math (expander noad field)
  "TeX's scan_math (§1151): fill FIELD of NOAD from what follows blanks
and \\relax: a math character, or a subformula in braces, read in a math
group (END-MATH-GROUP)."
  (loop
    (multiple-value-bind (token meaning) (get-x-nonblank-nonrelax expander)
      (let ((span (and token (token-span token))))
        (multiple-value-bind (c code)
            (and token (math-char-code expander (command-key token meaning) token meaning))
          (cond ((null c)
                 (when token
                   (back-token expander token))
                 (scan-left-brace expander)
                 (push-math expander :math :span span :context (list noad field span))
                 (return))
                ((= c #x8000)
                 (back-token expander (treat-as-active expander code span)))
                (t
                 (set-noad-field noad field (list (math-char-node expander c span)) :span span)
                 (return))))))))

(defun end-math-group (expander token)
  "The `}' TOKEN of a math group (§§1186-1187): the subformula fills its
field.  One ord noad without scripts gives its nucleus instead; one
accent noad as the nucleus of the ord noad ending the list replaces that
noad."
  (let* ((group (unsave expander))
         (nodes (fin-mlist expander))
         (only (and nodes (null (rest nodes)) (first nodes)))
         (list (current-list expander)))
    (destructuring-bind (noad field span) (group-record-context group)
      (cond ((and only (eq (noad-class only) :ord)
                  (null (noad-field only :superscript)) (null (noad-field only :subscript)))
             (let ((nucleus (noad-field only :nucleus)))
               (if nucleus
                   (set-noad-field noad field (node-children nucleus)
                                   :span (node-span nucleus)
                                   :end-span (node-end-span nucleus))
                   ;; An empty nucleus copied: the field stays empty.
                   (setf (node-children noad)
                         (remove field (node-children noad) :key #'node-kind)))))
            ((and only (eq (noad-class only) :accent) (eq field :nucleus)
                  (eq noad (first (list-state-contents list))) (eq (noad-class noad) :ord))
             (remove-last-node list)
             (append-node expander only))
            (t (set-noad-field noad field nodes :span span :end-span (token-span token)))))))

(defun fin-mlist (expander &optional last)
  "TeX's fin_mlist (§1184): end the current math list, popping it, with
LAST (a :RIGHT node) at its end.  Its incompleat fraction gets the list
as its denominator and becomes the list (after its \\left, before LAST).
Returns the nodes, then the list popped."
  (let* ((list (pop-nest expander))
         (nodes (list-nodes list))
         (fraction (list-state-incompleat list)))
    (values (cond ((null fraction) (if last (append nodes (list last)) nodes))
                  (t
                   (setf (node-children fraction)
                         (append (node-children fraction)
                                 (list (make-node :denominator :children nodes
                                                               :span (node-span fraction)))))
                   (if (null last)
                       (list fraction)
                       (let* ((numerator (noad-field fraction :numerator))
                              (left (first (node-children numerator))))
                         (setf (node-children numerator) (rest (node-children numerator)))
                         (list left fraction last)))))
            list)))

;;; Scripts (§§1175-1177)

(defun scripts-allowed-p (node)
  "TeX's scripts_allowed: NODE is a noad or a fraction."
  (and node (member (node-kind node) '(:noad :fraction)) t))

(defun sub-sup (expander token key)
  "TeX's sub_sup (§1176) for `^' or `_' (KEY :SUP-MARK or :SUB-MARK): the
script of the noad ending the list, or of a new ord noad when there is
none or the script is there already (`Double superscript')."
  (let* ((span (token-span token))
         (field (if (eq key :sup-mark) :superscript :subscript))
         (tail (first (list-state-contents (current-list expander))))
         (noad (and (scripts-allowed-p tail) tail)))
    (when (or (null noad) (noad-field noad field))
      (let ((double (and noad t)))
        (setf noad (append-node expander (make-noad :ord span)))
        (when double
          (tex-error (if (eq field :superscript) "Double superscript" "Double subscript")
                     :span span))))
    (scan-math expander noad field)))

;;; Noad commands (§§1156-1168)

(define-command ("mathord" "mathop" "mathbin" "mathrel" "mathopen" "mathclose"
                 "mathpunct" "mathinner" "underline" "overline")
    (expander token meaning)
  ;; math_comp (§1158)
  (let ((class (intern (string-upcase (if (string= (subseq name 0 4) "math")
                                          (subseq name 4)
                                          name))
                       :keyword)))
    (scan-math expander (append-node expander (make-noad class (token-span token)))
               :nucleus)))

(define-command ("limits" "nolimits" "displaylimits") (expander token meaning)
  ;; §1159: the limits of the op noad ending the list.
  (let ((tail (first (list-state-contents (current-list expander)))))
    (if (and tail (eq (noad-class tail) :op))
        (if (string= name "displaylimits")
            (remf (node-properties tail) :limits)
            (let ((limits (if (string= name "limits") :limits :no-limits)))
              ;; After :CLASS, where the event shows it.
              (if (getf (node-properties tail) :limits)
                  (setf (getf (node-properties tail) :limits) limits)
                  (setf (node-properties tail)
                        (append (node-properties tail) (list :limits limits))))))
        (tex-error "Limit controls must follow a math operator" :span (token-span token)))))

(defun delimiter-fields (value)
  "The delimiter code VALUE as its four fields: (small-fam small-code
large-fam large-code)."
  (list (mod (floor value #o4000000) 16) (mod (floor value #o10000) 256)
        (mod (floor value 256) 16) (mod value 256)))

(defun scan-delimiter (expander radical)
  "TeX's scan_delimiter (§1160): after \\radical (RADICAL) a 27-bit
number, else a character's \\delcode or \\delimiter's number; anything
else, or a negative \\delcode, is `Missing delimiter (. inserted)', read
again, and the null delimiter.  Returns DELIMITER-FIELDS."
  (if radical
      (delimiter-fields (scan-twenty-seven-bit-int expander))
      (multiple-value-bind (token meaning) (get-x-nonblank-nonrelax expander)
        (let* ((key (and token (command-key token meaning)))
               (value (cond ((member key '(:letter :other-char))
                             (code (expander-state expander) :delcode
                                   (character-code token meaning)))
                            ((equal key "delimiter") (scan-twenty-seven-bit-int expander))
                            (t -1))))
          (when (minusp value)
            (when token
              (back-token expander token))
            (tex-error "Missing delimiter (. inserted)" :span (and token (token-span token)))
            (setf value 0))
          (delimiter-fields value)))))

(define-command "radical" (expander token meaning)
  ;; §1163
  (let ((delimiter (scan-delimiter expander t)))
    (scan-math expander (append-node expander (make-noad :radical (token-span token)
                                                         (list :delimiter delimiter)))
               :nucleus)))

(defun math-accent (expander token meaning)
  "TeX's math_ac (§1165) for \\mathaccent or \\accent (`Please use
\\mathaccent') read as TOKEN with MEANING: an accent noad of the
15-bit code's character, whose nucleus follows."
  (let ((span (token-span token)))
    (when (primitive-named-p meaning "accent")
      (tex-error (format nil "Please use ~A for accents in math mode" (esc expander "mathaccent"))
                 :span span))
    (let ((char (math-char-node expander (scan-fifteen-bit-int expander) span)))
      (scan-math expander (append-node expander (make-noad :accent span (node-properties char)))
                 :nucleus))))

(define-command "mathaccent" (expander token meaning)
  (math-accent expander token meaning))

(define-command "vcenter" (expander token meaning)
  ;; §1167: like \vbox, with no box context.
  (scan-spec expander :vcenter nil token meaning)
  (normal-paragraph expander)
  (push-nest expander :internal-vertical (token-span token))
  (setf (list-state-prev-depth (current-list expander)) +ignore-depth+)
  (begin-token-list expander (parameter (expander-state expander) :everyvbox) :every-vbox))

(defun end-vcenter (expander token)
  "The `}' TOKEN of a vcenter group (§1168): a vcenter noad whose nucleus
is the vbox of the list."
  (end-graf expander (token-span token))
  (let* ((group (unsave expander))
         (list (pop-nest expander))
         (start (group-record-token group))
         (box (make-tex-box :vbox :command "vcenter" :spec (group-record-spec group)
                                  :contents (list-nodes list)
                                  :span (and start (token-span start))))
         (noad (make-noad :vcenter (tex-box-span box))))
    (set-noad-field noad :nucleus (list (box-node box)) :span (tex-box-span box)
                                                         :end-span (token-span token))
    (append-node expander noad)))

;;; Styles, choices, math glue and kerns (§§1057-1061, 1169-1174)

(define-command ("displaystyle" "textstyle" "scriptstyle" "scriptscriptstyle")
    (expander token meaning)
  (append-node expander
               (make-node :math-style
                          :properties (list :style (intern (string-upcase
                                                            (subseq name 0 (- (length name) 5)))
                                                           :keyword))
                          :span (token-span token))))

(define-command "nonscript" (expander token meaning)
  ;; §1171: glue of zero, cancelled in script styles.
  (append-node expander (glue-node (make-glue) "nonscript" (token-span token))))

(define-command "mskip" (expander token meaning)
  (append-node expander (glue-node (scan-glue expander :mu) "mskip" (token-span token))))

(define-command "mkern" (expander token meaning)
  (let ((width (scan-dimen expander :mu t)))
    (append-node expander (make-node :kern :properties (list :width (concatenate 'string
                                                                                (format-scaled width)
                                                                                "mu")
                                                             :mu t)
                                           :value width :span (token-span token)))))

(defparameter *choice-styles* #(:display :text :script :scriptscript)
  "The styles of \\mathchoice's four lists, in order.")

(defun begin-choice (expander choice index)
  "Read list INDEX of the :MATH-CHOICE node CHOICE in a math-choice
group (§§1172, 1174)."
  (push-math expander :math-choice :span (node-span choice) :context (cons choice index))
  (scan-left-brace expander))

(define-command "mathchoice" (expander token meaning)
  (begin-choice expander (append-node expander (make-node :math-choice :children '()
                                                                       :span (token-span token)))
                0))

(defun build-choices (expander token)
  "TeX's build_choices (§1174) at the `}' TOKEN of a math-choice group:
the list becomes the next :CHOICE of the node; after the fourth, the
node is done."
  (let* ((group (unsave expander))
         (nodes (fin-mlist expander)))
    (destructuring-bind (choice . index) (group-record-context group)
      (setf (node-children choice)
            (append (node-children choice)
                    (list (make-node :choice :properties (list :style (aref *choice-styles* index))
                                             :children nodes :span (node-span choice)
                                             :end-span (token-span token)))))
      (when (< index 3)
        (begin-choice expander choice (1+ index))))))

;;; Generalized fractions (§§1178-1183)

(define-command ("above" "over" "atop" "abovewithdelims" "overwithdelims" "atopwithdelims")
    (expander token meaning)
  (let* ((list (current-list expander))
         (span (token-span token))
         (delimited (search "withdelims" name))
         (base (subseq name 0 (or delimited (length name)))))
    (if (list-state-incompleat list)
        (progn
          (when delimited
            (scan-delimiter expander nil)
            (scan-delimiter expander nil))
          (when (string= base "above")
            (scan-dimen expander))
          (tex-error "Ambiguous; you need another { and }" :span span))
        (let* ((left (and delimited (scan-delimiter expander nil)))
               (right (and delimited (scan-delimiter expander nil)))
               (thickness (cond ((string= base "above") (format-dimen (scan-dimen expander)))
                                ((string= base "over") :default)
                                (t (format-dimen 0)))))
          (setf (list-state-incompleat list)
                (make-node :fraction
                           :properties (append (list :command name :thickness thickness)
                                               (when delimited
                                                 (list :left-delimiter left
                                                       :right-delimiter right)))
                           :children (list (make-node :numerator :children (list-nodes list)
                                                                 :span span))
                           :span span)
                (list-state-contents list) '())))))

;;; \left and \right (§§1188-1191)

(define-command ("left" "right") (expander token meaning)
  (let ((span (token-span token))
        (group (current-group-code expander)))
    (if (and (string= name "right") (not (eq group :math-left)))
        (if (eq group :math-shift)
            (progn (scan-delimiter expander nil)
                   (tex-error (format nil "Extra ~A" (esc expander "right")) :span span))
            (off-save expander token meaning))
        (let ((delimiter (make-node (if (string= name "left") :left :right)
                                    :properties (list :delimiter (scan-delimiter expander nil))
                                    :span span)))
          (if (string= name "left")
              (progn (push-math expander :math-left :span span)
                     (append-node expander delimiter))
              (multiple-value-bind (nodes list) (fin-mlist expander delimiter)
                (unsave expander)
                (let ((noad (make-noad :inner (list-state-span list))))
                  (set-noad-field noad :nucleus nodes :span (list-state-span list)
                                                      :end-span span)
                  (append-node expander noad))))))))
