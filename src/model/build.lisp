;;;; src/model/build.lisp
;;;;
;;;; The builder core (docs/model.md, "Building"): a cursor over a job's
;;;; events, the handler table that DEFINE-HANDLER fills (one file per
;;;; area adds its handlers), the container stack the handlers open and
;;;; close, and the build report, where every event no handler takes and
;;;; every inconsistency goes.  BUILD-EVENTS builds a list of events;
;;;; BUILD-JOB, BUILD-MODEL and BUILD-FIXTURE run chapter jobs first.

(in-package #:cl-ansi-spec/model)

;;; Events (docs/events.md)

(defun event-head-length (event)
  "How many elements of EVENT come before its properties: two for
:BEGIN, :END and :MARK (the key) and :TEXT (the text), one otherwise."
  (if (member (first event) '(:begin :end :mark :text)) 2 1))

(defun event-type (event)
  "The type of EVENT, its first element: :BEGIN, :END, :MARK, :TEXT,
:GLUE, ..."
  (first event))

(defun event-key (event)
  "The key of a :BEGIN, :END or :MARK EVENT (:COM, :PARAGRAPH, ...); NIL
for an event of another type."
  (and (member (first event) '(:begin :end :mark)) (second event)))

(defun event-text (event)
  "The characters of a :TEXT EVENT, a string."
  (assert (eq (first event) :text) () "Not a :TEXT event: ~S" event)
  (second event))

(defun event-properties (event)
  "The property list of EVENT, its :SPAN included."
  (nthcdr (event-head-length event) event))

(defun event-property (event indicator &optional default)
  "The property INDICATOR of EVENT, or DEFAULT."
  (getf (event-properties event) indicator default))

(defun event-span (event)
  "Where EVENT came from: its :SPAN, or NIL."
  (event-property event :span))

(defun event-arguments (event)
  "The :ARGUMENTS of EVENT: one token list (or, in events the tests
make, one string) per argument."
  (event-property event :arguments))

;;; Spans

(defun join-spans (begin end)
  "The span of a container begun at BEGIN and ended at END: from BEGIN's
start to END's end when both lie in one file and END does not end
before BEGIN starts; BEGIN otherwise (END when BEGIN is NIL).  A
container ended inside a macro of the setup files keeps the span of its
beginning."
  (cond ((null begin) end)
        ((and end
              (equal (span-file begin) (span-file end))
              (>= (span-end end) (span-start begin)))
         (make-span (span-file begin) (span-start begin)
                    (max (span-end begin) (span-end end))
                    (span-line begin) (span-column begin)))
        (t begin)))

;;; The cursor

(defstruct (cursor (:constructor make-cursor
                       (events &aux (events (coerce events 'simple-vector)))))
  "A position in EVENTS, a job's events in order."
  (events #() :type simple-vector :read-only t)
  (position 0 :type (integer 0)))

(defun cursor-peek (cursor)
  "The event at CURSOR and its span, as two values, without moving; NIL
at the end."
  (let ((events (cursor-events cursor))
        (position (cursor-position cursor)))
    (if (< position (length events))
        (let ((event (svref events position)))
          (values event (event-span event)))
        (values nil nil))))

(defun cursor-next (cursor)
  "The event at CURSOR and its span, as two values, moving past it; NIL
at the end."
  (multiple-value-bind (event span) (cursor-peek cursor)
    (when event
      (incf (cursor-position cursor)))
    (values event span)))

;;; The build report

(defparameter *problem-kinds*
  '((:unhandled "An event no handler takes.")
    (:unmatched-end "An :END whose key no open container has, while
containers are open.")
    (:underflow "An :END whose key no open container has, while none is
open.")
    (:unclosed "A container still open when one below it, or the build,
ends; it is closed there.")
    (:node "A node that does not match its declaration (NODE-PROBLEMS)
when its container closes.")
    (:diagnostic "An unknown construct the expander met: a :DIAGNOSTIC
event or entry of the job's log.")
    (:tex-error "A TeX error the job recovered from.")
    (:fatal-error "A TeX error that stopped the job.")
    (:id-collision "Addressable nodes of one target kind that keep one id
after the collision rule (ASSIGN-IDS): each but the first, at its
span.")
    (:unresolved-term "A term reference no glossary entry matches by the
inflection rules (RESOLVE-TERMS), at its span.")
    (:ambiguous-term "A term reference two glossary entries match in one
tier of the rules, the first kept; or two glossary ids that differ only
by case.")
    (:missing-sense "A \\meaning sense the glossary entry of its term
reference does not number.")
    (:unresolved-reference "A section, figure or operator reference no
node of its kind has the label or name of (RESOLVE-SECTION-REFERENCES,
RESOLVE-OPERATOR-REFS), or a section or figure label several have.")
    (:ambiguous-reference "An operator reference whose name entries of
several kinds share, none of them the kind its wrapper prefers
(RESOLVE-OPERATOR-REFS)."))
  "The kinds of PROBLEM a build reports, each with its meaning.")

(defstruct (problem (:constructor make-problem
                        (kind span &key message event job)))
  "What a build reports: its KIND (one of *PROBLEM-KINDS*), the SPAN it
was met at (or NIL), a MESSAGE (a string, or NIL when the EVENT, the
event concerned, says it all) and the JOB it was met in."
  (kind nil :type keyword :read-only t)
  (span nil :read-only t)
  (message nil :type (or null string) :read-only t)
  (event nil :read-only t)
  (job nil :read-only t))

(defstruct (build-report (:constructor make-build-report (problems)))
  "The report of a build: its PROBLEMs, in the order they were met."
  (problems '() :type list :read-only t))

(defun merge-build-reports (reports)
  "One build report holding the problems of REPORTS, in order."
  (make-build-report (loop for report in reports
                           append (build-report-problems report))))

;;; The handler table

(defstruct (handler-table (:constructor make-handler-table ()))
  "The handlers of a build, by (event type, key): each a function of
the builder, the event and its span."
  (handlers (make-hash-table :test 'equal) :read-only t))

(defvar *handlers* (make-handler-table)
  "The handler table of the model, filled by the DEFINE-HANDLER forms of
src/model/build-*.lisp.  A build takes its table as an argument, so that
tests build with tables of their own.")

(defun find-handler (type key &optional (table *handlers*))
  "The handler of the events of TYPE and KEY (NIL for a type without
keys) in TABLE, or NIL."
  (values (gethash (list type key) (handler-table-handlers table))))

(defun handled-events (&optional (table *handlers*))
  "The (type key) pairs TABLE has a handler for, sorted."
  (sort (loop for pair being the hash-keys of (handler-table-handlers table)
              collect pair)
        #'string< :key (lambda (pair) (format nil "~{~S~^ ~}" pair))))

(defun register-handler (type key function table)
  "Make FUNCTION the handler of the events of TYPE and KEY in TABLE,
replacing the one before."
  (setf (gethash (list type key) (handler-table-handlers table)) function))

(defmacro define-handler ((type key &key (table '*handlers*))
                          (builder event span) &body body)
  "Define the handler of the events of TYPE (a keyword: :BEGIN, :TEXT,
...) and KEY (a keyword, the vocabulary or list key of a :BEGIN, :END
or :MARK event; NIL for other types) in the handler table TABLE holds.
BODY, which may start with a docstring and declarations, runs with
BUILDER, EVENT and SPAN (the event's span) bound.  An :END whose key has
a :BEGIN handler and no :END handler closes that key's container
(CLOSE-CONTAINER)."
  (unless (keywordp type)
    (error "A handler's event type is a keyword, not ~S." type))
  (unless (or (null key) (keywordp key))
    (error "A handler's key is a keyword or NIL, not ~S." key))
  (when (and key (not (member type '(:begin :end :mark))))
    (error "Events of type ~S have no key, not ~S." type key))
  `(register-handler ,type ,key
                     (lambda (,builder ,event ,span) ,@body)
                     ,table))

;;; Containers and the builder

(defstruct (container (:constructor make-container
                          (key span &key node field on-close ends-with-input
                                         groups-only)))
  "An open container: the KEY of the event that opened it and that
event's SPAN; the NODE it builds (or NIL: its items then go to the
container below); the FIELD of NODE that receives its items, in order,
when it closes (or NIL); ON-CLOSE, a function of the builder and the
container called then, before NODE is checked (or NIL), when END-SPAN
holds the span it is closed at (NIL at the end of the input); with
ENDS-WITH-INPUT true, the end of the input closes it quietly (a chapter
or section, which nothing but the next one ends); GROUPS-ONLY true for
a container without node, field or on-close that may stay open when a
container below it closes (CLOSE-UNDER-PASS-THROUGH); and ITEMS, the
nodes and strings added to it, newest first."
  (key nil :type symbol :read-only t)
  (span nil :read-only t)
  (node nil :read-only t)
  (field nil :type symbol :read-only t)
  (on-close nil :type (or null function) :read-only t)
  (ends-with-input nil :type boolean :read-only t)
  (groups-only nil :type boolean :read-only t)
  (end-span nil)
  (items '() :type list))

(defun container-contents (container)
  "The items added to CONTAINER, oldest first."
  (reverse (container-items container)))

(defun container-closing-span (container)
  "The span at which CONTAINER is being closed (its END-SPAN), or that of
its beginning at the end of the input: for an on-close function."
  (or (container-end-span container) (container-span container)))

(defstruct (builder (:constructor make-builder
                        (cursor registry handlers expander job)))
  "The state of one build: the CURSOR over its events, the REGISTRY of
the node kinds it makes, its HANDLERS (a HANDLER-TABLE), the EXPANDER
whose job made the events (NIL for events made otherwise), the name of
that JOB, the STACK of open containers (the bottom one, of key :ROOT,
receives the top-level nodes) and its PROBLEMS, newest first."
  (cursor nil :type cursor :read-only t)
  (registry nil :type registry :read-only t)
  (handlers nil :type handler-table :read-only t)
  (expander nil :read-only t)
  (job nil :read-only t)
  (stack (list (make-container :root nil)) :type list)
  (problems '() :type list))

(defun next-event (builder)
  "The next event of BUILDER's events and its span, consumed, as two
values; NIL at the end.  A handler calls it to take the events that
follow its own."
  (cursor-next (builder-cursor builder)))

(defun peek-event (builder)
  "The next event of BUILDER's events and its span, not consumed."
  (cursor-peek (builder-cursor builder)))

(defun events-ahead (builder count)
  "The next COUNT events of BUILDER, not consumed (fewer at the end)."
  (let* ((cursor (builder-cursor builder))
         (events (cursor-events cursor))
         (start (cursor-position cursor)))
    (coerce (subseq events (min start (length events)) (min (+ start count) (length events)))
            'list)))

(defun report-problem (builder kind span &key message event)
  "Add a problem of KIND (one of *PROBLEM-KINDS*) met at SPAN to
BUILDER's report."
  (unless (assoc kind *problem-kinds*)
    (error "Unknown problem kind ~S." kind))
  (push (make-problem kind span :message message :event event
                                :job (builder-job builder))
        (builder-problems builder)))

(defun argument-text (builder argument)
  "The text of ARGUMENT, a token list of an event's :ARGUMENTS, as TeX
shows it (TOKEN-LIST-TEXT); a string (in events made by tests) is its
own text."
  (if (stringp argument)
      argument
      (token-list-text (builder-expander builder) argument)))

(defun event-argument-texts (builder event)
  "The texts of EVENT's arguments (ARGUMENT-TEXT), in order."
  (mapcar (lambda (argument) (argument-text builder argument))
          (event-arguments event)))

(defun make-builder-node (builder kind &rest initargs)
  "A new node of the kind KIND of BUILDER's registry, with the INITARGS
of MAKE-NODE (:SPAN and the fields' keywords)."
  (let ((declaration (find-node-declaration kind (builder-registry builder))))
    (unless declaration
      (error "Unknown node kind ~S." kind))
    (apply #'make-instance (definition-name declaration) initargs)))

(defun current-container (builder)
  "The innermost open container of BUILDER (its root when none is
open)."
  (first (builder-stack builder)))

(defun find-container (builder key)
  "The innermost open container of BUILDER opened by KEY, or NIL."
  (find key (butlast (builder-stack builder)) :key #'container-key))

(defun add-item (builder item)
  "Add ITEM, a node or a string, to BUILDER's innermost container."
  (push item (container-items (current-container builder))))

(defun open-container (builder key span &key node field on-close ends-with-input
                                             groups-only)
  "Open a container of KEY begun at SPAN (MAKE-CONTAINER says what NODE,
FIELD, ON-CLOSE, ENDS-WITH-INPUT and GROUPS-ONLY are) and return it."
  (let ((container (make-container key span :node node :field field
                                            :on-close on-close
                                            :ends-with-input ends-with-input
                                            :groups-only groups-only)))
    (push container (builder-stack builder))
    container))

(defun finish-container (builder container end-span)
  "Close CONTAINER, the innermost, at END-SPAN: store its items in its
node's field, join the node's span with END-SPAN, call ON-CLOSE, check
the node and add it to the container below; without a node, its items
go to the container below."
  (pop (builder-stack builder))
  (setf (container-end-span container) end-span)
  (let ((node (container-node container))
        (registry (builder-registry builder)))
    (when node
      (when (container-field container)
        (setf (node-field-value node (container-field container) registry)
              (container-contents container)))
      (setf (node-span node)
            (join-spans (container-span container) end-span)))
    (when (container-on-close container)
      (funcall (container-on-close container) builder container))
    (cond (node
           (dolist (problem (node-problems node registry))
             (report-problem builder :node (node-span node) :message problem))
           (add-item builder node))
          (t
           (dolist (item (container-contents container))
             (add-item builder item))))))

(defun pass-through-p (container)
  "True when CONTAINER was opened to group only (OPEN-CONTAINER's
GROUPS-ONLY): no node, no field, no on-close, so that its items go to
the container below as they are (a box in a line of text)."
  (and (container-groups-only container)
       (not (or (container-node container) (container-field container)
                (container-on-close container)))))

(defun close-under-pass-through (builder target span)
  "Close TARGET at SPAN although containers that only group are open
above it (\\hbox{… \\rparen}, whose \\rparen closes what began outside
the box): their items so far go to TARGET, and they stay open, now
above TARGET's parent, for what they still hold."
  (let ((lifted '()))
    (loop until (eq (current-container builder) target)
          do (push (pop (builder-stack builder)) lifted))
    ;; LIFTED is outermost first: its items came first.
    (dolist (container lifted)
      (dolist (item (container-contents container))
        (push item (container-items target)))
      (setf (container-items container) '()))
    (finish-container builder target span)
    (dolist (container lifted)
      (push container (builder-stack builder)))))

(defun close-container (builder key span &optional event)
  "Close the innermost container of KEY at SPAN, where EVENT (when given)
ended it.  When only containers that group (PASS-THROUGH-P) are open
inside it, they stay open (CLOSE-UNDER-PASS-THROUGH); otherwise the
containers opened inside it and still open are closed first, each
reported :UNCLOSED.  With none of KEY open, the end is reported
(:UNDERFLOW when no container is open, :UNMATCHED-END otherwise) and
nothing is closed."
  (let ((target (find-container builder key)))
    (cond ((null target)
           (report-problem builder
                           (if (rest (builder-stack builder)) :unmatched-end :underflow)
                           span
                           :message (format nil "No ~S container is open." key)
                           :event event))
          ((and (not (eq target (current-container builder)))
                (every #'pass-through-p
                       (ldiff (builder-stack builder) (member target (builder-stack builder)))))
           (close-under-pass-through builder target span))
          (t
           (loop for container = (current-container builder)
                 until (eq container target)
                 do (report-problem builder :unclosed (container-span container)
                                    :message (format nil "~S, closed by the end of ~S."
                                                     (container-key container) key))
                    (finish-container builder container span))
           (finish-container builder target span)))))

(defun dispatch (builder event span)
  "Hand EVENT, at SPAN, to its handler in BUILDER's table; an :END with
no handler of its own closes its key's container when the key has a
:BEGIN handler; any other event without a handler is reported
:UNHANDLED."
  (let* ((type (event-type event))
         (key (event-key event))
         (table (builder-handlers builder))
         (handler (find-handler type key table)))
    (cond (handler (funcall handler builder event span))
          ((and (eq type :end) (find-handler :begin key table))
           (close-container builder key span event))
          (t (report-problem builder :unhandled span :event event)))))

(defun build-events (events &key (registry *registry*) (handlers *handlers*)
                                 expander job)
  "Build EVENTS (a job's events, in order; from EXPANDER's job JOB, which
shows their token lists) with the HANDLERS of the node kinds of
REGISTRY.  Return the top-level nodes and strings, and the build
report.  The containers still open at the end are closed, each reported
:UNCLOSED but those opened to end with the input (OPEN-CONTAINER)."
  (let ((builder (make-builder (make-cursor events) registry handlers expander job)))
    (loop (multiple-value-bind (event span) (next-event builder)
            (unless event (return))
            (dispatch builder event span)))
    (loop while (rest (builder-stack builder))
          do (let ((container (current-container builder)))
               (unless (container-ends-with-input container)
                 (report-problem builder :unclosed (container-span container)
                                 :message (format nil "~S, still open at the end."
                                                  (container-key container))))
               (finish-container builder container nil)))
    (values (container-contents (current-container builder))
            (make-build-report (reverse (builder-problems builder))))))

;;; The build's own handlers (src/model/owners.sexp)

(define-handler (:diagnostic nil) (builder event span)
  "A :DIAGNOSTIC event: an unknown construct, reported."
  (report-problem builder :diagnostic span :event event))

;;; Running chapter jobs

(defvar *plain-format* nil
  "Plain TeX's format, loaded once (LOAD-PLAIN-FORMAT): every job starts
from it.")

(defun plain-format ()
  "Plain TeX's format, loaded on first use."
  (or *plain-format* (setf *plain-format* (load-plain-format))))

(defstruct (job-run (:constructor make-job-run (job expander records)))
  "A chapter JOB run to its end by EXPANDER, with RECORDS, a vector of
what it output in order, each (FILE LINE . ITEM): the innermost file
being read then and its line (CURRENT-FILE-NAME, CURRENT-LINE-NUMBER;
FILE NIL when none was), and ITEM, a node appended to a list (a
composite node when it ends), a PROBLEM (a TeX error or a diagnostic) or
NIL (another entry of the job's log)."
  (job "" :type string :read-only t)
  (expander nil :read-only t)
  (records #() :type simple-vector :read-only t))

(defun run-job (job)
  "Run the chapter job JOB (a name, \"chap-14\") from plain TeX's
format, observing the spec's vocabulary, as `make events' does; return
its JOB-RUN."
  (let ((expander (make-job (plain-format) :job-name job))
        (records '()))
    (observe-vocabulary expander (spec-vocabulary))
    (start-job expander job)
    (flet ((record (item)
             (let ((input (expander-input expander)))
               (push (list* (current-file-name input) (current-line-number input) item)
                     records)))
           (tex-problem (kind condition)
             (make-problem kind (tex-error-span condition) :job job
                           :message (tex-error-message condition))))
      (handler-case
          (handler-bind ((job-output
                           (lambda (condition)
                             (let ((item (job-output-item condition)))
                               (record (cond ((not (log-entry-p item)) item)
                                             ((eq (log-entry-kind item) :diagnostic)
                                              (make-problem :diagnostic (log-entry-span item)
                                                            :job job
                                                            :message (log-entry-text item))))))))
                         (tex-report (lambda (condition) (declare (ignore condition)))))
            (call-recovering-tex-errors
             (lambda () (main-control expander))
             (lambda (condition) (record (tex-problem :tex-error condition)))))
        (tex-fatal-error (condition)
          (record (tex-problem :fatal-error condition)))))
    (make-job-run job expander (coerce (nreverse records) 'simple-vector))))

(defun run-problems (run &optional (records (job-run-records run)))
  "The problems among RECORDS of RUN, in order."
  (loop for (nil nil . item) across records
        when (problem-p item) collect item))

(defun build-run (run events problems registry handlers)
  "Build EVENTS of RUN with HANDLERS and REGISTRY; the report starts
with PROBLEMS, the job's own."
  (multiple-value-bind (nodes report)
      (build-events events :registry registry :handlers handlers
                           :expander (job-run-expander run) :job (job-run-job run))
    (values nodes (make-build-report (append problems (build-report-problems report))))))

(defun build-job (job &key (registry *registry*) (handlers *handlers*))
  "Run the chapter job JOB and build its events (BUILD-EVENTS); its TeX
errors and diagnostics open the report.  A third value is the job's
revision of the draft (JOB-VERSION)."
  (let ((run (run-job job)))
    (multiple-value-bind (nodes report)
        (build-run run (job-events (job-run-expander run)) (run-problems run)
                   registry handlers)
      (values nodes report (job-version (job-run-expander run))))))

(defun build-model (&key (jobs (chapter-jobs)) (registry *registry*) (handlers *handlers*))
  "Build the chapter jobs JOBS (names, \"chap-14\"; every one by default,
in the order of the standard) in turn (BUILD-JOB) and settle the ids of
their nodes (ASSIGN-IDS), then resolve their term, section and figure,
and operator references (RESOLVE-TERMS, RESOLVE-SECTION-REFERENCES,
OPERATOR-REF-PROBLEMS); return the top-level nodes of all of them, in
order, one report, the id collisions and the references' problems last,
and the revision of the draft the jobs give (the first one's)."
  (let* ((reports '()) (version nil)
         (nodes (loop for job in jobs
                      append (multiple-value-bind (nodes report job-version)
                                 (build-job job :registry registry :handlers handlers)
                               (push report reports)
                               (unless version (setf version job-version))
                               nodes))))
    (push (make-build-report (nth-value 1 (assign-ids nodes :registry registry))) reports)
    (push (make-build-report (resolve-terms nodes :registry registry)) reports)
    (push (make-build-report (resolve-section-references nodes :registry registry)) reports)
    (push (make-build-report (operator-ref-problems nodes :registry registry)) reports)
    (values nodes (merge-build-reports (nreverse reports)) version)))

;;; Fixtures: the model of a job's lines

(defvar *job-runs* (make-hash-table :test 'equal)
  "The JOB-RUNs BUILD-FIXTURE made, by job name: each job runs once per
session however many fixtures it holds.  FORGET-JOB-RUNS empties it.")

(defun forget-job-runs ()
  "Forget the job runs BUILD-FIXTURE keeps."
  (clrhash *job-runs*))

(defun memoised-run (job)
  "JOB's run, made on first use."
  (or (gethash job *job-runs*)
      (setf (gethash job *job-runs*) (run-job job))))

(defun records-in-lines (run file first last)
  "The records of RUN output while the reader was at the lines FIRST to
LAST (NIL: to the end) of FILE, the innermost file it was reading."
  (remove-if-not (lambda (record)
                   (destructuring-bind (record-file line . item) record
                     (declare (ignore item))
                     (and (equal record-file file)
                          (<= first line)
                          (or (null last) (<= line last)))))
                 (job-run-records run)))

(defun selected-events (nodes shown)
  "The events of the nodes of the list NODES that SHOWN (a table) holds,
whole, and of those inside the composite ones it does not hold, in
order."
  (loop for node in nodes
        append (cond ((gethash node shown) (flatten-nodes (list node)))
                     ((node-composite node) (selected-events (node-children node) shown)))))

(defun build-fixture (job &key (file (format nil "~A.tex" job)) (lines '(1 nil))
                               (registry *registry*) (handlers *handlers*))
  "Build the events of the nodes JOB appended while the reader was at
LINES, (FIRST LAST) with LAST NIL for no bound, of FILE (a spec file
name with its type, \"dict-conses.tex\"; by default the job's own),
the innermost file it was reading: a composite node appended then
whole, and of one appended later the nodes inside it appended then.
Unlike `make events', which locates a node by its span, this places a
node made by a macro of the setup files (a vocabulary entry's marker)
at the line its call was read from.  The job runs once per session
(*JOB-RUNS*).  Return the nodes and the report, which starts
with the job's TeX errors and diagnostics met within LINES."
  (destructuring-bind (first &optional last) lines
    (let* ((run (memoised-run job))
           (records (records-in-lines run file first last))
           (shown (make-hash-table :test 'eq)))
      (loop for (nil nil . item) across records
            when (and item (not (problem-p item)))
              do (setf (gethash item shown) t))
      (build-run run
                 (selected-events (list-nodes (outer-list (job-run-expander run))) shown)
                 (run-problems run records)
                 registry handlers))))
