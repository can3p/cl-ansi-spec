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
 :why "The punctuation after `\\label ...:\\None': `.', `!' or `?', how sure the authors are that the part is empty (setup-aux.tex:1021; \\labelNone, :1025, passes it on).")

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
 :why "Names a chapter, for \\secref (setup-aux.tex:1114).")
(:entry "secref" :secref
 :why "A reference to a section, by name; \\defsecrefs defines it, \\chapref is \\let to it (setup-aux.tex:1118).")
(:entry "figref" :figref
 :why "A reference to a figure, by name; \\deffigrefs defines it (setup-aux.tex:1100).")

;;; Content the options hide

(:entry "editornote" :editor-note :handler hidden-note
 :why "An editor's note, kept even when \\editornotesfalse hides it (setup-document.tex:419).")
(:entry "reviewer" :reviewer-note :handler hidden-note
 :why "A reviewer's note, kept even when \\editornotesfalse hides it (setup-document.tex:420).")

;;; Inline meaning: terms, parameters, emphasis and code

(:entry "term" :term
 :why "A use of a glossary term, as written: phase 4 resolves it, with its inflections (setup-document.tex:85).")
(:entry "newterm" :new-term
 :why "A term defined where it is used; its \\idxterm index mark follows (setup-document.tex:83).")
(:entry "newtermidx" :new-term
 :why "A term defined where it is used, then the glossary name its \\idxterm indexes (setup-document.tex:84).")
(:entry "param" :param
 :why "A parameter of the entry or the syntax it is in (setup-document.tex:86).")
(:entry "metavar" :metavariable
 :why "A metavariable, in double angle brackets (setup-document.tex:23).")
(:entry "metaparam" :metavariable
 :why "A metavariable naming a parameter, in double angle brackets (setup-document.tex:24).")
(:entry "i" :emphasis
 :why "Emphasis: the authors' italic markup (setup-document.tex:8); it redefines plain's \\i.")
(:entry "j" :emphasis
 :why "Emphasis, with italic correction (setup-document.tex:9); it redefines plain's \\j.")
(:entry "b" :strong
 :why "Strong emphasis: the authors' bold markup (setup-document.tex:7); it redefines plain's \\b.")
(:entry "f" :inline-code
 :why "Code within text, in a box (setup-document.tex:10).")
(:entry "ff" :inline-code :placement :block
 :why "Code within a formula, in a box with a trailing space, which its begin must precede (setup-document.tex:12).")
(:entry "ang" :angle
 :why "A name in angle brackets: a character (\\NewlineChar), no arguments (\\noargs) (setup-document.tex:18).")
(:entry "hat" :caret
 :why "The caret character, drawn from a lowered math wedge whose text would not be `^' (setup-document.tex:268).")

;;; Evaluation arrows and the notation of examples

(:entry "EV" :evaluates-to
 :why "`evaluates to', an arrow in examples (setup-document.tex:239).")
(:entry "OV" :may-evaluate-to
 :why "`or evaluates to': one of several possible results (setup-document.tex:240).")
(:entry "NV" :does-not-evaluate-to
 :why "`does not evaluate to' (setup-document.tex:241).")
(:entry "EQ" :equivalent
 :why "`is equivalent to' (setup-document.tex:242).")
(:entry "OUT" :output
 :why "Output of an example, after a triangle (setup-document.tex:246).")
(:entry "IN" :input
 :why "User input in an example, underlined (setup-document.tex:247).")

;;; References to the standard's objects: \\clref and \\ttref, and the
;;; wrappers that say what kind of object is named.

(:entry "clref" :clref
 :why "A reference to a defined name, in the code font (setup-document.tex:61).")
(:entry "ttref" :ttref
 :why "A reference set in the typewriter font: keywords, packages, loop keywords (setup-document.tex:62).")
(:entry "typeref" :typeref :kind :wrapper
 :why "A reference to a type or class; the \\clref it calls has the name (setup-document.tex:71).")
(:entry "misc" :misc :kind :wrapper
 :why "A reference to a symbol of no other kind (t, nil, restarts); the \\clref it calls has the name (setup-document.tex:72).")
(:entry "miscref" :misc :kind :wrapper
 :why "A reference to a symbol of no other kind; the \\clref it calls has the name (setup-document.tex:73).")
(:entry "declref" :declref :kind :wrapper
 :why "A reference to a declaration; the \\clref it calls has the name (setup-document.tex:74).")
(:entry "funref" :funref :kind :wrapper
 :why "A reference to a function; the \\clref it calls has the name (setup-document.tex:75).")
(:entry "macref" :macref :kind :wrapper
 :why "A reference to a macro; the \\clref it calls has the name (setup-document.tex:76).")
(:entry "specref" :specref :kind :wrapper
 :why "A reference to a special operator; the \\clref it calls has the name (setup-document.tex:77).")
(:entry "conref" :conref :kind :wrapper
 :why "A reference to a constant variable; the \\clref it calls has the name (setup-document.tex:78).")
(:entry "varref" :varref :kind :wrapper
 :why "A reference to a variable; the \\clref it calls has the name (setup-document.tex:79).")
(:entry "kwd" :kwd :kind :wrapper
 :why "A keyword, its name without the colon; the \\ttref it calls has it with (setup-document.tex:64).")
(:entry "kwdref" :kwd :kind :wrapper
 :why "A keyword, as \\kwd (setup-document.tex:65).")
(:entry "packref" :packref :kind :wrapper
 :why "A package, its name as written; the \\ttref it calls upper-cases it (setup-document.tex:66).")
(:entry "loopref" :loopref :kind :wrapper
 :why "A loop keyword; the \\ttref it calls has it (setup-document.tex:67).")
(:entry "keyref" :keyref :kind :wrapper
 :why "A lambda-list keyword, its name without the ampersand; the \\clref it calls has it with (setup-document.tex:69).")
(:entry "formatOp" :format-directive
 :why "A format directive, after its tilde (setup-terms.tex:199).")
(:entry "formatdirective" :format-directive
 :why "A format directive, then the words `format directive' (setup-terms.tex:200).")
(:entry "allowotherkeys" :lambda-list-keyword
 :why "A lambda-list keyword, in the keyword font (setup-terms.tex:95).")
(:entry "aux" :lambda-list-keyword
 :why "A lambda-list keyword, in the keyword font (setup-terms.tex:96).")
(:entry "body" :lambda-list-keyword
 :why "A lambda-list keyword, in the keyword font (setup-terms.tex:98).")
(:entry "environment" :lambda-list-keyword
 :why "A lambda-list keyword, in the keyword font (setup-terms.tex:99).")
(:entry "key" :lambda-list-keyword
 :why "A lambda-list keyword, in the keyword font (setup-terms.tex:101).")
(:entry "opt" :lambda-list-keyword
 :why "A lambda-list keyword, in the keyword font (setup-terms.tex:103).")
(:entry "optional" :lambda-list-keyword
 :why "A lambda-list keyword, in the keyword font (setup-terms.tex:104).")
(:entry "rest" :lambda-list-keyword
 :why "A lambda-list keyword, in the keyword font (setup-terms.tex:106).")
(:entry "whole" :lambda-list-keyword
 :why "A lambda-list keyword, in the keyword font (setup-terms.tex:107).")

;;; Self-references

(:entry "thissection" :this-section
 :why "`this section': a reference to the section it is in (setup-aux.tex:1112).")
(:entry "Thissection" :this-section
 :why "`This section': a reference to the section it is in (setup-aux.tex:1111).")
(:entry "thenextfigure" :next-figure
 :why "`Figure N--M': a reference to the next figure, numbered by \\capno (setup-document.tex:409).")
(:entry "Thenextfigure" :next-figure
 :why "`Figure N--M' at the start of a sentence (setup-document.tex:408).")

;;; Index entries: marks, the letter \\logidx gets in their keys

(:entry "idxref" :index-ref :kind :mark
 :why "An index entry of kind R, a defined name (setup-aux.tex:426).")
(:entry "idxkeyref" :index-keyref :kind :mark
 :why "An index entry of kind R, a lambda-list keyword, without its ampersand (setup-aux.tex:427).")
(:entry "idxcode" :index-code :kind :mark
 :why "An index entry of kind C, code (setup-aux.tex:428).")
(:entry "idxkwd" :index-keyword :kind :mark
 :why "An index entry of kind K, a keyword (setup-aux.tex:429).")
(:entry "idxtext" :index-text :kind :mark
 :why "An index entry of kind T, text (setup-aux.tex:430).")
(:entry "idxterm" :index-term :kind :mark
 :why "An index entry of kind G, a glossary term (setup-aux.tex:431).")
(:entry "idxexample" :index-example :kind :mark
 :why "An index entry of kind E, an example (setup-aux.tex:432).")
(:entry "idxpackref" :index-package :kind :mark
 :why "An index entry of kind P, a package (setup-aux.tex:433).")

;;; The bibliography's works

(:entry "CLtL" :cite
 :why "The title of a work the standard cites (setup-terms.tex:7).")
(:entry "CLtLTwo" :cite
 :why "The title of a work the standard cites (setup-terms.tex:8).")
(:entry "RandomHouseDictionary" :cite
 :why "The title of a work the standard cites (setup-terms.tex:10).")
(:entry "WebstersDictionary" :cite
 :why "The title of a work the standard cites (setup-terms.tex:13).")
(:entry "CondSysPaper" :cite
 :why "The title of a work the standard cites (setup-terms.tex:16).")
(:entry "GabrielBenchmarks" :cite
 :why "The title of a work the standard cites (setup-terms.tex:18).")
(:entry "KnuthVolThree" :cite
 :why "The title of a work the standard cites (setup-terms.tex:20).")
(:entry "MetaObjectProtocol" :cite
 :why "The title of a work the standard cites (setup-terms.tex:22).")
(:entry "AnatomyOfLisp" :cite
 :why "The title of a work the standard cites (setup-terms.tex:24).")
(:entry "FlavorsPaper" :cite
 :why "The title of a work the standard cites (setup-terms.tex:26).")
(:entry "LispOnePointFive" :cite
 :why "The title of a work the standard cites (setup-terms.tex:28).")
(:entry "Moonual" :cite
 :why "The title of a work the standard cites (setup-terms.tex:30).")
(:entry "Pitmanual" :cite
 :why "The title of a work the standard cites (setup-terms.tex:32).")
(:entry "InterlispManual" :cite
 :why "The title of a work the standard cites (setup-terms.tex:34).")
(:entry "Chinual" :cite
 :why "The title of a work the standard cites (setup-terms.tex:36).")
(:entry "SmalltalkBook" :cite
 :why "The title of a work the standard cites (setup-terms.tex:38).")
(:entry "XPPaper" :cite
 :why "The title of a work the standard cites (setup-terms.tex:40).")
(:entry "IEEEFloatingPoint" :cite
 :why "The title of a work the standard cites (setup-terms.tex:44).")
(:entry "IEEEScheme" :cite
 :why "The title of a work the standard cites (setup-terms.tex:46).")
(:entry "ISOChars" :cite
 :why "The title of a work the standard cites (setup-terms.tex:48).")
(:entry "PrincipalValues" :cite
 :why "The title of a work the standard cites (setup-terms.tex:56).")
(:entry "RevisedCubedScheme" :cite
 :why "The title of a work the standard cites (setup-terms.tex:58).")
(:entry "StandardLispReport" :cite
 :why "The title of a work the standard cites (setup-terms.tex:60).")
(:entry "NILReport" :cite
 :why "The title of a work the standard cites (setup-terms.tex:62).")
(:entry "SOneCLPaper" :cite
 :why "The title of a work the standard cites (setup-terms.tex:64).")
(:entry "CLOSPaper" :cite
 :why "The title of a work the standard cites (setup-terms.tex:66).")

;;; Syntax of dictionary entries: the signature paragraph each \\Def...
;;; macro sets (not the entry after it).  Arguments: the name, the
;;; lambda list, then the values when the macro has them; the key says
;;; the kind of operator and whether it returns.

(:entry "Defun" :defun
 :why "A function (setup-document.tex:113).")
(:entry "DefunWithValues" :defun
 :why "A function and its values (setup-document.tex:116).")
(:entry "DefunWithValuesNewline" :defun
 :why "A function and its values, on a second line (setup-document.tex:120).")
(:entry "DefunNoReturn" :defun-no-return
 :why "A function that does not return (setup-document.tex:125).")
(:entry "Defmac" :defmac
 :why "A macro (setup-document.tex:98).")
(:entry "DefmacWithValues" :defmac
 :why "A macro and its values (setup-document.tex:109).")
(:entry "DefmacWithValuesNewline" :defmac
 :why "A macro and its values, on a second line (setup-document.tex:104).")
(:entry "DefmacNoReturn" :defmac-no-return
 :why "A macro that does not return (setup-document.tex:101).")
(:entry "Defspec" :defspec
 :why "A special operator (setup-document.tex:188).")
(:entry "DefspecWithValues" :defspec
 :why "A special operator and its values (setup-document.tex:197).")
(:entry "DefspecWithValuesNewline" :defspec
 :why "A special operator and its values, on a second line (setup-document.tex:201).")
(:entry "DefspecNoReturn" :defspec-no-return
 :why "A special operator that does not return (setup-document.tex:192).")
(:entry "Defgen" :defgen
 :why "A generic function (setup-document.tex:157).")
(:entry "DefgenWithValues" :defgen
 :why "A generic function and its values (setup-document.tex:161).")
(:entry "DefgenWithValuesNewline" :defgen
 :why "A generic function and its values, on a second line (setup-document.tex:165).")
(:entry "Defmeth" :defmeth
 :why "A method: its generic function and specialized lambda list (setup-document.tex:172).")
(:entry "Defsetf" :defsetf
 :why "A setf form: the accessor, its lambda list and the new value (setup-document.tex:146).")
(:entry "Defvar" :defvar
 :why "A variable, between asterisks (setup-document.tex:176).")
(:entry "Defvarnoast" :defvar
 :why "A variable whose name has no asterisks (setup-document.tex:180).")
(:entry "Defcon" :defcon
 :why "A constant variable (setup-document.tex:184).")
(:entry "DefunMultiWithValues" :defun-multi :placement :block
 :why "Several functions with one lambda list and values: the lambda list, the values, then their \\entry lines (setup-document.tex:130).")
(:entry "DefunMultiAccessorWithValues" :defun-multi-accessor :placement :block
 :why "Several accessors: lambda list, values, new value, then their \\entry lines, set twice, as readers and as setf forms (setup-document.tex:137).")
(:entry "DefsetfMulti" :defsetf-multi :placement :block
 :why "Several setf forms: lambda list, new value, then their \\entry lines (setup-document.tex:150).")
(:entry "entry" :entry :kind :mark :local t
 :why "A line of the alignment of the macro that defines it, anew each time (setup-document.tex:132): a name of \\DefunMulti... or \\DefsetfMulti (:139-152), a row of \\tabletwo (setup-tables.tex:137).")
(:entry "Deftype" :deftype :kind :mark
 :why "A type specifier: its name, then the lines of its compound syntax, set as an alignment and then a paragraph begun by \\hfill, so a mark (setup-document.tex:211).")

;;; BNF (setup-document.tex:280-345): rules and their operators

(:entry "auxbnf" :bnf-rule :placement :block
 :why "A BNF rule: the non-terminal, then its right side, set as an alignment (setup-document.tex:323).")
(:entry "CR" :bnf-break :kind :mark
 :why "A line break within a BNF rule's right side; \\auxbnf defines it (setup-document.tex:323).")
(:entry "star" :zero-or-more
 :why "Its argument, zero or more times: a star after it (setup-document.tex:283).")
(:entry "plus" :one-or-more :placement :block
 :why "Its argument, one or more times: a plus after it, in a formula (setup-document.tex:303).")
(:entry "prevplus" :repeat-previous :kind :mark
 :why "What precedes, one or more times: a plus alone, after a group split over lines (setup-document.tex:304).")
(:entry "one" :required :placement :block
 :why "Its argument, which must appear once in the interleaving around it (setup-document.tex:306; concept-definitions.tex:104).")
(:entry "brac" :optional
 :why "Its argument, optional: in brackets (setup-document.tex:290).")
(:entry "lbrac" :optional :kind :open
 :why "An optional part split over lines: its opening bracket (setup-document.tex:291).")
(:entry "rbrac" :end-optional :kind :close :closes :optional
 :why "The closing bracket of an optional part split over lines (setup-document.tex:293).")
(:entry "curly" :group
 :why "A group, usually of alternatives: in braces (setup-document.tex:299).")
(:entry "lcurly" :group :kind :open
 :why "A group split over lines: its opening brace (setup-document.tex:300).")
(:entry "rcurly" :end-group :kind :close :closes :group
 :why "The closing brace of a group split over lines (setup-document.tex:302).")
(:entry "paren" :parenthesized
 :why "Its argument in literal parentheses, part of the syntax (setup-document.tex:286).")
(:entry "lparen" :parenthesized :kind :open
 :why "Literal parentheses split over lines: the opening one (setup-document.tex:287).")
(:entry "rparen" :end-parenthesized :kind :close :closes :parenthesized
 :why "The closing literal parenthesis split over lines (setup-document.tex:289).")
(:entry "ttbrac" :bracketed
 :why "Its argument in literal brackets, in the code font (setup-document.tex:295).")
(:entry "lttbrac" :bracketed :kind :open
 :why "Literal brackets split over lines: the opening one (setup-document.tex:296).")
(:entry "rttbrac" :end-bracketed :kind :close :closes :bracketed
 :why "The closing literal bracket split over lines (setup-document.tex:298).")
(:entry "interleave" :interleave
 :why "Its alternatives in any order, each at most once (setup-document.tex:311; concept-definitions.tex:88-96).")
(:entry "begininterleave" :interleave :kind :open
 :why "An interleaving split over lines: its opening double bracket (setup-document.tex:308).")
(:entry "endinterleave" :end-interleave :kind :close :closes :interleave
 :why "The closing double bracket of an interleaving split over lines (setup-document.tex:310).")
(:entry "down" :indirection
 :why "A non-terminal whose definition is spliced in place (setup-document.tex:316; concept-definitions.tex:188-197).")

;;; The glossary (concept-glossary.tex defines its own macros)

(:entry "gentry" :glossary-entry :kind :mark
 :why "A glossary entry, its term; it runs to the next one, as a label does, and its body is \\itemitem, \\b and \\idxterm, whose events follow (concept-glossary.tex:49).")
(:entry "gexample" :glossary-example
 :why "An example of a glossary sense, in quotes (concept-glossary.tex:50).")
(:entry "firstindextab" :glossary-letter :kind :mark
 :why "The heading of the glossary's first group, non-alphabetic terms (concept-glossary.tex:52).")
(:entry "indextab" :glossary-letter :kind :mark
 :why "The heading of a group of glossary entries, a letter; it ends one list and begins another (concept-glossary.tex:51).")
(:entry "Noun" :part-of-speech :kind :wrapper
 :why "A glossary sense's part of speech, `n.'; the \\i it calls has the text (concept-glossary.tex:55).")
(:entry "Verb" :part-of-speech :kind :wrapper
 :why "A glossary sense's part of speech, `v.'; the \\i it calls has the text (concept-glossary.tex:56).")
(:entry "TransitiveVerb" :part-of-speech :kind :wrapper
 :why "A glossary sense's part of speech, `v.t.'; the \\i it calls has the text (concept-glossary.tex:57).")
(:entry "Adjective" :part-of-speech :kind :wrapper
 :why "A glossary sense's part of speech, `adj.'; the \\i it calls has the text (concept-glossary.tex:58).")
(:entry "Adverb" :part-of-speech :kind :wrapper
 :why "A glossary sense's part of speech, `adv.'; the \\i it calls has the text (concept-glossary.tex:59).")
(:entry "ANSI" :usage :kind :wrapper
 :why "Where a glossary sense comes from or is used, `ANSI'; the \\i it calls has the text (concept-glossary.tex:61).")
(:entry "IEEE" :usage :kind :wrapper
 :why "Where a glossary sense comes from or is used, `IEEE'; the \\i it calls has the text (concept-glossary.tex:62).")
(:entry "ISO" :usage :kind :wrapper
 :why "Where a glossary sense comes from or is used, `ISO'; the \\i it calls has the text (concept-glossary.tex:63).")
(:entry "Traditional" :usage :kind :wrapper
 :why "Where a glossary sense comes from or is used, `Trad.'; the \\i it calls has the text (concept-glossary.tex:64).")
(:entry "Mathematics" :usage :kind :wrapper
 :why "Where a glossary sense comes from or is used, `Math.'; the \\i it calls has the text (concept-glossary.tex:65).")
(:entry "Idiomatic" :usage :kind :wrapper
 :why "Where a glossary sense comes from or is used, `Idiom.'; the \\i it calls has the text (concept-glossary.tex:66).")
(:entry "Computers" :usage :kind :wrapper
 :why "Where a glossary sense comes from or is used, `Comp.'; the \\i it calls has the text (concept-glossary.tex:67).")
(:entry "meaning" :sense
 :why "The sense of the term before it, a number set as a subscript (setup-document.tex:452); it redefines the primitive \\meaning.")
(:entry "pronounced" :pronunciation
 :why "How a glossary term is pronounced, in brackets (setup-document.tex:450).")


;;; Figures: the content goes to box 1, which \\endfig unboxes

(:entry "endfig" :figure :placement :block
 :why "A figure (setup-aux.tex:734): its \\ifcase stays open while \\finishboxfig unboxes box 1, the content \\boxfig set aside with its events, and sets the caption.")
(:entry "docaption" :caption :placement :block
 :why "A caption, `Figure N--M. text', as set (setup-aux.tex:744); empty when none was given.")

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
(:class :phrase
 :names ("\\clisp" "\\Lisp" "\\Unix" "\\t" "\\nil" "\\etc" "\\ie" "\\eg"
         "\\CLOS" "\\OS" "\\SETFof" "\\objectoftype" "\\oftype" "\\ofclass"
         "\\oftypes" "\\ofmetaclass" "\\thetype" "\\Thetype" "\\Thetypes"
         "\\theclass" "\\Theclass" "\\thevariable" "\\Thevariable"
         "\\Thevariables" "\\themacro" "\\Themacro" "\\theinitkeyarg"
         "\\theinitkeyargs" "\\thekeyarg" "\\Thekeyarg" "\\thefunction"
         "\\Thefunction" "\\thefunctions" "\\Thefunctions" "\\thespecform"
         "\\Thespecform" "\\thespecop" "\\Thespecop" "\\TheGF" "\\subtypeof"
         "\\subtypesof" "\\supertypeof" "\\supertypesof" "\\subclassof"
         "\\therestart" "\\Therestart" "\\thepackage" "\\Thepackage"
         "\\instsofclass" "\\instancesofclasses" "\\Theloopconstruct"
         "\\theloopconstruct" "\\theloopkeyword" "\\thevalueof" "\\Thevalueof"
         "\\TypePredicate" "\\NamedPredicate" "\\Predicate" "\\StrictPredicate"
         "\\Shouldcheckplus" "\\Checktypes" "\\Shouldchecktype"
         "\\Shouldcheckanytype" "\\Lazychecktype" "\\Lazychecktypes"
         "\\Lazycheckanytype" "\\shouldchecktype" "\\Default" "\\DefaultFor"
         "\\DefaultIn" "\\Defaults" "\\DefaultEach" "\\HairyDefault"
         "\\MentionMetaObjects" "\\symbolnamedesignator"
         "\\symbolnamedesignators" "\\packagenamedesignator"
         "\\packagenamedesignators")
 :why "setup-terms.tex's phrases: words, and entries (\\term, \\typeref, \\param, \\issue ...) for what has meaning.")
(:class :phrase
 :names ("\\Seefun" "\\seefun" "\\Seefuns" "\\seefuns" "\\Seespec" "\\seespec"
         "\\Seemac" "\\seemac" "\\Seevar" "\\seevar" "\\Seetype" "\\seetype"
         "\\Seemisc" "\\seemisc" "\\Seesection" "\\seesection" "\\Seechapter"
         "\\seechapter" "\\Seefigure" "\\seefigure" "\\Seeterm" "\\seeterm"
         "\\SeetermAlso" "\\seetermAlso" "\\noargs" "\\novalues" "\\eval"
         "\\noeval" "\\evalspecial" "\\bogusterm" "\\NewlineChar" "\\SpaceChar"
         "\\TabChar" "\\ReturnChar" "\\LinefeedChar" "\\BackspaceChar"
         "\\PageChar" "\\RuboutChar" "\\WhitespaceChar")
 :why "setup-document.tex:370-409 and :253-261: `See' and the name of what a reference names, `evaluated', character names (through \\ang); \\bogusterm is its argument only.")
(:class :presentational
 :names ("\\sub" "\\Font" "\\sc" "\\mi" "\\mh" "\\mii" "\\miii" "\\keyword"
         "\\function" "\\bf" "\\it" "\\tt" "\\rm" "\\normaltype" "\\break"
         "\\bull" "\\ " "\\{" "\\}" "\\\\" "<" ">" "|" "*" "_" "-" "~")
 :why "Fonts, sizes and characters (setup-aux.tex:3-103, 440, 550, 597, 960-981): the code characters typeset themselves; phase 4 reads direct font changes outside entries.")
(:class :presentational
 :names ("\\normalleftskip" "\\comleftskip" "\\hcomleftskip" "\\normalparskip"
         "\\combarht" "\\Vskip" "\\par" "\\fullhsize" "\\footline" "\\headline"
         "\\pageno" "\\iskip" "\\capno" "\\secn" "\\ssecn" "\\sssecn"
         "\\ssssecn" "\\sssssecn" "\\ssssssecn" "\\comline" "\\idxins"
         "\\ifcomfirst" "\\folio" "\\onecolumn" "\\twocolumn" "\\nopageticks"
         "\\footers" "\\dotw" "\\donormalcomma" "\\changedepth")
 :why "Layout: skips, page parts, columns and the counters the section and figure macros keep (setup-aux.tex:110-343, 848-931).")
(:class :presentational
 :names ("\\bq" "\\ampersand" "\\lbr" "\\rbr" "\\dot" "\\vert" "\\centerdot"
         "\\lbracket" "\\rbracket" "\\minussign" "\\CRLF" "\\ssso" "\\ssst"
         "\\ssse" "\\ssss" "\\sssn" "\\sssx" "\\sssy" "\\empty")
 :why "One character or symbol each, or a subscript (setup-document.tex:225-278); \\empty is `()' in the code font (setup-terms.tex:93), but plain's \\empty, called everywhere, cannot be an entry.")

(:class :phrase
 :names ("\\specparam" "\\starparam" "\\stardown" "\\starparen" "\\plusparam"
         "\\plusdown" "\\plusparen" "\\placeplus" "\\DeclsAndDoc" "\\LocalDeclsAndDoc"
         "\\TVar" "\\starTVar" "\\SpecializedVar" "\\JustVar" "\\VarValue"
         "\\VarValueSuppliedP" "\\KeyVarValueSuppliedP" "\\JustKey" "\\VarInitStep"
         "\\NoReturn")
 :why "BNF and syntax made of entries (setup-document.tex:92, 170, 313-366): \\starparam is \\star{\\curly{\\param{...}}}, \\NoReturn an arrow and a bar.")
(:class :presentational
 :names ("\\Vtop" "\\vtop" "\\blankline" "\\more" "\\xparen" "\\xbrac" "\\xttbrac"
         "\\xcurly" "\\extrainterleave")
 :why "Layout of syntax (setup-document.tex:94-98, 133, 282-309): \\Vtop aligns a signature's lines; \\x... are spacers as wide as an opening bracket, set in a box that is thrown away, so the entries inside them leave no event.")

(:class :phrase
 :names ("\\beginsubSection" "\\beginsubsection" "\\chapref" "\\begincom")
 :why "\\let copies of entries, or macros that call one at once: \\beginsubsection is \\beginSubsection (setup-aux.tex:787-788), \\chapref is \\secref (:1119), \\begincom changes catcodes and calls \\dobegincom (:842).")
(:class :presentational
 :names ("\\endSubsection" "\\endsubsubsection" "\\endsubsubsubsection"
         "\\endsubsubsubsubsection" "\\endsubSection" "\\endsubsection"
         "\\endSection" "\\endchapter" "\\endSimpleChapter")
 :why "The ends of sections and chapters (setup-aux.tex:782-807): page breaks, or \\empty; phase 4 nests sections by level.")
(:class :presentational
 :names ("\\deffigrefs" "\\defsecrefs" "\\Head" "\\HeadI" "\\chapline")
 :why "\\deffigrefs and \\defsecrefs define \\figref and \\secref (setup-aux.tex:1100, 1118); \\Head and \\HeadI set the headings \\beginchapter marks (:471-476), and the cover's title lines in chap-0.tex:6-8, kept as text; \\chapline is the running title.")
(:class :option
 :names ("\\draftcomment")
 :why "Text for the running foot of a draft (setup-aux.tex:260).")
(:class :phrase
 :names ("\\bookline" "\\longbookline" "\\DocumentNumber" "\\rev"
         "\\TypographyCaveats")
 :why "Text: the standard's name, its document number and revision (setup-title.tex:11-27, setup-version.tex:5), a note on the pronunciation key (setup-document.tex:447).")
(:class :presentational
 :names ("\\maybeStress" "\\Stress" "\\stress" "\\harda" "\\harde" "\\hardo"
         "\\schwa")
 :why "Accents and stress marks of the glossary's pronunciations (setup-document.tex:429-446), inside \\pronounced.")
(:class :phrase
 :names ("\\SatisfyTest" "\\DocMethods" "\\Meth" "\\realtypespec" "\\writekeys"
         "\\writekeydescriptions" "\\ExplainRecursiveP")
 :why "Text and entries a chapter defines for itself (dict-conses.tex:3, dict-environment.tex:981-983, dict-numbers.tex:3, dict-printer.tex:7-11, dict-streams.tex:3).")
(:class :presentational
 :names ("\\Qfont" "\\alfa" "\\subOne" "\\subN" "\\Result" "\\starY" "\\starN")
 :why "Fonts, symbols and table marks a chapter defines for itself (\\starY is an asterisk, its text kept; \\starN its blank width) (concept-numbers.tex:575, dict-characters.tex:553, dict-flow.tex:5436-5437, dict-numbers.tex:1486-1488).")

(:class :phrase
 :names ("\\displaytwo" "\\displaythree" "\\displayfour" "\\displayfive"
         "\\showtwo" "\\showthree" "\\showfive" "\\tabletwo" "\\tablefigtwo"
         "\\tablefigthree" "\\tablefigfour" "\\tablefigsix")
 :why "Figures of setup-tables.tex: \\boxfig, an alignment of their cells (\\misc references in the \\display... templates), \\caption and \\endfig; \\tabletwo is a displayed alignment of \\entry rows (:137).")
(:class :phrase
 :names ("\\caption" "\\simplecaption")
 :why "\\caption keeps its text for \\docaption (setup-aux.tex:706, again at :737); \\simplecaption calls both (:756).")
(:class :presentational
 :names ("\\boxfig" "\\fig" "\\rulefig" "\\cboxfig")
 :why "They set a figure's content aside in box 1 (setup-aux.tex:637-690); \\endfig is the figure.")

