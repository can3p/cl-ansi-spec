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
(:entry "ff" :inline-code
 :why "Code within a formula, in a box with a trailing space (setup-document.tex:12).")
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

(:class :unreviewed
 :files ("setup-document.tex" "setup-aux.tex" "concept-glossary.tex"
         "setup-tables.tex" "setup-title.tex" "setup-version.tex" "concept-numbers.tex"
         "dict-characters.tex" "dict-conses.tex" "dict-environment.tex" "dict-flow.tex"
         "dict-numbers.tex" "dict-printer.tex" "dict-streams.tex")
 :why "Not yet classified (step 13c).")
