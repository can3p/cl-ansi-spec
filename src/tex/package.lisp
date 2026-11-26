;;;; src/tex/package.lisp
;;;;
;;;; The TeX machinery below expansion: category codes and other
;;;; equivalents with TeX's grouping, tokens, line buffers, the input
;;;; scanner (TeXbook chapters 7-8) and TeX's input stack.

(defpackage #:cl-ansi-spec/tex
  (:use #:cl)
  (:import-from #:cl-ansi-spec #:read-spec-file
                #:find-input-file #:source-search-path)
  (:export
   ;; Category codes
   #:+escape+ #:+begin-group+ #:+end-group+ #:+math-shift+ #:+alignment-tab+
   #:+end-of-line+ #:+parameter+ #:+superscript+ #:+subscript+ #:+ignored+
   #:+space+ #:+letter+ #:+other+ #:+active+ #:+comment+ #:+invalid+
   #:catcode-name #:catcode-value #:character-code
   ;; State: equivalents and the save stack
   #:tex-state #:make-initex-state #:make-plain-state #:apply-plain-catcodes
   #:catcode #:set-catcode #:lccode #:set-lccode #:uccode #:set-uccode
   #:endlinechar #:set-endlinechar #:integer-parameter #:set-integer-parameter
   #:equivalents #:make-equivalents #:equivalent #:assign
   #:group-level #:begin-group #:end-group #:current-group-kind #:save-stack-depth
   #:group-underflow
   ;; Spans, control sequences and tokens
   #:span #:make-span #:span-file #:span-start #:span-end #:span-line
   #:span-column
   #:control-sequence #:control-sequence-name #:control-sequence-active-p
   #:intern-control-sequence #:intern-active-character
   #:make-frozen-control-sequence
   #:token #:token-span #:token= #:token-text #:character-text
   #:character-token #:make-character-token #:character-token-p
   #:character-token-code #:character-token-catcode
   #:cs-token #:make-cs-token #:cs-token-p #:cs-token-control-sequence
   ;; Lines and the scanner
   #:line-source #:make-line-source #:open-line-source #:line-source-name
   #:invalid-character #:invalid-character-code #:invalid-character-span
   ;; The input stack
   #:input-stack #:make-input-stack #:directory-resolver
   #:input-stack-file-end-hook #:end-current-file
   #:push-source #:push-file #:push-tokens #:back-input
   #:next-token #:peek-token #:input-depth #:current-file-name
   #:current-line-number
   #:input-file-missing #:input-file-missing-name))
