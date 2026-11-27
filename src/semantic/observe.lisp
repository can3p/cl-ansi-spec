;;;; src/semantic/observe.lisp
;;;;
;;;; Observing a job (docs/vocabulary.md, "Rules"): OBSERVE-VOCABULARY
;;;; sets the expander's observers so that the calls of a vocabulary's
;;;; macros, recognised by their meanings, become markers.  An inline
;;;; :BEGIN waits, pending, for the first node of its content; every
;;;; other marker is placed at once, after what is pending.

(in-package #:cl-ansi-spec/semantic)

(defstruct (report (:constructor make-report
                       (kind name span &key previous-span previous-name))
                   (:copier nil))
  "Something the vocabulary did not expect.  KIND is :REDEFINED (the
macro NAME, an entry's, was defined again at SPAN by another definition
than the last one, at PREVIOUS-SPAN, NIL for the format), :SHARED (the
meaning given to NAME at SPAN already belongs to the entry of
PREVIOUS-NAME, which keeps it) or :UNBALANCED (a call of NAME's entry
ended at SPAN in another list than the one its begin, from the call at
PREVIOUS-SPAN, went to: the entry must be :BLOCK, or observed elsewhere)."
  (kind nil :type (member :redefined :shared :unbalanced) :read-only t)
  (name "" :type string :read-only t)
  (span nil :read-only t)
  (previous-span nil :read-only t)
  (previous-name nil :type (or null string) :read-only t))

(defstruct (observer (:constructor %make-observer (vocabulary))
                     (:copier nil))
  "What the semantic layer keeps about one job: its VOCABULARY; MEANINGS,
an EQ table from the macros attached to an entry to that entry;
DEFINITIONS, from an entry's name to (meaning . span) of its last
definition seen; PENDING inline begins, (event span activation) newest
first; and REPORT-LIST, newest first."
  (vocabulary nil :type vocabulary :read-only t)
  (meanings (make-hash-table :test #'eq) :type hash-table :read-only t)
  (definitions (make-hash-table :test #'equal) :type hash-table :read-only t)
  (pending '() :type list)
  (report-list '() :type list))

(defstruct (activation (:constructor make-activation (entry span end-span))
                       (:copier nil))
  "A call of a :CALL ENTRY at SPAN whose body ends at END-SPAN; LIST is
the list its begin went to, once placed.  The expander's tag for it."
  (entry nil :type entry :read-only t)
  (span nil :read-only t)
  (end-span nil :read-only t)
  (list nil))

(defun observer-reports (observer)
  "The reports of OBSERVER's job, oldest first."
  (reverse (observer-report-list observer)))

(defun observe-vocabulary (expander vocabulary)
  "Observe VOCABULARY in EXPANDER's job, from now on: the macros its
entries name that are defined already (by the format) are attached to
their entries, and the expander's call, level-end, definition and append
observers are set; none may be set already.  Returns the OBSERVER."
  (when (or (expander-call-observer expander) (expander-level-end-observer expander)
            (expander-definition-observer expander) (expander-append-observer expander))
    (error "The expander has observers already."))
  (let ((observer (%make-observer vocabulary))
        (state (expander-state expander)))
    (dolist (entry (vocabulary-entries vocabulary))
      (let ((meaning (meaning state (intern-control-sequence (es-tex state)
                                                             (entry-name entry)))))
        (when meaning
          (note-definition observer entry meaning nil))))
    (setf (expander-call-observer expander)
          (lambda (expander token macro arguments)
            (observe-call observer expander token macro arguments))
          (expander-level-end-observer expander)
          (lambda (expander activation)
            (end-call observer expander activation))
          (expander-definition-observer expander)
          (lambda (expander control-sequence meaning span)
            (declare (ignore expander))
            (let ((entry (find-entry vocabulary (control-sequence-name control-sequence))))
              (when entry
                (note-definition observer entry meaning span))))
          (expander-append-observer expander)
          (lambda (expander node list)
            (unless (or (null (observer-pending observer)) (content-neutral-p node))
              (place-pending observer expander list))))
    observer))

;;; Meanings

(defun note-definition (observer entry meaning span)
  "ENTRY's macro got MEANING at SPAN (NIL: in the format): report a
redefinition, and attach MEANING to ENTRY when it is a macro."
  (let* ((name (entry-name entry))
         (previous (gethash name (observer-definitions observer))))
    ;; A definition run again (one a macro makes when called) is not
    ;; another one.
    (when (and previous (not (eq (car previous) meaning))
               (not (equalp span (cdr previous))))
      (push (make-report :redefined name span :previous-span (cdr previous))
            (observer-report-list observer)))
    (setf (gethash name (observer-definitions observer)) (cons meaning span))
    (when (macro-p meaning)
      (let ((owner (gethash meaning (observer-meanings observer))))
        (cond ((null owner)
               (setf (gethash meaning (observer-meanings observer)) entry))
              ((not (eq owner entry))
               (push (make-report :shared name span :previous-name (entry-name owner))
                     (observer-report-list observer))))))))

;;; Calls

(defun observe-call (observer expander token macro arguments)
  "The call observer: when MACRO belongs to an entry, emit or hold its
events and return the expander's action and tag (see OBSERVE-VOCABULARY)."
  (let ((entry (gethash macro (observer-meanings observer)))
        (span (token-span token)))
    (cond ((null entry) nil)
          ((entry-handler entry)
           (funcall (entry-handler entry) observer expander token arguments)
           :replace)
          (t
           (let ((key (entry-key entry)))
             (ecase (entry-kind entry)
               (:call
                (let ((event (list :begin key :arguments arguments))
                      (activation (make-activation entry span
                                                   (body-end-span macro arguments span))))
                  (if (eq (entry-placement entry) :inline)
                      (push (list event span activation) (observer-pending observer))
                      (setf (activation-list activation)
                            (emit-event observer expander event :span span)))
                  (values nil activation)))
               (:mark
                (emit-event observer expander (list :mark key :arguments arguments)
                            :span span)
                nil)
               (:open
                (emit-event observer expander (list :begin key :arguments arguments)
                            :span span)
                nil)
               (:close
                (emit-event observer expander
                            (list :end (entry-closes entry) :arguments arguments)
                            :span span)
                nil)))))))

(defun end-call (observer expander activation)
  "The level-end observer: the body of ACTIVATION's call has ended.  Its
:END goes to the current list, which should be the list its begin went
to."
  (let ((entry (activation-entry activation))
        (span (activation-end-span activation)))
    (emit-event observer expander (list :end (entry-key entry)) :span span)
    (unless (eq (activation-list activation) (current-list expander))
      (push (make-report :unbalanced (entry-name entry) span
                         :previous-span (activation-span activation))
            (observer-report-list observer)))))

(defun body-end-span (macro arguments span)
  "The span of the last token of MACRO's body with ARGUMENTS substituted,
or SPAN, the call's, when the body is empty."
  (dolist (element (reverse (macro-body macro)) span)
    (let ((token (if (integerp element)
                     (car (last (nth (1- element) arguments)))
                     element)))
      (when token
        (return (token-span token))))))

;;; Placing markers

(defun content-neutral-p (node)
  "True when NODE does not end the wait of a pending begin: a marker, or
what TeX adds by itself when a paragraph begins (its \\parskip glue,
its indentation), so that an inline entry used in vertical mode begins
inside the paragraph it starts."
  (or (marker-p node)
      (eq (node-kind node) :indent)
      (and (eq (node-kind node) :glue)
           (equal (getf (node-properties node) :command) "parskip"))))

(defun place-pending (observer expander list)
  "Append OBSERVER's pending begins to LIST, oldest first."
  (let ((pending (reverse (observer-pending observer))))
    (setf (observer-pending observer) '())
    (loop for (event span activation) in pending
          do (append-marker expander event :span span :list list)
             (when activation
               (setf (activation-list activation) list)))))

(defun emit-event (observer expander event &key span)
  "Append a marker for EVENT at SPAN to EXPANDER's current list, after
OBSERVER's pending begins; return that list.  Replace handlers emit
their events with it."
  (let ((list (current-list expander)))
    (place-pending observer expander list)
    (append-marker expander event :span span :list list)
    list))
