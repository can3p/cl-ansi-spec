;;;; src/model/nodes-structure.lisp
;;;;
;;;; The node kinds of the document's structure (docs/model.md,
;;;; "Structure"): the standard, its chapters and their sections of every
;;;; level, and the target kinds that point to chapters and sections.
;;;; Its examples are in this file.

(in-package #:cl-ansi-spec/model)

(define-target-kind :chapter (:area :structure :node :chapter)
  "A chapter, by its id: the target of a \\secref whose label a
\\DefineChapter defines.")

(define-target-kind :section (:area :structure :node :section)
  "A section of any level, by its id: the target of a \\secref whose
label a \\DefineSection defines.")

(define-node document (:area :structure
                      :example (:document :version "15.17"
                                :front-matter ((:chapter :id "Credits" :title ("Credits")))
                                :chapters ((:chapter :id "ChapOne" :number "1"
                                            :title ("Introduction")))))
  "The whole standard: the root of the model, built from every chapter
job."
  (version :string :required t
   :example "15.17"
   :doc "The revision of the draft, the text of \\rev in setup-version.tex.")
  (cover (:node :block) :repeated t
   :example ((:paragraph :content ((:strong :content ("X3J13/94-101")))))
   :doc "The blocks of the cover, before the first chapter of chap-0.tex:
the standard's name, its document number, a page left blank.")
  (front-matter (:node :chapter) :repeated t
   :example ((:chapter :id "Credits" :title ("Credits")))
   :doc "The unnumbered chapters of chap-0.tex (\\beginSimpleChapter), in
order; absent when the model is built from part of the jobs.")
  (chapters (:node :chapter) :repeated t :required t
   :example ((:chapter :id "ChapOne" :number "1" :title ("Introduction")))
   :doc "The numbered chapters (\\beginchapter), 1 to 26, then the
appendix A, in that order."))

(define-node chapter (:area :structure
                      :example (:chapter :id "ChapFifteen" :number "15" :title ("Arrays")
                                :children ((:section :id "ArrayConcepts" :number "15.1"
                                            :level 1 :title ("Array Concepts")))))
  "A chapter: a numbered one begun by \\beginchapter, or an unnumbered
one of the front matter begun by \\beginSimpleChapter or
\\beginSimpleChapterLeft."
  (id :string :required t
   :example "ChapFifteen"
   :doc "The chapter's id: the reference name of \\beginchapter (its third
argument, e.g. ChapOne), or a simple chapter's title.")
  (aliases :string :repeated t
   :example ("Syntax")
   :doc "The other labels that name the chapter, which a reference may
use: the short name, the second argument of \\DefineChapter
(\\DefineChapter{ChapTwo}{Syntax}).")
  (number :string
   :example "15"
   :doc "The chapter's number as \\beginchapter's first argument gives it
(\"1\" … \"26\", \"A\"); absent for a simple chapter.")
  (title :inlines :required t
   :example ("Arrays")
   :doc "The chapter's title, \\beginchapter's second argument or the
simple chapter's one.")
  (children (:node :section :dictionary-entry :block) :repeated t
   :example ((:section :id "ArrayConcepts" :number "15.1" :level 1
               :title ("Array Concepts")))
   :doc "What the chapter holds, in order: the blocks before its first
section, then its sections."))

(define-node section (:area :structure
                      :example (:section :id "ArrayElements" :number "15.1.1" :level 2
                                :title ("Array Elements")
                                :children ((:section :id "ArrayElements/1" :number "15.1.1.1"
                                            :level 3 :title ("Array Indices")))))
  "A section of any level: \\beginSection or \\includeDictionary (level
1), \\beginSubsection (2), \\beginsubsubsection (3),
\\beginsubsubsubsection (4) or \\beginsubsubsubsubsection (5).  It runs
to the next section of its level or above, or the chapter's end."
  (id :string :required t
   :example "ArrayElements"
   :doc "The label of the \\DefineSection that names the section, or
<parent-id>/<n> for a section that none names (its n-th among its
parent's sections).  When the sources name a section twice, the last label.")
  (aliases :string :repeated t
   :example ("CharacterSyntax")
   :doc "The other labels that name the section, which a reference may
use: those of its earlier \\DefineSection when the sources name the
section twice (2.1 is CharacterSyntax in chap-2.tex and
TheStandardSyntax in concept-syntax.tex).")
  (number :string :required t
   :example "15.1.1"
   :doc "The section's number, its chapter's and the count of each level
joined by dots (\"14.1.2\"), as the :write of its \\DefineSection
confirms.")
  (level :integer :required t
   :example 2
   :doc "The level, 1 for a section of the chapter, 2 for a subsection,
and so on to 5.")
  (dictionary :boolean
   :example t
   :doc "True for a dictionary section, begun by \\includeDictionary: its
children are dictionary entries.")
  (title :inlines :required t
   :example ("Array Elements")
   :doc "The section's title, the argument of the macro that began it.")
  (children (:node :section :dictionary-entry :glossary-group :block) :repeated t
   :example ((:section :id "ArrayElements/1" :number "15.1.1.1" :level 3
               :title ("Array Indices")))
   :doc "What the section holds, in order: blocks, dictionary entries,
glossary groups and its subsections."))
