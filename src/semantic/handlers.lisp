;;;; src/semantic/handlers.lisp
;;;;
;;;; Replace handlers of the spec's vocabulary (docs/vocabulary.md,
;;;; "Replace"): each stands for a call whose expansion would hide
;;;; content, emits the events itself, and does what the macro must
;;;; still do.  The data file names them by symbol.

(in-package #:cl-ansi-spec/semantic)

(defun named-meaning (expander name)
  "The meaning of the control sequence NAME in EXPANDER's job."
  (let ((state (expander-state expander)))
    (meaning state (intern-control-sequence (es-tex state) name))))

(defun macro-expansion (expander token arguments)
  "The body of the macro TOKEN means, ARGUMENTS substituted: what TeX
reads for the call."
  (let ((macro (meaning (expander-state expander) (cs-token-control-sequence token))))
    (loop for element in (macro-body macro)
          if (integerp element) append (nth (1- element) arguments)
          else collect element)))

(defun hidden-note (observer expander entry token arguments)
  "\\editornote and \\reviewer (setup-document.tex:419-420): a :MARK
keyed as ENTRY with the note's ARGUMENTS and :HIDDEN, true when
\\ifeditornotes (set in setup-options.tex) is \\iffalse, so that the
note is not typeset; then the macro's body is read, as TeX reads it."
  (emit-event observer expander
              (list :mark (entry-key entry) :arguments arguments
                    :hidden (eq (named-meaning expander "ifeditornotes")
                                (named-meaning expander "iffalse")))
              :span (token-span token))
  (insert-tokens expander (macro-expansion expander token arguments)))
