;;;; src/inventory/package.lisp
;;;;
;;;; The vocabulary inventory: a survey of the macros the sources define
;;;; and use, read with the reader alone (no expansion).  A development
;;;; aid that seeds the semantic vocabulary and its invariants
;;;; (docs/vocabulary.md, "Choosing entries"); not a phase of the pipeline.

(defpackage #:cl-ansi-spec/inventory
  (:use #:cl)
  (:import-from #:cl-ansi-spec #:spec-files #:source-search-path #:chapter-jobs)
  (:import-from #:cl-ansi-spec/tex
                #:+begin-group+ #:+end-group+ #:+escape+ #:+letter+ #:+comment+
                #:+space+ #:+other+ #:+active+ #:+parameter+
                #:make-plain-state #:catcode #:set-catcode
                #:begin-group #:end-group #:current-group-kind #:group-level
                #:token-span #:token-text #:span-file #:span-line
                #:character-token-p #:character-token-code
                #:character-token-catcode
                #:cs-token-p #:cs-token-control-sequence #:control-sequence-name
                #:control-sequence-active-p
                #:line-source-name #:directory-resolver
                #:make-input-stack #:push-file #:push-tokens #:next-token #:back-input
                #:input-file-missing #:invalid-character)
  (:export
   ;; Records
   #:definition #:definition-name #:definition-kind #:definition-file
   #:definition-line #:definition-depth #:definition-global-p
   #:definition-long-p #:definition-parent #:definition-alias
   #:definition-value #:definition-uncertain-p
   #:definition-arity #:definition-input-parameters
   #:occurrence #:occurrence-name #:occurrence-file #:occurrence-line
   #:occurrence-context #:occurrence-uncertain-p
   #:input-record #:input-record-file #:input-record-line
   #:input-record-target #:input-record-status #:input-record-macro
   #:catcode-note #:catcode-note-file #:catcode-note-line
   #:catcode-note-code #:catcode-note-value #:catcode-note-how
   ;; Surveys
   #:survey #:survey-job #:survey-job-name #:survey-files #:survey-definitions
   #:survey-occurrences #:survey-inputs #:survey-catcode-notes
   #:survey-uncertain-lines
   #:merge-surveys #:count-table #:name-counts #:name-class))
