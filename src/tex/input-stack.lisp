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
SKIP-HOOK is given to every file reader (see FILE-READER)."
  (state nil :type tex-state :read-only t)
  (resolver nil :type function :read-only t)
  (skip-hook nil :type (or null function) :read-only t)
  (levels '() :type list))

(define-condition input-file-missing (error)
  ((name :initarg :name :reader input-file-missing-name))
  (:report (lambda (condition stream)
             (format stream "Input file ~S not found."
                     (input-file-missing-name condition))))
  (:documentation "Signalled when the resolver finds no file for a name."))

(defun directory-resolver (directory)
  "Return a resolver for the files in DIRECTORY.  As TeX does, a name
without a type is tried with type tex first.  Sources are named by their
file name relative to DIRECTORY."
  (lambda (name)
    (flet ((try (file-name)
             (let ((pathname (merge-pathnames (uiop:parse-unix-namestring file-name)
                                              directory)))
               (when (and (not (wild-pathname-p pathname))
                          (uiop:file-exists-p pathname))
                 (open-line-source file-name pathname)))))
      (or (and (member (pathname-type (uiop:parse-unix-namestring name))
                       '(nil :unspecific))
               (try (concatenate 'string name ".tex")))
          (try name)))))

(defun make-input-stack (state &key (resolver (directory-resolver (spec-directory)))
                                    skip-hook)
  "Return an empty input stack reading with the equivalents of STATE.
RESOLVER defaults to the pristine spec sources."
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

(defun push-tokens (stack tokens &optional (kind :inserted))
  "Insert the list TOKENS to be read next, as a level of KIND."
  (push (make-token-level (copy-list tokens) kind) (input-stack-levels stack))
  tokens)

(defun back-input (stack token)
  "Put TOKEN back so that it is the next token read from STACK.
Exhausted token lists on top are removed first, as TeX does."
  (loop for top = (first (input-stack-levels stack))
        while (and (token-level-p top) (null (token-level-tokens top)))
        do (pop (input-stack-levels stack)))
  (push-tokens stack (list token) :backed-up)
  token)

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
           (if token
               (return token)
               (pop (input-stack-levels stack)))))))))

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
