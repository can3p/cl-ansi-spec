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

(defstruct (token-level (:constructor make-token-level (tokens kind &optional tag)))
  "A token list being read.  KIND says where it comes from, e.g.
:BACKED-UP, :INSERTED or :MACRO; TAG, if not NIL, is given to the stack's
LEVEL-END-HOOK when the level is removed."
  (tokens '() :type list)
  (kind nil :read-only t)
  (tag nil :read-only t))

(defstruct (input-stack (:constructor %make-input-stack
                            (state resolver skip-hook)))
  "TeX's input stack.  RESOLVER maps a file name to a LINE-SOURCE or NIL;
SKIP-HOOK is given to every file reader (see FILE-READER).  FILE-END-HOOK,
if not NIL, is called with the stack and the file's name each time a file
has been read to its end and removed; it may push tokens, which are read
next (TeX checks for runaway text there, §362).  U-TEMPLATE-END-HOOK, if
not NIL, is called with the stack each time an exhausted :U-TEMPLATE
list is removed (TeX's end_token_list, §324).  LEVEL-END-HOOK, if not
NIL, is called with the stack and the level's tag each time a token list
with a tag is removed."
  (state nil :type tex-state :read-only t)
  (resolver nil :type function :read-only t)
  (skip-hook nil :type (or null function) :read-only t)
  (file-end-hook nil :type (or null function))
  (u-template-end-hook nil :type (or null function))
  (level-end-hook nil :type (or null function))
  ;; TeX's force_eof, set by \\endinput: the next file to finish a line
  ;; ends there.
  (force-eof nil :type boolean)
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

(defun pop-token-level (stack)
  "Remove the exhausted token list on top of STACK; at the end of a
:U-TEMPLATE list, call the stack's U-TEMPLATE-END-HOOK, and for a list
with a tag its LEVEL-END-HOOK."
  (let ((level (pop (input-stack-levels stack)))
        (hook (input-stack-u-template-end-hook stack))
        (end-hook (input-stack-level-end-hook stack)))
    (when (and end-hook (token-level-tag level))
      (funcall end-hook stack (token-level-tag level)))
    (when (and hook (eq (token-level-kind level) :u-template))
      (funcall hook stack))))

(defun pop-exhausted-token-lists (stack)
  "Remove the exhausted token lists on top of STACK, as TeX does before it
backs up a token or starts a macro body, so that tail calls do not grow
the stack.  An exhausted :V-TEMPLATE list stays: its end is significant
to alignments, and an exhausted :READ-LINE list stays until
END-READ-LINE removes it."
  (loop for top = (first (input-stack-levels stack))
        while (and (token-level-p top) (null (token-level-tokens top))
                   (not (member (token-level-kind top) '(:v-template :read-line))))
        do (pop-token-level stack)))

(defun push-tokens (stack tokens &optional (kind :inserted) tag)
  "Insert the list TOKENS to be read next, as a level of KIND.  For a
:MACRO body the exhausted token lists are removed first, as TeX's
macro_call does (§390); other lists (TeX's begin_token_list and
back_list) go on top of them, which ends a u template later.  TOKENS is
copied, never modified.  A non-NIL TAG is given to the stack's
LEVEL-END-HOOK when the level is removed.  Returns no values."
  (when (eq kind :macro)
    (pop-exhausted-token-lists stack))
  (push (make-token-level (copy-list tokens) kind tag) (input-stack-levels stack))
  (values))

(defun resolve-input (stack name)
  "The line source the resolver of STACK finds for the file NAME, or NIL;
as PUSH-FILE finds it, but nothing is pushed (TeX's a_open_in for
\\openin)."
  (funcall (input-stack-resolver stack) name))

(defun push-read-line (stack tokens)
  "TeX's begin_file_reading for a line of \\read (§483): TOKENS, the tokens
of one line, are read next.  Once they are read, NEXT-TOKEN returns NIL
(TeX's `\\read line has ended', §360) until END-READ-LINE removes the
level.  Returns no values."
  (push-tokens stack tokens :read-line))

(defun open-level-tags (stack)
  "The tags of the token-list levels of STACK not yet removed, innermost
first."
  (loop for level in (input-stack-levels stack)
        when (and (token-level-p level) (token-level-tag level))
          collect (token-level-tag level)))

(defun reading-line-p (stack)
  "True when the top level of STACK is a line PUSH-READ-LINE pushed, so
that the token last read came from it (TeX's 1 <= name <= 17, §339)."
  (let ((top (first (input-stack-levels stack))))
    (and (token-level-p top) (eq (token-level-kind top) :read-line))))

(defun end-read-line (stack)
  "TeX's end_file_reading for a line of \\read: remove the exhausted
lists on top of STACK and the line PUSH-READ-LINE pushed below them."
  (pop-exhausted-token-lists stack)
  (unless (reading-line-p stack)
    (error "No line of \\read is being read."))
  (pop (input-stack-levels stack))
  (values))

(defun back-input (stack token)
  "TeX's back_input (§325): remove the exhausted token lists, then put
TOKEN back so that it is the next token read from STACK."
  (pop-exhausted-token-lists stack)
  (push-tokens stack (list token) :backed-up)
  token)

(defun end-current-file (stack)
  "TeX's \\endinput (§362): the next file of STACK to finish a line ends
there.  As TeX's force_eof is one global flag, after `\\endinput\\input f'
on one line that file is f."
  (setf (input-stack-force-eof stack) t))

(defun next-token (stack)
  "Return the next token of STACK, or NIL once all its input is read, or
once the line on top that PUSH-READ-LINE pushed is read.  Exhausted
levels (finished token lists, files at their end) are removed."
  (loop
    (let ((top (first (input-stack-levels stack))))
      (etypecase top
        (null (return nil))
        (token-level
         (cond ((token-level-tokens top)
                (return (pop (token-level-tokens top))))
               ((eq (token-level-kind top) :read-line)
                (return nil))
               (t (pop-token-level stack))))
        (file-reader
         (let ((token (next-file-token top (input-stack-state stack)
                                       (lambda ()
                                         (shiftf (input-stack-force-eof stack) nil)))))
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

(defun v-template-ended-p (stack)
  "True when the token just read ended the :V-TEMPLATE list on STACK:
below exhausted token lists of other kinds, the next level is that list,
exhausted (TeX's check in do_endv, §1131)."
  (let ((level (find-if-not (lambda (level)
                              (and (token-level-p level)
                                   (null (token-level-tokens level))
                                   (not (eq (token-level-kind level) :v-template))))
                            (input-stack-levels stack))))
    (and (token-level-p level)
         (eq (token-level-kind level) :v-template)
         (null (token-level-tokens level)))))

(defun input-depth (stack)
  "Return the number of levels on STACK."
  (length (input-stack-levels stack)))

(defun current-file-name (stack)
  "Return the name of the innermost file being read, or NIL."
  (let ((reader (find-if #'file-reader-p (input-stack-levels stack))))
    (and reader (file-reader-name reader))))

(defun current-line-number (stack)
  "Return the number of the line last read from the innermost file being
read (TeX's line, shown by \\inputlineno), or 0 when no file is open."
  (let ((reader (find-if #'file-reader-p (input-stack-levels stack))))
    (if reader
        (line-source-line-number (file-reader-source reader))
        0)))
