;;;; tests/model/define-node.lisp
;;;;
;;;; DEFINE-NODE and the registry (src/model/define-node.lisp), on node
;;;; kinds declared here, in a registry of their own.  Owner: step 3.1.

(in-package #:cl-ansi-spec/tests)

(defvar *test-registry* (model:make-registry)
  "The registry of the node kinds these tests declare, apart from the
model's.")

(model:define-category :test-block (:area :blocks :registry *test-registry*)
  "A block of the tests.")

(model:define-category :inline (:area :inlines :registry *test-registry*)
  "An inline of the tests.")

(model:define-enum test-kind (:area :entries :registry *test-registry*)
  "The kinds of a test entry."
  (:function "A function.")
  (:macro))

(model:define-target-kind :test-entry (:area :entries :node :test-entry
                                       :registry *test-registry*)
  "A test entry, by its id.")

(model:define-node test-entry (:area :entries :categories (:test-block)
                               :example (:test-entry :id "endp" :names ("endp"))
                               :registry *test-registry*)
  "An entry of the tests."
  (id :string :required t :doc "Its id." :example "endp")
  (names :string :required t :repeated t :doc "Its names.")
  (flavor (:enum test-kind) :example :function)
  (count :integer)
  (none :boolean :doc "True when empty." :example t)
  (parts (:node :test-block) :repeated t :doc "Its parts." :example ())
  (text :inlines :doc "Its text." :example ("a " (:test-ref "b")))
  (see (:target :test-entry) :doc "Where it points." :example nil))

(model:define-node test-ref (:area :inlines :categories (:inline)
                             :registry *test-registry*)
  (to (:target :test-entry) :required t))

(define-test define-node
  :parent model
  :description "Declaring node kinds, their classes and the registry.")

(define-test define-node-classes
  :parent define-node
  (let ((model:*registry* *test-registry*)
        (node (make-instance 'test-entry :id "endp" :names '("endp") :flavor :function)))
    (is eq :test-entry (model:node-kind node))
    (is string= "endp" (test-entry-id node))
    (is equal '("endp") (test-entry-names node))
    (is eq nil (test-entry-parts node))
    (is eq nil (model:node-span node))
    (is equal '("endp") (model:node-field-value node 'names))))

(define-test define-node-registry
  :parent define-node
  (let ((model:*registry* *test-registry*))
    (is equal '(:test-entry :test-ref) (model:node-kinds))
    (is equal '(id names flavor count none parts text see)
        (mapcar #'model:field-name (model:node-fields :test-entry)))
    (let ((names (find 'names (model:node-fields :test-entry) :key #'model:field-name))
          (see (find 'see (model:node-fields :test-entry) :key #'model:field-name)))
      (is eq :string (model:field-type names))
      (true (model:field-required names))
      (true (model:field-repeated names))
      (false (model:field-example-p names))
      (is equal '(:target :test-entry) (model:field-type see))
      (true (model:field-example-p see))
      (is eq nil (model:field-example see)))
    (is equal '(:test-entry) (model:category-kinds :test-block))
    (is equal '(:test-entry :test-ref) (model:expand-kinds '(:test-block :inline :test-ref)))
    (is equal '((:function "A function.") (:macro nil))
        (model:enum-values (model:find-enum 'test-kind)))
    (is eq :test-entry (model:target-kind-node (model:find-target-kind :test-entry)))
    (is equal '() (model:registry-problems))
    (fail (model:node-fields :no-such-kind))))

(define-test define-node-redefinition
  :parent define-node
  ;; Declaring a name again replaces its declaration in place.
  (let ((registry (model:make-registry)))
    (let ((model:*registry* registry))
      (model:define-category :a (:area :blocks) "One.")
      (model:define-category :b (:area :blocks) "Two.")
      (model:define-category :a (:area :blocks) "One again.")
      (is equal '(:a :b) (mapcar #'model:definition-name (model:categories)))
      (is string= "One again." (model:definition-doc (model:find-category :a))))))

(define-test define-node-checks
  :parent define-node
  ;; Malformed declarations are refused when the form is expanded.
  (flet ((expand (form) (macroexpand-1 form)))
    (macrolet ((fail* (form) `(fail ,form 'model:declaration-error)))
    (fail* (expand '(model:define-node bad (:area :nowhere))))
    (fail* (expand '(model:define-node bad (:area :blocks) (kind :string))))
    (fail* (expand '(model:define-node bad (:area :blocks) (span :string))))
    (fail* (expand '(model:define-node bad (:area :blocks) (x :float))))
    (fail* (expand '(model:define-node bad (:area :blocks) (x (:node)))))
    (fail* (expand '(model:define-node bad (:area :blocks) (x :boolean :repeated t))))
    (fail* (expand '(model:define-node bad (:area :blocks) (x :string :colour :red))))
    (fail* (expand '(model:define-enum bad (:area :blocks) (:a 1))))
    (fail* (expand '(model:define-category bad (:area :blocks))))
    (fail* (expand '(model:define-node bad (:area :blocks) (x (:enum . e)))))
    (fail* (expand '(model:define-node string (:area :blocks))))
    (fail* (expand '(model:define-node model:field (:area :blocks))))))
  ;; Two kinds whose accessors would be the same function.
  (let ((model:*registry* (model:make-registry)))
    (eval '(model:define-node clash-a (:area :blocks) (b-c :string)))
    (fail (eval '(model:define-node clash-a-b (:area :blocks) (c :string)))
          'model:declaration-error))
  ;; Names used but not declared are registry problems.
  (let ((registry (model:make-registry)))
    (let ((model:*registry* registry))
      (model:define-target-kind :t1 (:area :blocks :node :missing-node) "T.")
      (eval '(model:define-node dangling-node (:area :blocks :categories (:nope))
              (x (:enum no-enum)) (y (:node :no-kind)) (z (:target :no-target))))
      (is = 5 (length (model:registry-problems))))))

(define-test define-node-filling
  :parent define-node
  ;; The builder makes a node by kind and fills its fields by name.
  (let* ((model:*registry* *test-registry*)
         (node (model:make-node :test-entry :id "a")))
    (is eq 'test-entry (type-of node))
    (setf (model:node-field-value node :names) '("a"))
    (push "b" (test-entry-names node))
    (is equal '("b" "a") (model:node-field-value node 'names))
    (is eq 'names (model:field-name (model:find-field :test-entry :names)))
    (is eq nil (model:find-field :test-entry :nothing))
    (fail (model:node-field-value node :nothing))
    (fail (model:make-node :no-such-kind))))

(define-test define-node-redefined
  :parent define-node
  ;; Declaring a kind again replaces its class and its declaration.
  (let ((model:*registry* (model:make-registry)))
    (eval '(model:define-node again-node (:area :blocks) (x :string)))
    (eval '(model:define-node again-node (:area :blocks) (x :string) (y :integer)))
    (is equal '(:again-node) (model:node-kinds))
    (is equal '(x y) (mapcar #'model:field-name (model:node-fields :again-node)))
    (is = 2 (funcall 'again-node-y (model:make-node :again-node :y 2)))))

(define-test define-node-values
  :parent define-node
  (let ((model:*registry* *test-registry*))
    (flet ((problems (&rest initargs)
             (length (model:node-problems (apply #'make-instance 'test-entry initargs)))))
      ;; Complete and well typed.
      (is = 0 (problems :id "x" :names '("x") :flavor :macro :count 2 :none t
                        :parts (list (make-instance 'test-entry :id "y" :names '("y")))
                        :text (list "a" (make-instance 'test-ref
                                                       :to (model:make-target :test-entry "x")))
                        :see nil))
      ;; Required fields missing: id, names.
      (is = 2 (problems))
      (is = 1 (problems :id "x" :names '()))
      ;; Wrong types.
      (is = 1 (problems :id 1 :names '("x")))
      (is = 1 (problems :id "x" :names '("x") :flavor :special))
      (is = 1 (problems :id "x" :names '("x") :count "2"))
      (is = 1 (problems :id "x" :names '("x") :none 1))
      (is = 1 (problems :id "x" :names "x"))
      (is = 1 (problems :id "x" :names '("x") :parts (list (make-instance 'test-ref))))
      (is = 1 (problems :id "x" :names '("x") :text (list 1)))
      (is = 1 (problems :id "x" :names '("x") :see (model:make-target :other "x")))
      ;; An unresolved reference is no problem, even when required.
      (is = 0 (length (model:node-problems (make-instance 'test-ref)))))))
