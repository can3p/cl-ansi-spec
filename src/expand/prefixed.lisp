;;;; src/expand/prefixed.lisp
;;;;
;;;; TeX's prefixed_command (TeX: The Program, §§1208-1225, 1269): the
;;;; prefixes \global, \long and \outer with their errors, \globaldefs,
;;;; the dispatch to the assignment itself (assignments.lisp), and the
;;;; token \afterassignment saved, inserted after every assignment.  Here
;;;; too are the assignments of meanings: \def and its relatives, \let
;;;; and \futurelet, and the shorthand definitions.
;;;;
;;;; An assignment is a function of the expander, the command's token
;;;; and meaning, and the prefixes (GLOBAL, LONG, OUTER), registered by
;;;; DEFINE-ASSIGNMENT.  GLOBAL already reflects \globaldefs; the setters
;;;; of state.lisp apply \globaldefs again, which gives the same answer.

(in-package #:cl-ansi-spec/expand)

(defvar *assignments* (make-hash-table :test 'equal)
  "TeX's assignment commands (those above max_non_prefixed_command, §209)
by primitive name: a function of the expander, token, meaning and the
prefixes.  Global data, filled while the system loads by
DEFINE-ASSIGNMENT; never rebound.")

(defmacro define-assignment (names (expander token meaning global &optional
                                    (long (gensym "LONG")) (outer (gensym "OUTER")))
                             &body body)
  "Register BODY as the assignment for the primitive(s) NAMES and make
them main control's commands (through PREFIXED-COMMAND).  Inside BODY,
NAME is bound to the primitive's name."
  `(dolist (name ',(if (listp names) names (list names)))
     (setf (gethash name *assignments*)
           (let ((name name))
             (declare (ignorable name))
             (lambda (,expander ,token ,meaning ,global ,long ,outer)
               (declare (ignorable ,expander ,token ,meaning ,global ,long ,outer))
               ,@body)))
     (define-primitive name :operation #'prefixed-command)))

(defun parameter-keyword (name)
  "The keyword of the TeX82 parameter NAME (\"tolerance\"), or NIL."
  (let ((keyword (find-symbol (string-upcase name) :keyword)))
    (and keyword (parameter-kind keyword) keyword)))

(defun assignment-function (meaning)
  "The assignment MEANING performs, or NIL when it is no assignment: a
primitive registered by DEFINE-ASSIGNMENT, a parameter, a font
identifier (select the font) or a register shorthand."
  (typecase meaning
    (primitive (let ((name (primitive-name meaning)))
                 (or (gethash name *assignments*)
                     (and (parameter-keyword name) #'assign-parameter))))
    (tex-font #'select-font)
    (shorthand (and (not (member (shorthand-kind meaning) '(:char :mathchar)))
                    #'assign-parameter))))

(defun prefix-name (meaning)
  "\"global\", \"long\" or \"outer\" when MEANING is that prefix."
  (and (primitive-p meaning)
       (find (primitive-name meaning) '("global" "long" "outer") :test #'string=)))

(defun definition-p (meaning)
  "True when MEANING is TeX's def command: \\def, \\gdef, \\edef, \\xdef."
  (and (primitive-p meaning)
       (member (primitive-name meaning) '("def" "gdef" "edef" "xdef")
               :test #'string=)
       t))

(defun prefixed-command (expander token meaning)
  "TeX's prefixed_command (§1211): read the prefixes, then carry out the
assignment TOKEN with MEANING begins, then insert the token
\\afterassignment saved."
  (let ((global nil) (long nil) (outer nil)
        (state (expander-state expander)))
    (loop for prefix = (prefix-name meaning)
          while prefix
          do (cond ((string= prefix "global") (setf global t))
                   ((string= prefix "long") (setf long t))
                   (t (setf outer t)))
             (multiple-value-setq (token meaning) (get-x-nonblank-nonrelax expander))
             (unless (and token (or (prefix-name meaning)
                                    (assignment-function meaning)))
               ;; §1212: the token is read again.
               (back-token expander token)
               (tex-error "You can't use a prefix with"
                          :context (format nil "`~A'"
                                           (if token
                                               (meaning-text expander token meaning)
                                               "the end of the input"))
                          :span (and token (token-span token)))
               (return-from prefixed-command)))
    (when (and (or long outer) (not (definition-p meaning)))
      (tex-error (format nil "You can't use `~A' or `~A' with"
                         (esc expander "long") (esc expander "outer"))
                 :context (format nil "`~A'" (meaning-text expander token meaning))
                 :span (token-span token)))
    (funcall (assignment-function meaning) expander token meaning
             (effective-global state global) long outer)
    (let ((after (expander-after-token expander)))
      (when after
        (setf (expander-after-token expander) nil)
        (back-token expander after)))))

;;; Defining control sequences

(defun frozen-protection (expander)
  "TeX's frozen_protection: the control sequence `\\inaccessible ' that
`Missing control sequence inserted' inserts."
  (frozen-control-sequence expander "inaccessible "))

(defun definable-p (expander cs)
  "True when CS can be defined (§1215): an active character or an
interned control sequence, or the frozen `\\inaccessible '; not another
frozen control sequence."
  (or (control-sequence-active-p cs)
      (eq cs (intern-control-sequence (expander-tex expander)
                                      (control-sequence-name cs)))
      (eq cs (frozen-protection expander))))

(defun space-token-p (token)
  "True when TOKEN is TeX's space_token: character 32 of category 10."
  (and (character-catcode-p token +space+) (= (character-token-code token) 32)))

(defun get-r-token (expander)
  "TeX's get_r_token (§1215): the control sequence to be defined, read
without expansion after spaces.  Anything else is `Missing control
sequence inserted': a character is read again after `\\inaccessible '."
  (loop
    (let ((token (loop for token = (get-token expander)
                       unless (space-token-p token) return token)))
      (if (and (cs-token-p token)
               (definable-p expander (cs-token-control-sequence token)))
          (return (cs-token-control-sequence token))
          (let ((span (and token (token-span token))))
            (unless (cs-token-p token)
              (back-token expander token))
            (back-token expander (make-cs-token (frozen-protection expander) span))
            (tex-error "Missing control sequence inserted" :span span))))))

(defun define-control-sequence (expander token cs meaning global)
  "Give CS the MEANING (GLOBAL as for SET-MEANING), as the definition
command TOKEN does, and tell EXPANDER's definition observer."
  (set-meaning (expander-state expander) cs meaning :global global)
  (let ((observer (expander-definition-observer expander)))
    (when observer
      (funcall observer expander cs meaning (token-span token)))))

(define-assignment ("def" "gdef" "edef" "xdef") (expander token meaning global long outer)
  ;; §1218
  (let ((cs (get-r-token expander)))
    (when (and (member name '("gdef" "xdef") :test #'string=)
               (>= (parameter (expander-state expander) :globaldefs) 0))
      (setf global t))
    (multiple-value-bind (parameter-text body)
        (scan-toks expander :macro-def t
                            :xpand (member name '("edef" "xdef") :test #'string=)
                            :warning-index cs)
      (define-control-sequence expander token cs
                               (make-macro parameter-text body :long-p long :outer-p outer)
                               global))))

(defun token-meaning (token meaning)
  "What \\let gives a control sequence for TOKEN with MEANING (§1221): a
character's code and category, or the meaning of a control sequence."
  (if (character-token-p token)
      (make-character-meaning (character-token-code token)
                              (character-token-catcode token))
      meaning))

(define-assignment ("let" "futurelet") (expander token meaning global)
  ;; §1221
  (let ((cs (get-r-token expander)))
    (multiple-value-bind (value value-meaning)
        (if (string= name "let")
            (multiple-value-bind (token meaning)
                (loop (multiple-value-bind (token meaning) (get-token expander)
                        (unless (and token (blank-p token meaning))
                          (return (values token meaning)))))
              (when (other-character-p token #\=)
                (multiple-value-setq (token meaning) (get-token expander))
                (when (and token (blank-p token meaning))
                  (multiple-value-setq (token meaning) (get-token expander))))
              (values token meaning))
            (let ((first (get-token expander)))
              (multiple-value-bind (second second-meaning) (get-token expander)
                (back-token expander second)
                (back-token expander first)
                (values second second-meaning))))
      (define-control-sequence expander token cs
                               (and value (token-meaning value value-meaning))
                               global))))

(define-assignment ("chardef" "mathchardef" "countdef" "dimendef" "skipdef"
                    "muskipdef" "toksdef")
    (expander token meaning global)
  ;; §1224: the name means \relax while its value is read.
  (let ((cs (get-r-token expander))
        (state (expander-state expander))
        (kind (cdr (assoc name '(("chardef" . :char) ("mathchardef" . :mathchar)
                                 ("countdef" . :count) ("dimendef" . :dimen)
                                 ("skipdef" . :skip) ("muskipdef" . :muskip)
                                 ("toksdef" . :toks))
                          :test #'string=))))
    (set-meaning state cs (find-primitive "relax") :global global)
    (scan-optional-equals expander)
    (define-control-sequence expander token cs
                             (make-shorthand kind (case kind
                                                    (:char (scan-char-num expander))
                                                    (:mathchar (scan-fifteen-bit-int expander))
                                                    (t (scan-eight-bit-int expander))))
                             global)))

(defun do-assignments (expander)
  "TeX's do_assignments (§1270): carry out the assignments that follow,
after blanks and \\relax, with \\setbox not allowed (`Improper').
Returns the first other token and its meaning, which are not read again."
  (loop
    (multiple-value-bind (token meaning) (get-x-nonblank-nonrelax expander)
      (unless (and token (or (prefix-name meaning) (assignment-function meaning)))
        (return (values token meaning)))
      (setf (expander-set-box-allowed expander) nil)
      (prefixed-command expander token meaning)
      (setf (expander-set-box-allowed expander) t))))
