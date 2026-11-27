;;;; src/export/generate.lisp
;;;;
;;;; The generated files of the repository (docs/exports.md, "One
;;;; definition, everything generated"): a registry of generators, each a
;;;; repository-relative path and a function returning the file's text.
;;;; A generator step registers its own with DEFINE-GENERATOR in its own
;;;; file, so steps never edit a shared list.  `make generate' writes
;;;; them all (tools/generate.lisp); the suite fails on a stale one
;;;; (tests/export/generate.lisp).  Owner: step 3.0.

(in-package #:cl-ansi-spec/export)

(defstruct (generator (:constructor make-generator (name path thunk)))
  "The generator NAME (a symbol) writes the file PATH, relative to the
repository root, with the text THUNK (a function designator, of no
arguments) returns."
  (name nil :type symbol :read-only t)
  (path "" :type string :read-only t)
  (thunk nil :read-only t))

(defvar *generators* '()
  "The registered GENERATORs, in the order they were first defined.")

(defun register-generator (generator)
  "Register GENERATOR, replacing one of the same name in place."
  (let ((old (position (generator-name generator) *generators*
                       :key #'generator-name)))
    (if old
        (setf (nth old *generators*) generator)
        (setf *generators* (append *generators* (list generator))))
    (generator-name generator)))

(defmacro define-generator (name path function)
  "Register the generator NAME: the file PATH (a string, relative to the
repository root) holds the text that FUNCTION, a function designator of
no arguments, returns."
  `(register-generator (make-generator ',name ,path ,function)))

(defun generators ()
  "The registered generators, in order."
  (copy-list *generators*))

(defun generated-text (generator)
  "The text GENERATOR makes, a string."
  (let ((text (funcall (generator-thunk generator))))
    (check-type text string)
    text))

(defun generator-pathname (generator root)
  "Where GENERATOR's file is under the directory ROOT."
  (merge-pathnames (generator-path generator) root))

(defun file-text (pathname)
  "The contents of PATHNAME as UTF-8 text, or NIL when it does not exist."
  (with-open-file (in pathname :external-format :utf-8 :if-does-not-exist nil)
    (when in
      (let* ((text (make-string (file-length in)))
             (end (read-sequence text in)))
        (subseq text 0 end)))))

(defun stale-generated-files (root)
  "The paths of the generators whose file under ROOT is missing or differs
from what they make now."
  (loop for generator in *generators*
        unless (equal (file-text (generator-pathname generator root))
                      (generated-text generator))
          collect (generator-path generator)))

(defun write-generated-files (root)
  "Write every generator's file under ROOT; return the paths written
(those whose contents changed)."
  (loop for generator in *generators*
        for pathname = (generator-pathname generator root)
        for text = (generated-text generator)
        unless (equal (file-text pathname) text)
          collect (progn
                    (ensure-directories-exist pathname)
                    (with-open-file (out pathname :direction :output
                                                  :if-exists :supersede
                                                  :external-format :utf-8)
                      (write-string text out))
                    (generator-path generator))))
