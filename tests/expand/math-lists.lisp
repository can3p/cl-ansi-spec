;;;; tests/expand/math-lists.lisp
;;;;
;;;; Math lists (src/expand/math-lists.lisp, modes.lisp; docs/events.md):
;;;; math characters and their noads, fields and scripts, the noad
;;;; commands, fractions, \left/\right, \mathchoice, styles, math glue,
;;;; boxes in math and equation numbers.

(in-package #:cl-ansi-spec/tests)

(define-test math-lists
  :parent events
  :description "The noads of math lists.")

(defun math-events (expander)
  "The events of EXPANDER's job from its first math node to the end of
its last, stripped as STRIP-EVENT does."
  (let* ((events (mapcar (lambda (event) (strip-event expander event))
                         (expand:job-events expander)))
         (start (position-if (lambda (event) (and (eq (first event) :begin)
                                                  (eq (second event) :math)))
                             events))
         (end (position-if (lambda (event) (equal event '(:end :math))) events
                           :from-end t)))
    (and start end (subseq events start (1+ end)))))

(defmacro check-math (text events &key (errors '()))
  "Run TEXT\\end with the math fonts set up and check the events of its
math (MATH-EVENTS) and its ERRORS."
  `(let ((expander (make-test-expander (concatenate 'string (with-math-fonts ,text) "\\end"))))
     (multiple-value-bind (output messages) (run-job expander)
       (declare (ignore output))
       (is equal ',events (math-events expander) "math of ~S" ,text)
       (is equal ',errors messages "errors of ~S" ,text))))

;;; Math characters (§§1151-1155)

(define-test math-characters
  :parent math-lists
  ;; Class and family from \mathcode (INITEX: letters var "7100+c,
  ;; digits var "7000+c, others class 0 fam 0), \fam for a variable
  ;; code when it is 0-15; \mathchar, \mathchardef, \delimiter, \char.
  (check-math "$x1+\\fam1 2\\mathchar\"161\\mathchardef\\m=\"3162 \\m\\delimiter\"4163364 \\char`y$"
              ((:begin :math)
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 1 :code 120)
               (:end :nucleus) (:end :noad)
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 0 :code 49)
               (:end :nucleus) (:end :noad)
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 0 :code 43)
               (:end :nucleus) (:end :noad)
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 1 :code 50)
               (:end :nucleus) (:end :noad)
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 1 :code 97)
               (:end :nucleus) (:end :noad)
               (:begin :noad :class :rel) (:begin :nucleus) (:math-char :fam 1 :code 98)
               (:end :nucleus) (:end :noad)
               (:begin :noad :class :open) (:begin :nucleus) (:math-char :fam 1 :code 99)
               (:end :nucleus) (:end :noad)
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 1 :code 121)
               (:end :nucleus) (:end :noad)
               (:end :math)))
  ;; Math code "8000: the character is read again as active (§1152),
  ;; in a field too.
  (check-math "\\mathcode`a=\"8000 {\\catcode`a=13 \\gdef a{z}}$a^a$"
              ((:begin :math)
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 1 :code 122)
               (:end :nucleus) (:begin :superscript) (:math-char :fam 1 :code 122)
               (:end :superscript) (:end :noad)
               (:end :math))))

;;; Fields, subformulas and scripts (§§1151, 1154, 1176-1187)

(define-test math-scripts
  :parent math-lists
  ;; A one-noad subformula is its nucleus; {} is an empty sub-mlist; a
  ;; second superscript is a new ord noad, after `Double superscript'; a
  ;; script with nothing before it is a new ord noad too.
  (check-math "$x_1^{ab}y^{}^2{z}{}$"
              ((:begin :math)
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 1 :code 120)
               (:end :nucleus)
               (:begin :superscript)
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 1 :code 97)
               (:end :nucleus) (:end :noad)
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 1 :code 98)
               (:end :nucleus) (:end :noad)
               (:end :superscript)
               (:begin :subscript) (:math-char :fam 0 :code 49) (:end :subscript)
               (:end :noad)
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 1 :code 121)
               (:end :nucleus) (:begin :superscript) (:end :superscript) (:end :noad)
               (:begin :noad :class :ord) (:begin :superscript) (:math-char :fam 0 :code 50)
               (:end :superscript) (:end :noad)
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 1 :code 122)
               (:end :nucleus) (:end :noad)
               (:begin :noad :class :ord) (:begin :nucleus) (:end :nucleus) (:end :noad)
               (:end :math))
              :errors ("Double superscript"))
  (check-math "$_1_2$"
              ((:begin :math)
               (:begin :noad :class :ord) (:begin :subscript) (:math-char :fam 0 :code 49)
               (:end :subscript) (:end :noad)
               (:begin :noad :class :ord) (:begin :subscript) (:math-char :fam 0 :code 50)
               (:end :subscript) (:end :noad)
               (:end :math))
              :errors ("Double subscript"))
  ;; Blanks and \relax before a field; anything else begins a
  ;; subformula (here of one box noad, which gives its box).
  (check-math "$x^ \\relax\\hbox{}$"
              ((:begin :math)
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 1 :code 120)
               (:end :nucleus)
               (:begin :superscript)
               (:begin :box :kind :hbox :command "hbox") (:end :box)
               (:end :superscript) (:end :noad)
               (:end :math))
              :errors ("Missing { inserted" "Missing } inserted")))

;;; Noad commands (§§1156-1168)

(define-test noad-commands
  :parent math-lists
  (check-math "$\\mathop x\\limits\\mathbin x\\nolimits\\mathpunct x\\underline x$"
              ((:begin :math)
               (:begin :noad :class :op :limits :limits) (:begin :nucleus)
               (:math-char :fam 1 :code 120) (:end :nucleus) (:end :noad)
               (:begin :noad :class :bin) (:begin :nucleus) (:math-char :fam 1 :code 120)
               (:end :nucleus) (:end :noad)
               (:begin :noad :class :punct) (:begin :nucleus) (:math-char :fam 1 :code 120)
               (:end :nucleus) (:end :noad)
               (:begin :noad :class :underline) (:begin :nucleus)
               (:math-char :fam 1 :code 120) (:end :nucleus) (:end :noad)
               (:end :math))
              :errors ("Limit controls must follow a math operator"))
  (check-math "$\\mathop x\\limits\\nolimits\\mathop y\\limits\\displaylimits$"
              ((:begin :math)
               (:begin :noad :class :op :limits :no-limits) (:begin :nucleus)
               (:math-char :fam 1 :code 120) (:end :nucleus) (:end :noad)
               (:begin :noad :class :op) (:begin :nucleus)
               (:math-char :fam 1 :code 121) (:end :nucleus) (:end :noad)
               (:end :math)))
  ;; \radical's delimiter; \mathaccent's character; an accent noad alone
  ;; in braces replaces the ord noad they make (§1187); \accent in math.
  (check-math "$\\radical\"270370 x{\\mathaccent\"7016 c}\\accent\"16 d$"
              ((:begin :math)
               (:begin :noad :class :radical :delimiter (2 112 3 112)) (:begin :nucleus)
               (:math-char :fam 1 :code 120) (:end :nucleus) (:end :noad)
               (:begin :noad :class :accent :fam 0 :code 22) (:begin :nucleus)
               (:math-char :fam 1 :code 99) (:end :nucleus) (:end :noad)
               (:begin :noad :class :accent :fam 0 :code 22) (:begin :nucleus)
               (:math-char :fam 1 :code 100) (:end :nucleus) (:end :noad)
               (:end :math))
              :errors ("Please use \\mathaccent for accents in math mode"))
  ;; \vcenter is a vbox in the nucleus; boxes and \indent are ord noads.
  (check-math "$\\vcenter to2pt{x}\\raise1pt\\hbox{}\\indent$"
              ((:begin :math)
               (:begin :noad :class :vcenter) (:begin :nucleus)
               (:begin :box :kind :vbox :command "vcenter" :spec (:exactly "2.0pt"))
               (:begin :paragraph) (:indent) (:text "x" :style "nullfont") (:end :paragraph)
               (:end :box) (:end :nucleus) (:end :noad)
               (:begin :noad :class :ord) (:begin :nucleus)
               (:begin :box :kind :hbox :command "hbox" :shift "-1.0pt") (:end :box)
               (:end :nucleus) (:end :noad)
               (:begin :noad :class :ord) (:begin :nucleus) (:indent) (:end :nucleus)
               (:end :noad)
               (:end :math))))

;;; Styles, choices, glue and kerns (§§1057-1061, 1169-1174)

(define-test math-styles-and-spacing
  :parent math-lists
  (check-math "$\\mathchoice{a}{}{}{b}\\scriptstyle\\mskip3mu plus1fill\\mkern-2mu\\nonscript$"
              ((:begin :math)
               (:begin :math-choice)
               (:begin :choice :style :display)
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 1 :code 97)
               (:end :nucleus) (:end :noad)
               (:end :choice)
               (:begin :choice :style :text) (:end :choice)
               (:begin :choice :style :script) (:end :choice)
               (:begin :choice :style :scriptscript)
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 1 :code 98)
               (:end :nucleus) (:end :noad)
               (:end :choice)
               (:end :math-choice)
               (:math-style :style :script)
               (:glue :glue "3.0mu plus 1.0fill" :command "mskip")
               (:kern :width "-2.0mu" :mu t)
               (:glue :glue "0.0pt" :command "nonscript")
               (:end :math))))

;;; Fractions and \left ... \right (§§1178-1191)

(define-test fractions
  :parent math-lists
  (check-math "$a\\over b$"
              ((:begin :math)
               (:begin :fraction :command "over" :thickness :default)
               (:begin :numerator) (:begin :noad :class :ord) (:begin :nucleus)
               (:math-char :fam 1 :code 97) (:end :nucleus) (:end :noad) (:end :numerator)
               (:begin :denominator) (:begin :noad :class :ord) (:begin :nucleus)
               (:math-char :fam 1 :code 98) (:end :nucleus) (:end :noad) (:end :denominator)
               (:end :fraction)
               (:end :math)))
  ;; A second fraction is `Ambiguous', its operands scanned (the first
  ;; takes the whole list as its numerator); \atop is
  ;; thickness 0, \above its dimension; delimiters by \delcode (`.' is
  ;; 0, others -1: `Missing delimiter', read again).
  (check-math "\\delcode`(=\"161300 ${\\atop}{\\above1pt}{\\overwithdelims(.}x\\over\\abovewithdelims..2pt$"
              ((:begin :math)
               (:begin :fraction :command "over" :thickness :default)
               (:begin :numerator)
               (:begin :noad :class :ord) (:begin :nucleus)
               (:begin :fraction :command "atop" :thickness "0.0pt")
               (:begin :numerator) (:end :numerator) (:begin :denominator) (:end :denominator)
               (:end :fraction) (:end :nucleus) (:end :noad)
               (:begin :noad :class :ord) (:begin :nucleus)
               (:begin :fraction :command "above" :thickness "1.0pt")
               (:begin :numerator) (:end :numerator) (:begin :denominator) (:end :denominator)
               (:end :fraction) (:end :nucleus) (:end :noad)
               (:begin :noad :class :ord) (:begin :nucleus)
               (:begin :fraction :command "overwithdelims" :thickness :default
                :left-delimiter (1 97 3 0) :right-delimiter (0 0 0 0))
               (:begin :numerator) (:end :numerator) (:begin :denominator) (:end :denominator)
               (:end :fraction) (:end :nucleus) (:end :noad)
               (:begin :noad :class :ord) (:begin :nucleus)
               (:math-char :fam 1 :code 120) (:end :nucleus) (:end :noad)
               (:end :numerator)
               (:begin :denominator) (:end :denominator)
               (:end :fraction)
               (:end :math))
              :errors ("Ambiguous; you need another { and }"))
  (check-math "$\\overwithdelims x$"
              ((:begin :math)
               (:begin :fraction :command "overwithdelims" :thickness :default
                :left-delimiter (0 0 0 0) :right-delimiter (0 0 0 0))
               (:begin :numerator) (:end :numerator)
               (:begin :denominator) (:begin :noad :class :ord) (:begin :nucleus)
               (:math-char :fam 1 :code 120) (:end :nucleus) (:end :noad) (:end :denominator)
               (:end :fraction)
               (:end :math))
              :errors ("Missing delimiter (. inserted)" "Missing delimiter (. inserted)")))

(define-test left-right
  :parent math-lists
  ;; An inner noad: \left's delimiter, the list (a fraction in it after
  ;; the \left), \right's.
  (check-math "$\\left.a\\over b\\right.x$"
              ((:begin :math)
               (:begin :noad :class :inner) (:begin :nucleus)
               (:left :delimiter (0 0 0 0))
               (:begin :fraction :command "over" :thickness :default)
               (:begin :numerator) (:begin :noad :class :ord) (:begin :nucleus)
               (:math-char :fam 1 :code 97) (:end :nucleus) (:end :noad) (:end :numerator)
               (:begin :denominator) (:begin :noad :class :ord) (:begin :nucleus)
               (:math-char :fam 1 :code 98) (:end :nucleus) (:end :noad) (:end :denominator)
               (:end :fraction)
               (:right :delimiter (0 0 0 0))
               (:end :nucleus) (:end :noad)
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 1 :code 120)
               (:end :nucleus) (:end :noad)
               (:end :math)))
  ;; \right without \left; `$' inside \left (`\right.' inserted).
  (check-math "$\\right.\\left.$"
              ((:begin :math)
               (:begin :noad :class :inner) (:begin :nucleus)
               (:left :delimiter (0 0 0 0)) (:right :delimiter (0 0 0 0))
               (:end :nucleus) (:end :noad)
               (:end :math))
              :errors ("Extra \\right" "Missing \\right. inserted"))
  ;; `}' cannot end a math-left group (extra_right_brace).
  (check-math "$\\left.}\\right.$"
              ((:begin :math)
               (:begin :noad :class :inner) (:begin :nucleus)
               (:left :delimiter (0 0 0 0)) (:right :delimiter (0 0 0 0))
               (:end :nucleus) (:end :noad)
               (:end :math))
              :errors ("Extra }, or forgotten"))
  (check-math "${\\right.}$"
              ((:begin :math)
               (:begin :noad :class :ord) (:begin :nucleus) (:end :nucleus) (:end :noad)
               (:end :math))
              :errors ("Missing } inserted" "Extra \\right" "Extra }, or forgotten")))

;;; Displays and equation numbers (§§1140-1145, 1194-1199)

(define-test equation-numbers
  :parent math-lists
  (check-math "$$x\\eqno1$$"
              ((:begin :math :display t)
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 1 :code 120)
               (:end :nucleus) (:end :noad)
               (:begin :eqno :command "eqno")
               (:begin :noad :class :ord) (:begin :nucleus) (:math-char :fam 0 :code 49)
               (:end :nucleus) (:end :noad)
               (:end :eqno)
               (:end :math)))
  (check-math "$$\\leqno{\\over}$ x"
              ((:begin :math :display t)
               (:begin :eqno :command "leqno")
               (:begin :noad :class :ord) (:begin :nucleus)
               (:begin :fraction :command "over" :thickness :default)
               (:begin :numerator) (:end :numerator) (:begin :denominator) (:end :denominator)
               (:end :fraction) (:end :nucleus) (:end :noad)
               (:end :eqno)
               (:end :math))
              :errors ("Display math should end with $$"))
  ;; In a subformula of a display \eqno is not privileged either.
  (check-math "$${\\eqno}$$"
              ((:begin :math :display t)
               (:begin :noad :class :ord) (:begin :nucleus) (:end :nucleus) (:end :noad)
               (:end :math))
              :errors ("You can't use"))
  ;; In an equation number \eqno is not privileged.
  (check-math "$$\\eqno\\eqno$$"
              ((:begin :math :display t) (:begin :eqno :command "eqno") (:end :eqno)
               (:end :math))
              :errors ("You can't use")))
