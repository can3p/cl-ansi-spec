;;;; src/expand/main-control.lisp
;;;;
;;;; TeX's main_control (TeX: The Program, §§1029-1054, 1063-1066, 1135,
;;;; 1335): read with get_x_token and carry out each command by mode.  A
;;;; command first meets TeX's rules of mode (a paragraph starts, a
;;;; paragraph ends before a vertical command, `$' is inserted, or `You
;;;; can't use'); then main control's own commands run their operation,
;;;; and the rest are handed on (UNHANDLED-COMMAND, commands.lisp).  The
;;;; job ends at \end or \dump with TeX's final_cleanup.
;;;;
;;;; A command is keyed by its primitive's name, or by a keyword for a
;;;; character command (:LETTER, :MATH-SHIFT, ...: TeX's cur_cmd), a
;;;; character or math character shorthand (:CHAR-GIVEN, :MATH-GIVEN), or
;;;; an assignment that is no primitive (:ASSIGNMENT: a font identifier or
;;;; a register shorthand).

(in-package #:cl-ansi-spec/expand)

(defun command-key (token meaning)
  "The key of the command TOKEN with MEANING (see the file header)."
  (let ((catcode (command-catcode token meaning)))
    (cond
      (catcode
       (ecase catcode
         (#.+begin-group+ :left-brace) (#.+end-group+ :right-brace)
         (#.+math-shift+ :math-shift) (#.+alignment-tab+ :tab-mark)
         (#.+parameter+ :mac-param) (#.+superscript+ :sup-mark)
         (#.+subscript+ :sub-mark) (#.+space+ :spacer)
         (#.+letter+ :letter) (#.+other+ :other-char)))
      ((primitive-p meaning) (primitive-name meaning))
      ((and (shorthand-p meaning) (eq (shorthand-kind meaning) :char)) :char-given)
      ((and (shorthand-p meaning) (eq (shorthand-kind meaning) :mathchar)) :math-given)
      (t :assignment))))

;;; TeX's cases by mode (§§1045-1048, 1090, 1094)

(defparameter *paragraph-starters*
  '(:letter :other-char :char-given :math-shift "char" "unhbox" "unhcopy"
    "vrule" "accent" "discretionary" "-" "hskip" "hfil" "hfill" "hss"
    "hfilneg" "valign" " " "noboundary")
  "Commands that begin a paragraph in vertical mode (§1090).")

(defparameter *vertical-commands*
  '("end" "dump" "vskip" "vfil" "vfill" "vss" "vfilneg" "hrule" "unvbox"
    "unvcopy" "halign")
  "Commands that end a paragraph first in horizontal mode (§1094).")

(defparameter *math-enders*
  '("par" "end" "dump" "vskip" "vfil" "vfill" "vss" "vfilneg" "unvbox"
    "unvcopy" "valign" "hrule")
  "Commands that need math to end first (§1046).")

(defparameter *math-only-commands*
  '(:sup-mark :sub-mark :math-given "mathchar" "mathord" "mathop" "mathbin"
    "mathrel" "mathopen" "mathclose" "mathpunct" "mathinner" "underline"
    "overline" "delimiter" "left" "right" "above" "over" "atop"
    "abovewithdelims" "overwithdelims" "atopwithdelims" "radical"
    "displaystyle" "textstyle" "scriptstyle" "scriptscriptstyle"
    "mathchoice" "vcenter" "nonscript" "mkern" "limits" "nolimits"
    "displaylimits" "mskip" "mathaccent")
  "Commands that need math to begin first (§1046).")

(defparameter *illegal-commands*
  '((:vertical "raise" "lower" "vadjust" "/")
    (:horizontal "moveleft" "moveright" "eqno" "leqno")
    (:vertical "eqno" "leqno")
    (:math "moveleft" "moveright")
    (t :mac-param))
  "Commands TeX forbids in a kind of mode, or in every mode (T): `You
can't use x in y mode' (§1048).")

(defun key-member-p (key list)
  "True when the command KEY is in LIST."
  (and (member key list :test #'equal) t))

(defun mode-case (key kind)
  "What TeX does first with the command KEY in a mode of KIND (:VERTICAL,
:HORIZONTAL or :MATH): :NEW-GRAF, :HEAD-FOR-VMODE, :INSERT-DOLLAR,
:ILLEGAL, or NIL when the command's own operation decides."
  (cond ((loop for (mode . keys) in *illegal-commands*
               thereis (and (or (eq mode t) (eq mode kind)) (key-member-p key keys)))
         :illegal)
        ((eq kind :vertical)
         (cond ((key-member-p key *paragraph-starters*) :new-graf)
               ((key-member-p key *math-only-commands*) :insert-dollar)))
        ((eq kind :horizontal)
         (cond ((key-member-p key *vertical-commands*) :head-for-vmode)
               ((key-member-p key *math-only-commands*) :insert-dollar)))
        ((eq kind :math)
         (and (key-member-p key *math-enders*) :insert-dollar))))

;;; The dispatch

(defun character-command (expander key token meaning)
  "Main control for a character command KEY: braces, `$', characters and
spaces of text, and what is handed on (math characters, `&', `^' and
`_')."
  (let ((kind (mode-kind (current-mode expander))))
    (ecase key
      (:left-brace (if (eq kind :math)
                       (push-math expander :math (token-span token))
                       (new-save-level expander :simple)))
      (:right-brace (handle-right-brace expander token))
      (:math-shift (if (eq kind :horizontal)
                       (init-math expander (token-span token))
                       (if (eq (current-group-code expander) :math-shift)
                           (after-math expander (token-span token))
                           (off-save expander token meaning))))
      (:spacer (when (eq kind :horizontal)
                 ;; §1041
                 (append-space expander token nil)))
      ((:letter :other-char :char-given)
       (if (eq kind :horizontal)
           (append-character expander
                             (cond ((eq key :char-given) (shorthand-value meaning))
                                   ((character-meaning-p meaning)
                                    (character-meaning-code meaning))
                                   (t (character-token-code token)))
                             (token-span token))
           (hand-on expander token meaning :event)))
      ((:math-given :sup-mark :sub-mark)
       (hand-on expander token meaning :event))
      (:tab-mark (hand-on expander token meaning :alignment)))))

(defun dispatch (expander token meaning)
  "Carry out the command TOKEN with MEANING (§1045)."
  (let* ((key (command-key token meaning))
         (kind (mode-kind (current-mode expander))))
    (ecase (mode-case key kind)
      (:new-graf (back-token expander token) (new-graf expander t (token-span token)))
      (:head-for-vmode (head-for-vmode expander token meaning))
      (:insert-dollar (insert-dollar-sign expander token))
      (:illegal (report-illegal-case expander token meaning))
      ((nil)
       (cond ((keywordp key)
              (if (eq key :assignment)
                  (prefixed-command expander token meaning)
                  (character-command expander key token meaning)))
             (t
              (let ((operation (primitive-operation (find-primitive key))))
                (if operation
                    (funcall operation expander token meaning)
                    (hand-on expander token meaning (command-disposition key))))))))))

(defun main-control (expander)
  "TeX's main_control (§1030): run EXPANDER's job until \\end or \\dump.
The end of all input before them is TeX's fatal `no legal \\end found'.
Returns how the job ended, :END or :DUMP."
  (loop until (expander-ended expander)
        do (multiple-value-bind (token meaning) (get-x-token expander)
             (unless token
               (tex-fatal-error "*** (job aborted, no legal \\end found)"))
             (dispatch expander token meaning)))
  (expander-ended expander))

;;; Main control's own commands

(define-command "relax" (expander token meaning))

(define-command ("lastpenalty" "lastkern" "lastskip" "inputlineno" "badness")
    (expander token meaning)
  ;; Quantities only, never commands (§1048).
  (report-illegal-case expander token meaning))

(define-command "ignorespaces" (expander token meaning)
  ;; §1045: the next non-blank command is carried out as it is.
  (multiple-value-bind (next next-meaning) (get-x-nonblank expander)
    (when next
      (dispatch expander next next-meaning))))

(define-command ("global" "long" "outer") (expander token meaning)
  (prefixed-command expander token meaning))

(define-command "afterassignment" (expander token meaning)
  (setf (expander-after-token expander) (get-token expander)))

(define-command "aftergroup" (expander token meaning)
  (let ((next (get-token expander)))
    (when next
      (save-for-after expander next))))

(define-command "begingroup" (expander token meaning)
  (new-save-level expander :semi-simple))

(define-command "endgroup" (expander token meaning)
  (if (eq (current-group-code expander) :semi-simple)
      (unsave expander)
      (off-save expander token meaning)))

(define-command "endcsname" (expander token meaning)
  ;; cs_error (§1135)
  (tex-error "Extra" :context (esc expander "endcsname") :span (token-span token)))

(define-command ("indent" "noindent") (expander token meaning)
  ;; §§1090-1093
  (cond ((eq (mode-kind (current-mode expander)) :vertical)
         (new-graf expander (string= name "indent") (token-span token)))
        ((string= name "indent")
         ;; indent_in_hmode (§1093); in math the box is a noad (9d).
         (let ((list (current-list expander)))
           (when (eq (mode-kind (list-state-mode list)) :horizontal)
             (setf (list-state-space-factor list) 1000))
           (append-node expander (make-node :indent :span (token-span token)))))))

(define-command ("eqno" "leqno") (expander token meaning)
  ;; §1140: outside math the mode case reports it; inline math is not
  ;; privileged.  In a display it begins an equation number: an event.
  (when (privileged-p expander token meaning)
    (if (eq (current-group-code expander) :math-shift)
        (hand-on expander token meaning :event)
        (off-save expander token meaning))))

(define-command "par" (expander token meaning)
  ;; §§1070, 1094
  (if (eq (mode-kind (current-mode expander)) :vertical)
      (normal-paragraph expander)
      (progn
        (when (minusp (expander-align-state expander))
          (off-save expander token meaning))
        (end-graf expander (token-span token))))
  (when (eq (current-mode expander) :vertical)
    (build-page expander)))

(define-command ("box" "copy" "lastbox" "vsplit" "vtop" "vbox" "hbox")
    (expander token meaning)
  (begin-box expander token meaning :append))

(define-command ("end" "dump") (expander token meaning)
  ;; its_all_over (§1054): no page builder holds material back, so the
  ;; job ends in (outer) vertical mode.
  (when (privileged-p expander token meaning)
    (final-cleanup expander (string= name "dump"))))

(defun final-cleanup (expander dump)
  "TeX's final_cleanup (§1335): report the groups and conditionals still
open (TEX-REPORTs, not errors), then end the job; \\dump (DUMP) inside a
group is fatal (§1304)."
  (let ((level (group-level (expander-tex expander))))
    (when (plusp level)
      (tex-report (esc expander "end occurred")
                  :context (format nil "inside a group at level ~D" level))))
  (loop for conditional = (pop (expander-conditionals expander))
        while conditional
        do (tex-report (esc expander "end occurred")
                       :context (format nil "when ~A~@[ on line ~D~] was incomplete"
                                       (esc expander (conditional-kind conditional))
                                       (let ((line (conditional-line conditional)))
                                         (and (plusp line) line)))))
  (when dump
    (when (plusp (save-stack-depth (expander-tex expander)))
      (tex-fatal-error "You can't dump inside a group"))
    (setf (expander-trie-not-ready expander) nil))
  (setf (expander-ended expander) (if dump :dump :end)))
