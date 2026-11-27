;;;; tests/model/undocumented-math.sexp
;;;;
;;;; The documentation ratchet of the area math (tests/model/documentation.lisp):
;;;; one form per item UNDOCUMENTED-ITEMS lists that still lacks its
;;;; docstring or example, e.g. (:doc :field :part :title).  Empty when
;;;; the milestone closes.

(:example :node :math)
(:example :field :math :display)
(:example :field :math :content)
(:example :field :math :equation-number)
(:example :node :math-noad)
(:example :field :math-noad :class)
(:example :field :math-noad :limits)
(:example :field :math-noad :delimiter)
(:example :field :math-noad :nucleus)
(:example :field :math-noad :superscript)
(:example :field :math-noad :subscript)
(:example :node :math-char)
(:example :field :math-char :text)
(:example :node :math-fraction)
(:example :field :math-fraction :numerator)
(:example :field :math-fraction :denominator)
(:example :field :math-fraction :no-rule)
(:example :field :math-fraction :left-delimiter)
(:example :field :math-fraction :right-delimiter)
(:example :node :math-delimiter)
(:example :field :math-delimiter :right)
(:example :field :math-delimiter :text)
(:example :node :math-style-change)
(:example :field :math-style-change :style)
(:example :node :math-choice)
(:example :field :math-choice :display)
(:example :field :math-choice :text)
(:example :field :math-choice :script)
(:example :field :math-choice :scriptscript)
