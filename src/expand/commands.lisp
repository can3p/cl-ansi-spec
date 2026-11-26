;;;; src/expand/commands.lisp
;;;;
;;;; Who carries out each TeX82 primitive (docs/tex-fidelity.md, "Main
;;;; control"): every primitive has one disposition.  :EXPANDABLE ones run
;;;; inside get_x_token; :MAIN-CONTROL ones are main control's own
;;;; (assignments, groups, modes, input and output); :EVENT ones become
;;;; presentational events and :ALIGNMENT ones alignment commands, in
;;;; later steps.  A command whose operation has not landed is handed on
;;;; as an UNHANDLED-COMMAND, a condition the caller may observe; it is
;;;; never dropped unseen.
;;;;
;;;; Main control's own commands are registered with DEFINE-COMMAND: their
;;;; operation is a function of the expander, the token and its meaning.

(in-package #:cl-ansi-spec/expand)

(defun event-command-names ()
  "The primitives that become presentational events (docs/events.md):
boxes placed in lists, glue, kerns, penalties, rules, characters,
marks, inserts, math and its noads, leaders, \\shipout, \\special,
\\showbox and \\showlists."
  '(" " "/" "-" "above" "abovewithdelims" "accent" "atop" "atopwithdelims"
    "char" "cleaders" "delimiter" "discretionary" "displaylimits"
    "displaystyle" "eqno" "hfil" "hfill" "hfilneg" "hrule" "hskip" "hss"
    "insert" "kern" "lastbox" "leaders" "left" "leqno" "limits" "lower"
    "mark" "mathaccent" "mathbin" "mathchar" "mathchoice" "mathclose"
    "mathinner" "mathop" "mathopen" "mathord" "mathpunct" "mathrel"
    "mkern" "moveleft" "moveright" "mskip" "noboundary" "nolimits"
    "nonscript" "over" "overline" "overwithdelims" "penalty" "radical"
    "raise" "right" "scriptscriptstyle" "scriptstyle" "setlanguage"
    "shipout" "showbox" "showlists" "special" "textstyle" "underline"
    "unhbox" "unhcopy" "unkern" "unpenalty" "unskip" "unvbox" "unvcopy"
    "vadjust" "vcenter" "vfil" "vfill" "vfilneg" "vrule" "vskip" "vss"
    "xleaders"))

(defun alignment-command-names ()
  "The primitives of alignments."
  '("cr" "crcr" "halign" "noalign" "omit" "span" "valign"))

(defun input-output-command-names ()
  "Main control's commands of input, output and messages, which have no
operation yet (step 8b of docs/plan/m2.md)."
  '("closein" "closeout" "errmessage" "immediate" "lowercase" "message"
    "openin" "openout" "read" "show" "showthe" "uppercase" "write"))

(defun command-disposition (name)
  "The disposition of the TeX82 primitive NAME: :EXPANDABLE,
:MAIN-CONTROL, :EVENT or :ALIGNMENT; NIL when NAME is no primitive."
  (let ((primitive (find-primitive name)))
    (cond ((null primitive) nil)
          ((primitive-expandable-p primitive) :expandable)
          ((member name (event-command-names) :test #'string=) :event)
          ((member name (alignment-command-names) :test #'string=) :alignment)
          (t :main-control))))

(define-condition unhandled-command (condition)
  ((token :initarg :token :reader unhandled-command-token
          :documentation "The command's token.")
   (meaning :initarg :meaning :reader unhandled-command-meaning
            :documentation "Its meaning (NIL for a character).")
   (disposition :initarg :disposition :reader unhandled-command-disposition
                :documentation "Who is to carry it out: :EVENT,
:ALIGNMENT or :MAIN-CONTROL (input and output).")
   (mode :initarg :mode :reader unhandled-command-mode
         :documentation "The mode main control was in."))
  (:report (lambda (condition stream)
             (format stream "Unhandled ~(~A~) command ~A in ~(~A~) mode"
                     (unhandled-command-disposition condition)
                     (unhandled-command-token condition)
                     (unhandled-command-mode condition))))
  (:documentation "Signalled for a command main control hands on to a
step that has not landed (an event, an alignment command, input or
output).  If no handler transfers control, the command is skipped: its
operands, if any, are read as what follows."))

(defun hand-on (expander token meaning disposition)
  "Signal UNHANDLED-COMMAND for TOKEN with MEANING, of DISPOSITION."
  (signal 'unhandled-command
          :token token :meaning meaning :disposition disposition
          :mode (list-state-mode (current-list expander))))

(defmacro define-command (names (expander token meaning) &body body)
  "Install BODY as main control's operation for the primitive(s) NAMES (a
string or a list of strings); inside it NAME is bound to the name."
  `(dolist (name ',(if (listp names) names (list names)))
     (define-primitive
      name
      :operation (let ((name name))
                   (declare (ignorable name))
                   (lambda (,expander ,token ,meaning)
                     (declare (ignorable ,expander ,token ,meaning))
                     ,@body)))))
