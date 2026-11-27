;;;; src/expand/whatsits.lisp
;;;;
;;;; The whatsits other than the writes (streams.lisp) and \shipout
;;;; (TeX: The Program, §§638-640, 1354, 1366-1377).  \special appends a
;;;; :SPECIAL node of its text, expanded; \setlanguage a :LANGUAGE node as
;;;; fix_language's.  \shipout ships a box: no DVI is written, but the
;;;; box becomes a :SHIPOUT node of the outer vertical list and its
;;;; whatsits are carried out as ship_out's hlist_out and vlist_out do
;;;; (§1366): the \openout, \write and \closeout nodes, depth first, in
;;;; list order, under the state of the moment, except in leaders; a
;;;; \vadjust's list after the paragraph or adjusted \hbox holding it,
;;;; where TeX moves it.  What they give is flagged :SHIPOUT, as
;;;; \immediate's are flagged :IMMEDIATE.

(in-package #:cl-ansi-spec/expand)

(define-command "special" (expander token meaning)
  ;; §1354: the text expanded as \edef's body is.
  (let ((tokens (scan-toks expander :xpand t
                                    :warning-index (and (cs-token-p token)
                                                        (cs-token-control-sequence token)))))
    (append-node expander (make-node :special :properties (list :tokens tokens)
                                              :value tokens :span (token-span token)))))

(define-command "setlanguage" (expander token meaning)
  ;; §1377: in horizontal modes only; out of range is language 0.
  (if (eq (mode-kind (current-mode expander)) :horizontal)
      (let ((n (scan-int expander)))
        (append-language expander (if (<= 1 n 255) n 0) (token-span token)))
      (report-illegal-case expander token meaning)))

(define-command "shipout" (expander token meaning)
  (scan-box expander (list :shipout (token-span token))))

(defun carry-out-whatsit (expander node)
  "out_what (§1373) for the \\openout, \\write or \\closeout NODE of a
shipped box."
  (let ((properties (node-properties node)))
    (out-what expander (string-downcase (symbol-name (node-kind node)))
              (getf properties :stream)
              (case (node-kind node)
                (:openout (getf properties :file))
                (:write (getf properties :tokens)))
              (node-span node) :shipout)))

(defun carry-out-whatsits (expander nodes &optional adjusted)
  "Carry out the whatsits among NODES as hlist_out and vlist_out meet
them (§§619-640, 1366): in boxes and paragraphs (the lines TeX would
have made), in math and in a discretionary's no-break list, not in
leaders, inserts or a discretionary's break lists.  When ADJUSTED (the
list of a MIGRATING-NODE-P node), each \\vadjust's list, in math too,
follows the others."
  (let ((moved '()))
    (labels ((walk (nodes adjusted)
               (dolist (node nodes)
                 (case (node-kind node)
                   ((:openout :write :closeout) (carry-out-whatsit expander node))
                   ((:box :paragraph)
                    (carry-out-whatsits expander (node-children node)
                                        (migrating-node-p node)))
                   ;; Math becomes part of the list it is in.
                   (:math (if adjusted
                              (walk (node-children node) t)
                              (carry-out-whatsits expander (node-children node)
                                                  (display-math-p node))))
                   (:discretionary
                    (let ((no-break (find :no-break (node-children node)
                                          :key #'node-kind)))
                      (when no-break
                        (walk (node-children no-break) adjusted))))
                   (:vadjust (when adjusted (push node moved)))))))
      (walk nodes adjusted))
    (dolist (node (nreverse moved))
      (carry-out-whatsits expander (node-children node)))))

(defun ship-out (expander box span)
  "TeX's ship_out (§§638-640) of BOX for \\shipout read at SPAN: a
:SHIPOUT node of the outer vertical list holding the box, its whatsits
carried out, then \\deadcycles 0.  When \\tracingoutput is positive the
box is shown in the log."
  (let ((node (box-node box)))
    (append-node expander (make-node :shipout :children (list node) :span span)
                 :list (outer-list expander))
    (when (plusp (parameter (expander-state expander) :tracingoutput))
      (log-message expander :diagnostic
                   (format nil "Completed box being shipped out~A"
                           (show-box-text expander (list node)))
                   :span span))
    (carry-out-whatsits expander (list node))
    (setf (page-state-dead-cycles (expander-page expander)) 0)))
