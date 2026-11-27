;;;; src/expand/modes.lisp
;;;;
;;;; Main control's modes (TeX: The Program, §§211-219, 1043-1051,
;;;; 1090-1096, 1136-1200): pushing and popping the semantic nest,
;;;; starting and ending paragraphs (with \everypar and normal_paragraph),
;;;; entering and leaving math (with \everymath and \everydisplay), and
;;;; TeX's errors for commands used in the wrong mode.
;;;;
;;;; No line breaking (docs/tex-fidelity.md, "Not emulated"): a paragraph
;;;; becomes one paragraph node of the enclosing vertical list, and it
;;;; counts as one line for \prevgraf.

(in-package #:cl-ansi-spec/expand)

(defun mode-text (mode)
  "TeX's print_mode (§211): \"vertical mode\", \"internal vertical mode\",
... \"no mode\"."
  (concatenate 'string
               (ecase mode
                 (:vertical "vertical")
                 (:internal-vertical "internal vertical")
                 (:horizontal "horizontal")
                 (:restricted-horizontal "restricted horizontal")
                 (:math "math")
                 (:display-math "display math")
                 (:none "no"))
               " mode"))

(defun outer-mode-p (mode)
  "True when MODE is positive in TeX's sense: vertical, horizontal or
display math, not an inner mode or :NONE."
  (member mode '(:vertical :horizontal :display-math)))

(defun current-mode (expander)
  "The mode of the innermost list of EXPANDER's nest."
  (list-state-mode (current-list expander)))

;;; The nest (§§216-217)

(defun push-nest (expander mode &optional span)
  "TeX's push_nest, then the new MODE: a new innermost list, empty, begun
at SPAN, with \\prevgraf 0 and the other fields of the enclosing list
until set."
  (let ((outer (current-list expander)))
    (push (make-list-state :mode mode
                           :prev-depth (list-state-prev-depth outer)
                           :space-factor (list-state-space-factor outer)
                           :clang (list-state-clang outer)
                           :span span
                           :line (current-line-number (expander-input expander)))
          (expander-nest expander))))

(defun pop-nest (expander)
  "TeX's pop_nest: drop the innermost list."
  (pop (expander-nest expander)))

(defun begin-token-list (expander tokens kind)
  "TeX's begin_token_list for one of the \\every... parameters: TOKENS
are read next, as a level of KIND."
  (when tokens
    (push-tokens (expander-input expander) tokens kind)))

;;; Errors of mode (§§1043-1051)

(defun report-illegal-case (expander token meaning)
  "TeX's report_illegal_case: `You can't use x in y mode'."
  (tex-error "You can't use"
             :context (format nil "`~A' in ~A" (meaning-text expander token meaning)
                              (mode-text (current-mode expander)))
             :span (and token (token-span token))))

(defun privileged-p (expander token meaning)
  "TeX's privileged (§1051): true in an outer mode, else
REPORT-ILLEGAL-CASE and false."
  (or (outer-mode-p (current-mode expander))
      (progn (report-illegal-case expander token meaning) nil)))

(defun insert-dollar-sign (expander token)
  "TeX's insert_dollar_sign (§1047): a math-only command outside math, or
a command that ends math: `$' is inserted before TOKEN."
  (back-token expander token)
  (back-token expander (make-character-token (char-code #\$) +math-shift+
                                             (token-span token)))
  (tex-error "Missing $ inserted" :span (token-span token)))

;;; Paragraphs (§§1070, 1091-1096)

(defun norm-min (h)
  "TeX's norm_min: a hyphenation minimum clamped to 1..63."
  (max 1 (min 63 h)))

(defun current-language (expander)
  "TeX's set_cur_lang: \\language, or 0 when out of range."
  (let ((language (parameter (expander-state expander) :language)))
    (if (<= 1 language 255) language 0)))

(defun horizontal-prev-graf (expander)
  "The prev_graf TeX keeps in a new paragraph: the hyphenation minimums
and the language (§1091)."
  (let ((state (expander-state expander)))
    (+ (* (+ (* (norm-min (parameter state :lefthyphenmin)) 64)
             (norm-min (parameter state :righthyphenmin)))
          65536)
       (current-language expander))))

(defun new-graf (expander indented &optional span)
  "TeX's new_graf (§1091): begin a paragraph at SPAN, indented or not, and
insert \\everypar.  The \\parskip glue goes before it, and the indentation
is its first node."
  (let ((outer (current-list expander)))
    (setf (list-state-prev-graf outer) 0)
    (when (or (eq (list-state-mode outer) :vertical)
              (list-state-contents outer))
      (append-node expander (glue-node (parameter (expander-state expander) :parskip)
                                       "parskip" span))))
  (push-nest expander :horizontal span)
  (let ((list (current-list expander)))
    (setf (list-state-space-factor list) 1000
          (list-state-clang list) (current-language expander)
          (list-state-prev-graf list) (horizontal-prev-graf expander))
    (when indented
      (append-node expander (make-node :indent :span span))))
  (begin-token-list expander (parameter (expander-state expander) :everypar)
                    :every-par))

(defun normal-paragraph (expander)
  "TeX's normal_paragraph (§1070): \\looseness 0, \\hangindent 0pt,
\\hangafter 1 and an empty \\parshape, locally, as TeX assigns them."
  (let ((state (expander-state expander)))
    (flet ((reset (name value)
             (unless (eql (parameter state name) value)
               (set-parameter state name value :globaldefs nil))))
      (reset :looseness 0)
      (reset :hangindent 0)
      (reset :hangafter 1))
    (when (par-shape state)
      (set-par-shape state '() :globaldefs nil))))

(defun break-paragraph (expander &optional end-span)
  "What line_break leaves of the paragraph that is the innermost list,
ended at END-SPAN: it is popped, its final glue removed (§816), and it
becomes one paragraph node of the enclosing vertical list, which counts
one more line, of unknown depth (no line breaking, §§815, 890)."
  (let ((paragraph (pop-nest expander)))
    (when (eq (car (list-state-last-node paragraph)) :glue)
      (remove-last-node paragraph))
    (append-node expander (make-node :paragraph :children (list-nodes paragraph)
                                                :span (list-state-span paragraph)
                                                :end-span end-span)))
  (let ((list (current-list expander)))
    (incf (list-state-prev-graf list))
    (setf (list-state-prev-depth list) 0)))

(defun end-graf (expander &optional end-span)
  "TeX's end_graf (§1096): end the paragraph being built, if any, at
END-SPAN; an empty one is dropped."
  (when (eq (current-mode expander) :horizontal)
    (if (list-state-contents (current-list expander))
        (break-paragraph expander end-span)
        (pop-nest expander))
    (normal-paragraph expander)))

(defun head-for-vmode (expander token meaning)
  "TeX's head_for_vmode (§1095): a vertical command in horizontal mode.
In a paragraph, \\par is inserted before TOKEN; in restricted horizontal
mode the box must end first (OFF-SAVE), and \\hrule is an error."
  (cond ((eq (current-mode expander) :horizontal)
         (back-token expander token)
         (insert-tokens expander (list (named-token expander "par"
                                                    (token-span token)))))
        ((primitive-named-p meaning "hrule")
         (tex-error "You can't use"
                    :context (format nil "`~A' here except with leaders"
                                     (esc expander "hrule"))
                    :span (token-span token)))
        (t (off-save expander token meaning))))

;;; Math (§§1136-1200)

(defun push-math (expander code &key span context)
  "TeX's push_math (§1136): a math list begun at SPAN, in a group of CODE
with CONTEXT (see GROUP-RECORD)."
  (push-nest expander :math span)
  (new-save-level expander code :context context))

(defun enter-math (expander span &optional context)
  "Go into ordinary math mode (§1139) at SPAN, in a math-shift group of
CONTEXT (the command of an equation number)."
  (let ((state (expander-state expander)))
    (push-math expander :math-shift :span span :context context)
    (set-parameter state :fam -1 :globaldefs nil)
    (begin-token-list expander (parameter state :everymath) :every-math)))

(defun display-line (expander)
  "The width and indentation of the line a display occupies (§1149),
from \\parshape, \\hangindent and \\hangafter at the current \\prevgraf.
Returns the length and the shift, in sp."
  (let* ((state (expander-state expander))
         (prev-graf (list-state-prev-graf (current-list expander)))
         (shape (par-shape state))
         (hang-indent (parameter state :hangindent))
         (hang-after (parameter state :hangafter))
         (hsize (parameter state :hsize)))
    (cond (shape
           (let ((line (nth (1- (min (length shape) (+ prev-graf 2))) shape)))
             (values (cdr line) (car line))))
          ((and (/= hang-indent 0)
                (or (and (>= hang-after 0) (> (+ prev-graf 2) hang-after))
                    (< (+ prev-graf 1) (- hang-after))))
           (values (- hsize (abs hang-indent)) (max hang-indent 0)))
          (t (values hsize 0)))))

(defun enter-display (expander span)
  "Go into display math mode at SPAN (§§1145-1149): the paragraph so far
is ended, then \\predisplaysize (0pt without metrics, -\\maxdimen after an
empty paragraph), \\displaywidth and \\displayindent are set."
  (let ((state (expander-state expander))
        (size (if (list-state-contents (current-list expander))
                  (progn (break-paragraph expander span) 0)
                  (progn (pop-nest expander) (- +max-dimen+)))))
    (multiple-value-bind (length shift) (display-line expander)
      (push-math expander :math-shift :span span)
      (setf (list-state-mode (current-list expander)) :display-math)
      (set-parameter state :fam -1 :globaldefs nil)
      (set-parameter state :predisplaysize size :globaldefs nil)
      (set-parameter state :displaywidth length :globaldefs nil)
      (set-parameter state :displayindent shift :globaldefs nil)
      (begin-token-list expander (parameter state :everydisplay)
                        :every-display))))

(defun init-math (expander span)
  "TeX's init_math (§1138), for `$' read at SPAN in horizontal mode: `$$'
in a paragraph begins a display, anything else inline math.  The token
after the first `$' is read without expansion."
  (multiple-value-bind (token meaning) (get-token expander)
    (if (and (outer-mode-p (current-mode expander))
             (eql (command-catcode token meaning) +math-shift+))
        (enter-display expander span)
        (progn (back-token expander token)
               (enter-math expander span)))))

(defun check-math-fonts (expander)
  "TeX's check of the math fonts at the end of a formula (§1195): family 2
needs 22 parameters in each size and family 3 needs 13, where the count
is known (\\nullfont's); otherwise the formula is deleted, which here is
only the error."
  (let ((state (expander-state expander)))
    (flet ((insufficient-p (family count)
             (loop for size from 0 to 2
                   thereis (let ((known (tex-font-parameter-count
                                         (family-font state size family))))
                             (and known (< known count))))))
      (cond ((insufficient-p 2 22)
             (tex-error "Math formula deleted: Insufficient symbol fonts"))
            ((insufficient-p 3 13)
             (tex-error "Math formula deleted: Insufficient extension fonts"))))))

(defun resume-after-display (expander span)
  "TeX's resume_after_display (§1200): the paragraph goes on after the
display, three lines further, after an optional space, as a new
paragraph node begun at SPAN."
  (unsave expander)
  (incf (list-state-prev-graf (current-list expander)) 3)
  (push-nest expander :horizontal span)
  (let ((list (current-list expander)))
    (setf (list-state-space-factor list) 1000
          (list-state-clang list) (current-language expander)
          (list-state-prev-graf list) (horizontal-prev-graf expander)))
  (scan-optional-space expander)
  (when (= (length (expander-nest expander)) 2)
    (build-page expander)))

(defun check-display-end (expander span)
  "§1197: the second `$' of a display's end; returns its span, else SPAN
after `Display math should end with $$'."
  (multiple-value-bind (token meaning) (get-x-token expander)
    (if (eql (command-catcode token meaning) +math-shift+)
        (token-span token)
        (progn
          (back-token expander token)
          (tex-error "Display math should end with $$"
                     :span (and token (token-span token)))
          span))))

(defun after-math (expander span)
  "TeX's after_math (§1194), for the `$' read at SPAN that ends the
current formula (its group is :MATH-SHIFT); a display needs a second `$'.
The formula becomes a math node: of the paragraph for inline math, of
the enclosing vertical list for a display.  An equation number ends with
its display, and is the display's last child, an :EQNO node."
  (check-math-fonts expander)
  (let ((display (eq (current-mode expander) :display-math))
        (end-span span)
        (eqno nil))
    (multiple-value-bind (nodes math) (fin-mlist expander)
      (when (and (not display) (eq (current-mode expander) :display-math))
        ;; The end of an equation number (§1194).
        (setf end-span (check-display-end expander span)
              eqno (make-node :eqno :properties (list :command (group-record-context
                                                                (unsave expander)))
                                    :children nodes :span (list-state-span math)
                                    :end-span span)
              display t)
        (check-math-fonts expander)
        (multiple-value-setq (nodes math) (fin-mlist expander)))
      (when (and display (null eqno))
        (setf end-span (check-display-end expander span)))
      (append-node expander (make-node :math :properties (and display (list :display t))
                                             :children (if eqno (append nodes (list eqno)) nodes)
                                             :span (list-state-span math)
                                             :end-span end-span)))
    (if display
        (resume-after-display expander end-span)
        (progn
          (setf (list-state-space-factor (current-list expander)) 1000)
          (unsave expander)))))
