;;;; tools/vocab.lisp
;;;;
;;;; Print the vocabulary inventory (src/inventory/): which control
;;;; sequences the sources define and use, without expansion.
;;;;
;;;; Summary (default): a header, then one line per name,
;;;;   NAME<tab>CLASS<tab>DEFINED<tab>text T<tab>body B<tab>uncertain U<tab>files F
;;;; sorted by text uses, at most LIMIT lines.  CLASS is defined, nested,
;;;; plain or primitive; DEFINED is the first definition's kind and place,
;;;; with "+N" for N more.  With NAME, the details of one name instead.
;;;;
;;;; Usage: make vocab [JOB=chap-1] [FILE=setup-aux.tex] [NAME=\term] [LIMIT=40]
;;;; JOB defaults to every chapter job, each file counted once.  FILE
;;;; restricts the counts to one file.  LIMIT=0 prints every line.

(load (merge-pathnames "setup.lisp" *load-truename*))

(in-package #:cl-ansi-spec.tools)

(configure-asdf)
(let ((*standard-output* (make-broadcast-stream)))
  (asdf:load-system "cl-ansi-spec"))

(defpackage #:cl-ansi-spec.tools.vocab
  (:use #:cl #:cl-ansi-spec/inventory)
  (:import-from #:cl-ansi-spec.tools #:with-exit-status))

(in-package #:cl-ansi-spec.tools.vocab)

(defun env (name &optional default)
  "Return the environment variable NAME, or DEFAULT if unset or empty."
  (let ((value (uiop:getenv name)))
    (if (and value (string/= value "")) value default)))

(defun place (file line) (format nil "~A:~D" file line))

(defun definition-text (definition)
  "Describe DEFINITION in one line."
  (format nil "~(~A~) ~A~@[ depth ~D~]~:[~; global~]~:[~; long~]~@[ alias ~A~]~
~@[ value ~D~]~@[ nested in ~A~]~:[~; UNCERTAIN~]"
          (definition-kind definition)
          (place (definition-file definition) (definition-line definition))
          (definition-depth definition) (definition-global-p definition)
          (definition-long-p definition) (definition-alias definition)
          (definition-value definition) (definition-parent definition)
          (definition-uncertain-p definition)))

(defun print-header (survey plain)
  (let ((inputs (remove :found (survey-inputs survey) :key #'input-record-status)))
    (format t "# job ~A: ~D files, ~D definitions, ~D uses, ~D uncertain lines~%"
            (survey-job-name survey) (length (survey-files survey))
            (length (survey-definitions survey)) (length (survey-occurrences survey))
            (length (survey-uncertain-lines survey)))
    (format t "# plain.tex: ~D definitions~%" (length (survey-definitions plain)))
    (dolist (status '(:missing :repeated :computed))
      (let ((targets (mapcar #'input-record-target
                             (remove status inputs :key #'input-record-status
                                                   :test-not #'eq))))
        (when targets
          (format t "# inputs ~(~A~): ~D (~{~A~^ ~}~:[~; ...~])~%"
                  status (length targets) (subseq targets 0 (min 4 (length targets)))
                  (> (length targets) 4)))))
    (format t "# NAME	CLASS	DEFINED	TEXT	BODY	UNCERTAIN	FILES~%")))

(defun print-summary (survey plain file limit)
  "Print one line per name used or defined in SURVEY."
  (let ((table (count-table (survey-occurrences survey)))
        (definitions (make-hash-table :test 'equal))
        (rows '()))
    (dolist (definition (survey-definitions survey))
      (push definition (gethash (definition-name definition) definitions)))
    (flet ((add (name)
             (let* ((counts (remove-if-not (lambda (entry)
                                             (or (null file) (string= file (first entry))))
                                           (gethash name table)))
                    (defs (reverse (gethash name definitions))))
               (when (or counts (and defs (null file)))
                 (push (list name
                             (reduce #'+ counts :key #'second)
                             (reduce #'+ counts :key #'third)
                             (reduce #'+ counts :key #'fourth)
                             (length counts)
                             defs)
                       rows)))))
      (maphash (lambda (name entries) (declare (ignore entries)) (add name)) table)
      (maphash (lambda (name defs) (declare (ignore defs))
                 (unless (gethash name table) (add name)))
               definitions))
    (setf rows (sort rows (lambda (a b)
                            (or (> (second a) (second b))
                                (and (= (second a) (second b))
                                     (string< (first a) (first b)))))))
    (print-header survey plain)
    (loop for (name text body uncertain files defs) in rows
          for i from 0
          while (or (zerop limit) (< i limit))
          do (format t "~A	~(~A~)	~:[-~;~:*~A~]	text ~D	body ~D	uncertain ~D	files ~D~%"
                     name (name-class survey name plain)
                     (and defs (format nil "~(~A~) ~A~@[ +~D~]"
                                       (definition-kind (first defs))
                                       (place (definition-file (first defs))
                                              (definition-line (first defs)))
                                       (and (rest defs) (length (rest defs)))))
                     text body uncertain files))
    (when (and (plusp limit) (> (length rows) limit))
      (format t "# ... ~D more (LIMIT=0 for all)~%" (- (length rows) limit)))))

(defun print-name (survey plain name limit)
  "Print what SURVEY knows about NAME."
  (format t "~A	~(~A~)~%" name (name-class survey name plain))
  (dolist (definition (append (survey-definitions plain) (survey-definitions survey)))
    (when (string= name (definition-name definition))
      (format t "  defines: ~A~%" (definition-text definition))))
  (dolist (definition (survey-definitions survey))
    (when (equal name (definition-alias definition))
      (format t "  alias: ~A ~A~%" (definition-name definition)
              (definition-text definition))))
  (dolist (note (survey-catcode-notes survey))
    (when (equal (catcode-note-how note) (list :call name))
      (format t "  catcode: ~A code ~A value ~A~%"
              (place (catcode-note-file note) (catcode-note-line note))
              (catcode-note-code note) (catcode-note-value note))))
  (loop for (file text body uncertain) in (name-counts survey name)
        for i from 0
        while (or (zerop limit) (< i limit))
        do (format t "  uses: ~A text ~D body ~D uncertain ~D~%"
                   file text body uncertain)))

(with-exit-status
  (let* ((job (env "JOB"))
         (file (env "FILE"))
         (name (env "NAME"))
         (limit (parse-integer (env "LIMIT" "40")))
         (plain (survey-job "plain"))
         (survey (if job
                     (survey-job job)
                     (merge-surveys (mapcar #'survey-job (chapter-jobs))))))
    (if name
        (print-name survey plain name limit)
        (print-summary survey plain file limit))
    t))
