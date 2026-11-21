;;;; src/expand/parameters.lisp
;;;;
;;;; TeX82's parameters as data: every integer (§236), dimen (§247), glue
;;;; and mu glue (§224) and token-list (§230) parameter, named by the
;;;; keyword of its control sequence (:TOLERANCE for \tolerance), with
;;;; INITEX's initial values (§§240-241).

(in-package #:cl-ansi-spec/expand)

(defun parameter-table ()
  "Every TeX82 parameter as (kind . names), kind one of :INTEGER, :DIMEN,
:GLUE, :MUGLUE and :TOKENS, names in TeX's order.  A literal, never
modified."
  '((:integer
     :pretolerance :tolerance :linepenalty :hyphenpenalty :exhyphenpenalty
     :clubpenalty :widowpenalty :displaywidowpenalty :brokenpenalty
     :binoppenalty :relpenalty :predisplaypenalty :postdisplaypenalty
     :interlinepenalty :doublehyphendemerits :finalhyphendemerits
     :adjdemerits :mag :delimiterfactor :looseness :time :day :month :year
     :showboxbreadth :showboxdepth :hbadness :vbadness :pausing
     :tracingonline :tracingmacros :tracingstats :tracingparagraphs
     :tracingpages :tracingoutput :tracinglostchars :tracingcommands
     :tracingrestores :uchyph :outputpenalty :maxdeadcycles :hangafter
     :floatingpenalty :globaldefs :fam :escapechar :defaulthyphenchar
     :defaultskewchar :endlinechar :newlinechar :language :lefthyphenmin
     :righthyphenmin :holdinginserts :errorcontextlines)
    (:dimen
     :parindent :mathsurround :lineskiplimit :hsize :vsize :maxdepth
     :splitmaxdepth :boxmaxdepth :hfuzz :vfuzz :delimitershortfall
     :nulldelimiterspace :scriptspace :predisplaysize :displaywidth
     :displayindent :overfullrule :hangindent :hoffset :voffset
     :emergencystretch)
    (:glue
     :lineskip :baselineskip :parskip :abovedisplayskip :belowdisplayskip
     :abovedisplayshortskip :belowdisplayshortskip :leftskip :rightskip
     :topskip :splittopskip :tabskip :spaceskip :xspaceskip :parfillskip)
    (:muglue :thinmuskip :medmuskip :thickmuskip)
    (:tokens
     :output :everypar :everymath :everydisplay :everyhbox :everyvbox
     :everyjob :everycr :errhelp)))

(defun parameter-names (kind)
  "The names of the TeX82 parameters of KIND (see PARAMETER-TABLE)."
  (rest (assoc kind (parameter-table))))

(defun parameter-kind (name)
  "The kind of the parameter NAME (see PARAMETER-TABLE), or NIL if TeX82
has no such parameter."
  (car (find-if (lambda (entry) (member name (rest entry))) (parameter-table))))

(defun initex-integer-parameters ()
  "The integer parameters INITEX sets to nonzero values, as a plist (§240;
\\time, \\day, \\month, \\year as §241 fixes them, noon on 4 July 1776, so
that every job is reproducible)."
  '(:mag 1000 :tolerance 10000 :hangafter 1 :maxdeadcycles 25
    :escapechar 92 :endlinechar 13
    :time 720 :day 4 :month 7 :year 1776))

(defun initex-code (kind code)
  "The INITEX value of the math, space-factor or delimiter code (KIND
:MATHCODE, :SFCODE or :DELCODE) of character CODE (§§232, 240): math
codes are the code itself, variable family (\"7000) for digits and
letters, the latter in family 1; space factors 1000, 999 for upper-case
letters; delimiter codes -1, 0 for the period."
  (flet ((in (low high) (<= (char-code low) code (char-code high))))
    (ecase kind
      (:mathcode (cond ((in #\0 #\9) (+ code #x7000))
                       ((or (in #\A #\Z) (in #\a #\z)) (+ code #x7100))
                       (t code)))
      (:sfcode (if (in #\A #\Z) 999 1000))
      (:delcode (if (= code (char-code #\.)) 0 -1)))))
