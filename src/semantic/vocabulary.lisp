;;;; src/semantic/vocabulary.lisp
;;;;
;;;; Vocabulary entries (docs/vocabulary.md, "Rules"): each names a macro,
;;;; the key of its events, its kind (how its calls become events), where
;;;; its begin is placed, and why it is an entry.  A vocabulary is a set
;;;; of entries checked for consistency when it is made.

(in-package #:cl-ansi-spec/semantic)

(defstruct (entry (:constructor make-entry
                      (name key &key (kind :call) (placement :inline)
                                     closes handler why))
                  (:copier nil))
  "A vocabulary entry: the macro NAME (a string, without escape) whose
calls become events keyed KEY (a keyword).  KIND is :CALL (a :BEGIN when
called, an :END when its body ends), :MARK (one :MARK event), :OPEN (a
:BEGIN; the extent runs to the call of a :CLOSE entry) or :CLOSE (the
:END of the :OPEN entry keyed CLOSES).  PLACEMENT, for a :CALL entry, is
:INLINE (its :BEGIN waits for the first node of its content) or :BLOCK
(placed at once).  HANDLER, when given, replaces the call: a function
(observer expander token arguments) that emits the events itself.  WHY
says why the macro is an entry."
  (name "" :type string :read-only t)
  (key nil :type keyword :read-only t)
  (kind :call :type (member :call :mark :open :close) :read-only t)
  (placement :inline :type (member :inline :block) :read-only t)
  (closes nil :type (or null keyword) :read-only t)
  (handler nil :type (or null function symbol) :read-only t)
  (why "" :type string :read-only t))

(defun entry-mode (entry)
  "How ENTRY's calls are treated: :OBSERVE (the macro expands as usual)
or :REPLACE (its handler stands for the call)."
  (if (entry-handler entry) :replace :observe))

(defstruct (vocabulary (:constructor %make-vocabulary (entries table))
                       (:copier nil))
  "A set of ENTRIES, oldest first, and a TABLE from their names to them."
  (entries '() :type list :read-only t)
  (table nil :type hash-table :read-only t))

(defun make-vocabulary (entries)
  "A vocabulary of ENTRIES.  Names are unique; a :CLOSE entry closes the
key of an :OPEN entry, and only :CLOSE entries close anything."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (entry entries)
      (when (gethash (entry-name entry) table)
        (error "Two vocabulary entries name \\~A." (entry-name entry)))
      (setf (gethash (entry-name entry) table) entry))
    (dolist (entry entries)
      (if (eq (entry-kind entry) :close)
          (unless (find-if (lambda (other)
                             (and (eq (entry-kind other) :open)
                                  (eq (entry-key other) (entry-closes entry))))
                           entries)
            (error "\\~A closes ~S, which no :OPEN entry opens."
                   (entry-name entry) (entry-closes entry)))
          (when (entry-closes entry)
            (error "\\~A is not a :CLOSE entry but closes ~S."
                   (entry-name entry) (entry-closes entry)))))
    (%make-vocabulary (copy-list entries) table)))

(defun find-entry (vocabulary name)
  "The entry of VOCABULARY naming the macro NAME, or NIL."
  (values (gethash name (vocabulary-table vocabulary))))
