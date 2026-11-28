;;;; tests/model/build.lisp
;;;;
;;;; The builder core (src/model/build.lisp) and the node printer
;;;; (src/model/print.lisp), with node kinds and handlers declared here,
;;;; in a registry and a handler table of their own: on events made here,
;;;; and on the real lines of dict-conses.tex (BUILD-FIXTURE).
;;;; Owner: step 3.3.

(in-package #:cl-ansi-spec/tests)

(define-test build
  :parent model
  :description "The builder core and the node printer.")

;;; Node kinds and handlers of the tests

(defvar *build-registry* (model:make-registry)
  "The node kinds of the builder's tests.")

(defvar *build-handlers* (model:make-handler-table)
  "The handlers of the builder's tests.")

(model:define-category :inline (:area :inlines :registry *build-registry*)
  "An inline of the builder's tests.")

(model:define-node build-test-term (:area :inlines :categories (:inline)
                                    :registry *build-registry*)
  "A term."
  (text :string :required t))

(model:define-node build-test-paragraph (:area :blocks :registry *build-registry*)
  "A paragraph."
  (content :inlines))

(model:define-node build-test-entry (:area :entries :registry *build-registry*)
  "An entry: its name and its paragraphs."
  (name :string :required t)
  (paragraphs (:node :build-test-paragraph) :repeated t))

(model:define-handler (:begin :com :table *build-handlers*) (builder event span)
  "An entry, named by its first argument; its paragraphs fill it."
  (model:open-container
   builder :com span
   :node (model:make-builder-node
          builder :build-test-entry
          :name (first (model:event-argument-texts builder event)))
   :field 'paragraphs))

(model:define-handler (:begin :paragraph :table *build-handlers*) (builder event span)
  "A paragraph; texts and terms fill it."
  (declare (ignore event))
  (model:open-container
   builder :paragraph span
   :node (model:make-builder-node builder :build-test-paragraph)
   :field 'content))

(defun add-inline (builder inline event span)
  "Add INLINE, made from EVENT at SPAN, to the paragraph open in BUILDER;
report EVENT unhandled outside paragraphs."
  (if (eq (model:container-key (model:current-container builder)) :paragraph)
      (model:add-item builder inline)
      (model:report-problem builder :unhandled span :event event)))

(model:define-handler (:text nil :table *build-handlers*) (builder event span)
  "A text in a paragraph: its characters."
  (add-inline builder (model:event-text event) event span))

(model:define-handler (:mark :term :table *build-handlers*) (builder event span)
  "A term in a paragraph, named by its argument."
  (add-inline builder
              (model:make-builder-node builder :build-test-term :span span
                                       :text (first (model:event-argument-texts builder event)))
              event span))

;;; Events of the tests

(defun test-span (line start end &optional (file "test.tex"))
  "A span of FILE from START to END, at LINE, column 0."
  (make-span file start end line 0))

(defun test-event (type head &rest properties &key (span (test-span 1 0 1))
                                              &allow-other-keys)
  "An event of TYPE: HEAD (its key or text, or NIL for none), then
PROPERTIES and SPAN."
  (append (list type) (and head (list head))
          (loop for (key value) on properties by #'cddr
                unless (eq key :span) append (list key value))
          (list :span span)))

(defun build-test-events (&rest events)
  "Build EVENTS with the tests' handlers and node kinds."
  (model:build-events events :registry *build-registry* :handlers *build-handlers*))

(defun problem-kinds (report)
  "The kinds of REPORT's problems, in order."
  (mapcar #'model:problem-kind (model:build-report-problems report)))

;;; Events and spans

(define-test build-events-accessors
  :parent build
  (let ((span (test-span 3 10 20)))
    (let ((event (test-event :begin :com :arguments '("endp" "Function") :span span)))
      (is eq :begin (model:event-type event))
      (is eq :com (model:event-key event))
      (is equal '("endp" "Function") (model:event-arguments event))
      (is eq span (model:event-span event)))
    (let ((event (test-event :text "endp" :style "cmr10" :span span)))
      (is eq nil (model:event-key event))
      (is string= "endp" (model:event-text event))
      (is equal "cmr10" (model:event-property event :style))
      (is equal (list :style "cmr10" :span span) (model:event-properties event)))
    (let ((event (test-event :glue nil :glue "1.0pt" :span span)))
      (is eq :glue (model:event-type event))
      (is eq nil (model:event-key event))
      (is equal "1.0pt" (model:event-property event :glue)))))

(define-test build-join-spans
  :parent build
  (let ((begin (test-span 3 10 20))
        (end (test-span 9 90 95))
        (elsewhere (test-span 9 90 95 "setup-aux.tex")))
    (let ((joined (model:join-spans begin end)))
      (is equal '("test.tex" 10 95 3 0) (model:span-sexp joined)))
    (is eq begin (model:join-spans begin elsewhere))
    (is eq begin (model:join-spans begin nil))
    (is eq end (model:join-spans nil end))
    (is eq begin (model:join-spans begin (test-span 1 0 5)))
    (is equal '("test.tex" 10 20 3 0) (model:span-sexp (model:join-spans begin (test-span 3 12 15))))))

(define-test build-cursor
  :parent build
  (let* ((first (test-event :space nil :span (test-span 1 0 1)))
         (second (test-event :space nil :span (test-span 2 5 6)))
         (cursor (model:make-cursor (list first second))))
    (is eq first (model:cursor-peek cursor))
    (is eq first (model:cursor-peek cursor))
    (multiple-value-bind (event span) (model:cursor-next cursor)
      (is eq first event)
      (is eq (model:event-span first) span))
    (is eq second (model:cursor-next cursor))
    (is eq nil (model:cursor-next cursor))
    (is eq nil (model:cursor-peek cursor))))

(define-test build-define-handler
  :parent build
  (fail (macroexpand-1 '(model:define-handler ("begin" :com) (b e s))))
  (fail (macroexpand-1 '(model:define-handler (:begin "com") (b e s))))
  (fail (macroexpand-1 '(model:define-handler (:text :com) (b e s))))
  (let ((table (model:make-handler-table)))
    (model:define-handler (:space nil :table table) (builder event span)
      (declare (ignore builder event span))
      :first)
    (model:define-handler (:space nil :table table) (builder event span)
      (declare (ignore builder event span))
      :second)
    (is equal '((:space nil)) (model:handled-events table))
    (is eq :second (funcall (model:find-handler :space nil table) nil nil nil))
    (is eq nil (model:find-handler :text nil table))))

;;; Building

(define-test build-nested
  :parent build
  (multiple-value-bind (nodes report)
      (build-test-events
       (test-event :begin :com :arguments '("endp" "Function") :span (test-span 1 0 8))
       (test-event :begin :paragraph :span (test-span 2 10 11))
       (test-event :text "Is " :span (test-span 2 10 13))
       (test-event :mark :term :arguments '("true") :span (test-span 2 13 23))
       (test-event :end :paragraph :span (test-span 2 23 24))
       (test-event :begin :paragraph :span (test-span 3 30 31))
       (test-event :end :paragraph :span (test-span 3 31 32))
       (test-event :end :com :span (test-span 4 40 47)))
    (is equal '() (model:build-report-problems report))
    (is = 1 (length nodes))
    (let ((entry (first nodes)))
      (is equal '(:build-test-entry
                  :name "endp"
                  :paragraphs ((:build-test-paragraph
                                :content ("Is " (:build-test-term :text "true"
                                                 :span ("test.tex" 13 23 2 0)))
                                :span ("test.tex" 10 24 2 0))
                               (:build-test-paragraph :span ("test.tex" 30 32 3 0)))
                  :span ("test.tex" 0 47 1 0))
          (model:node-sexp entry :registry *build-registry*))
      (is equal '(:build-test-entry
                  :name "endp"
                  :paragraphs ((:build-test-paragraph :content ("Is " (:build-test-term :text "true")))
                               (:build-test-paragraph)))
          (model:node-sexp entry :registry *build-registry* :spans nil))
      (is equal '("test.tex" 1)
          (getf (rest (model:node-sexp entry :registry *build-registry* :spans :line)) :span))
      (is string= (format nil "(:build-test-entry :name \"endp\" ~
                               :paragraphs ((:build-test-paragraph) (:build-test-paragraph)))~%")
          (with-output-to-string (out)
            (model:print-node (make-instance 'build-test-entry
                                             :name "endp"
                                             :paragraphs (list (make-instance 'build-test-paragraph)
                                                               (make-instance 'build-test-paragraph)))
                              :stream out :registry *build-registry* :spans nil))))))

(define-test build-top-level-and-unhandled
  :parent build
  (let ((glue (test-event :glue nil :glue "1.0pt" :span (test-span 5 50 51)))
        (table (model:make-handler-table)))
    (model:define-handler (:text nil :table table) (builder event span)
      (declare (ignore span))
      (model:add-item builder (model:event-text event)))
    (multiple-value-bind (nodes report)
        (model:build-events (list (test-event :text "loose") glue)
                            :registry *build-registry* :handlers table)
      (is equal '("loose") nodes)
      (is equal '(:unhandled) (problem-kinds report))
      (let ((problem (first (model:build-report-problems report))))
        (is eq glue (model:problem-event problem))
        (is eq (model:event-span glue) (model:problem-span problem))))))

(define-test build-mismatched-ends
  :parent build
  ;; An entry ended inside its paragraph: the paragraph is closed first.
  (multiple-value-bind (nodes report)
      (build-test-events
       (test-event :begin :com :arguments '("a"))
       (test-event :begin :paragraph)
       (test-event :text "x")
       (test-event :end :com))
    (is equal '(:unclosed) (problem-kinds report))
    (is equal '((:build-test-entry :name "a"
                 :paragraphs ((:build-test-paragraph :content ("x")))))
        (mapcar (lambda (node) (model:node-sexp node :registry *build-registry* :spans nil))
                nodes)))
  ;; An end with nothing open, then with only another key open.
  (multiple-value-bind (nodes report)
      (build-test-events
       (test-event :end :paragraph)
       (test-event :begin :com :arguments '("a"))
       (test-event :end :paragraph)
       (test-event :end :com))
    (is equal '(:underflow :unmatched-end) (problem-kinds report))
    (is = 1 (length nodes)))
  ;; An end whose key has no handler at all is unhandled.
  (multiple-value-bind (nodes report) (build-test-events (test-event :end :term))
    (is equal '() nodes)
    (is equal '(:unhandled) (problem-kinds report))))

(define-test build-unclosed-at-end
  :parent build
  (multiple-value-bind (nodes report)
      (build-test-events
       (test-event :begin :com :arguments '("a") :span (test-span 1 0 5))
       (test-event :begin :paragraph :span (test-span 2 6 7)))
    (is equal '(:unclosed :unclosed) (problem-kinds report))
    ;; Innermost first, each at its beginning.
    (is equal '(2 1)
        (mapcar (lambda (problem) (span-line (model:problem-span problem)))
                (model:build-report-problems report)))
    (is equal '((:build-test-entry :name "a" :paragraphs ((:build-test-paragraph))))
        (mapcar (lambda (node) (model:node-sexp node :registry *build-registry* :spans nil))
                nodes))))

(define-test build-node-problems
  :parent build
  ;; An entry without arguments has no name: checked when it closes.
  (multiple-value-bind (nodes report)
      (build-test-events (test-event :begin :com) (test-event :end :com))
    (is = 1 (length nodes))
    (is equal '(:node) (problem-kinds report))
    (true (search "name" (model:problem-message
                          (first (model:build-report-problems report)))))))

(define-test build-diagnostic
  :parent build
  (let ((event (test-event :diagnostic nil :message "unknown")))
    (multiple-value-bind (nodes report) (model:build-events (list event))
      (is equal '() nodes)
      (is equal '(:diagnostic) (problem-kinds report))
      (is eq event (model:problem-event (first (model:build-report-problems report)))))))

(define-test build-report-merging
  :parent build
  (let ((a (model:make-problem :unhandled nil))
        (b (model:make-problem :tex-error nil :message "x")))
    (is equal (list a b)
        (model:build-report-problems
         (model:merge-build-reports (list (model:make-build-report (list a))
                                          (model:make-build-report '())
                                          (model:make-build-report (list b))))))))

;;; The real lines

(defun endp-fixture (&optional (lines '(1702 1759)))
  "The nodes and report of dict-conses.tex's LINES, built with the tests'
handlers."
  (model:build-fixture "chap-14" :file "dict-conses.tex" :lines lines
                                 :registry *build-registry* :handlers *build-handlers*))

(defun paragraph-text (entry)
  "The strings of ENTRY's paragraphs, concatenated."
  (format nil "~{~A~}"
          (loop for paragraph in (build-test-entry-paragraphs entry)
                append (remove-if-not #'stringp (build-test-paragraph-content paragraph)))))

(define-test build-fixture-endp
  :parent build
  (multiple-value-bind (nodes report) (endp-fixture)
    (let ((entries (remove-if-not (lambda (node) (typep node 'build-test-entry)) nodes)))
      (is = 1 (length entries))
      (let ((entry (first entries)))
        (is string= "endp" (build-test-entry-name entry))
        ;; Its paragraphs come from the entry's lines; the entry's own span
        ;; is that of \begincom's call of the vocabulary entry
        ;; \dobegincom, in setup-aux.tex.
        (is equal '("dict-conses.tex" 1702)
            (model:span-sexp (model:node-span (first (build-test-entry-paragraphs entry)))
                             :line))
        (true (search "Returns" (paragraph-text entry)))
        (true (search "dotted" (paragraph-text entry)))))
    ;; The entry ends within the lines, and nothing is dropped: what the
    ;; tests' handlers do not take is in the report.
    (is eq nil (find :unclosed (problem-kinds report)))
    (true (find :unhandled (problem-kinds report)))
    (is equal '() (remove :unhandled (problem-kinds report))))
  ;; The same lines build the same model, from the job run once.
  (is equal (mapcar (lambda (node) (model:node-sexp node :registry *build-registry*))
                    (remove-if #'stringp (endp-fixture)))
      (mapcar (lambda (node) (model:node-sexp node :registry *build-registry*))
              (remove-if #'stringp (endp-fixture))))
  ;; Lines that end inside the entry leave it open.
  (multiple-value-bind (nodes report) (endp-fixture '(1702 1706))
    (is equal '("endp")
        (mapcar #'build-test-entry-name
                (remove-if-not (lambda (node) (typep node 'build-test-entry)) nodes)))
    (true (find :unclosed (problem-kinds report)))))

(define-test build-model-job
  :parent build
  ;; One job built whole: one entry per \begincom of dict-conses.tex (49).
  (multiple-value-bind (nodes report)
      (model:build-model :jobs '("chap-14") :registry *build-registry*
                         :handlers *build-handlers*)
    (is = 49 (count-if (lambda (node) (typep node 'build-test-entry)) nodes))
    ;; Two entries end inside their last paragraph (\endcom on the line
    ;; after it): the paragraph is closed with the entry, and its end
    ;; then closes nothing.
    (is equal '((:unclosed 201) (:underflow 129) (:unclosed 4021) (:underflow 129))
        (loop for problem in (model:build-report-problems report)
              unless (eq (model:problem-kind problem) :unhandled)
                collect (list (model:problem-kind problem)
                              (span-line (model:problem-span problem)))))))
