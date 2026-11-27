;;;; src/expand/font.lisp
;;;;
;;;; Fonts as identifiers, without metrics (docs/tex-fidelity.md, "Not
;;;; emulated").  A font remembers what \font named it after and the
;;;; \fontdimen, \hyphenchar and \skewchar values assigned to it; these
;;;; assignments are global in TeX (§§578, 1253), so they are plain slot
;;;; writes, outside the save stack.

(in-package #:cl-ansi-spec/expand)

(defstruct (tex-font (:constructor %make-tex-font (file size identifier
                                                    hyphen-char skew-char))
                     (:copier nil))
  "A font loaded by \\font.  FILE is the font's file name (\"cmr10\"),
SIZE its size specification as NORMALIZE-FONT-SIZE returns it, and
IDENTIFIER the name of the control sequence \\font last defined with it
(TeX's font_id_text, shown by \\meaning; §1260).  DIMENS holds the
\\fontdimen values assigned so far: without metrics every other
parameter is 0.
PARAMETER-COUNT is TeX's font_params: known only for \\nullfont (7,
§552), NIL (any number) for a font loaded without its metrics."
  (file "" :type string :read-only t)
  (size nil :read-only t)
  (identifier "" :type string)
  (dimens (make-array 0 :adjustable t :initial-element 0) :read-only t)
  (hyphen-char 0 :type integer)
  (skew-char 0 :type integer)
  (parameter-count nil :type (or null (integer 0)))
  ;; The font's name as the :STYLE of text (FONT-STYLE-NAME), made on
  ;; first use.
  (style nil :type (or null string)))

(defun normalize-font-size (size)
  "SIZE, one of NIL (the design size), (:AT sp) or (:SCALED n), in the form
under which two loads are the same font: `scaled 1000' is the design size.
Without metrics the design size is unknown, so `at' sizes never match it."
  (if (equal size '(:scaled 1000)) nil size))

(defun make-tex-font (file &key size (identifier file) (hyphen-char 0)
                             (skew-char 0) parameter-count)
  "A new font for FILE at SIZE (see NORMALIZE-FONT-SIZE).  HYPHEN-CHAR and
SKEW-CHAR are \\defaulthyphenchar and \\defaultskewchar at load time;
PARAMETER-COUNT is NIL unless the number of parameters is known."
  (let ((font (%make-tex-font file (normalize-font-size size) identifier
                              hyphen-char skew-char)))
    (setf (tex-font-parameter-count font) parameter-count)
    font))

(defun font-dimen (font n)
  "\\fontdimen N of FONT: the value assigned, else 0."
  (check-type n (integer 1))
  (let ((dimens (tex-font-dimens font)))
    (if (<= n (length dimens)) (aref dimens (1- n)) 0)))

(defun set-font-dimen (font n value)
  "Assign VALUE (sp) to \\fontdimen N of FONT; always global, as in TeX."
  (check-type n (integer 1))
  (check-type value scaled)
  (let ((dimens (tex-font-dimens font)))
    (when (> n (length dimens))
      (adjust-array dimens n :initial-element 0))
    (setf (aref dimens (1- n)) value)))
