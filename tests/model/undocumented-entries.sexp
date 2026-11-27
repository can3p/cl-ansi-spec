;;;; tests/model/undocumented-entries.sexp
;;;;
;;;; The documentation ratchet of the area entries (tests/model/documentation.lisp):
;;;; one form per item UNDOCUMENTED-ITEMS lists that still lacks its
;;;; docstring or example, e.g. (:doc :field :part :title).  Empty when
;;;; the milestone closes.

(:example :node :dictionary-entry)
(:example :field :dictionary-entry :id)
(:example :field :dictionary-entry :names)
(:example :field :dictionary-entry :entry-kind)
(:example :field :dictionary-entry :parts)
(:example :node :part)
(:example :field :part :title)
(:example :field :part :none)
(:example :field :part :content)
(:example :node :operator-signature)
(:example :field :operator-signature :operator)
(:example :field :operator-signature :names)
(:example :field :operator-signature :lambda-list)
(:example :field :operator-signature :values)
(:example :field :operator-signature :no-return)
(:example :node :setf-signature)
(:example :field :setf-signature :names)
(:example :field :setf-signature :lambda-list)
(:example :field :setf-signature :new-value)
(:example :node :variable-signature)
(:example :field :variable-signature :name)
(:example :field :variable-signature :constant)
(:example :node :type-signature)
(:example :field :type-signature :name)
(:example :field :type-signature :syntax)
