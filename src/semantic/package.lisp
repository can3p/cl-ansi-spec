;;;; src/semantic/package.lisp
;;;;
;;;; Phase 3, the semantic layer (docs/architecture.md,
;;;; docs/vocabulary.md): a vocabulary of the macros that carry meaning,
;;;; and the observer that turns their calls into the markers of the
;;;; event stream (docs/events.md), through the expander's observers.

(defpackage #:cl-ansi-spec/semantic
  (:use #:cl)
  (:import-from #:cl-ansi-spec/tex
                #:intern-control-sequence #:control-sequence-name
                #:token #:token-span #:cs-token-control-sequence)
  (:import-from #:cl-ansi-spec/expand
                #:expander-state #:es-tex #:meaning #:macro-p #:macro-body
                #:current-list #:expander-nest #:list-state-mode #:mode-kind
                #:node-kind #:node-properties #:marker-p #:append-marker
                #:expander-call-observer #:expander-level-end-observer
                #:expander-definition-observer #:expander-append-observer
                #:insert-tokens)
  (:export
   ;; Entries and vocabularies (vocabulary.lisp)
   #:entry #:make-entry #:entry-name #:entry-key #:entry-kind
   #:entry-placement #:entry-closes #:entry-handler #:entry-local #:entry-why
   #:entry-mode
   #:vocabulary #:make-vocabulary #:vocabulary-entries #:vocabulary-classes
   #:find-entry
   #:macro-class #:make-macro-class #:macro-class-kind #:macro-class-names
   #:macro-class-files #:macro-class-why #:classify-macro
   #:load-vocabulary #:spec-vocabulary
   ;; Handlers (handlers.lisp)
   #:hidden-note
   ;; Observing a job (observe.lisp)
   #:observer #:observe-vocabulary #:observer-vocabulary
   #:observer-reports #:observer-call-count #:emit-event
   #:report #:report-kind #:report-name #:report-span #:report-previous-span
   #:report-previous-name))
