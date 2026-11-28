;;;; src/model/resolve-operators.lisp
;;;;
;;;; Operator references (\clref and its wrappers) resolved to dictionary entries.
;;;; Owner: step 3.18 of docs/plan/m3.md.
;;;;
;;;; The model has one node, :OPERATOR-REF, for \clref and every wrapper;
;;;; its :VIA says which wrapper wrote it.  Resolution runs on the built
;;;; model, after ASSIGN-IDS (an entry's id is final only then), and sets
;;;; :TARGET to the entry named by the reference's text.  Rules, in order
;;;; (docs/model.md, "References: operators"):
;;;;
;;;;   1. The text is normalised (CLREF-NORMALISE): trimmed, `\&' is `&'.
;;;;   2. A reference that cannot name an entry is :ENTRYLESS, no target and
;;;;      no problem: a :VIA of *CLREF-ENTRYLESS-VIAS*, or a text that is a
;;;;      keyword (`:test') or a lambda list keyword (`&key').
;;;;   3. The candidates are the entries with the name among their :NAMES.
;;;;      None: :UNRESOLVED.
;;;;   4. The candidates whose kind the wrapper prefers
;;;;      (*CLREF-PREFERRED-KINDS*) are kept when there are any; else all.
;;;;   5. One candidate: :RESOLVED.  Several: :AMBIGUOUS, no target.

(in-package #:cl-ansi-spec/model)

(defparameter *clref-entryless-vias*
  '((:keyword . "a keyword is not a defined name of the dictionary")
    (:package . "a package has no dictionary entry")
    (:lambda-list-keyword . "a lambda list keyword has no dictionary entry")
    (:loop-keyword . "a loop keyword is defined by loop, not by an entry of its own; an entry of the same name is another thing"))
  "The reference kinds that never point to an entry, each with the reason.")

(defparameter *clref-preferred-kinds*
  '((:function :function :accessor :standard-generic-function :local-function)
    (:macro :macro :local-macro)
    (:special-operator :special-operator)
    (:type :type :class :system-class :condition-type :type-specifier)
    (:variable :variable :constant-variable)
    (:constant :constant-variable)
    (:declaration :declaration)
    (:misc :symbol :restart :constant-variable))
  "For each reference kind that has a preference, the entry kinds it
prefers on a name that entries of several kinds share (`list' is a system
class and a function; \\typeref{list} means the class).  \\clref (:ANY) and
\\ttref (:TYPEWRITER) prefer none.")

(defstruct (clref-finding (:constructor make-clref-finding (node outcome entries message)))
  "What resolving one :OPERATOR-REF found when it did not point to one
entry: the NODE, the OUTCOME (:UNRESOLVED or :AMBIGUOUS), the ids of the
candidate ENTRIES (several for :AMBIGUOUS) and a MESSAGE."
  (node nil :read-only t)
  (outcome nil :type keyword :read-only t)
  (entries '() :type list :read-only t)
  (message "" :type string :read-only t))

(defun clref-normalise (text)
  "The name a reference's TEXT means: trimmed, with the TeX spelling `\\&'
of an ampersand as `&'."
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline) text)) (out (make-string-output-stream)))
    (loop with n = (length trimmed)
          for i from 0 below n
          for c = (char trimmed i)
          unless (and (char= c #\\) (< (1+ i) n) (char= (char trimmed (1+ i)) #\&))
            do (write-char c out))
    (get-output-stream-string out)))

(defun clref-index (items &key (registry *registry*))
  "The dictionary entries of ITEMS by name: a hash table from a name to
the list of its (entry-kind . id), in document order, each entry once."
  (let ((index (make-hash-table :test 'equal)))
    (walk-nodes (lambda (node)
                  (when (eq (node-kind node) :dictionary-entry)
                    (let ((candidate (cons (node-field-value node :entry-kind registry)
                                           (node-field-value node :id registry))))
                      (dolist (name (node-field-value node :names registry))
                        (pushnew candidate (gethash name index) :test #'equal)))))
                items registry)
    (maphash (lambda (name candidates) (setf (gethash name index) (reverse candidates))) index)
    index))

(defun clref-entryless-reason (via name)
  "Why a reference of kind VIA to NAME names no dictionary entry, or NIL
when it may."
  (flet ((reason (kind) (cdr (assoc kind *clref-entryless-vias*))))
    (or (reason via)
        (and (plusp (length name))
             (case (char name 0)
               (#\: (reason :keyword))
               (#\& (reason :lambda-list-keyword)))))))

(defun clref-resolve (via text index)
  "Resolve a reference of kind VIA (a keyword of REFERENCE-KIND) to TEXT
against INDEX (CLREF-INDEX).  Return the outcome (:RESOLVED, :ENTRYLESS,
:UNRESOLVED or :AMBIGUOUS), the ids of the entries concerned (one when
resolved, the candidates when ambiguous) and a message (NIL when
resolved)."
  (let* ((name (clref-normalise text))
         (entryless (clref-entryless-reason via name)))
    (cond (entryless (values :entryless '() entryless))
          ((string= name "")
           (values :unresolved '() "The reference has no text."))
          (t
           (let* ((candidates (gethash name index))
                  (preferred (remove-if-not (lambda (candidate)
                                              (member (car candidate)
                                                      (cdr (assoc via *clref-preferred-kinds*))))
                                            candidates))
                  (pool (or preferred candidates)))
             (cond ((null pool)
                    (values :unresolved '()
                            (format nil "No dictionary entry describes ~S." name)))
                   ((rest pool)
                    (values :ambiguous (mapcar #'cdr pool)
                            (format nil "~S names entries of several kinds (~{~(~A~)~^, ~}) and ~(~A~) prefers none of them."
                                    name (mapcar #'car pool) via)))
                   (t (values :resolved (list (cdar pool)) nil))))))))

(defun resolve-operator-refs (items &key (registry *registry*) (apply t))
  "Resolve every :OPERATOR-REF of ITEMS, a built model whose ids ASSIGN-IDS
settled: set its :TARGET to the entry it names (unless APPLY is false);
the :TARGET of a reference that does not resolve is left as it was.
Return the number resolved and the CLREF-FINDINGs, in document order, of
the references that did not point to one entry; :ENTRYLESS ones are no
finding."
  (let ((index (clref-index items :registry registry)) (resolved 0) (findings '()))
    (walk-nodes (lambda (node)
                  (when (eq (node-kind node) :operator-ref)
                    (multiple-value-bind (outcome ids message)
                        (clref-resolve (node-field-value node :via registry)
                                       (node-field-value node :text registry) index)
                      (case outcome
                        (:resolved
                         (incf resolved)
                         (when apply
                           (setf (node-field-value node :target registry)
                                 (make-target :entry (first ids)))))
                        ((:unresolved :ambiguous)
                         (push (make-clref-finding node outcome ids message) findings))))))
                items registry)
    (values resolved (nreverse findings))))
