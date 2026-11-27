;;;; tools/patched.lisp
;;;;
;;;; Write the patched spec tree to build/patched/, for reading and
;;;; diffing only (every job reads the patched text from memory): each
;;;; file of spec/tex/ as the patch set serves it, then the patches
;;;; applied, with their SHA-256.  Fails, naming the patch, the hunk and
;;;; the line, if patches/ does not load.
;;;;
;;;; Usage: make patched

(load (merge-pathnames "setup.lisp" *load-truename*))

(in-package #:cl-ansi-spec.tools)

(configure-asdf)

(with-exit-status
  (let ((*standard-output* (make-broadcast-stream)))
    (asdf:load-system "cl-ansi-spec"))
  (let* ((out (merge-pathnames "build/patched/" *root*))
         (set (uiop:symbol-call '#:cl-ansi-spec/patch '#:current-patch-set))
         (changed 0))
    (uiop:delete-directory-tree out :validate t :if-does-not-exist :ignore)
    (ensure-directories-exist out)
    (dolist (file (uiop:symbol-call '#:cl-ansi-spec '#:spec-files :type :wild))
      (let* ((name (file-namestring file))
             (patched (uiop:symbol-call '#:cl-ansi-spec/patch '#:patched-text name set))
             (target (merge-pathnames name out)))
        (if patched
            (progn (incf changed)
                   (with-open-file (stream target :direction :output
                                                  :external-format :utf-8)
                     (write-string patched stream)))
            (uiop:copy-file file target))))
    (dolist (entry (uiop:symbol-call '#:cl-ansi-spec/patch '#:applied-patches set))
      (format t "~A  ~A~%" (second entry) (first entry)))
    (format t "~D patch(es) applied, ~D file(s) changed, tree in build/patched/.~%"
            (length (uiop:symbol-call '#:cl-ansi-spec/patch '#:applied-patches set))
            changed))
  t)
