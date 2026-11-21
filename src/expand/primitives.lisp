;;;; src/expand/primitives.lisp
;;;;
;;;; The primitive table (docs/architecture.md, "extension points are
;;;; data"): every TeX82 primitive by name, as a PRIMITIVE meaning.  Each
;;;; step registers the operations it implements; a name without one is
;;;; still installed, so that \meaning and \ifx see TeX's primitives from
;;;; the start.  INSTALL-PRIMITIVES gives a job's state these meanings.

(in-package #:cl-ansi-spec/expand)

(defvar *primitives* (make-hash-table :test 'equal)
  "The primitive table: name (a string, \"relax\") to PRIMITIVE.  Global
data, filled while the system loads by DEFINE-PRIMITIVE; never rebound.")

(defun define-primitive (name &key operation expandable-p)
  "Register the primitive NAME with its OPERATION (see PRIMITIVE),
replacing any earlier entry.  Returns the primitive."
  (setf (gethash name *primitives*)
        (make-primitive name :operation operation :expandable-p expandable-p)))

(defun find-primitive (name)
  "The primitive called NAME, or NIL."
  (values (gethash name *primitives*)))

(defun tex82-command-names ()
  "The names of TeX82's primitive commands that are not expandable, besides
its parameters (PARAMETER-NAMES), which are primitives too.  \" \" is the
control space, \"/\" the italic correction, \"-\" the discretionary
hyphen."
  '(" " "/" "-" "above" "abovewithdelims" "accent" "advance"
    "afterassignment" "aftergroup" "atop" "atopwithdelims" "badness"
    "batchmode" "begingroup" "box" "char" "chardef" "cleaders" "closein"
    "closeout" "copy" "count" "countdef" "cr" "crcr" "deadcycles" "def"
    "delcode" "delimiter" "dimen" "dimendef" "discretionary"
    "displaylimits" "displaystyle" "divide" "dp" "dump" "edef" "end"
    "endcsname" "endgroup" "eqno" "errmessage" "errorstopmode" "font"
    "fontdimen" "futurelet" "gdef" "global" "halign" "hbox" "hfil" "hfill"
    "hfilneg" "hrule" "hskip" "hss" "ht" "hyphenation" "hyphenchar"
    "ignorespaces" "immediate" "indent" "inputlineno" "insert"
    "insertpenalties" "kern" "lastbox" "lastkern" "lastpenalty" "lastskip"
    "lccode" "leaders" "left" "leqno" "let" "limits" "long" "lower"
    "lowercase" "mark" "mathaccent" "mathbin" "mathchar" "mathchardef"
    "mathchoice" "mathclose" "mathcode" "mathinner" "mathop" "mathopen"
    "mathord" "mathpunct" "mathrel" "message" "mkern" "moveleft"
    "moveright" "mskip" "multiply" "muskip" "muskipdef" "noalign"
    "noboundary" "noindent" "nolimits" "nonscript" "nonstopmode" "omit"
    "openin" "openout" "outer" "over" "overline" "overwithdelims"
    "pagedepth" "pagefilllstretch" "pagefillstretch" "pagefilstretch"
    "pagegoal" "pageshrink" "pagestretch" "pagetotal" "par" "parshape"
    "patterns" "penalty" "prevdepth" "prevgraf" "radical" "raise" "read"
    "relax" "right" "scriptfont" "scriptscriptfont" "scriptscriptstyle"
    "scriptstyle" "scrollmode" "setbox" "setlanguage" "sfcode" "shipout"
    "show" "showbox" "showlists" "showthe" "skewchar" "skip" "skipdef"
    "spacefactor" "span" "special" "textfont" "textstyle" "toks" "toksdef"
    "uccode" "underline" "unhbox" "unhcopy" "unkern" "unpenalty" "unskip"
    "unvbox" "unvcopy" "uppercase" "vadjust" "valign" "vbox" "vcenter"
    "vfil" "vfill" "vfilneg" "vrule" "vskip" "vsplit" "vss" "vtop" "wd"
    "write" "xdef" "xleaders"))

(defun tex82-expandable-names ()
  "The names of TeX82's expandable primitives (§366)."
  '("expandafter" "noexpand" "csname" "input" "endinput" "topmark"
    "firstmark" "botmark" "splitfirstmark" "splitbotmark" "the" "number"
    "romannumeral" "string" "meaning" "fontname" "jobname" "if" "ifcat"
    "ifnum" "ifdim" "ifodd" "ifvmode" "ifhmode" "ifmmode" "ifinner"
    "ifvoid" "ifhbox" "ifvbox" "ifx" "ifeof" "iftrue" "iffalse" "ifcase"
    "fi" "or" "else"))

(defun not-implemented-operation (expander token)
  "The operation of an expandable primitive whose step has not landed: a
TeX error whose recovery drops the token."
  (declare (ignore expander))
  (tex-error "Primitive not implemented yet"
             :context (control-sequence-name (cs-token-control-sequence token))
             :span (token-span token)))

;;; Every TeX82 name is in the table from the start.
(dolist (name (tex82-command-names))
  (unless (find-primitive name)
    (define-primitive name)))
(dolist (name (loop for kind in '(:integer :dimen :glue :muglue :tokens)
                     append (parameter-names kind)))
  (let ((name (string-downcase (symbol-name name))))
    (unless (find-primitive name)
      (define-primitive name))))
(dolist (name (tex82-expandable-names))
  (unless (find-primitive name)
    (define-primitive name :operation #'not-implemented-operation
                           :expandable-p t)))

(defun install-primitives (state)
  "Give every primitive of the table its name's meaning in STATE, and
\\nullfont the null font, globally (INITEX's primitive calls, §226)."
  (maphash (lambda (name primitive)
             (set-meaning state (intern-control-sequence (es-tex state) name)
                          primitive :global t))
           *primitives*)
  (set-meaning state (intern-control-sequence (es-tex state) "nullfont")
               (es-null-font state) :global t)
  state)
