;;;; src/source.lisp
;;;;
;;;; Locating and reading the pristine dpANS3 TeX sources in spec/tex/.

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
