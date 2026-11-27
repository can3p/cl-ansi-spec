;;;; src/patch/set.lisp
;;;;
;;;; The patch set: patches/*.patch in name order, checked (name, header,
;;;; independence) and applied to the pristine spec tree in memory.  The
;;;; patched texts are served to every job through the source overlay of
;;;; cl-ansi-spec (*SOURCE-OVERLAY*), which this file installs; spans point
;;;; into the patched text under the file's own name.

(in-package #:cl-ansi-spec/patch)

(define-condition invalid-patch (patch-error)
  ((reason :initarg :reason :reader invalid-patch-reason))
  (:report (lambda (condition stream)
             (report-patch-location condition stream)
             (write-string (invalid-patch-reason condition) stream)))
  (:documentation "A patch file breaks a rule of patches/README.md that is
not about the diff itself: its name or its header."))

(defstruct (patch-set (:constructor make-patch-set (patches files applied)))
  "PATCHES, the PATCH records in name order; FILES, an alist from a spec
file's name to its patched text; APPLIED, a list of (NAME SHA-256) per
patch, the digest being that of the patch file's bytes."
  patches files applied)

(defun patch-directory ()
  "The directory holding the patch files."
  (asdf:system-relative-pathname "cl-ansi-spec" "patches/"))

(defun valid-patch-name-p (name)
  "True when NAME is NNNN-short-description.patch: four digits, then
lower-case words of letters and digits joined by hyphens."
  (let ((end (- (length name) (length ".patch"))))
    (and (> end 5)
         (string= ".patch" name :start2 end)
         (every #'digit-char-p (subseq name 0 4))
         (char= (char name 4) #\-)
         (let ((words (uiop:split-string (subseq name 5 end) :separator "-")))
           (every (lambda (word)
                    (and (plusp (length word))
                         (every (lambda (c) (or (digit-char-p c)
                                                (char<= #\a c #\z)))
                                word)))
                  words)))))

(defun invalid-patch (patch reason &rest arguments)
  (error 'invalid-patch :patch (patch-name patch) :hunk nil :line nil
                        :reason (apply #'format nil reason arguments)))

(defun check-patch-rules (patches)
  "Check the names (shape, distinct numbers) and the headers of PATCHES."
  (let ((numbers (make-hash-table :test #'equal)))
    (dolist (patch patches)
      (let ((name (patch-name patch)))
        (unless (valid-patch-name-p name)
          (invalid-patch patch "the name is not NNNN-short-description.patch."))
        (let ((other (gethash (subseq name 0 4) numbers)))
          (when other
            (invalid-patch patch "the number is also patch ~A's." other)))
        (setf (gethash (subseq name 0 4) numbers) name)
        (when (zerop (length (string-trim '(#\Space #\Tab #\Newline #\Return)
                                          (patch-header patch))))
          (invalid-patch patch "the header, the text before the first \"--- \" line, is empty: say why."))))))

(defun pristine-source (path)
  "The text of the pristine spec file PATH, or NIL; never patched."
  (let ((pathname (merge-pathnames (uiop:parse-unix-namestring path)
                                   (cl-ansi-spec:spec-directory))))
    (and (uiop:file-exists-p pathname)
         (cl-ansi-spec:read-spec-file pathname))))

(defun load-patch-set (&optional (directory (patch-directory))
                         (source #'pristine-source))
  "Read the patch files in DIRECTORY in name order, check their names and
headers, check that each applies alone to the pristine files SOURCE serves
and that no two patches' hunks overlap or touch (so any order gives the
same tree), and return the PATCH-SET.  Signal a PATCH-ERROR otherwise."
  (let* ((pathnames (sort (copy-list (and (uiop:directory-exists-p directory)
                                          (uiop:directory-files
                                           directory
                                           (make-pathname :name :wild :type "patch"))))
                          #'string< :key #'file-namestring))
         (patches (mapcar #'read-patch-file pathnames)))
    (check-patch-rules patches)
    (dolist (patch patches) (apply-patch patch source))
    (make-patch-set patches
                    (apply-patches patches source)
                    (loop for pathname in pathnames
                          collect (list (file-namestring pathname)
                                        (cl-ansi-spec/sha256:sha256-file-hex pathname))))))

(defvar *patch-set* nil
  "The patch set jobs read through, or NIL for the default one, loaded
from patches/ on first use (CURRENT-PATCH-SET).")

(defvar *default-patch-set* nil
  "The patch set loaded from patches/, once per image: a long-lived image
calls RESET-PATCH-SET after patches/ changes.  The first job to read a
spec file loads it, so a broken patch set fails that job with a
PATCH-ERROR; tools and tests that want the failure up front call
CURRENT-PATCH-SET first.")

(defun current-patch-set ()
  "The patch set in force: *PATCH-SET*, else the one loaded from patches/."
  (or *patch-set*
      *default-patch-set*
      (setf *default-patch-set* (load-patch-set))))

(defun reset-patch-set ()
  "Forget the loaded default patch set, so patches/ is read again."
  (setf *default-patch-set* nil))

(defmacro with-patch-set ((set) &body body)
  "Run BODY with SET, a PATCH-SET, in force for every job."
  `(let ((*patch-set* ,set)) ,@body))

(defun patched-text (file-name &optional (set (current-patch-set)))
  "The patched text of the spec file FILE-NAME in SET, or NIL if no patch
touches it."
  (cdr (assoc file-name (patch-set-files set) :test #'string=)))

(defun applied-patches (&optional (set (current-patch-set)))
  "The patches of SET, in order, as a list of (NAME SHA-256), for the
export manifest."
  (patch-set-applied set))

(setf cl-ansi-spec:*source-overlay* (lambda (file-name) (patched-text file-name)))
