;;;; src/tex/input-stack.lisp
;;;;
;;;; TeX's input stack: one stack whose levels are files being read and
;;;; token lists being replayed (macro bodies, inserted lists, tokens put
;;;; back with BACK-INPUT).  Tokens always come from the top level; an
;;;; exhausted level is removed when the next token is requested.
;;;;
;;;; Files are found through a pluggable resolver, so that later stages can
;;;; supply files that only exist after a TeX run (chap-N.fig, .toc, ...).

(in-package #:cl-ansi-spec/tex)

(defstruct (token-level (:constructor make-token-level (tokens kind)))
  "A token list being read.  KIND says where it comes from, e.g.
:BACKED-UP, :INSERTED or :MACRO."
  (tokens '() :type list)
  (kind nil :read-only t))

(defstruct (input-stack (:constructor %make-input-stack
                            (state resolver skip-hook)))
  "TeX's input stack.  RESOLVER maps a file name to a LINE-SOURCE or NIL;
SKIP-HOOK is given to every file reader (see FILE-READER).  FILE-END-HOOK,
if not NIL, is called with the stack and the file's name each time a file
has been read to its end and removed; it may push tokens, which are read
next (TeX checks for runaway text there, §362)."
  (state nil :type tex-state :read-only t)
  (resolver nil :type function :read-only t)
  (skip-hook nil :type (or null function) :read-only t)
  (file-end-hook nil :type (or null function))
  (levels '() :type list))

(define-condition input-file-missing (error)
  ((name :initarg :name :reader input-file-missing-name))
  (:report (lambda (condition stream)
             (format stream "Input file ~S not found."
                     (input-file-missing-name condition))))
  (:documentation "Signalled when the resolver finds no file for a name."))

(defun directory-resolver (&rest directories)
  "Return a resolver for the files in DIRECTORIES, looked up in order with
FIND-INPUT-FILE: type tex is tried first for a name without one, unsafe
names never resolve, and a name found in two directories signals
AMBIGUOUS-INPUT-FILE.  Sources are named by their file name relative to
their directory."
  (lambda (name)
    (multiple-value-bind (file-name pathname) (find-input-file name directories)
      (and file-name (open-line-source file-name pathname)))))

(defun make-input-stack (state &key (resolver (apply #'directory-resolver
                                                     (source-search-path)))
                                    skip-hook)
  "Return an empty input stack reading with the equivalents of STATE.
RESOLVER defaults to the source search path: the spec tree, then the
vendored plain TeX format."
  (%make-input-stack state resolver skip-hook))

(defun push-source (stack source)
  "Start reading the line source SOURCE on top of STACK."
  (push (make-file-reader source (input-stack-state stack)
                          :skip-hook (input-stack-skip-hook stack))
        (input-stack-levels stack))
  source)

(defun push-file (stack name)
  "Start reading the file NAME, as found by the resolver of STACK.
Signal INPUT-FILE-MISSING if there is none."
  (push-source stack (or (funcall (input-stack-resolver stack) name)
                         (error 'input-file-missing :name name))))

(defun pop-exhausted-token-lists (stack)
  "Remove the exhausted token lists on top of STACK, as TeX does before it
backs up a token or starts a macro body, so that tail calls do not grow
the stack.  An exhausted :V-TEMPLATE list stays: its end is significant
to alignments."
  (loop for top = (first (input-stack-levels stack))
        while (and (token-level-p top) (null (token-level-tokens top))
                   (not (eq (token-level-kind top) :v-template)))
        do (pop (input-stack-levels stack))))

(defun push-tokens (stack tokens &optional (kind :inserted))
  "Insert the list TOKENS to be read next, as a level of KIND, after
removing exhausted token lists.  TOKENS is copied, never modified.
Returns no values."
  (pop-exhausted-token-lists stack)
  (push (make-token-level (copy-list tokens) kind) (input-stack-levels stack))
  (values))

(defun back-input (stack token)
  "Put TOKEN back so that it is the next token read from STACK."
  (push-tokens stack (list token) :backed-up)
  token)

(defun end-current-file (stack)
  "Make the innermost file of STACK end once its current line is read
(TeX's \\endinput, §362).  Does nothing outside every file."
  (let ((reader (find-if #'file-reader-p (input-stack-levels stack))))
    (when reader
      (setf (file-reader-force-eof reader) t))))

(defun next-token (stack)
  "Return the next token of STACK, or NIL once all its input is read.
Exhausted levels (finished token lists, files at their end) are removed."
  (loop
    (let ((top (first (input-stack-levels stack))))
      (etypecase top
        (null (return nil))
        (token-level
         (if (token-level-tokens top)
             (return (pop (token-level-tokens top)))
             (pop (input-stack-levels stack))))
        (file-reader
         (let ((token (next-file-token top (input-stack-state stack))))
           (cond (token (return token))
                 (t (pop (input-stack-levels stack))
                    (let ((hook (input-stack-file-end-hook stack)))
                      (when hook
                        (funcall hook stack (file-reader-name top))))))))))))

(defun peek-token (stack)
  "Return the next token of STACK without consuming it, or NIL."
  (let ((token (next-token stack)))
    (when token
      (back-input stack token))
    token))

(defun input-depth (stack)
  "Return the number of levels on STACK."
  (length (input-stack-levels stack)))

(defun current-file-name (stack)
  "Return the name of the innermost file being read, or NIL."
  (let ((reader (find-if #'file-reader-p (input-stack-levels stack))))
    (and reader (file-reader-name reader))))
