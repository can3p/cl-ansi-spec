;;;; src/expand/arithmetic.lisp
;;;;
;;;; TeX's integer and fixed-point arithmetic (TeX: The Program, §§99-107,
;;;; §§1236-1240).  Integers are CL integers; dimensions are integers in
;;;; scaled points (sp, 2^-16 pt).
;;;;
;;;; Overflow convention.  TeX sets a global flag, arith_error, and lets
;;;; the caller report it.  Here every operation that can overflow returns
;;;; its result as the first value and a generalized boolean OVERFLOW-P as
;;;; the second; a third value, where TeX has one, is the remainder.  The
;;;; first value on overflow is the one TeX computes, so that a caller that
;;;; goes on (as TeX does) gets TeX's numbers.  Reporting the error
;;;; ("Arithmetic overflow", "Dimension too large") is the scanner's job.

(in-package #:cl-ansi-spec/expand)

(defconstant +infinity+ (1- (expt 2 31))
  "The largest integer TeX accepts, 2^31-1 (TeX's infinity, §109).")

(defconstant +max-dimen+ (1- (expt 2 30))
  "The largest legal dimension, 2^30-1 sp = 16383.99998pt (§421).")

(defconstant +unity+ (expt 2 16)
  "One point in scaled points (§101).")

(deftype tex-integer ()
  "A value held by an integer register or parameter: a 32-bit word.  TeX
scans only ±(2^31-1), but \\advance wraps around (see INTEGER-ADVANCE)."
  '(signed-byte 32))

(deftype scaled ()
  "A dimension in scaled points.  Legal dimensions are within
±+MAX-DIMEN+, but \\advance can leave any 32-bit value in a register."
  '(signed-byte 32))

(defun wrap-32 (n)
  "N reduced to a signed 32-bit word, as TeX's implementations do when an
unchecked addition overflows."
  (- (mod (+ n (expt 2 31)) (expt 2 32)) (expt 2 31)))

;;; §§105-107.  Pascal's div and mod truncate towards zero, like CL's
;;; TRUNCATE and REM.

(defun mult-and-add (n x y max-answer)
  "N*X+Y if its magnitude is at most MAX-ANSWER (§105).  Returns the
result and OVERFLOW-P; an overflow yields 0."
  (when (minusp n)
    (setf x (- x) n (- n)))
  (cond ((zerop n) (values y nil))
        ((and (<= x (truncate (- max-answer y) n))
              (<= (- x) (truncate (+ max-answer y) n)))
         (values (+ (* n x) y) nil))
        (t (values 0 t))))

(defun nx-plus-y (n x y)
  "N*X+Y for dimensions X and Y, overflowing beyond +MAX-DIMEN+ (§105).
Returns the result and OVERFLOW-P."
  (mult-and-add n x y +max-dimen+))

(defun mult-integers (n x)
  "N*X for integers, overflowing beyond +INFINITY+ (§105).  Returns the
result and OVERFLOW-P."
  (mult-and-add n x 0 +infinity+))

(defun x-over-n (x n)
  "X divided by N, truncated towards zero (§106).  Returns the quotient,
OVERFLOW-P (true when N is 0; the quotient is then 0) and the remainder,
which has the sign of X."
  (if (zerop n)
      (values 0 t x)
      (multiple-value-bind (quotient remainder) (truncate x n)
        (values quotient nil remainder))))

(defun xn-over-d (x n d)
  "X*N/D, truncated towards zero, for 0 <= N, D <= 2^16 and D > 0 (§107).
Returns the quotient, OVERFLOW-P (true when the quotient is at least 2^30
in magnitude) and the remainder, which has the sign of X.  Computed in
TeX's 15-bit pieces, so that an overflow returns TeX's value."
  (let* ((positive (>= x 0))
         (x (abs x))
         (two-15 (expt 2 15))
         (tt (* (mod x two-15) n))
         (u (+ (* (floor x two-15) n) (floor tt two-15)))
         (v (+ (* (mod u d) two-15) (mod tt two-15)))
         (overflow (>= (floor u d) two-15)))
    (unless overflow
      (setf u (+ (* two-15 (floor u d)) (floor v d))))
    (if positive
        (values u overflow (mod v d))
        (values (- u) overflow (- (mod v d))))))

;;; \advance, \multiply and \divide on integer and dimen registers
;;; (§§1238, 1240).  TeX checks neither sum.

(defun integer-advance (old by)
  "OLD + BY as \\advance computes it: unchecked, wrapping to 32 bits."
  (wrap-32 (+ old by)))

(defun integer-multiply (old by)
  "OLD * BY as \\multiply computes it.  Returns the result and OVERFLOW-P."
  (mult-integers old by))

(defun integer-divide (old by)
  "OLD / BY as \\divide computes it.  Returns the result and OVERFLOW-P
(true when BY is 0)."
  (multiple-value-bind (quotient overflow) (x-over-n old by)
    (values quotient overflow)))

(defun dimen-advance (old by)
  "OLD + BY in sp as \\advance computes it: unchecked, wrapping to 32 bits."
  (wrap-32 (+ old by)))

(defun dimen-multiply (old by)
  "OLD sp times the integer BY as \\multiply computes it.  Returns the
result and OVERFLOW-P."
  (nx-plus-y old by 0))

(defun dimen-divide (old by)
  "OLD sp divided by the integer BY as \\divide computes it.  Returns the
result and OVERFLOW-P (true when BY is 0)."
  (integer-divide old by))

;;; Decimal fractions (§102, §452).

(defun round-decimals (digits)
  "The fraction 0.d1d2... in sp, rounded as TeX rounds it (§102).  DIGITS
is a sequence of integers 0-9; as in TeX (§452), only the first 17 are
used, since later ones cannot change the result."
  (let ((a 0))
    (loop for k from (1- (min 17 (length digits))) downto 0
          do (setf a (floor (+ a (* (elt digits k) (expt 2 17))) 10)))
    (floor (1+ a) 2)))
