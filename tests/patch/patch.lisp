;;;; tests/patch/patch.lisp
;;;;
;;;; Reading and applying unified diffs (src/patch/): exact expected
;;;; results, failures included.

(defpackage #:cl-ansi-spec/tests/patch
  (:use #:cl)
  (:import-from #:parachute #:define-test #:is #:true #:false #:fail)
  (:local-nicknames (#:patch #:cl-ansi-spec/patch)))

(in-package #:cl-ansi-spec/tests/patch)

(define-test patch
  :parent (cl-ansi-spec/tests cl-ansi-spec)
  :description "Unified diffs: reading and strict application.")

(defun lines (&rest strings)
  "STRINGS joined, each ending in a newline."
  (format nil "~{~A~%~}" strings))

(defun source-of (alist)
  (lambda (path) (cdr (assoc path alist :test #'string=))))

(defun patch-of (&rest strings)
  (patch:parse-patch (apply #'lines strings) :name "0001-test.patch"))

(defun result (patches alist)
  "The new text of the single file patched, applying PATCHES to ALIST."
  (cdr (first (patch:apply-patches (if (listp patches) patches (list patches))
                                   (source-of alist)))))

(defparameter *abc* (lines "a" "b" "c" "d" "e"))

;;; Reading

(define-test reads-header-files-and-hunks
  :parent patch
  (let* ((p (patch-of "Fix a typo." "Cites f.tex:2." "--- f.tex" "+++ f.tex"
                      "@@ -2,2 +2,2 @@" " b" "-c" "+C"
                      "@@ -5 +5 @@" "-e" "+E"))
         (file (first (patch:patch-files p))))
    (is string= (lines "Fix a typo." "Cites f.tex:2.") (patch:patch-header p))
    (is = 1 (length (patch:patch-files p)))
    (is string= "f.tex" (patch:file-patch-path file))
    (let ((hunks (patch:file-patch-hunks file)))
      (is = 2 (length hunks))
      (is equal '(2 2 2 2) (let ((h (first hunks)))
                             (list (patch:hunk-old-start h) (patch:hunk-old-count h)
                                   (patch:hunk-new-start h) (patch:hunk-new-count h))))
      (is equal '(5 1 5 1) (let ((h (second hunks)))
                             (list (patch:hunk-old-start h) (patch:hunk-old-count h)
                                   (patch:hunk-new-start h) (patch:hunk-new-count h))))
      (is equal '("b" "c") (patch:hunk-old-lines (first hunks)))
      (is equal '("b" "C") (patch:hunk-new-lines (first hunks)))
      (is equal '(1 2) (mapcar #'patch:hunk-index hunks)))))

(define-test deleted-line-looking-like-a-file-header
  :parent patch
  ;; "--- x" inside a hunk is a deleted line "-- x": the counts decide.
  (let ((p (patch-of "why" "--- f.tex" "+++ f.tex" "@@ -1 +1 @@" "--- x" "+y")))
    (is equal '("-- x") (patch:hunk-old-lines
                         (first (patch:file-patch-hunks (first (patch:patch-files p))))))))

(define-test several-files-and-time-stamps
  :parent patch
  (let ((p (patch-of "why" "--- f.tex	2020-01-01" "+++ f.tex	2020-01-02"
                     "@@ -1 +1 @@" "-a" "+A"
                     "--- g.tex" "+++ g.tex" "@@ -1 +1 @@" "-x" "+X")))
    (is equal '("f.tex" "g.tex") (mapcar #'patch:file-patch-path (patch:patch-files p)))
    (is equal '(1 2) (mapcar (lambda (f) (patch:hunk-index (first (patch:file-patch-hunks f))))
                             (patch:patch-files p)))))

(defmacro syntax-fails (form &optional (type 'patch:patch-syntax-error))
  `(fail ,form ,type))

(define-test syntax-errors
  :parent patch
  (syntax-fails (patch:parse-patch "no files here"))
  (syntax-fails (patch-of "h" "--- f" "+++ g" "@@ -1 +1 @@" "-a" "+b")) ; rename
  (syntax-fails (patch-of "h" "--- f" "@@ -1 +1 @@" "-a" "+b"))         ; no +++
  (syntax-fails (patch-of "h" "--- f" "+++ f"))                        ; no hunk
  (syntax-fails (patch-of "h" "--- f" "+++ f" "@@ -1 +1 @@" "-a"))     ; short
  (syntax-fails (patch-of "h" "--- f" "+++ f" "@@ -1 +1 @@" "-a" "+b" "+c"))
  (syntax-fails (patch-of "h" "--- f" "+++ f" "@@ -1 +1 @@" "-a" "+b" "junk"))
  (syntax-fails (patch-of "h" "--- f" "+++ f" "@@ -1 +1 @@" "-a" "" "+b")) ; empty line
  (syntax-fails (patch-of "h" "--- f" "+++ f" "@@ nonsense @@" "-a" "+b"))
  (syntax-fails (patch-of "h" "--- f" "+++ f" "@@ -1 +1" "-a" "+b"))
  (syntax-fails (patch-of "h" "--- f" "+++ f" "@@ -1 +1 @@" "\\ No newline at end of file")))

(define-test unsafe-paths
  :parent patch
  (dolist (path '("/etc/passwd" "../x.tex" "a/../x.tex"))
    (fail (patch-of "h" (format nil "--- ~A" path) (format nil "+++ ~A" path)
                    "@@ -1 +1 @@" "-a" "+b")
          'patch:unsafe-patch-path)))

;;; Applying

(define-test replaces-lines
  :parent patch
  (is string= (lines "a" "B" "c" "d" "e")
      (result (patch-of "h" "--- f" "+++ f" "@@ -1,3 +1,3 @@" " a" "-b" "+B" " c")
              `(("f" . ,*abc*)))))

(define-test inserts-and-deletes
  :parent patch
  (is string= (lines "a" "b" "X" "Y" "c" "d" "e")
      (result (patch-of "h" "--- f" "+++ f" "@@ -2,0 +3,2 @@" "+X" "+Y")
              `(("f" . ,*abc*))))
  (is string= (lines "X" "a" "b" "c" "d" "e")
      (result (patch-of "h" "--- f" "+++ f" "@@ -0,0 +1 @@" "+X")
              `(("f" . ,*abc*))))
  (is string= (lines "a" "b" "d" "e")
      (result (patch-of "h" "--- f" "+++ f" "@@ -3 +2,0 @@" "-c")
              `(("f" . ,*abc*)))))

(define-test hunks-in-pristine-coordinates
  :parent patch
  ;; The first hunk adds a line; the second still names line 5 of the pristine file.
  (is string= (lines "a" "X" "b" "c" "d" "E")
      (result (patch-of "h" "--- f" "+++ f"
                        "@@ -1,2 +1,3 @@" " a" "+X" " b"
                        "@@ -5 +6 @@" "-e" "+E")
              `(("f" . ,*abc*)))))

(define-test several-patches-merge-in-any-order
  :parent patch
  (let ((one (patch-of "h" "--- f" "+++ f" "@@ -1 +1 @@" "-a" "+A"))
        (two (patch-of "h" "--- f" "+++ f" "@@ -5 +5 @@" "-e" "+E")))
    (is string= (lines "A" "b" "c" "d" "E")
        (result (list one two) `(("f" . ,*abc*))))
    (is string= (lines "A" "b" "c" "d" "E")
        (result (list two one) `(("f" . ,*abc*))))))

(define-test only-patched-files-are-returned
  :parent patch
  (is equal `(("f" . ,(lines "A" "b" "c" "d" "e")))
      (patch:apply-patch (patch-of "h" "--- f" "+++ f" "@@ -1 +1 @@" "-a" "+A")
                         (source-of `(("f" . ,*abc*) ("g" . "other"))))))

(define-test no-newline-at-end-of-file
  :parent patch
  (let ((text (format nil "a~%b")))
    (is string= (format nil "a~%B")
        (result (patch-of "h" "--- f" "+++ f" "@@ -2 +2 @@" "-b" "\\ No newline at end of file"
                          "+B" "\\ No newline at end of file")
                `(("f" . ,text))))
    ;; Adding the newline.
    (is string= (lines "a" "b")
        (result (patch-of "h" "--- f" "+++ f" "@@ -2 +2 @@" "-b" "\\ No newline at end of file"
                          "+b")
                `(("f" . ,text))))
    ;; Context at the end, unchanged and unterminated.
    (is string= (format nil "A~%b")
        (result (patch-of "h" "--- f" "+++ f" "@@ -1,2 +1,2 @@" "-a" "+A" " b"
                          "\\ No newline at end of file")
                `(("f" . ,text))))
    ;; A hunk that does not mention it, on a file that lacks it, fails.
    (fail (result (patch-of "h" "--- f" "+++ f" "@@ -2 +2 @@" "-b" "+B")
                  `(("f" . ,text)))
          'patch:hunk-mismatch)
    ;; And the reverse.
    (fail (result (patch-of "h" "--- f" "+++ f" "@@ -2 +2 @@" "-b" "\\ No newline at end of file"
                            "+B")
                  `(("f" . ,*abc*)))
          'patch:hunk-mismatch)))

(define-test failures-name-patch-hunk-and-line
  :parent patch
  (let ((condition
          (handler-case
              (result (patch-of "h" "--- f" "+++ f" "@@ -1 +1 @@" "-a" "+A"
                                "@@ -3 +3 @@" "-WRONG" "+x")
                      `(("f" . ,*abc*)))
            (patch:hunk-mismatch (c) c))))
    (true (typep condition 'patch:hunk-mismatch))
    (is string= "0001-test.patch" (patch:patch-error-patch condition))
    (is = 2 (patch:patch-error-hunk condition))
    (is = 3 (patch:patch-error-line condition))
    (is string= "WRONG" (patch:hunk-mismatch-expected condition))
    (is string= "c" (patch:hunk-mismatch-actual condition))
    (true (search "hunk 2, line 3" (princ-to-string condition)))))

(define-test no-offset-and-no-fuzz
  :parent patch
  ;; Right text, wrong line: not found by searching.
  (fail (result (patch-of "h" "--- f" "+++ f" "@@ -2 +2 @@" "-c" "+C")
                `(("f" . ,*abc*)))
        'patch:hunk-mismatch)
  ;; Context that is only partly right.
  (fail (result (patch-of "h" "--- f" "+++ f" "@@ -1,3 +1,3 @@" " a" "-b" "+B" " X")
                `(("f" . ,*abc*)))
        'patch:hunk-mismatch)
  ;; Past the end.
  (fail (result (patch-of "h" "--- f" "+++ f" "@@ -5,2 +5,2 @@" " e" "-f" "+F")
                `(("f" . ,*abc*)))
        'patch:hunk-mismatch))

(define-test overlapping-or-touching-hunks
  :parent patch
  (let ((a (patch-of "h" "--- f" "+++ f" "@@ -1,2 +1,2 @@" " a" "-b" "+B"))
        (overlap (patch-of "h" "--- f" "+++ f" "@@ -2,2 +2,2 @@" " b" "-c" "+C"))
        (touch (patch-of "h" "--- f" "+++ f" "@@ -3 +3 @@" "-c" "+C"))
        (apart (patch-of "h" "--- f" "+++ f" "@@ -4 +4 @@" "-d" "+D")))
    (fail (result (list a overlap) `(("f" . ,*abc*))) 'patch:hunk-overlap)
    (fail (result (list overlap a) `(("f" . ,*abc*))) 'patch:hunk-overlap)
    (fail (result (list a touch) `(("f" . ,*abc*))) 'patch:hunk-overlap)
    (is string= (lines "a" "B" "c" "D" "e")
        (result (list a apart) `(("f" . ,*abc*))))
    ;; Within one patch too.
    (fail (result (patch-of "h" "--- f" "+++ f" "@@ -1,2 +1,2 @@" " a" "-b" "+B"
                            "@@ -2,2 +2,2 @@" " b" "-c" "+C")
                  `(("f" . ,*abc*)))
          'patch:hunk-overlap)))

(define-test missing-file
  :parent patch
  (let ((condition (handler-case
                       (result (patch-of "h" "--- nope.tex" "+++ nope.tex"
                                         "@@ -1 +1 @@" "-a" "+b")
                               `(("f" . ,*abc*)))
                     (patch:patch-file-missing (c) c))))
    (true (typep condition 'patch:patch-file-missing))
    (is string= "nope.tex" (patch:patch-file-missing-path condition))
    (is string= "0001-test.patch" (patch:patch-error-patch condition))))

(define-test nothing-is-returned-when-one-file-fails
  :parent patch
  (fail (patch:apply-patch (patch-of "h" "--- f" "+++ f" "@@ -1 +1 @@" "-a" "+A"
                                     "--- g" "+++ g" "@@ -1 +1 @@" "-zzz" "+A")
                           (source-of `(("f" . ,*abc*) ("g" . ,*abc*))))
        'patch:hunk-mismatch))

(define-test reads-a-patch-file
  :parent patch
  (let ((file (merge-pathnames "0001-test.patch"
                               (uiop:ensure-directory-pathname (uiop:temporary-directory)))))
    (unwind-protect
         (progn
           (with-open-file (out file :direction :output :if-exists :supersede)
             (write-string (lines "why" "--- f" "+++ f" "@@ -1 +1 @@" "-a" "+A") out))
           (let ((p (patch:read-patch-file file)))
             (is string= "0001-test.patch" (patch:patch-name p))
             (is string= (lines "why") (patch:patch-header p))))
      (ignore-errors (delete-file file)))))

(define-test insertion-edge-cases
  :parent patch
  (let ((a (patch-of "h" "--- f" "+++ f" "@@ -2,0 +3 @@" "+X"))
        (b (patch-of "h" "--- f" "+++ f" "@@ -2,0 +3 @@" "+Y"))
        (inside (patch-of "h" "--- f" "+++ f" "@@ -2,2 +2,2 @@" " b" "-c" "+C")))
    (fail (result (list a b) `(("f" . ,*abc*))) 'patch:hunk-overlap)
    (fail (result (list a inside) `(("f" . ,*abc*))) 'patch:hunk-overlap))
  (is string= (lines "a" "b" "c" "d" "e" "X")
      (result (patch-of "h" "--- f" "+++ f" "@@ -5,0 +6 @@" "+X")
              `(("f" . ,*abc*))))
  (fail (result (patch-of "h" "--- f" "+++ f" "@@ -0,2 +1,2 @@" " a" "-b" "+B")
                `(("f" . ,*abc*)))
        'patch:hunk-mismatch)
  (is string= (lines "X")
      (result (patch-of "h" "--- f" "+++ f" "@@ -0,0 +1 @@" "+X") '(("f" . "")))))

(define-test marker-before-the-end-of-a-side
  :parent patch
  (syntax-fails (patch-of "h" "--- f" "+++ f" "@@ -1,2 +1,2 @@" "-a" "\\ No newline at end of file"
                          "-b" "+A" "+B")))
