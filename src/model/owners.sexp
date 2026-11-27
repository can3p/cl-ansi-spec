;;;; src/model/owners.sexp
;;;;
;;;; The ownership table of the model builder (docs/plan/m3.md, step 3.0;
;;;; docs/model.md, "Building"), read by LOAD-OWNERS
;;;; (src/model/owners.lisp).  Each form
;;;;   (:owner step :file "build-….lisp" :vocabulary (keys…) :events (kinds…)
;;;;    :why "…")
;;;; gives a builder step the vocabulary keys (src/semantic/vocabulary.sexp)
;;;; and the event kinds (docs/events.md) whose handlers it writes, in that
;;;; file of src/model/.  Every key and every kind has exactly one owner
;;;; (tests/model/owners.lisp), so nothing falls to the whole-spec step
;;;; (3.16) by default.  A closing key (:endcom …) goes with the key it
;;;; closes.

(:owner "3.3" :file "build.lisp"
 :events (:diagnostic)
 :why "A recovered TeX error or an unknown construct goes into the build report.")

(:owner "3.8" :file "build-structure.lisp"
 :vocabulary (:chapter :simple-chapter :section :dictionary :subsection
              :subsubsection :subsubsubsection :subsubsubsubsection
              :define-chapter :define-section)
 :events (:write)
 :why "Chapters and sections nested by level, their labels, and the numbers
checked against the :write of \\DefineSection; every other \\write (index
and table-of-contents data the model rebuilds from events) is dropped by
this handler, by the rule 3.10 lists.")

(:owner "3.9" :file "build-entries.lisp"
 :vocabulary (:com :endcom :label :label-confidence
              :defun :defun-no-return :defmac :defmac-no-return :defspec
              :defspec-no-return :defgen :defmeth :defsetf :defsetf-multi
              :defvar :defcon :deftype :defun-multi :defun-multi-accessor
              :entry)
 :why "Dictionary entries, their parts from one \\label to the next, and their
signatures; an :entry mark is a name of a -multi signature.")

(:owner "3.10" :file "build-blocks.lisp"
 :vocabulary (:code :endcode :list :endlist :item :item-2 :item-3
              :editor-note :reviewer-note)
 :events (:paragraph :indent :glue :kern :penalty :rule :language :box
          :leaders :tex-mark :insert :vadjust :special :shipout
          :openout :closeout)
 :why "Blocks, and the presentational events between and inside them, each
dropped or kept by a rule this step lists with its reason.")

(:owner "3.11" :file "build-tables.lisp"
 :vocabulary (:figure :caption :next-figure :define-figure)
 :events (:alignment :row :cell :no-align)
 :why "Alignments as tables, figures with their captions and numbers.")

(:owner "3.12" :file "build-text.lisp"
 :events (:text :space :discretionary :pre-break :post-break :no-break
          :accent)
 :why "Characters to Unicode text by the font's ligatures and codes; a
discretionary becomes its no-break text, an accent a precomposed
character.")

(:owner "3.13" :file "build-inlines.lisp"
 :vocabulary (:term :new-term :param :emphasis :strong :inline-code
              :clref :funref :macref :typeref :varref :conref :declref
              :specref :packref :loopref :keyref :kwd :ttref :misc
              :secref :figref :this-section
              :evaluates-to :may-evaluate-to :does-not-evaluate-to
              :equivalent :output :input
              :cite :index-ref :index-keyref :index-code :index-keyword
              :index-text :index-term :index-example :index-package
              :issue :endissue
              :metavariable :format-directive :lambda-list-keyword)
 :why "Inlines by meaning; references with their key text, unresolved
(3.17-3.19 resolve them); issues as anchors.  :misc (\\misc, \\miscref)
is a reference wrapper and :input (\\IN) example notation, beside
:output (\\OUT).")

(:owner "3.14" :file "build-glossary.lisp"
 :vocabulary (:glossary-letter :glossary-entry :glossary-example :sense
              :part-of-speech :pronunciation :usage)
 :why "Glossary entries from one \\gentry to the next, with their senses.")

(:owner "3.15" :file "build-bnf.lisp"
 :vocabulary (:bnf-rule :bnf-break :optional :end-optional :zero-or-more
              :one-or-more :interleave :end-interleave :bracketed
              :end-bracketed :parenthesized :end-parenthesized :group
              :end-group :required :repeat-previous :caret :angle
              :indirection)
 :why "BNF rules and the notation of syntax descriptions.")

(:owner "3.15m" :file "build-math.lisp"
 :events (:math :eqno :noad :nucleus :superscript :subscript :math-char
          :fraction :numerator :denominator :left :right :math-style
          :math-choice :choice)
 :why "Math lists as a small tree of their own, characters to Unicode by
font family.")
