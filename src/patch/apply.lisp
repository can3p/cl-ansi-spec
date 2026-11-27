;;;; src/patch/apply.lisp
;;;;
;;;; Applying patches strictly.  The hunks of every patch that touches a
;;;; file are merged into one edit set in pristine coordinates, checked
;;;; (context exact, no hunk overlapping or touching another, so no hunk
;;;; shifts another) and applied in one pass.  No fuzz, no offset.

(in-package #:cl-ansi-spec/patch)

(defun hunk-start (hunk)
  "The 0-based index in the pristine lines where HUNK's old side begins
(for an empty old side, where its lines are inserted)."
  (if (zerop (hunk-old-count hunk))
      (hunk-old-start hunk)
      (1- (hunk-old-start hunk))))

(defun hunk-end (hunk)
  (+ (hunk-start hunk) (hunk-old-count hunk)))

(defun signal-mismatch (hunk line reason &optional expected actual)
  (error 'hunk-mismatch :patch (hunk-patch-name hunk) :hunk (hunk-index hunk)
                        :line line :reason reason
                        :expected expected :actual actual))

(defun check-hunk (hunk lines count final-newline-p)
  "Check HUNK against the pristine LINES (a vector of COUNT lines)."
  (let ((start (hunk-start hunk)) (end (hunk-end hunk)))
    (when (and (plusp (hunk-old-count hunk)) (zerop (hunk-old-start hunk)))
      (signal-mismatch hunk (hunk-old-start hunk) "invalid start line"))
    (when (> end count)
      (signal-mismatch hunk (max 1 (min (1+ start) count))
                (format nil "reaches line ~D, past the end of the file (~D lines)"
                        end count)))
    (loop for expected in (hunk-old-lines hunk)
          for index from start
          for actual = (aref lines index)
          unless (string= expected actual)
            do (signal-mismatch hunk (1+ index) "context differs" expected actual))
    (let ((at-end (= end count)))
      (when (and at-end (plusp count)
                 (not (eq (hunk-old-no-newline-p hunk) (not final-newline-p))))
        (signal-mismatch hunk count
                  (if final-newline-p
                      "claims the file has no newline at its end"
                      "does not say the file has no newline at its end")))
      (when (and (or (hunk-old-no-newline-p hunk) (hunk-new-no-newline-p hunk))
                 (not at-end))
        (signal-mismatch hunk (1+ start) "\"No newline\" marker on a hunk that is not at the end")))))

(defun check-disjoint (hunks)
  "HUNKS are sorted by position; signal HUNK-OVERLAP for two that overlap or touch."
  (loop for (previous next) on hunks
        while next
        when (>= (hunk-end previous) (hunk-start next))
          do (error 'hunk-overlap :patch (hunk-patch-name next)
                                  :hunk (hunk-index next)
                                  :line (1+ (hunk-start next))
                                  :other-patch (hunk-patch-name previous)
                                  :other-hunk (hunk-index previous))))

(defun join-lines (lines final-newline-p)
  (with-output-to-string (out)
    (loop for (line . more) on lines
          do (write-string line out)
             (when (or more final-newline-p) (terpri out)))))

(defun apply-hunks (hunks text)
  "Apply HUNKS, hunks of one file in any order, to TEXT; return the new text."
  (multiple-value-bind (list final-newline-p) (split-lines text)
    (let* ((lines (coerce list 'vector))
           (count (length lines))
           (sorted (stable-sort (copy-list hunks) #'< :key #'hunk-start))
           (result '()) (position 0) (new-final-newline-p final-newline-p))
      (check-disjoint sorted)
      (dolist (hunk sorted)
        (check-hunk hunk lines count final-newline-p)
        (loop for index from position below (hunk-start hunk)
              do (push (aref lines index) result))
        (dolist (line (hunk-new-lines hunk)) (push line result))
        (setf position (hunk-end hunk))
        (when (= position count)
          (setf new-final-newline-p (not (hunk-new-no-newline-p hunk)))))
      (loop for index from position below count
            do (push (aref lines index) result))
      (join-lines (nreverse result) new-final-newline-p))))

(defun apply-patches (patches source)
  "Apply PATCHES, a list of PATCH, to the files SOURCE serves: a function
from a relative path to the file's text, or NIL when there is no such
file.  All hunks of a file, from all patches, are checked against the
pristine text and applied together.  Return an alist (PATH . NEW-TEXT) of
the files patched, in order of first mention.  Signal a PATCH-ERROR on the
first failure; nothing is returned then."
  (let ((order '()) (table (make-hash-table :test #'equal)))
    (dolist (patch patches)
      (dolist (file (patch-files patch))
        (let ((path (file-patch-path file)))
          (unless (nth-value 1 (gethash path table)) (push path order))
          (setf (gethash path table)
                (append (gethash path table)
                        (mapcar (lambda (hunk) (cons patch hunk))
                                (file-patch-hunks file)))))))
    (loop for path in (nreverse order)
          for entries = (gethash path table)
          for text = (funcall source path)
          unless text
            do (error 'patch-file-missing
                      :patch (patch-name (car (first entries)))
                      :hunk (hunk-index (cdr (first entries)))
                      :path path)
          collect (cons path (apply-hunks (mapcar #'cdr entries) text)))))

(defun apply-patch (patch source)
  "Apply the single PATCH; see APPLY-PATCHES."
  (apply-patches (list patch) source))
