;;;; src/model/build-inlines.lisp
;;;;
;;;; The handlers that build semantic inlines and unresolved references
;;;; from their events (docs/model.md, "Inlines"): terms, parameters,
;;;; fonts by meaning, references to names, sections and figures with
;;;; their key text (3.17-3.19 resolve them), example notation,
;;;; citations, index entries and issues as anchors.
;;;; Owner: step 3.13 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/model)

(defparameter *reference-vias*
  '((:clref . :any) (:funref . :function) (:macref . :macro)
    (:specref . :special-operator) (:typeref . :type) (:varref . :variable)
    (:conref . :constant) (:declref . :declaration) (:packref . :package)
    (:kwd . :keyword) (:loopref . :loop-keyword)
    (:keyref . :lambda-list-keyword) (:ttref . :typewriter) (:misc . :misc))
  "The vocabulary key of each reference macro and the REFERENCE-KIND it
stands for.  A wrapper's event has the wrapper's key (\\kwd, \\misc), not
that of the macro it calls.")

(defparameter *index-kinds*
  '((:index-ref . :ref) (:index-keyref . :keyref) (:index-code . :code)
    (:index-keyword . :keyword) (:index-text . :text) (:index-term . :term)
    (:index-example . :example) (:index-package . :package))
  "The vocabulary key of each index macro and its INDEX-KIND.")

(defparameter *notation-keys*
  '(:evaluates-to :may-evaluate-to :does-not-evaluate-to :equivalent
    :output :this-section)
  "The keys whose node has no field: the arrows and signs of examples,
and `this section'.  What their macros typeset (math) is dropped.")

(defun trimmed-argument (builder event index)
  "The text of the INDEXth argument of EVENT, without the spaces around
it; the empty string when EVENT has none."
  (let ((argument (nth index (event-arguments event))))
    (if argument
        (string-trim '(#\Space #\Tab #\Newline) (argument-text builder argument))
        "")))

(defun last-argument-text (builder event)
  "The text of the last argument of EVENT, without the spaces around it."
  (trimmed-argument builder event (1- (max 1 (length (event-arguments event))))))

(defun open-node-container (builder key span kind &rest initargs)
  "Open a container of KEY at SPAN for a new node of KIND with INITARGS;
what the event's extent holds is dropped, as the node has no field for
it."
  (open-container builder key span
                  :node (apply #'make-builder-node builder kind :span span initargs)))

(defun open-content-container (builder key span kind)
  "Open a container of KEY at SPAN for a new node of KIND whose items
go to its :CONTENT field."
  (open-container builder key span
                  :node (make-builder-node builder kind :span span)
                  :field :content))

(defun finish-lambda-list-keyword (builder container)
  "Set the name of the :LAMBDA-LIST-KEYWORD node of CONTAINER to the
strings its macro typeset."
  (setf (node-field-value (container-node container) :name (builder-registry builder))
        (apply #'concatenate 'string
               (remove-if-not #'stringp (container-contents container)))))

(defun install-inline-handlers (table)
  "Register the handlers of step 3.13 in the handler table TABLE."
  (flet ((begin (key function)
           (register-handler :begin key function table)))
    ;; Terms and names by meaning.
    (dolist (key '(:term :new-term))
      (let ((key key))
        (begin key (lambda (builder event span)
                     (open-node-container builder key span :term-ref
                                          :text (trimmed-argument builder event 0)
                                          :defining (eq key :new-term))))))
    (begin :param (lambda (builder event span)
                    (open-node-container builder :param span :param
                                         :name (trimmed-argument builder event 0))))
    (begin :metavariable
           (lambda (builder event span)
             (open-node-container builder :metavariable span :metavariable
                                  :name (trimmed-argument builder event 0))))
    (begin :format-directive
           (lambda (builder event span)
             (open-node-container builder :format-directive span :format-directive
                                  :name (trimmed-argument builder event 0))))
    (begin :lambda-list-keyword
           (lambda (builder event span)
             (declare (ignore event))
             (open-container builder :lambda-list-keyword span
                             :node (make-builder-node builder :lambda-list-keyword
                                                      :span span)
                             :on-close #'finish-lambda-list-keyword)))
    ;; Fonts by meaning, citations and input: nodes with content.
    (dolist (entry '((:emphasis . :emphasis) (:strong . :strong)
                     (:inline-code . :code) (:cite . :citation) (:input . :input)))
      (destructuring-bind (key . kind) entry
        (begin key (lambda (builder event span)
                     (declare (ignore event))
                     (open-content-container builder key span kind)))))
    ;; References, unresolved.
    (loop for (key . via) in *reference-vias*
          do (let ((key key) (via via))
               (begin key (lambda (builder event span)
                            (open-node-container builder key span :operator-ref
                                                 :text (last-argument-text builder event)
                                                 :via via)))))
    (begin :secref (lambda (builder event span)
                     (open-node-container builder :secref span :section-ref
                                          :label (trimmed-argument builder event 0))))
    (begin :figref (lambda (builder event span)
                     (open-node-container builder :figref span :figure-ref
                                          :label (trimmed-argument builder event 0))))
    ;; Example notation and `this section'.
    (dolist (key *notation-keys*)
      (let ((key key))
        (begin key (lambda (builder event span)
                     (declare (ignore event))
                     (open-node-container builder key span key)))))
    ;; Index entries and issues: anchors, no containers.
    (loop for (key . kind) in *index-kinds*
          do (let ((kind kind))
               (register-handler :mark key
                                 (lambda (builder event span)
                                   (add-item builder
                                             (make-builder-node
                                              builder :index-entry :span span
                                              :index-kind kind
                                              :text (trimmed-argument builder event 0))))
                                 table)))
    (begin :issue (lambda (builder event span)
                    (add-item builder (make-builder-node
                                       builder :issue-start :span span
                                       :name (trimmed-argument builder event 0)))))
    (register-handler :end :issue
                      (lambda (builder event span)
                        (add-item builder (make-builder-node
                                           builder :issue-end :span span
                                           :name (trimmed-argument builder event 0))))
                      table))
  table)

(install-inline-handlers *handlers*)
