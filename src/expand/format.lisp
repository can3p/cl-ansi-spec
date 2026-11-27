;;;; src/expand/format.lisp
;;;;
;;;; Formats and jobs (docs/tex-fidelity.md, "Jobs").  A format is the
;;;; state INITEX leaves at a \dump (TeX's store_fmt_file, §§1299-1329):
;;;; LOAD-PLAIN-FORMAT makes plain TeX's, as `initex plain \dump' does.
;;;; MAKE-JOB starts a job from a format (load_fmt_file, §1337) on a copy
;;;; of its state, so that jobs never share anything mutable with the
;;;; format or with each other; START-JOB gives it its file and
;;;; \everyjob.

(in-package #:cl-ansi-spec/expand)

(defstruct (tex-format (:constructor %make-tex-format
                           (state frozen font-identifiers patterns
                            hyphenation-exceptions interaction))
                       (:copier nil))
  "What a \\dump keeps: the expander STATE, the FROZEN control sequences
and FONT-IDENTIFIERS the job made (tables as in EXPANDER), its PATTERNS
and HYPHENATION-EXCEPTIONS (the trie being ready) and its INTERACTION
mode.  Never run again: each job copies it."
  (state nil :type expander-state :read-only t)
  (frozen nil :type hash-table :read-only t)
  (font-identifiers nil :type hash-table :read-only t)
  (patterns '() :type list :read-only t)
  (hyphenation-exceptions '() :type list :read-only t)
  (interaction :error-stop :read-only t))

(define-condition format-error (error)
  ((detail :initarg :detail :reader format-error-detail
           :documentation "What went wrong: a TeX condition or a string."))
  (:report (lambda (condition stream)
             (format stream "The format did not load cleanly: ~A"
                     (format-error-detail condition))))
  (:documentation "Signalled by LOAD-PLAIN-FORMAT when its job errs,
notes anything (a TEX-REPORT) or ends other than by \\dump."))

(defun load-plain-format (&key (resolver nil resolver-p))
  "Plain TeX's format: an INITEX job `plain' reading plain.tex (which
inputs hyphen.tex) through RESOLVER (default: the source search path),
followed by \\dump, as `initex plain \\dump' reads the rest of its first
line after the file (§1337).  Signals FORMAT-ERROR unless the job runs
with no TeX error or note and ends at that \\dump."
  (let* ((expander (apply #'make-expander :job-name "plain"
                          (and resolver-p (list :resolver resolver))))
         (input (expander-input expander)))
    (push-tokens input (list (named-token expander "dump")) :inserted)
    (push-file input "plain")
    (handler-bind (((or tex-error tex-report)
                     (lambda (condition)
                       (error 'format-error :detail condition))))
      (unless (eq (main-control expander) :dump)
        (error 'format-error :detail "the job ended by \\end")))
    (%make-tex-format (expander-state expander)
                      (expander-frozen expander)
                      (expander-font-identifiers expander)
                      (expander-patterns expander)
                      (expander-hyphenation-exceptions expander)
                      (expander-interaction expander))))

;;; Copying a format's state

(defun copy-tex-font (font)
  "A new font with FONT's file, size, identifier and assignments."
  (let ((copy (make-tex-font (tex-font-file font)
                             :size (tex-font-size font)
                             :identifier (tex-font-identifier font)
                             :hyphen-char (tex-font-hyphen-char font)
                             :skew-char (tex-font-skew-char font)
                             :parameter-count (tex-font-parameter-count font))))
    (loop for n from 1 to (length (tex-font-dimens font))
          do (set-font-dimen copy n (font-dimen font n)))
    (setf (tex-font-style copy) (tex-font-style font))
    copy))

(defun font-copier ()
  "A function of a value: a font is copied the first time it is given
(the same copy after), anything else is returned as it is."
  (let ((copies (make-hash-table :test 'eq)))
    (lambda (value)
      (if (tex-font-p value)
          (or (gethash value copies)
              (setf (gethash value copies) (copy-tex-font value)))
          value))))

(defun copy-expander-state (state copy-font)
  "A copy of STATE (at level one) sharing nothing mutable with it: every
table copied, every font passed through COPY-FONT (see FONT-COPIER), every
box register copied.  Control sequences, tokens, glue and meanings other
than fonts are immutable and shared."
  (flet ((copy-table (table) (copy-equivalents table copy-font)))
    (%copy-expander-state
     (copy-tex-state (es-tex state))
     (funcall copy-font (es-null-font state))
     (copy-table (es-meanings state))
     (loop for (kind table) on (es-registers state) by #'cddr
           collect kind
           collect (copy-equivalents table (if (eq kind :box) #'copy-box #'identity)))
     (copy-table (es-parameters state))
     (loop for (kind table) on (es-codes state) by #'cddr
           collect kind collect (copy-table table))
     (copy-table (es-fonts state))
     (copy-table (es-shapes state))
     (mapcar copy-font (es-loaded-fonts state)))))

(defun copy-hash-table (table &optional (copy-key #'identity))
  "A new table of TABLE's test with its entries, each key passed through
COPY-KEY."
  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (key value)
               (setf (gethash (funcall copy-key key) copy) value))
             table)
    copy))

;;; Jobs

(defun make-job (format &key (resolver nil resolver-p) (job-name ""))
  "A new TeX job called JOB-NAME from FORMAT, reading through RESOLVER
(default: the source search path): FORMAT's state copied, everything a
\\dump does not keep fresh (an empty input stack, nest and page, no
marks, conditionals or open streams, align_state 1000000).  Give it its
file with START-JOB."
  (let* ((copy-font (font-copier))
         (state (copy-expander-state (tex-format-state format) copy-font))
         (input (if resolver-p
                    (make-input-stack (es-tex state) :resolver resolver)
                    (make-input-stack (es-tex state))))
         (expander (%make-format-expander
                    state input job-name
                    (copy-hash-table (tex-format-frozen format))
                    ;; Keys are (font . identifier).
                    (copy-hash-table (tex-format-font-identifiers format)
                                     (lambda (key)
                                       (cons (funcall copy-font (car key))
                                             (cdr key)))))))
    (setf (expander-patterns expander) (tex-format-patterns format)
          (expander-hyphenation-exceptions expander)
          (tex-format-hyphenation-exceptions format)
          (expander-trie-not-ready expander) nil
          (expander-interaction expander) (tex-format-interaction format))
    (install-input-hooks expander)))

(defun start-job (expander name)
  "Begin EXPANDER's job on the file NAME: \\everyjob is read first, then
the file (§1337)."
  (push-file (expander-input expander) name)
  (begin-token-list expander (parameter (expander-state expander) :everyjob)
                    :every-job)
  expander)
