;;;; src/expand/units.lisp
;;;;
;;;; Units of measure as data and pure functions (TeX: The Program,
;;;; §§453-458, §§716-717).  A dimension arrives here already split by the
;;;; scanner into its sign, its integer part and its fraction (in sp, from
;;;; ROUND-DECIMALS); the scanner parses the keywords and reports the
;;;; errors these functions flag.  The steps follow scan_dimen:
;;;;
;;;;   physical units:  [APPLY-TRUE-MAGNIFICATION] -> CONVERT-PHYSICAL-UNIT
;;;;   em, ex, an internal dimen, or mu in math:  SCALE-BY-UNIT
;;;;   then always:     ATTACH-SIGN
;;;;
;;;; fil, fill and filll units scale like pt (CONVERT-PHYSICAL-UNIT with
;;;; :pt); their order belongs to the glue.

(in-package #:cl-ansi-spec/expand)

(defun physical-unit-table ()
  "TeX's physical units with their exact ratios to the point, numerator
and denominator (§458), as a literal alist (never modified).  sp has none:
it takes the integer part as is."
  '((:pt 1 1) (:in 7227 100) (:pc 12 1) (:cm 7227 254) (:mm 7227 2540)
    (:bp 7227 7200) (:dd 1238 1157) (:cc 14856 1157) (:sp nil nil)))

(defun physical-units ()
  "The keywords of TeX's physical units, in TeX's order."
  (mapcar #'first (physical-unit-table)))

(defun unit-conversion (unit)
  "The ratio of the physical UNIT to the point, as two values: numerator
and denominator (NIL for :sp).  Signals an error for an unknown unit."
  (let ((entry (assoc unit (physical-unit-table))))
    (unless entry
      (error "Unknown physical unit ~S." unit))
    (values (second entry) (third entry))))

(defun rescale (integer fraction num denom)
  "INTEGER + FRACTION/2^16 times NUM/DENOM, kept as a new integer part and
fraction (§457, §458).  Returns them and OVERFLOW-P."
  (multiple-value-bind (value overflow remainder) (xn-over-d integer num denom)
    (let ((f (floor (+ (* num fraction) (* +unity+ remainder)) denom)))
      (values (+ value (floor f +unity+)) (mod f +unity+) overflow))))

(defun apply-true-magnification (integer fraction mag)
  "Undo the magnification MAG (\\mag, 1..32768, already checked by the
scanner) on a `true' dimension INTEGER + FRACTION/2^16 (§457).  Returns
the new integer part, fraction and OVERFLOW-P."
  (check-type mag (integer 1 32768))
  (if (= mag 1000)
      (values integer fraction nil)
      (rescale integer fraction 1000 mag)))

(defun convert-physical-unit (integer fraction unit)
  "The non-negative dimension INTEGER + FRACTION/2^16 UNITs in sp (§458),
with FRACTION from ROUND-DECIMALS.  Returns it and OVERFLOW-P, which
ATTACH-SIGN turns into `Dimension too large'."
  (if (eq unit :sp)
      (values integer nil)
      (multiple-value-bind (num denom) (unit-conversion unit)
        (multiple-value-bind (integer fraction overflow)
            (if (= num denom 1)
                (values integer fraction nil)
                (rescale integer fraction num denom))
          ;; attach_fraction
          (if (>= integer (expt 2 14))
              (values integer t)
              (values (+ (* integer +unity+) fraction) overflow))))))

(defun scale-by-unit (integer fraction unit-value)
  "INTEGER + FRACTION/2^16 times UNIT-VALUE sp, for em and ex (UNIT-VALUE
is the font's quad or x-height \\fontdimen), an internal dimen, or mu
(§455).  Returns the result and OVERFLOW-P."
  (multiple-value-bind (part overflow-1) (xn-over-d unit-value fraction +unity+)
    (multiple-value-bind (value overflow-2) (nx-plus-y integer unit-value part)
      (values value (or overflow-1 overflow-2)))))

(defun attach-sign (value negative overflow)
  "The final dimension of scan_dimen (§§448, 460): +MAX-DIMEN+ if
OVERFLOW or VALUE is out of range, negated when NEGATIVE.  Returns it and
TOO-LARGE-P, true when the scanner must report `Dimension too large'."
  (let ((too-large (or overflow (>= (abs value) (expt 2 30)))))
    (when too-large
      (setf value +max-dimen+))
    (values (if negative (- value) value) too-large)))

;;; Math units (§§716-717): 1mu is 1/18 of the math quad (\fontdimen6 of
;;; family 2 in the current size).

(defun math-unit (math-quad)
  "The size of 1mu in sp, given the math quad in sp."
  (values (x-over-n math-quad 18)))

(defun mu-multiply (x math-unit)
  "X mu in sp, given 1mu = MATH-UNIT sp (§716, mu_mult).  Returns the
result and OVERFLOW-P."
  (multiple-value-bind (n overflow remainder) (x-over-n math-unit +unity+)
    (declare (ignore overflow))
    (when (minusp remainder)
      (decf n)
      (incf remainder +unity+))
    (scale-by-unit n remainder x)))
