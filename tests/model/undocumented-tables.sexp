;;;; tests/model/undocumented-tables.sexp
;;;;
;;;; The documentation ratchet of the area tables (tests/model/documentation.lisp):
;;;; one form per item UNDOCUMENTED-ITEMS lists that still lacks its
;;;; docstring or example, e.g. (:doc :field :part :title).  Empty when
;;;; the milestone closes.

(:example :node :table)
(:example :field :table :rows)
(:example :node :row)
(:example :field :row :header)
(:example :field :row :cells)
(:example :node :cell)
(:example :field :cell :content)
(:example :field :cell :columns)
(:example :node :figure)
(:example :field :figure :id)
(:example :field :figure :number)
(:example :field :figure :caption)
(:example :field :figure :content)
