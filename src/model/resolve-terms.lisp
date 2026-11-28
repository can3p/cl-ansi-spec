;;;; src/model/resolve-terms.lisp
;;;;
;;;; Term references resolved to glossary entries by explicit inflection
;;;; rules (docs/model.md, "References: terms"): RESOLVE-TERMS sets the
;;;; :TARGET of every :TERM-REF of a model and reports what it cannot
;;;; resolve, what it resolves two ways, and the \meaning senses the
;;;; entry found has not.
;;;; Owner: step 3.19 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/model)

;;; The rules

(defparameter *term-irregulars*
  '(("leaves" "leaf" "the plural of leaf (concept-glossary.tex:2663), \\term{leaves}")
    ("indices" "index" "the plural of index in valid array index and
bounding index (concept-glossary.tex:607)")
    ("written" "write" "the past participle of write, \\term{written}
(concept-places.tex:559)")
    ("thrown" "throw" "the past participle of throw, \\term{thrown}
(concept-glossary.tex:723)")
    ("\\symbolnamedesignator" "string designator" "a macro in the
argument: setup-terms.tex:260 defines it as `string designator'")
    ("\\symbolnamedesignators" "string designator" "a macro in the
argument: setup-terms.tex:261 defines it as `string designators'")
    ("\\packagenamedesignator" "string designator" "a macro in the
argument: setup-terms.tex:262 defines it as `string designator'")
    ("\\packagenamedesignators" "string designator" "a macro in the
argument: setup-terms.tex:263 defines it as `string designators'"))
  "The words whose base no suffix rule derives: (word base reason), the
word as the argument writes it, compared ignoring case.")

(defun term-consonant-p (char)
  "True when CHAR is a lower-case consonant (y included)."
  (and (char<= #\a char #\z) (not (find char "aeiou"))))

(defun term-doubled-before-p (word suffix)
  "True when WORD ends with SUFFIX after a doubled consonant (stopped,
-ed; setting, -ing)."
  (let ((end (- (length word) (length suffix))))
    (and (>= end 3)
         (string= suffix word :start2 end)
         (char= (char word (- end 1)) (char word (- end 2)))
         (term-consonant-p (char word (- end 1))))))

(defun term-strip (word suffix &optional (replacement ""))
  "WORD without its SUFFIX, REPLACEMENT in its place, when WORD ends with
SUFFIX and keeps at least two characters; NIL otherwise."
  (let ((end (- (length word) (length suffix))))
    (when (and (>= end 2) (string= suffix word :start2 end))
      (concatenate 'string (subseq word 0 end) replacement))))

(defparameter *term-suffix-rules*
  `((:ies "-ies for -y: bodies, body"
     ,(lambda (word) (term-strip word "ies" "y")))
    (:es "-es after s, x, z, ch or sh: classes, class"
     ,(lambda (word)
        (when (some (lambda (ending) (term-strip word (concatenate 'string ending "es")))
                    '("s" "x" "z" "ch" "sh"))
          (term-strip word "es"))))
    (:s "-s, not after s: objects, object"
     ,(lambda (word) (unless (term-strip word "ss") (term-strip word "s"))))
    (:ed "-ed: signaled, signal"
     ,(lambda (word) (term-strip word "ed")))
    (:d "-d after e: evaluated, evaluate"
     ,(lambda (word) (term-strip word "ed" "e")))
    (:doubled-ed "a doubled consonant and -ed: stopped, stop"
     ,(lambda (word) (when (term-doubled-before-p word "ed")
                       (subseq word 0 (- (length word) 3)))))
    (:ing "-ing: binding, bind"
     ,(lambda (word) (term-strip word "ing")))
    (:ing-e "-ing for -e: evaluating, evaluate"
     ,(lambda (word) (term-strip word "ing" "e")))
    (:doubled-ing "a doubled consonant and -ing: setting, set"
     ,(lambda (word) (when (term-doubled-before-p word "ing")
                       (subseq word 0 (- (length word) 4))))))
  "The suffix rules, in the order they are tried: (rule doc function),
FUNCTION giving a word's base by the rule, or NIL when it does not
apply.  The irregulars (*TERM-IRREGULARS*, rule :IRREGULAR) are tried
before them.")

(defparameter *term-rules*
  (cons :irregular (mapcar #'first *term-suffix-rules*))
  "Every inflection rule, in the order they are tried.")

(defun term-word-bases (word)
  "The bases of WORD, in rule order: a list of (rule . base)."
  (let ((irregular (assoc word *term-irregulars* :test #'string-equal)))
    (append (and irregular (list (cons :irregular (second irregular))))
            (loop for (rule nil function) in *term-suffix-rules*
                  for base = (funcall function word)
                  when base collect (cons rule base)))))

(defun term-split (name)
  "The words of NAME, split at its spaces."
  (uiop:split-string name :separator " "))

(defparameter *term-tiers* '(:name :last-word :first-word)
  "The tiers of the lookup, in the order they are tried: the name
itself, its last word inflected, its first word inflected.")

(defun term-candidates (name)
  "The names to look NAME up by: for each tier of *TERM-TIERS*, a list
of (rule . candidate) in rule order, the rule of the name itself
:EXACT; the first word is inflected only in a name of more than one
word."
  (let* ((words (term-split name)) (last (car (last words))))
    (list (list (cons :exact name))
          (loop for (rule . base) in (term-word-bases last)
                collect (cons rule (format nil "~{~A ~}~A" (butlast words) base)))
          (and (rest words)
               (loop for (rule . base) in (term-word-bases (first words))
                     collect (cons rule (format nil "~A~{ ~A~}" base (rest words))))))))

;;; The glossary

(defun term-glossary-table (items registry)
  "The glossary entries of ITEMS by their id, ignoring case (an EQUALP
hash table to lists of entries, in document order)."
  (let ((table (make-hash-table :test 'equalp)))
    (walk-nodes (lambda (node)
                  (when (eq (node-kind node) :glossary-entry)
                    (push node (gethash (node-field-value node :id registry) table))))
                items registry)
    (maphash (lambda (id entries) (setf (gethash id table) (reverse entries))) table)
    table))

(defun term-lookup (name table)
  "The resolution of NAME through the glossary TABLE: the distinct
entries the first tier that finds any yields, in rule order, and the
tier and rule that found the first; NIL when none does."
  (loop for tier in *term-tiers*
        for candidates in (term-candidates name)
        do (let ((rule nil) (entries '()))
             (loop for (candidate-rule . candidate) in candidates
                   do (dolist (entry (gethash candidate table))
                        (unless (member entry entries)
                          (unless rule (setf rule candidate-rule))
                          (push entry entries))))
             (when entries
               (return (values (nreverse entries) tier rule))))
        finally (return (values '() nil nil))))

(defun term-entry-has-sense-p (entry sense registry)
  "True when the glossary ENTRY has a sense numbered SENSE, or SENSE is
1 and ENTRY has one sense, without a number."
  (let ((senses (node-field-value entry :senses registry)))
    (or (find sense senses :key (lambda (node) (node-field-value node :number registry)))
        (and (eql sense 1) senses (null (rest senses))
             (null (node-field-value (first senses) :number registry))))))

;;; The references

(defun term-references (items registry)
  "Every :TERM-REF of ITEMS, at any depth, in document order, each as
(reference . name): the name it is looked up by, its text, or for a
defining reference followed by a term index entry (\\newterm,
\\newtermidx's second argument), that entry's text."
  (let ((found '()))
    (labels ((name (reference next)
               ;; The index entry's text names a defining reference.
               (or (and (node-field-value reference :defining registry)
                        (typep next 'node)
                        (eq (node-kind next) :index-entry)
                        (eq (node-field-value next :index-kind registry) :term)
                        (node-field-value next :text registry))
                   (node-field-value reference :text registry)))
             (walk (value next)
               (typecase value
                 (node (when (eq (node-kind value) :term-ref)
                         (push (cons value (name value next)) found))
                       (dolist (field (node-fields (node-kind value) registry))
                         (walk (node-field-value value field registry) nil)))
                 (cons (walk-list value))))
             (walk-list (values)
               (loop for (value . rest) on values
                     do (walk value (first rest)))))
      (walk-list items))
    (nreverse found)))

(defun term-problem (kind reference format &rest arguments)
  "A problem of KIND at REFERENCE's span, its message made by FORMAT."
  (make-problem kind (node-span reference)
                :message (apply #'format nil format arguments)))

(defun resolve-term (reference name table registry)
  "Set REFERENCE's target from NAME through the glossary TABLE; return
its problems, and the tier and rule that resolved it (NIL when none
did)."
  (multiple-value-bind (entries tier rule) (term-lookup name table)
    (let ((entry (first entries)) (problems '()))
      (setf (node-field-value reference :target registry)
            (and entry (make-target :glossary (node-field-value entry :id registry))))
      (cond ((null entry)
             (push (term-problem :unresolved-term reference
                                 "No glossary entry for ~S." name)
                   problems))
            ((rest entries)
             (push (term-problem :ambiguous-term reference
                                 "~S is ~{~S~^ or ~} by ~(~A~) of the ~(~A~); the first is kept." name
                                 (mapcar (lambda (entry) (node-field-value entry :id registry))
                                         entries)
                                 rule tier)
                   problems)))
      (let ((sense (node-field-value reference :sense registry)))
        (when (and entry sense (not (term-entry-has-sense-p entry sense registry)))
          (push (term-problem :missing-sense reference
                              "~S (by ~(~A~) of the ~(~A~)) has no sense ~D."
                              (node-field-value entry :id registry) rule tier sense)
                problems)))
      (values (nreverse problems) tier rule))))

(defun term-case-problems (table registry)
  "An :AMBIGUOUS-TERM problem for each glossary entry of TABLE whose id
another one's equals but for case, at its span."
  (let ((problems '()))
    (maphash (lambda (id entries)
               (declare (ignore id))
               (dolist (entry (rest entries))
                 (unless (equal (node-field-value entry :id registry)
                                (node-field-value (first entries) :id registry))
                   (push (term-problem :ambiguous-term entry
                                       "The glossary ids ~S and ~S differ only by case."
                                       (node-field-value (first entries) :id registry)
                                       (node-field-value entry :id registry))
                         problems))))
             table)
    (sort problems #'string< :key #'problem-message)))

(defun resolve-terms (items &key (glossary items) (registry *registry*))
  "Resolve every :TERM-REF of ITEMS (a built model) to an entry of the
glossary of GLOSSARY (by default ITEMS itself): set its :TARGET, NIL
when unresolved.  Running it again gives the same targets.  Return the
problems, those of the glossary's ids first, then the references' in
document order; and how often each tier and rule resolved a reference,
an alist ((tier . rule) . count) in the order they were first used."
  (let ((table (term-glossary-table glossary registry))
        (counts '())
        (problems '()))
    (loop for (reference . name) in (term-references items registry)
          do (multiple-value-bind (reference-problems tier rule)
                 (resolve-term reference name table registry)
               (when tier
                 (let ((cell (assoc (cons tier rule) counts :test #'equal)))
                   (if cell
                       (incf (cdr cell))
                       (push (cons (cons tier rule) 1) counts))))
               (setf problems (revappend reference-problems problems))))
    (values (append (term-case-problems table registry) (nreverse problems))
            (nreverse counts))))
