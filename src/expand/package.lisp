;;;; src/expand/package.lisp
;;;;
;;;; Phase 2, the expander: TeX's semantics below typesetting
;;;; (docs/architecture.md, docs/tex-fidelity.md).  So far it holds TeX's
;;;; quantities (integers, dimensions and glue, with TeX's exact
;;;; arithmetic, units and printing), its state (meanings, registers,
;;;; parameters, codes and fonts over the reader's save stack), the
;;;; expansion of macros and expandable primitives, scanning,
;;;; conditionals, and main control: assignments, groups, modes, input,
;;;; output and messages, and the lists of nodes it builds (text, spaces,
;;;; paragraphs, glue, kerns, penalties, rules, boxes, whatsits, math,
;;;; alignments), and the formats jobs start from.

(defpackage #:cl-ansi-spec/expand
  (:use #:cl)
  (:import-from #:cl-ansi-spec/tex
                #:tex-state #:make-initex-state #:copy-tex-state #:copy-equivalents
                #:make-equivalents #:equivalent #:assign #:replace-equivalent
                #:begin-group #:end-group #:current-group-kind #:group-level
                #:save-stack-depth
                #:integer-parameter #:set-integer-parameter
                #:catcode #:set-catcode #:lccode #:set-lccode #:uccode #:set-uccode
                #:character-code #:catcode-value
                #:control-sequence #:token #:token= #:span #:token-span
                #:make-span #:span-file #:span-start #:span-end #:span-line #:span-column
                #:+begin-group+ #:+end-group+ #:+parameter+ #:+space+
                #:+letter+ #:+other+ #:+math-shift+ #:+alignment-tab+
                #:+superscript+ #:+subscript+
                #:cs-token #:cs-token-p #:cs-token-control-sequence #:make-cs-token
                #:character-token #:character-token-p #:character-token-code
                #:character-token-catcode #:make-character-token
                #:intern-control-sequence #:intern-active-character
                #:make-frozen-control-sequence
                #:control-sequence-name #:control-sequence-active-p
                #:input-stack #:make-input-stack #:input-stack-file-end-hook
                #:input-stack-u-template-end-hook #:v-template-ended-p
                #:next-token #:back-input #:push-tokens #:push-file
                #:end-current-file #:input-file-missing #:current-line-number
                #:resolve-input #:push-read-line #:reading-line-p #:end-read-line
                #:read-line-tokens)
  (:export
   ;; Integers and scaled values (arithmetic.lisp)
   #:+infinity+ #:+max-dimen+ #:+unity+
   #:tex-integer #:scaled
   #:x-over-n #:xn-over-d #:nx-plus-y #:mult-integers
   #:integer-advance #:integer-multiply #:integer-divide
   #:dimen-advance #:dimen-multiply #:dimen-divide
   #:round-decimals
   ;; Units (units.lisp)
   #:physical-units #:unit-conversion
   #:apply-true-magnification #:convert-physical-unit #:scale-by-unit
   #:attach-sign #:math-unit #:mu-multiply
   ;; Glue (glue.lisp)
   #:glue #:make-glue #:glue-p #:glue-width #:glue-stretch #:glue-shrink
   #:glue-stretch-order #:glue-shrink-order #:glue-mu-p #:glue-order
   #:glue=
   #:glue-advance #:glue-multiply #:glue-divide #:glue-negate
   #:mu-glue-to-glue
   ;; Printing (print.lisp)
   #:format-scaled #:format-dimen #:format-glue
   ;; Fonts (font.lisp)
   #:tex-font #:tex-font-p #:make-tex-font #:tex-font-file #:tex-font-size
   #:tex-font-identifier #:tex-font-hyphen-char #:tex-font-skew-char
   #:normalize-font-size #:font-dimen #:set-font-dimen
   ;; Meanings (meaning.lisp)
   #:meaning #:meaning-p #:meaning=
   #:macro #:macro-p #:make-macro #:macro-parameter-text #:macro-body
   #:macro-long-p #:macro-outer-p
   #:primitive #:primitive-p #:make-primitive #:primitive-name
   #:primitive-operation #:primitive-expandable-p
   #:character-meaning #:character-meaning-p #:make-character-meaning
   #:character-meaning-code #:character-meaning-catcode
   #:shorthand #:shorthand-p #:make-shorthand #:shorthand-kind
   #:shorthand-value
   ;; Parameters (parameters.lisp)
   #:parameter-names #:parameter-kind #:initex-integer-parameters
   #:initex-code
   ;; The expander state (state.lisp)
   #:expander-state #:make-expander-state #:es-tex #:es-null-font
   #:register-kind #:register-number #:code-kind
   #:effective-global
   #:set-meaning #:register #:set-register #:replace-register
   #:parameter #:set-parameter
   #:code #:set-code #:current-font #:set-current-font
   #:family-font #:set-family-font #:par-shape #:set-par-shape
   #:load-font
   ;; Errors (errors.lisp)
   #:tex-error #:tex-fatal-error #:tex-error-message #:tex-error-context
   #:tex-error-span #:recover #:call-recovering-tex-errors
   #:tex-report #:tex-report-message #:tex-report-context
   ;; Primitives (primitives.lisp)
   #:define-primitive #:find-primitive #:install-primitives
   #:tex82-command-names #:tex82-expandable-names
   ;; The expander (expander.lisp, show.lisp, macro.lisp, expandable.lisp)
   #:expander #:make-expander #:expander-state #:expander-input
   #:expander-job-name #:expander-scanner-status #:expander-align-state
   #:expander-marks #:scanner-status
   #:get-next #:get-token #:get-x-token #:back-token #:insert-tokens
   #:expand #:expandable-p #:frozen-control-sequence #:dont-expand-meaning
   #:cs-name-text #:token-list-text #:meaning-text #:string-tokens
   #:current-list
   ;; The nest and the page (nest.lisp)
   #:+ignore-depth+ #:mode #:mode-kind #:last-node-kind
   #:list-state #:make-list-state #:list-state-p #:list-state-mode
   #:list-state-prev-depth #:list-state-space-factor #:list-state-prev-graf
   #:list-state-last-node #:list-state-contents #:list-state-clang
   #:list-state-span
   ;; Nodes (nodes.lisp, list-commands.lisp)
   #:node #:node-p #:make-node #:node-kind #:node-properties #:node-value
   #:node-children #:node-composite #:node-span #:node-end-span #:node-via
   #:node-last-item #:list-nodes #:outer-list #:append-node #:remove-last-node
   #:flatten-nodes #:font-style-name
   #:page-state #:page-state-so-far #:page-state-contents
   #:page-state-output-active #:page-state-last-penalty
   #:page-state-last-kern #:page-state-last-glue #:page-state-dead-cycles
   #:page-state-insert-penalties
   #:expander-nest #:expander-page #:expander-mag-set #:expander-last-badness
   ;; Scanning (scan.lisp, internal.lisp, dimen-scan.lisp, toks.lisp)
   #:scan-keyword #:scan-optional-equals #:scan-optional-space
   #:scan-left-brace #:get-x-nonblank #:get-x-nonblank-nonrelax
   #:scan-int #:scan-eight-bit-int #:scan-char-num #:scan-four-bit-int
   #:scan-fifteen-bit-int #:scan-twenty-seven-bit-int
   #:internal-command-p #:scan-something-internal
   #:box-dimension #:scan-font-ident #:find-font-dimen #:font-identifier-token
   #:prepare-mag #:scan-dimen #:scan-glue
   #:scan-toks #:the-toks
   #:format-roman #:font-name-text
   #:tex-font-parameter-count
   ;; Conditionals (conditionals.lisp)
   #:conditional #:conditional-p #:conditional-kind #:conditional-line
   #:conditional-limit #:expander-conditionals #:expander-skip-line
   #:expander-read-streams #:if-limit #:if-test-names #:pass-text #:box-kind
   ;; Main control (commands.lisp, groups.lisp, modes.lisp, boxes.lisp,
   ;; prefixed.lisp, assignments.lisp, main-control.lisp)
   #:command-disposition #:event-command-names #:input-output-command-names
   #:group-code #:group-record #:group-record-code #:group-record-line
   #:current-group #:current-group-code
   #:tex-box #:tex-box-p #:make-tex-box #:tex-box-kind #:tex-box-spec
   #:tex-box-contents #:tex-box-command
   #:expander-after-token #:expander-interaction #:expander-patterns
   #:expander-hyphenation-exceptions #:expander-trie-not-ready
   #:expander-ended
   #:main-control
   ;; Input, output and messages (log.lisp, messages.lisp, streams.lisp)
   #:log-entry #:log-entry-p #:log-entry-kind #:log-entry-text
   #:log-entry-stream #:log-entry-help #:log-entry-span
   #:job-output #:job-output-item #:job-log #:job-events
   #:expander-write-streams #:expander-set-box-allowed
   #:read-toks
   ;; Formats and jobs (format.lisp)
   #:tex-format #:tex-format-p #:load-plain-format #:format-error
   #:format-error-detail #:make-job #:start-job))
