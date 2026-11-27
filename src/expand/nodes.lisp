;;;; src/expand/nodes.lisp
;;;;
;;;; The nodes of the lists main control builds (TeX: The Program,
;;;; §§133-161, 214, 424; docs/events.md).  A node is what TeX's
;;;; tail_append adds to the current list, without dimensions: text, a
;;;; space, glue, a kern, a penalty, a rule, a paragraph, a box ...  Each
;;;; list of the nest keeps its nodes (LIST-STATE-CONTENTS, newest first);
;;;; the scanner reads the last one (\lastskip and friends) and the
;;;; commands that remove nodes (\unskip ...) take it.  The job's events
;;;; are the outer vertical list's nodes, flattened (FLATTEN-NODES).
;;;;
;;;; A node's PROPERTIES are ready for its event: strings, numbers,
;;;; keywords, tokens, spans and lists of them (glue and dimensions as
;;;; \the shows them).  Its VALUE is what TeX reads back from it (a
;;;; penalty, a kern's width, a GLUE, a box), never part of the event.

(in-package #:cl-ansi-spec/expand)

(defstruct (node (:constructor make-node
                     (kind &key properties value (children '() composite)
                             span end-span)))
  "A node of KIND (a keyword: :TEXT, :SPACE, :GLUE, :KERN, :PENALTY,
:RULE, :INDENT, :LANGUAGE, :PARAGRAPH, :MATH, :WRITE, ...) with its event
PROPERTIES (a plist), its VALUE (see the file header) and its SPAN.  A
COMPOSITE node holds CHILDREN, a list of nodes oldest first, and flattens
to (:begin KIND ...), its children's events and (:end KIND), the latter
with END-SPAN (the span of what ended it) when known.  VIA are the spans
of the commands that replayed the node, newest first.  The text of a
:TEXT node is its VALUE, a string that grows while characters are
appended."
  (kind :other :type keyword :read-only t)
  (properties '() :type list :read-only t)
  (value nil)
  (children '() :type list :read-only t)
  (composite nil :type boolean :read-only t)
  (span nil)
  (end-span nil)
  (via '() :type list))

(defun node-last-item (node)
  "What \\lastpenalty, \\lastkern and \\lastskip see of NODE (§424): a
cons (KIND . VALUE), KIND a LAST-NODE-KIND."
  (case (node-kind node)
    (:text (list :character))
    ((:space :glue :leaders) (cons :glue (node-value node)))
    (:kern (cons :kern (node-value node)))
    (:penalty (cons :penalty (node-value node)))
    (t (list :other))))

(defun list-state-last-node (list)
  "The last node of LIST as NODE-LAST-ITEM gives it, or NIL when LIST is
empty (TeX's tail = head): when it has no nodes, or when the page builder
took them all (BUILD-PAGE)."
  (let ((node (first (list-state-contents list))))
    (and node (not (eq node (list-state-contributed list)))
         (node-last-item node))))

(defun list-nodes (list)
  "The nodes of LIST, oldest first."
  (reverse (list-state-contents list)))

(defun outer-list (expander)
  "The outer vertical list, the bottom of EXPANDER's nest."
  (car (last (expander-nest expander))))

(defun append-node (expander node &key (list (current-list expander)))
  "TeX's tail_append: NODE becomes the last node of LIST, the current list
unless given.  It is signalled as a JOB-OUTPUT."
  (push node (list-state-contents list))
  (signal 'job-output :item node)
  node)

(defun remove-last-node (list)
  "Remove the last node of LIST and return it."
  (pop (list-state-contents list)))

;;; The page builder (§§994-996)

(defun build-page (expander)
  "What TeX's build_page leaves behind, where TeX calls it: the outer
vertical list counts as empty, its nodes being on the page (they stay in
the list, which is the job's output: no page is built), and the page's
last glue, penalty and kern are those of its last node (§996)."
  (let* ((outer (outer-list expander))
         (node (first (list-state-contents outer)))
         (page (expander-page expander)))
    (when (and node (not (eq node (list-state-contributed outer))))
      (setf (list-state-contributed outer) node)
      (let ((item (node-last-item node)))
        (setf (page-state-last-glue page) (and (eq (car item) :glue) (cdr item))
              (page-state-last-penalty page) (if (eq (car item) :penalty) (cdr item) 0)
              (page-state-last-kern page) (if (eq (car item) :kern) (cdr item) 0))))))

;;; Flattening (docs/events.md)

(defun node-head (node)
  "The event of NODE itself: (KIND . PROPERTIES), its text first for a
:TEXT node, then :SPAN and, when it was replayed, :VIA."
  (append (list (node-kind node))
          (and (eq (node-kind node) :text) (list (copy-seq (node-value node))))
          (node-properties node)
          (list :span (node-span node))
          (and (node-via node) (list :via (node-via node)))))

(defun flatten-nodes (nodes)
  "The events of NODES (oldest first): a composite node becomes
(:begin KIND ...), the events of its children and (:end KIND :span ...)."
  (let ((events '()))
    (labels ((walk (node)
               (if (node-composite node)
                   (progn
                     (push (cons :begin (node-head node)) events)
                     (mapc #'walk (node-children node))
                     (push (list :end (node-kind node)
                                 :span (or (node-end-span node) (node-span node)))
                           events))
                   (push (node-head node) events))))
      (mapc #'walk nodes))
    (nreverse events)))

(defun job-events (expander)
  "The events of EXPANDER's job so far: its outer vertical list,
flattened."
  (flatten-nodes (list-nodes (outer-list expander))))
