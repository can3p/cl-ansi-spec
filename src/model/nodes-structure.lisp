;;;; src/model/nodes-structure.lisp
;;;;
;;;; The node kinds of the document's structure (docs/model.md,
;;;; "Structure"): the standard, its chapters and their sections of every
;;;; level, and the target kinds that point to chapters and sections.
;;;; Owner: step 3.2 (shapes), then 3.8 of docs/plan/m3.md (documentation
;;;; and examples, through tests/model/undocumented-structure.sexp).

(in-package #:cl-ansi-spec/model)

(define-target-kind :chapter (:area :structure :node :chapter)
  "A chapter, by its id: the target of a \\secref whose label a
\\DefineChapter defines.")

(define-target-kind :section (:area :structure :node :section)
  "A section of any level, by its id: the target of a \\secref whose
label a \\DefineSection defines.")

(define-node document (:area :structure)
  "The whole standard: the root of the model, built from every chapter
job."
  (version :string :required t
   :doc "The revision of the draft, the text of \\rev in setup-version.tex.")
  (front-matter (:node :chapter) :repeated t
   :doc "The unnumbered chapters of chap-0.tex (\\beginSimpleChapter), in
order; absent when the model is built from part of the jobs.")
  (chapters (:node :chapter) :repeated t :required t
   :doc "The numbered chapters (\\beginchapter), 1 to 26, then the
appendix A, in that order."))

(define-node chapter (:area :structure)
  "A chapter: a numbered one begun by \\beginchapter, or an unnumbered
one of the front matter begun by \\beginSimpleChapter or
\\beginSimpleChapterLeft."
  (id :string :required t
   :doc "The chapter's id: the reference name of \\beginchapter (its third
argument, e.g. ChapOne), or a simple chapter's title.")
  (number :string
   :doc "The chapter's number as \\beginchapter's first argument gives it
(\"1\" … \"26\", \"A\"); absent for a simple chapter.")
  (title :inlines :required t
   :doc "The chapter's title, \\beginchapter's second argument or the
simple chapter's one.")
  (children (:node :section :dictionary-entry :block) :repeated t
   :doc "What the chapter holds, in order: the blocks before its first
section, then its sections."))

(define-node section (:area :structure)
  "A section of any level: \\beginSection or \\includeDictionary (level
1), \\beginSubsection (2), \\beginsubsubsection (3),
\\beginsubsubsubsection (4) or \\beginsubsubsubsubsection (5).  It runs
to the next section of its level or above, or the chapter's end."
  (id :string :required t
   :doc "The label of the \\DefineSection that names the section, or
<parent-id>/<n> for a section that none names (its n-th among its
parent's sections).")
  (number :string :required t
   :doc "The section's number, its chapter's and the count of each level
joined by dots (\"14.1.2\"), as the :write of its \\DefineSection
confirms.")
  (level :integer :required t
   :doc "The level, 1 for a section of the chapter, 2 for a subsection,
and so on to 5.")
  (dictionary :boolean
   :doc "True for a dictionary section, begun by \\includeDictionary: its
children are dictionary entries.")
  (title :inlines :required t
   :doc "The section's title, the argument of the macro that began it.")
  (children (:node :section :dictionary-entry :glossary-group :block) :repeated t
   :doc "What the section holds, in order: blocks, dictionary entries,
glossary groups and its subsections."))
