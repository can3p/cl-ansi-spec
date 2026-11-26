;;;; src/expand/toks.lisp
;;;;
;;;; Token lists (TeX: The Program, §§464-479): scan_toks, which reads a
;;;; definition's parameter text and body or a general text, with or
;;;; without expansion; the_toks, the tokens \the gives; and the
;;;; expandable primitives built on them, \the, \number, \romannumeral and
;;;; \fontname (§§465, 470).

(in-package #:cl-ansi-spec/expand)

(defun brace-token-p (token catcode)
  "True when TOKEN is a character token of CATCODE, a brace (TeX compares
cur_tok with the brace limits, so a \\let brace does not count)."
  (and token (character-catcode-p token catcode)))

(defun parameter-command-code (token meaning)
  "The character code of TOKEN with MEANING when it is a macro parameter
character (cur_cmd = mac_param): a character of category 6, or a control
sequence \\let to one; NIL otherwise."
  (when (eql (command-catcode token meaning) +parameter+)
    (if (character-token-p token)
        (character-token-code token)
        (character-meaning-code meaning))))

(defun parameter-digit (token)
  "The value of TOKEN as a parameter number: a digit 1-9 of category 12."
  (and (character-catcode-p token +other+)
       (<= 49 (character-token-code token) 57)
       (- (character-token-code token) 48)))

(defun scan-parameter-text (expander)
  "The parameter part of a definition (§§474-476), up to the brace that
opens the body (consumed).  Returns the parameter text (see MACRO), the
number of parameters, the `#{' brace or NIL, and true when a `}' came
first (the definition then has an empty body)."
  (let ((text '()) (count 0))
    (loop
      (multiple-value-bind (token meaning) (get-token expander)
        (cond ((null token)
               (return (values (nreverse text) count nil nil)))
              ((brace-token-p token +begin-group+)
               (return (values (nreverse text) count nil nil)))
              ((brace-token-p token +end-group+)
               (tex-error "Missing { inserted" :span (token-span token))
               (incf (expander-align-state expander))
               (return (values (nreverse text) count nil t)))
              ((parameter-command-code token meaning)
               (let ((code (parameter-command-code token meaning))
                     (next (get-token expander)))
                 (cond ((brace-token-p next +begin-group+)
                        (push next text)
                        (return (values (nreverse text) count next nil)))
                       ((= count 9)
                        (tex-error "You already have nine parameters"
                                   :span (token-span token)))
                       (t
                        (incf count)
                        (unless (eql (parameter-digit next) count)
                          (back-token expander next)
                          (tex-error "Parameters must be numbered consecutively"
                                     :span (and next (token-span next))))
                        (push (if (character-token-p token)
                                  token
                                  (make-character-token code +parameter+
                                                        (token-span token)))
                              text)))))
              (t (push token text)))))))

(defun scan-body (expander macro-def xpand count)
  "The body of a token list after its opening brace, up to the matching
`}' (consumed) (§§477-479).  With MACRO-DEF, `#n' (n up to COUNT) becomes
the parameter number n and `##' one parameter character.  With XPAND
the input is expanded, except that what \\the gives is taken as it is.
Returns the body in order."
  (let ((body '()) (unbalance 1))
    (loop
      (multiple-value-bind (token meaning)
          (if xpand
              (loop
                (multiple-value-bind (token meaning) (get-next expander)
                  (cond ((not (expandable-p token meaning))
                         (return (values token meaning)))
                        ((primitive-named-p meaning "the")
                         (dolist (item (the-toks expander (token-span token)))
                           (push item body)))
                        (t (expand expander token meaning)))))
              (get-token expander))
        (cond ((null token) (return))
              ((brace-token-p token +begin-group+)
               (incf unbalance)
               (push token body))
              ((brace-token-p token +end-group+)
               (when (zerop (decf unbalance))
                 (return))
               (push token body))
              ((and macro-def (parameter-command-code token meaning))
               (multiple-value-bind (next next-meaning)
                   (if xpand (get-x-token expander) (get-token expander))
                 (cond ((parameter-command-code next next-meaning)
                        (push next body))
                       ((let ((n (parameter-digit next)))
                          (and n (<= n count)))
                        (push (parameter-digit next) body))
                       (t
                        (back-token expander next)
                        (tex-error "Illegal parameter number in definition of"
                                   :context (let ((cs (expander-warning-index expander)))
                                              (if cs (cs-name-text expander cs) "?"))
                                   :span (and next (token-span next)))
                        (push token body)))))
              (t (push token body)))))
    (nreverse body)))

(defun scan-toks (expander &key macro-def xpand warning-index)
  "TeX's scan_toks (§473), for WARNING-INDEX, the control sequence whose
definition or text is read (for the runaway and error messages).  With
MACRO-DEF, a definition: returns the parameter text and body MAKE-MACRO
takes (\\def, \\edef ...).  Otherwise a general text in braces, after
blanks and \\relax: returns its tokens (\\toks, \\message, \\mark ...).
XPAND expands the body as \\edef and \\message do: \\noexpand-ed tokens
stay, and what \\the gives is not expanded again."
  (let ((saved-status (expander-scanner-status expander))
        (saved-warning (expander-warning-index expander)))
    (setf (expander-scanner-status expander) (if macro-def :defining :absorbing)
          (expander-warning-index expander) warning-index)
    (unwind-protect
         (if macro-def
             (multiple-value-bind (text count hash-brace no-body)
                 (scan-parameter-text expander)
               (let ((body (if no-body '() (scan-body expander t xpand count))))
                 (values text (if hash-brace (append body (list hash-brace)) body))))
             (progn
               (scan-left-brace expander)
               (scan-body expander nil xpand 0)))
      (setf (expander-scanner-status expander) saved-status
            (expander-warning-index expander) saved-warning))))

;;; \the and the conversions

(defun the-toks (expander &optional span)
  "TeX's the_toks (§465): read an internal quantity, with expansion, and
return the tokens \\the gives: a token list as it is, a font's
identifier, or the value as a string of characters with SPAN."
  (multiple-value-bind (token meaning) (get-x-token expander)
    (multiple-value-bind (value level)
        (scan-something-internal expander token meaning :tok nil)
      (ecase level
        (:tok value)
        (:ident (list (font-identifier-token expander value span)))
        (:int (string-tokens (format nil "~D" value) span))
        (:dimen (string-tokens (format-dimen value) span))
        ((:glue :mu) (string-tokens (format-glue value) span))))))

(define-expandable "the"
  (lambda (expander token)
    ;; §367 (ins_the_toks)
    (insert-tokens expander (the-toks expander (token-span token)))))

(define-expandable "number"
  (lambda (expander token)
    ;; §§470-471
    (insert-tokens expander (string-tokens (format nil "~D" (scan-int expander))
                                           (token-span token)))))

(define-expandable "romannumeral"
  (lambda (expander token)
    (insert-tokens expander (string-tokens (format-roman (scan-int expander))
                                           (token-span token)))))

(define-expandable "fontname"
  (lambda (expander token)
    (insert-tokens expander (string-tokens (font-name-text (scan-font-ident expander))
                                           (token-span token)))))
