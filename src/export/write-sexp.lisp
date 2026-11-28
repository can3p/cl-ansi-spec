;;;; src/export/write-sexp.lisp
;;;;
;;;; The S-expression writer over the node registry: a node is written as
;;;; MODEL:NODE-SEXP makes it, (kind :field value ... :span (file start end
;;;; line column)); a file is one form, (:schema-version "<digest>" :key
;;;; content ...), read back with READ under standard syntax and
;;;; *READ-EVAL* false (docs/exports.md, "Files").

(in-package #:cl-ansi-spec/export)

(defun content-sexp (content registry)
  "CONTENT, a node or a list of nodes, as an S-expression."
  (if (listp content)
      (mapcar (lambda (node) (model:node-sexp node :registry registry)) content)
      (model:node-sexp content :registry registry)))

(defun file-sexp (schema-version content &optional (registry model:*registry*))
  "The form of an S-expression file: SCHEMA-VERSION, then the plist CONTENT
of keys (keywords) and their nodes or lists of nodes."
  (list* :schema-version schema-version
         (loop for (key node) on content by #'cddr
               append (list key (content-sexp node registry)))))

(defun sexp-text (form)
  "FORM printed readably as the text of a file, ending with a newline."
  (with-standard-io-syntax
    (let ((*print-case* :downcase)
          (*print-pretty* t)
          (*print-right-margin* 100)
          (*package* (find-package '#:keyword)))
      (format nil "~S~%" form))))

(defun read-sexp-text (text)
  "The form in TEXT, the text of an S-expression file."
  (with-standard-io-syntax
    (let ((*read-eval* nil)
          (*package* (find-package '#:keyword)))
      (multiple-value-bind (form end) (read-from-string text)
        (when (find-if-not (lambda (c) (member c '(#\Space #\Newline #\Tab #\Return)))
                           text :start end)
          (error "Text follows the form of an S-expression file."))
        form))))
