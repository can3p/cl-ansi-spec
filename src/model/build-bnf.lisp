;;;; src/model/build-bnf.lisp
;;;;
;;;; The handlers that build BNF rules and their notation from their events
;;;; (docs/model.md, "Syntax").
;;;; Owner: step 3.15 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/model)

(defparameter *bnf-containers*
  '((:optional :bnf-optional content)
    (:zero-or-more :bnf-zero-or-more content)
    (:one-or-more :bnf-one-or-more content)
    (:group :bnf-group content)
    (:parenthesized :bnf-parenthesized content)
    (:bracketed :bnf-bracketed content)
    (:required :bnf-required content)
    (:interleave :bnf-interleave content))
  "The notation keys whose begin opens a container: (KEY NODE-KIND FIELD).
Each is closed by the :END of its key, the way a macro with an argument
or an opening and a closing macro (\\lbrac ... \\rbrac) reports it.")

(defparameter *bnf-leaves*
  '((:caret :bnf-caret)
    (:angle :angle-name :name)
    (:indirection :bnf-indirection :name))
  "The notation keys whose begin opens a container of a node without
content: (KEY NODE-KIND [NAME-FIELD]), NAME-FIELD the field that holds
the text of the event's first argument.  What the container holds (the
drawn wedge of a caret, say) is dropped.")

(defparameter *bnf-marks*
  '((:bnf-break :bnf-break)
    (:repeat-previous :bnf-repeat-previous))
  "The notation keys reported by a :MARK event, each a node of its own:
(KEY NODE-KIND).")

(defparameter *bnf-glyphs*
  '((:optional "[" "]")
    (:bracketed "[" "]")
    (:parenthesized "(" ")")
    (:zero-or-more nil "*"))
  "The characters the notation macros typeset around their content, which
the node says instead: (KEY OPENING CLOSING), either NIL when the macro
sets none as text (a brace or a plus is a math character, not text).")

(defun strip-glyphs (items opening closing)
  "ITEMS, a container's contents, without the string OPENING at the
start of the first item and CLOSING at the end of the last, when they
are there; an item left empty goes."
  (flet ((strip (items prefix suffix)
           (let ((item (first items)))
             (if (and (stringp item)
                      (or (null prefix) (eql 0 (search prefix item)))
                      (or (null suffix)
                          (and (>= (length item) (length suffix))
                               (string= suffix item :start2 (- (length item) (length suffix))))))
                 (let ((text (subseq item (length (or prefix ""))
                                     (- (length item) (length (or suffix ""))))))
                   (if (string= text "") (rest items) (cons text (rest items))))
                 items))))
    (let ((items (strip items opening nil)))
      (nreverse (strip (nreverse (copy-list items)) nil closing)))))

(defun strip-notation-glyphs (key)
  "The ON-CLOSE function of the containers of KEY: remove the glyphs
*BNF-GLYPHS* lists for KEY from its node's content."
  (destructuring-bind (&optional opening closing) (rest (assoc key *bnf-glyphs*))
    (and (or opening closing)
         (lambda (builder container)
           (let* ((node (container-node container))
                  (registry (builder-registry builder))
                  (items (node-field-value node 'content registry)))
             (setf (node-field-value node 'content registry)
                   (strip-glyphs items opening closing)))))))

(defun bnf-strip-opening-glyph (builder node)
  "Remove from the start of NODE's content the opening glyph of its
kind's notation key (*BNF-GLYPHS*, by *BNF-CONTAINERS*), as
STRIP-NOTATION-GLYPHS does when its container closes: for content whose
start changed after that."
  (let* ((key (first (find (node-kind node) *bnf-containers* :key #'second)))
         (opening (second (assoc key *bnf-glyphs*))))
    (when opening
      (let ((registry (builder-registry builder)))
        (setf (node-field-value node 'content registry)
              (strip-glyphs (node-field-value node 'content registry) opening nil))))))

(defun first-argument-text (builder event)
  "The text of EVENT's first argument, or NIL when it has none."
  (let ((arguments (event-arguments event)))
    (and arguments (argument-text builder (first arguments)))))

(defun interleave-twice-p (builder event)
  "True when EVENT begins an :INTERLEAVE without an argument right inside
one that has just begun with its content: \\interleave calls
\\begininterleave, which reports the same notation again."
  (and (null (event-arguments event))
       (let ((container (current-container builder)))
         (and (eq (container-key container) :interleave)
              (null (container-items container))
              (container-node container)))))

(defun bnf-container-handler (key kind field)
  "The handler of the :BEGIN of KEY: a container of a KIND node holding
its items in FIELD."
  (lambda (builder event span)
    (if (and (eq key :interleave) (interleave-twice-p builder event))
        ;; A container without a node passes its items on to the one below.
        (open-container builder key span)
        (open-container builder key span
                        :node (make-builder-node builder kind)
                        :field field
                        :on-close (strip-notation-glyphs key)))))

(defun bnf-leaf-handler (key kind name-field)
  "The handler of the :BEGIN of KEY: a container of a KIND node with no
content, its NAME-FIELD set to the first argument's text.  What the
container holds is what the macro drew (the wedge of a caret, the name
in angle brackets), dropped.  \\down draws only math, its arrow: text in
it went there because the begin waited for its first node (a template's
text, \"(values\" in dict-types.tex:856), and goes before the node."
  (lambda (builder event span)
    (let ((name (and name-field (first-argument-text builder event))))
      (open-container builder key span
                      :node (apply #'make-builder-node builder kind
                                   (and name (list name-field name)))
                      :on-close (and (eq key :indirection)
                                     (lambda (builder container)
                                       (dolist (item (container-contents container))
                                         (when (stringp item)
                                           (add-item builder item)))))))))

(defun bnf-end-indirection (builder event span)
  "The :END of \\down: its node closes; \\down then sets its name with
\\param, which the node already says: that parameter's events are
dropped."
  (close-container builder :indirection span event)
  (let ((node (first (container-items (current-container builder))))
        (next (peek-event builder)))
    (when (and next (typep node 'node) (eq (node-kind node) :bnf-indirection)
               (eq (event-type next) :begin) (eq (event-key next) :param)
               (equal (first-argument-text builder next)
                      (node-field-value node :name (builder-registry builder))))
      (let ((depth 0))
        (loop (let ((event (next-event builder)))
                (cond ((null event) (return))
                      ((not (eq (event-key event) :param)))
                      ((eq (event-type event) :begin) (incf depth))
                      ((and (eq (event-type event) :end) (zerop (decf depth)))
                       (return)))))))))

(defun bnf-rule-handler (builder event span)
  "A :BEGIN :BNF-RULE: the rule's name is its first argument; the items up
to the matching end, its right side.  \\auxbnf sets the rule in an
alignment of three columns (an indent; the name, `::=`; the right side),
whose lines \\CR (a :BNF-BREAK) ends: the alignment is layout, its right
side's cells are the definition (BNF-RULE-READ)."
  (let ((name (or (first-argument-text builder event) "")))
    (open-container builder :bnf-rule span
                    :node (make-builder-node builder :bnf-rule :name name)
                    :field 'definition
                    :on-close (lambda (builder container)
                                (let* ((node (container-node container))
                                       (registry (builder-registry builder)))
                                  (setf (node-field-value node 'definition registry)
                                        (strip-glyphs (node-field-value node 'definition registry)
                                                      (format nil "~A::" name) nil)))))
    (bnf-rule-read builder)))

(defun bnf-rule-ends-p (builder key)
  "True when an :END of KEY closes the innermost rule open in BUILDER (or
none is open): the rule's own, or that of a container below it."
  (let* ((stack (builder-stack builder))
         (rule (position :bnf-rule stack :key #'container-key))
         (closed (position key (butlast stack) :key #'container-key)))
    (or (null rule) (and closed (>= closed rule)))))

(defun bnf-skip-cell (builder)
  "Consume the events of a cell whose :BEGIN was just consumed, up to its
:END: the indent or the name and `::=' of a rule's alignment, which the
node says otherwise."
  (let ((depth 1))
    (loop (let ((event (next-event builder)))
            (cond ((null event) (return))
                  ((not (eq (event-key event) :cell)))
                  ((eq (event-type event) :begin) (incf depth))
                  ((and (eq (event-type event) :end) (zerop (decf depth)))
                   (return)))))))

(defun bnf-rule-read (builder)
  "Take the events of the rule just opened up to its :END, dispatched as
usual, but those of the alignment \\auxbnf sets it in (the first one
met, outside any cell of another): its rows, its cells and its
\\noalign groups are dropped, the cells of columns 1 and 2 with their
content, so the right side's content goes to the rule."
  (let ((alignment-depth nil) (depth 0))
    (loop
      (multiple-value-bind (event event-span) (peek-event builder)
        ;; The rule is closed, by its end or one below it: done.
        (when (or (null event) (null (find-container builder :bnf-rule)))
          (return))
        (let ((type (event-type event)) (key (event-key event)))
          (flet ((drop () (next-event builder)))
            (cond
              ;; The rule's end, or an end that closes it (of the
              ;; paragraph it stands in): back to the usual dispatch.
              ((and (eq type :end) (null alignment-depth) (bnf-rule-ends-p builder key))
               (return))
              ((and (eq type :begin) (eq key :alignment))
               (if (and (null alignment-depth) (zerop depth))
                   (progn (drop) (setf alignment-depth 0))
                   (progn (incf depth) (next-event builder)
                          (dispatch builder event event-span))))
              ((and (eq type :end) (eq key :alignment))
               (next-event builder)
               (if (zerop depth)
                   (setf alignment-depth nil)
                   (progn (decf depth) (dispatch builder event event-span))))
              ((and alignment-depth (zerop depth)
                    (member key '(:row :no-align)) (member type '(:begin :end)))
               (drop))
              ((and alignment-depth (zerop depth) (eq key :cell) (eq type :begin))
               (drop)
               (when (< (event-property event :column 0) 3)
                 (bnf-skip-cell builder)))
              ((and alignment-depth (zerop depth) (eq key :cell) (eq type :end))
               (drop))
              (t (next-event builder)
                 (dispatch builder event event-span)))))))))

(defun install-bnf-handlers (table)
  "Register the handlers of step 3.15 in the handler table TABLE."
  (register-handler :begin :bnf-rule #'bnf-rule-handler table)
  (loop for (key kind field) in *bnf-containers*
        do (register-handler :begin key (bnf-container-handler key kind field) table))
  (loop for (key kind name-field) in *bnf-leaves*
        do (register-handler :begin key (bnf-leaf-handler key kind name-field) table))
  (register-handler :end :indirection #'bnf-end-indirection table)
  (loop for (key kind) in *bnf-marks*
        ;; KIND is rebound: each handler closes over its own.
        do (let ((kind kind))
             (register-handler :mark key
                               (lambda (builder event span)
                                 (declare (ignore event))
                                 (add-item builder (make-builder-node builder kind :span span)))
                               table)))
  table)

(install-bnf-handlers *handlers*)
