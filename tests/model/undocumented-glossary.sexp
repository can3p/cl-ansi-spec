;;;; tests/model/undocumented-glossary.sexp
;;;;
;;;; The documentation ratchet of the area glossary (tests/model/documentation.lisp):
;;;; one form per item UNDOCUMENTED-ITEMS lists that still lacks its
;;;; docstring or example, e.g. (:doc :field :part :title).  Empty when
;;;; the milestone closes.

(:example :node :glossary-group)
(:example :field :glossary-group :letter)
(:example :field :glossary-group :entries)
(:example :node :glossary-entry)
(:example :field :glossary-entry :id)
(:example :field :glossary-entry :term)
(:example :field :glossary-entry :pronunciation)
(:example :field :glossary-entry :parts-of-speech)
(:example :field :glossary-entry :usages)
(:example :field :glossary-entry :senses)
(:example :node :glossary-sense)
(:example :field :glossary-sense :number)
(:example :field :glossary-sense :parts-of-speech)
(:example :field :glossary-sense :usages)
(:example :field :glossary-sense :content)
(:example :field :glossary-sense :examples)
(:example :node :glossary-example)
(:example :field :glossary-example :content)
