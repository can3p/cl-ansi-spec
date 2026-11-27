;;;; src/expand/list-commands.lisp
;;;;
;;;; The commands that append simple nodes to the current list (TeX: The
;;;; Program, §§1034-1044, 1056-1061, 1101, 1103-1113): characters (TeX's
;;;; main loop without ligatures or kerns, which need metrics), interword
;;;; spaces, glue, kerns, penalties, rules, the italic correction, the
;;;; commands that remove the last node (\unskip, \unkern, \unpenalty)
;;;; and marks.
;;;; Math characters and math glue are math's (step 9d).

(in-package #:cl-ansi-spec/expand)

(defun font-style-name (font)
  "The :STYLE of text in FONT: its file and size, \"cmr10\", \"cmr10 at
12.0pt\" or \"cmr10 scaled 1200\" (TeX's \\fontname, with scaled sizes
kept), whatever control sequence names the font; made once per font, so
that text nodes of one font share it (EQ)."
  (or (tex-font-style font)
      (setf (tex-font-style font)
            (let ((size (tex-font-size font)))
              (format nil "~A~@[ ~A~]" (tex-font-file font)
                      (case (first size)
                        (:at (concatenate 'string "at " (format-dimen (second size))))
                        (:scaled (format nil "scaled ~D" (second size)))))))))

;;; Characters (§§1034, 1376)

(defun adjust-space-factor (expander code)
  "TeX's adjust_space_factor (§1034) for the character CODE."
  (let ((list (current-list expander))
        (sf (code (expander-state expander) :sfcode code)))
    (setf (list-state-space-factor list)
          (cond ((= sf 1000) 1000)
                ((< sf 1000) (if (plusp sf) sf (list-state-space-factor list)))
                ((< (list-state-space-factor list) 1000) 1000)
                (t sf)))))

(defun fix-language (expander span)
  "TeX's fix_language (§1376): a language whatsit when \\language differs
from the paragraph's language so far."
  (let ((list (current-list expander))
        (language (current-language expander))
        (state (expander-state expander)))
    (unless (= language (list-state-clang list))
      (setf (list-state-clang list) language)
      (append-node expander
                   (make-node :language
                              :properties (list :number language
                                                :left-hyphen-min
                                                (norm-min (parameter state :lefthyphenmin))
                                                :right-hyphen-min
                                                (norm-min (parameter state :righthyphenmin)))
                              :span span)))))

(defun text-continues-p (node style span)
  "True when a character of STYLE read at SPAN extends the :TEXT NODE:
same font, both spans absent or in the same file, in order, and NODE not
replayed from a box (\\unhbox)."
  (and (eq (node-kind node) :text)
       (null (node-via node))
       (eq (getf (node-properties node) :style) style)
       (let ((old (node-span node)))
         (if (and old span)
             (and (equal (span-file old) (span-file span))
                  (<= (span-end old) (span-start span)))
             (and (null old) (null span))))))

(defun append-character (expander code span)
  "TeX's main loop (§1034) for the character CODE read at SPAN, in
horizontal mode: the space factor, the language, then the character,
which extends the text node that ends the list when it can."
  (adjust-space-factor expander code)
  (when (eq (current-mode expander) :horizontal)
    (fix-language expander span))
  (let* ((list (current-list expander))
         (style (font-style-name (current-font (expander-state expander))))
         (last (last-node list))
         (char (code-char code)))
    (if (and last (text-continues-p last style span))
        (progn
          (vector-push-extend char (node-value last))
          (when span
            (let ((old (node-span last)))
              (setf (node-span last)
                    (make-span (span-file old) (span-start old) (span-end span)
                               (span-line old) (span-column old)))))
          (signal 'job-output :item last))
        (append-node expander
                     (make-node :text :properties (list :style style)
                                      :value (make-array 1 :element-type 'character
                                                           :initial-element char
                                                           :adjustable t :fill-pointer 1)
                                      :span span)))))

(define-command "char" (expander token meaning)
  ;; §1038: in math, a math character (step 9d).
  (if (eq (mode-kind (current-mode expander)) :horizontal)
      (append-character expander (scan-char-num expander) (token-span token))
      (hand-on expander token meaning :event)))

(define-command "noboundary" (expander token meaning)
  ;; §1034: it only cancels a boundary ligature, which needs metrics.
  )

;;; Spaces (§§1041-1044)

(defun zero-glue-p (glue)
  "TeX's test against zero_glue, which trap_zero_glue (§1229) makes true
of every glue with zero width, stretch and shrink."
  (and (zerop (glue-width glue)) (zerop (glue-stretch glue))
       (zerop (glue-shrink glue))))

(defun font-glue (font)
  "The interword glue of FONT (§1042): \\fontdimen 2, 3 and 4."
  (make-glue :width (font-dimen font 2) :stretch (font-dimen font 3)
             :shrink (font-dimen font 4)))

(defun space-glue (expander factor)
  "The glue of an interword space at space factor FACTOR (§§1041-1044);
FACTOR NIL is append_normal_space, as for \\ and a space factor of 1000."
  (let* ((state (expander-state expander))
         (font (current-font state))
         (space-skip (parameter state :spaceskip))
         (xspace-skip (parameter state :xspaceskip)))
    (cond ((null factor)
           (if (zero-glue-p space-skip) (font-glue font) space-skip))
          ((and (>= factor 2000) (not (zero-glue-p xspace-skip)))
           xspace-skip)
          (t
           (let ((glue (if (zero-glue-p space-skip) (font-glue font) space-skip)))
             (make-glue :width (if (>= factor 2000)
                                   (+ (glue-width glue) (font-dimen font 7))
                                   (glue-width glue))
                        :stretch (xn-over-d (glue-stretch glue) factor 1000)
                        :shrink (xn-over-d (glue-shrink glue) 1000 factor)
                        :stretch-order (glue-stretch-order glue)
                        :shrink-order (glue-shrink-order glue)))))))

(defun append-space (expander token normal)
  "An interword space read as TOKEN (§1041): at the current space factor,
or a normal space when NORMAL (\\ )."
  (let ((factor (list-state-space-factor (current-list expander))))
    (append-node expander
                 (make-node :space :value (space-glue expander
                                                      (and (not normal) (/= factor 1000)
                                                           factor))
                                   :span (token-span token)))))

(define-command " " (expander token meaning)
  ;; §1045: in horizontal and math mode; vertical mode began a paragraph.
  (append-space expander token t))

;;; Glue, kerns and penalties (§§1057-1061, 1103)

(defun command-glue (expander name)
  "The glue of the glue command NAME (§§1058-1060)."
  (flet ((fil (stretch &optional (shrink 0))
           (make-glue :stretch (* stretch +unity+) :stretch-order (if (zerop stretch) 0 1)
                      :shrink (* shrink +unity+) :shrink-order (if (zerop shrink) 0 1))))
    (cond ((member name '("hfil" "vfil") :test #'string=) (fil 1))
          ((member name '("hfill" "vfill") :test #'string=)
           (make-glue :stretch +unity+ :stretch-order 2))
          ((member name '("hss" "vss") :test #'string=) (fil 1 1))
          ((member name '("hfilneg" "vfilneg") :test #'string=) (fil -1))
          (t (scan-glue expander :glue)))))

(defun glue-node (glue command span)
  "A glue node of GLUE, made by COMMAND (a name) or a parameter, read at
SPAN."
  (make-node :glue :properties (list :glue (format-glue glue) :command command)
                   :value glue :span span))

(define-command ("hskip" "vskip" "hfil" "hfill" "hss" "hfilneg"
                 "vfil" "vfill" "vss" "vfilneg")
    (expander token meaning)
  (append-node expander (glue-node (command-glue expander name) name (token-span token))))

(define-command "kern" (expander token meaning)
  (let ((width (scan-dimen expander)))
    (append-node expander (make-node :kern :properties (list :width (format-dimen width))
                                           :value width :span (token-span token)))))

(define-command "penalty" (expander token meaning)
  (let ((penalty (scan-int expander)))
    (append-node expander (make-node :penalty :properties (list :value penalty)
                                              :value penalty :span (token-span token)))
    (when (eq (current-mode expander) :vertical)
      (build-page expander))))

(define-command "/" (expander token meaning)
  ;; §1112: after a character, a kern of the character's italic
  ;; correction, which is 0 without metrics; in math, always.
  (let ((last (first (list-state-contents (current-list expander)))))
    (when (or (eq (mode-kind (current-mode expander)) :math)
              (and last (eq (node-kind last) :text)))
      (append-node expander (make-node :kern :properties (list :width (format-dimen 0)
                                                               :italic t)
                                             :value 0 :span (token-span token))))))

;;; Rules (§§463, 1056)

(defconstant +default-rule+ 26214
  "TeX's default_rule, 0.4pt in sp (§463).")

(defun scan-rule-spec (expander name)
  "TeX's scan_rule_spec (§463) for \\hrule or \\vrule NAME: the width,
height and depth, each a dimension in sp or :RUNNING."
  (let ((width (if (string= name "vrule") +default-rule+ :running))
        (height (if (string= name "hrule") +default-rule+ :running))
        (depth (if (string= name "hrule") 0 :running)))
    (loop (cond ((scan-keyword expander "width") (setf width (scan-dimen expander)))
                ((scan-keyword expander "height") (setf height (scan-dimen expander)))
                ((scan-keyword expander "depth") (setf depth (scan-dimen expander)))
                (t (return))))
    (values width height depth)))

(defun rule-node (expander name span)
  "The rule node of \\hrule or \\vrule NAME read at SPAN, its spec scanned."
  (multiple-value-bind (width height depth) (scan-rule-spec expander name)
    (flet ((show (d) (if (eq d :running) :running (format-dimen d))))
      (make-node :rule :properties (list :kind (if (string= name "hrule") :hrule :vrule)
                                         :width (show width) :height (show height)
                                         :depth (show depth))
                       :span span))))

(define-command ("hrule" "vrule") (expander token meaning)
  ;; §1056
  (append-node expander (rule-node expander name (token-span token)))
  (let ((list (current-list expander)))
    (case (mode-kind (list-state-mode list))
      (:vertical (setf (list-state-prev-depth list) +ignore-depth+))
      (:horizontal (setf (list-state-space-factor list) 1000)))))

;;; Removing the last node (§§1105-1106)

(define-command ("unskip" "unkern" "unpenalty") (expander token meaning)
  (let* ((list (current-list expander))
         (kind (cond ((string= name "unskip") :glue)
                     ((string= name "unkern") :kern)
                     (t :penalty)))
         (last (list-state-last-node list)))
    (cond ((and (eq (list-state-mode list) :vertical) (null last))
           ;; An empty outer vertical list: the page holds what came
           ;; before (BUILD-PAGE), and TeX cannot take things from it.
           (unless (and (eq kind :glue)
                        (null (page-state-last-glue (expander-page expander))))
             (report-illegal-case expander token meaning)))
          ((and last (eq (car last) kind))
           (remove-last-node list)))))

;;; Marks (§1101)

(define-command "mark" (expander token meaning)
  ;; make_mark: the text is expanded as \edef's body is.
  (let ((tokens (scan-toks expander :xpand t
                                    :warning-index (and (cs-token-p token)
                                                        (cs-token-control-sequence token)))))
    (append-node expander (make-node :tex-mark :properties (list :tokens tokens)
                                               :value tokens :span (token-span token)))))
