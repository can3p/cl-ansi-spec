;;;; tests/expand/quantities.lisp
;;;;
;;;; TeX's quantities (src/expand/arithmetic.lisp, units.lisp, glue.lisp,
;;;; print.lisp): properties of the arithmetic against CL's exact
;;;; arithmetic, goldens derived from TeX's rules, and print/read round
;;;; trips.

(in-package #:cl-ansi-spec/tests)

(define-test quantities
  :parent cl-ansi-spec
  :description "Integers, dimensions and glue with TeX's exact arithmetic.")

(defun pseudo-random-generator (seed)
  "A deterministic generator of integers (Park-Miller), so that property
tests are reproducible: (funcall it low high) is in [LOW, HIGH]."
  (lambda (low high)
    (setf seed (mod (* seed 48271) 2147483647))
    (+ low (mod seed (1+ (- high low))))))

(defun boundary-integers (limit)
  "Integers around 0, 2^15, 2^30, 2^31 and LIMIT, with both signs, within
±LIMIT."
  (remove-duplicates
   (loop for base in (list 0 1 (expt 2 15) (expt 2 16) (expt 2 30)
                           (expt 2 31) limit)
         nconc (loop for delta from -2 to 2
                     for n = (+ base delta)
                     when (<= (abs n) limit) nconc (list n (- n))))))

(defun read-test-dimen (string &key (mag 1000) unit-value)
  "The dimension STRING (sign, decimal, `true', unit, as \"-1.5truecm\")
read along scan_dimen's steps.  UNIT-VALUE is the sp of em/ex.  Returns
the sp and TOO-LARGE-P."
  (let* ((negative (char= (char string 0) #\-))
         (string (string-left-trim "+-" string))
         (end (position-if (lambda (c) (not (or (digit-char-p c) (char= c #\.))))
                           string))
         (number (subseq string 0 end))
         (dot (position #\. number))
         (integer (if (eql dot 0) 0 (parse-integer number :end dot)))
         (fraction (if dot
                       (expand:round-decimals
                        (map 'list #'digit-char-p (subseq number (1+ dot))))
                       0))
         (unit (subseq string end))
         (true (and (> (length unit) 4) (string= "true" unit :end2 4))))
    (when true (setf unit (subseq unit 4)))
    (multiple-value-bind (value overflow)
        (cond ((member unit '("em" "ex") :test #'string=)
               (expand:scale-by-unit integer fraction unit-value))
              (t
               (let ((overflow-1 nil))
                 (when true
                   (multiple-value-setq (integer fraction overflow-1)
                     (expand:apply-true-magnification
                      integer fraction mag)))
                 (multiple-value-bind (value overflow-2)
                     (expand:convert-physical-unit
                      integer fraction
                      (intern (string-upcase unit) :keyword))
                   (values value (or overflow-1 overflow-2))))))
      (expand:attach-sign value negative overflow))))

(defun the-dimen (string &rest options)
  "STRING read as a dimension and printed as \\the prints it."
  (expand:format-dimen (apply #'read-test-dimen string options)))

;;; Arithmetic

(defun counterexamples (property generate)
  "The argument lists for which PROPERTY is false, among those GENERATE
passes to the checking function it receives."
  (let ((failures '()))
    (funcall generate (lambda (&rest arguments)
                        (unless (apply property arguments)
                          (push arguments failures))))
    failures))

(defun x-over-n-agrees-p (x n)
  "x_over_n agrees with TRUNCATE, and flags a division by 0."
  (multiple-value-bind (q overflow r) (expand:x-over-n x n)
    (if (zerop n)
        (and overflow (= q 0) (= r x))
        (multiple-value-bind (eq er) (truncate x n)
          (and (not overflow) (= q eq) (= r er))))))

(defun xn-over-d-agrees-p (x n d)
  "xn_over_d agrees with TRUNCATE of X*N by D below 2^30, flags overflow above."
  (multiple-value-bind (q overflow r) (expand:xn-over-d x n d)
    (multiple-value-bind (eq er) (truncate (* x n) d)
      (if (>= (abs eq) (expt 2 30))
          overflow
          (and (not overflow) (= q eq) (= r er))))))

(defun nx-plus-y-agrees-p (n x y)
  "nx_plus_y is N*X+Y (Y when N is 0) within max_dimen, else overflows to 0."
  (multiple-value-bind (value overflow) (expand:nx-plus-y n x y)
    (let ((exact (if (zerop n) y (+ (* n x) y))))
      (if (> (abs exact) expand:+max-dimen+)
          (and overflow (= value 0))
          (and (not overflow) (= value exact))))))

(define-test x-over-n-property
  :parent quantities
  (let ((random (pseudo-random-generator 1))
        (limit expand:+infinity+))
    (is equal '()
        (counterexamples
         #'x-over-n-agrees-p
         (lambda (check)
           (dolist (x (boundary-integers limit))
             (dolist (n (boundary-integers limit))
               (funcall check x n)))
           (loop repeat 20000
                 do (funcall check (funcall random (- limit) limit)
                             (funcall random (- limit) limit))))))))

(define-test xn-over-d-property
  :parent quantities
  (let ((random (pseudo-random-generator 2))
        (limit expand:+infinity+))
    (is equal '()
        (counterexamples
         #'xn-over-d-agrees-p
         (lambda (check)
           (dolist (x (boundary-integers limit))
             (dolist (n '(0 1 2 1000 7227 32767 32768 65535 65536))
               (dolist (d '(1 2 100 1157 7200 32768 65536))
                 (funcall check x n d))))
           (loop repeat 20000
                 do (funcall check (funcall random (- limit) limit)
                             (funcall random 0 65536)
                             (funcall random 1 65536))))))))

(define-test nx-plus-y-property
  :parent quantities
  (let ((random (pseudo-random-generator 3))
        (max expand:+max-dimen+))
    (is equal '()
        (counterexamples
         #'nx-plus-y-agrees-p
         (lambda (check)
           (dolist (n (boundary-integers expand:+infinity+))
             (dolist (x (boundary-integers max))
               (dolist (y (list 0 1 -1 max (- max) (expt 2 15)))
                 (funcall check n x y))))
           (loop repeat 20000
                 do (funcall check (funcall random -70000 70000)
                             (funcall random (- max) max)
                             (funcall random (- max) max))))))))

(define-test integer-operations
  :parent quantities
  (let ((infinity expand:+infinity+))
    (is = (- (expt 2 31)) (expand:integer-advance infinity 1))
    (is = infinity (expand:integer-advance (- (expt 2 31)) -1))
    (is = infinity (expand:integer-multiply infinity 1))
    (is = (- infinity) (expand:integer-multiply infinity -1))
    (true (nth-value 1 (expand:integer-multiply (expt 2 16) (expt 2 15))))
    (false (nth-value 1 (expand:integer-multiply (expt 2 15) (expt 2 15))))
    (is = -3 (expand:integer-divide -7 2))
    (is = 3 (expand:integer-divide -7 -2))
    (true (nth-value 1 (expand:integer-divide 5 0)))
    ;; Dimensions overflow at 2^30 under \multiply.
    (is = expand:+max-dimen+
        (expand:dimen-multiply expand:+max-dimen+ 1))
    (true (nth-value 1 (expand:dimen-multiply (expt 2 29) 2)))
    (true (nth-value 1 (expand:dimen-divide 5 0)))
    (is = (expt 2 30) (expand:dimen-advance expand:+max-dimen+ 1))
    (is = infinity (expand:dimen-advance (- (expt 2 31)) -1))))

(define-test round-decimals
  :parent quantities
  (flet ((rd (string) (expand:round-decimals
                       (map 'list #'digit-char-p string))))
    (is = 0 (rd ""))
    (is = 32768 (rd "5"))
    (is = 65536 (rd "99999999"))        ; rounds up to a whole point
    (is = 65535 (rd "99999"))
    (is = 1 (rd "00001"))
    (is = 0 (rd "000007"))
    ;; Digits beyond the 17th are ignored.
    (is = (rd "12345678901234567") (rd "12345678901234567999"))))

;;; Units and printing

(define-test dimension-goldens
  :parent quantities
  (is string= "72.26999pt" (the-dimen "1in"))
  (is string= "28.45274pt" (the-dimen "1cm"))
  (is string= "2.84526pt" (the-dimen "1mm"))
  (is string= "1.00374pt" (the-dimen "1bp"))
  (is string= "1.07pt" (the-dimen "1dd"))
  (is string= "12.8401pt" (the-dimen "1cc"))
  (is string= "12.0pt" (the-dimen "1pc"))
  (is string= "0.00002pt" (the-dimen "1sp"))
  (is string= "1.0pt" (the-dimen "65536sp"))
  (is string= "-0.5pt" (the-dimen "-.5pt"))
  (is string= "0.0pt" (the-dimen "0pt"))
  (is string= "1.0pt" (the-dimen "0.999999pt"))
  ;; sp skips attach_fraction: the fraction is dropped.
  (is = 1 (read-test-dimen "1.5sp"))
  (fail (expand:unit-conversion :furlong)))

(define-test dimension-limits
  :parent quantities
  (let ((max expand:+max-dimen+))
    (is = max (read-test-dimen "16383.99999pt"))
    (is string= "16383.99998pt" (the-dimen "16383.99999pt"))
    (is string= "-16383.99998pt" (the-dimen "-16383.99999pt"))
    (dolist (too-large '("16384pt" "16383.999999pt" "1073741824sp" "227in"
                         "-16384pt" "2147483647cm"))
      (multiple-value-bind (value too-large-p) (read-test-dimen too-large)
        (true too-large-p "~A is too large" too-large)
        (is = max (abs value) "~A clamps to max_dimen" too-large)))
    (false (nth-value 1 (read-test-dimen "1073741823sp")))
    (false (nth-value 1 (read-test-dimen "226in")))))

(define-test true-dimensions
  :parent quantities
  (is string= "72.26999pt" (the-dimen "1truein"))
  (is = expand:+unity+ (read-test-dimen "1truept"))
  (is string= "36.135pt" (the-dimen "1truein" :mag 2000))
  (is string= "20.0pt" (the-dimen "10truept" :mag 500))
  (is string= "10.0pt" (the-dimen "10pt" :mag 500))
  (true (nth-value 1 (read-test-dimen "10000truept" :mag 500)))
  (fail (expand:apply-true-magnification 1 0 0)))

(define-test font-relative-units
  :parent quantities
  (let ((quad (* 10 expand:+unity+)))
    (is string= "15.0pt" (the-dimen "1.5em" :unit-value quad))
    (is string= "-5.0pt" (the-dimen "-.5ex" :unit-value quad))
    (is string= "0.0pt" (the-dimen "3em" :unit-value 0))
    (true (nth-value 1 (read-test-dimen "2000em" :unit-value quad)))))

(define-test math-units
  :parent quantities
  (let ((mu (expand:math-unit (* 18 expand:+unity+))))
    (is = expand:+unity+ mu)
    (is = (* 3 expand:+unity+)
        (expand:mu-multiply (* 3 expand:+unity+) mu))
    (is = 0 (expand:mu-multiply 0 mu))
    ;; A negative math unit: n is floored, the fraction kept positive.
    (is = (- (* 3 expand:+unity+))
        (expand:mu-multiply (* 3 expand:+unity+) (- mu)))))

(define-test print-read-round-trip
  :parent quantities
  (let ((failures '()))
    (flet ((round-trip (sp)
             (let* ((printed (expand:format-scaled sp))
                    (value (read-test-dimen (concatenate 'string printed "pt"))))
               (unless (= value sp)
                 (push (list sp printed value) failures)))))
      (loop for sp from 0 below 65536 do (round-trip sp) (round-trip (- sp)))
      (loop for sp from 65536 to expand:+max-dimen+ by 9973
            do (round-trip sp))
      (round-trip expand:+max-dimen+))
    (is equal '() failures "(sp printed read-back) that do not round-trip")))

;;; Glue

(defun points (x)
  "X points in sp."
  (round (* x expand:+unity+)))

(define-test glue-printing
  :parent quantities
  (flet ((the-glue (&rest args)
           (expand:format-glue
            (apply #'expand:make-glue args))))
    (is string= "0.0pt" (the-glue))
    (is string= "3.0pt plus 1.0fil minus 2.0pt"
        (the-glue :width (points 3) :stretch (points 1) :stretch-order 1 :shrink (points 2)))
    (is string= "0.0pt minus 1.0filll"
        (the-glue :shrink (points 1) :shrink-order 3))
    (is string= "1.0mu plus 2.0fill"
        (the-glue :width (points 1) :stretch (points 2) :stretch-order 2 :mu-p t))
    (is string= "-1.5mu plus 0.5mu"
        (the-glue :width (points -3/2) :stretch (points 1/2) :mu-p t))
    ;; A zero stretch is not shown, whatever its order.
    (is string= "1.0pt" (the-glue :width (points 1) :stretch-order 2))))

(define-test glue-arithmetic
  :parent quantities
  (flet ((g (&rest args) (apply #'expand:make-glue args))
         (same (a b) (true (expand:glue= a b) "~A /= ~A"
                           (expand:format-glue a)
                           (expand:format-glue b))))
    ;; The higher order wins; equal orders add.
    (same (g :width (points 3) :stretch (points 1) :stretch-order 1)
          (expand:glue-advance
           (g :width (points 1) :stretch (points 1) :stretch-order 1)
           (g :width (points 2) :stretch (points 3))))
    (same (g :width (points 3) :stretch (points 1) :stretch-order 1)
          (expand:glue-advance
           (g :width (points 1) :stretch (points 3))
           (g :width (points 2) :stretch (points 1) :stretch-order 1)))
    (same (g :stretch (points 4) :stretch-order 2 :shrink (points 3))
          (expand:glue-advance
           (g :stretch (points 1) :stretch-order 2 :shrink (points 1))
           (g :stretch (points 3) :stretch-order 2 :shrink (points 2))))
    ;; A zero stretch loses its order, and a zero register's order loses.
    (same (g :stretch (points 3))
          (expand:glue-advance
           (g :stretch (points 3))
           (g :stretch 0 :stretch-order 3)))
    (same (g :stretch (points 3))
          (expand:glue-advance
           (g :stretch 0 :stretch-order 3)
           (g :stretch (points 3))))
    ;; \multiply, \divide, negation keep the orders.
    (same (g :width (points 6) :stretch (points 2) :stretch-order 1 :shrink (points -4))
          (expand:glue-multiply
           (g :width (points 3) :stretch (points 1) :stretch-order 1 :shrink (points -2)) 2))
    (true (nth-value 1 (expand:glue-multiply
                        (g :shrink (expt 2 29)) 2)))
    (same (g :width 1 :stretch -1 :stretch-order 3)
          (expand:glue-divide (g :width 3 :stretch -3 :stretch-order 3) 2))
    (true (nth-value 1 (expand:glue-divide (g :width 3) 0)))
    (same (g :width (points -1) :stretch (points -2) :stretch-order 1 :shrink (points 3) :mu-p t)
          (expand:glue-negate
           (g :width (points 1) :stretch (points 2) :stretch-order 1 :shrink (points -3) :mu-p t)))
    ;; Negation is unchecked: -2^31 stays itself, as a 32-bit word.
    (is = (- (expt 2 31))
        (expand:glue-width (expand:glue-negate (g :width (- (expt 2 31))))))
    ;; mu glue to points: finite components convert, infinite ones stay.
    (same (g :width (points 6) :stretch (points 1) :stretch-order 1 :shrink (points 2))
          (expand:mu-glue-to-glue
           (g :width (points 3) :stretch (points 1) :stretch-order 1 :shrink (points 1) :mu-p t)
           (points 2)))))
