;;;; tests/source.lisp

(in-package #:cl-ansi-spec/tests)

(define-test source
  :parent cl-ansi-spec
  :description "Locating and reading the sources: spec tree and vendored plain TeX.")

(define-test spec-directory-exists
  :parent source
  (true (uiop:directory-exists-p (spec-directory))))

(defparameter *source-trees*
  '(("spec/tex/" . "spec/SHA256SUMS")
    ("vendor/plain/" . "vendor/SHA256SUMS"))
  "The pristine source trees, each with its manifest of SHA-256 sums.")

(defun tree-directory (tree)
  (asdf:system-relative-pathname "cl-ansi-spec" (car tree)))

(defun manifest-file-names (tree)
  "Return the sorted file names recorded in the manifest of TREE."
  (sort (mapcar (lambda (line)
                  ;; Lines look like "<sha256>  ./<file-name>".
                  (subseq line (+ (search "  ./" line) (length "  ./"))))
                (uiop:read-file-lines
                 (asdf:system-relative-pathname "cl-ansi-spec" (cdr tree))))
        #'string<))

(define-test source-inventory
  :parent source
  :description "Each source tree holds exactly the files of its manifest."
  (dolist (tree *source-trees*)
    (is equal (manifest-file-names tree)
        (mapcar #'file-namestring (spec-files :type :wild
                                              :directory (tree-directory tree)))
        "~A differs from its manifest" (car tree))))

(define-test every-chapter-is-present
  :parent source
  (dolist (chapter (list* "chap-0-edit-history" "chap-a"
                          (loop for n from 0 to 26
                                collect (format nil "chap-~D" n))))
    (true (spec-file chapter) "Missing chapter ~A" chapter)))

(define-test spec-files-are-sorted
  :parent source
  (let ((names (mapcar #'file-namestring (spec-files))))
    (is equal (sort (copy-list names) #'string<) names)))

(define-test spec-file-signals-when-missing
  :parent source
  (fail (spec-file "no-such-file") 'spec-file-missing))

(define-test spec-file-rejects-wild-names
  :parent source
  (fail (spec-file "chap-*") 'error))

(define-test sources-are-ascii
  :parent source
  :description "The pristine sources are pure ASCII with LF line endings."
  (dolist (pathname (loop for tree in *source-trees*
                          append (spec-files :type :wild
                                             :directory (tree-directory tree))))
    (let ((text (read-spec-file pathname))
          (name (file-namestring pathname)))
      (true (plusp (length text)) "~A is empty" name)
      (true (every (lambda (char) (< (char-code char) 128)) text)
            "~A contains non-ASCII characters" name)
      (false (find #\Return text) "~A contains CR characters" name))))

(define-test read-spec-file-reads-verbatim
  :parent source
  (true (search "\\begincom{list}\\ftype{System Class}"
                (read-spec-file (spec-file "dict-conses")))))

(define-test search-path
  :parent source
  :description "Input names are looked up in the spec tree, then vendor/plain/."
  (is equal (list (spec-directory) (vendor-directory)) (source-search-path))
  (is equal "chap-1.tex" (find-input-file "chap-1"))
  (is equal "hyphen.tex" (find-input-file "hyphen"))
  (is equal (merge-pathnames "plain.tex" (vendor-directory))
      (nth-value 1 (find-input-file "plain.tex")))
  (false (find-input-file "no-such-file"))
  (false (find-input-file "/etc/passwd"))
  (false (find-input-file "../SHA256SUMS"))
  (false (find-input-file "")))

(defun call-with-temporary-trees (function &rest trees)
  "Call FUNCTION with fresh directories populated per TREES, each a list of
(file-name . contents) where a file name may hold subdirectories, and
delete them afterwards."
  (let ((random-state (make-random-state t))
        (directories '()))
    (flet ((fresh-directory ()
             (loop for directory = (merge-pathnames
                                    (format nil "cl-ansi-spec-tree-~36R/"
                                            (random (expt 36 10) random-state))
                                    (uiop:temporary-directory))
                   unless (uiop:directory-exists-p directory)
                     return (ensure-directories-exist directory))))
      (unwind-protect
           (progn
             (dolist (files trees)
               (let ((directory (fresh-directory)))
                 (push directory directories)
                 (loop for (name . contents) in files
                       for pathname = (merge-pathnames (uiop:parse-unix-namestring name)
                                                       directory)
                       do (ensure-directories-exist pathname)
                          (with-open-file (out pathname :direction :output)
                            (write-string contents out)))))
             (funcall function (reverse directories)))
        (dolist (directory directories)
          (uiop:delete-directory-tree
           directory :validate (lambda (pathname)
                                 (search "cl-ansi-spec-tree-"
                                         (namestring pathname)))))))))

(define-test search-path-order-and-types
  :parent source
  (call-with-temporary-trees
   (lambda (directories)
     (destructuring-bind (first second) directories
       ;; The tex type is tried first, then the name as given.
       (is equal "a.tex" (find-input-file "a" directories))
       (is equal "b" (find-input-file "b" directories))
       (is equal (merge-pathnames "c.tex" second)
           (nth-value 1 (find-input-file "c" directories)))
       (is equal (merge-pathnames "a.tex" first)
           (nth-value 1 (find-input-file "a.tex" (list first))))
       ;; A name is ambiguous when two directories resolve it, even to
       ;; different file names.
       (fail (find-input-file "d" directories) 'ambiguous-input-file)
       (fail (find-input-file "e" directories) 'ambiguous-input-file)
       ;; A dot in a directory name does not give the name a type.
       (is equal "x.d/f.tex" (find-input-file "x.d/f" directories))
       ;; Directories are not input files; wildcard characters and
       ;; backslashes are literal.
       (false (find-input-file "x.d" directories))
       (false (find-input-file "x.d/" directories))
       (is equal "w*" (find-input-file "w*" directories))
       (is equal "b\\s" (find-input-file "b\\s" directories))
       (false (find-input-file "x.d/../a" directories))))
   '(("a.tex" . "") ("a" . "") ("b" . "") ("d.tex" . "") ("e.tex" . "")
     ("x.d/f.tex" . "") ("w*" . "") ("b\\s" . ""))
   '(("c.tex" . "") ("d.tex" . "") ("e" . ""))))
