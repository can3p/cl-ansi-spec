;;;; src/model/define-node.lisp
;;;;
;;;; The declarations of the model (docs/exports.md, "One definition,
;;;; everything generated"; docs/model.md, "Declarations"): DEFINE-NODE
;;;; declares a node kind, its fields and their documentation, and makes
;;;; its class; DEFINE-ENUM, DEFINE-TARGET-KIND and DEFINE-CATEGORY
;;;; declare what fields refer to.  Every declaration goes into a
;;;; registry, which the builder, the writers, the schema and the
;;;; reference doc read through the introspection functions below, and
;;;; which UNDOCUMENTED-ITEMS checks for missing documentation.
;;;; Owner: step 3.1.

(in-package #:cl-ansi-spec/model)

;;; Errors

(define-condition declaration-error (simple-error) ()
  (:documentation "A declaration (DEFINE-NODE, DEFINE-ENUM, ...) that is
malformed or clashes with another; signalled when the form is expanded
or registered."))

(defun declaration-error (control &rest arguments)
  "Signal a DECLARATION-ERROR with the message CONTROL and ARGUMENTS."
  (error 'declaration-error :format-control control :format-arguments arguments))

;;; Areas

(defparameter *areas*
  '(:structure :entries :blocks :tables :inlines :glossary :bnf :math)
  "The areas of the model, one per file src/model/nodes-<area>.lisp; each
declaration names its area, and the documentation ratchet has one file
per area (tests/model/undocumented-<area>.sexp).")

(defun check-area (area)
  "Signal an error unless AREA is one of *AREAS*."
  (unless (member area *areas*)
    (declaration-error "Unknown area ~S: one of ~S." area *areas*))
  area)

;;; Declarations

(defstruct (definition (:constructor nil))
  "What every definition has: its NAME, its AREA (see *AREAS*), and its
DOC, a docstring or NIL while it lacks one."
  (name nil :type symbol :read-only t)
  (area nil :type keyword :read-only t)
  (doc nil :type (or null string) :read-only t))

(defstruct (field (:constructor make-field
                      (name type &key required repeated doc
                                      (example nil example-p))))
  "A field of a node kind: NAME, a symbol (its slot; its JSON name is the
name in lower case); TYPE (see FIELD-TYPE-P); REQUIRED, true when every
node of the kind has a value; REPEATED, true when the value is a list of
values of TYPE; its DOC, and an EXAMPLE from the real spec when
EXAMPLE-P."
  (name nil :type symbol :read-only t)
  (type nil :read-only t)
  (required nil :type boolean :read-only t)
  (repeated nil :type boolean :read-only t)
  (doc nil :type (or null string) :read-only t)
  (example nil :read-only t)
  (example-p nil :type boolean :read-only t))

(defstruct (node-declaration (:include definition)
                             (:constructor make-node-declaration
                                 (name area &key doc kind categories fields
                                                 (example nil example-p))))
  "A node kind: its KIND keyword, the class NAME that holds its nodes, the
CATEGORIES (keywords) it belongs to, its FIELDS in order, and an EXAMPLE
node, written as an S-expression of the export, when EXAMPLE-P."
  (kind nil :type keyword :read-only t)
  (categories '() :type list :read-only t)
  (fields '() :type list :read-only t)
  (example nil :read-only t)
  (example-p nil :type boolean :read-only t))

(defstruct (enum (:include definition)
                 (:constructor make-enum (name area &key doc values)))
  "An enumeration: its VALUES, in order, each a list (KEYWORD DOC) where
DOC is NIL while the value lacks one."
  (values '() :type list :read-only t))

(defstruct (target-kind-declaration
            (:include definition) (:conc-name target-kind-) (:predicate nil)
            (:constructor make-target-kind (name area &key doc node)))
  "A kind of reference target, NAME a keyword (:GLOSSARY): a reference
of this kind points to a node of the kind NODE (a keyword) by its id."
  (node nil :type keyword :read-only t))

(defstruct (category (:include definition)
                     (:constructor make-category (name area &key doc)))
  "A category of node kinds, NAME a keyword (:BLOCK, :INLINE): a field
of type (:NODE category) holds a node of any kind in it.")

;;; The registry

(defstruct (registry (:constructor make-registry ()))
  "Declarations by kind, in the order they were first made: NODES
(NODE-DECLARATIONs), ENUMS, TARGET-KINDS and CATEGORIES."
  (nodes '() :type list)
  (enums '() :type list)
  (target-kinds '() :type list)
  (categories '() :type list))

(defvar *registry* (make-registry)
  "The registry of the model's declarations.  Declarations go into the
registry a variable names (:REGISTRY, by default this one), so that
tests declare their own kinds in a registry of their own.")

(defun replace-definition (definitions definition)
  "DEFINITIONS with DEFINITION in place of the one of the same name, or
at the end."
  (let ((position (position (definition-name definition) definitions
                            :key #'definition-name)))
    (if position
        (substitute definition (nth position definitions) definitions
                    :count 1 :start position)
        (append definitions (list definition)))))

(defun reader-name (class field)
  "The accessor of FIELD's slot in CLASS: CLASS-FIELD, in CLASS's package."
  (intern (format nil "~A-~A" (symbol-name class) (symbol-name field))
          (symbol-package class)))

(defun node-readers (declaration)
  "The accessor names of DECLARATION's fields."
  (loop for field in (node-declaration-fields declaration)
        collect (reader-name (definition-name declaration) (field-name field))))

(defun check-readers (declaration registry)
  "Signal a DECLARATION-ERROR when an accessor of DECLARATION's fields is
also one of another kind's in REGISTRY (kind A with field B-C, kind A-B
with field C)."
  (dolist (other (registry-nodes registry))
    (unless (eq (definition-name other) (definition-name declaration))
      (let ((shared (intersection (node-readers declaration) (node-readers other))))
        (when shared
          (declaration-error "~S and ~S both define the accessors ~S."
                             (definition-name declaration) (definition-name other)
                             shared))))))

(defun register (definition registry)
  "Put DEFINITION into REGISTRY, replacing one of the same name and
sort; return its name."
  (when (node-declaration-p definition)
    (check-readers definition registry))
  (macrolet ((put (accessor)
               `(setf (,accessor registry)
                      (replace-definition (,accessor registry) definition))))
    (etypecase definition
      (node-declaration (put registry-nodes))
      (enum (put registry-enums))
      (target-kind-declaration (put registry-target-kinds))
      (category (put registry-categories))))
  (definition-name definition))

;;; Field types

(defun field-type-p (type)
  "True when TYPE is a field type: :STRING, :INTEGER, :BOOLEAN, :SPAN (a
source span), :INLINES (a list of strings and nodes of the category
:INLINE), (:ENUM name), (:NODE name...) (a node of one of the kinds or
categories named), or (:TARGET kind...) (a reference to a node, through
one of the target kinds named, or NIL while unresolved)."
  (or (member type '(:string :integer :boolean :span :inlines))
      (and (consp type)
           (case (first type)
             (:enum (and (consp (rest type)) (null (cddr type))
                         (symbolp (second type))))
             ((:node :target) (and (consp (rest type))
                                   (null (cdr (last type)))
                                   (every #'keywordp (rest type))))))))

(defun parse-field (spec)
  "The FIELD of the field specification SPEC, (name type &key required
repeated doc example)."
  (destructuring-bind (name type &rest options) spec
    (unless (and (symbolp name) (not (keywordp name)))
      (declaration-error "A field name is a symbol, not ~S." name))
    (when (member (symbol-name name) '("KIND" "SPAN") :test #'string=)
      (declaration-error "The field name ~S is reserved: every node has it." name))
    (unless (field-type-p type)
      (declaration-error "Not a field type: ~S in ~S." type spec))
    (unless (and (evenp (length options))
                 (loop for key in options by #'cddr
                       always (member key '(:required :repeated :doc :example))))
      (declaration-error "Not field options: ~S in ~S." options spec))
    (destructuring-bind (&key required repeated doc (example nil example-p)) options
      (when (and repeated (member type '(:boolean :inlines)))
        (declaration-error "A ~S field cannot be repeated: ~S." type spec))
      (when (and doc (not (stringp doc)))
        (declaration-error "A field's doc is a string: ~S." spec))
      (if example-p
          (make-field name type :required (and required t) :repeated (and repeated t)
                                :doc doc :example example)
          (make-field name type :required (and required t) :repeated (and repeated t)
                                :doc doc)))))

;;; Declaring

(defun split-doc (body)
  "The docstring at the head of BODY, or NIL, and the rest of BODY."
  (if (stringp (first body))
      (values (first body) (rest body))
      (values nil body)))

(defun keyword-of (symbol)
  "The keyword named as SYMBOL."
  (intern (symbol-name symbol) '#:keyword))

(defclass node ()
  ((span :initarg :span :initform nil :accessor node-span
         :documentation "Where the node came from in the sources: a span
(cl-ansi-spec/tex), or NIL for a node made by the builder."))
  (:documentation "A node of the model.  Its class is the one DEFINE-NODE
made for its kind."))

(defgeneric node-kind (node)
  (:documentation "The kind of NODE, a keyword."))

(defun check-node-name (name)
  "Signal a DECLARATION-ERROR unless NAME may name a node kind and its
class: a symbol not of the COMMON-LISP package (whose classes and names
are locked) and not naming a class that is not a node's."
  (unless (and (symbolp name) name (not (keywordp name)))
    (declaration-error "A node kind is named by a symbol, not ~S." name))
  (when (eq (symbol-package name) (find-package '#:common-lisp))
    (declaration-error "~S is a symbol of COMMON-LISP; name the kind in its own package."
                       name))
  (let ((class (find-class name nil)))
    (when (and class (not (subtypep class 'node)))
      (declaration-error "~S already names a class that is not a node's." name))))

(defmacro define-node (name (&key area categories (example nil example-p)
                                  (registry '*registry*))
                       &body body)
  "Declare the node kind named as the symbol NAME (its kind is the keyword
of that name) in AREA (*AREAS*), and define its class NAME, a subclass of
NODE with one slot per field, initarg the field's keyword and accessor
NAME-FIELD (its JSON name is the field's name in lower case).  BODY is an optional docstring, then one specification per
field, (field type &key required repeated doc example): TYPE as
FIELD-TYPE-P says, REQUIRED when every node of the kind has a value,
REPEATED when the value is a list.  CATEGORIES are the categories the
kind belongs to; EXAMPLE a node of the real spec, as the S-expression
export writes it.  The declaration goes into the registry the variable
REGISTRY holds."
  (multiple-value-bind (doc specs) (split-doc body)
    (check-area area)
    (check-node-name name)
    (let ((fields (mapcar #'parse-field specs))
          (kind (keyword-of name)))
      `(progn
         (defclass ,name (node)
           (,@(loop for field in fields
                    for slot = (field-name field)
                    collect `(,slot :initarg ,(keyword-of slot)
                                    :initform nil
                                    :accessor ,(reader-name name slot)
                                    ,@(when (field-doc field)
                                        `(:documentation ,(field-doc field))))))
           ,@(when doc `((:documentation ,doc))))
         (defmethod node-kind ((node ,name)) ,kind)
         (register (make-node-declaration
                    ',name ,area :doc ,doc :kind ,kind :categories ',categories
                    :fields (mapcar #'parse-field ',specs)
                    ,@(when example-p `(:example ',example)))
                   ,registry)
         ',name))))

(defmacro define-enum (name (&key area (registry '*registry*)) &body body)
  "Declare the enumeration NAME (a symbol) in AREA.  BODY is an optional
docstring, then one (keyword [doc]) per value, in order."
  (multiple-value-bind (doc values) (split-doc body)
    (check-area area)
    (dolist (value values)
      (unless (and (consp value) (keywordp (first value))
                   (typep (rest value) '(or null (cons string null))))
        (declaration-error "Not an enumeration value: ~S in ~S." value name)))
    `(register (make-enum ',name ,area :doc ,doc
                          :values ',(loop for (value doc) in values
                                          collect (list value doc)))
               ,registry)))

(defmacro define-target-kind (name (&key area node (registry '*registry*))
                              &optional doc)
  "Declare the target kind NAME (a keyword) in AREA: a reference of this
kind points to a node of the kind NODE (a keyword), by its id."
  (unless (and (keywordp name) (keywordp node))
    (declaration-error "A target kind and its node kind are keywords: ~S, ~S." name node))
  (check-area area)
  `(register (make-target-kind ,name ,area :doc ,doc :node ,node) ,registry))

(defmacro define-category (name (&key area (registry '*registry*)) &optional doc)
  "Declare the category of node kinds NAME (a keyword) in AREA; a kind
joins it by naming it in its :CATEGORIES."
  (unless (keywordp name)
    (declaration-error "A category is named by a keyword, not ~S." name))
  (check-area area)
  `(register (make-category ,name ,area :doc ,doc) ,registry))

;;; Introspection, for the builder, the writers and the generators

(defun node-kinds (&optional (registry *registry*))
  "The declared node kinds (keywords), in declaration order."
  (mapcar #'node-declaration-kind (registry-nodes registry)))

(defun find-node-declaration (kind &optional (registry *registry*))
  "The NODE-DECLARATION of the node kind KIND, or NIL."
  (find kind (registry-nodes registry) :key #'node-declaration-kind))

(defun node-fields (kind &optional (registry *registry*))
  "The FIELDs of the node kind KIND, in order."
  (let ((declaration (find-node-declaration kind registry)))
    (unless declaration
      (error "Unknown node kind ~S." kind))
    (node-declaration-fields declaration)))

(defun enums (&optional (registry *registry*))
  "The declared ENUMs, in order."
  (copy-list (registry-enums registry)))

(defun find-enum (name &optional (registry *registry*))
  "The ENUM named NAME (a symbol of any package, compared by name), or
NIL."
  (find (string name) (registry-enums registry)
        :key (lambda (enum) (symbol-name (definition-name enum))) :test #'string=))

(defun target-kinds (&optional (registry *registry*))
  "The declared TARGET-KIND-DECLARATIONs, in order."
  (copy-list (registry-target-kinds registry)))

(defun find-target-kind (name &optional (registry *registry*))
  "The TARGET-KIND-DECLARATION named NAME, or NIL."
  (find name (registry-target-kinds registry) :key #'definition-name))

(defun categories (&optional (registry *registry*))
  "The declared CATEGORYs, in order."
  (copy-list (registry-categories registry)))

(defun find-category (name &optional (registry *registry*))
  "The CATEGORY named NAME, or NIL."
  (find name (registry-categories registry) :key #'definition-name))

(defun category-kinds (category &optional (registry *registry*))
  "The node kinds in CATEGORY, in declaration order."
  (loop for declaration in (registry-nodes registry)
        when (member category (node-declaration-categories declaration))
          collect (node-declaration-kind declaration)))

(defun expand-kinds (names &optional (registry *registry*))
  "The node kinds NAMES stand for, each a kind or a category, without
repetition, in order."
  (let ((kinds '()))
    (dolist (name names (nreverse kinds))
      (dolist (kind (if (find-category name registry)
                        (category-kinds name registry)
                        (list name)))
        (pushnew kind kinds)))))

;;; Consistency

(defun type-references (type)
  "The declarations the field type TYPE refers to, as (:ENUM name),
(:NODE name) and (:TARGET name) lists."
  (when (consp type)
    (ecase (first type)
      (:enum (list (list :enum (second type))))
      (:node (loop for name in (rest type) collect (list :node name)))
      (:target (loop for name in (rest type) collect (list :target name))))))

(defun registry-problems (&optional (registry *registry*))
  "The problems of REGISTRY, as strings: names a declaration uses but no
declaration makes (enums, kinds or categories, target kinds and the
kinds they point to, categories of kinds), and kinds that are also
categories."
  (let ((problems '()))
    (flet ((problem (control &rest arguments)
             (push (apply #'format nil control arguments) problems)))
      (dolist (declaration (registry-nodes registry))
        (let ((kind (node-declaration-kind declaration)))
          (when (find-category kind registry)
            (problem "~S is both a node kind and a category." kind))
          (dolist (category (node-declaration-categories declaration))
            (unless (find-category category registry)
              (problem "~S belongs to the undeclared category ~S." kind category)))
          (dolist (field (node-declaration-fields declaration))
            (loop for (sort name) in (type-references (field-type field))
                  unless (ecase sort
                           (:enum (find-enum name registry))
                           (:node (or (find-node-declaration name registry)
                                      (find-category name registry)))
                           (:target (find-target-kind name registry)))
                    do (problem "~S's field ~(~A~) names the undeclared ~(~A~) ~S."
                                kind (field-name field) sort name)))))
      (dolist (target (registry-target-kinds registry))
        (unless (find-node-declaration (target-kind-node target) registry)
          (problem "The target kind ~S points to the undeclared kind ~S."
                   (definition-name target) (target-kind-node target)))))
    (nreverse problems)))

;;; Values

(defstruct (target (:constructor make-target (kind id)))
  "A resolved reference: the node of the target kind KIND (a keyword)
whose id is ID (a string)."
  (kind nil :type keyword :read-only t)
  (id "" :type string :read-only t))

(defun find-field (kind name &optional (registry *registry*))
  "The FIELD of the node kind KIND named NAME, a symbol of any package
(a keyword, usually) compared by name; NIL when there is none."
  (find (string name) (node-fields kind registry)
        :key (lambda (field) (symbol-name (field-name field))) :test #'string=))

(defun node-slot (node field registry)
  "The slot name of NODE's FIELD (a FIELD or a field name)."
  (if (field-p field)
      (field-name field)
      (let ((found (find-field (node-kind node) field registry)))
        (unless found
          (error "~S has no field ~S." (node-kind node) field))
        (field-name found))))

(defun node-field-value (node field &optional (registry *registry*))
  "The value of NODE's FIELD: a FIELD, or a field's name (a symbol of any
package, compared by name)."
  (slot-value node (node-slot node field registry)))

(defun (setf node-field-value) (value node field &optional (registry *registry*))
  "Set NODE's FIELD to VALUE, FIELD as for NODE-FIELD-VALUE."
  (setf (slot-value node (node-slot node field registry)) value))

(defun make-node (kind &rest initargs &key span &allow-other-keys)
  "A new node of the kind KIND (a keyword) in *REGISTRY*, with its SPAN
and its fields given as INITARGS, each field's keyword.  Nothing is
checked: the builder fills a node as its events come, and NODE-PROBLEMS
checks it once it is complete."
  (declare (ignore span))
  (let ((declaration (find-node-declaration kind)))
    (unless declaration
      (error "Unknown node kind ~S." kind))
    (apply #'make-instance (definition-name declaration) initargs)))

(defun value-problem (value type registry)
  "Why VALUE is not of the field type TYPE (a string), or NIL."
  (flet ((node-of-p (value names)
           (and (typep value 'node)
                (member (node-kind value) (expand-kinds names registry)))))
    (let ((ok (cond ((eq type :string) (stringp value))
                    ((eq type :integer) (integerp value))
                    ((eq type :boolean) (typep value 'boolean))
                    ((eq type :span) (typep value 'span))
                    ((eq type :inlines)
                     (and (listp value)
                          (every (lambda (item)
                                   (or (stringp item) (node-of-p item '(:inline))))
                                 value)))
                    ((eq (first type) :enum)
                     (let ((enum (find-enum (second type) registry)))
                       (and enum (assoc value (enum-values enum)))))
                    ((eq (first type) :node) (node-of-p value (rest type)))
                    ((eq (first type) :target)
                     (and (target-p value) (member (target-kind value) (rest type)))))))
      (unless ok
        (format nil "~S is not of type ~S" value type)))))

(defun node-problems (node &optional (registry *registry*))
  "The problems of NODE against its kind's declaration, as strings: a
required field without a value (NIL, or an empty list when repeated),
a value not of its field's type.  A target field may be NIL (an
unresolved reference); other absent optional fields are NIL."
  (let ((kind (node-kind node))
        (problems '()))
    (dolist (field (node-fields kind registry) (nreverse problems))
      (let ((value (node-field-value node field))
            (type (field-type field)))
        (cond ((and (null value) (eq type :boolean)))
              ((null value)
               (when (and (field-required field)
                          (not (and (consp type) (eq (first type) :target))))
                 (push (format nil "~S has no ~(~A~)" kind (field-name field)) problems)))
              ((and (field-repeated field) (not (listp value)))
               (push (format nil "~S's ~(~A~) is not a list" kind (field-name field))
                     problems))
              (t
               (dolist (item (if (field-repeated field) value (list value)))
                 (let ((problem (value-problem item type registry)))
                   (when problem
                     (push (format nil "~S's ~(~A~): ~A" kind (field-name field) problem)
                           problems))))))))))

;;; Documentation

(defun undocumented-items (area &optional (registry *registry*))
  "What in AREA lacks documentation (docs/exports.md, \"Documentation of
every definition\"), in declaration order: (:DOC :NODE kind), (:EXAMPLE
:NODE kind), (:DOC :FIELD kind field), (:EXAMPLE :FIELD kind field),
(:DOC :ENUM name), (:DOC :ENUM-VALUE name value), (:DOC :TARGET-KIND
name) and (:DOC :CATEGORY name).  A docstring counts when it is not
blank."
  (check-area area)
  (let ((items '()))
    (flet ((note (item) (push item items))
           (documented-p (doc) (and doc (string/= "" (string-trim "
" doc)))))
      (dolist (declaration (registry-nodes registry))
        (when (eq area (definition-area declaration))
          (let ((kind (node-declaration-kind declaration)))
            (unless (documented-p (definition-doc declaration))
              (note (list :doc :node kind)))
            (unless (and (node-declaration-example-p declaration)
                         (node-declaration-example declaration))
              (note (list :example :node kind)))
            (dolist (field (node-declaration-fields declaration))
              (let ((name (keyword-of (field-name field))))
                (unless (documented-p (field-doc field))
                  (note (list :doc :field kind name)))
                (unless (field-example-p field)
                  (note (list :example :field kind name))))))))
      (dolist (enum (registry-enums registry))
        (when (eq area (definition-area enum))
          (let ((name (keyword-of (definition-name enum))))
            (unless (documented-p (definition-doc enum))
              (note (list :doc :enum name)))
            (loop for (value doc) in (enum-values enum)
                  unless (documented-p doc)
                    do (note (list :doc :enum-value name value))))))
      (dolist (target (registry-target-kinds registry))
        (when (and (eq area (definition-area target))
                   (not (documented-p (definition-doc target))))
          (note (list :doc :target-kind (definition-name target)))))
      (dolist (category (registry-categories registry))
        (when (and (eq area (definition-area category))
                   (not (documented-p (definition-doc category))))
          (note (list :doc :category (definition-name category))))))
    (nreverse items)))
