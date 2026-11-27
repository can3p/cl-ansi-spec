;;;; src/expand/nest.lisp
;;;;
;;;; TeX's semantic nest (§§211-219): each level is a list being built,
;;;; with what the scanner reads of it (\spacefactor, \prevdepth,
;;;; \prevgraf, and through its last node \lastpenalty, \lastkern,
;;;; \lastskip), and the page (\pagegoal ... \pagedepth, §§980-982).  No
;;;; page is ever started (docs/tex-fidelity.md, "Not emulated"): the outer
;;;; vertical list keeps everything.  The nodes are nodes.lisp's.

(in-package #:cl-ansi-spec/expand)

(defconstant +ignore-depth+ -65536000
  "TeX's ignore_depth, -1000pt in sp: \\prevdepth when no box precedes (§212).")

(deftype mode ()
  "TeX's modes (§211): vertical, internal vertical, horizontal, restricted
horizontal, math, display math, and :NONE, the mode of a \\write being
expanded (mode 0)."
  '(member :vertical :internal-vertical :horizontal :restricted-horizontal
    :math :display-math :none))

(defun mode-kind (mode)
  "TeX's abs(mode): :VERTICAL, :HORIZONTAL, :MATH, or :NONE."
  (ecase mode
    ((:vertical :internal-vertical) :vertical)
    ((:horizontal :restricted-horizontal) :horizontal)
    ((:math :display-math) :math)
    (:none :none)))

(deftype last-node-kind ()
  "The kinds of node the scanner distinguishes at the end of a list (§424)."
  '(member :penalty :kern :glue :character :other))

(defstruct (list-state (:copier nil))
  "One level of the semantic nest.  CONTENTS are the nodes of its list,
newest first (nodes.lisp); its last node (§424) is read from them.
CONTRIBUTED is the node that ended the outer vertical list when TeX's
page builder last ran (BUILD-PAGE), NIL before: TeX would have moved it
and everything before it to the page.
CLANG is TeX's clang, the language of the paragraph's characters so far
(§1034); SPAN is where the list began (the token of the command that
opened it), NIL for the outer vertical list."
  (mode :vertical :type mode)
  (prev-depth +ignore-depth+ :type integer)
  (space-factor 1000 :type integer)
  (prev-graf 0 :type integer)
  (clang 0 :type integer)
  (contents '() :type list)
  (contributed nil)
  (span nil))

(defstruct (page-state (:copier nil))
  "The page builder's variables the scanner reads (§§980-982, 991).  The
page stays empty: no page builder runs.  SO-FAR is page_so_far: the
goal, total, stretch of each order (finite, fil, fill, filll), shrink and
depth, settable by \\pagegoal etc.  LAST-GLUE is NIL for TeX's
max_halfword (no glue)."
  (so-far (make-array 8 :initial-element 0) :read-only t)
  (contents :empty :type (member :empty :inserts-only :box-there))
  (output-active nil :type boolean)
  (last-penalty 0 :type integer)
  (last-kern 0 :type integer)
  (last-glue nil :type (or null glue))
  (dead-cycles 0 :type integer)
  (insert-penalties 0 :type integer))

(defun page-dimen-index (name)
  "The index in page_so_far of the page dimension primitive NAME, or NIL."
  (position name '("pagegoal" "pagetotal" "pagestretch" "pagefilstretch"
                   "pagefillstretch" "pagefilllstretch" "pageshrink"
                   "pagedepth")
            :test #'string=))
