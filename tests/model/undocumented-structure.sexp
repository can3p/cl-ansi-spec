;;;; tests/model/undocumented-structure.sexp
;;;;
;;;; The documentation ratchet of the area structure (tests/model/documentation.lisp):
;;;; one form per item UNDOCUMENTED-ITEMS lists that still lacks its
;;;; docstring or example, e.g. (:doc :field :part :title).  Empty when
;;;; the milestone closes.

(:example :node :document)
(:example :field :document :version)
(:example :field :document :front-matter)
(:example :field :document :chapters)
(:example :node :chapter)
(:example :field :chapter :id)
(:example :field :chapter :number)
(:example :field :chapter :title)
(:example :field :chapter :children)
(:example :node :section)
(:example :field :section :id)
(:example :field :section :number)
(:example :field :section :level)
(:example :field :section :dictionary)
(:example :field :section :title)
(:example :field :section :children)
