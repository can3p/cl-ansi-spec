;;;; src/tex/state.lisp
;;;;
;;;; TeX's table of equivalents (category codes, case codes, integer
;;;; parameters) and the save stack that implements grouping.
;;;;
;;;; As in TeX, every entry remembers the group level at which it was last
;;;; assigned.  A local assignment saves the old value on the save stack the
;;;; first time an entry changes inside a group; a global assignment marks
;;;; the entry as belonging to the outermost level, so that leaving a group
;;;; keeps ("retains") it instead of restoring the saved value.  Nothing is
;;;; ever copied wholesale.

(in-package #:cl-ansi-spec/tex)

;;; Category codes (TeXbook, chapter 7).

(defconstant +escape+ 0)
(defconstant +begin-group+ 1)
(defconstant +end-group+ 2)
(defconstant +math-shift+ 3)
(defconstant +alignment-tab+ 4)
(defconstant +end-of-line+ 5)
(defconstant +parameter+ 6)
(defconstant +superscript+ 7)
(defconstant +subscript+ 8)
(defconstant +ignored+ 9)
(defconstant +space+ 10)
(defconstant +letter+ 11)
(defconstant +other+ 12)
(defconstant +active+ 13)
(defconstant +comment+ 14)
(defconstant +invalid+ 15)

(deftype catcode-value () '(integer 0 15))

(defun catcode-name (catcode)
  "Return a keyword naming the category code CATCODE."
  (svref #(:escape :begin-group :end-group :math-shift :alignment-tab
           :end-of-line :parameter :superscript :subscript :ignored
           :space :letter :other :active :comment :invalid)
         catcode))

;;; Tables of equivalents.

(defconstant +level-one+ 1
  "The level of the outermost group, and of every global assignment.")

(defconstant +character-table-size+ 256
  "Number of character codes held in the vector part of a character
table.  Larger codes (possible in patched sources) live in a hash table.")

(defstruct (equivalents (:constructor %make-equivalents))
  "A table of equivalents: a value and a level for every key.  Integer
keys below the size of VALUES are stored in vectors; every other key in
OVERFLOW, as (value . level) conses."
  (name nil :type symbol :read-only t)
  (default nil :read-only t)
  (values #() :type simple-vector :read-only t)
  (levels (make-array 0 :element-type 'fixnum)
   :type (simple-array fixnum (*)) :read-only t)
  (overflow (make-hash-table) :type hash-table :read-only t))

(defun make-equivalents (name &key default (size 0))
  "Return a table NAME whose SIZE first integer keys are stored in vectors
and whose entries all hold DEFAULT at level one."
  (%make-equivalents
   :name name
   :default default
   :values (make-array size :initial-element default)
   :levels (make-array size :element-type 'fixnum :initial-element +level-one+)))

(declaim (inline vector-key-p))
(defun vector-key-p (table key)
  "True if KEY of TABLE is stored in its vectors rather than its overflow."
  (and (typep key 'fixnum)
       (< -1 key (length (equivalents-values table)))))

(defun equivalent (table key)
  "Return the current value of KEY in TABLE."
  (if (vector-key-p table key)
      (svref (equivalents-values table) key)
      (let ((entry (gethash key (equivalents-overflow table))))
        (if entry (car entry) (equivalents-default table)))))

(defun equivalent-level (table key)
  "Return the group level at which KEY was last assigned in TABLE."
  (if (vector-key-p table key)
      (aref (equivalents-levels table) key)
      (let ((entry (gethash key (equivalents-overflow table))))
        (if entry (cdr entry) +level-one+))))

(defun store-equivalent (table key value level)
  "Set KEY in TABLE to VALUE, assigned at LEVEL."
  (if (vector-key-p table key)
      (setf (svref (equivalents-values table) key) value
            (aref (equivalents-levels table) key) level)
      (setf (gethash key (equivalents-overflow table)) (cons value level))))

;;; The state: all tables plus the save stack.

(defstruct (tex-state (:constructor %make-tex-state) (:conc-name state-))
  "The equivalents TeX consults while reading, with their grouping."
  (catcodes (make-equivalents 'catcode :default +other+
                                       :size +character-table-size+)
   :read-only t)
  (lccodes (make-equivalents 'lccode :default 0 :size +character-table-size+)
   :read-only t)
  (uccodes (make-equivalents 'uccode :default 0 :size +character-table-size+)
   :read-only t)
  (integers (make-equivalents 'integer-parameter :default 0) :read-only t)
  ;; Interned control sequences (by name) and active characters (by code).
  (names (make-hash-table :test 'equal) :type hash-table :read-only t)
  ;; Group level as TeX counts it: +LEVEL-ONE+ outside every group.
  (level +level-one+ :type fixnum)
  ;; Entries are (table key value level) lists, or a GROUP-BOUNDARY.
  (save-stack '() :type list))

(defstruct (group-boundary (:constructor make-group-boundary (kind)))
  "Marks the start of a group on the save stack."
  (kind nil :read-only t))

(define-condition group-underflow (error)
  ()
  (:report "End of group without a matching beginning of group.")
  (:documentation "Signalled by END-GROUP outside of every group."))

(defun group-level (state)
  "Return how many groups are open in STATE (0 outside every group)."
  (- (state-level state) +level-one+))

(defun save-stack-depth (state)
  "Return the number of entries (saved values and group boundaries) on
the save stack of STATE."
  (length (state-save-stack state)))

(defun begin-group (state &optional (kind :simple))
  "Open a group of KIND in STATE.  KIND is any object; END-GROUP returns
it so that the caller can check that groups of different kinds (TeX's
braces versus \\begingroup) are properly matched."
  (push (make-group-boundary kind) (state-save-stack state))
  (incf (state-level state))
  kind)

(defun end-group (state)
  "Close the innermost group of STATE, undoing its local assignments, and
return its kind.  Entries assigned globally inside the group keep their
value.  Signal GROUP-UNDERFLOW if no group is open."
  (when (= (state-level state) +level-one+)
    (error 'group-underflow))
  (loop for entry = (pop (state-save-stack state))
        until (group-boundary-p entry)
        do (destructuring-bind (table key value level) entry
             (unless (= (equivalent-level table key) +level-one+)
               (store-equivalent table key value level)))
        finally (decf (state-level state))
                (return (group-boundary-kind entry))))

(defun assign (state table key value global)
  "Assign VALUE to KEY in TABLE of STATE, globally if GLOBAL is true,
otherwise locally to the current group.  Returns VALUE."
  (let ((level (state-level state)))
    (cond (global
           (store-equivalent table key value +level-one+))
          ((= (equivalent-level table key) level)
           (store-equivalent table key value level))
          (t
           (when (> level +level-one+)
             (push (list table key (equivalent table key)
                         (equivalent-level table key))
                   (state-save-stack state)))
           (store-equivalent table key value level))))
  value)

;;; Typed accessors.

(deftype character-code () `(integer 0 (,char-code-limit)))

(defun check-character-code (code)
  "Signal a TYPE-ERROR unless CODE is a character code; return CODE."
  (check-type code character-code)
  code)

(defun catcode (state code)
  "Return the category code of the character with code CODE."
  (equivalent (state-catcodes state) code))

(defun set-catcode (state code catcode &key global)
  "Assign CATCODE as the category code of character CODE."
  (check-character-code code)
  (check-type catcode catcode-value)
  (assign state (state-catcodes state) code catcode global))

(defun lccode (state code)
  "Return the lower-case code of the character with code CODE."
  (equivalent (state-lccodes state) code))

(defun set-lccode (state code value &key global)
  "Assign VALUE as the lower-case code of character CODE."
  (check-character-code code)
  (check-character-code value)
  (assign state (state-lccodes state) code value global))

(defun uccode (state code)
  "Return the upper-case code of the character with code CODE."
  (equivalent (state-uccodes state) code))

(defun set-uccode (state code value &key global)
  "Assign VALUE as the upper-case code of character CODE."
  (check-character-code code)
  (check-character-code value)
  (assign state (state-uccodes state) code value global))

(defun endlinechar (state)
  "Return \\endlinechar: the code appended to every input line, or a
value outside 0..255 for none."
  (equivalent (state-integers state) :endlinechar))

(defun set-endlinechar (state value &key global)
  "Assign VALUE to \\endlinechar.  Any integer is allowed, as in TeX;
values outside 0..255 mean that nothing is appended to input lines."
  (check-type value integer)
  (assign state (state-integers state) :endlinechar value global))

;;; Initial states.

(defun make-initex-state ()
  "Return a state with INITEX's initial equivalents: every character
other, except escape \\, comment %, letters A-Z and a-z, invalid ^^?,
ignored ^^@, end of line ^^M and space; case codes for the letters; and
\\endlinechar = ^^M."
  (let ((state (%make-tex-state)))
    (flet ((cat (char catcode)
             (set-catcode state (char-code char) catcode)))
      (cat #\\ +escape+)
      (cat #\% +comment+)
      (set-catcode state 127 +invalid+)
      (set-catcode state 0 +ignored+)
      (set-catcode state 13 +end-of-line+)
      (cat #\Space +space+)
      (loop for upper from (char-code #\A) to (char-code #\Z)
            for lower = (+ upper 32)
            do (set-catcode state upper +letter+)
               (set-catcode state lower +letter+)
               (set-lccode state upper lower)
               (set-lccode state lower lower)
               (set-uccode state upper upper)
               (set-uccode state lower upper)))
    (set-endlinechar state 13)
    state))

(defparameter *plain-catcodes*
  `((#\{ . ,+begin-group+) (#\} . ,+end-group+) (#\$ . ,+math-shift+)
    (#\& . ,+alignment-tab+) (#\# . ,+parameter+)
    (#\^ . ,+superscript+) (11 . ,+superscript+)
    (#\_ . ,+subscript+) (1 . ,+subscript+)
    (9 . ,+space+) (#\~ . ,+active+) (12 . ,+active+))
  "The category codes plain.tex changes from INITEX's, as (character or
code . catcode).  ^^K, ^^A, ^^I and ^^L are given by code.")

(defun apply-plain-catcodes (state)
  "Make the category code assignments of plain.tex in STATE; return STATE."
  (loop for (char . catcode) in *plain-catcodes*
        do (set-catcode state (if (characterp char) (char-code char) char)
                        catcode))
  state)

(defun make-plain-state ()
  "Return an INITEX state with plain TeX's category codes (but none of
its macros, which the expander loads from plain.tex)."
  (apply-plain-catcodes (make-initex-state)))
