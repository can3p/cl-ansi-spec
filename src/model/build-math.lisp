;;;; src/model/build-math.lisp
;;;;
;;;; The handlers that build math lists from their events, and the
;;;; character tables that map a math family's code to Unicode
;;;; (docs/model.md, "Math").
;;;; Owner: step 3.15m of docs/plan/m3.md.

(in-package #:cl-ansi-spec/model)

;;; Families

(defparameter *math-families*
  '((0 "cmr"  :layout :roman      "Roman: digits, parentheses, the operator names (\\log).")
    (1 "cmmi" :table :cmmi        "Math italic: letters, lower-case Greek, old-style digits.")
    (2 "cmsy" :table :cmsy        "Symbols: operators, relations, arrows, calligraphic capitals.")
    (3 "cmex" :table :cmex        "Extension: big operators, delimiters in their sizes, radicals.")
    (4 "cmbx" :layout :roman      "Bold extended, the layout of roman (setup-aux.tex:51, \\fam4).")
    (5 "cmti" :layout :italic     "Text italic (setup-aux.tex:52, \\fam5).")
    (6 "cmtt" :layout :typewriter "Typewriter (setup-aux.tex:53, \\fam6).")
    (7 "cmmi" :table :cmmi        "Math italic again, the family the sources' \\spLT and \\spGT use (setup-aux.tex:939).")
    (8 "cmsy" :table :cmsy        "Symbols again, the family \\spST and \\spMI use (setup-aux.tex:941)."))
  "The math families the jobs set (plain.tex:477-492 as setup-aux.tex:50-59
changes them): (FAMILY FONT KIND NAME WHY).  KIND :LAYOUT has a layout of
*LAYOUT-CODES* (the text fonts, 3.12) for NAME, :TABLE a table of
*MATH-TABLES*.")

(defun math-letters (start first-letter count)
  "Rows for COUNT letters from FIRST-LETTER at code START."
  (loop for i below count
        collect (list (+ start i) (string (code-char (+ (char-code first-letter) i)))
                      "letter, shown italic by the font; the model keeps the plain letter")))

(defparameter *cmmi-codes*
  `((0 "Γ" "capital Greek letter") (1 "Δ" "capital Greek letter")
    (2 "Θ" "capital Greek letter") (3 "Λ" "capital Greek letter")
    (4 "Ξ" "capital Greek letter") (5 "Π" "capital Greek letter")
    (6 "Σ" "capital Greek letter") (7 "Υ" "capital Greek letter")
    (8 "Φ" "capital Greek letter") (9 "Ψ" "capital Greek letter")
    (10 "Ω" "capital Greek letter")
    (11 "α" "\\alpha") (12 "β" "\\beta") (13 "γ" "\\gamma") (14 "δ" "\\delta")
    (15 "ϵ" "\\epsilon, the open form") (16 "ζ" "\\zeta") (17 "η" "\\eta")
    (18 "θ" "\\theta") (19 "ι" "\\iota") (20 "κ" "\\kappa") (21 "λ" "\\lambda")
    (22 "μ" "\\mu") (23 "ν" "\\nu") (24 "ξ" "\\xi") (25 "π" "\\pi") (26 "ρ" "\\rho")
    (27 "σ" "\\sigma") (28 "τ" "\\tau") (29 "υ" "\\upsilon") (30 "ϕ" "\\phi, the stroked form")
    (31 "χ" "\\chi") (32 "ψ" "\\psi") (33 "ω" "\\omega")
    (34 "ε" "\\varepsilon, the curled form") (35 "ϑ" "\\vartheta") (36 "ϖ" "\\varpi")
    (37 "ϱ" "\\varrho") (38 "ς" "\\varsigma") (39 "φ" "\\varphi, the looped form")
    (40 "↼" "\\leftharpoonup") (41 "↽" "\\leftharpoondown")
    (42 "⇀" "\\rightharpoonup") (43 "⇁" "\\rightharpoondown")
    (44 "↩" "\\lhook") (45 "↪" "\\rhook") (46 "▷" "\\triangleright")
    (47 "◁" "\\triangleleft")
    ,@(loop for digit from 0 to 9
            collect (list (+ 48 digit) (string (code-char (+ 48 digit)))
                          "old-style digit of the math italic font; the model keeps the digit"))
    (58 "." "the period of \\ldotp") (59 "," "the comma") (60 "<" "less-than sign")
    (61 "/" "the slash, which plain.tex gives mathcode \"013D") (62 ">" "greater-than sign")
    (63 "⋆" "\\star") (64 "∂" "\\partial")
    ,@(math-letters 65 #\A 26)
    (91 "♭" "\\flat") (92 "♮" "\\natural") (93 "♯" "\\sharp") (94 "⌣" "\\smile")
    (95 "⌢" "\\frown") (96 "ℓ" "\\ell")
    ,@(math-letters 97 #\a 26)
    (123 "ı" "\\imath, dotless i") (124 "ȷ" "\\jmath, dotless j") (125 "℘" "\\wp")
    (126 "⃗" "the vector accent \\vec, a combining mark")
    (127 "⁀" "the tie accent"))
  "The slots of the math italic font (cmmi), every code 0-127: (CODE TEXT
WHY), after TeXbook p. 431 and the names plain.tex gives (\\mathchardef).")

(defparameter *calligraphic*
  '("𝒜" "ℬ" "𝒞" "𝒟" "ℰ" "ℱ" "𝒢" "ℋ" "ℐ" "𝒥" "𝒦" "ℒ" "ℳ" "𝒩" "𝒪" "𝒫" "𝒬"
    "ℛ" "𝒮" "𝒯" "𝒰" "𝒱" "𝒲" "𝒳" "𝒴" "𝒵")
  "The calligraphic capitals A-Z of cmsy, as Unicode script capitals.")

(defparameter *cmsy-codes*
  `((0 "−" "minus sign") (1 "·" "\\cdot") (2 "×" "\\times") (3 "∗" "\\ast")
    (4 "÷" "\\div") (5 "⋄" "\\diamond") (6 "±" "\\pm") (7 "∓" "\\mp")
    (8 "⊕" "\\oplus") (9 "⊖" "\\ominus") (10 "⊗" "\\otimes") (11 "⊘" "\\oslash")
    (12 "⊙" "\\odot") (13 "○" "\\bigcirc") (14 "∘" "\\circ") (15 "•" "\\bullet")
    (16 "≍" "\\asymp") (17 "≡" "\\equiv") (18 "⊆" "\\subseteq") (19 "⊇" "\\supseteq")
    (20 "≤" "\\leq") (21 "≥" "\\geq") (22 "≼" "\\preceq") (23 "≽" "\\succeq")
    (24 "∼" "\\sim") (25 "≈" "\\approx") (26 "⊂" "\\subset") (27 "⊃" "\\supset")
    (28 "≪" "\\ll") (29 "≫" "\\gg") (30 "≺" "\\prec") (31 "≻" "\\succ")
    (32 "←" "\\leftarrow") (33 "→" "\\rightarrow") (34 "↑" "\\uparrow")
    (35 "↓" "\\downarrow") (36 "↔" "\\leftrightarrow") (37 "↗" "\\nearrow")
    (38 "↘" "\\searrow") (39 "≃" "\\simeq") (40 "⇐" "\\Leftarrow")
    (41 "⇒" "\\Rightarrow") (42 "⇑" "\\Uparrow") (43 "⇓" "\\Downarrow")
    (44 "⇔" "\\Leftrightarrow") (45 "↖" "\\nwarrow") (46 "↙" "\\swarrow")
    (47 "∝" "\\propto") (48 "′" "\\prime") (49 "∞" "\\infty") (50 "∈" "\\in")
    (51 "∋" "\\ni") (52 "△" "\\bigtriangleup") (53 "▽" "\\bigtriangledown")
    (54 "̸" "the slash \\not puts through a relation, a combining mark")
    (55 "↦" "\\mapstochar, the bar of \\mapsto")
    (56 "∀" "\\forall") (57 "∃" "\\exists") (58 "¬" "\\neg") (59 "∅" "\\emptyset")
    (60 "ℜ" "\\Re") (61 "ℑ" "\\Im") (62 "⊤" "\\top") (63 "⊥" "\\bot") (64 "ℵ" "\\aleph")
    ,@(loop for letter in *calligraphic* for code from 65
            collect (list code letter "calligraphic capital, a Unicode script capital"))
    (91 "∪" "\\cup") (92 "∩" "\\cap") (93 "⊎" "\\uplus") (94 "∧" "\\wedge")
    (95 "∨" "\\vee") (96 "⊢" "\\vdash") (97 "⊣" "\\dashv") (98 "⌊" "\\lfloor")
    (99 "⌋" "\\rfloor") (100 "⌈" "\\lceil") (101 "⌉" "\\rceil") (102 "{" "\\lbrace")
    (103 "}" "\\rbrace") (104 "⟨" "\\langle") (105 "⟩" "\\rangle") (106 "|" "\\vert")
    (107 "‖" "\\Vert") (108 "↕" "\\updownarrow") (109 "⇕" "\\Updownarrow")
    (110 "\\" "\\backslash") (111 "≀" "\\wr") (112 "√" "\\surd") (113 "∐" "\\amalg")
    (114 "∇" "\\nabla") (115 "∫" "\\smallint") (116 "⊔" "\\sqcup") (117 "⊓" "\\sqcap")
    (118 "⊑" "\\sqsubseteq") (119 "⊒" "\\sqsupseteq") (120 "§" "\\S") (121 "†" "\\dag")
    (122 "‡" "\\ddag") (123 "¶" "\\P") (124 "♣" "\\clubsuit") (125 "♢" "\\diamondsuit")
    (126 "♡" "\\heartsuit") (127 "♠" "\\spadesuit"))
  "The slots of the symbol font (cmsy), every code 0-127: (CODE TEXT WHY),
after TeXbook p. 431 and plain.tex's names.")

(defparameter *cmex-codes*
  '((0 "(" "left parenthesis, first size") (1 ")" "right parenthesis, first size")
    (2 "[" "left bracket, first size") (3 "]" "right bracket, first size")
    (4 "⌊" "left floor, first size") (5 "⌋" "right floor, first size")
    (6 "⌈" "left ceiling, first size") (7 "⌉" "right ceiling, first size")
    (8 "{" "left brace, first size") (9 "}" "right brace, first size")
    (10 "⟨" "left angle, first size") (11 "⟩" "right angle, first size")
    (12 "|" "vertical bar, first size") (13 "‖" "double vertical bar, first size")
    (14 "/" "slash, first size") (15 "\\" "backslash, first size")
    (70 "⨆" "\\bigsqcup, text size") (71 "⨆" "\\bigsqcup, display size")
    (72 "∮" "\\oint, text size") (73 "∮" "\\oint, display size")
    (74 "⨀" "\\bigodot, text size") (75 "⨀" "\\bigodot, display size")
    (76 "⨁" "\\bigoplus, text size") (77 "⨁" "\\bigoplus, display size")
    (78 "⨂" "\\bigotimes, text size") (79 "⨂" "\\bigotimes, display size")
    (80 "∑" "\\sum, text size") (81 "∏" "\\prod, text size") (82 "∫" "\\int, text size")
    (83 "⋃" "\\bigcup, text size") (84 "⋂" "\\bigcap, text size")
    (85 "⨄" "\\biguplus, text size") (86 "⋀" "\\bigwedge, text size")
    (87 "⋁" "\\bigvee, text size")
    (88 "∑" "\\sum, display size") (89 "∏" "\\prod, display size")
    (90 "∫" "\\int, display size") (91 "⋃" "\\bigcup, display size")
    (92 "⋂" "\\bigcap, display size") (93 "⨄" "\\biguplus, display size")
    (94 "⋀" "\\bigwedge, display size") (95 "⋁" "\\bigvee, display size")
    (96 "∐" "\\coprod, text size") (97 "∐" "\\coprod, display size")
    (112 "√" "radical, first size") (113 "√" "radical, second size")
    (114 "√" "radical, third size") (115 "√" "radical, fourth size")
    (116 "√" "radical, fifth size"))
  "The slots of the extension font (cmex) the model knows: (CODE TEXT WHY),
the delimiters of plain.tex's \\delcode table (0-15), the big operators and
the radicals (codes as plain.tex's \\mathchardefs give them, text size, and
the display size 8 codes after).  The sizes between and the extensible pieces (16-69, 98-111,
117-127) show no character of their own: they are not here, and a build
that meets one reports it (MATH-FAMILY-TEXT).")

(defparameter *math-tables*
  `((:cmmi . ,*cmmi-codes*) (:cmsy . ,*cmsy-codes*) (:cmex . ,*cmex-codes*))
  "The tables of the math fonts that have a layout of their own, by name.")

(defun math-table-text (table code)
  "The text of CODE in the math font TABLE (a key of *MATH-TABLES*), or NIL."
  (second (assoc code (cdr (assoc table *math-tables*)))))

(defun math-family-text (family code)
  "The Unicode text of the math character CODE of FAMILY, and true; or
NIL and NIL when the family or the slot has none (a build reports it)."
  (let ((entry (assoc family *math-families*)))
    (if (null entry)
        (values nil nil)
        (let ((text (ecase (third entry)
                      (:layout (let ((vector (cdr (assoc (fourth entry) *layout-vectors*))))
                                 (and (< -1 code 128) (aref vector code))))
                      (:table (math-table-text (fourth entry) code)))))
          (if text (values text t) (values nil nil))))))

(defparameter *unknown-math-char* (string (code-char #xFFFD))
  "The text of a math character the tables have no Unicode for.")

(defun math-family-text-reporting (builder family code span)
  "MATH-FAMILY-TEXT, or *UNKNOWN-MATH-CHAR* with a problem reported at SPAN."
  (multiple-value-bind (text known) (math-family-text family code)
    (cond (known text)
          (t (report-problem builder :diagnostic span
                             :message (format nil "No Unicode text for the math character ~D in family ~D."
                                              code family))
             *unknown-math-char*))))

(defun delimiter-text (builder delimiter span)
  "The Unicode text of DELIMITER, a list (small-family small-code
large-family large-code): the small character, else the large one when
the small slot is empty (zero) or has no text, as TeX tries them; NIL for
the null delimiter (all zero).  A problem is reported when no slot has a
text."
  (destructuring-bind (small-family small-code large-family large-code) delimiter
    (flet ((slot (family code)
             (and (not (and (zerop family) (zerop code)))
                  (multiple-value-bind (text known) (math-family-text family code)
                    (and known text)))))
      (cond ((and (zerop small-family) (zerop small-code)
                  (zerop large-family) (zerop large-code))
             nil)
            ((or (slot small-family small-code) (slot large-family large-code)))
            (t (math-family-text-reporting
                builder
                (if (and (zerop small-family) (zerop small-code)) large-family small-family)
                (if (and (zerop small-family) (zerop small-code)) large-code small-code)
                span))))))

;;; Leaf nodes

(defun add-leaf (builder node span)
  "Give NODE SPAN and add it to BUILDER's current container."
  (setf (node-span node) span)
  (add-item builder node))

(defun math-items (builder items)
  "ITEMS (the items of a math container, which text events may have
filled with strings: a control space) with each string a :MATH-CHAR."
  (mapcar (lambda (item)
            (if (stringp item)
                (make-builder-node builder :math-char :text item)
                item))
          items))

;;; Containers

(defun store-field (field)
  "An ON-CLOSE function: the items of the container become FIELD of the
node of the container below, and are not passed on."
  (lambda (builder container)
    (let* ((node (container-node (current-container builder)))
           (items (math-items builder (container-contents container))))
      (setf (container-items container) '())
      (cond ((null node)
             (report-problem builder :unmatched-end (container-span container)
                             :message (format nil "A ~(~A~) outside a noad or fraction." field)))
            (items
             (setf (node-field-value node field (builder-registry builder)) items))))))

(defun open-field (builder key span field)
  "Open the container of KEY whose items become FIELD of the node of the
container below when it closes."
  (open-container builder key span :on-close (store-field field)))

(defun open-formula (builder event span)
  "(:begin :math): the formula, inline or displayed."
  (let ((node (make-builder-node builder :math
                                         :display (and (event-property event :display) t))))
    (open-container builder :math span :node node
                    :on-close (lambda (builder container)
                                (let ((items (math-items builder (container-contents container))))
                                  (setf (container-items container) '())
                                  (when items
                                    (setf (node-field-value node 'content (builder-registry builder))
                                          items)))))))

(defun open-equation-number (builder event span)
  "(:begin :eqno): the equation number of the formula below."
  (let ((owner (find-container builder :math)))
    (when owner
      (setf (node-field-value (container-node owner) 'number-left (builder-registry builder))
            (equal (event-property event :command) "leqno"))))
  (open-field builder :eqno span 'equation-number))

(defun open-noad (builder event span)
  "(:begin :noad): a noad of the event's class; the sign of a radical, the
accent of an accent noad."
  (let* ((class (event-property event :class))
         (delimiter (event-property event :delimiter))
         (limits (case (event-property event :limits)
                   (:limits :limits) (:no-limits :no-limits)))
         (text (cond ((eq class :radical)
                      (and delimiter (delimiter-text builder delimiter span)))
                     ((eq class :accent)
                      (let ((fam (event-property event :fam))
                            (code (event-property event :code)))
                        (cond ((and fam code)
                               (math-family-text-reporting builder fam code span))
                              (t (report-problem builder :diagnostic span
                                                 :message "An accent noad without its character.")
                                 nil)))))))
    (open-container builder :noad span
                    :node (make-builder-node builder :math-noad :class class :limits limits
                                                                :delimiter text))))

(defun zero-dimension-p (dimension)
  "True when DIMENSION, a string as TeX writes one (\"0.0pt\"), is zero:
every digit before its unit is 0."
  (let ((unit (position-if #'alpha-char-p dimension)))
    (and (every (lambda (char) (member char '(#\0 #\. #\-))) (subseq dimension 0 unit))
         (find #\0 dimension :end unit)
         t)))

(defun open-fraction (builder event span)
  "(:begin :fraction): a fraction, its bar and delimiters as the event gives them."
  (let* ((thickness (event-property event :thickness))
         (left (event-property event :left-delimiter))
         (right (event-property event :right-delimiter))
         (written (and (stringp thickness) thickness)))
    (unless (or (eq thickness :default) written)
      (report-problem builder :diagnostic span
                      :message (format nil "A fraction thickness that is neither :DEFAULT nor a dimension: ~S."
                                       thickness)))
    (open-container
     builder :fraction span
     :node (make-builder-node
            builder :math-fraction
            :no-rule (and written (zero-dimension-p written))
            :thickness (and written (not (zero-dimension-p written)) written)
            :left-delimiter (and left (delimiter-text builder left span))
            :right-delimiter (and right (delimiter-text builder right span))))))

(defun choice-field (style)
  "The field of math-choice that holds the subformula for STYLE."
  (ecase style
    (:display 'display) (:text 'text) (:script 'script) (:scriptscript 'scriptscript)))

;;; Handlers

(defun install-math-handlers (table)
  "Register the handlers of step 3.15m in the handler table TABLE."
  (register-handler :begin :math #'open-formula table)
  (register-handler :begin :eqno #'open-equation-number table)
  (register-handler :begin :noad #'open-noad table)
  (register-handler :begin :fraction #'open-fraction table)
  (loop for (key field) in '((:nucleus nucleus) (:superscript superscript)
                             (:subscript subscript) (:numerator numerator)
                             (:denominator denominator))
        do (let ((key key) (field field))
             (register-handler :begin key
                               (lambda (builder event span)
                                 (declare (ignore event))
                                 (open-field builder key span field))
                               table)))
  (register-handler :begin :math-choice
                    (lambda (builder event span)
                      (declare (ignore event))
                      (open-container builder :math-choice span
                                      :node (make-builder-node builder :math-choice)))
                    table)
  (register-handler :begin :choice
                    (lambda (builder event span)
                      (open-field builder :choice span
                                  (choice-field (event-property event :style))))
                    table)
  (register-handler :math-char nil
                    (lambda (builder event span)
                      (add-leaf builder
                                (make-builder-node
                                 builder :math-char
                                 :text (math-family-text-reporting
                                        builder (event-property event :fam 0)
                                        (event-property event :code 0) span))
                                span))
                    table)
  (dolist (key '(:left :right))
    (let ((key key))
      (register-handler key nil
                        (lambda (builder event span)
                          (let ((delimiter (event-property event :delimiter)))
                            (add-leaf builder
                                      (make-builder-node
                                       builder :math-delimiter :right (eq key :right)
                                       :text (and delimiter
                                                  (delimiter-text builder delimiter span)))
                                      span)))
                        table)))
  (register-handler :math-style nil
                    (lambda (builder event span)
                      (add-leaf builder
                                (make-builder-node builder :math-style-change
                                                   :style (event-property event :style))
                                span))
                    table)
  table)

(install-math-handlers *handlers*)
