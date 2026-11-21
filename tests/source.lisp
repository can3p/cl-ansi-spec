;;;; tests/source.lisp

(in-package #:cl-ansi-spec/tests)

(define-test source
  :parent cl-ansi-spec
  :description "Locating and reading the spec sources.")

(define-test spec-directory-exists
  :parent source
  (true (uiop:directory-exists-p (spec-directory))))

(defun manifest-file-names ()
  "Return the sorted file names recorded in spec/SHA256SUMS."
  (sort (mapcar (lambda (line)
                  ;; Lines look like "<sha256>  ./<file-name>".
                  (subseq line (+ (search "  ./" line) (length "  ./"))))
                (uiop:read-file-lines
                 (asdf:system-relative-pathname "cl-ansi-spec" "spec/SHA256SUMS")))
        #'string<))

(define-test source-inventory
  :parent source
  :description "spec/tex/ holds exactly the files listed in spec/SHA256SUMS."
  (is equal (manifest-file-names)
      (mapcar #'file-namestring (spec-files :type :wild))))

(define-test every-chapter-is-present
  :parent source
  (dolist (chapter (list* "chap-0-edit-history" "chap-a"
                          (loop for n from 0 to 26
                                collect (format nil "chap-~D" n))))
    (true (spec-file chapter) "Missing chapter ~A" chapter)))

(define-test spec-files-are-sorted
  :parent source
  (let ((names (mapcar #'file-namestring (spec-files))))
    (is equal (sort (copy-list names) #'string<) names)))

(define-test spec-file-signals-when-missing
  :parent source
  (fail (spec-file "no-such-file") 'spec-file-missing))

(define-test spec-file-rejects-wild-names
  :parent source
  (fail (spec-file "chap-*") 'error))

(define-test sources-are-ascii
  :parent source
  :description "The pristine sources are pure ASCII with LF line endings."
  (dolist (pathname (spec-files :type :wild))
    (let ((text (read-spec-file pathname))
          (name (file-namestring pathname)))
      (true (plusp (length text)) "~A is empty" name)
      (true (every (lambda (char) (< (char-code char) 128)) text)
            "~A contains non-ASCII characters" name)
      (false (find #\Return text) "~A contains CR characters" name))))

(define-test read-spec-file-reads-verbatim
  :parent source
  (true (search "\\begincom{list}\\ftype{System Class}"
                (read-spec-file (spec-file "dict-conses")))))
