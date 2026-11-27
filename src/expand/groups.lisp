;;;; src/expand/groups.lisp
;;;;
;;;; Groups (TeX: The Program, §§268-284, 1063-1069): every group main
;;;; control opens is a GROUP-RECORD on the reader's save stack (the
;;;; group-boundary kind), with TeX's group code, the line it began on,
;;;; the tokens \aftergroup saved and what a box group needs at its end.
;;;; UNSAVE closes the innermost group and puts its \aftergroup tokens
;;;; back in the order they were saved; OFF-SAVE recovers from a group
;;;; ended by the wrong command.

(in-package #:cl-ansi-spec/expand)

(deftype group-code ()
  "TeX's group codes (§269); :BOTTOM-LEVEL outside every group."
  '(member :bottom-level :simple :hbox :adjusted-hbox :vbox :vtop :align
    :no-align :output :math :disc :insert :vcenter :math-choice
    :semi-simple :math-shift :math-left))

(defstruct (group-record (:constructor make-group-record
                             (code line &key context spec token meaning))
                         (:copier nil))
  "One open group.  CODE is its GROUP-CODE, LINE the input line it began
on.  AFTER holds the tokens \\aftergroup saved, newest first.  A box
group keeps the box's CONTEXT (see BOX-END), its SPEC (:EXACTLY or
:ADDITIONAL and a dimension, TeX's saved(1) and saved(2)), and the TOKEN
of the box command with its MEANING."
  (code :simple :type group-code :read-only t)
  (line 0 :type integer :read-only t)
  (after '() :type list)
  (context nil :read-only t)
  (spec nil :read-only t)
  (token nil :read-only t)
  (meaning nil :read-only t))

(defun current-group (expander)
  "The innermost open GROUP-RECORD of EXPANDER, or NIL."
  (let ((kind (current-group-kind (expander-tex expander))))
    (and (group-record-p kind) kind)))

(defun current-group-code (expander)
  "TeX's cur_group: the code of the innermost group, or :BOTTOM-LEVEL."
  (let ((group (current-group expander)))
    (if group (group-record-code group) :bottom-level)))

(defun new-save-level (expander code &rest options
                       &key context spec token meaning)
  "TeX's new_save_level (§274): open a group of CODE.  OPTIONS are kept
in the record (see GROUP-RECORD)."
  (declare (ignore context spec token meaning))
  (begin-group (expander-tex expander)
               (apply #'make-group-record code
                      (current-line-number (expander-input expander))
                      options)))

(defun unsave (expander)
  "TeX's unsave (§281): close the innermost group, restoring what it
assigned locally, and put back the tokens \\aftergroup saved in it, to be
read in the order they were saved.  Returns the group's record."
  (let ((group (end-group (expander-tex expander))))
    (when (group-record-p group)
      ;; Each token is backed up as TeX does, newest first, so that the
      ;; oldest is read first.
      (dolist (token (group-record-after group))
        (back-token expander token)))
    group))

(defun save-for-after (expander token)
  "TeX's save_for_after (§280): TOKEN is read after the innermost group
ends; outside every group it is forgotten."
  (let ((group (current-group expander)))
    (when group
      (push token (group-record-after group)))))

(defun off-save (expander token meaning)
  "TeX's off_save (§1064): TOKEN with MEANING tried to end a group of
another kind.  Outside every group it is `Extra' and dropped; otherwise
what ends the current group is inserted before TOKEN, which is read
again."
  (let ((code (current-group-code expander))
        (span (and token (token-span token))))
    (if (eq code :bottom-level)
        (tex-error "Extra" :context (meaning-text expander token meaning)
                           :span span)
        (progn
          (back-token expander token)
          (multiple-value-bind (tokens shown)
              (case code
                (:semi-simple
                 (values (list (make-cs-token
                                (frozen-control-sequence expander "endgroup")
                                span))
                         (esc expander "endgroup")))
                (:math-shift
                 (values (list (make-character-token (char-code #\$)
                                                     +math-shift+ span))
                         "$"))
                (:math-left
                 (values (list (make-cs-token
                                (frozen-control-sequence expander "right") span)
                               (make-character-token (char-code #\.) +other+
                                                     span))
                         (esc expander "right.")))
                (t (values (list (make-character-token (char-code #\})
                                                       +end-group+ span))
                           "}")))
            (insert-tokens expander tokens)
            (tex-error (format nil "Missing ~A inserted" shown) :span span))))))

(defun extra-right-brace-error (expander token)
  "TeX's extra_right_brace (§1069): a `}' ends a group begun by
\\begingroup, `$' or \\left.  The brace is dropped; the group stays
open."
  (incf (expander-align-state expander))
  (tex-error "Extra }, or forgotten"
             :context (ecase (current-group-code expander)
                        (:semi-simple (esc expander "endgroup"))
                        (:math-shift "$")
                        (:math-left (esc expander "right")))
             :span (token-span token)))

(defun handle-right-brace (expander token)
  "TeX's handle_right_brace (§1085) for the groups main control opens; the
groups of events and alignments end in their own steps."
  (let ((code (current-group-code expander)))
    (ecase code
      (:simple (unsave expander))
      (:bottom-level
       (tex-error "Too many }'s" :span (token-span token)))
      ((:semi-simple :math-shift :math-left)
       (extra-right-brace-error expander token))
      ((:hbox :adjusted-hbox) (package-box expander :hbox))
      (:vbox (end-graf expander) (package-box expander :vbox))
      (:vtop (end-graf expander) (package-box expander :vtop))
      (:math (unsave expander) (pop-nest expander)))))
