;;;; src/model/nodes-glossary.lisp
;;;;
;;;; The node kinds of the glossary (docs/model.md, "Glossary"): its
;;;; letter groups, entries, senses and examples, the enums of parts of
;;;; speech and usages, and the target kind that points to entries.
;;;; Owner: step 3.2 (shapes), then 3.14 of docs/plan/m3.md (documentation
;;;; and examples, through tests/model/undocumented-glossary.sexp).

(in-package #:cl-ansi-spec/model)

(define-target-kind :glossary (:area :glossary :node :glossary-entry)
  "A glossary entry, by its id: the target of \\term and \\newterm.")

(define-enum part-of-speech (:area :glossary)
  "The part of speech of a glossary term, by its macro."
  (:noun "\\Noun, `n.'.")
  (:verb "\\Verb, `v.'.")
  (:transitive-verb "\\TransitiveVerb, `v.t.'.")
  (:adjective "\\Adjective, `adj.'.")
  (:adverb "\\Adverb, `adv.'."))

(define-enum usage (:area :glossary)
  "Where a glossary sense comes from or is used, by its macro."
  (:ansi "\\ANSI: a sense the standard itself fixes.")
  (:ieee "\\IEEE: the sense of the IEEE standards.")
  (:iso "\\ISO: the sense of the ISO standards.")
  (:traditional "\\Traditional: a traditional sense, kept for
compatibility with earlier usage.")
  (:mathematics "\\Mathematics: the sense of mathematics.")
  (:idiomatic "\\Idiomatic: an idiomatic sense.")
  (:computers "\\Computers: the sense of computing in general."))

(define-node glossary-group
    (:area :glossary
     :example (:glossary-group
               :letter "A"
               :entries ((:glossary-entry
                          :id "absolute" :term "absolute"
                          :parts-of-speech (:adjective)
                          :senses ((:glossary-sense
                                    :number 1
                                    :content ("(of a "
                                              (:term-ref :text "time" :target (:glossary "time"))
                                              ") representing a specific point in time."))
                                   (:glossary-sense
                                    :number 2
                                    :content ("(of a "
                                              (:term-ref :text "pathname"
                                               :target (:glossary "pathname"))
                                              ") representing a specific position in a
directory hierarchy.")))))))
  "The glossary entries under one letter heading, from \\firstindextab
or \\indextab to the next."
  (letter :string :required t
   :doc "The heading's letter, or the heading for the entries that do not
begin with a letter."
   :example "A")
  (entries (:node :glossary-entry) :repeated t
   :doc "The group's entries, in order."
   :example ((:glossary-entry :id "abort" :term "abort"
              :senses ((:glossary-sense :content ("to stop a computation.")))))))

(define-node glossary-entry
    (:area :glossary
     :example (:glossary-entry
               :id "access" :term "access"
               :parts-of-speech (:noun :transitive-verb)
               :senses ((:glossary-sense
                         :number 1 :parts-of-speech (:transitive-verb)
                         :content ("(a " (:term-ref :text "place" :target (:glossary "place"))
                                   ") to " (:term-ref :text "read" :sense 1
                                            :target (:glossary "read"))
                                   " the value of the place."))
                        (:glossary-sense
                         :number 2 :parts-of-speech (:noun)
                         :content ("(of a " (:term-ref :text "place" :target (:glossary "place"))
                                   ") an attempt to read it.")))))
  "A glossary entry, from \\gentry to the next \\gentry, \\indextab or
the glossary's end."
  (id :string :required t
   :doc "The entry's id: its term."
   :example "access")
  (term :string :required t
   :doc "The term defined, \\gentry's argument."
   :example "access")
  (pronunciation :inlines
   :doc "How the term is pronounced, \\pronounced's argument, with its
stress marks; absent when not given."
   :example ((:strong :content ("nil"))))
  (parts-of-speech (:enum part-of-speech) :repeated t
   :doc "The parts of speech given after the term, before the senses, in
order."
   :example (:noun :transitive-verb))
  (usages (:enum usage) :repeated t
   :doc "The usages given after the term, before the senses, that hold
for every sense."
   :example (:idiomatic))
  (senses (:node :glossary-sense) :repeated t :required t
   :doc "The senses, in order; one, without a number, when the entry is
not numbered; text before `1.' (an optional context, `(of an array)')
is a sense of its own, first, without a number."
   :example ((:glossary-sense :number 1 :content ("expressed adjustability."))
             (:glossary-sense :number 2 :content ("actual adjustability.")))))

(define-node glossary-sense
    (:area :glossary
     :example (:glossary-sense
               :number 1 :parts-of-speech (:transitive-verb)
               :content ("(a " (:term-ref :text "place" :target (:glossary "place"))
                         ") to read the value of the place.")
               :examples ((:glossary-example :content ("Look it up."))))) 
  "A sense of a glossary term: a numbered definition (`1.', `2.', …), or
the entry's one definition."
  (number :integer
   :doc "The sense's number; absent when the entry has one sense."
   :example 1)
  (parts-of-speech (:enum part-of-speech) :repeated t
   :doc "The parts of speech given for this sense alone."
   :example (:transitive-verb))
  (usages (:enum usage) :repeated t
   :doc "The usages given for this sense alone."
   :example (:mathematics))
  (content :inlines :required t
   :doc "The definition's text, its \\term references and its `See'
pointers."
   :example ("(of a " (:term-ref :text "time" :target (:glossary "time"))
             ") representing a specific point in time."))
  (examples (:node :glossary-example) :repeated t
   :doc "The sense's examples, \\gexample, in order."
   :example ((:glossary-example :content ("This is an example of an example.")))))

(define-node glossary-example
    (:area :glossary
     :example (:glossary-example :content ("This is an example of an example.")))
  "An example of a glossary sense, set in quotes: \\gexample."
  (content :inlines :required t
   :doc "The example's text."
   :example ("This is an example of an example.")))
