;;;; src/expand/boxes.lisp
;;;;
;;;; Boxes as main control makes and moves them (TeX: The Program, §§645,
;;;; 977-979, 1071-1087, 1109-1110): \hbox, \vbox and \vtop open a box
;;;; group and an inner mode; at their `}' the box is made and goes where
;;;; its context says.  \box, \copy, \vsplit and \lastbox give a box that
;;;; exists already; \raise, \lower, \moveleft and \moveright shift the
;;;; box they place, and \leaders, \cleaders and \xleaders make it (or a
;;;; rule) the leaders of the glue that follows.  \unhbox, \unhcopy,
;;;; \unvbox and \unvcopy splice a register's list into the current one.
;;;; A TEX-BOX has no dimensions of its own (docs/tex-fidelity.md, "Not
;;;; emulated"): \wd, \ht and \dp read 0 unless assigned.  A box holds the
;;;; nodes of its list; placed in a list it is a box node.
;;;;
;;;; A box context (TeX's box_context) is :APPEND, the current list;
;;;; (:SHIFT d), the current list with the box shifted by d sp (down or
;;;; right); (:SETBOX n global), a box register; or (:LEADERS kind span),
;;;; the leaders of kind :LEADERS, :CLEADERS or :XLEADERS whose command
;;;; was read at span.
;;;;
;;;; Nodes never leave a register for a list shared: what \copy and
;;;; \unhcopy place is a COPY-NODE, so that the text a list goes on
;;;; growing is never the register's.

(in-package #:cl-ansi-spec/expand)

(defstruct (tex-box (:constructor make-tex-box (kind &key spec contents span
                                                       adjusted
                                                       (command (string-downcase
                                                                 (symbol-name kind)))))
                    (:copier nil))
  "A box: KIND :HBOX or :VBOX (\\vtop makes a :VBOX), the COMMAND that made
it (\"hbox\", \"vbox\" or \"vtop\"), the SPEC it was made with (see
GROUP-RECORD), its CONTENTS (nodes, oldest first), the SPAN where it was
made, the spans of the commands that gave it again (VIA, newest first),
whether it is an ADJUSTED \\hbox of vertical mode (§1083), and the
dimensions \\wd, \\ht and \\dp assigned to it."
  (kind :hbox :type (member :hbox :vbox) :read-only t)
  (command "hbox" :type string :read-only t)
  (spec nil :read-only t)
  (contents '() :type list)
  (span nil :read-only t)
  (via '() :type list)
  (adjusted nil :type boolean :read-only t)
  (width 0 :type integer)
  (height 0 :type integer)
  (depth 0 :type integer))

(defmethod box-kind ((box tex-box))
  (tex-box-kind box))

(defmethod box-dimension ((box tex-box) which)
  (ecase which
    (:width (tex-box-width box))
    (:height (tex-box-height box))
    (:depth (tex-box-depth box))))

(defmethod (setf box-dimension) (value (box tex-box) which)
  (ecase which
    (:width (setf (tex-box-width box) value))
    (:height (setf (tex-box-height box) value))
    (:depth (setf (tex-box-depth box) value))))

;;; Copying (§§204-206)

(defun copy-box (box)
  "TeX's copy_node_list of a box (\\copy): the box and its contents,
copied deeply."
  (and box
       (let ((copy (make-tex-box (tex-box-kind box) :spec (tex-box-spec box)
                                                    :command (tex-box-command box)
                                                    :contents (mapcar #'copy-node
                                                                      (tex-box-contents box))
                                                    :span (tex-box-span box)
                                                    :adjusted (tex-box-adjusted box))))
         (setf (tex-box-via copy) (tex-box-via box)
               (tex-box-width copy) (tex-box-width box)
               (tex-box-height copy) (tex-box-height box)
               (tex-box-depth copy) (tex-box-depth box))
         copy)))

(defun copy-node (node)
  "A deep copy of NODE: its text, its box and its children are its own."
  (let* ((kind (node-kind node))
         (value (node-value node))
         (copy (cond ((eq kind :box)
                      (let ((box (copy-box value)))
                        (make-node :box :properties (node-properties node) :value box
                                        :children (tex-box-contents box)
                                        :span (node-span node)
                                        :end-span (node-end-span node))))
                     ((node-composite node)
                      (make-node kind :properties (node-properties node) :value value
                                      :children (mapcar #'copy-node (node-children node))
                                      :span (node-span node)
                                      :end-span (node-end-span node)))
                     (t
                      (make-node kind :properties (node-properties node)
                                      :value (if (eq kind :text)
                                                 (make-array (length value)
                                                             :element-type 'character
                                                             :initial-contents value
                                                             :adjustable t
                                                             :fill-pointer (length value))
                                                 value)
                                      :span (node-span node))))))
    (setf (node-via copy) (node-via node))
    copy))

(defun add-via (node span)
  "Record that the command read at SPAN gave NODE again: SPAN joins its
:VIA (and its box's, for a box node)."
  (push span (node-via node))
  (when (eq (node-kind node) :box)
    (setf (tex-box-via (node-value node)) (node-via node)))
  node)

(defun given-again (box span)
  "BOX (or NIL), given again by the command read at SPAN (\\box, \\copy,
\\vsplit, \\lastbox): SPAN joins its :VIA."
  (when box
    (push span (tex-box-via box)))
  box)

;;; Box nodes

(defun make-box-command-p (meaning)
  "True when MEANING is one of TeX's make_box commands (§1071)."
  (and (primitive-p meaning)
       (member (primitive-name meaning)
               '("box" "copy" "lastbox" "vsplit" "vtop" "vbox" "hbox")
               :test #'string=)
       t))

(defun box-node (box &optional shift)
  "The node of BOX placed in a list, shifted by SHIFT sp when it was
moved: its kind, the command that made it, its spec, its shift and the
dimensions assigned to it; its children are its contents, its span and
:VIA the box's."
  (destructuring-bind (&optional spec-kind (amount 0)) (tex-box-spec box)
    (let ((node (make-node
                 :box
                 :properties (append (list :kind (tex-box-kind box)
                                           :command (tex-box-command box))
                                     (when (or (eq spec-kind :exactly) (/= amount 0))
                                       (list :spec (list spec-kind (format-dimen amount))))
                                     (when shift
                                       (list :shift (format-dimen shift)))
                                     (loop for (key value) in
                                           (list (list :width (tex-box-width box))
                                                 (list :height (tex-box-height box))
                                                 (list :depth (tex-box-depth box)))
                                           unless (zerop value)
                                             append (list key (format-dimen value))))
                 :value box :children (tex-box-contents box) :span (tex-box-span box))))
      (setf (node-via node) (tex-box-via box))
      node)))

(defun node-box (node)
  "The box \\lastbox takes from the box or paragraph NODE: a box node's
box, or for a paragraph (one line, docs/tex-fidelity.md) an \\hbox of its
contents."
  (if (eq (node-kind node) :box)
      (node-value node)
      (let ((box (make-tex-box :hbox :contents (node-children node)
                                     :span (node-span node))))
        (setf (tex-box-via box) (node-via node))
        box)))

;;; Where a box goes (§§1075-1078)

(defun append-box (expander box shift)
  "Append BOX to the current list, shifted by SHIFT when moved, and what
that does to the list (§§1076, 679)."
  (append-node expander (box-node box shift))
  (let ((list (current-list expander)))
    (case (mode-kind (list-state-mode list))
      (:vertical (setf (list-state-prev-depth list) (tex-box-depth box))
       (when (eq (list-state-mode list) :vertical) (build-page expander)))
      (:horizontal (setf (list-state-space-factor list) 1000)))))

(defparameter *leaders-glue*
  '((:vertical "vskip" "vfil" "vfill" "vss" "vfilneg")
    (:horizontal "hskip" "hfil" "hfill" "hss" "hfilneg")
    (:math "hskip" "hfil" "hfill" "hss" "hfilneg"))
  "The glue commands that may follow leaders, by kind of mode (§1078).")

(defun append-leaders (expander kind span leader)
  "§1078: the leaders of KIND, read at SPAN, of LEADER (a box or a rule
node) become the glue that follows, or `Leaders not followed by proper
glue' and they are dropped."
  (multiple-value-bind (token meaning) (get-x-nonblank-nonrelax expander)
    (let ((name (and (primitive-p meaning) (primitive-name meaning))))
      (if (and name
               (member name (cdr (assoc (mode-kind (current-mode expander)) *leaders-glue*))
                       :test #'string=))
          (let ((glue (command-glue expander name)))
            (append-node expander
                         (make-node :leaders
                                    :properties (list :kind kind :glue (format-glue glue)
                                                      :command name)
                                    :value glue
                                    :children (list (if (tex-box-p leader)
                                                        (box-node leader)
                                                        leader))
                                    :span span)))
          (progn
            (back-token expander token)
            (tex-error "Leaders not followed by proper glue"
                       :span (and token (token-span token))))))))

(defun box-end (expander context box)
  "TeX's box_end (§1075): BOX goes where CONTEXT says.  A void box is
nothing; a box placed in a list is a box node."
  (if (eq context :append)
      (when box
        (append-box expander box nil))
      (ecase (first context)
        (:setbox
         (destructuring-bind (n global) (rest context)
           ;; \setbox applied \globaldefs when it was read (§1241).
           (set-register (expander-state expander) :box n box
                         :global global :globaldefs nil)))
        (:shift (when box
                  (append-box expander box (second context))))
        (:leaders (when box
                    (destructuring-bind (kind span) (rest context)
                      (append-leaders expander kind span box)))))))

;;; Making a box (§§645, 1079-1087)

(defun scan-spec (expander code context token meaning)
  "TeX's scan_spec (§645): `to' or `spread' and a dimension, then a box
group of CODE and its left brace."
  (let ((spec (cond ((scan-keyword expander "to")
                     (list :exactly (scan-dimen expander)))
                    ((scan-keyword expander "spread")
                     (list :additional (scan-dimen expander)))
                    (t (list :additional 0)))))
    (new-save-level expander code :context context :spec spec
                                  :token token :meaning meaning)
    (scan-left-brace expander)))

(defun take-box-register (expander n)
  "The box in register N, which becomes void at its level (§1079)."
  (let* ((state (expander-state expander))
         (box (register state :box n)))
    (replace-register state :box n nil)
    box))

(defun split-marks (nodes)
  "The marks' token lists among NODES as \\vsplit sees them (§979): those
of the list, and those that TeX's line breaking or an adjusted \\hbox
(§655) would have moved out of a paragraph or box node into it."
  (loop for node in nodes
        append (case (node-kind node)
                 (:tex-mark (list (node-value node)))
                 ((:paragraph :box)
                  (when (or (eq (node-kind node) :paragraph)
                            (tex-box-adjusted (node-value node)))
                    (loop for child in (node-children node)
                          when (eq (node-kind child) :tex-mark)
                            collect (node-value child)))))))

(defun vsplit-box (expander)
  "\\vsplit's operands and box (§§1082, 977-979): the whole box of the
register, which becomes void, and the split marks from its marks; an
\\hbox is an error and gives a void box."
  (let ((n (scan-eight-bit-int expander)))
    (unless (scan-keyword expander "to")
      (tex-error "Missing `to' inserted"))
    (scan-dimen expander)
    (let ((marks (expander-marks expander))
          (box (register (expander-state expander) :box n)))
      (setf (aref marks (mark-index "splitfirstmark")) nil
            (aref marks (mark-index "splitbotmark")) nil)
      (cond ((null box) nil)
            ((eq (box-kind box) :hbox)
             (tex-error (format nil "~A needs a ~A" (esc expander "vsplit")
                                (esc expander "vbox")))
             nil)
            (t
             (let ((found (split-marks (tex-box-contents box))))
               (when found
                 (setf (aref marks (mark-index "splitfirstmark")) (first found)
                       (aref marks (mark-index "splitbotmark")) (car (last found)))))
             (take-box-register expander n))))))

(defun last-box (expander token meaning)
  "\\lastbox (§§1080-1081): the last node of the current list when it is
a box or a paragraph, removed; else a void box.  In math mode, and from
the empty outer vertical list, `You can't use'."
  (let* ((list (current-list expander))
         (mode (list-state-mode list))
         (last (last-node list)))
    (cond ((or (eq (mode-kind mode) :math)
               (and (eq mode :vertical) (null last)))
           (report-illegal-case expander token meaning)
           nil)
          ((and last (member (node-kind last) '(:box :paragraph)))
           (remove-last-node list)
           (node-box last)))))

(defun begin-box (expander token meaning context)
  "TeX's begin_box (§1079) for the make_box command TOKEN with MEANING in
CONTEXT.  \\hbox, \\vbox and \\vtop open their group and inner mode
(with \\everyhbox or \\everyvbox); the others give their box at once."
  (let ((name (primitive-name meaning))
        (state (expander-state expander))
        (span (token-span token)))
    (flet ((finish (box) (box-end expander context box)))
      (cond
        ((string= name "box")
         (finish (given-again (take-box-register expander (scan-eight-bit-int expander))
                              span)))
        ((string= name "copy")
         (finish (given-again (copy-box (register state :box (scan-eight-bit-int expander)))
                              span)))
        ((string= name "lastbox")
         (finish (given-again (last-box expander token meaning) span)))
        ((string= name "vsplit") (finish (given-again (vsplit-box expander) span)))
        ((string= name "hbox")
         ;; §1083: placed (or moved) in vertical mode, an adjusted \hbox.
         (scan-spec expander (if (and (or (eq context :append)
                                          (eq (first context) :shift))
                                      (eq (mode-kind (current-mode expander))
                                          :vertical))
                                 :adjusted-hbox
                                 :hbox)
                    context token meaning)
         (push-nest expander :restricted-horizontal)
         (setf (list-state-space-factor (current-list expander)) 1000)
         (begin-token-list expander (parameter state :everyhbox) :every-hbox))
        (t
         (scan-spec expander (if (string= name "vbox") :vbox :vtop)
                    context token meaning)
         (normal-paragraph expander)
         (push-nest expander :internal-vertical)
         (setf (list-state-prev-depth (current-list expander)) +ignore-depth+)
         (begin-token-list expander (parameter state :everyvbox) :every-vbox))))))

(defun package-box (expander kind)
  "TeX's package (§1086): end the box group of KIND (:HBOX, :VBOX or
:VTOP), make the box and give it to its context."
  (let* ((group (unsave expander))
         (list (pop-nest expander))
         (token (group-record-token group)))
    (box-end expander (group-record-context group)
             (make-tex-box (if (eq kind :hbox) :hbox :vbox)
                           :command (string-downcase (symbol-name kind))
                           :spec (group-record-spec group)
                           :contents (list-nodes list)
                           :span (and token (token-span token))
                           :adjusted (eq (group-record-code group) :adjusted-hbox)))))

(defun scan-box (expander context)
  "TeX's scan_box (§1084): the box of \\setbox, a move or leaders, after
blanks and \\relax; for leaders a rule will do.  Anything else is `A <box>
was supposed to be here' and is read again."
  (multiple-value-bind (token meaning) (get-x-nonblank-nonrelax expander)
    (cond ((make-box-command-p meaning)
           (begin-box expander token meaning context))
          ((and (consp context) (eq (first context) :leaders)
                (primitive-p meaning)
                (member (primitive-name meaning) '("hrule" "vrule") :test #'string=))
           (destructuring-bind (kind span) (rest context)
             (append-leaders expander kind span
                             (rule-node expander (primitive-name meaning)
                                        (token-span token)))))
          (t
           (back-token expander token)
           (tex-error "A <box> was supposed to be here"
                      :span (and token (token-span token)))))))

;;; The commands (§§1073, 1078, 1109-1110)

(define-command ("raise" "lower" "moveleft" "moveright") (expander token meaning)
  ;; scan_normal_dimen, then the box; \raise and \moveleft negate.
  (let ((amount (scan-dimen expander)))
    (scan-box expander (list :shift (if (member name '("raise" "moveleft") :test #'string=)
                                        (- amount)
                                        amount)))))

(define-command ("leaders" "cleaders" "xleaders") (expander token meaning)
  (scan-box expander (list :leaders (intern (string-upcase name) :keyword)
                           (token-span token))))

(define-command ("unhbox" "unhcopy" "unvbox" "unvcopy") (expander token meaning)
  ;; unpackage (§1110): the box's list goes on in the current list, each
  ;; node given the command's span.
  (let* ((n (scan-eight-bit-int expander))
         (box (register (expander-state expander) :box n))
         (copy (member name '("unhcopy" "unvcopy") :test #'string=)))
    (when box
      (if (ecase (mode-kind (current-mode expander))
            ;; Only \unhbox and \unhcopy get here in math: the others
            ;; insert `$' first (§1046).
            (:math t)
            (:vertical (not (eq (box-kind box) :vbox)))
            (:horizontal (not (eq (box-kind box) :hbox))))
          (tex-error "Incompatible list can't be unboxed" :span (token-span token))
          (progn
            (unless copy
              (take-box-register expander n))
            (dolist (node (tex-box-contents box))
              (append-node expander (add-via (copy-node node) (token-span token)))))))))
