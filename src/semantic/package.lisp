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
                #:token-span)
  (:import-from #:cl-ansi-spec/expand
                #:expander-state #:es-tex #:meaning #:macro-p #:macro-body
                #:current-list #:node-kind #:node-properties #:marker-p #:append-marker
                #:expander-call-observer #:expander-level-end-observer
                #:expander-definition-observer #:expander-append-observer)
  (:export
   ;; Entries and vocabularies (vocabulary.lisp)
   #:entry #:make-entry #:entry-name #:entry-key #:entry-kind
   #:entry-placement #:entry-closes #:entry-handler #:entry-why
   #:entry-mode
   #:vocabulary #:make-vocabulary #:vocabulary-entries #:find-entry
   ;; Observing a job (observe.lisp)
   #:observer #:observe-vocabulary #:observer-vocabulary
   #:observer-reports #:emit-event
   #:report #:report-kind #:report-name #:report-span #:report-previous-span
   #:report-previous-name))
