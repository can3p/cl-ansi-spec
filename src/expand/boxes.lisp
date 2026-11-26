;;;; src/expand/boxes.lisp
;;;;
;;;; Boxes as main control makes them (TeX: The Program, §§645,
;;;; 1073-1087): \hbox, \vbox and \vtop open a box group and an inner
;;;; mode; at their `}' the box is made and goes where its context says
;;;; (a box register for \setbox, else the current list).  \box, \copy and
;;;; \vsplit take a register's box.  A TEX-BOX has no dimensions of its
;;;; own (docs/tex-fidelity.md, "Not emulated"): \wd, \ht and \dp read 0
;;;; unless assigned.  What a box holds is the event layer's; placing a
;;;; box in a list, \lastbox, leaders and \shipout are events.
;;;;
;;;; A box context (TeX's box_context) is :APPEND, the current list, or
;;;; (:SETBOX n global), a box register.

(in-package #:cl-ansi-spec/expand)

(defstruct (tex-box (:constructor make-tex-box (kind &key spec contents))
                    (:copier nil))
  "A box: KIND :HBOX or :VBOX (\\vtop makes a :VBOX), the SPEC it was made
with (see GROUP-RECORD), its CONTENTS (events, kept by the event layer)
and the dimensions \\wd, \\ht and \\dp assigned to it."
  (kind :hbox :type (member :hbox :vbox) :read-only t)
  (spec nil :read-only t)
  (contents '() :type list)
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

(defun copy-box (box)
  "TeX's copy_node_list of a box register's contents, for \\copy."
  (and box
       (let ((copy (make-tex-box (tex-box-kind box) :spec (tex-box-spec box)
                                                    :contents (copy-list (tex-box-contents box)))))
         (setf (tex-box-width copy) (tex-box-width box)
               (tex-box-height copy) (tex-box-height box)
               (tex-box-depth copy) (tex-box-depth box))
         copy)))

(defun make-box-command-p (meaning)
  "True when MEANING is one of TeX's make_box commands (§1071)."
  (and (primitive-p meaning)
       (member (primitive-name meaning)
               '("box" "copy" "lastbox" "vsplit" "vtop" "vbox" "hbox")
               :test #'string=)
       t))

(defun box-end (expander context box token meaning)
  "TeX's box_end (§1075): BOX, made by TOKEN with MEANING, goes where
CONTEXT says.  A void box placed in a list is nothing; a box placed in a
list is an event."
  (if (eq context :append)
      (when box
        ;; What appending the box does to the list (§§1076, 679); the
        ;; box itself is an event.
        (let ((list (current-list expander)))
          (case (mode-kind (list-state-mode list))
            (:vertical (setf (list-state-prev-depth list) (tex-box-depth box)))
            (:horizontal (setf (list-state-space-factor list) 1000)))
          (setf (list-state-last-node list) (list :other)))
        (hand-on expander token meaning :event))
      (destructuring-bind (setbox n global) context
        (assert (eq setbox :setbox))
        ;; \setbox applied \globaldefs when it was read (§1241).
        (set-register (expander-state expander) :box n box
                      :global global :globaldefs nil))))

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

(defun vsplit-box (expander)
  "\\vsplit's operands and box (§§1082, 977): the whole box of the
register, which becomes void; an \\hbox is an error and gives a void
box.  The split marks are cleared."
  (let ((n (scan-eight-bit-int expander)))
    (unless (scan-keyword expander "to")
      (tex-error "Missing `to' inserted"))
    (scan-dimen expander)
    (let ((marks (expander-marks expander)))
      (setf (aref marks (mark-index "splitfirstmark")) nil
            (aref marks (mark-index "splitbotmark")) nil))
    (let ((box (register (expander-state expander) :box n)))
      (cond ((null box) nil)
            ((eq (box-kind box) :hbox)
             (tex-error (format nil "~A needs a ~A" (esc expander "vsplit")
                                (esc expander "vbox")))
             nil)
            (t (take-box-register expander n))))))

(defun begin-box (expander token meaning context)
  "TeX's begin_box (§1079) for the make_box command TOKEN with MEANING in
CONTEXT.  \\hbox, \\vbox and \\vtop open their group and inner mode
(with \\everyhbox or \\everyvbox); the others give their box at once.
\\lastbox is an event: here it gives a void box."
  (let ((name (primitive-name meaning))
        (state (expander-state expander)))
    (flet ((finish (box) (box-end expander context box token meaning)))
      (cond
        ((string= name "box") (finish (take-box-register expander (scan-eight-bit-int expander))))
        ((string= name "copy")
         (finish (copy-box (register state :box (scan-eight-bit-int expander)))))
        ((string= name "lastbox")
         (hand-on expander token meaning :event)
         (finish nil))
        ((string= name "vsplit") (finish (vsplit-box expander)))
        ((string= name "hbox")
         (scan-spec expander (if (and (eq context :append)
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
  (let ((group (unsave expander)))
    (pop-nest expander)
    (box-end expander (group-record-context group)
             (make-tex-box (if (eq kind :hbox) :hbox :vbox)
                           :spec (group-record-spec group))
             (group-record-token group) (group-record-meaning group))))

(defun scan-box (expander context)
  "TeX's scan_box (§1084): the box of \\setbox (or of a box command's
other contexts), after blanks and \\relax; anything else is `A <box> was
supposed to be here' and is read again."
  (multiple-value-bind (token meaning) (get-x-nonblank-nonrelax expander)
    (if (make-box-command-p meaning)
        (begin-box expander token meaning context)
        (progn
          (back-token expander token)
          (tex-error "A <box> was supposed to be here"
                     :span (and token (token-span token)))))))
