;;;; src/expand/glue.lisp
;;;;
;;;; Glue specifications (TeX: The Program, §150) and the operations
;;;; \advance, \multiply, \divide and negation perform on them (§§461,
;;;; 1239-1240), plus the conversion of mu glue to points (§716).  Glue is
;;;; immutable: registers share it, and the save stack restores it by
;;;; reference.

(in-package #:cl-ansi-spec/expand)

(deftype glue-order ()
  "The order of infinity of a stretch or shrink component: 0 for finite,
1 fil, 2 fill, 3 filll."
  '(integer 0 3))

(defstruct (glue (:constructor make-glue
                     (&key (width 0) (stretch 0) (shrink 0)
                        (stretch-order 0) (shrink-order 0) mu-p))
                 (:copier nil))
  "A glue specification.  WIDTH, STRETCH and SHRINK are in sp (in mu units
when MU-P, for \\muskip registers and math glue); a zero STRETCH or SHRINK
may still carry an order, as in TeX."
  (width 0 :type scaled :read-only t)
  (stretch 0 :type scaled :read-only t)
  (shrink 0 :type scaled :read-only t)
  (stretch-order 0 :type glue-order :read-only t)
  (shrink-order 0 :type glue-order :read-only t)
  (mu-p nil :type boolean :read-only t))

(defun glue= (a b)
  "True when the glue specifications A and B have the same components."
  (and (= (glue-width a) (glue-width b))
       (= (glue-stretch a) (glue-stretch b))
       (= (glue-shrink a) (glue-shrink b))
       (= (glue-stretch-order a) (glue-stretch-order b))
       (= (glue-shrink-order a) (glue-shrink-order b))
       (eq (glue-mu-p a) (glue-mu-p b))))

(defun add-component (value order old-value old-order)
  "The sum of one stretch or shrink component of a scanned glue (VALUE,
ORDER) and the register's (OLD-VALUE, OLD-ORDER), as §1239 computes it:
the higher nonzero order wins; equal orders add, unchecked."
  (when (zerop value)
    (setf order 0))
  (cond ((= order old-order) (values (wrap-32 (+ value old-value)) order))
        ((and (< order old-order) (/= old-value 0)) (values old-value old-order))
        (t (values value order))))

(defun glue-advance (old by)
  "\\advance of a register holding the glue OLD by the scanned glue BY
(§1239).  Widths add unchecked; see ADD-COMPONENT for the rest."
  (multiple-value-bind (stretch stretch-order)
      (add-component (glue-stretch by) (glue-stretch-order by)
                     (glue-stretch old) (glue-stretch-order old))
    (multiple-value-bind (shrink shrink-order)
        (add-component (glue-shrink by) (glue-shrink-order by)
                       (glue-shrink old) (glue-shrink-order old))
      (make-glue :width (wrap-32 (+ (glue-width by) (glue-width old)))
                 :stretch stretch :stretch-order stretch-order
                 :shrink shrink :shrink-order shrink-order
                 :mu-p (glue-mu-p old)))))

(defun map-components (function glue)
  "A copy of GLUE whose width, stretch and shrink are FUNCTION of the old
ones; FUNCTION returns a value and OVERFLOW-P.  Returns the new glue and
whether any component overflowed."
  (let ((overflow nil))
    (flet ((apply-1 (x)
             (multiple-value-bind (value overflow-p) (funcall function x)
               (when overflow-p (setf overflow t))
               value)))
      (values (make-glue :width (apply-1 (glue-width glue))
                         :stretch (apply-1 (glue-stretch glue))
                         :shrink (apply-1 (glue-shrink glue))
                         :stretch-order (glue-stretch-order glue)
                         :shrink-order (glue-shrink-order glue)
                         :mu-p (glue-mu-p glue))
              overflow))))

(defun glue-multiply (glue n)
  "\\multiply of GLUE by the integer N, each component by nx_plus_y
(§1240).  Returns the glue and OVERFLOW-P."
  (map-components (lambda (x) (nx-plus-y x n 0)) glue))

(defun glue-divide (glue n)
  "\\divide of GLUE by the integer N, each component by x_over_n (§1240).
Returns the glue and OVERFLOW-P (true when N is 0)."
  (map-components (lambda (x) (x-over-n x n)) glue))

(defun glue-negate (glue)
  "GLUE with every component negated, as a leading minus sign does to
internal glue (§461); unchecked, wrapping to 32 bits."
  (values (map-components (lambda (x) (values (wrap-32 (- x)) nil)) glue)))

(defun mu-glue-to-glue (glue math-unit)
  "The mu GLUE in points, given 1mu = MATH-UNIT sp (§716): the width and
the finite components are converted, infinite ones are kept.  Returns the
glue and OVERFLOW-P."
  (let ((overflow nil))
    (flet ((convert (x)
             (multiple-value-bind (value overflow-p) (mu-multiply x math-unit)
               (when overflow-p (setf overflow t))
               value)))
      (values
       (make-glue :width (convert (glue-width glue))
                  :stretch (if (zerop (glue-stretch-order glue))
                               (convert (glue-stretch glue))
                               (glue-stretch glue))
                  :stretch-order (glue-stretch-order glue)
                  :shrink (if (zerop (glue-shrink-order glue))
                              (convert (glue-shrink glue))
                              (glue-shrink glue))
                  :shrink-order (glue-shrink-order glue))
       overflow))))
