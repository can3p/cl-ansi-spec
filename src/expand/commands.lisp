;;;; src/expand/commands.lisp
;;;;
;;;; Who carries out each TeX82 primitive (docs/tex-fidelity.md, "Main
;;;; control"): every primitive has one disposition.  :EXPANDABLE ones run
;;;; inside get_x_token; :MAIN-CONTROL ones are main control's own
;;;; (assignments, groups, modes, input, output, messages and
;;;; alignments); :EVENT ones append the nodes of presentational events.
;;;; Every one of the latter two has an operation.
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

(defun input-output-command-names ()
  "Main control's commands of input, output and messages (messages.lisp,
streams.lisp)."
  '("closein" "closeout" "errmessage" "immediate" "lowercase" "message"
    "openin" "openout" "read" "show" "showthe" "uppercase" "write"))

(defun command-disposition (name)
  "The disposition of the TeX82 primitive NAME: :EXPANDABLE,
:MAIN-CONTROL or :EVENT; NIL when NAME is no primitive."
  (let ((primitive (find-primitive name)))
    (cond ((null primitive) nil)
          ((primitive-expandable-p primitive) :expandable)
          ((member name (event-command-names) :test #'string=) :event)
          (t :main-control))))

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
