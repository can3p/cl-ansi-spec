;;;; src/expand/print.lisp
;;;;
;;;; Printing quantities as \the, \showthe and \message show them (TeX:
;;;; The Program, §103 print_scaled, §§177-178 print_glue and print_spec).

(in-package #:cl-ansi-spec/expand)

(defun format-scaled (s)
  "The sp value S as TeX prints a scaled number (§103): at least one
decimal digit and the fewest digits that read back as S."
  (with-output-to-string (out)
    (when (minusp s)
      (write-char #\- out)
      (setf s (- s)))
    (format out "~D." (floor s +unity+))
    (let ((s (+ (* 10 (mod s +unity+)) 5))
          (delta 10))
      (loop
        (when (> delta +unity+)
          (incf s (- #o100000 50000)))     ; round the last digit
        (write-char (digit-char (floor s +unity+)) out)
        (setf s (* 10 (mod s +unity+))
              delta (* delta 10))
        (when (<= s delta)
          (return))))))

(defun format-dimen (s)
  "The dimension S (sp) as \\the shows it, e.g. \"72.26999pt\"."
  (concatenate 'string (format-scaled s) "pt"))

(defun format-glue-component (value order unit)
  "A stretch or shrink component (§177): VALUE followed by fil, fill or
filll for an infinite ORDER, else by UNIT."
  (concatenate 'string (format-scaled value)
               (if (zerop order)
                   unit
                   (concatenate 'string "fi" (make-string order :initial-element #\l)))))

(defun format-glue (glue)
  "GLUE as \\the shows it (§178), e.g. \"3.0pt plus 1.0fil minus 2.0pt\";
mu glue in mu.  Zero stretch and shrink are omitted."
  (let ((unit (if (glue-mu-p glue) "mu" "pt")))
    (with-output-to-string (out)
      (write-string (format-scaled (glue-width glue)) out)
      (write-string unit out)
      (unless (zerop (glue-stretch glue))
        (write-string " plus " out)
        (write-string (format-glue-component (glue-stretch glue)
                                             (glue-stretch-order glue) unit)
                      out))
      (unless (zerop (glue-shrink glue))
        (write-string " minus " out)
        (write-string (format-glue-component (glue-shrink glue)
                                             (glue-shrink-order glue) unit)
                      out)))))

(defun format-roman (n)
  "N in lowercase roman numerals as \\romannumeral shows it (§69,
print_roman_int); empty unless N is positive.  Thousands are repeated
m's, without limit."
  (let ((digits "m2d5c2l5x2v5i")
        (j 0)
        (v 1000))
    (with-output-to-string (out)
      (loop
        (loop while (>= n v)
              do (write-char (char digits j) out)
                 (decf n v))
        (when (<= n 0)
          (return))
        (let* ((k (+ j 2))
               (u (floor v (digit-char-p (char digits (1- k))))))
          (when (char= (char digits (1- k)) #\2)
            (incf k 2)
            (setf u (floor u (digit-char-p (char digits (1- k))))))
          (if (>= (+ n u) v)
              (progn (write-char (char digits k) out)
                     (incf n u))
              (progn (incf j 2)
                     (setf v (floor v (digit-char-p (char digits (1- j))))))))))))
