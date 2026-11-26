;;;; src/expand/dimen-scan.lisp
;;;;
;;;; TeX's scan_dimen and scan_glue (TeX: The Program, §§448-461) and
;;;; prepare_mag (§288): the keywords and their order, the decimal
;;;; fraction, internal quantities as values and as units, and the errors
;;;; with the units TeX inserts.  The arithmetic is units.lisp's.

(in-package #:cl-ansi-spec/expand)

(defun prepare-mag (expander)
  "TeX's prepare_mag (§288): the \\mag a `true' dimension uses.  Once one
was used, a different \\mag is `Incompatible magnification' and is set
back; one outside 1..32768 becomes 1000.  Both resets are global."
  (let* ((tex (expander-tex expander))
         (mag (integer-parameter tex :mag))
         (set (expander-mag-set expander)))
    (when (and (plusp set) (/= mag set))
      (tex-error "Incompatible magnification"
                 :context (format nil "(~D); the previous value will be retained (~D)"
                                  mag set))
      (set-integer-parameter tex :mag set :global t)
      (setf mag set))
    (unless (<= 1 mag 32768)
      (tex-error "Illegal magnification has been changed to 1000"
                 :context (int-error-context mag))
      (set-integer-parameter tex :mag 1000 :global t)
      (setf mag 1000))
    (setf (expander-mag-set expander) mag)))

(defun point-token-p (token)
  "True when TOKEN is `.' or `,' of category 12 (§448)."
  (or (other-character-p token #\.) (other-character-p token #\,)))

(defun scan-decimal-fraction (expander)
  "Read the decimal point (put back before) and the digits after it,
with expansion (§452).  Returns the fraction in sp; a blank after the
digits is consumed."
  (get-token expander)
  (let ((digits '()))
    (loop
      (multiple-value-bind (token meaning) (get-x-token expander)
        (let ((digit (and (character-catcode-p token +other+)
                          (digit-char-p (code-char (character-token-code token))))))
          (cond (digit
                 (when (< (length digits) 17)
                   (push digit digits)))
                (t
                 (unless (and token (blank-p token meaning))
                   (back-token expander token))
                 (return (round-decimals (nreverse digits))))))))))

(defun scan-internal-as-mu (expander token meaning)
  "An internal quantity read where mu are wanted (§§451, 456): glue gives
its width.  Returns the value and its level."
  (multiple-value-bind (value level)
      (scan-something-internal expander token meaning :mu nil)
    (values (if (member level '(:glue :mu)) (glue-width value) value)
            level)))

(defun scan-unit (expander integer fraction mu inf)
  "Read the unit of a dimension whose magnitude is INTEGER +
FRACTION/2^16 (§§453-459).  Returns the value in sp (or mu), the order
of infinity (0, or 1-3 for fil, fill, filll) and OVERFLOW-P."
  (let ((order 0))
    (flet ((attached (unit &optional overflow)
             ;; attach_fraction, then the optional space (§§453, 448).
             (multiple-value-bind (value overflow-2)
                 (convert-physical-unit integer fraction unit)
               (scan-optional-space expander)
               (return-from scan-unit (values value order (or overflow overflow-2)))))
           (scaled-by (unit-value)
             (multiple-value-bind (value overflow)
                 (scale-by-unit integer fraction unit-value)
               (return-from scan-unit (values value order overflow)))))
      (when (and inf (scan-keyword expander "fil"))
        (setf order 1)
        (loop while (scan-keyword expander "l")
              do (if (= order 3)
                     (tex-error "Illegal unit of measure (replaced by filll)")
                     (incf order)))
        (attached :pt))
      ;; An internal quantity as the unit (§455).
      (multiple-value-bind (token meaning) (get-x-nonblank expander)
        (cond ((internal-command-p meaning)
               (scaled-by
                (if mu
                    (multiple-value-bind (value level)
                        (scan-internal-as-mu expander token meaning)
                      (unless (eq level :mu) (mu-error))
                      value)
                    (values (scan-something-internal expander token meaning
                                                     :dimen nil)))))
              (t (back-token expander token))))
      (when mu
        (unless (scan-keyword expander "mu")
          (tex-error "Illegal unit of measure (mu inserted)"))
        (attached :pt))
      (let ((font (current-font (expander-state expander))))
        (cond ((scan-keyword expander "em")
               (scan-optional-space expander)
               (scaled-by (font-dimen font 6)))
              ((scan-keyword expander "ex")
               (scan-optional-space expander)
               (scaled-by (font-dimen font 5)))))
      (let ((overflow nil))
        (when (scan-keyword expander "true")
          (multiple-value-setq (integer fraction overflow)
            (apply-true-magnification integer fraction (prepare-mag expander))))
        (dolist (unit (physical-units))
          (when (scan-keyword expander (string-downcase (symbol-name unit)))
            (attached unit overflow)))
        (tex-error "Illegal unit of measure (pt inserted)")
        (attached :pt overflow)))))

(defun scan-dimen (expander &key mu inf shortcut)
  "TeX's scan_dimen (§448): a dimension in sp, with expansion; in mu
units when MU; fil, fill and filll allowed when INF.  SHORTCUT, an
integer already scanned, is the magnitude, so that only the unit is read.
Returns the value and its order of infinity.  An overflow is `Dimension
too large' and gives \\maxdimen."
  (let ((negative nil) (integer 0) (fraction 0))
    (flet ((finish (value overflow order)
             (multiple-value-bind (value too-large) (attach-sign value negative overflow)
               (when too-large
                 (tex-error "Dimension too large"))
               (return-from scan-dimen (values value order)))))
      (if shortcut
          (setf integer shortcut)
          (multiple-value-bind (token meaning signs) (scan-signs expander)
            (setf negative signs)
            (cond ((internal-command-p meaning)
                   (multiple-value-bind (value level)
                       (if mu
                           (scan-internal-as-mu expander token meaning)
                           (scan-something-internal expander token meaning
                                                    :dimen nil))
                     (when (eq level (if mu :mu :dimen))
                       (finish value nil 0))
                     (when (and mu (not (eq level :int)))
                       (mu-error))
                     (setf integer value)))
                  (t
                   (back-token expander token)
                   (multiple-value-bind (value radix last)
                       (if (point-token-p token)
                           (values 0 10 token)
                           (%scan-int expander))
                     (setf integer value)
                     (when (and (= radix 10) (point-token-p last))
                       (setf fraction (scan-decimal-fraction expander))))))))
      (when (minusp integer)
        (setf negative (not negative) integer (- integer)))
      (multiple-value-bind (value order overflow)
          (scan-unit expander integer fraction mu inf)
        (finish value overflow order)))))

(defun scan-glue (expander level)
  "TeX's scan_glue (§461): glue (LEVEL :GLUE) or mu glue (:MU), with
expansion: an internal glue, or a width with optional `plus' and `minus'
components, which may be infinite."
  (let ((mu (eq level :mu))
        (width 0))
    (multiple-value-bind (token meaning negative) (scan-signs expander)
      (cond ((internal-command-p meaning)
             (multiple-value-bind (value got)
                 (scan-something-internal expander token meaning level negative)
               (case got
                 ((:glue :mu)
                  (unless (eq got level) (mu-error))
                  (return-from scan-glue (retag-glue value mu)))
                 (:int (setf width (scan-dimen expander :mu mu :shortcut value)))
                 (t (when mu (mu-error))
                    (setf width value)))))
            (t
             (back-token expander token)
             (setf width (scan-dimen expander :mu mu))
             (when negative (setf width (- width))))))
    (multiple-value-bind (stretch stretch-order)
        (if (scan-keyword expander "plus") (scan-dimen expander :mu mu :inf t) (values 0 0))
      (multiple-value-bind (shrink shrink-order)
          (if (scan-keyword expander "minus") (scan-dimen expander :mu mu :inf t) (values 0 0))
        (make-glue :width width :stretch stretch :shrink shrink
                   :stretch-order stretch-order :shrink-order shrink-order
                   :mu-p mu)))))
