;;;; src/expand/macro.lisp
;;;;
;;;; Macro calls (TeX: The Program, §§389-400; TeXbook, chapter 20): the
;;;; parameter text is matched against the input, the arguments are
;;;; substituted into the body, and the result is read next.  Matching
;;;; follows TeX token by token, including its recovery after a partial
;;;; match of a delimiter (§397), brace stripping (§400), \par in a
;;;; macro that is not \long (§396) and an extra `}' (§395).
;;;;
;;;; Arguments keep the tokens actually read, with their spans; TeX keeps
;;;; equal tokens from the parameter text after a partial match, which no
;;;; TeX program can tell apart.

(in-package #:cl-ansi-spec/expand)

(defun split-parameter-text (parameter-text)
  "The delimiters of PARAMETER-TEXT: the tokens before the first match
token, and one vector of delimiter tokens per parameter (empty for an
undelimited one)."
  (let ((prefix '()) (delimiters '()) (current nil))
    (dolist (token parameter-text)
      (cond ((character-catcode-p token +parameter+)
             (when current (push (coerce (nreverse current) 'vector) delimiters))
             (setf current (list :parameter)))
            (current (push token current))
            (t (push token prefix))))
    (when current (push (coerce (nreverse current) 'vector) delimiters))
    (values (nreverse prefix)
            (mapcar (lambda (v) (subseq v 1)) (nreverse delimiters)))))

(defun macro-call (expander token macro)
  "Expand MACRO, the meaning of TOKEN: match its parameter text, then read
its body with the arguments substituted.  A failed match drops the call
as TeX does."
  (let ((saved-status (expander-scanner-status expander))
        (saved-warning (expander-warning-index expander)))
    (setf (expander-warning-index expander) (cs-token-control-sequence token))
    (unwind-protect
         (multiple-value-bind (arguments ok) (match-parameters expander macro)
           (when ok
             ;; A tail call ends its caller's body before it begins (§390).
             (pop-exhausted-token-lists (expander-input expander))
             (multiple-value-bind (action tag) (observe-call expander token macro arguments)
               (unless (eq action :replace)
                 (let ((body (substitute-arguments (macro-body macro) arguments)))
                   (cond (body
                          (push-tokens (expander-input expander) body :macro tag))
                         (tag
                          ;; An empty body ends at once.
                          (end-observed-body expander tag))))))))
      (setf (expander-scanner-status expander) saved-status
            (expander-warning-index expander) saved-warning))))

(defun observe-call (expander token macro arguments)
  "Call EXPANDER's call observer, if any, on a matched call of MACRO by
TOKEN with ARGUMENTS; return its action (NIL or :REPLACE) and tag."
  (let ((observer (expander-call-observer expander)))
    (if observer
        (multiple-value-bind (action tag)
            (funcall observer expander token macro arguments)
          (check-type action (member nil :replace))
          (when (and (eq action :replace) tag)
            (error "A replaced call has no body to tag."))
          (values action tag))
        (values nil nil))))

(defun end-observed-body (expander tag)
  "Tell EXPANDER's level-end observer, if any, that the body of the call
tagged TAG has ended."
  (let ((observer (expander-level-end-observer expander)))
    (when observer
      (funcall observer expander tag))))

(defun substitute-arguments (body arguments)
  "BODY with each parameter number replaced by its argument's tokens."
  (loop for element in body
        if (integerp element) append (nth (1- element) arguments)
        else collect element))

(defun match-parameters (expander macro)
  "Scan the arguments of MACRO.  Returns the list of arguments (lists of
tokens) and true, or NIL and NIL when the call is abandoned."
  (multiple-value-bind (prefix delimiters)
      (split-parameter-text (macro-parameter-text macro))
    (when (or prefix delimiters)
      (setf (expander-scanner-status expander) :matching
            (expander-long-state expander) (if (macro-long-p macro) :long :call)))
    (dolist (delimiter prefix)
      (let ((token (get-token expander)))
        (cond ((null token) (return-from match-parameters (values nil nil)))
              ((token= token delimiter)
               (when (character-catcode-p token +begin-group+)
                 (decf (expander-align-state expander))))
              (t
               (tex-error "Use of macro doesn't match its definition"
                          :context (cs-name-text expander
                                                 (expander-warning-index expander))
                          :span (token-span token))
               (return-from match-parameters (values nil nil))))))
    (let ((arguments '()))
      (dolist (delimiter delimiters (values (nreverse arguments) t))
        (multiple-value-bind (argument ok) (scan-argument expander delimiter)
          (unless ok
            (return (values nil nil)))
          (push argument arguments))))))

(defun runaway-abort (expander token unbalance)
  "TeX's `Report a runaway argument and abort' (§396) on the \\par TOKEN:
an error, unless a runaway was reported already, and the \\par is read
again.  Returns NIL and NIL, the result of an abandoned match."
  (decf (expander-align-state expander) unbalance)
  (when (eq (expander-long-state expander) :call)
    (back-token expander token)
    (tex-error "Paragraph ended before macro was complete"
               :context (cs-name-text expander (expander-warning-index expander))
               :span (token-span token)))
  (values nil nil))

(defun scan-group (expander open)
  "Read a balanced group after the begin-group token OPEN (§399).
Returns its tokens, braces included, and true; or NIL and NIL after a
runaway."
  (let ((tokens (list open))
        (unbalance 1))
    (loop
      (let ((token (get-token expander)))
        (cond ((null token) (return (values nil nil)))
              ((and (par-token-p expander token)
                    (not (eq (expander-long-state expander) :long)))
               (return (runaway-abort expander token unbalance))))
        (push token tokens)
        (cond ((character-catcode-p token +begin-group+) (incf unbalance))
              ((character-catcode-p token +end-group+)
               (when (zerop (decf unbalance))
                 (return (values (nreverse tokens) t)))))))))

(defun rematch-delimiter (delimiter matched token)
  "After TOKEN failed to continue a partial match of DELIMITER (MATCHED
holds the input tokens matching its first elements), TeX moves matched
tokens one by one into the argument and retries (§397).  Returns the
number of tokens moved and the new matched tokens (TOKEN included), or
all of MATCHED and NIL when no shift matches."
  (let ((j (length matched)))
    (loop for i from 0 below j
          when (and (loop for u from (1+ i) below j
                          for v from 0
                          always (token= (aref delimiter u) (aref delimiter v)))
                    (token= token (aref delimiter (- j 1 i))))
            do (return-from rematch-delimiter
                 (values (1+ i) (append (subseq matched (1+ i)) (list token)))))
    (values j nil)))

(defun scan-argument (expander delimiter)
  "Scan one argument ending with DELIMITER (a vector of tokens, empty for
an undelimited parameter), as §§392-400 do.  Returns its tokens and true,
or NIL and NIL when the call is abandoned."
  (let ((k (length delimiter))
        (argument '())                  ; reversed
        (items 0)                       ; TeX's m
        (matched '()))                  ; input tokens matching a prefix
    (flet ((store (token) (push token argument)))
      (loop
        (let ((token (get-token expander)))
          (when (null token)
            (return (values nil nil)))
          (block next-token
            ;; Advance the match of the delimiter.
            (when (and (< (length matched) k)
                       (token= token (aref delimiter (length matched))))
              (setf matched (append matched (list token)))
              (when (= (length matched) k)
                (when (character-catcode-p token +begin-group+)
                  (decf (expander-align-state expander)))
                (return (values (finish-argument argument items) t)))
              (return-from next-token))
            ;; A partial match failed: contribute the matched tokens.
            (when matched
              (multiple-value-bind (moved rematched)
                  (rematch-delimiter delimiter matched token)
                (dolist (moved-token (subseq matched 0 moved))
                  (store moved-token)
                  (incf items))
                (setf matched rematched)
                (when rematched
                  (return-from next-token))))
            (cond ((and (par-token-p expander token)
                        (not (eq (expander-long-state expander) :long)))
                   (return (runaway-abort expander token 0)))
                  ((character-catcode-p token +begin-group+)
                   (multiple-value-bind (group ok) (scan-group expander token)
                     (unless ok
                       (return (values nil nil)))
                     (dolist (token group) (store token))))
                  ((character-catcode-p token +end-group+)
                   (extra-right-brace expander token)
                   (return-from next-token))
                  ((and (zerop k) (character-catcode-p token +space+)
                        (= (character-token-code token) 32))
                   (return-from next-token))
                  (t (store token)))
            (incf items)
            (when (zerop k)
              (return (values (finish-argument argument items) t)))))))))

(defun extra-right-brace (expander token)
  "TeX's `Report an extra right brace' (§395): the `}' TOKEN is put back
and \\par inserted before it, which ends the call as a runaway."
  (back-token expander token)
  (incf (expander-align-state expander))
  (setf (expander-long-state expander) :call)
  (back-token expander (named-token expander "par" (token-span token)))
  (tex-error "Argument of macro has an extra }"
             :context (cs-name-text expander (expander-warning-index expander))
             :span (token-span token)))

(defun finish-argument (reversed items)
  "The argument from its REVERSED tokens and its count of ITEMS (TeX's m):
a single group loses its braces (§400)."
  (if (and (= items 1) reversed
           (or (character-catcode-p (first reversed) +end-group+)
               (character-catcode-p (first reversed) +begin-group+)))
      (rest (butlast (reverse reversed)))
      (reverse reversed)))
