;;;; src/semantic/vocabulary.sexp
;;;;
;;;; The spec's vocabulary (docs/vocabulary.md), read by LOAD-VOCABULARY
;;;; (src/semantic/vocabulary.lisp): (:entry name key options... :why "...")
;;;; names a macro without its escape, its options those of MAKE-ENTRY;
;;;; (:class kind :names (...) :files (...) :why "...") says why the other
;;;; macros with text uses are not entries, names spelt as `make vocab'
;;;; spells them.  Every form gives its reason.

;;; Chapters and sections: marks, nested by level in phase 4 (their ends
;;; cannot be keyed: \endSubsection and its relatives are \let to \empty).

(:entry "beginchapter" :chapter :kind :mark
 :why "A chapter: number, title, reference name, running title (setup-aux.tex:176).")
(:entry "beginSimpleChapter" :simple-chapter :kind :mark
 :why "An unnumbered chapter of the front matter, its title (setup-aux.tex:796).")
(:entry "beginSimpleChapterLeft" :simple-chapter :kind :mark
 :why "An unnumbered chapter set flush left (the index), its title (setup-aux.tex:799).")
(:entry "beginSection" :section :kind :mark
 :why "A section and its title; \\startSection numbers it (setup-aux.tex:762).")
(:entry "includeDictionary" :dictionary :kind :mark
 :why "A dictionary section, numbered, whose entries the file named holds (setup-aux.tex:764).")
(:entry "beginSubsection" :subsection :kind :mark
 :why "A subsection and its title (setup-aux.tex:769); \\beginsubsection and others are \\let to it.")
(:entry "beginsubsubsection" :subsubsection :kind :mark
 :why "A subsubsection and its title (setup-aux.tex:772).")
(:entry "beginsubsubsubsection" :subsubsubsection :kind :mark
 :why "A section of the fifth level and its title (setup-aux.tex:775).")
(:entry "beginsubsubsubsubsection" :subsubsubsubsection :kind :mark
 :why "A section of the sixth level and its title (setup-aux.tex:778).")

;;; Dictionary entries

(:entry "dobegincom" :com :kind :open
 :why "A dictionary entry: its names, then its kind, the text before \\ftype (setup-aux.tex:867); \\begincom only changes catcodes first.")
(:entry "doobegincom" :com :kind :open
 :why "A dictionary entry with one argument, its names (setup-aux.tex:897).")
(:entry "endcom" :endcom :kind :close :closes :com
 :why "The end of a dictionary entry (setup-aux.tex:812).")
(:entry "label" :label :kind :mark
 :why "A labelled part of an entry: its title, then `:' or the token that says it is empty, \\None (setup-aux.tex:1023).")
(:entry "EatPunc" :label-confidence :kind :mark
 :why "The punctuation after `\\label ...:\\None': `.', `!' or `?', how sure the authors are that the part is empty (setup-aux.tex:1000-1021).")

;;; Environments

(:entry "issue" :issue :kind :open
 :why "The start of the text an X3J13 issue brought, its name; kept whatever \\ifissdisp says (setup-aux.tex:1075).")
(:entry "endissue" :endissue :kind :close :closes :issue
 :why "The end of an issue's text, its name (setup-aux.tex:1078).")
(:entry "code" :code :kind :open
 :why "Code, each line as it is written (setup-document.tex:414, \\screen!).")
(:entry "endcode" :endcode :kind :close :closes :code
 :why "The end of code (setup-document.tex:415).")
(:entry "beginlist" :list :kind :open
 :why "A list of items (setup-aux.tex:567).")
(:entry "endlist" :endlist :kind :close :closes :list
 :why "The end of a list (setup-aux.tex:572).")
(:entry "item" :item :kind :mark
 :why "An item of a list, its label (setup-aux.tex:563).")
(:entry "itemitem" :item-2 :kind :mark
 :why "An item of a list within an item, its label (setup-aux.tex:564).")
(:entry "itemitemitem" :item-3 :kind :mark
 :why "An item of the third level, its label (setup-aux.tex:565).")

;;; Cross-references

(:entry "DefineSection" :define-section :kind :mark
 :why "Names the section it is in, for \\secref (setup-aux.tex:1107).")
(:entry "DefineFigure" :define-figure :kind :mark
 :why "Names the figure that follows, for \\figref (setup-aux.tex:1097).")
(:entry "DefineChapter" :define-chapter :kind :mark
 :why "Names a chapter, for \\secref (setup-aux.tex:1112).")
(:entry "secref" :secref
 :why "A reference to a section, by name; \\defsecrefs defines it, \\chapref is \\let to it (setup-aux.tex:1118).")
(:entry "figref" :figref
 :why "A reference to a figure, by name; \\deffigrefs defines it (setup-aux.tex:1100).")

;;; Content the options hide

(:entry "editornote" :editor-note :handler hidden-note
 :why "An editor's note, kept even when \\editornotesfalse hides it (setup-document.tex:419).")
(:entry "reviewer" :reviewer-note :handler hidden-note
 :why "A reviewer's note, kept even when \\editornotesfalse hides it (setup-document.tex:420).")

;;; The other macros

(:class :reference-name
 :files ("setup-sections.tex" "setup-figures.tex" "setup-sections-for-toc.tex")
 :why "Generated names of sections, figures and chapters: arguments of \\secref, \\figref and \\beginchapter, which phase 4 resolves from the \\Define... marks.")
(:class :option
 :names ("\\sphyfalse" "\\incomfalse" "\\tocfalse" "\\showtoctrue" "\\nullabelfalse"
         "\\smallabfalse" "\\examplestrue" "\\notestrue" "\\editornotestrue"
         "\\editornotesfalse" "\\drafttrue" "\\showtocfalse" "\\issdispfalse"
         "\\isslogtrue")
 :why "Flags of the options and the layout; what they hide is still observed.")
(:class :phrase
 :names ("\\None" "\\Figref")
 :why "\\None is only ever \\label's second argument; \\Figref calls \\figref.")
(:class :unreviewed
 :files ("setup-document.tex" "setup-aux.tex" "setup-terms.tex" "concept-glossary.tex"
         "setup-tables.tex" "setup-title.tex" "setup-version.tex" "concept-numbers.tex"
         "dict-characters.tex" "dict-conses.tex" "dict-environment.tex" "dict-flow.tex"
         "dict-numbers.tex" "dict-printer.tex" "dict-streams.tex")
 :why "Not yet classified (steps 13b and 13c).")
