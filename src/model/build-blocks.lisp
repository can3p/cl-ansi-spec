;;;; src/model/build-blocks.lisp
;;;;
;;;; The handlers that build paragraphs, code, lists, notes from their events,
;;;; and the rules that drop the presentational events (docs/model.md,
;;;; "Blocks").
;;;; Owner: step 3.10 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/model)

;;; What is dropped, and why

(defparameter *dropped-events*
  '((:indent "Paragraph indentation is layout; a paragraph is a node.")
    (:glue "Spacing between words, lines and blocks: a space between words
is a :space event, and the structure is in the nodes.")
    (:kern "Spacing and italic corrections: layout.")
    (:penalty "Break hints: layout.")
    (:rule "A drawn line (\\hrule, \\vrule): layout.")
    (:language "Hyphenation language: layout.")
    (:tex-mark "\\mark feeds running heads: layout.")
    (:special "\\special is a hint to the output driver: layout.")
    (:openout "Opens a file for \\write; the data the model needs is rebuilt
from events (docs/events.md).")
    (:closeout "Closes a file for \\write: see :openout."))
  "The events no node stands for: each event type and the reason it is
dropped (step 3.10).  Dropped events are not reported.")

(defparameter *discarded-containers*
  '((:leaders "The filler (dots, rules) repeated across a line: layout.")
    (:insert "\\insert is a vertical-list insertion (footnotes, floats): the spec
uses it only inside its own page macros, not in its text.")
    (:vadjust "\\vadjust adds material above or below a line: layout.")
    (:shipout "\\shipout sends a page to the output: layout."))
  "The containers whose whole content is dropped, each with its reason.")

;;; State of a build

(defstruct (block-state (:constructor make-block-state ()))
  "What the block handlers of one build remember: the PENDING item (its
level and span) that the next paragraph begins, and the AFTER-PARAGRAPH
actions that wait for the open paragraph to end."
  (pending nil)
  (after-paragraph '()))

(defvar *block-states*
  (make-hash-table :test 'eq #+sbcl :weakness #+sbcl :key #+sbcl :synchronized #+sbcl t)
  "The BLOCK-STATE of each builder.")

(defun block-state (builder)
  "The BLOCK-STATE of BUILDER."
  (or (gethash builder *block-states*)
      (setf (gethash builder *block-states*) (make-block-state))))

(defun open-paragraph-p (builder)
  "True when the innermost container is a paragraph or a line of code."
  (member (container-key (current-container builder)) '(:paragraph :code-line)))

(defun after-paragraph (builder function)
  "Call FUNCTION when the open paragraph has ended, now when none is open.
TeX ends the paragraph a list begins or ends in after the event
announcing it (docs/model.md, \"Blocks\")."
  (if (open-paragraph-p builder)
      (setf (block-state-after-paragraph (block-state builder))
            (append (block-state-after-paragraph (block-state builder))
                    (list function)))
      (funcall function)))

;;; Paragraphs and code lines

(defun blank-content-p (items)
  "True when ITEMS hold nothing but spaces."
  (every (lambda (item) (and (stringp item) (every (lambda (c) (char= c #\Space)) item)))
         items))

(defun finish-paragraph (builder container)
  "On-close of a paragraph: its items become a :paragraph node, unless
the paragraph holds nothing (a paragraph TeX starts for an empty
line)."
  (let ((items (container-contents container)))
    (setf (container-items container)
          (unless (blank-content-p items)
            (list (make-builder-node builder :paragraph :content items
                                     :span (join-spans (container-span container)
                                                       (container-closing-span container))))))))

(define-handler (:begin :paragraph) (builder event span)
  (declare (ignore event))
  (cond ((eq (container-key (current-container builder)) :code)
         (open-container builder :code-line span :node (make-builder-node builder :code-line)
                                                 :field 'content))
        (t
         (let* ((state (block-state builder))
                (pending (block-state-pending state)))
           (when pending
             (setf (block-state-pending state) nil)
             (start-item builder (first pending) (second pending)))
           (open-container builder :paragraph span :on-close #'finish-paragraph)))))

;;; The end of a paragraph runs what waited for it (a list's begin or end).

(defun innermost-paragraph-key (builder)
  "The key of the innermost open paragraph or code line."
  (loop for container in (builder-stack builder)
        when (member (container-key container) '(:paragraph :code-line))
          return (container-key container)
        finally (return :paragraph)))

(define-handler (:end :paragraph) (builder event span)
  (close-container builder (innermost-paragraph-key builder) span event)
  (unless (open-paragraph-p builder)
    (let* ((state (block-state builder))
           (actions (block-state-after-paragraph state)))
      (setf (block-state-after-paragraph state) '())
      (mapc #'funcall actions))))

;;; Lists

(defun item-key (level)
  "The container key of an item of LEVEL (1 to 3)."
  (ecase level (1 :item-1) (2 :item-2) (3 :item-3)))

(defun sublist-key (level)
  "The container key of the list of the items of LEVEL under an item."
  (ecase level (2 :sublist-2) (3 :sublist-3)))

(defun key-level (key)
  "The level of an item container KEY or of a sublist's, else NIL."
  (case key
    ((:item-1) 1) ((:item-2 :sublist-2) 2) ((:item-3 :sublist-3) 3)))

(defun item-container-key-p (key)
  "True when KEY is the key of an item's container."
  (member key '(:item-1 :item-2 :item-3)))

(defun sublist-container-key-p (key)
  "True when KEY is the key of the list of an item's sub-items."
  (member key '(:sublist-2 :sublist-3)))

(defun close-items-from (builder level span)
  "Close the items of LEVEL or below (deeper) and the lists of items
deeper than LEVEL that are open at the top of the stack."
  (loop for key = (container-key (current-container builder))
        while (or (and (item-container-key-p key) (>= (key-level key) level))
                  (and (sublist-container-key-p key) (> (key-level key) level)))
        do (close-container builder key span nil)))

(defun start-item (builder level span)
  "Begin an item of LEVEL (the paragraph that holds its label begins now),
closing what the previous item left open and opening the list of its
level inside an item above it."
  (close-items-from builder level span)
  (let ((key (container-key (current-container builder))))
    (cond ((item-container-key-p key)
           (open-container builder (sublist-key level) span
                           :node (make-builder-node builder :item-list)
                           :field 'items))
          ((member key '(:list :sublist-2 :sublist-3)))
          (t (report-problem builder :node span
                             :message "An item outside a list."))))
  (open-container builder (item-key level) span
                  :node (make-builder-node builder :item) :field 'content))

(defun note-item (level)
  "The handler of the mark of an item of LEVEL: it is begun by the next
paragraph, since the mark comes while the previous item's paragraph is
still open (docs/model.md, \"Blocks\")."
  (lambda (builder event span)
    (declare (ignore event))
    (setf (block-state-pending (block-state builder)) (list level span))))

(defun item-label-container-p (builder)
  "True when the innermost container is the first paragraph of an
item, with nothing in it yet: its first box holds the item's label."
  (let ((stack (builder-stack builder)))
    (and (eq (container-key (first stack)) :paragraph)
         (null (container-items (first stack)))
         (item-container-key-p (container-key (second stack)))
         (null (node-field-value (container-node (second stack)) 'label
                                 (builder-registry builder))))))

(defun finish-label (builder container)
  "On-close of a box holding an item's label: its items are the label."
  (let ((item (find-if #'item-container-key-p (builder-stack builder)
                       :key #'container-key)))
    (when item
      (setf (node-field-value (container-node item) 'label (builder-registry builder))
            (unless (blank-content-p (container-contents container))
              (container-contents container))))
    (setf (container-items container) '())))

(define-handler (:begin :box) (builder event span)
  (declare (ignore event))
  (if (item-label-container-p builder)
      (open-container builder :box span :on-close #'finish-label)
      (open-container builder :box span :groups-only t)))

(defun close-list (builder span event)
  "Close the items of an open list, then the list."
  (close-items-from builder 1 span)
  (close-container builder :list span event))

(define-handler (:begin :list) (builder event span)
  (declare (ignore event))
  (after-paragraph builder
                   (lambda ()
                     (open-container builder :list span
                                     :node (make-builder-node builder :item-list)
                                     :field 'items))))

(define-handler (:end :list) (builder event span)
  (after-paragraph builder (lambda () (close-list builder span event))))

;;; Code

(define-handler (:begin :code) (builder event span)
  "A code block.  \\code on the line after a paragraph's last (as in:
dict-flow.tex:414) begins before that paragraph's end: the block opens
after it (AFTER-PARAGRAPH)."
  (declare (ignore event))
  (after-paragraph builder
                   (lambda ()
                     (open-container builder :code span
                                     :node (make-builder-node builder :code-block)
                                     :field 'lines))))

;;; Notes

(defun note-handler (kind)
  "The handler of the mark of a note of KIND: its text is the argument
as TeX shows it, since the note's typeset copy does not exist while the
options hide it."
  (lambda (builder event span)
    (let ((text (string-trim " " (or (first (event-argument-texts builder event)) ""))))
      (unless (event-property event :hidden)
        (report-problem builder :node span
                        :message "A note the options show: its typeset copy is also in the text."))
      (add-item builder (make-builder-node builder kind :content (list text)
                                                         :hidden (and (event-property event :hidden) t)
                                                         :span span)))))

;;; Dropped events

(defun discard-container (builder key span)
  "Open a container for KEY whose items are thrown away when it closes."
  (open-container builder key span
                  :on-close (lambda (builder container)
                              (declare (ignore builder))
                              (setf (container-items container) '()))))

(defun install-block-handlers (table)
  "Register the handlers of step 3.10 in the handler table TABLE."
  (dolist (row *dropped-events*)
    (register-handler (first row) nil (lambda (builder event span)
                                        (declare (ignore builder event span)))
                      table))
  (dolist (row *discarded-containers*)
    (let ((key (first row)))
      (register-handler :begin key
                        (lambda (builder event span)
                          (declare (ignore event))
                          (discard-container builder key span))
                        table)))
  (loop for (level key) in '((1 :item) (2 :item-2) (3 :item-3))
        do (register-handler :mark key (note-item level) table))
  (register-handler :mark :editor-note (note-handler :editor-note) table)
  (register-handler :mark :reviewer-note (note-handler :reviewer-note) table)
  table)

(install-block-handlers *handlers*)

;; Text directly in a line of code is code, not a font run.  The call
;; computes the list on first use, so that the push below is kept.
(plain-text-container-p :code)
(pushnew :code-line *plain-text-containers*)
