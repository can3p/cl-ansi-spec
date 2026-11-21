;;;; src/expand/expandable.lisp
;;;;
;;;; The expandable primitives of the expansion core (TeX: The Program,
;;;; §§366-378, 464-472): \expandafter, \noexpand, \csname, \string,
;;;; \meaning, \jobname, \input, \endinput and the marks.  Each is
;;;; registered in the primitive table.

(in-package #:cl-ansi-spec/expand)

(defun define-expandable (name operation)
  "Register the expandable primitive NAME with OPERATION, a function of
the expander and the primitive's token."
  (define-primitive name :expandable-p t :operation operation))

(define-expandable "expandafter"
  (lambda (expander token)
    (declare (ignorable token))
    ;; §368
    (let ((first (get-token expander)))
      (multiple-value-bind (second meaning) (get-token expander)
        (cond ((null second))
              ((expandable-p second meaning) (expand expander second meaning))
              (t (back-token expander second))))
      (back-token expander first))))

(define-expandable "noexpand"
  (lambda (expander token)
    (declare (ignorable token))
    ;; §367: the next token, read with the scanner status :normal, is put
    ;; back marked so that it does not expand.
    (let ((next (get-token-normally expander)))
      (back-token expander
                  (if (cs-token-p next)
                      (make-dont-expand-token (cs-token-control-sequence next)
                                              (token-span next))
                      next)))))

(define-expandable "csname"
  (lambda (expander token)
    (declare (ignorable token))
    ;; §372
    (let ((codes '())
          (state (expander-state expander)))
      (loop
        (multiple-value-bind (next meaning) (get-x-token expander)
          (cond ((null next) (return))
                ((character-token-p next)
                 (push (character-token-code next) codes))
                (t
                 (unless (meaning= meaning (find-primitive "endcsname"))
                   (back-token expander next)
                   (tex-error "Missing \\endcsname inserted" :span (token-span next)))
                 (return)))))
      (let ((cs (intern-control-sequence
                 (expander-tex expander)
                 (map 'string #'code-char (nreverse codes)))))
        (unless (meaning state cs)
          ;; eq_define: local, whatever \globaldefs says.
          (set-meaning state cs (find-primitive "relax") :globaldefs nil))
        (back-token expander (make-cs-token cs (token-span token)))))))

(define-expandable "string"
  (lambda (expander token)
    (declare (ignorable token))
    ;; §§465, 469
    (let ((next (get-token-normally expander)))
      (when next
        (insert-tokens
         expander
         (string-tokens (if (cs-token-p next)
                            (cs-name-text expander (cs-token-control-sequence next))
                            (string (code-char (character-token-code next))))
                        (token-span token)))))))

(define-expandable "meaning"
  (lambda (expander token)
    (declare (ignorable token))
    ;; §§465, 469
    (multiple-value-bind (next meaning)
        (get-token-normally expander)
      (when next
        (insert-tokens expander (string-tokens (meaning-text expander next meaning)
                                               (token-span token)))))))

(define-expandable "jobname"
  (lambda (expander token)
    (declare (ignorable token))
    (insert-tokens expander (string-tokens (expander-job-name expander)
                                           (token-span token)))))

(defun blank-p (token meaning)
  "True when TOKEN with MEANING is TeX's spacer command: a space token, or
a control sequence \\let to one."
  (or (character-catcode-p token +space+)
      (and (character-meaning-p meaning)
           (= (character-meaning-catcode meaning) +space+))))

(defun scan-file-name (expander)
  "TeX's scan_file_name (§526): skip blanks, then take characters, with
expansion, up to a space (consumed) or a token that is not a character
(put back).  A control sequence \\let to a character counts as one."
  (setf (expander-name-in-progress expander) t)
  (unwind-protect
       (let ((codes '()))
         (multiple-value-bind (token meaning) (get-x-token expander)
           (loop while (and token (blank-p token meaning))
                 do (multiple-value-setq (token meaning) (get-x-token expander)))
           (loop
             (when (null token) (return))
             (multiple-value-bind (code catcode)
                 (cond ((character-token-p token)
                        (values (character-token-code token)
                                (character-token-catcode token)))
                       ((character-meaning-p meaning)
                        (values (character-meaning-code meaning)
                                (character-meaning-catcode meaning))))
               (when (or (null catcode) (> catcode +other+) (> code 255))
                 (back-token expander token)
                 (return))
               (when (= code 32)
                 (return))
               (push code codes))
             (multiple-value-setq (token meaning) (get-x-token expander))))
         (map 'string #'code-char (nreverse codes)))
    (setf (expander-name-in-progress expander) nil)))

(define-expandable "input"
  (lambda (expander token)
    (declare (ignorable token))
    ;; §§376-378
    (if (expander-name-in-progress expander)
        (progn                            ; insert_relax (§379)
          (back-token expander token)
          (back-token expander (make-cs-token (frozen-control-sequence expander "relax")
                                              (token-span token))))
        (let ((name (scan-file-name expander)))
          (handler-case (push-file (expander-input expander) name)
            (input-file-missing ()
              (tex-fatal-error "I can't find file" :context name
                                                   :span (token-span token))))))))

(define-expandable "endinput"
  (lambda (expander token)
    (declare (ignorable token))
    (end-current-file (expander-input expander))))

(dolist (name '("topmark" "firstmark" "botmark" "splitfirstmark" "splitbotmark"))
  (let ((index (mark-index name)))
    (define-primitive name
      :expandable-p t
      :operation (lambda (expander token)
                   (declare (ignore token))
                   (let ((mark (aref (expander-marks expander) index)))
                     (when mark
                       (push-tokens (expander-input expander) mark :mark)))))))
