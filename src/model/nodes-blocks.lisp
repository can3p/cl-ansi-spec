;;;; src/model/nodes-blocks.lisp
;;;;
;;;; The node kinds of blocks (docs/model.md, "Blocks"): the category
;;;; :block, paragraphs, code, lists and their items, editor and reviewer
;;;; notes.
;;;; Owner: step 3.2 (shapes), then 3.10 of docs/plan/m3.md (documentation
;;;; and examples, through tests/model/undocumented-blocks.sexp).

(in-package #:cl-ansi-spec/model)

(define-category :block (:area :blocks)
  "What stands between paragraphs in a section, a part or an item:
paragraphs, code, lists, tables, figures, signatures, BNF rules,
displayed math, notes and the anchors that fall between blocks.")

(define-node paragraph (:area :blocks :categories (:block)
                 :example (:paragraph :content ("A " (:emphasis :content ("call"))
                                       " is a " (:strong :content ("safe call"))
                                       " if each of the following ...")))
  "A paragraph: the text TeX set from the start of horizontal mode to
\\par."
  (content :inlines :required t
   :doc "The paragraph's text and inlines, in order."
   :example ("The " (:emphasis :content ("global environment")) " is that part of an environment ...")))

(define-node code-block (:area :blocks :categories (:block)
                 :example (:code-block
                           :lines ((:code-line :content (" (let ((x 1))"))
                                   (:code-line :content ("   (declare (special x))")))))
  "Code, from \\code to \\endcode, each line as it is written."
  (lines (:node :code-line) :repeated t :required t
   :doc "The lines, in order, blank ones included."
   :example ((:code-line :content (" (let ((x 1))")) (:code-line))))

(define-node code-line (:area :blocks
                 :example (:code-line :content ("   (declare (special x))")))
  "A line of a code block."
  (content :inlines
   :doc "The line's text, its spaces kept, and its inlines (terms,
example notation); absent for a blank line."
   :example ("   (declare (special x))")))

(define-node item-list (:area :blocks :categories (:block)
                 :example (:item-list
                           :items ((:item :label ("•")
                                    :content ((:paragraph :content ("bindings of dynamic variables."))))
                                   (:item :label ("•")
                                    :content ((:paragraph :content ("bindings of functions.")))))))
  "A list, from \\beginlist to \\endlist, or the items of a level below
\\item (\\itemitem, \\itemitemitem) that follow one another."
  (items (:node :item) :repeated t :required t
   :doc "The list's items, in order."
   :example ((:item :label ("•") :content ((:paragraph :content ("bindings of functions.")))))))

(define-node item (:area :blocks
                 :example (:item :label ("•")
                           :content ((:paragraph :content ("bindings of dynamic variables.")))))
  "An item of a list: \\item, \\itemitem or \\itemitemitem and what
follows it up to the next item of its level or above, or the list's
end.  Items of a lower level after it form an item list in its content."
  (label :inlines
   :doc "The item's label, the macro's argument (a bullet, a number, a
term); absent when empty."
   :example ("•"))
  (content (:node :block) :repeated t
   :doc "The item's blocks."
   :example ((:paragraph :content ("bindings of dynamic variables.")))))

(define-node editor-note (:area :blocks :categories (:block :inline)
                 :example (:editor-note
                           :content ("KMP: ``derivatives??'' terminology to be worked on.")
                           :hidden t))
  "An editor's note, \\editornote: a remark of the editors, not part of
the standard, kept whatever the options say."
  (content :inlines :required t
   :doc "The note's text."
   :example ("KMP: ``derivatives??'' terminology to be worked on."))
  (hidden :boolean
   :doc "True when the options (\\editornotesfalse) hide the note from
the typeset document."
   :example t))

(define-node reviewer-note (:area :blocks :categories (:block :inline)
                 :example (:reviewer-note
                           :content ("Is the order of other things specified??")
                           :hidden t))
  "A reviewer's note, \\reviewer: a remark of a reviewer, not part of
the standard, kept whatever the options say."
  (content :inlines :required t
   :doc "The note's text."
   :example ("Is the order of other things specified??"))
  (hidden :boolean
   :doc "True when the options (\\editornotesfalse) hide the note from
the typeset document."
   :example t))
