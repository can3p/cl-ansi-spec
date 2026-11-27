;;;; src/patch/package.lisp
;;;;
;;;; Unified diffs: reading a patch file and applying patches strictly to
;;;; the text of a file (phase 0, "Sources"; patches/README.md).  Every
;;;; hunk's line numbers are counted in the pristine file; there is no
;;;; fuzz and no offset.  The patch set, its checks and the patched
;;;; resolver build on this package.

(defpackage #:cl-ansi-spec/patch
  (:use #:cl)
  (:export
   ;; Records
   #:patch #:patch-name #:patch-header #:patch-files
   #:file-patch #:file-patch-path #:file-patch-line #:file-patch-hunks
   #:hunk #:hunk-patch-name #:hunk-index #:hunk-line #:hunk-old-start
   #:hunk-old-count #:hunk-new-start #:hunk-new-count #:hunk-lines
   #:hunk-old-lines #:hunk-new-lines
   #:hunk-old-no-newline-p #:hunk-new-no-newline-p
   ;; Reading and applying
   #:parse-patch #:read-patch-file #:apply-patch #:apply-patches
   ;; Conditions
   #:patch-error #:patch-error-patch #:patch-error-hunk #:patch-error-line
   #:patch-syntax-error #:patch-syntax-error-reason
   #:unsafe-patch-path #:unsafe-patch-path-path
   #:patch-file-missing #:patch-file-missing-path
   #:hunk-mismatch #:hunk-mismatch-expected #:hunk-mismatch-actual
   #:hunk-mismatch-reason
   #:hunk-overlap #:hunk-overlap-other-patch #:hunk-overlap-other-hunk))
