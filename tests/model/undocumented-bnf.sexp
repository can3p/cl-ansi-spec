;;;; tests/model/undocumented-bnf.sexp
;;;;
;;;; The documentation ratchet of the area bnf (tests/model/documentation.lisp):
;;;; one form per item UNDOCUMENTED-ITEMS lists that still lacks its
;;;; docstring or example, e.g. (:doc :field :part :title).  Empty when
;;;; the milestone closes.

(:example :node :bnf-rule)
(:example :field :bnf-rule :name)
(:example :field :bnf-rule :definition)
(:example :node :bnf-break)
(:example :node :bnf-optional)
(:example :field :bnf-optional :content)
(:example :node :bnf-zero-or-more)
(:example :field :bnf-zero-or-more :content)
(:example :node :bnf-one-or-more)
(:example :field :bnf-one-or-more :content)
(:example :node :bnf-repeat-previous)
(:example :node :bnf-group)
(:example :field :bnf-group :content)
(:example :node :bnf-parenthesized)
(:example :field :bnf-parenthesized :content)
(:example :node :bnf-bracketed)
(:example :field :bnf-bracketed :content)
(:example :node :bnf-interleave)
(:example :field :bnf-interleave :content)
(:example :node :bnf-required)
(:example :field :bnf-required :content)
(:example :node :bnf-indirection)
(:example :field :bnf-indirection :name)
(:example :node :bnf-caret)
(:example :node :angle-name)
(:example :field :angle-name :name)
