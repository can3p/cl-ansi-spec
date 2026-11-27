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
content, its NAME-FIELD set to the first argument's text."
  (lambda (builder event span)
    (let ((name (and name-field (first-argument-text builder event))))
      (open-container builder key span
                      :node (apply #'make-builder-node builder kind
                                   (and name (list name-field name)))))))

(defun bnf-rule-handler (builder event span)
  "A :BEGIN :BNF-RULE: the rule's name is its first argument; the items up
to the matching end, its right side."
  (let ((name (or (first-argument-text builder event) "")))
    (open-container builder :bnf-rule span
                    :node (make-builder-node builder :bnf-rule :name name)
                    :field 'definition
                    :on-close (lambda (builder container)
                                (let* ((node (container-node container))
                                       (registry (builder-registry builder)))
                                  (setf (node-field-value node 'definition registry)
                                        (strip-glyphs (node-field-value node 'definition registry)
                                                      (format nil "~A::" name) nil)))))))

(defun install-bnf-handlers (table)
  "Register the handlers of step 3.15 in the handler table TABLE."
  (register-handler :begin :bnf-rule #'bnf-rule-handler table)
  (loop for (key kind field) in *bnf-containers*
        do (register-handler :begin key (bnf-container-handler key kind field) table))
  (loop for (key kind name-field) in *bnf-leaves*
        do (register-handler :begin key (bnf-leaf-handler key kind name-field) table))
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
