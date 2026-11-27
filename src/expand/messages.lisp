;;;; src/expand/messages.lisp
;;;;
;;;; Main control's mode-independent commands of TeX: The Program,
;;;; §§1279-1298: \message and \errmessage (issue_message), \uppercase and
;;;; \lowercase (shift_case), \show and \showthe (show_whatever; \showbox
;;;; and \showlists show lists: show-lists.lisp).  What they print goes to
;;;; the job's log (log.lisp) as one string: TeX's line breaking of the
;;;; terminal and \newlinechar are not kept.

(in-package #:cl-ansi-spec/expand)

(define-command ("message" "errmessage") (expander token meaning)
  ;; issue_message (§1279): the text is expanded as for \edef.
  (let* ((tokens (scan-toks expander :xpand t
                                     :warning-index (cs-token-control-sequence token)))
         (text (token-list-text expander tokens))
         (span (token-span token)))
    (if (string= name "message")
        (log-message expander :message text :span span)
        ;; §1283: an error whose help is \errhelp when it is not empty.
        (let ((help (parameter (expander-state expander) :errhelp)))
          (log-message expander :errmessage text
                       :help (and help (token-list-text expander help))
                       :span span)
          (tex-error text :span span)))))

(defun shift-case-token (expander token kind)
  "TOKEN with its character code replaced by its KIND code (:UCCODE or
:LCCODE) when that is not 0 (§1289): a character token keeps its
category, an active character becomes the active character of the new
code; other control sequences stay as they are."
  (let ((state (expander-state expander)))
    (flet ((shifted (code) (let ((new (code state kind code)))
                             (and (/= new 0) new))))
      (cond
        ((character-token-p token)
         (let ((new (shifted (character-token-code token))))
           (if new
               (make-character-token new (character-token-catcode token)
                                     (token-span token))
               token)))
        ((control-sequence-active-p (cs-token-control-sequence token))
         (let ((new (shifted (char-code (char (control-sequence-name
                                               (cs-token-control-sequence token))
                                              0)))))
           (if new
               (make-cs-token (intern-active-character (expander-tex expander) new)
                              (token-span token))
               token)))
        (t token)))))

(define-command ("uppercase" "lowercase") (expander token meaning)
  ;; shift_case (§1288): the shifted text is read next, as backed-up input.
  (let ((kind (if (string= name "uppercase") :uccode :lccode))
        (tokens (scan-toks expander :warning-index (cs-token-control-sequence token))))
    (when tokens
      (push-tokens (expander-input expander)
                   (mapcar (lambda (token) (shift-case-token expander token kind))
                           tokens)
                   :backed-up))))

(define-command "show" (expander token meaning)
  ;; §1294: the next token, unexpanded, and its meaning.
  (multiple-value-bind (shown shown-meaning) (get-token expander)
    (when shown
      (log-message expander :show
                   (if (cs-token-p shown)
                       (concatenate 'string
                                    (cs-name-text expander (cs-token-control-sequence shown))
                                    "=" (meaning-text expander shown shown-meaning))
                       (meaning-text expander shown shown-meaning))
                   :span (token-span token)))))

(define-command "showthe" (expander token meaning)
  ;; §1297
  (log-message expander :show
               (token-list-text expander (the-toks expander (token-span token)))
               :span (token-span token)))
