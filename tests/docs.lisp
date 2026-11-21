;;;; tests/docs.lisp
;;;;
;;;; The docs reference check: every repository path and `make` target the
;;;; docs name in backticks exists, unless it is marked as planned.  The
;;;; rules are stated in docs/process.md, "Docs name what exists"; this
;;;; file implements them:
;;;;
;;;; - Checked files: CHECKED-DOC-FILES.
;;;; - Code spans follow Markdown: a run of N backticks closes at the next
;;;;   run of exactly N, within one paragraph; fenced blocks (``` or ~~~,
;;;;   closed by the same character, at least as many) are skipped.
;;;; - A path is a span without whitespace that starts with one of
;;;;   *CHECKED-PREFIXES*, optionally followed by ":<line>" or
;;;;   ":<line>-<line>".  Placeholders (<, > or …) are skipped; a * makes
;;;;   it a glob that must match something.
;;;; - A make target is the first operand after each word "make" of a span.
;;;; - Planned: "(planned)" right after the closing backticks; every line
;;;;   of an unticked "- [ ]" item of a docs/plan/ file; every line of the
;;;;   Milestones section of PLAN.md.

(in-package #:cl-ansi-spec/tests)

(define-test docs
  :parent cl-ansi-spec
  :description "The docs name only what exists, or mark it as planned.")

;;; Repository files

(defun repository-root ()
  "Return the directory holding cl-ansi-spec.asd."
  (asdf:system-relative-pathname "cl-ansi-spec" ""))

(defun wildcard-match-p (pattern string)
  "Return true iff STRING matches PATTERN, where * matches any run of
characters (none included, a leading dot included) and every other
character matches itself."
  (labels ((match (p s)
             (cond ((= p (length pattern)) (= s (length string)))
                   ((char= (char pattern p) #\*)
                    (loop for i from s to (length string)
                            thereis (match (1+ p) i)))
                   (t (and (< s (length string))
                           (char= (char pattern p) (char string s))
                           (match (1+ p) (1+ s)))))))
    (match 0 0)))

(defun entry-name (pathname)
  "Return the last name of PATHNAME, a file or a directory."
  (if (uiop:directory-pathname-p pathname)
      (car (last (pathname-directory pathname)))
      (file-namestring pathname)))

(defun glob (pattern &optional (root (repository-root)))
  "Return the files and directories under ROOT that match PATTERN, a
relative Unix path whose segments may hold * wildcards.  A pattern ending
in / matches directories only; otherwise the last segment matches files
and directories alike, as a path written without a slash may name either."
  (let ((directory-only (uiop:string-suffix-p pattern "/"))
        (segments (remove "" (uiop:split-string pattern :separator "/")
                          :test #'string=)))
    (labels ((walk (directory segments)
               (let* ((segment (first segments))
                      (last-p (null (rest segments)))
                      (entries (if (and last-p (not directory-only))
                                   (append (uiop:subdirectories directory)
                                           (uiop:directory-files directory))
                                   (uiop:subdirectories directory))))
                 (loop for entry in entries
                       when (wildcard-match-p segment (entry-name entry))
                         append (if last-p
                                    (list entry)
                                    (walk entry (rest segments)))))))
      (and segments (walk root segments)))))

(defun makefile-rule-names (lines)
  "Return the names of the rules defined by LINES, a Makefile's lines: the
words before the colon of every rule line.  Recipe lines, comments,
variable assignments (=, :=, ::=, ?=, +=), special targets (.PHONY, ...)
and pattern rules (%) are not rules a reader can name."
  (loop for line in lines
        for colon = (position #\: line)
        when (and colon
                  (plusp (length line))
                  (not (member (char line 0) '(#\Tab #\Space #\#)))
                  (not (find #\= line :end colon))
                  (not (eql (position #\= line :start colon) (1+ colon)))
                  (not (uiop:string-prefix-p "::=" (subseq line colon))))
          append (remove-if (lambda (name)
                              (or (string= name "")
                                  (char= (char name 0) #\.)
                                  (find #\% name)))
                            (uiop:split-string (subseq line 0 colon)))))

(defun makefile-targets (&optional (root (repository-root)))
  "Return the rule names of the Makefile under ROOT."
  (makefile-rule-names (uiop:read-file-lines (merge-pathnames "Makefile" root))))

;;; Reading the docs

(defparameter *checked-prefixes*
  '("docs/" "src/" "tests/" "tools/" "spec/" "patches/" ".github/" ".claude/"
    "vendor/" "schema/")
  "A code span starting with one of these is a repository path.")

(defun leading-spaces (line)
  "Return the number of spaces LINE starts with."
  (or (position #\Space line :test-not #'char=) (length line)))

(defun blank-line-p (line)
  "Return true iff LINE holds only spaces."
  (= (leading-spaces line) (length line)))

(defun fence-opening (line)
  "If LINE opens a fenced code block, return the fence character and the
length of its run as two values; otherwise return NIL."
  (let* ((body (string-left-trim " " line))
         (char (and (plusp (length body)) (char body 0))))
    (when (member char '(#\` #\~))
      (let ((run (or (position char body :test-not #'char=) (length body))))
        (when (>= run 3)
          (values char run))))))

(defun fence-closes-p (line char run)
  "Return true iff LINE closes a fence of RUN characters CHAR: at least as
many of the same character and nothing else."
  (let ((body (string-trim " " line)))
    (and (>= (length body) run)
         (every (lambda (c) (char= c char)) body))))

(defun unfenced-lines (lines)
  "Return LINES with the lines of fenced code blocks, fences included,
replaced by empty strings, so that line numbers are kept."
  (loop with fence-char = nil and fence-run = 0
        for line in lines
        collect (cond (fence-char
                       (when (fence-closes-p line fence-char fence-run)
                         (setf fence-char nil))
                       "")
                      (t (multiple-value-bind (char run) (fence-opening line)
                           (cond (char (setf fence-char char fence-run run)
                                       "")
                                 (t line)))))))

(defun line-planned-flags (lines kind)
  "Return a vector telling, for each of LINES, whether everything it names
counts as planned.  KIND is :plan for a docs/plan/ file (unticked items),
:index for PLAN.md (the Milestones section), :doc otherwise."
  (let ((flags (make-array (length lines) :initial-element nil))
        (item-indent nil)               ; indentation of the open "- [ ]" item
        (in-milestones nil))
    (loop for line in lines
          for i from 0
          for indent = (leading-spaces line)
          for body = (subseq line indent)
          do (ecase kind
               (:doc)
               (:index
                (when (uiop:string-prefix-p "## " line)
                  (setf in-milestones
                        (string= (string-right-trim " " line) "## Milestones")))
                (setf (aref flags i) in-milestones))
               (:plan
                (cond ((and item-indent (not (blank-line-p line))
                            (> indent item-indent)))
                      ((uiop:string-prefix-p "- [ ]" body)
                       (setf item-indent indent))
                      ((not (blank-line-p line))
                       (setf item-indent nil)))
                (setf (aref flags i) (and item-indent t)))))
    flags))

(defun paragraph-span-scan (text)
  "Return the code spans of TEXT, one paragraph, as (content start end):
START and END delimit the whole span, backticks included."
  (flet ((run-end (start)
           (or (position #\` text :start start :test-not #'char=)
               (length text))))
    (let ((spans '())
          (pos 0))
      (loop for open = (position #\` text :start pos)
            while open
            do (let* ((open-end (run-end open))
                      (width (- open-end open))
                      (close (loop for candidate = (position #\` text :start open-end)
                                     then (position #\` text :start (run-end candidate))
                                   while candidate
                                   when (= (- (run-end candidate) candidate) width)
                                     return candidate)))
                 (cond (close
                        (push (list (string-trim " " (subseq text open-end close))
                                    open (+ close width))
                              spans)
                        (setf pos (+ close width)))
                       (t (setf pos open-end)))))
      (nreverse spans))))

(defun paragraphs (lines)
  "Return the paragraphs of LINES as (index . lines), INDEX being the
position of the paragraph's first line: runs of non-blank lines."
  (let ((result '())
        (start nil))
    (loop for line in lines
          for i from 0
          do (cond ((blank-line-p line)
                    (when start
                      (push (cons start (subseq lines start i)) result)
                      (setf start nil)))
                   ((null start) (setf start i))))
    (when start
      (push (cons start (subseq lines start)) result))
    (nreverse result)))

(defun code-spans (lines)
  "Return the code spans of LINES, a document's lines, as
(content line-index planned-marker-p), skipping fenced blocks.  A span
stays within its paragraph and may cross line ends, which count as spaces;
it is reported at the line it starts on."
  (loop for (start . paragraph) in (paragraphs (unfenced-lines lines))
        for text = (format nil "~{~A~^ ~}" paragraph)
        for line-starts = (loop with offset = 0
                                for line in paragraph
                                collect offset
                                do (incf offset (1+ (length line))))
        append (loop for (content span-start span-end) in (paragraph-span-scan text)
                     collect (list content
                                   (+ start -1 (count-if (lambda (offset)
                                                           (<= offset span-start))
                                                         line-starts))
                                   (uiop:string-prefix-p
                                    " (planned)" (subseq text span-end))))))

(defun placeholder-p (string)
  "Return true iff STRING holds a placeholder character: <, > or …."
  (find-if (lambda (c) (find c "<>…")) string))

(defun make-targets-in (words)
  "Return the targets of every make command in WORDS, a code span split at
whitespace: the first operand after each word \"make\" that is not an
option or a variable assignment, unless a placeholder.  A shell separator
ends a command."
  (loop for tail on words
        when (string= (first tail) "make")
          append (loop for word in (rest tail)
                       until (member word '("&&" "||" "|" ";") :test #'string=)
                       unless (or (uiop:string-prefix-p "-" word) (find #\= word))
                         return (unless (placeholder-p word) (list word)))))

(defun strip-line-suffix (path)
  "Remove a trailing \":<line>\", \":<line>-<line>\" or \":\" from PATH."
  (let ((colon (position #\: path :from-end t)))
    (if (and colon
             (every (lambda (c) (or (digit-char-p c) (char= c #\-)))
                    (subseq path (1+ colon))))
        (subseq path 0 colon)
        path)))

(defun span-references (span)
  "Return the references a code span names as (:make target) and
(:path path) lists.  A span with whitespace names only make targets: a
command line is not checked otherwise."
  (let ((words (uiop:split-string span :separator '(#\Space #\Tab))))
    (cond ((member "make" words :test #'string=)
           (mapcar (lambda (target) (list :make target)) (make-targets-in words)))
          ((or (rest words)
               (placeholder-p span)
               (notany (lambda (prefix) (uiop:string-prefix-p prefix span))
                       *checked-prefixes*))
           '())
          (t (list (list :path (strip-line-suffix span)))))))

(defun doc-references (text kind)
  "Return the references TEXT names and does not mark as planned, as
(:make target line) or (:path path line), LINE 1-based.  KIND as for
LINE-PLANNED-FLAGS."
  (let* ((lines (mapcar (lambda (line) (string-right-trim '(#\Return) line))
                        (uiop:split-string text :separator '(#\Newline))))
         (planned (line-planned-flags lines kind)))
    (loop for (span index marked) in (code-spans lines)
          unless (or marked (aref planned index))
            append (mapcar (lambda (reference) (append reference (list (1+ index))))
                           (span-references span)))))

(defun reference-exists-p (reference &key (root (repository-root))
                                         (targets (makefile-targets root)))
  "Return true iff REFERENCE, as returned by DOC-REFERENCES, names one of
TARGETS or an existing path under ROOT."
  (ecase (first reference)
    (:make (member (second reference) targets :test #'string=))
    (:path (glob (second reference) root))))

(defun checked-doc-files (&optional (root (repository-root)))
  "Return the docs the reference check reads as (file . kind): AGENTS.md,
PLAN.md, docs/*.md, docs/plan/*.md and .claude/skills/*/SKILL.md.
docs/history/ is not read: it describes the past."
  (flet ((files (pattern kind)
           (mapcar (lambda (file) (cons file kind)) (glob pattern root))))
    (append (files "AGENTS.md" :doc)
            (files "PLAN.md" :index)
            (files "docs/*.md" :doc)
            (files "docs/plan/*.md" :plan)
            (files ".claude/skills/*/SKILL.md" :doc))))

(defun broken-doc-references (&optional (root (repository-root)))
  "Return a description of every reference in the checked docs that names
nothing, as strings \"FILE:LINE: REFERENCE\"."
  (let ((targets (makefile-targets root)))
    (loop for (file . kind) in (checked-doc-files root)
          append (loop for reference in (doc-references
                                         (uiop:read-file-string file) kind)
                       unless (reference-exists-p reference :root root
                                                            :targets targets)
                         collect (format nil "~A:~D: ~A"
                                         (enough-namestring file root)
                                         (third reference)
                                         (second reference))))))

;;; Tests

(define-test wildcard-matching
  :parent docs
  (true (wildcard-match-p "*.md" "PLAN.md"))
  (true (wildcard-match-p "*" ""))
  (true (wildcard-match-p "*" ".claude"))
  (true (wildcard-match-p "a*b*c" "abbc"))
  (false (wildcard-match-p "*.md" "PLAN.mdx"))
  (false (wildcard-match-p "a" "")))

(define-test globbing
  :parent docs
  (is = 1 (length (glob "AGENTS.md")))
  (true (glob "docs/"))
  (true (glob "docs"))
  (true (glob ".claude/skills"))
  (false (glob "AGENTS.md/"))
  (true (glob "docs/*.md"))
  (true (glob ".claude/skills/*/SKILL.md"))
  (false (glob "docs/*.nothing"))
  (false (glob "no-such-directory/"))
  (false (glob "")))

(define-test makefile-rules
  :parent docs
  (is equal '("all" "a" "b" "deps")
      (makefile-rule-names
       '("LISP := x" "X ?= y" "Y += z" "Z ::= w" "export A := b"
         ".PHONY: all a" "all: test" "a b: c" "%.o: %.c"
         "	echo a: b" "# c: d" "deps:")))
  (let ((targets (makefile-targets)))
    (true (member "test" targets :test #'string=))
    (true (member "tokens" targets :test #'string=))))

(define-test span-classification
  :parent docs
  (is equal '((:path "docs/process.md")) (span-references "docs/process.md"))
  (is equal '((:path "src/tex/state.lisp")) (span-references "src/tex/state.lisp:12"))
  (is equal '((:path "src/a.lisp")) (span-references "src/a.lisp:12-20"))
  (is equal '((:path "src/a.lisp")) (span-references "src/a.lisp:"))
  (is equal '((:make "tokens")) (span-references "make tokens FILE=… LINES=a-b"))
  (is equal '((:make "test")) (span-references "make test 2>&1 | tail -5"))
  (is equal '((:make "test")) (span-references "make -j4 test"))
  (is equal '((:make "tokens")) (span-references "make FILE=x tokens"))
  (is equal '((:make "deps") (:make "test"))
      (span-references "cd x && make deps && make test"))
  (is equal '() (span-references "make"))
  (is equal '() (span-references "make <target>"))
  (is equal '() (span-references "docs/plan/<id>.md"))
  (is equal '() (span-references "docs/…"))
  (is equal '() (span-references "dict-conses.tex:1702"))
  (is equal '() (span-references "cl-ansi-spec/expand"))
  (is equal '() (span-references "tools/x.lisp --flag"))
  (is equal '() (span-references "(cd spec/tex && sha256sum -c)")))

(defun references-in (kind &rest lines)
  "Return the DOC-REFERENCES of a document of KIND made of LINES."
  (doc-references (format nil "~{~A~%~}" lines) kind))

(define-test planned-marker
  :parent docs
  (is equal '((:path "docs/a.md" 1))
      (references-in :doc "`docs/a.md` and `docs/b.md` (planned)."))
  (is equal '((:path "docs/b.md" 1))
      (references-in :doc "`docs/a.md` (planned), then `docs/b.md` planned"))
  (is equal '()
      (references-in :doc "`docs/a.md`" "(planned): a line end is a space.")))

(define-test spans-and-fences
  :parent docs
  (is equal '((:path "docs/x.md" 5))
      (references-in :doc "Text" "```lisp" "`docs/in-fence.md`" "```" "`docs/x.md`"))
  (is equal '((:path "docs/x.md" 6))
      (references-in :doc "````" "```" "`docs/in-fence.md`" "```" "````" "`docs/x.md`"))
  (is equal '((:path "docs/x.md" 4))
      (references-in :doc "~~~" "`docs/in-fence.md`" "~~~" "`docs/x.md`"))
  (is equal '((:path "docs/x.md" 1))
      (references-in :doc "``docs/x.md``"))
  (is equal '((:path "docs/x.md" 1))
      (references-in :doc "`` a`b `` `docs/x.md`"))
  (is equal '((:path "docs/x.md" 1))
      (references-in :doc "a `docs/x.md" "` b"))
  (is equal '((:path "docs/x.md" 3))
      (references-in :doc "a stray ` here" "" "`docs/x.md`"))
  (is equal '((:path "docs/x.md" 1))
      (references-in :doc (format nil "`docs/x.md`~C" #\Return)))
  (is equal '((:make "test" 1))
      (references-in :doc "| `make test` | `docs/<topic>.md` |")))

(define-test plan-items
  :parent docs
  (is equal '((:path "src/done.lisp" 1) (:path "src/after.lisp" 7))
      (references-in :plan
                     "- [x] **0.** `src/done.lisp`"
                     "- [ ] **1.** `src/new.lisp`,"
                     "      continued `src/more.lisp`"
                     "      - [x] nested `src/nested.lisp`"
                     ""
                     "      `src/after-blank.lisp`"
                     "Done when `src/after.lisp`.")))

(define-test plan-index-milestones
  :parent docs
  (is equal '((:path "docs/a.md" 2) (:path "docs/c.md" 6))
      (references-in :index
                     "## Status"
                     "`docs/a.md`"
                     "## Milestones "
                     "### M9"
                     "`docs/b.md`"
                     "## Open questions `docs/c.md`")))

(define-test missing-references-are-reported
  :parent docs
  (false (reference-exists-p '(:path "docs/no-such-file.md" 1)))
  (false (reference-exists-p '(:make "no-such-target" 1)))
  (true (reference-exists-p '(:path "docs/process.md" 1)))
  (true (reference-exists-p '(:make "test" 1))))

(define-test docs-name-what-exists
  :parent docs
  :description "Every reference in the checked docs exists or is planned."
  (is equal '() (broken-doc-references)))
