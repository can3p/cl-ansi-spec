;;;; tests/inventory.lisp
;;;;
;;;; The vocabulary inventory (src/inventory/): fixtures for each rule, and
;;;; cross-checks over the real sources.

(in-package #:cl-ansi-spec/tests)

(define-test inventory
  :parent cl-ansi-spec
  :description "Surveying definitions and uses without expansion.")

(defun tex-alist-resolver (files)
  "Return a resolver serving FILES, an alist of (name . text), that tries
NAME.tex first as TeX does."
  (let ((resolver (alist-resolver files)))
    (lambda (name)
      (or (funcall resolver (concatenate 'string name ".tex"))
          (funcall resolver name)))))

(defun survey-of (files &optional (job (car (first files))))
  "Survey JOB over FILES, an alist of (name . text)."
  (cl-ansi-spec/inventory:survey-job job :resolver (tex-alist-resolver files)))

(defun definitions-named (survey name)
  (remove name (cl-ansi-spec/inventory:survey-definitions survey)
          :key #'cl-ansi-spec/inventory:definition-name :test-not #'string=))

(defun the-definition (survey name)
  (let ((definitions (definitions-named survey name)))
    (true (= 1 (length definitions)) "~A defined ~D times" name (length definitions))
    (first definitions)))

(defun uses-of (survey name)
  "Return NAME's (text body uncertain) use counts summed over files."
  (let ((counts (cl-ansi-spec/inventory:name-counts survey name)))
    (list (reduce #'+ counts :key #'second)
          (reduce #'+ counts :key #'third)
          (reduce #'+ counts :key #'fourth))))

(define-test definition-forms
  :parent inventory
  (let ((survey (survey-of
                 '(("job.tex" . "\\def\\a{x}\\gdef\\b#1{#1}\\edef\\c{y}\\xdef\\d{z}
\\long\\def\\e#1{#1}\\global\\def\\f{}\\long\\global\\def\\g{}
\\let\\h=\\a \\let\\i\\a \\let\\j = x
\\chardef\\other=12 \\mathchardef\\m=\"0123 \\countdef\\n=7
\\newif\\iffoo \\newcount\\k \\font\\tenrm=cmr10
\\def\\al{\\a} \\def\\na#1{\\a}
{\\def\\local{}}
")))))
    (flet ((kind (name)
             (cl-ansi-spec/inventory:definition-kind (the-definition survey name))))
      (is equal '(:def :gdef :edef :xdef :def :def :def)
          (mapcar #'kind '("\\a" "\\b" "\\c" "\\d" "\\e" "\\f" "\\g")))
      (is equal '(:let :let :let :chardef :mathchardef :countdef :newif :newif :newif
                  :newcount :font)
          (mapcar #'kind '("\\h" "\\i" "\\j" "\\other" "\\m" "\\n" "\\iffoo"
                           "\\footrue" "\\foofalse" "\\k" "\\tenrm"))))
    (flet ((field (reader name) (funcall reader (the-definition survey name))))
      (is equal '(nil t nil t nil t t)
          (mapcar (lambda (name)
                    (field #'cl-ansi-spec/inventory:definition-global-p name))
                  '("\\a" "\\b" "\\c" "\\d" "\\e" "\\f" "\\g")))
      (is equal '(nil nil nil nil t nil t)
          (mapcar (lambda (name)
                    (field #'cl-ansi-spec/inventory:definition-long-p name))
                  '("\\a" "\\b" "\\c" "\\d" "\\e" "\\f" "\\g")))
      (is equal '("\\a" "\\a" "x 11" "\\a" nil)
          (mapcar (lambda (name)
                    (field #'cl-ansi-spec/inventory:definition-alias name))
                  '("\\h" "\\i" "\\j" "\\al" "\\na")))
      (is equal '(12 #x123 7)
          (mapcar (lambda (name)
                    (field #'cl-ansi-spec/inventory:definition-value name))
                  '("\\other" "\\m" "\\n")))
      (is = 0 (field #'cl-ansi-spec/inventory:definition-depth "\\a"))
      (is = 1 (field #'cl-ansi-spec/inventory:definition-depth "\\local"))
      (is = 4 (field #'cl-ansi-spec/inventory:definition-line "\\other")))))

(define-test nested-definitions-and-body-uses
  :parent inventory
  (let ((survey (survey-of
                 '(("job.tex" . "\\def\\wrap#1{\\def\\inner##1{\\use##1}\\let\\al=\\use}
\\wrap x \\use \\use")))))
    (let ((inner (the-definition survey "\\inner"))
          (alias (the-definition survey "\\al")))
      (is equal "\\wrap" (cl-ansi-spec/inventory:definition-parent inner))
      (is eq nil (cl-ansi-spec/inventory:definition-depth inner))
      (is equal "\\wrap" (cl-ansi-spec/inventory:definition-parent alias))
      (is equal "\\use" (cl-ansi-spec/inventory:definition-alias alias)))
    (is equal '(2 1 0) (uses-of survey "\\use"))
    (is equal '(1 0 0) (uses-of survey "\\wrap"))
    (is equal '(0 0 0) (uses-of survey "\\inner"))
    (is eq :nested (cl-ansi-spec/inventory:name-class survey "\\inner"))
    (is eq :defined (cl-ansi-spec/inventory:name-class survey "\\wrap"))
    (is eq :primitive (cl-ansi-spec/inventory:name-class survey "\\use"))))

(define-test literal-catcodes-are-applied
  :parent inventory
  (let ((survey (survey-of
                 '(("job.tex" . "{\\catcode`\\!=0 !foo}!bar
\\catcode`\\,\\active \\catcode'041=\\active \\chardef\\other=12 \\catcode`\\?=\\other
,? \\input next ")
                   ("next.tex" . "!")))))
    (is equal '(1 0 0) (uses-of survey "\\foo"))
    (is equal '(0 0 0) (uses-of survey "\\bar"))
    ;; , and ! are active from line 2 on, also in the next file; ? is other.
    (is equal '(1 0 0) (uses-of survey ","))
    (is equal '(1 0 0) (uses-of survey "!"))
    (is equal '(0 0 0) (uses-of survey "?"))
    (is equal '((#.(char-code #\!) 0 :applied) (#.(char-code #\,) 13 :applied)
                (#.(char-code #\!) 13 :applied) (#.(char-code #\?) 12 :applied))
        (mapcar (lambda (note)
                  (list (cl-ansi-spec/inventory:catcode-note-code note)
                        (cl-ansi-spec/inventory:catcode-note-value note)
                        (cl-ansi-spec/inventory:catcode-note-how note)))
                (cl-ansi-spec/inventory:survey-catcode-notes survey)))))

(define-test literal-numbers-and-groups
  :parent inventory
  (let ((survey (survey-of
                 '(("job.tex" . "\\chardef\\a=\"AF \\chardef\\b='17 \\chardef\\c=`\\a
\\chardef\\d=`\\a\\x \\chardef\\e=`b \\chardef\\f=\\count
\\begingroup\\catcode`\\!=0 !in\\endgroup !out
\\global \\def\\g{}{\\endgroup}\\begingroup}")))))
    (is equal '(#xAF #o17 97 97 98 nil)
        (mapcar (lambda (name)
                  (cl-ansi-spec/inventory:definition-value
                   (the-definition survey name)))
                '("\\a" "\\b" "\\c" "\\d" "\\e" "\\f")))
    (is equal '(1 0 0) (uses-of survey "\\x"))
    (is equal '(1 0 0) (uses-of survey "\\in"))
    (is equal '(0 0 0) (uses-of survey "\\out"))
    (true (cl-ansi-spec/inventory:definition-global-p (the-definition survey "\\g")))
    (is equal '(:applied :group-mismatch :group-mismatch)
        (mapcar #'cl-ansi-spec/inventory:catcode-note-how
                (cl-ansi-spec/inventory:survey-catcode-notes survey)))))

(define-test macro-catcode-changes-make-lines-uncertain
  :parent inventory
  (let ((survey (survey-of
                 '(("job.tex" . "\\def\\mk{\\catcode`\\!=0 }\\def\\act{\\catcode`\\,=13 }
\\def\\viamk{\\mk}\\act
a, \\x
\\viamk \\y
\\z !w
\\z")))))
    ;; , may only become active: not structural, nothing uncertain.
    (is equal '(1 0 0) (uses-of survey "\\x"))
    ;; ! may become an escape character through \viamk -> \mk.
    (is equal '(("job.tex" . 5))
        (cl-ansi-spec/inventory:survey-uncertain-lines survey))
    (is equal '(2 0 1) (uses-of survey "\\z"))
    (is equal '((:call "\\act") (:call "\\viamk"))
        (mapcar #'cl-ansi-spec/inventory:catcode-note-how
                (cl-ansi-spec/inventory:survey-catcode-notes survey)))))

(define-test input-records
  :parent inventory
  (let ((survey (survey-of
                 '(("job.tex" . "\\input sub \\input gone \\input\\jobname.toc
\\input sub.tex \\input sub-file ")
                   ("sub.tex" . "\\s")
                   ("sub-file.tex" . "\\t")))))
    (is equal '(("sub" :found) ("gone" :missing) ("\\jobname" :computed)
                ("sub.tex" :repeated) ("sub-file" :found))
        (mapcar (lambda (record)
                  (list (cl-ansi-spec/inventory:input-record-target record)
                        (cl-ansi-spec/inventory:input-record-status record)))
                (cl-ansi-spec/inventory:survey-inputs survey)))
    (is equal '("job.tex" "sub.tex" "sub-file.tex")
        (cl-ansi-spec/inventory:survey-files survey))
    (is equal '(1 0 0) (uses-of survey "\\s"))
    (is equal '(1 0 0) (uses-of survey "\\jobname"))))

(define-test input-macros-are-followed
  :parent inventory
  (let ((survey (survey-of
                 '(("job.tex" . "\\def\\inc #1#2{\\a\\input #2 \\b}
\\def\\dl #1.{\\input #1 }\\def\\plain{\\input x }
\\inc{\\x}{sub}\\inc\\y{\\z}\\dl a.\\plain")
                   ("sub.tex" . "\\s")))))
    (is equal '(nil 2 0)
        (mapcar (lambda (name)
                  (cl-ansi-spec/inventory:definition-arity
                   (the-definition survey name)))
                '("\\dl" "\\inc" "\\plain")))
    (is equal '((2) (1) ())
        (mapcar (lambda (name)
                  (cl-ansi-spec/inventory:definition-input-parameters
                   (the-definition survey name)))
                '("\\inc" "\\dl" "\\plain")))
    (is equal '(("sub" :found "\\inc") ("\\z" :computed "\\inc")
                ("\\dl" :computed "\\dl"))
        (mapcar (lambda (record)
                  (list (cl-ansi-spec/inventory:input-record-target record)
                        (cl-ansi-spec/inventory:input-record-status record)
                        (cl-ansi-spec/inventory:input-record-macro record)))
                (cl-ansi-spec/inventory:survey-inputs survey)))
    ;; The arguments are read as text, ahead of the file.
    (is equal '(1 0 0) (uses-of survey "\\x"))
    (is equal '(1 0 0) (uses-of survey "\\s"))
    (is equal '(1 0 0) (uses-of survey "\\z"))))

(define-test merged-surveys-count-each-file-once
  :parent inventory
  (let* ((files '(("a.tex" . "\\input common \\x")
                  ("b.tex" . "\\input common \\x")
                  ("common.tex" . "\\c")))
         (merged (cl-ansi-spec/inventory:merge-surveys
                  (list (survey-of files "a") (survey-of files "b")))))
    (is equal '("a.tex" "common.tex" "b.tex")
        (cl-ansi-spec/inventory:survey-files merged))
    (is equal '(1 0 0) (uses-of merged "\\c"))
    (is equal '(2 0 0) (uses-of merged "\\x"))))

;;; The real sources

(defun raw-use-count (name files)
  "Count NAME in FILES by text: occurrences not followed by a letter, outside
comments (from an unescaped % to the end of the line)."
  (loop for file in files
        sum (loop for line in (uiop:read-file-lines (nth-value 1 (find-input-file file)))
                  for comment = (loop for i from 0 below (length line)
                                      when (and (char= (char line i) #\%)
                                                (or (zerop i)
                                                    (char/= (char line (1- i)) #\\)))
                                        return i)
                  for text = (subseq line 0 comment)
                  sum (loop with start = 0
                            for hit = (search name text :start2 start)
                            while hit
                            do (setf start (+ hit (length name)))
                            count (or (= start (length text))
                                      (not (alpha-char-p (char text start))))))))

(define-test survey-of-the-whole-spec
  :parent inventory
  :description "Every chapter job is surveyed; uses agree with a textual count."
  (let* ((surveys (mapcar #'cl-ansi-spec/inventory:survey-job
                          (cl-ansi-spec/inventory:chapter-jobs)))
         (merged (cl-ansi-spec/inventory:merge-surveys surveys))
         (files (cl-ansi-spec/inventory:survey-files merged)))
    ;; Commented out (chap-a.tex:10,14, setup-aux.tex:23) or never input.
    (is equal '("appendix-implem-defined.tex" "appendix-portability.tex"
                "setup-amfont.tex" "setup-boxfig.tex")
        (remove-if (lambda (file) (member file files :test #'string=))
                   (mapcar #'file-namestring (spec-files :type "tex"))))
    (dolist (name '("\\issue" "\\endissue" "\\begincom" "\\endcom" "\\term"
                    "\\param" "\\funref" "\\secref" "\\label"))
      ;; The textual count also sees the name in its definitions' heads and
      ;; as the target of a \let, which copies its meaning: not uses.
      (is = (- (raw-use-count name files)
               (length (definitions-named merged name))
               (count-if (lambda (definition)
                           (and (eq :let (cl-ansi-spec/inventory:definition-kind definition))
                                (equal name (cl-ansi-spec/inventory:definition-alias
                                             definition))))
                         (cl-ansi-spec/inventory:survey-definitions merged)))
          (reduce #'+ (uses-of merged name) :end 2)
          "Uses of ~A" name))
    (is = (first (uses-of merged "\\issue")) (first (uses-of merged "\\endissue")))
    (is equal '() (cl-ansi-spec/inventory:survey-uncertain-lines merged))))
