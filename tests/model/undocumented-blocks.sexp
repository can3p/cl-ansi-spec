;;;; tests/model/undocumented-blocks.sexp
;;;;
;;;; The documentation ratchet of the area blocks (tests/model/documentation.lisp):
;;;; one form per item UNDOCUMENTED-ITEMS lists that still lacks its
;;;; docstring or example, e.g. (:doc :field :part :title).  Empty when
;;;; the milestone closes.

(:example :node :paragraph)
(:example :field :paragraph :content)
(:example :node :code-block)
(:example :field :code-block :lines)
(:example :node :code-line)
(:example :field :code-line :content)
(:example :node :item-list)
(:example :field :item-list :items)
(:example :node :item)
(:example :field :item :label)
(:example :field :item :content)
(:example :node :editor-note)
(:example :field :editor-note :content)
(:example :field :editor-note :hidden)
(:example :node :reviewer-note)
(:example :field :reviewer-note :content)
(:example :field :reviewer-note :hidden)
