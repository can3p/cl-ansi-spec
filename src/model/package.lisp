;;;; src/model/package.lisp
;;;;
;;;; Phase 4, the model builder (docs/architecture.md, docs/model.md):
;;;; the node declarations (define-node and the registry), the builder
;;;; that turns the event streams of the chapter jobs into the document
;;;; model, and the resolution of its references.  Owner: 3.0; each step
;;;; of docs/plan/m3.md adds the exports of the files it owns.

(defpackage #:cl-ansi-spec/model
  (:use #:cl)
  (:import-from #:cl-ansi-spec/tex
                #:span #:make-span #:span-file #:span-start #:span-end
                #:span-line #:span-column #:current-file-name #:current-line-number)
  (:import-from #:cl-ansi-spec/expand
                #:make-job #:start-job #:main-control #:load-plain-format
                #:call-recovering-tex-errors #:tex-error-message #:tex-error-span
                #:tex-fatal-error #:tex-report #:job-output #:job-output-item
                #:job-events #:log-entry-p #:log-entry-kind #:log-entry-text
                #:log-entry-span #:node-composite #:node-children #:expander-input
                #:list-nodes #:outer-list #:flatten-nodes #:token-list-text)
  (:import-from #:cl-ansi-spec/semantic #:observe-vocabulary #:spec-vocabulary)
  (:export
   ;; The ownership table (owners.lisp)
   #:load-owners #:owners #:owner #:owner-step #:owner-file
   #:owner-vocabulary #:owner-events #:owner-why
   ;; Declarations and the registry (define-node.lisp)
   #:declaration-error
   #:*areas* #:define-node #:define-enum #:define-target-kind #:define-category
   #:node #:node-kind #:node-span #:node-field-value #:make-node #:find-field
   #:registry #:make-registry #:*registry*
   #:definition-name #:definition-area #:definition-doc
   #:node-declaration #:node-declaration-kind #:node-declaration-categories
   #:node-declaration-fields #:node-declaration-example
   #:node-declaration-example-p
   #:field #:field-name #:field-type #:field-required #:field-repeated
   #:field-doc #:field-example #:field-example-p #:field-type-p
   #:enum #:enum-values #:target-kind-declaration #:target-kind-node #:category
   #:node-kinds #:find-node-declaration #:node-fields
   #:enums #:find-enum #:target-kinds #:find-target-kind
   #:categories #:find-category #:category-kinds #:expand-kinds
   #:registry-problems #:node-problems
   #:target #:make-target #:target-p #:target-kind #:target-id
   #:undocumented-items
   ;; The builder core (build.lisp)
   #:event-type #:event-key #:event-text #:event-properties #:event-property
   #:event-span #:event-arguments #:join-spans
   #:cursor #:make-cursor #:cursor-peek #:cursor-next
   #:*problem-kinds* #:problem #:make-problem #:problem-p #:problem-kind
   #:problem-span #:problem-message #:problem-event #:problem-job
   #:build-report #:make-build-report #:build-report-problems
   #:merge-build-reports
   #:handler-table #:make-handler-table #:*handlers* #:define-handler
   #:find-handler #:handled-events
   #:container #:container-key #:container-span #:container-node
   #:container-field #:container-items #:container-contents
   #:builder #:builder-registry #:builder-expander #:builder-job
   #:next-event #:peek-event #:report-problem #:argument-text
   #:event-argument-texts #:make-builder-node #:current-container
   #:find-container #:add-item #:open-container #:close-container
   #:build-events #:build-job #:build-model #:build-fixture #:forget-job-runs
   ;; Text and fonts (build-text.lisp)
   #:*fonts* #:font-entry #:register-handler #:*layout-codes* #:*ligatures* #:font-file #:font-class
   #:convert-text #:install-text-handlers #:*plain-text-containers*
   #:plain-text-container-p
   ;; Tables and figures (build-tables.lisp)
   #:install-table-handlers
   ;; Printing nodes (print.lisp)
   #:span-sexp #:node-sexp #:print-node))
