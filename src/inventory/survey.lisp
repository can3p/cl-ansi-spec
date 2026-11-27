;;;; src/inventory/survey.lisp
;;;;
;;;; Surveying a TeX job without expansion: its definitions, the uses of
;;;; every control sequence, its \input files and its catcode changes.
;;;; Rules (docs/vocabulary.md, "Choosing entries"):
;;;;
;;;; - Literal catcode assignments at top level (\catcode`\X=N, with N a
;;;;   number, \active or a \chardef'd name; \obeylines; \obeyspaces) are
;;;;   applied to the reader's state, scoped by groups, so reading follows
;;;;   the source exactly.
;;;; - Catcode changes made inside macros are not executed.  A call of a
;;;;   macro whose body assigns catcodes makes those characters unknown for
;;;;   the rest of the job; a line holding an unknown character whose
;;;;   category may be structural (escape, braces, letter, comment) is
;;;;   uncertain, and so is everything on it.
;;;; - A definition inside another macro's body is recorded as nested under
;;;;   it: it exists only once the outer macro expands.

(in-package #:cl-ansi-spec/inventory)

;;; Records

(defstruct definition
  "A definition made by the sources.  KIND is the defining command as a
keyword (:def, :gdef, :edef, :xdef, :let, :chardef, ..., :font, :newcount,
..., :newif).  DEPTH is the group level of a top-level definition, NIL for
a nested one, whose PARENT is the name of the macro whose body holds it.
ALIAS is the token text a :let names, or the one control sequence a
parameterless macro expands to.  VALUE is a \\chardef's literal number.
ARITY is the number of parameters of a macro whose parameter text is only
undelimited parameters (#1#2...), NIL for any other.  INPUT-PARAMETERS
are the parameters its body inputs as a file (\\input #1)."
  name kind file line depth global-p long-p parent alias value uncertain-p
  arity (input-parameters '())
  (body-catcodes '())                   ; (code . value) assigned in the body
  (body-names '()))                     ; control sequences the body uses

(defstruct occurrence
  "A use of the control sequence NAME.  CONTEXT is :text outside every
definition and :body inside a macro body."
  name file line context uncertain-p)

(defstruct input-record
  "An \\input.  STATUS is :found, :missing (no such file; generated files
such as chap-N.fig), :repeated (already read in this job; not read again)
or :computed (the name is not literal: TARGET is then the text of its
first token, or of MACRO).  MACRO names the input macro whose call made
the \\input (\\includeDictionary{dict-types}), if any."
  file line target status macro)

(defstruct catcode-note
  "A catcode change, or a grouping problem met while tracking them.  HOW is
:applied (literal, done), :unknown-value or :unknown-character (not
literal), (:call NAME) when a macro call makes CODE unknown, or
:group-underflow / :group-mismatch (a group closed that was not open, or
a brace closing a \\begingroup or the reverse).  VALUE is the new category
code, or NIL when not known."
  file line code value how)

(defstruct survey
  "What surveying the job JOB-NAME found, in source order."
  job-name files definitions occurrences inputs catcode-notes
  (uncertain-lines '()))                ; sorted ("file" . line) pairs

;;; Token sources: the input stack, or a token list (a macro body)

(defstruct (walker (:constructor make-walker (stack state)))
  stack state
  (meanings (make-hash-table :test 'equal)) ; name -> latest top-level definition
  (definitions '()) (occurrences '()) (inputs '()) (notes '())
  (files '())
  (followed '())                        ; names of the files read so far
  (repeated nil)                        ; set when the resolver refuses a repeat
  (unknown (make-hash-table))           ; code -> possible values (NIL = any)
  (uncertain (make-hash-table :test 'equal)))

(defun follow-once-resolver (walker resolver)
  "Return a resolver serving each file RESOLVER finds once: a repeated
file resolves to NIL with WALKER-REPEATED set, so that a survey, which
cannot evaluate the conditionals guarding an \\input, terminates."
  (lambda (name)
    (setf (walker-repeated walker) nil)
    (let ((source (funcall resolver name)))
      (cond ((null source) nil)
            ((member (line-source-name source) (walker-followed walker)
                     :test #'string=)
             (setf (walker-repeated walker) t)
             nil)
            (t (push (line-source-name source) (walker-followed walker))
               source)))))

(defstruct (token-source (:constructor %make-token-source (next unread)))
  next unread)

(defun stream-source (walker)
  "Return a token source reading WALKER's input stack."
  (%make-token-source (lambda () (read-token walker))
                      (lambda (token) (back-input (walker-stack walker) token))))

(defun list-source (tokens)
  "Return a token source reading the list TOKENS."
  (%make-token-source (lambda () (pop tokens))
                      (lambda (token) (push token tokens))))

(defun take (source) (funcall (token-source-next source)))
(defun untake (source token) (funcall (token-source-unread source) token))

(defparameter *structural-catcodes*
  (list +escape+ +begin-group+ +end-group+ +letter+ +comment+)
  "Categories that decide which control sequences are read.")

(defun structural-unknown-p (walker code)
  "Return true iff the category of the character CODE is unknown and may
be structural."
  (multiple-value-bind (values present) (gethash code (walker-unknown walker))
    (and present
         (or (member nil values)
             (member (catcode (walker-state walker) code) *structural-catcodes*)
             (intersection values *structural-catcodes*)))))

(defun token-codes (token)
  "Return the character codes TOKEN was read from, as far as they decide
its meaning: its own code, or the characters of a control sequence's name."
  (if (character-token-p token)
      (list (character-token-code token))
      (map 'list #'char-code (control-sequence-name (cs-token-control-sequence token)))))

(defun read-token (walker)
  "Read the next token of WALKER's input, marking its line uncertain if it
holds an unknown structural character.  Invalid characters are skipped."
  (let ((token (handler-bind ((invalid-character #'continue))
                 (next-token (walker-stack walker)))))
    (when token
      (let* ((span (token-span token))
             (file (span-file span)))
        (unless (member file (walker-files walker) :test #'string=)
          (push file (walker-files walker)))
        (when (some (lambda (code) (structural-unknown-p walker code))
                    (token-codes token))
          (setf (gethash (cons file (span-line span)) (walker-uncertain walker)) t))))
    token))

;;; Small readers

(defun name-of (token)
  "Return the text of TOKEN if it is a control sequence or active
character, else NIL."
  (and token (cs-token-p token) (token-text token)))

(defun char-token-p (token char &optional catcode)
  (and token (character-token-p token)
       (= (character-token-code token) (char-code char))
       (or (null catcode) (= (character-token-catcode token) catcode))))

(defun skip-spaces (source)
  "Skip space tokens of SOURCE."
  (loop for token = (take source)
        while (and token (character-token-p token)
                   (= (character-token-catcode token) +space+))
        finally (when token (untake source token))))

(defun skip-optional-equals (source)
  "Skip spaces, an optional =, and spaces again: TeX's <equals>."
  (skip-spaces source)
  (let ((token (take source)))
    (unless (char-token-p token #\= +other+)
      (when token (untake source token))))
  (skip-spaces source))

(defun read-digits (source radix)
  "Read the digits of RADIX that follow in SOURCE and one optional space;
return their value, or NIL if there are none."
  (loop with value = nil
        for token = (take source)
        for digit = (and token (character-token-p token)
                         (member (character-token-catcode token) (list +other+ +letter+))
                         (not (lower-case-p (code-char (character-token-code token))))
                         (digit-char-p (code-char (character-token-code token)) radix))
        while digit
        do (setf value (+ (* (or value 0) radix) digit))
        finally (cond ((and token (character-token-p token)
                            (= (character-token-catcode token) +space+)))
                      (token (untake source token)))
                (return value)))

(defun read-literal-number (walker source)
  "Read a TeX <number> from SOURCE if it is literal: decimal, 'octal,
\"hex, `character, \\active or a name \\chardef'd to a literal value.
Return it, or NIL after consuming the operand when it is not literal."
  (skip-spaces source)
  (let ((token (take source)))
    (cond ((null token) nil)
          ((char-token-p token #\` +other+)
           (let ((operand (take source)))
             (prog1 (cond ((null operand) nil)
                          ((character-token-p operand) (character-token-code operand))
                          (t (let ((name (control-sequence-name
                                          (cs-token-control-sequence operand))))
                               (and (= (length name) 1) (char-code (char name 0))))))
               (let ((space (take source)))
                 (unless (and space (character-token-p space)
                              (= (character-token-catcode space) +space+))
                   (when space (untake source space)))))))
          ((char-token-p token #\' +other+) (read-digits source 8))
          ((char-token-p token #\" +other+) (read-digits source 16))
          ((and (character-token-p token)
                (= (character-token-catcode token) +other+)
                (digit-char-p (code-char (character-token-code token))))
           (untake source token)
           (read-digits source 10))
          ((name-of token)
           (if (string= (name-of token) "\\active")
               +active+
               (let ((meaning (gethash (name-of token) (walker-meanings walker))))
                 (and meaning (definition-value meaning)))))
          (t (untake source token) nil))))

;;; Recording

(defun line-of (token) (span-line (token-span token)))
(defun file-of (token) (span-file (token-span token)))

(defun record-use (walker token context)
  (push (make-occurrence :name (name-of token) :file (file-of token)
                         :line (line-of token) :context context)
        (walker-occurrences walker)))

(defun record-note (walker token code value how)
  (push (make-catcode-note :file (file-of token) :line (line-of token)
                           :code code :value value :how how)
        (walker-notes walker)))

(defun add-definition (walker definition context)
  "Record DEFINITION; a top-level one becomes the current meaning."
  (push definition (walker-definitions walker))
  (when (eq context :text)
    (setf (gethash (definition-name definition) (walker-meanings walker))
          definition))
  definition)

;;; Definitions

(defparameter *macro-definers*
  '(("\\def" . :def) ("\\gdef" . :gdef) ("\\edef" . :edef) ("\\xdef" . :xdef)))

(defparameter *other-definers*
  '(("\\let" . :let) ("\\font" . :font)
    ("\\chardef" . :chardef) ("\\mathchardef" . :mathchardef)
    ("\\countdef" . :countdef) ("\\dimendef" . :dimendef)
    ("\\skipdef" . :skipdef) ("\\muskipdef" . :muskipdef)
    ("\\toksdef" . :toksdef)
    ("\\newcount" . :newcount) ("\\newdimen" . :newdimen)
    ("\\newskip" . :newskip) ("\\newmuskip" . :newmuskip)
    ("\\newtoks" . :newtoks) ("\\newbox" . :newbox) ("\\newread" . :newread)
    ("\\newwrite" . :newwrite) ("\\newfam" . :newfam)
    ("\\newinsert" . :newinsert) ("\\newlanguage" . :newlanguage)
    ("\\newif" . :newif))
  "Defining commands other than the \\def family, with their kinds.")

(defun definer-kind (name)
  (cdr (or (assoc name *macro-definers* :test #'equal)
           (assoc name *other-definers* :test #'equal))))

(defun read-balanced (source)
  "Read tokens up to the end-group token matching an already read
begin-group token; return them, the end-group token excluded."
  (loop with depth = 1
        for token = (take source)
        while token
        do (when (character-token-p token)
             (let ((catcode (character-token-catcode token)))
               (cond ((= catcode +begin-group+) (incf depth))
                     ((= catcode +end-group+) (decf depth)))))
        until (zerop depth)
        collect token))

(defun read-definition (walker source kind prefixes context parent)
  "Read the rest of a definition of KIND from SOURCE and record it.
PREFIXES are the keywords :global and :long seen before it."
  (skip-spaces source)
  (let ((name-token (take source)))
    (unless (name-of name-token)
      (when name-token (untake source name-token))
      (return-from read-definition nil))
    (let ((definition
            (make-definition :name (name-of name-token) :kind kind
                             :file (file-of name-token) :line (line-of name-token)
                             :depth (and (eq context :text)
                                         (group-level (walker-state walker)))
                             :global-p (and (or (member :global prefixes)
                                                (member kind '(:gdef :xdef)))
                                            t)
                             :long-p (and (member :long prefixes) t)
                             :parent parent)))
      (case kind
        ((:def :gdef :edef :xdef)
         (let* ((parameters (loop for token = (take source)
                                  until (or (null token)
                                            (and (character-token-p token)
                                                 (= (character-token-catcode token)
                                                    +begin-group+)))
                                  collect token))
                (body (read-balanced source)))
           (when (and (null parameters) body (null (rest body)) (name-of (first body)))
             (setf (definition-alias definition) (name-of (first body))))
           (setf (definition-arity definition) (undelimited-arity parameters))
           (add-definition walker definition context)
           (analyze-body walker body definition)))
        (:let
         (skip-optional-equals source)
         (let ((target (take source)))
           (when target
             (setf (definition-alias definition) (token-text target))))
         (add-definition walker definition context))
        ((:chardef :mathchardef :countdef :dimendef :skipdef :muskipdef :toksdef)
         (skip-optional-equals source)
         (setf (definition-value definition) (read-literal-number walker source))
         (add-definition walker definition context))
        (:newif
         (add-definition walker definition context)
         (let ((name (definition-name definition)))
           (when (and (> (length name) 3) (string= "\\if" name :end2 3))
             (dolist (suffix '("true" "false"))
               (let ((derived (copy-definition definition)))
                 (setf (definition-name derived)
                       (concatenate 'string "\\" (subseq name 3) suffix))
                 (add-definition walker derived context))))))
        (t (add-definition walker definition context))))))

(defun undelimited-arity (parameters)
  "Return the number of parameters of the parameter text PARAMETERS if it
is #1#2...#n, else NIL."
  (loop for (sign digit) on parameters by #'cddr
        for n from 1
        unless (and (character-token-p sign)
                    (= (character-token-catcode sign) +parameter+)
                    digit (character-token-p digit)
                    (eql (digit-char-p (code-char (character-token-code digit))) n))
          return nil
        finally (return (/ (length parameters) 2))))

(defun read-input-parameter (source)
  "After \\input in a macro body, read a parameter #N if one follows and
return N; otherwise leave SOURCE as it was."
  (skip-spaces source)
  (let ((sign (take source)))
    (if (and sign (character-token-p sign)
             (= (character-token-catcode sign) +parameter+))
        (let ((digit (take source)))
          (or (and digit (character-token-p digit)
                   (digit-char-p (code-char (character-token-code digit))))
              (progn (when digit (untake source digit))
                     (untake source sign)
                     nil)))
        (progn (when sign (untake source sign)) nil))))

(defun analyze-body (walker tokens owner)
  "Record what the macro body TOKENS of the definition OWNER uses, defines
and assigns: uses as :body occurrences, definitions as nested under OWNER,
literal catcode assignments in OWNER's BODY-CATCODES."
  (let ((source (list-source tokens)))
    (loop for token = (take source)
          while token
          do (let* ((name (name-of token))
                    (kind (and name (definer-kind name))))
               (when name
                 (record-use walker token :body)
                 (pushnew name (definition-body-names owner) :test #'string=)
                 (cond (kind
                        (read-definition walker source kind '() :body
                                         (definition-name owner)))
                       ((string= name "\\catcode")
                        (let ((code (read-literal-number walker source)))
                          (skip-optional-equals source)
                          (push (cons code (read-literal-number walker source))
                                (definition-body-catcodes owner))))
                       ((string= name "\\obeylines")
                        (push (cons 13 +active+) (definition-body-catcodes owner)))
                       ((string= name "\\obeyspaces")
                        (push (cons 32 +active+) (definition-body-catcodes owner)))
                       ((string= name "\\input")
                        (let ((n (read-input-parameter source)))
                          (when n
                            (pushnew n (definition-input-parameters owner)))))))))))

;;; Catcodes at top level

(defun apply-catcode (walker token code value global)
  "Assign VALUE to the category of CODE, or note why it cannot be."
  (cond ((and code value)
         (set-catcode (walker-state walker) code value :global global)
         (remhash code (walker-unknown walker))
         (record-note walker token code value :applied))
        (code
         (setf (gethash code (walker-unknown walker)) (list nil))
         (record-note walker token code nil :unknown-value))
        (t (record-note walker token nil nil :unknown-character))))

(defun body-catcode-effects (walker name &optional visited)
  "Return the (code . value) catcode assignments a call of NAME makes,
following the macros its body calls."
  (let ((meaning (gethash name (walker-meanings walker))))
    (when (and meaning (not (member name visited :test #'string=)))
      (append (definition-body-catcodes meaning)
              (loop for called in (definition-body-names meaning)
                    append (body-catcode-effects walker called (cons name visited)))))))

(defun note-macro-call (walker token)
  "Make the characters a call of TOKEN's macro assigns unknown."
  (loop for (code . value) in (body-catcode-effects walker (name-of token))
        do (when code
             (pushnew value (gethash code (walker-unknown walker))))
           (record-note walker token code value (list :call (name-of token)))))

(defun safe-end-group (walker token kind)
  "End the innermost group if TOKEN closes it: a group of KIND (:brace, or
:semi for \\begingroup).  Otherwise note the problem and leave the group
open, as TeX does after reporting an extra } or \\endgroup."
  (let ((open (current-group-kind (walker-state walker))))
    (cond ((null open) (record-note walker token nil nil :group-underflow))
          ((not (eq open kind)) (record-note walker token nil nil :group-mismatch))
          (t (end-group (walker-state walker))))))

;;; \input

(defun file-name-character-p (token)
  "Return true iff TOKEN continues a file name: a character token that is
not a space.  TeX82 takes characters of category 12 or below and expands
the rest; without expansion, an active character stands for itself (the
spec's active - is defined to typeset -)."
  (if (character-token-p token)
      (and (<= (character-token-catcode token) +other+)
           (/= (character-token-catcode token) +space+)
           (/= (character-token-code token) 32))
      (and token (control-sequence-active-p (cs-token-control-sequence token)))))

(defun file-name-character (token)
  "Return the character a FILE-NAME-CHARACTER-P token contributes."
  (if (character-token-p token)
      (code-char (character-token-code token))
      (char (control-sequence-name (cs-token-control-sequence token)) 0)))

(defun read-file-name (source)
  "Read a file name as TeX82 does: FILE-NAME-CHARACTER-P tokens up to a
space, which is consumed.  Return the name, or NIL if the next token does
not start one (it is left in SOURCE)."
  (skip-spaces source)
  (loop with characters = '()
        for token = (take source)
        while (file-name-character-p token)
        do (push (file-name-character token) characters)
        finally (unless (and token (character-token-p token)
                             (or (= (character-token-catcode token) +space+)
                                 (= (character-token-code token) 32)))
                  (when token (untake source token)))
                (return (and characters (coerce (nreverse characters) 'string)))))

(defun open-input (walker record name)
  "Start reading the file NAME, setting the status of the input RECORD."
  (setf (input-record-target record) name
        (input-record-status record)
        (handler-case (progn (push-file (walker-stack walker) name) :found)
          (input-file-missing ()
            (if (walker-repeated walker) :repeated :missing))))
  (push record (walker-inputs walker)))

(defun read-argument (source)
  "Read an undelimited macro argument from SOURCE: a balanced group
without its braces, or one token."
  (skip-spaces source)
  (let ((token (take source)))
    (if (and token (character-token-p token)
             (= (character-token-catcode token) +begin-group+))
        (read-balanced source)
        (and token (list token)))))

(defun follow-input-macro (walker token source meaning)
  "If MEANING, the macro TOKEN calls, inputs one of its arguments as a
file, read its arguments and start reading that file; the arguments are
then read as text, ahead of the file."
  (let ((record (make-input-record :file (file-of token) :line (line-of token)
                                   :macro (definition-name meaning))))
    (cond ((null (definition-arity meaning))
           (setf (input-record-target record) (definition-name meaning)
                 (input-record-status record) :computed)
           (push record (walker-inputs walker)))
          (t
           (let ((arguments (loop repeat (definition-arity meaning)
                                  collect (read-argument source))))
             (dolist (n (definition-input-parameters meaning))
               (let ((argument (nth (1- n) arguments)))
                 (if (and argument (every #'file-name-character-p argument))
                     (open-input walker (copy-input-record record)
                                 (map 'string #'file-name-character argument))
                     (let ((computed (copy-input-record record)))
                       (setf (input-record-target computed)
                             (and argument (token-text (first argument)))
                             (input-record-status computed) :computed)
                       (push computed (walker-inputs walker))))))
             (push-tokens (walker-stack walker)
                          (reduce #'append arguments :from-end t)))))))

(defun handle-input (walker token source)
  "Read the file name after \\input TOKEN and start reading that file."
  (let ((name (read-file-name source))
        (record (make-input-record :file (file-of token) :line (line-of token))))
    (cond (name (open-input walker record name))
          (t (let ((next (take source)))
               (setf (input-record-target record) (and next (token-text next))
                     (input-record-status record) :computed)
               (when next (untake source next))
               (push record (walker-inputs walker)))))))

;;; The walk

(defun top-level-token (walker token source prefixes)
  "Process TOKEN, read outside every definition, after PREFIXES."
  (let ((name (name-of token))
        (state (walker-state walker)))
    (cond ((null name)
           (when (character-token-p token)
             (let ((catcode (character-token-catcode token)))
               (cond ((= catcode +begin-group+) (begin-group state :brace))
                     ((= catcode +end-group+) (safe-end-group walker token :brace))))))
          (t
           (record-use walker token :text)
           (let ((kind (definer-kind name)))
             (cond ((member name '("\\global" "\\long" "\\outer") :test #'string=)
                    (skip-spaces source)
                    (let ((next (take source)))
                      (when next
                        (top-level-token walker next source
                                         (cons (intern (string-upcase (subseq name 1))
                                                       :keyword)
                                               prefixes)))))
                   (kind (read-definition walker source kind prefixes :text nil))
                   ((string= name "\\input") (handle-input walker token source))
                   ((string= name "\\catcode")
                    (let ((code (read-literal-number walker source)))
                      (skip-optional-equals source)
                      (apply-catcode walker token code
                                     (read-literal-number walker source)
                                     (and (member :global prefixes) t))))
                   ((string= name "\\obeylines")
                    (apply-catcode walker token 13 +active+ (and (member :global prefixes) t)))
                   ((string= name "\\obeyspaces")
                    (apply-catcode walker token 32 +active+ (and (member :global prefixes) t)))
                   ((string= name "\\begingroup") (begin-group state :semi))
                   ((string= name "\\endgroup") (safe-end-group walker token :semi))
                   (t
                    (note-macro-call walker token)
                    (let ((meaning (gethash name (walker-meanings walker))))
                      (when (and meaning (definition-input-parameters meaning))
                        (follow-input-macro walker token source meaning))))))))))

(defun survey-job (job &key (resolver (apply #'directory-resolver
                                             (source-search-path))))
  "Survey the TeX job reading the file JOB, with RESOLVER (by default the
source search path), and return a SURVEY.  Each file is read at most once."
  (let* ((state (make-plain-state))
         (walker (make-walker nil state))
         (source (stream-source walker)))
    (setf (walker-stack walker)
          (make-input-stack state :resolver (follow-once-resolver walker resolver)))
    (push-file (walker-stack walker) job)
    (loop for token = (take source)
          while token
          do (top-level-token walker token source '()))
    (finish-survey walker job)))

(defun finish-survey (walker job)
  "Mark what lies on uncertain lines and package WALKER's findings."
  (let ((uncertain (walker-uncertain walker)))
    (flet ((uncertain-p (file line) (gethash (cons file line) uncertain)))
      (dolist (occurrence (walker-occurrences walker))
        (setf (occurrence-uncertain-p occurrence)
              (uncertain-p (occurrence-file occurrence) (occurrence-line occurrence))))
      (dolist (definition (walker-definitions walker))
        (setf (definition-uncertain-p definition)
              (uncertain-p (definition-file definition) (definition-line definition))))
      (make-survey :job-name job
                   :files (reverse (walker-files walker))
                   :definitions (reverse (walker-definitions walker))
                   :occurrences (reverse (walker-occurrences walker))
                   :inputs (reverse (walker-inputs walker))
                   :catcode-notes (reverse (walker-notes walker))
                   :uncertain-lines
                   (sort (loop for key being the hash-keys of uncertain collect key)
                         #'line<)))))

(defun line< (a b)
  "Order (file . line) pairs by file name, then line."
  (or (string< (car a) (car b))
      (and (string= (car a) (car b)) (< (cdr a) (cdr b)))))

;;; Queries

(defun chapter-jobs ()
  "Return the names of the chapter jobs: the chap-N.tex files, N a
number or a letter (chap-0-edit-history.tex is not one: chap-0 inputs
it)."
  (loop for pathname in (spec-files)
        for name = (pathname-name pathname)
        when (and (> (length name) 5) (string= "chap-" name :end2 5)
                  (not (find #\- name :start 5)))
          collect name))

(defun count-table (occurrences)
  "Return a hash table mapping each name used in OCCURRENCES to its uses
per file, in file order, as lists (file text body uncertain): uses outside
definitions, inside macro bodies, and how many of all of them lie on
uncertain lines."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (occurrence occurrences)
      (let* ((file (occurrence-file occurrence))
             (entries (gethash (occurrence-name occurrence) table))
             (entry (or (assoc file entries :test #'string=)
                        (let ((new (list file 0 0 0)))
                          (setf (gethash (occurrence-name occurrence) table)
                                (append entries (list new)))
                          new))))
        (incf (nth (if (eq (occurrence-context occurrence) :text) 1 2) entry))
        (when (occurrence-uncertain-p occurrence)
          (incf (nth 3 entry)))))
    table))

(defun name-counts (survey name)
  "Return the uses of NAME in SURVEY per file, as COUNT-TABLE does."
  (gethash name (count-table (remove-if-not (lambda (occurrence)
                                             (string= name (occurrence-name occurrence)))
                                           (survey-occurrences survey)))))

(defun name-class (survey name &optional plain-survey)
  "Return how NAME gets its meaning in SURVEY's job: :defined at top level,
:nested only inside another macro's body, :plain by PLAIN-SURVEY's job,
else :primitive."
  (flet ((defined-in (survey nested)
           (and survey
                (find-if (lambda (definition)
                           (and (string= name (definition-name definition))
                                (eq nested (and (definition-parent definition) t))))
                         (survey-definitions survey)))))
    (cond ((defined-in survey nil) :defined)
          ((defined-in survey t) :nested)
          ((or (defined-in plain-survey nil) (defined-in plain-survey t)) :plain)
          (t :primitive))))

(defun merge-surveys (surveys &optional (job-name "all"))
  "Return one survey holding what SURVEYS found, each file counted once:
from the first survey that read it.  Inputs and catcode notes are kept
once per place."
  (let ((seen-files '())
        (files '()) (definitions '()) (occurrences '()) (inputs '()) (notes '())
        (uncertain '()))
    (dolist (survey surveys)
      (let ((new (set-difference (survey-files survey) seen-files :test #'string=)))
        (flet ((new-p (file) (member file new :test #'string=)))
          (setf files (append files (remove-if-not #'new-p (survey-files survey))))
          (dolist (definition (survey-definitions survey))
            (when (new-p (definition-file definition)) (push definition definitions)))
          (dolist (occurrence (survey-occurrences survey))
            (when (new-p (occurrence-file occurrence)) (push occurrence occurrences)))
          (dolist (record (survey-inputs survey))
            (when (new-p (input-record-file record)) (push record inputs)))
          (dolist (note (survey-catcode-notes survey))
            (when (new-p (catcode-note-file note)) (push note notes)))
          (dolist (line (survey-uncertain-lines survey))
            (when (new-p (car line)) (push line uncertain)))
          (setf seen-files (append seen-files new)))))
    (make-survey :job-name job-name :files files
                 :definitions (nreverse definitions)
                 :occurrences (nreverse occurrences)
                 :inputs (nreverse inputs)
                 :catcode-notes (nreverse notes)
                 :uncertain-lines (sort (nreverse uncertain) #'line<))))
