;;;; src/model/build-text.lisp
;;;;
;;;; Text and fonts: :text and :space to strings (ligatures and character
;;;; codes per font, discretionaries, accents), font runs outside entries
;;;; to inlines (docs/model.md, "Text").
;;;; Owner: step 3.12 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/model)

;;; The fonts the jobs load, by file (the style of a :text event is the
;;; file, then " scaled N" or " at Xpt").  Its layout says what each
;;; character code shows; its class what a run in it means outside entries.

(defparameter *fonts*
  '(("cmtt"  :typewriter :code     "Computer Modern typewriter: the code font.")
    ("cmti"  :italic     :emphasis "Computer Modern text italic.")
    ("cmssi" :roman      :emphasis "Sans-serif italic, set by \\arg and \\argument.")
    ("cmsl"  :roman      :emphasis "Slanted roman.")
    ("cmbx"  :roman      :strong   "Bold extended, also bold slanted (cmbxsl): the bold font.")
    ("cmss"  :roman      nil       "Sans-serif: no meaning of its own.")
    ("cmr"   :roman      nil       "Roman, also at 7 point: plain text."))
  "The font families of the jobs, first match of a file's prefix wins:
(PREFIX LAYOUT CLASS WHY).  LAYOUT names a table of *LAYOUT-CODES*
(its :roman, :italic and :typewriter are Knuth's OT1 text layouts); CLASS
is the inline a run in the font becomes outside vocabulary entries
(:code, :emphasis, :strong), or NIL for plain text.  The size of a font
is not looked at: a heading in cmbx10 scaled 1728 has the class of cmbx10.")

(defparameter *ot1-codes*
  '((0 "Γ" "capital Greek letter") (1 "Δ" "capital Greek letter")
    (2 "Θ" "capital Greek letter") (3 "Λ" "capital Greek letter")
    (4 "Ξ" "capital Greek letter") (5 "Π" "capital Greek letter")
    (6 "Σ" "capital Greek letter") (7 "Υ" "capital Greek letter")
    (8 "Φ" "capital Greek letter") (9 "Ψ" "capital Greek letter")
    (10 "Ω" "capital Greek letter")
    (11 "ff" "ligature glyph: the text is its letters")
    (12 "fi" "ligature glyph: the text is its letters")
    (13 "fl" "ligature glyph: the text is its letters")
    (14 "ffi" "ligature glyph: the text is its letters")
    (15 "ffl" "ligature glyph: the text is its letters")
    (16 "ı" "dotless i") (17 "ȷ" "dotless j")
    (18 "`" "grave accent, spacing form") (19 "´" "acute accent, spacing form")
    (20 "ˇ" "caron, spacing form") (21 "˘" "breve, spacing form")
    (22 "¯" "macron, spacing form") (23 "˚" "ring above, spacing form")
    (24 "¸" "cedilla, spacing form")
    (25 "ß" "German sharp s") (26 "æ" "ae ligature letter")
    (27 "œ" "oe ligature letter") (28 "ø" "slashed o")
    (29 "Æ" "capital AE") (30 "Œ" "capital OE") (31 "Ø" "capital slashed O")
    (34 "”" "the ligature '' makes it; the slot shows a closing double quote")
    (39 "’" "apostrophe and closing single quote")
    (60 "¡" "inverted exclamation mark; the ligature !` makes it")
    (62 "¿" "inverted question mark; the ligature ?` makes it")
    (92 "“" "opening double quote; the ligature `` makes it")
    (94 "ˆ" "circumflex, spacing form") (95 "˙" "dot above, spacing form")
    (96 "‘" "opening single quote")
    (123 "–" "en dash; the ligature -- makes it")
    (124 "—" "em dash; the ligature --- makes it")
    (125 "˝" "double acute, spacing form") (126 "˜" "tilde, spacing form")
    (127 "¨" "diaeresis, spacing form"))
  "Slots of the OT1 text layout (cmr, cmbx, cmsl, cmss and their
relatives) that do not show the ASCII character of their code:
(CODE TEXT WHY).  Every other printable ASCII code shows its character.")

(defparameter *layout-codes*
  `((:roman . ,*ot1-codes*)
    (:italic . ((36 "£" "the italic text font has the pound sign where the roman has the dollar")
                ,@(remove 36 *ot1-codes* :key #'first)))
    (:typewriter
     . ((0 "Γ" "capital Greek letter") (1 "Δ" "capital Greek letter")
        (2 "Θ" "capital Greek letter") (3 "Λ" "capital Greek letter")
        (4 "Ξ" "capital Greek letter") (5 "Π" "capital Greek letter")
        (6 "Σ" "capital Greek letter") (7 "Υ" "capital Greek letter")
        (8 "Φ" "capital Greek letter") (9 "Ψ" "capital Greek letter")
        (10 "Ω" "capital Greek letter")
        (11 "↑" "up arrow") (12 "↓" "down arrow") (13 "'" "straight apostrophe")
        (14 "¡" "inverted exclamation mark") (15 "¿" "inverted question mark")
        (16 "ı" "dotless i") (17 "ȷ" "dotless j")
        (18 "`" "grave accent, spacing form") (19 "´" "acute accent, spacing form")
        (20 "ˇ" "caron, spacing form") (21 "˘" "breve, spacing form")
        (22 "¯" "macron, spacing form") (23 "˚" "ring above, spacing form")
        (24 "¸" "cedilla, spacing form")
        (25 "ß" "German sharp s") (26 "æ" "ae ligature letter")
        (27 "œ" "oe ligature letter") (28 "ø" "slashed o")
        (29 "Æ" "capital AE") (30 "Œ" "capital OE") (31 "Ø" "capital slashed O")
        (32 "␣" "the typewriter font shows its space")
        (127 "¨" "diaeresis, spacing form"))))
  "The slots of each layout of *FONTS* that do not show the ASCII
character of their code: (CODE TEXT WHY).  The typewriter layout is
ASCII otherwise: `\\', `^', `_', `{', `|', `}', `~', `<' and `>' are
there, which the roman layouts have no slots for.")

(defparameter *ligatures*
  '(("---" "—") ("--" "–") ("``" "“") ("''" "”") ("!`" "¡") ("?`" "¿"))
  "The ligatures of the OT1 text layouts (:roman and :italic), each the
characters typed and the text they make, longest first.  The f ligatures
change no text and are not applied; the typewriter font has none.")

(defparameter *accent-marks*
  '(("`" . #x300) ("´" . #x301) ("ˇ" . #x30C) ("˘" . #x306) ("¯" . #x304)
    ("˚" . #x30A) ("¸" . #x327) ("ˆ" . #x302) ("˙" . #x307) ("˝" . #x30B)
    ("˜" . #x303) ("¨" . #x308) ("^" . #x302) ("~" . #x303))
  "The spacing accents a layout shows (the text of a slot) and the
combining mark of each, for \\accent.")

(defun layout-vector (layout)
  "The 128 texts of the slots of LAYOUT, a key of *LAYOUT-CODES*."
  (let ((vector (make-array 128)))
    (dotimes (code 128)
      (setf (aref vector code) (string (code-char code))))
    (loop for (code text) in (cdr (assoc layout *layout-codes*))
          do (setf (aref vector code) text))
    vector))

(defparameter *layout-vectors*
  (loop for (layout) in *layout-codes* collect (cons layout (layout-vector layout)))
  "The slot texts of each layout, built from *LAYOUT-CODES*.")

(defun font-file (style)
  "The font file of STYLE, a :text event's :STYLE (\"cmr10 scaled 1200\"
is \"cmr10\"); NIL for NIL."
  (and style (subseq style 0 (position #\Space style))))

(defun font-entry (file)
  "The row of *FONTS* of the font FILE, or NIL."
  (and file (find-if (lambda (row) (eql 0 (search (first row) file))) *fonts*)))

(defun font-class (file)
  "What a run in the font FILE becomes outside entries: :CODE,
:EMPHASIS, :STRONG, or NIL for plain text (also for an unknown font)."
  (third (font-entry file)))

(defun convert-text (file raw)
  "The text a run RAW of characters typed in the font FILE shows: the
ligatures of the layout, then each code by the layout's slot.  A
character without a slot (code 128 up) stays.  Second value: true when
FILE is a font of *FONTS*."
  (let* ((entry (font-entry file))
         (layout (second entry))
         (vector (cdr (assoc layout *layout-vectors*)))
         (ligatures (and (member layout '(:roman :italic)) *ligatures*)))
    (if (null entry)
        (values raw nil)
        (values
         (with-output-to-string (out)
           (let ((i 0) (n (length raw)))
             (loop while (< i n)
                   do (let ((ligature (find-if (lambda (rule)
                                                 (let ((end (+ i (length (first rule)))))
                                                   (and (<= end n)
                                                        (string= (first rule) raw
                                                                 :start2 i :end2 end))))
                                               ligatures)))
                        (cond (ligature
                               (write-string (second ligature) out)
                               (incf i (length (first ligature))))
                              (t (let ((code (char-code (char raw i))))
                                   (if (< code 128)
                                       (write-string (aref vector code) out)
                                       (write-char (char raw i) out)))
                                 (incf i)))))))
         t))))

;;; Pieces and segments

(defstruct (piece (:constructor make-piece (kind text span &key file)))
  "A bit of text of a segment: KIND :TEXT (TEXT typed in the font FILE),
:SPACE, or :FINAL (TEXT already shown, in FILE: an accented character)."
  kind text span file)

(defstruct segment
  "The pieces of text since the last item another handler added to a
container (newest first), the container's items below them (ANCHOR) and
the items this segment last set (ITEMS), to tell that nothing was added
since."
  (pieces '()) anchor items)

(defvar *segments* (make-hash-table :test 'eq #+sbcl :weakness #+sbcl :key #+sbcl :synchronized #+sbcl t)
  "The SEGMENT of each container.")

(defvar *reported-fonts* (make-hash-table :test 'eq #+sbcl :weakness #+sbcl :key #+sbcl :synchronized #+sbcl t)
  "The fonts without an entry in *FONTS* each builder has reported.")

(defvar *plain-text-containers* nil
  "The keys of the containers whose text is not read by font, since the
container gives it its meaning (vocabulary entries, headings, code):
the vocabulary of the steps for structure, entries, tables, inlines,
glossary and syntax, and :CODE.  A function of the ownership table,
computed on first use; steps owning another such container push its
key.")

(defun plain-text-container-p (key)
  "True when text directly in a container opened by KEY is not read by
font (*PLAIN-TEXT-CONTAINERS*)."
  (unless *plain-text-containers*
    (setf *plain-text-containers*
          (cons :code
                (loop for owner in (owners)
                      when (member (owner-step owner)
                                   '("3.8" "3.9" "3.11" "3.13" "3.14" "3.15" "3.15m")
                                   :test #'string=)
                        append (owner-vocabulary owner)))))
  (member key *plain-text-containers*))

(defun segment-items-of (builder pieces)
  "The items (strings and :CODE, :EMPHASIS, :STRONG nodes) PIECES, in
order, make in BUILDER's current container: texts of one font file
joined and converted, a space inside a run when the pieces on both
sides are of one class, a run of a class other than NIL a node, unless
the container's text is not read by font."
  (let* ((meaningful (not (plain-text-container-p
                           (container-key (current-container builder)))))
         (units '()))
    ;; Units: (class text span).
    (let ((tail pieces))
      (loop while tail
            do (let ((piece (pop tail)))
                 (ecase (piece-kind piece)
                   (:space (push (list :space " " (piece-span piece)) units))
                   (:final (push (list (and meaningful (font-class (piece-file piece)))
                                       (piece-text piece) (piece-span piece))
                                 units))
                   (:text
                    (let ((file (piece-file piece))
                          (raw (list (piece-text piece)))
                          (span (piece-span piece)))
                      (loop while (and tail (eq (piece-kind (first tail)) :text)
                                       (equal (piece-file (first tail)) file))
                            do (let ((next (pop tail)))
                                 (setf raw (append raw (list (piece-text next)))
                                       span (join-spans span (piece-span next)))))
                      (multiple-value-bind (text known) (convert-text file (apply #'concatenate 'string raw))
                        (unless known
                          (report-unknown-font builder file span))
                        (push (list (and meaningful (font-class file)) text span) units))))))))
    (setf units (nreverse units))
    ;; A space belongs to a run when its nearest neighbours share a class.
    (let ((before :none))
      (loop for cell on units
            for unit = (car cell)
            do (if (eq (first unit) :space)
                   (let ((after (find-if-not (lambda (next) (eq (first next) :space))
                                             (cdr cell))))
                     (setf (first unit)
                           (and (not (eq before :none)) after
                                (eq before (first after))
                                before)))
                   (setf before (first unit)))))
    ;; Group by class.
    (let ((items '()))
      (loop while units
            do (let* ((class (first (first units)))
                      (group (loop while (and units (eq (first (first units)) class))
                                   collect (pop units)))
                      (text (apply #'concatenate 'string (mapcar #'second group))))
                 (push (if class
                           (make-builder-node builder class
                                              :content (list text)
                                              :span (join-spans (third (first group))
                                                                (third (car (last group)))))
                           text)
                       items)))
      (nreverse items))))

(defun report-unknown-font (builder file span)
  "Report once per builder that the font FILE has no entry in *FONTS*."
  (unless (member file (gethash builder *reported-fonts*) :test #'equal)
    (push file (gethash builder *reported-fonts*))
    (report-problem builder :diagnostic span
                    :message (format nil "No layout for font ~A: its characters are kept as typed."
                                     (or file "(none)")))))

(defun add-piece (builder piece)
  "Add PIECE to the text segment of BUILDER's current container,
converting the whole segment again; a segment is closed when another
item was added to the container since."
  (let* ((container (current-container builder))
         (segment (gethash container *segments*)))
    (unless (and segment (eq (container-items container) (segment-items segment)))
      (setf segment (make-segment :anchor (container-items container))
            (gethash container *segments*) segment))
    (push piece (segment-pieces segment))
    (setf (container-items container)
          (append (reverse (segment-items-of builder (reverse (segment-pieces segment))))
                  (segment-anchor segment))
          (segment-items segment) (container-items container))))

;;; Accents

(defun compose-accent (accent base)
  "ACCENT (a spacing accent's text) over BASE (a string, or NIL for none),
in the precomposed form where Unicode has one, else the base and the
combining mark."
  (let ((mark (cdr (assoc accent *accent-marks* :test #'string=))))
    (cond ((null base) accent)
          ((null mark) (concatenate 'string base accent))
          (t (sb-unicode:normalize-string
              (concatenate 'string base (string (code-char mark))) :nfc)))))

(defun finish-accent (builder container)
  "The end of an \\accent: its two texts, the accent's in the font before
and the character's in the font after, become one :FINAL piece in the
font of the character."
  (let* ((parts (reverse (remove-if-not #'piece-p (container-items container))))
         (accent (first parts))
         (base (second parts)))
    (setf (container-items container) '())
    (when accent
      (let ((shown (lambda (part) (and part (convert-text (piece-file part) (piece-text part))))))
        (add-piece builder
                   (make-piece :final
                               (compose-accent (funcall shown accent) (funcall shown base))
                               (container-span container)
                               :file (piece-file (or base accent))))))))

;;; Handlers

(defun text-handler (builder event span)
  "A :TEXT event: a piece of the current text segment; inside an
\\accent, its raw part."
  (let ((piece (make-piece :text (event-text event) span
                           :file (font-file (event-property event :style)))))
    (if (eq (container-key (current-container builder)) :accent)
        (push piece (container-items (current-container builder)))
        (add-piece builder piece))))

(defun space-handler (builder event span)
  "A :SPACE event: a space piece of the current text segment."
  (declare (ignore event))
  (add-piece builder (make-piece :space " " span)))

(defun install-text-handlers (table)
  "Register the handlers of step 3.12 in the handler table TABLE."
  (register-handler :text nil #'text-handler table)
  (register-handler :space nil #'space-handler table)
  (register-handler :begin :accent
                    (lambda (builder event span)
                      (declare (ignore event))
                      (open-container builder :accent span :on-close #'finish-accent))
                    table)
  (register-handler :begin :discretionary
                    (lambda (builder event span)
                      (declare (ignore event))
                      (open-container builder :discretionary span))
                    table)
  (register-handler :begin :no-break
                    (lambda (builder event span)
                      (declare (ignore event))
                      (open-container builder :no-break span))
                    table)
  (dolist (key '(:pre-break :post-break))
    (let ((key key))
      (register-handler :begin key
                        (lambda (builder event span)
                          (declare (ignore event))
                          (open-container builder key span
                                          :on-close (lambda (builder container)
                                                      (declare (ignore builder))
                                                      (setf (container-items container) '()))))
                        table)))
  table)

(install-text-handlers *handlers*)
