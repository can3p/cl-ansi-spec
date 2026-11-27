;;;; src/patch/parse.lisp
;;;;
;;;; Reading a unified diff.  The text before the first "--- " line is the
;;;; header.  Each file pair is "--- PATH" and "+++ PATH" (the same, plain,
;;;; relative path; no "a/" or "b/" prefix, no renames, no creation or
;;;; deletion), followed by hunks.  A hunk is read by its counts, so a
;;;; deleted line that starts with "-- " is no confusion.

(in-package #:cl-ansi-spec/patch)

(defstruct (patch (:constructor make-patch (name header files)))
  "A patch: its NAME (file name), the HEADER text before the first file
pair, and its FILES, a list of FILE-PATCH."
  name header files)

(defstruct (file-patch (:constructor make-file-patch (path line hunks)))
  "The hunks of one file: PATH relative to the tree, LINE of its \"---\"
line in the patch text, HUNKS in file order."
  path line hunks)

(defstruct (hunk (:constructor make-hunk))
  "One hunk.  PATCH-NAME and INDEX (from 1, in the patch) name it in
errors; LINE is its \"@@\" line in the patch text.  OLD-START and
OLD-COUNT are in the pristine file; NEW-COUNT is checked against the
lines, NEW-START is kept as the patch states it and not used.  LINES is a list
of (OP . TEXT), OP one of :CONTEXT, :DELETE, :ADD.  The flags say the
last old (new) line has no newline at the end of the file."
  patch-name index line old-start old-count new-start new-count lines
  old-no-newline-p new-no-newline-p)

(defun hunk-old-lines (hunk)
  "The texts of the lines HUNK expects in the pristine file, in order."
  (loop for (op . text) in (hunk-lines hunk)
        unless (eq op :add) collect text))

(defun hunk-new-lines (hunk)
  "The texts of the lines HUNK leaves in the patched file, in order."
  (loop for (op . text) in (hunk-lines hunk)
        unless (eq op :delete) collect text))

(defun split-lines (text)
  "Split TEXT at newlines; return the lines and whether TEXT ends with a
newline (true for empty TEXT, which has no lines)."
  (let ((lines '()) (start 0) (length (length text)))
    (loop for end = (position #\Newline text :start start)
          while end
          do (push (subseq text start end) lines)
             (setf start (1+ end)))
    (cond ((= start length) (values (nreverse lines) t))
          (t (push (subseq text start) lines)
             (values (nreverse lines) nil)))))

(defun starts-with-p (prefix string)
  (and (>= (length string) (length prefix))
       (string= prefix string :end2 (length prefix))))

(defun syntax-error (name line reason &rest arguments)
  (error 'patch-syntax-error :patch name :line line
                             :reason (apply #'format nil reason arguments)))

(defun safe-path-p (path)
  "True iff PATH is not empty, not absolute and has no \"..\" component."
  (not (or (zerop (length path))
           (char= (char path 0) #\/)
           (member ".." (uiop:split-string path :separator "/")
                   :test #'string=))))

(defun parse-file-path (name line text prefix)
  "The path of a \"--- \" or \"+++ \" line TEXT (PREFIX stripped; a tab
and a time stamp after the path are ignored)."
  (let* ((rest (subseq text (length prefix)))
         (path (subseq rest 0 (position #\Tab rest))))
    (unless (safe-path-p path)
      (error 'unsafe-patch-path :patch name :line line :path path
                               ))
    path))

(defun parse-range (name line text start)
  "Parse \"S\" or \"S,C\" in TEXT from START; return S, C (1 when omitted)
and the end position."
  (flet ((number-at (from)
           (let ((end (or (position-if-not #'digit-char-p text :start from)
                          (length text))))
             (when (= end from)
               (syntax-error name line "malformed hunk header ~S" text))
             (values (parse-integer text :start from :end end) end))))
    (multiple-value-bind (first end) (number-at start)
      (if (and (< end (length text)) (char= (char text end) #\,))
          (multiple-value-bind (count end) (number-at (1+ end))
            (values first count end))
          (values first 1 end)))))

(defun parse-hunk-header (name line text)
  "Return the four numbers of a \"@@ -S,C +S,C @@\" line."
  (unless (starts-with-p "@@ -" text)
    (syntax-error name line "expected a hunk header, found ~S" text))
  (multiple-value-bind (old-start old-count end) (parse-range name line text 4)
    (unless (starts-with-p " +" (subseq text end))
      (syntax-error name line "malformed hunk header ~S" text))
    (multiple-value-bind (new-start new-count end)
        (parse-range name line text (+ end 2))
      (unless (starts-with-p " @@" (subseq text end))
        (syntax-error name line "malformed hunk header ~S" text))
      (values old-start old-count new-start new-count))))

(defun parse-hunk (name index lines line)
  "Read one hunk whose header is (FIRST LINES) at patch line LINE.  Return
the hunk and the remaining lines."
  (multiple-value-bind (old-start old-count new-start new-count)
      (parse-hunk-header name line (first lines))
    (let ((remaining (rest lines)) (line-number (1+ line))
          (old-left old-count) (new-left new-count)
          (body '()) (old-flag nil) (new-flag nil)
          (old-marked nil) (new-marked nil))
      (flet ((read-markers ()
               ;; "\ No newline at end of file" applies to the line before.
               (loop while (and remaining (starts-with-p "\\" (first remaining)))
                     do (let ((op (car (first body))))
                          (unless body
                            (syntax-error name line-number "stray \"\\\" line"))
                          (when (member op '(:context :delete))
                            (setf old-flag t old-marked (length body)))
                          (when (member op '(:context :add))
                            (setf new-flag t new-marked (length body))))
                        (pop remaining)
                        (incf line-number))))
        (loop while (or (plusp old-left) (plusp new-left))
              do (unless remaining
                   (syntax-error name line-number
                                 "hunk ends early (counts ~D,~D left)"
                                 old-left new-left))
                 (let* ((text (pop remaining))
                        (op (and (plusp (length text))
                                 (case (char text 0)
                                   (#\Space :context) (#\- :delete) (#\+ :add)))))
                   (unless op
                     (syntax-error name line-number
                                   "line ~S is not a context, deletion or addition"
                                   text))
                   (when (and (member op '(:context :delete)) (zerop old-left))
                     (syntax-error name line-number "more old lines than the count"))
                   (when (and (member op '(:context :add)) (zerop new-left))
                     (syntax-error name line-number "more new lines than the count"))
                   (when (member op '(:context :delete)) (decf old-left))
                   (when (member op '(:context :add)) (decf new-left))
                   (push (cons op (subseq text 1)) body)
                   (incf line-number)
                   (read-markers)))
        (read-markers))
      (setf body (nreverse body))
      ;; A marker must follow the last line of its side.
      (progn
        (when (and old-marked
                   (find-if (lambda (entry) (member (car entry) '(:context :delete)))
                            body :start old-marked))
          (syntax-error name line "\"No newline\" marker before the end of the old side"))
        (when (and new-marked
                   (find-if (lambda (entry) (member (car entry) '(:context :add)))
                            body :start new-marked))
          (syntax-error name line "\"No newline\" marker before the end of the new side"))
        )
      (values (make-hunk :patch-name name :index index :line line
                         :old-start old-start :old-count old-count
                         :new-start new-start :new-count new-count
                         :lines body
                         :old-no-newline-p old-flag :new-no-newline-p new-flag)
              remaining line-number))))

(defun parse-file-patch (name lines line hunk-index)
  "Read a file pair and its hunks from LINES (at patch line LINE).  Return
the file patch, the remaining lines, the next line number and the next
hunk number."
  (let ((old (parse-file-path name line (first lines) "--- ")))
    (unless (and (second lines) (starts-with-p "+++ " (second lines)))
      (syntax-error name (1+ line) "expected a \"+++ \" line after \"--- \""))
    (let ((new (parse-file-path name (1+ line) (second lines) "+++ ")))
      (unless (string= old new)
        (syntax-error name (1+ line) "~S is patched into ~S: renames are not supported"
                      old new)))
    (let ((remaining (cddr lines)) (line-number (+ line 2)) (hunks '()))
      (loop while (and remaining (starts-with-p "@@" (first remaining)))
            do (multiple-value-bind (hunk rest next)
                   (parse-hunk name hunk-index remaining line-number)
                 (push hunk hunks)
                 (incf hunk-index)
                 (setf remaining rest line-number next)))
      (unless hunks
        (syntax-error name line-number "no hunk for ~S" old))
      (values (make-file-patch old line (nreverse hunks))
              remaining line-number hunk-index))))

(defun parse-patch (text &key (name "<patch>"))
  "Parse TEXT, a unified diff, into a PATCH called NAME.  Signal
PATCH-SYNTAX-ERROR (or UNSAFE-PATCH-PATH) when it is malformed."
  (let* ((lines (split-lines text))
         (header-end (position-if (lambda (line) (starts-with-p "--- " line))
                                  lines)))
    (unless header-end
      (syntax-error name nil "no file to patch (no \"--- \" line)"))
    (let ((header (format nil "~{~A~%~}" (subseq lines 0 header-end)))
          (remaining (nthcdr header-end lines))
          (line-number (1+ header-end))
          (hunk-index 1)
          (files '()))
      (loop while remaining
            do (unless (starts-with-p "--- " (first remaining))
                 (syntax-error name line-number "unexpected line ~S"
                               (first remaining)))
               (multiple-value-bind (file rest next index)
                   (parse-file-patch name remaining line-number hunk-index)
                 (push file files)
                 (setf remaining rest line-number next hunk-index index)))
      (make-patch name header (nreverse files)))))

(defun read-patch-file (pathname)
  "Parse the patch file PATHNAME; its name is the file name."
  (parse-patch (uiop:read-file-string pathname :external-format :utf-8)
               :name (file-namestring pathname)))
