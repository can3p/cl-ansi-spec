;;;; src/source.lisp
;;;;
;;;; Locating and reading the sources: the pristine dpANS3 TeX sources in
;;;; spec/tex/ and the plain TeX format vendored in vendor/plain/, searched
;;;; in that order (SOURCE-SEARCH-PATH).

(in-package #:cl-ansi-spec)

(define-condition spec-file-missing (file-error)
  ()
  (:report (lambda (condition stream)
             (format stream "Spec source file ~A does not exist."
                     (file-error-pathname condition))))
  (:documentation "Signalled when a requested spec source file is absent."))

(defun spec-directory ()
  "Return the directory holding the pristine dpANS3 TeX sources."
  (asdf:system-relative-pathname "cl-ansi-spec" "spec/tex/"))

(defun vendor-directory ()
  "Return the directory holding the vendored plain TeX format."
  (asdf:system-relative-pathname "cl-ansi-spec" "vendor/plain/"))

(defun source-search-path ()
  "Return the directories an \\input name is looked up in, in order: the
spec tree, then the vendored plain TeX format."
  (list (spec-directory) (vendor-directory)))

(define-condition ambiguous-input-file (error)
  ((name :initarg :name :reader ambiguous-input-file-name)
   (pathnames :initarg :pathnames :reader ambiguous-input-file-pathnames))
  (:report (lambda (condition stream)
             (format stream "Input file ~S is found in several source trees: ~{~A~^, ~}."
                     (ambiguous-input-file-name condition)
                     (ambiguous-input-file-pathnames condition))))
  (:documentation "Signalled when an input name resolves in more than one
directory of the search path.  Sources are named by their file name within
their tree, so such a name would make spans ambiguous."))

(defun safe-input-name-p (name)
  "Return true iff NAME may be looked up: not empty, not absolute and
without a \"..\" component, so only files inside a source tree are read."
  (not (or (zerop (length name))
           (char= (char name 0) #\/)
           (member ".." (uiop:split-string name :separator "/")
                   :test #'string=))))

(defun find-in-directory (name directory)
  "Return the file name and the pathname NAME resolves to in DIRECTORY, as
two values, or NIL.  As TeX82 does, a name without a type (no dot in its
last component) is tried with type tex first; a name with a type is used
as given."
  (flet ((try (file-name)
           (let ((pathname (merge-pathnames (uiop:parse-unix-namestring file-name)
                                            directory)))
             (when (and (not (wild-pathname-p pathname))
                        (uiop:file-exists-p pathname))
               (return-from find-in-directory (values file-name pathname))))))
    (when (member (pathname-type (uiop:parse-unix-namestring name))
                  '(nil :unspecific))
      (try (concatenate 'string name ".tex")))
    (try name)
    nil))

(defun find-input-file (name &optional (directories (source-search-path)))
  "Return the file name and the pathname of the input file NAME, as two
values, or NIL if no directory of DIRECTORIES holds it or NAME is not
SAFE-INPUT-NAME-P.  The file name is relative to its directory.  Signal
AMBIGUOUS-INPUT-FILE if NAME resolves in several directories, even to
different file names (a.tex in one, a in another)."
  (when (safe-input-name-p name)
    (let ((hits (loop for directory in directories
                      for (file-name pathname) = (multiple-value-list
                                                  (find-in-directory name directory))
                      when file-name
                        collect (cons file-name pathname))))
      (when (rest hits)
        (error 'ambiguous-input-file :name name :pathnames (mapcar #'cdr hits)))
      (values (car (first hits)) (cdr (first hits))))))

(defun spec-file (name &key (type "tex") (directory (spec-directory)))
  "Return the truename of the source file NAME.TYPE in DIRECTORY.
Signal SPEC-FILE-MISSING if it does not exist."
  (let ((pathname (make-pathname :name name :type type :defaults directory)))
    (when (wild-pathname-p pathname)
      (error "Spec file name ~S.~A must not be wild." name type))
    (or (probe-file pathname)
        (error 'spec-file-missing :pathname pathname))))

(defun spec-files (&key (type "tex") (directory (spec-directory)))
  "Return the source files of TYPE in DIRECTORY, sorted by file name.
TYPE may be :WILD to list every file.  Subdirectories are never listed."
  (sort (uiop:directory-files directory
                              (make-pathname :name :wild :type type))
        #'string< :key #'file-namestring))

(defun read-spec-file (pathname)
  "Return the contents of the source file PATHNAME as a string.
The pristine sources are ASCII; UTF-8 is accepted so that patched sources
may contain non-ASCII text."
  (uiop:read-file-string pathname :external-format :utf-8))
