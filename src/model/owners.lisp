;;;; src/model/owners.lisp
;;;;
;;;; The ownership table of the builder (src/model/owners.sexp): which
;;;; builder step, in which handler file, builds each
;;;; vocabulary key and each event kind.  Read by the tests that check
;;;; every key and kind has exactly one owner (tests/model/owners.lisp).

(in-package #:cl-ansi-spec/model)

(defstruct (owner (:constructor make-owner
                      (step &key file vocabulary events why)))
  "STEP (a string, \"3.8\") writes, in FILE of src/model/, the handlers
of the vocabulary keys VOCABULARY and of the event kinds EVENTS, for the
reason WHY."
  (step "" :type string :read-only t)
  (file "" :type string :read-only t)
  (vocabulary '() :type list :read-only t)
  (events '() :type list :read-only t)
  (why "" :type string :read-only t))

(defun load-owners (pathname)
  "The OWNERs of the data file PATHNAME: (:OWNER step options...) forms,
MAKE-OWNER's arguments, read without evaluation; each names a file and
gives a non-empty :WHY."
  (with-open-file (in pathname :external-format :utf-8)
    (with-standard-io-syntax
      (let ((*read-eval* nil)
            (*package* (find-package '#:cl-ansi-spec/model)))
        (loop for form = (read in nil in)
              until (eq form in)
              collect (destructuring-bind (tag step &rest options
                                           &key file why &allow-other-keys)
                          form
                        (unless (and (eq tag :owner) (stringp step)
                                     (stringp file) (plusp (length file))
                                     (stringp why) (plusp (length why)))
                          (error "Not an ownership form: ~S" form))
                        (apply #'make-owner step options)))))))

(defun owners ()
  "The builder's ownership table, from src/model/owners.sexp."
  (load-owners (asdf:system-relative-pathname
                "cl-ansi-spec" "src/model/owners.sexp")))
