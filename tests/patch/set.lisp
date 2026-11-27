;;;; tests/patch/set.lisp
;;;;
;;;; The patch set (src/patch/set.lisp): names, headers, independence, the
;;;; patched text served to jobs, and the transparency of the overlay.

(in-package #:cl-ansi-spec/tests/patch)

(define-test patch-set
  :parent patch
  :description "The patch set and the patched resolver.")

(defun call-with-patch-directory (files function)
  "Call FUNCTION with a fresh directory holding FILES, an alist from a
file name to its text, and delete the directory afterwards."
  (let ((directory (uiop:ensure-directory-pathname
                    (merge-pathnames (format nil "cl-ansi-spec-patches-~D/" (random 1000000000))
                                     (uiop:temporary-directory)))))
    (ensure-directories-exist directory)
    (unwind-protect
         (progn
           (loop for (name . text) in files
                 do (with-open-file (out (merge-pathnames name directory)
                                         :direction :output :external-format :utf-8)
                      (write-string text out)))
           (funcall function directory))
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))

(defun pristine-spec (path)
  (let ((pathname (merge-pathnames path (cl-ansi-spec:spec-directory))))
    (and (uiop:file-exists-p pathname) (cl-ansi-spec:read-spec-file pathname))))

(defparameter *tree* `(("f.tex" . ,(lines "a" "b" "c" "d" "e"))))

(defun load-set (files)
  (call-with-patch-directory
   files (lambda (directory) (patch:load-patch-set directory (source-of *tree*)))))

(defun upcase-patch (line from to)
  (lines "Why: a test." "--- f.tex" "+++ f.tex" (format nil "@@ -~D +~D @@" line line)
         (format nil "-~A" from) (format nil "+~A" to)))

(define-test loading
  :parent patch-set
  (let ((set (load-set `(("0002-b.patch" . ,(upcase-patch 2 "b" "B"))
                         ("0001-a.patch" . ,(upcase-patch 4 "d" "D"))
                         ("README.md" . "ignored")))))
    (is equal '("0001-a.patch" "0002-b.patch")
        (mapcar #'patch:patch-name (patch:patch-set-patches set)))
    (is string= (lines "a" "B" "c" "D" "e") (patch:patched-text "f.tex" set))
    (false (patch:patched-text "other.tex" set))
    (is equal '("0001-a.patch" "0002-b.patch")
        (mapcar #'first (patch:applied-patches set)))
    (is = 64 (length (second (first (patch:applied-patches set))))))
  (let ((set (load-set '())))
    (false (patch:patch-set-patches set))
    (false (patch:patch-set-files set))))

(define-test applied-patches-digest
  :parent patch-set
  (let* ((text (upcase-patch 2 "b" "B"))
         (set (load-set `(("0001-a.patch" . ,text)))))
    (is string= (cl-ansi-spec/sha256:sha256-hex
                 (sb-ext:string-to-octets text :external-format :utf-8))
        (second (first (patch:applied-patches set))))))

(define-test rules
  :parent patch-set
  (dolist (name '("1-a.patch" "0001.patch" "0001-A.patch" "0001-a_b.patch"
                  "0001-a--b.patch" "00x1-a.patch"))
    (fail (load-set `((,name . ,(upcase-patch 2 "b" "B")))) 'patch:patch-error))
  (fail (load-set `(("0001-a.patch" . ,(upcase-patch 2 "b" "B"))
                    ("0001-b.patch" . ,(upcase-patch 4 "d" "D"))))
        'patch:invalid-patch)
  (fail (load-set `(("0001-a.patch" . ,(lines "  " "--- f.tex" "+++ f.tex"
                                               "@@ -2 +2 @@" "-b" "+B"))))
        'patch:invalid-patch))

(define-test independence
  :parent patch-set
  ;; Does not apply alone.
  (fail (load-set `(("0001-a.patch" . ,(upcase-patch 2 "x" "B"))))
        'patch:hunk-mismatch)
  ;; Same line, and touching hunks, in two patches.
  (fail (load-set `(("0001-a.patch" . ,(upcase-patch 2 "b" "B"))
                    ("0002-b.patch" . ,(upcase-patch 2 "b" "Z"))))
        'patch:hunk-overlap)
  (fail (load-set `(("0001-a.patch" . ,(upcase-patch 2 "b" "B"))
                    ("0002-b.patch" . ,(upcase-patch 3 "c" "C"))))
        'patch:hunk-overlap)
  ;; A patch of a file that is not in the tree.
  (fail (load-set `(("0001-a.patch" . ,(lines "why" "--- g.tex" "+++ g.tex"
                                               "@@ -1 +1 @@" "-a" "+A"))))
        'patch:patch-file-missing))

(define-test no-patches-is-transparent
  :parent patch-set
  ;; With an empty set the resolver serves each file's own text, as the
  ;; plain directory resolver did before the patch set existed.
  (let ((set (call-with-patch-directory
              '() (lambda (directory) (patch:load-patch-set directory #'pristine-spec)))))
    (false (patch:patched-text "chap-1.tex" set))
    (patch:with-patch-set (set)
      (let ((source (funcall (cl-ansi-spec/tex:directory-resolver (cl-ansi-spec:spec-directory))
                             "chap-1")))
        (is string= (cl-ansi-spec:read-spec-file (cl-ansi-spec:spec-file "chap-1"))
            (cl-ansi-spec/tex:line-source-text source))))))

(define-test resolver-serves-patched-text
  :parent patch-set
  (let* ((original (cl-ansi-spec:read-spec-file (cl-ansi-spec:spec-file "chap-1")))
         (first-line (subseq original 0 (position #\Newline original)))
         (patch-text (lines "Test: change the first line." "--- chap-1.tex" "+++ chap-1.tex"
                            "@@ -1 +1 @@" (format nil "-~A" first-line) "+% patched"))
         (set (call-with-patch-directory
               `(("0001-test.patch" . ,patch-text))
               (lambda (directory)
                 (patch:load-patch-set directory #'pristine-spec)))))
    (patch:with-patch-set (set)
      ;; \input chap-1, \input chap-1.tex and a generated file all go through
      ;; the resolver; the vendored files and the fixtures are not patched.
      (let ((resolver (cl-ansi-spec/tex:directory-resolver (cl-ansi-spec:spec-directory)
                                                           (cl-ansi-spec:vendor-directory))))
        (dolist (name '("chap-1" "chap-1.tex"))
          (let ((source (funcall resolver name)))
            (is string= "chap-1.tex" (cl-ansi-spec/tex:line-source-name source))
            (true (eql 0 (search "% patched" (cl-ansi-spec/tex:line-source-text source))))))
        (false (search "% patched"
                       (cl-ansi-spec/tex:line-source-text (funcall resolver "plain"))))
        (false (search "% patched"
                       (cl-ansi-spec/tex:line-source-text
                        (funcall resolver "chap-1.fig"))))))))

(define-test real-patch-set-loads
  :parent patch-set
  ;; patches/ as committed: every patch valid, independent and applying.
  (let ((set (patch:load-patch-set)))
    (is = (length (patch:patch-set-patches set)) (length (patch:applied-patches set)))))
