;;;; tools/setup.lisp
;;;;
;;;; Shared bootstrap for the command-line tools: loads ASDF and points it
;;;; at this repository and the pinned dependencies in .deps/, ignoring any
;;;; user or system configuration so that builds are reproducible.  Fasls
;;;; go to build/, never to a user cache.

(require "asdf")

(defpackage #:cl-ansi-spec.tools
  (:use #:cl)
  (:export #:*root* #:*deps-directory* #:configure-asdf #:with-exit-status))

(in-package #:cl-ansi-spec.tools)

(defparameter *root*
  (uiop:pathname-parent-directory-pathname
   (uiop:pathname-directory-pathname *load-truename*))
  "Root directory of the repository.")

(defparameter *deps-directory* (merge-pathnames ".deps/" *root*)
  "Directory holding the pinned third-party dependencies.")

(defun configure-asdf ()
  "Make ASDF find only this repository and the pinned dependencies, and
write all compiled files under build/."
  (asdf:initialize-source-registry
   `(:source-registry
     (:directory ,*root*)
     (:tree ,*deps-directory*)
     :ignore-inherited-configuration))
  (asdf:initialize-output-translations
   `(:output-translations
     (t (,(merge-pathnames "build/" *root*) :implementation :**/ :*.*.*))
     :ignore-inherited-configuration)))

(defmacro with-exit-status (&body body)
  "Run BODY; exit with status 0 if it returns true, 1 if it returns false
or signals a serious condition."
  `(uiop:quit
    (handler-case (if (progn ,@body) 0 1)
      (serious-condition (condition)
        (format *error-output* "~&Error: ~A~%" condition)
        1))))

(defun parse-line-range (string)
  "Parse \"A-B\", \"A-\" or \"A\" into an inclusive range (FIRST LAST),
LAST being NIL for no upper bound.  NIL or \"\" means every line."
  (if (or (null string) (string= string ""))
      (list 1 nil)
      (handler-case
          (let* ((dash (position #\- string))
                 (first (parse-integer string :end dash))
                 (last (cond ((null dash) first)
                             ((= dash (1- (length string))) nil)
                             (t (parse-integer string :start (1+ dash))))))
            (list first last))
        (parse-error ()
          (error "LINES must look like A-B, A- or A, not ~S." string)))))
