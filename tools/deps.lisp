;;;; tools/deps.lisp
;;;;
;;;; Fetch the dependencies pinned in tools/deps.sexp into .deps/.
;;;; Idempotent and offline-friendly: the network is only used when a
;;;; pinned commit is not available locally.  Usage: make deps

(load (merge-pathnames "setup.lisp" *load-truename*))

(in-package #:cl-ansi-spec.tools)

(defun run-git (arguments)
  "Run git with ARGUMENTS and return its trimmed output.  Signal an error
if git fails.  Git never prompts for credentials."
  (string-trim '(#\Space #\Newline)
               (uiop:run-program (list* "env" "GIT_TERMINAL_PROMPT=0" "git" arguments)
                                 :input nil
                                 :output :string
                                 :error-output *error-output*)))

(defun git (directory &rest arguments)
  "Run git with ARGUMENTS on the repository checked out in DIRECTORY.
The repository is named explicitly, so git can never fall back to an
enclosing repository (such as this project) if DIRECTORY is broken."
  (run-git (list* (concatenate 'string "--git-dir="
                               (uiop:native-namestring
                                (merge-pathnames ".git/" directory)))
                  (concatenate 'string "--work-tree="
                               (uiop:native-namestring directory))
                  arguments)))

(defun git-succeeds-p (directory &rest arguments)
  "Run git with ARGUMENTS on DIRECTORY and return true iff it succeeded."
  (handler-case (progn (apply #'git directory arguments) t)
    (uiop:subprocess-error () nil)))

(defun head-commit (directory)
  "Return the commit checked out in DIRECTORY, or NIL if it is not a
usable git checkout (e.g. a clone that was interrupted)."
  (and (uiop:directory-exists-p (merge-pathnames ".git/" directory))
       (handler-case (git directory "rev-parse" "--verify" "--quiet" "HEAD")
         (uiop:subprocess-error () nil))))

(defun clone (url directory)
  "Clone URL into DIRECTORY, first removing any broken leftover there
(e.g. from an interrupted clone)."
  (format t "~&Cloning ~A~%" url)
  (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore)
  (ensure-directories-exist *deps-directory*)
  (run-git (list "clone" "--quiet" url (uiop:native-namestring directory))))

(defun ensure-dependency (name url commit)
  "Ensure .deps/NAME/ is a checkout of URL at COMMIT."
  (let ((directory (merge-pathnames (concatenate 'string name "/") *deps-directory*)))
    (unless (head-commit directory)
      (clone url directory))
    (unless (string= commit (head-commit directory))
      (format t "~&Checking out ~A at ~A~%" name commit)
      (unless (git-succeeds-p directory "checkout" "--quiet" "--detach" commit)
        (git directory "fetch" "--quiet" "origin" commit)
        (git directory "checkout" "--quiet" "--detach" commit)))
    (let ((actual (head-commit directory)))
      (unless (equal commit actual)
        (error "~A is at ~A, expected ~A" name actual commit)))
    (format t "~&~A ~A~%" name commit)))

(defun read-pins ()
  "Read the list of (NAME URL COMMIT) pins from tools/deps.sexp."
  (with-open-file (stream (merge-pathnames "tools/deps.sexp" *root*))
    (with-standard-io-syntax
      (let ((*read-eval* nil))
        (read stream)))))

(with-exit-status
  (loop for (name url commit) in (read-pins)
        do (ensure-dependency name url commit))
  t)
