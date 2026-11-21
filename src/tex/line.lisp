;;;; src/tex/line.lisp
;;;;
;;;; Line sources and line buffers.  TeX reads its input a line at a time:
;;;; trailing spaces are removed and the current \endlinechar, if it is a
;;;; valid character code, is appended.  A LINE keeps, for every element
;;;; of its buffer, the file offset it was read from, so that every token
;;;; gets an exact source span even after TeX rewrites ^^ notation inside
;;;; control sequence names.

(in-package #:cl-ansi-spec/tex)

(deftype buffer () '(simple-array fixnum (*)))

(defstruct (line (:constructor %make-line))
  "One input line.  CODES holds LIMIT character codes; OFFSETS holds
LIMIT + 1 file offsets: the offset of every code, then the offset where
the buffer's content ends.  END is the offset after the line's newline.
START is the offset of the line's first character, NUMBER counts from 1."
  (codes (make-array 0 :element-type 'fixnum) :type buffer)
  (offsets (make-array 1 :element-type 'fixnum) :type buffer)
  (limit 0 :type fixnum)
  (start 0 :type fixnum :read-only t)
  (end 0 :type fixnum :read-only t)
  (number 1 :type fixnum :read-only t))

(defstruct (line-source (:constructor %make-line-source (name text)))
  "The lines of TEXT, a source file called NAME (relative to the source
tree), read one at a time."
  (name "" :type string :read-only t)
  (text "" :type simple-string :read-only t)
  (position 0 :type fixnum)
  (line-number 0 :type fixnum))

(defun make-line-source (name text)
  "Return a line source reading the string TEXT under the file NAME."
  (%make-line-source name (coerce text 'simple-string)))

(defun open-line-source (name pathname)
  "Return a line source reading the file PATHNAME under the name NAME."
  (make-line-source name (read-spec-file pathname)))

(defun valid-endlinechar-p (value)
  "True if \\endlinechar VALUE designates a character to append."
  (<= 0 value 255))

(defun read-source-line (source state)
  "Return the next line of SOURCE, or NIL at the end of the file.  Lines
end at a newline or at the end of the text.  Trailing spaces are removed;
\\endlinechar of STATE is appended if valid."
  (let* ((text (line-source-text source))
         (start (line-source-position source))
         (length (length text)))
    (when (>= start length)
      (return-from read-source-line nil))
    (let* ((newline (position #\Newline text :start start))
           (content-end (or newline length))
           (stripped (or (position #\Space text :start start :end content-end
                                                :test-not #'char= :from-end t)
                         (1- start)))
           (content-length (- stripped start -1))
           (endlinechar (endlinechar state))
           (append-p (valid-endlinechar-p endlinechar))
           (limit (if append-p (1+ content-length) content-length))
           (codes (make-array limit :element-type 'fixnum))
           (offsets (make-array (1+ limit) :element-type 'fixnum))
           (end (if newline (1+ newline) length)))
      (loop for i below content-length
            do (setf (aref codes i) (char-code (schar text (+ start i)))
                     (aref offsets i) (+ start i)))
      (if append-p
          (setf (aref codes content-length) endlinechar
                (aref offsets content-length) (+ start content-length)
                (aref offsets limit) end)
          (setf (aref offsets limit) (+ start content-length)))
      (setf (line-source-position source) end)
      (%make-line :codes codes :offsets offsets :limit limit
                  :start start :end end
                  :number (incf (line-source-line-number source))))))

(defun line-span (source line from to)
  "Return the span of buffer elements FROM (inclusive) to TO (exclusive)
of LINE, read from SOURCE."
  (let ((start (aref (line-offsets line) from)))
    (make-span (line-source-name source) start (aref (line-offsets line) to)
               (line-number line) (- start (line-start line)))))

(defun line-end-span (source line)
  "Return the span between the end of LINE's buffer content and the end of
the line: removed trailing spaces and the newline, when no \\endlinechar
stands for them.  It is empty when an \\endlinechar was appended."
  (let ((start (aref (line-offsets line) (line-limit line))))
    (make-span (line-source-name source) start (line-end line)
               (line-number line) (- start (line-start line)))))

(defun reduce-in-buffer (line index width code)
  "Replace the WIDTH buffer elements of LINE starting at INDEX by the
single character CODE, keeping the offset of the first one.  This is how
TeX rewrites ^^ notation inside control sequence names."
  (let ((codes (line-codes line))
        (offsets (line-offsets line))
        (limit (line-limit line)))
    (setf (aref codes index) code)
    (replace codes codes :start1 (1+ index) :start2 (+ index width) :end2 limit)
    (replace offsets offsets :start1 (1+ index) :start2 (+ index width)
                             :end2 (1+ limit))
    (setf (line-limit line) (- limit (1- width)))))
