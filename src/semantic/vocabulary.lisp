;;;; src/semantic/vocabulary.lisp
;;;;
;;;; Vocabulary entries (docs/vocabulary.md, "Rules"): each names a macro,
;;;; the key of its events, its kind (how its calls become events), where
;;;; its begin is placed, and why it is an entry.  A vocabulary is a set
;;;; of entries checked for consistency when it is made, with the classes
;;;; that say why the other macros of the sources are not entries; the
;;;; spec's own is read from a data file (LOAD-VOCABULARY).

(in-package #:cl-ansi-spec/semantic)

(defstruct (entry (:constructor make-entry
                      (name key &key (kind :call) (placement :inline)
                                     closes handler local why))
                  (:copier nil))
  "A vocabulary entry: the macro NAME (a string, without escape) whose
calls become events keyed KEY (a keyword).  KIND is :CALL (a :BEGIN when
called, an :END when its body ends), :WRAPPER (its call gives its key and
arguments to the next :CALL entry's call, its tail call, whose arguments
follow them), :MARK (one :MARK event), :OPEN (a :BEGIN; the extent runs
to the call of a :CLOSE entry) or :CLOSE (the :END of the :OPEN entry
keyed CLOSES).  PLACEMENT, for a :CALL entry, is :INLINE (its :BEGIN waits for the first node of its content) or :BLOCK
(placed at once).  HANDLER, when given, replaces the call: a function
(observer expander entry token arguments) that emits the events itself.
LOCAL is true for a macro that the macros using it define anew, in
several places (\\entry, setup-document.tex:132-152): its
redefinitions are not reported.  WHY says why the macro is an entry."
  (name "" :type string :read-only t)
  (key nil :type keyword :read-only t)
  (kind :call :type (member :call :wrapper :mark :open :close) :read-only t)
  (placement :inline :type (member :inline :block) :read-only t)
  (closes nil :type (or null keyword) :read-only t)
  (handler nil :type (or null function symbol) :read-only t)
  (local nil :type boolean :read-only t)
  (why "" :type string :read-only t))

(defun entry-mode (entry)
  "How ENTRY's calls are treated: :OBSERVE (the macro expands as usual)
or :REPLACE (its handler stands for the call)."
  (if (entry-handler entry) :replace :observe))

(defstruct (macro-class (:constructor make-macro-class
                            (kind &key names files why))
                        (:copier nil))
  "Macros that are not entries, and why: those called NAMES (spelt as
the survey spells them, \"\\\\tt\" or an active \"~\") and those defined in FILES (file names such as \"setup-terms.tex\").
KIND is :PRESENTATIONAL (layout and fonts, no meaning), :PHRASE (it
expands to text and entries only), :REFERENCE-NAME (a name references take as
argument) or :OPTION (a flag of the options)."
  (kind nil :type (member :presentational :phrase :reference-name :option)
        :read-only t)
  (names '() :type list :read-only t)
  (files '() :type list :read-only t)
  (why "" :type string :read-only t))

(defstruct (vocabulary (:constructor %make-vocabulary (entries table classes))
                       (:copier nil))
  "A set of ENTRIES, oldest first, a TABLE from their names to them, and
the CLASSES of the other macros."
  (entries '() :type list :read-only t)
  (table nil :type hash-table :read-only t)
  (classes '() :type list :read-only t))

(defun make-vocabulary (entries &key classes)
  "A vocabulary of ENTRIES and the macro CLASSES.  Names are unique; a
:CLOSE entry closes the key of an :OPEN entry, and only :CLOSE entries
close anything."
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
    (%make-vocabulary (copy-list entries) table (copy-list classes))))

(defun find-entry (vocabulary name)
  "The entry of VOCABULARY naming the macro NAME, or NIL."
  (values (gethash name (vocabulary-table vocabulary))))

(defun classify-macro (vocabulary name file)
  "What VOCABULARY makes of the macro NAME (as the survey spells it, with
its escape: \"\\\\term\"), defined in FILE (NIL when the sources do not
define it): :ENTRY when an entry names it, else the kind of the class
naming it, else that of the class naming FILE, else NIL.  A second value
is true when the answer is ambiguous: an entry also named by a class, or
two classes naming it (or its file)."
  (flet ((classes (key value)
           (remove-if-not (lambda (class)
                            (member value (funcall key class) :test #'string=))
                          (vocabulary-classes vocabulary))))
    (let ((entry (and (> (length name) 1) (char= (char name 0) #\\)
                      (find-entry vocabulary (subseq name 1))))
          (by-name (classes #'macro-class-names name))
          (by-file (and file (classes #'macro-class-files file))))
      (cond (entry (values :entry (and by-name t)))
            (by-name (values (macro-class-kind (first by-name)) (and (rest by-name) t)))
            (by-file (values (macro-class-kind (first by-file)) (and (rest by-file) t)))
            (t nil)))))

;;; The data file

(defun read-vocabulary-forms (pathname)
  "The forms of the vocabulary file PATHNAME, read without evaluation,
symbols in this package."
  (with-open-file (in pathname :external-format :utf-8)
    (with-standard-io-syntax
      (let ((*read-eval* nil)
            (*package* (find-package '#:cl-ansi-spec/semantic)))
        (loop for form = (read in nil in)
              until (eq form in)
              collect form)))))

(defun load-vocabulary (pathname)
  "The vocabulary of the data file PATHNAME: (:ENTRY name key options...)
forms, MAKE-ENTRY's arguments, a handler named by a symbol, and
(:CLASS kind options...) forms, MAKE-MACRO-CLASS's.  Every form has a
non-empty :WHY."
  (let ((entries '()) (classes '()))
    (dolist (form (read-vocabulary-forms pathname))
      (let ((options (case (and (consp form) (first form))
                       (:entry (cdddr form))
                       (:class (cddr form))
                       (t (error "Not a vocabulary form: ~S" form)))))
        (unless (and (listp options) (evenp (length options)))
          (error "Not a vocabulary form: ~S" form))
        (unless (plusp (length (getf options :why "")))
          (error "Vocabulary form without a reason: ~S" form))
        (let ((handler (getf options :handler)))
          (when (and handler (not (fboundp handler)))
            (error "Vocabulary form with an undefined handler: ~S" form))))
      (ecase (first form)
        (:entry (push (apply #'make-entry (rest form)) entries))
        (:class (push (apply #'make-macro-class (rest form)) classes))))
    (make-vocabulary (nreverse entries) :classes (nreverse classes))))

(defun spec-vocabulary ()
  "The vocabulary of the spec, from src/semantic/vocabulary.sexp."
  (load-vocabulary (asdf:system-relative-pathname
                    "cl-ansi-spec" "src/semantic/vocabulary.sexp")))
