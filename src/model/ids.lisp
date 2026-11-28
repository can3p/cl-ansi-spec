;;;; src/model/ids.lisp
;;;;
;;;; Ids of addressable nodes, with the collision rule (docs/exports.md,
;;;; "JSON shape"): each builder gives its nodes the id the sources name
;;;; them by; ASSIGN-IDS, run over the whole model, settles the dictionary
;;;; entries that share a first name and reports the ids that are still
;;;; not unique among the nodes of their target kind.
;;;; Owner: step 3.16 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/model)

(defun walk-nodes (function items &optional (registry *registry*))
  "Call FUNCTION on every node of ITEMS (nodes and strings) and of their
fields, at any depth, each before the nodes inside it, in document order."
  (labels ((walk (value)
             (typecase value
               (node (funcall function value)
                     (dolist (field (node-fields (node-kind value) registry))
                       (walk (node-field-value value field registry))))
               (cons (mapc #'walk value)))))
    (walk items)
    (values)))

(defun ids-by-target-kind (items registry)
  "The addressable nodes of ITEMS by target kind: an alist (target-kind
. nodes), the nodes in document order."
  (let ((kinds (mapcar (lambda (declaration)
                         (cons (target-kind-node declaration) (definition-name declaration)))
                       (target-kinds registry)))
        (table '()))
    (walk-nodes (lambda (node)
                  (let ((kind (cdr (assoc (node-kind node) kinds))))
                    (when kind
                      (let ((cell (assoc kind table)))
                        (if cell
                            (push node (cdr cell))
                            (push (list kind node) table))))))
                items registry)
    (mapcar (lambda (cell) (cons (car cell) (reverse (cdr cell)))) (nreverse table))))

(defun group-by-id (nodes registry)
  "NODES grouped by their :ID, as lists of the nodes sharing one, in the
order of their first node."
  (let ((groups '()))
    (dolist (node nodes)
      (let* ((id (node-field-value node :id registry))
             (group (assoc id groups :test #'equal)))
        (if group
            (push node (cdr group))
            (push (list id node) groups))))
    (mapcar (lambda (group) (reverse (cdr group))) (nreverse groups))))

(defun entry-collision-id (entry registry)
  "The id of a dictionary ENTRY whose first name another entry shares:
<name>/<entry-kind>, the kind as the enum names it (the \\ftype text in
kebab-case)."
  (format nil "~A/~(~A~)" (node-field-value entry :id registry)
          (node-field-value entry :entry-kind registry)))

(defun assign-ids (items &key (registry *registry*))
  "Settle the ids of the nodes of ITEMS, a built model: the dictionary
entries that share a first name get <name>/<entry-kind>.  Every id must
then be unique among the nodes of its target kind: each node that
repeats an id is an :ID-COLLISION problem.  Return the ids the rule gave,
in document order, and those problems."
  (let ((by-kind (ids-by-target-kind items registry)) (renamed '()) (problems '()))
    (dolist (group (group-by-id (cdr (assoc :entry by-kind)) registry))
      (when (rest group)
        ;; An entry without a kind (reported by its builder) keeps its
        ;; id, so that its collision is reported below.
        (dolist (entry (remove-if-not (lambda (entry)
                                        (node-field-value entry :entry-kind registry))
                                      group))
          (let ((id (entry-collision-id entry registry)))
            (setf (node-field-value entry :id registry) id)
            (push id renamed)))))
    (loop for (kind . nodes) in by-kind
          do (dolist (group (group-by-id nodes registry))
               (let ((first (first group)))
                 (dolist (node (rest group))
                   (push (make-problem :id-collision (node-span node)
                                       :message (format nil "The ~(~A~) id ~S is also that of the node at ~A."
                                                        kind (node-field-value node :id registry)
                                                        (let ((span (node-span first)))
                                                          (if span
                                                              (format nil "~A:~D" (span-file span) (span-line span))
                                                              "-"))))
                         problems)))))
    (values (nreverse renamed) (nreverse problems))))
