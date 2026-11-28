;;;; src/model/build-entries.lisp
;;;;
;;;; The handlers that build dictionary entries, their parts and signatures
;;;; from their events (docs/model.md, "Entries").

(in-package #:cl-ansi-spec/model)

;;; Reading events

(defun skip-balanced (builder)
  "Consume the events of BUILDER up to and including the :END that closes
the :BEGIN consumed before the call.  Return the events skipped, the :END
last, or NIL when the events run out first."
  (let ((depth 0) (skipped '()))
    (loop
      (let ((event (next-event builder)))
        (unless event
          (return nil))
        (push event skipped)
        (case (event-type event)
          (:begin (incf depth))
          (:end (if (zerop depth)
                    (return (nreverse skipped))
                    (decf depth))))))))

(defun vocabulary-keys ()
  "Every vocabulary key of the ownership table."
  (loop for owner in (owners) append (owner-vocabulary owner)))

(defun skip-presentation (builder what span)
  "Consume the balanced events of a presentational list opened by the
:BEGIN just consumed (the heading of an entry, the box of a label).  What
it held is dropped; an event with a meaning of its own (a vocabulary key)
is reported, since dropping it would lose it.  WHAT names the list in the
report."
  (let ((keys (vocabulary-keys)))
    (dolist (event (skip-balanced builder))
      (when (and (member (event-type event) '(:begin :mark))
                 (member (event-key event) keys))
        (report-problem builder :node (or (event-span event) span)
                               :message (format nil "~A holds ~S, dropped with it."
                                                what (event-key event))
                               :event event)))))

(defun trim-text (text)
  "TEXT without the whitespace around it."
  (string-trim '(#\Space #\Tab #\Newline #\Return) text))

(defun argument-trimmed (builder event n)
  "The text of EVENT's Nth argument (from 0), trimmed; \"\" when absent."
  (let ((argument (nth n (event-arguments event))))
    (if argument (trim-text (argument-text builder argument)) "")))

;;; Names and kinds

(defun entries-name-text (text)
  "TEXT, a name as a signature's argument spells it, without the math
shifts and grouping braces TeX reads in it: {\\tt $-$} and string$=$
name - and string=."
  (remove-if (lambda (char) (member char '(#\$ #\{ #\}))) text))

(defun split-names (text)
  "The names of TEXT, a comma-separated list, trimmed, without empty ones."
  (loop with start = 0
        for comma = (position #\, text :start start)
        for name = (trim-text (subseq text start comma))
        unless (string= name "") collect name
        while comma
        do (setf start (1+ comma))))

(defun entry-kind-keyword (text)
  "The keyword of an \\ftype TEXT: its words in kebab-case, \"System
Class\" -> :SYSTEM-CLASS."
  (let ((words (loop with text = (substitute #\Space #\Newline text)
                     with start = 0
                     for end = (position #\Space text :start start)
                     for word = (subseq text start end)
                     unless (string= word "") collect (string-downcase word)
                     while end
                     do (setf start (1+ end)))))
    (intern (string-upcase (format nil "~{~A~^-~}" words)) :keyword)))

;;; Items

(defun trim-items (items)
  "ITEMS (strings and nodes) without whitespace at either end; a string
that is all whitespace goes."
  (let ((items (copy-list items)))
    (loop while (and items (stringp (first items))
                     (string= (setf (first items) (string-left-trim " " (first items))) ""))
          do (pop items))
    (when (and items (stringp (first items)))
      (setf (first items) (string-left-trim " " (first items))))
    (setf items (nreverse items))
    (loop while (and items (stringp (first items))
                     (string= (setf (first items) (string-right-trim " " (first items))) ""))
          do (pop items))
    (nreverse items)))

(defun strip-prefix (items prefix)
  "ITEMS without PREFIX, a string their first string starts with, and
the whitespace after it; a second value, true, when ITEMS did not start
so (ITEMS then come back as they are)."
  (let ((first (first (trim-items items))))
    (if (and (stringp first) (>= (length first) (length prefix))
             (string= prefix first :end2 (length prefix))
             ;; The prefix is a whole word: "car" does not start "cardinal".
             (or (= (length first) (length prefix))
                 (member (char first (length prefix)) '(#\Space #\( #\)))))
        (values (trim-items (cons (subseq first (length prefix)) (rest (trim-items items))))
                nil)
        (values items t))))

(defun split-at-close-paren (items)
  "Split ITEMS at the first parenthesis that closes more than it opened
in the strings: two values, the items before it and those after it."
  (let ((depth 0) (before '()))
    (loop for rest on items
          for item = (first rest)
          do (when (stringp item)
               (loop for char across item
                     for index from 0
                     do (case char
                          (#\( (incf depth))
                          (#\) (when (minusp (decf depth))
                                 (return-from split-at-close-paren
                                   (values (nreverse (if (zerop index)
                                                         before
                                                         (cons (subseq item 0 index) before)))
                                           (cons (subseq item (1+ index)) (rest rest)))))))))
             (push item before))
    (values (nreverse before) nil)))

(defun strip-final-paren (items)
  "ITEMS without the \")\" that ends them, and a second value, true, when
they did not end in one."
  (let* ((items (trim-items items)) (last (car (last items))))
    (if (and (stringp last) (plusp (length last))
             (char= (char last (1- (length last))) #\)))
        (values (trim-items (append (butlast items)
                                    (list (subseq last 0 (1- (length last))))))
                nil)
        (values items t))))

(defun operator-keys ()
  "The keys of the signatures of one operator."
  '(:defun :defun-no-return :defmac :defmac-no-return :defspec
    :defspec-no-return :defgen :defmeth))

;;; Reporting and adding nodes

(defun add-built-node (builder node end-span)
  "Check NODE against its declaration (problems go to the report), join
its span with END-SPAN and add it to BUILDER's innermost container."
  (setf (node-span node) (join-spans (node-span node) end-span))
  (dolist (problem (node-problems node (builder-registry builder)))
    (report-problem builder :node (node-span node) :message problem))
  (add-item builder node))

(defun report-shape (builder span control &rest arguments)
  "Report, as a :NODE problem at SPAN, that the events do not have the
shape the entry's rules expect."
  (report-problem builder :node span :message (apply #'format nil control arguments)))

;;; Entries and their parts

(defun close-entry (builder container)
  "CONTAINER's items: the parts fill the entry's :PARTS, what stands
before the first part its :CONTENT (the node's check reports what that
cannot hold); a string or node after a part has no place, reported."
  (let ((node (container-node container)) (parts '()) (content '()))
    (dolist (item (container-contents container))
      (cond ((and (typep item 'node) (eq (node-kind item) :part))
             (push item parts))
            ((null parts) (push item content))
            (t (report-shape builder (node-span node)
                             "~S stands in the entry ~A after a part, dropped."
                             (if (stringp item) item (node-kind item))
                             (dictionary-entry-id node)))))
    (let ((registry (builder-registry builder)))
      (setf (node-field-value node 'content registry) (nreverse content)
            (node-field-value node 'parts registry) (nreverse parts)))))

(defun skip-heading (builder)
  "The events of an entry's heading, set by \\dobegincom from its
arguments, are dropped: those before the entry's first paragraph are
handled as usual, then the paragraph is skipped."
  (loop
    (multiple-value-bind (event span) (peek-event builder)
      (cond ((null event) (return))
            ((and (eq (event-type event) :begin) (eq (event-key event) :paragraph))
             (next-event builder)
             (skip-presentation builder "The heading of an entry" span)
             (return))
            ((or (and (eq (event-type event) :mark) (eq (event-key event) :label))
                 (and (member (event-type event) '(:begin :end))
                      (member (event-key event) (list* :com (operator-keys)))))
             (return))
            (t (next-event builder)
               (dispatch builder event span))))))

(defun close-part (builder span)
  "Close the part open in BUILDER, if any."
  (when (find-container builder :label)
    (close-container builder :label span)))

(defun inner-container-open-p (builder)
  "True when a container of another handler is open inside the entry's
part: the innermost is neither a part nor the entry."
  (not (member (container-key (current-container builder)) '(:label :com :root))))

(defun drain-inner-containers (builder)
  "An entry may end inside the paragraph that holds its last words
(dict-conses.tex:201), so that its :END arrives before the paragraph's.
Take the events that follow as usual while a container of another
handler is open, so that it closes where TeX closed it; stop where a
new paragraph, entry or part begins, or an :END that closes nothing here."
  (loop while (inner-container-open-p builder)
        do (multiple-value-bind (event span) (peek-event builder)
             (when (or (null event)
                       (and (eq (event-type event) :begin)
                            (member (event-key event) '(:paragraph :com)))
                       (and (eq (event-type event) :mark) (eq (event-key event) :label))
                       (and (eq (event-type event) :end)
                            (not (find-container builder (event-key event)))))
               (return))
             (next-event builder)
             (dispatch builder event span))))

;;; Signatures

(defun leave-paragraph (builder span)
  "A signature is set in a paragraph of its own, which the part's blocks
do not need: when the innermost container is a paragraph, close it and
return true; it is dropped when empty, and built where it stands when it
holds something before the signature.  Callers then drop the paragraph's end with
SWALLOW-PARAGRAPH-END."
  (when (eq (container-key (current-container builder)) :paragraph)
    (let ((paragraph (current-container builder)))
      (if (container-items paragraph)
          (finish-container builder paragraph span)
          (pop (builder-stack builder)))
      t)))

(defun swallow-paragraph-end (builder)
  "Take the events up to and including the :END of the paragraph a
signature left (LEAVE-PARAGRAPH): the presentational ones as usual, and
the marks after the signature (an index entry) into the part.  Anything
else means the paragraph held more than the signature, which is
reported; the paragraph's end then reports itself."
  (loop
    (multiple-value-bind (event span) (peek-event builder)
      (cond ((null event) (return))
            ((and (eq (event-type event) :end) (eq (event-key event) :paragraph))
             (next-event builder)
             (return))
            ((member (event-type event) '(:glue :penalty :kern :rule :space :mark :indent))
             (next-event builder)
             (dispatch builder event span))
            (t (report-shape builder span "The paragraph of a signature holds more than the signature.")
               (return))))))

(defun skip-label-heading (builder)
  "The label's heading is typeset in a box, after the glue and penalties
that space it; the box is dropped, since the part's title replaces it."
  (loop
    (multiple-value-bind (event span) (peek-event builder)
      (cond ((null event) (return))
            ((member (event-type event) '(:glue :penalty :kern :rule :indent))
             (next-event builder)
             (dispatch builder event span))
            ((and (eq (event-type event) :begin) (eq (event-key event) :box))
             (next-event builder)
             (skip-presentation builder "The heading of a part" span)
             (return))
            (t (return))))))

(defun dispatch-in-signature (builder event span)
  "Hand EVENT to its handler inside a signature.  A box (the stacked
keyword parameters of make-array, \\vtop of \\hbox es) starts a new word:
a space goes before it."
  (when (and (eq (event-type event) :begin) (eq (event-key event) :box))
    (let ((last (first (container-items (current-container builder)))))
      (when (and last (not (and (stringp last)
                                (char= (char last (1- (length last))) #\Space))))
        (add-item builder " "))))
  (dispatch builder event span))

(defun read-signature (builder key span)
  "Consume the events of the signature of KEY just begun, up to its :END,
taking them as usual into a container of their own; the first
:EVALUATES-TO among them (the arrow before the values) is dropped and
splits them.  Return three values: the items before the arrow (all of
them without one), those after it, and whether there was an arrow; a
fourth, the span of the :END."
  (let ((container (open-container builder :signature span))
        (head nil) (arrow nil) (end-span span))
    (loop
      (multiple-value-bind (event espan) (next-event builder)
        (cond ((null event)
               (report-shape builder span "The signature ~S never ends." key)
               (return))
              ((and (eq (event-type event) :end) (eq (event-key event) key))
               (setf end-span espan)
               (return))
              ((and (eq (event-type event) :begin) (eq (event-key event) :evaluates-to)
                    (not arrow) (eq (current-container builder) container))
               (setf head (container-contents container)
                     (container-items container) '()
                     arrow t)
               (skip-presentation builder "The arrow of a signature" espan))
              (t (dispatch-in-signature builder event espan)))))
    (finish-capture builder container span)
    (let ((items (container-contents container)))
      (if arrow
          (values head items t end-span)
          (values items nil nil end-span)))))

(defun finish-capture (builder container span)
  "Pop CONTAINER, a capture of this file, closing (and reporting) the
containers still open inside it; its items go nowhere."
  (loop until (eq (current-container builder) container)
        do (let ((inner (current-container builder)))
             (when (eq inner (first (last (builder-stack builder))))
               (return))
             (report-problem builder :unclosed (container-span inner)
                             :message (format nil "~S, closed by the end of a signature."
                                              (container-key inner)))
             (finish-container builder inner span)))
  (when (eq (current-container builder) container)
    (pop (builder-stack builder))))

(defun operator-of-key (key)
  "The OPERATOR enum value of the signature key KEY."
  (ecase key
    ((:defun :defun-no-return :defun-multi :defun-multi-accessor) :function)
    ((:defmac :defmac-no-return) :macro)
    ((:defspec :defspec-no-return) :special-operator)
    (:defgen :generic-function)
    (:defmeth :method)))

(defun entries-math-text (node)
  "The characters of the formula NODE, in order, minus signs as the
hyphen-minus of a name: the text a name set in math (\\Defun's `<', set
as $<$ by setup-aux.tex) spells, or NIL when NODE holds anything but
noads and characters."
  (labels ((walk (item)
             (cond ((not (typep item 'node)) (return-from entries-math-text nil))
                   ((eq (node-kind item) :math-char)
                    (substitute #\- (code-char #x2212) (math-char-text item)))
                   ((and (eq (node-kind item) :math-noad)
                         (null (math-noad-superscript item))
                         (null (math-noad-subscript item)))
                    (format nil "~{~A~}" (mapcar #'walk (math-noad-nucleus item))))
                   (t (return-from entries-math-text nil)))))
    (format nil "~{~A~}" (mapcar #'walk (math-content node)))))

(defun entries-strip-name (items name)
  "STRIP-PREFIX of NAME from ITEMS, whose leading formulas count as the
text they spell (ENTRIES-MATH-TEXT): two values as STRIP-PREFIX's."
  (multiple-value-bind (rest missing) (strip-prefix items name)
    (unless missing
      (return-from entries-strip-name (values rest nil))))
  (let ((rest (trim-items items)) (text ""))
    (loop
      (let ((item (first rest)))
        (cond ((string= text name)
               (return (values (trim-items rest) nil)))
              ((not (and (< (length text) (length name))
                         (string= text name :end2 (length text))))
               (return (values items t)))
              ((stringp item)
               (let ((remaining (subseq name (length text))))
                 (if (and (< (length item) (length remaining))
                          (string= item remaining :end2 (length item)))
                     (progn (setf text (concatenate 'string text item))
                            (pop rest))
                     (multiple-value-bind (after missing) (strip-prefix rest remaining)
                       (return (if missing (values items t) (values after nil)))))))
              ((and (typep item 'node) (eq (node-kind item) :math)
                    (entries-math-text item))
               (setf text (concatenate 'string text (entries-math-text item)))
               (pop rest))
              (t (return (values items t))))))))

(defun after-name (builder span items name)
  "ITEMS without NAME, the name the signature starts with (reported when
it does not)."
  (multiple-value-bind (rest missing) (entries-strip-name items name)
    (when missing
      (report-shape builder span "The signature does not start with ~S." name))
    rest))

(defun operator-signature (builder key span names head tail end-span)
  "Add the operator signature of KEY, named NAMES, whose first line is
HEAD (the name, then the lambda list) and whose values are TAIL."
  (let ((no-return (member key '(:defun-no-return :defmac-no-return :defspec-no-return))))
    (add-built-node
     builder
     (make-builder-node builder :operator-signature
                        :span span :operator (operator-of-key key) :names names
                        :lambda-list (after-name builder span head (first names))
                        :values (and (not no-return) (trim-items tail))
                        :no-return (and no-return t))
     end-span)))

(defun setf-parts (builder span items name)
  "The lambda list and the new value of ITEMS, the words of a setf form
\"(setf (NAME lambda-list) new-value)\"."
  (multiple-value-bind (rest missing)
      (strip-prefix items (concatenate 'string "(setf (" name))
    (when missing
      (report-shape builder span "The setf form does not start with (setf (~A." name)
      (return-from setf-parts (values nil items)))
    (multiple-value-bind (lambda-list after) (split-at-close-paren rest)
      (multiple-value-bind (new-value unclosed) (strip-final-paren after)
        (when unclosed
          (report-shape builder span "The setf form of ~A does not end with a parenthesis." name))
        (values (trim-items lambda-list) new-value)))))

(defun setf-signature (builder span names items end-span)
  "Add the setf signature of NAMES whose words are ITEMS."
  (multiple-value-bind (lambda-list new-value) (setf-parts builder span items (first names))
    (add-built-node
     builder
     (make-builder-node builder :setf-signature :span span :names names
                                                :lambda-list lambda-list :new-value new-value)
     end-span)))

(defun items-text (items)
  "The strings of ITEMS joined, trimmed."
  (trim-text (apply #'concatenate 'string (remove-if-not #'stringp items))))

(defun single-signature-handler (builder event span)
  "A signature that sets one name: operators, \\Defsetf, \\Defvar, \\Defcon."
  (let* ((key (event-key event))
         (name (entries-name-text (argument-trimmed builder event 0)))
         (paragraph (leave-paragraph builder span)))
    (multiple-value-bind (head tail arrow end-span) (read-signature builder key span)
      (declare (ignore arrow))
      (case key
        (:defsetf (setf-signature builder span (list name) head end-span))
        ((:defvar :defcon)
         (add-built-node
          builder
          (make-builder-node builder :variable-signature
                             :span span :constant (eq key :defcon)
                             :name (let ((text (items-text head)))
                                     (if (string= text "") name text)))
          end-span))
        (t (operator-signature builder key span (list name) head tail end-span))))
    (when paragraph (swallow-paragraph-end builder))))

;;; The -multi signatures

(defstruct (capture (:constructor make-capture (container)))
  "The first row of one table of a -multi signature: its CONTAINER, the
items before the arrow, and whether the arrow came."
  container (head nil) (arrow nil))

(defun capture-result (builder capture span)
  "End CAPTURE: its items before and after the arrow."
  (let ((container (capture-container capture)))
    (finish-capture builder container span)
    (let ((items (container-contents container)))
      (if (capture-arrow capture)
          (values (capture-head capture) items)
          (values items nil)))))

(defun table-structure-p (event)
  "True for the events of the table a -multi signature is set in, which
only lay out its rows."
  (and (member (event-type event) '(:begin :end))
       (member (event-key event) '(:alignment :row :cell :no-align :box))))

(defun multi-signature-handler (builder event span)
  "A signature of several names, set as a table with one \\entry per
name: the names are the :ENTRY marks, and the words of the first row of
each table (the second table of an accessor sets its setf forms) are the
signature's."
  (let ((key (event-key event)) (names '()) (first-row nil) (second-row nil)
        (capture nil) (which nil) (end-span span)
        (paragraph (leave-paragraph builder span)))
    (flet ((start (row)
             (setf which row
                   capture (make-capture (open-container builder :signature span))))
           (stop ()
             (when capture
               (multiple-value-bind (head tail) (capture-result builder capture span)
                 (if (eq which :first)
                     (setf first-row (list head tail))
                     (setf second-row (list head tail))))
               (setf capture nil))))
      (loop
        (multiple-value-bind (e espan) (next-event builder)
          (cond ((null e)
                 (report-shape builder span "The signature ~S never ends." key)
                 (return))
                ((and (eq (event-type e) :end) (eq (event-key e) key))
                 (setf end-span espan)
                 (return))
                ((and (eq (event-type e) :mark) (eq (event-key e) :entry))
                 (let ((name (entries-name-text (argument-trimmed builder e 0))))
                   (cond ((not (member name names :test #'string=))
                          (stop)
                          (push name names)
                          (unless first-row (start :first)))
                         ((and (not second-row) (not (eq which :second))
                               (eq key :defun-multi-accessor))
                          (stop)
                          (start :second))
                         (t (stop)))))
                ((and (table-structure-p e)
                      (not (and capture (eq (event-key e) :box)))))
                ((and capture (eq (event-type e) :begin) (eq (event-key e) :evaluates-to)
                      (not (capture-arrow capture))
                      (eq (current-container builder) (capture-container capture)))
                 (setf (capture-head capture) (container-contents (capture-container capture))
                       (container-items (capture-container capture)) '()
                       (capture-arrow capture) t)
                 (skip-presentation builder "The arrow of a signature" espan))
                (capture (dispatch-in-signature builder e espan)))))
      (stop))
    (setf names (nreverse names))
    (cond ((null names)
           (report-shape builder span "The signature ~S names nothing." key))
          (t
           (ecase key
             ((:defun-multi :defun-multi-accessor)
              (operator-signature builder key span names (first first-row) (second first-row)
                                  end-span)
              (when (eq key :defun-multi-accessor)
                (setf-signature builder span names (first second-row) end-span)))
             (:defsetf-multi
              (setf-signature builder span names (first first-row) end-span)))))
    (when paragraph (swallow-paragraph-end builder))))

;;; Type specifiers

(defun entries-strip-syntax-prefix (builder items prefix)
  "STRIP-PREFIX of PREFIX, \"(NAME\", from a line of syntax: from ITEMS,
or from the content of the notation node ITEMS start with, at any depth
(\\starparam's group in its repetition).  The \\halign of \\Deftype sets
the prefix in its template, which TeX reads after it has expanded the
first macro of the line (looking for \\omit), so a notation macro there
(\\ttbrac) begins before the prefix: the prefix is taken out of it, and
the notation's opening glyph, which then begins its content, too
(BNF-STRIP-NODE-GLYPHS)."
  (multiple-value-bind (rest missing) (strip-prefix items prefix)
    (if (not missing)
        (values rest nil)
        (let ((first (first (trim-items items)))
              (registry (builder-registry builder)))
          (if (and (typep first 'node) (find-field (node-kind first) 'content registry))
              (multiple-value-bind (inner inner-missing)
                  (entries-strip-syntax-prefix
                   builder (node-field-value first 'content registry) prefix)
                (cond (inner-missing (values items t))
                      (t (setf (node-field-value first 'content registry) inner)
                         (bnf-strip-opening-glyph builder first)
                         (values (trim-items items) nil))))
              (values items t))))))

(defun syntax-row (builder span name items)
  "The words of one line of a type specifier's syntax, \"(NAME …)\"
without its parentheses and name."
  (multiple-value-bind (rest missing)
      (entries-strip-syntax-prefix builder items (concatenate 'string "(" name))
    (when missing
      (report-shape builder span "A syntax line does not start with (~A." name)
      (return-from syntax-row (trim-items items)))
    (nth-value 0 (strip-final-paren rest))))

(defun type-signature-handler (builder event span)
  "\\Deftype: the type specifier's name, and the lines of its compound
syntax, set as the rows of the alignment that follows."
  (let ((name (argument-trimmed builder event 0)) (rows '()) (row nil) (end-span span))
    (let ((next (peek-event builder)))
      (when (and next (eq (event-type next) :begin) (eq (event-key next) :alignment))
        (next-event builder)
        (loop
          (multiple-value-bind (e espan) (next-event builder)
            (cond ((null e)
                   (report-shape builder span "The syntax of ~A never ends." name)
                   (return))
                  ((and (eq (event-type e) :end) (eq (event-key e) :alignment))
                   (setf end-span espan)
                   (return))
                  ((and (eq (event-type e) :begin) (eq (event-key e) :row))
                   (setf row (open-container builder :signature espan)))
                  ((and (eq (event-type e) :end) (eq (event-key e) :row))
                   (when row
                     (let ((items (container-contents row)))
                       (finish-capture builder row espan)
                       (setf row nil)
                       (when (trim-items items)
                         (push (syntax-row builder espan name items) rows)))))
                  ((table-structure-p e))
                  (row (dispatch builder e espan)))))))
    ;; The macro ends with a paragraph of its own, empty (setup-document.tex:212).
    (destructuring-bind (&optional first second) (events-ahead builder 2)
      (when (and first second
                 (eq (event-type first) :begin) (eq (event-key first) :paragraph)
                 (eq (event-type second) :end) (eq (event-key second) :paragraph))
        (next-event builder)
        (next-event builder)))
    (let ((syntax (loop for (lines . more) on (nreverse rows)
                        append lines
                        when more collect (make-builder-node builder :bnf-break))))
      (add-built-node
       builder
       (make-builder-node builder :type-signature :span span :name name :syntax syntax)
       end-span))))

;;; The handlers

(defun install-entry-handlers (table)
  "Register the handlers of step 3.9 in the handler table TABLE."
  (define-handler (:begin :com :table table) (builder event span)
    "An entry: its names, its kind, its parts."
    (let* ((names (mapcar #'entries-name-text (split-names (argument-trimmed builder event 0))))
           (text (argument-trimmed builder event 1))
           (kind (and (string/= text "") (entry-kind-keyword text)))
           (enum (find-enum 'entry-kind (builder-registry builder))))
      (unless (and kind (assoc kind (enum-values enum)))
        (report-shape builder span "The entry ~{~A~^, ~} has the kind ~S, which is none of the entry kinds."
                      names text)
        (setf kind nil))
      (open-container builder :com span
                      :node (make-builder-node builder :dictionary-entry
                                               :id (first names) :names names
                                               :entry-kind kind)
                      :on-close #'close-entry)
      (skip-heading builder)))
  (define-handler (:end :com :table table) (builder event span)
    "The end of an entry: its last part ends with it."
    (drain-inner-containers builder)
    (close-part builder span)
    (close-container builder :com span event))
  (define-handler (:mark :label :table table) (builder event span)
    "A part: it runs to the next label or the end of the entry.  A label
on the line after a paragraph's last (dict-flow.tex:2447) comes before
that paragraph's end, which closes it first (DRAIN-INNER-CONTAINERS)."
    (drain-inner-containers builder)
    (close-part builder span)
    (unless (find-container builder :com)
      (report-shape builder span "The label ~S stands outside any entry."
                    (argument-trimmed builder event 0)))
    (open-container builder :label span
                    :node (make-builder-node builder :part
                                             :title (argument-trimmed builder event 0)
                                             :none (and (string/= (argument-trimmed builder event 1) ":") t))
                    :field 'content)
    (skip-label-heading builder))
  (define-handler (:mark :label-confidence :table table) (builder event span)
    "The punctuation after a part that says None: how sure the authors are."
    (let ((part (find-container builder :label)))
      (if (and part (container-node part))
          (setf (node-field-value (container-node part) 'confidence (builder-registry builder))
                (argument-trimmed builder event 0))
          (report-shape builder span "A label confidence stands outside any part."))))
  (dolist (key (operator-keys))
    (register-handler :begin key #'single-signature-handler table))
  (dolist (key '(:defsetf :defvar :defcon))
    (register-handler :begin key #'single-signature-handler table))
  (dolist (key '(:defun-multi :defun-multi-accessor :defsetf-multi))
    (register-handler :begin key #'multi-signature-handler table))
  (register-handler :mark :deftype #'type-signature-handler table)
  (define-handler (:mark :entry :table table) (builder event span)
    "A row of \\tabletwo outside a signature: its cells are built in the table."
    (declare (ignore builder event span)))
  table)

(install-entry-handlers *handlers*)

;; The words of a signature are set in the entry's own fonts, which mean
;; nothing there: the signature container reads text as it comes.
(plain-text-container-p :signature)   ; computes the list before it is extended
(pushnew :signature *plain-text-containers*)
