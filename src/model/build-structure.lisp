;;;; src/model/build-structure.lisp
;;;;
;;;; The handlers that build chapters, sections and the standard from their
;;;; events (docs/model.md, "Structure").
;;;; Owner: step 3.8 of docs/plan/m3.md.
;;;;
;;;; A chapter and a section are marks with no end: a section runs to the
;;;; next mark of its level or above, so the handlers keep a container open
;;;; per chapter and per section and close them when the next one begins.
;;;; The last ones of a job stay open at its end, which the core reports
;;;; (:UNCLOSED); see docs/model.md.

(in-package #:cl-ansi-spec/model)

;;; Levels

(defparameter *section-levels*
  '((:section . 1) (:dictionary . 1) (:subsection . 2) (:subsubsection . 3)
    (:subsubsubsection . 4) (:subsubsubsubsection . 5))
  "The vocabulary key of each kind of section mark and the level it begins.")

(defun structure-level (key)
  "The level of the container opened by KEY: 0 for a chapter, 1 to 5 for
a section, NIL for any other container."
  (case key
    ((:chapter :simple-chapter) 0)
    (t (cdr (assoc key *section-levels*)))))

(defun structure-container-p (container)
  "True when CONTAINER holds a chapter or a section."
  (and (structure-level (container-key container)) t))

(defun section-node-p (item)
  "True when ITEM is a section node."
  (and (typep item 'node) (eq (node-kind item) :section)))

(defun field-of (builder node name)
  "The value of NODE's field NAME in BUILDER's registry."
  (node-field-value node name (builder-registry builder)))

;;; Closing and finding the enclosing structure

(defun enclosing-structure (builder level)
  "The innermost open container of a chapter or section above LEVEL, or
NIL."
  (find-if (lambda (container)
             (let ((open-level (structure-level (container-key container))))
               (and open-level (< open-level level))))
           (butlast (builder-stack builder))))

(defun close-down-to (builder keep span)
  "Close the open containers above KEEP at SPAN: those of chapters and
sections quietly, since a mark of the next one ends them, any other
reported :UNCLOSED."
  (loop until (eq (current-container builder) keep)
        do (let ((top (current-container builder)))
             (unless (structure-container-p top)
               (report-problem builder :unclosed (container-span top)
                               :message (format nil "~S, closed by the next chapter or section."
                                                (container-key top))))
             (finish-container builder top span))))

(defun close-structure-for (builder level span)
  "Close what a mark of LEVEL ends and return the container that now
holds the new chapter or section (NIL: the root)."
  (let ((parent (enclosing-structure builder level)))
    (close-down-to builder (or parent (car (last (builder-stack builder)))) span)
    parent))

;;; Headings

(defun trim-title (items)
  "ITEMS, the inlines of a heading, without the space around them and
without empty strings."
  (let ((items (copy-list items)))
    (when (stringp (first items))
      (setf (first items) (string-left-trim " " (first items))))
    (let ((last (last items)))
      (when (stringp (first last))
        (setf (first last) (string-right-trim " " (first last)))))
    (remove "" items :test #'equal)))

(defun skip-to-end (builder key)
  "Consume the events up to the :END of KEY that closes the :BEGIN just
consumed, returning the :TEXT events' texts and, as a second value,
true when that end was found.  It stops, without consuming it, at the
end of the paragraph, so that a missing end does not eat the job."
  (let ((depth 1) (texts '()))
    (loop (multiple-value-bind (event) (peek-event builder)
            (when (or (null event)
                      (and (eq (event-type event) :end) (eq (event-key event) :paragraph)))
              (return-from skip-to-end (values (nreverse texts) nil)))
            (next-event builder)
            (let ((type (event-type event)))
              (cond ((and (eq type :begin) (eq (event-key event) key)) (incf depth))
                    ((and (eq type :end) (eq (event-key event) key))
                     (when (zerop (decf depth)) (return)))
                    ((eq type :text) (push (event-text event) texts))))))
    (values (nreverse texts) t)))

(defun read-heading-paragraph (builder key span number-box)
  "Consume the events of a heading's paragraph, whose :BEGIN is consumed,
to its end.  The text, in a container of KEY (whose text is not read by
font), becomes the title inlines.  With NUMBER-BOX the first box is the
number TeX typeset.  An empty math (the hang of the number) is skipped.
Return the title and the typeset number (NIL without one)."
  (let* ((title '()) (number nil) (box-seen nil)
         (container (open-container
                     builder key span
                     :on-close (lambda (builder container)
                                 (declare (ignore builder))
                                 (setf title (container-contents container)
                                       (container-items container) '())))))
    (loop (multiple-value-bind (event event-span) (next-event builder)
            (unless event (return))
            (let ((type (event-type event)) (event-key (event-key event)))
              (cond ((and (eq type :end) (eq event-key :paragraph)) (return))
                    ((eq type :indent))
                    ((and (eq type :begin) (eq event-key :math))
                     (unless (nth-value 1 (skip-to-end builder :math))
                       (report-problem builder :node event-span
                                       :message "A heading's math has no end.")))
                    ((and number-box (not box-seen) (eq type :begin) (eq event-key :box))
                     (setf box-seen t)
                     (multiple-value-bind (texts ended) (skip-to-end builder :box)
                       (unless ended
                         (report-problem builder :node event-span
                                         :message "A heading's number box has no end."))
                       (setf number (string-trim " " (apply #'concatenate 'string texts)))))
                    (t (dispatch builder event event-span))))))
    (when (member container (builder-stack builder))
      (close-down-to builder container span)
      (finish-container builder container span))
    (values (trim-title title) number)))

(defun read-headings (builder key paragraphs number-box)
  "Consume what follows the mark of a chapter or section: the events
before and between its PARAGRAPHS heading paragraphs, handled as usual
(glue, penalties, writes), and the paragraphs, which become the title.
Return the title of the last and the typeset number of the first box.
Reaching text, a mark or another container before the paragraph is
reported and ends the search."
  (let ((title '()) (number nil) (seen 0))
    (loop while (< seen paragraphs)
          do (multiple-value-bind (event event-span) (peek-event builder)
               (unless event (return))
               (let ((type (event-type event)) (event-key (event-key event)))
                 (cond ((and (eq type :begin) (eq event-key :paragraph))
                        (next-event builder)
                        (multiple-value-bind (text typeset)
                            (read-heading-paragraph builder key event-span number-box)
                          (setf title text)
                          (unless number (setf number typeset)))
                        (incf seen))
                       ((or (member type '(:text :space))
                            (and (eq type :mark) (not (eq event-key :define-chapter)))
                            (and (member type '(:begin :end)) (not (eq event-key :box))))
                        (report-problem builder :node event-span
                                        :message (format nil "No heading follows ~S." key)
                                        :event event)
                        (return))
                       (t (next-event builder)
                          (dispatch builder event event-span))))))
    (values title number)))

;;; Numbers and ids

(defun counted-number (builder parent level)
  "The number of a new section of LEVEL in PARENT (the container of a
chapter or section, or NIL), counted as TeX's counters do: its parent's
number, a zero for each level skipped, then one more than the sections of
LEVEL since the last of a level above.  NIL when the parent has no
number, as in a build that starts inside a chapter."
  (let* ((node (and parent (container-node parent)))
         (base (and node (field-of builder node :number)))
         (parent-level (and parent (structure-level (container-key parent)))))
    (when base
      (let ((count 0))
        (dolist (item (container-items parent))
          (when (section-node-p item)
            (let ((item-level (field-of builder item :level)))
              (cond ((= item-level level) (incf count))
                    ((< item-level level) (return))))))
        (with-output-to-string (out)
          (write-string base out)
          (loop repeat (- level parent-level 1) do (write-string ".0" out))
          (format out ".~D" (1+ count)))))))

(defun default-section-id (builder parent number)
  "The id of a section no \\DefineSection names, until one does:
<parent-id>/<n>, its n-th among its parent's sections, or its number when
the build holds no parent."
  (let ((node (and parent (container-node parent))))
    (if node
        (format nil "~A/~D" (field-of builder node :id)
                (1+ (count-if #'section-node-p (container-items parent))))
        (format nil "section-~A" number))))

;;; The handlers

(defun dictionary-title (builder parent)
  "The title of a dictionary section, which has no heading of its own:
its chapter's title and \"Dictionary\", as \\includeDictionary has the
table of contents show it."
  (let* ((chapter (and parent (container-node parent)))
         (title (and chapter (field-of builder chapter :title)))
         (last (car (last title))))
    (if (stringp last)
        (append (butlast title) (list (concatenate 'string last " Dictionary")))
        (append title (list (if title " Dictionary" "Dictionary"))))))

(defun begin-section (builder event span)
  "A section mark: close the sections it ends, read its heading, count
its number, check it against the number TeX typeset, and open it."
  (let* ((key (event-key event))
         (level (structure-level key))
         (dictionary (eq key :dictionary))
         (parent (close-structure-for builder level span)))
    (multiple-value-bind (title typeset)
        (if dictionary
            (values nil nil)
            (read-headings builder key 1 t))
      (let* ((counted (counted-number builder parent level))
             (number (or counted typeset))
             (node (make-builder-node
                    builder :section
                    :span span
                    :id (default-section-id builder parent number)
                    :number number
                    :level level
                    :dictionary dictionary
                    :title (if dictionary
                               (dictionary-title builder parent)
                               title))))
        (when (and counted typeset (string/= counted typeset))
          (report-problem builder :node span
                          :message (format nil "Section counted ~A, but TeX typeset ~A."
                                           counted typeset)))
        (open-container builder key span :node node :field :children)))))

(defun begin-chapter (builder event span)
  "A chapter mark: close the chapter before it and open this one, its
title and reference name from the arguments, then drop its heading."
  (let* ((key (event-key event))
         (simple (eq key :simple-chapter))
         (arguments (event-argument-texts builder event))
         (title (convert-text "cmbx10" (or (if simple (first arguments) (second arguments))
                                           (progn (report-problem builder :node span
                                                                  :message "A chapter mark without a title.")
                                                  ""))))
         (node (make-builder-node builder :chapter
                                  :span span
                                  :id (if simple title (third arguments))
                                  :number (if simple nil (first arguments))
                                  :title (list title))))
    (close-structure-for builder 0 span)
    (open-container builder key span :node node :field :children)
    (read-headings builder key (if simple 1 2) nil)))

(defun innermost-structure (builder)
  "The innermost open container of a chapter or section, or NIL."
  (find-if #'structure-container-p (butlast (builder-stack builder))))

(defun write-text (builder event)
  "The text of a :WRITE event to the section file (stream 5) when EVENT
is one, else NIL."
  (and event (eq (event-type event) :write)
       (eql (event-property event :stream) 5)
       (argument-text builder (event-property event :tokens))))

(defun take-section-write (builder)
  "Consume the next event when it is a write to the section file and
return its text."
  (let ((text (write-text builder (peek-event builder))))
    (when text (next-event builder))
    text))

(defun parse-reference-write (text word)
  "The label and the number of a section-file line `!<label> WORD <number>...'
\(TeX's record of a \\DefineSection or \\DefineChapter), or NIL when TEXT
is not one.  The number ends at a control space or a space."
  (let* ((space (and (plusp (length text)) (char= (char text 0) #\!)
                     (position #\Space text)))
         (marker (format nil "~A " word)))
    (when (and space (eql (search marker text :start2 (1+ space)) (1+ space)))
      (let ((start (+ space 1 (length marker))))
        (values (subseq text 1 space)
                (subseq text start (or (position-if (lambda (char) (member char '(#\\ #\Space)))
                                                    text :start start)
                                       (length text))))))))

(defun check-reference-write (builder text word label number span)
  "Report a mismatch between TEXT, TeX's record of the reference LABEL
and its NUMBER, and what the builder counted."
  (multiple-value-bind (written-label written-number) (and text (parse-reference-write text word))
    (cond ((null written-label)
           (report-problem builder :node span
                           :message (format nil "No ~A line follows the definition of ~A." word label)))
          ((string/= written-label label)
           (report-problem builder :node span
                           :message (format nil "TeX wrote the label ~A for ~A." written-label label)))
          ((and number (string/= written-number number))
           (report-problem builder :node span
                           :message (format nil "~A ~A counted ~A, but TeX wrote ~A."
                                            word label number written-number))))))

(defun define-section (builder event span)
  "\\DefineSection: the label is the id of the section it is in; the
number TeX wrote on the next line must be the one counted."
  (let* ((label (first (event-argument-texts builder event)))
         (container (innermost-structure builder))
         (node (and container (container-node container))))
    (cond ((not (and node (eq (node-kind node) :section)))
           (report-problem builder :node span
                           :message (format nil "\\DefineSection ~A is not in a section." label))
           (take-section-write builder))
          (t
           (when (some #'section-node-p (container-items container))
             (report-problem builder :node span
                             :message (format nil "\\DefineSection ~A follows a subsection of its section."
                                              label)))
           (setf (node-field-value node :id (builder-registry builder)) label)
           (check-reference-write builder (take-section-write builder) "Section" label
                                  (field-of builder node :number) span)))))

(defun define-chapter (builder event span)
  "\\DefineChapter: the reference name must be the chapter's id, and the
two lines TeX wrote (by name and by title) must give its number."
  (let* ((arguments (event-argument-texts builder event))
         (container (innermost-structure builder))
         (node (and container (container-node container))))
    (cond ((not (and node (eq (node-kind node) :chapter)))
           (report-problem builder :node span :message "\\DefineChapter is not in a chapter.")
           (take-section-write builder)
           (take-section-write builder))
          (t
           (unless (equal (first arguments) (field-of builder node :id))
             (report-problem builder :node span
                             :message (format nil "\\DefineChapter ~A is not the id of its chapter."
                                              (first arguments))))
           (check-reference-write builder (take-section-write builder) "Chapter"
                                  (first arguments) (field-of builder node :number) span)
           (check-reference-write builder (take-section-write builder) "Chapter"
                                  (second arguments) (field-of builder node :number) span)))))

(defun install-structure-handlers (table)
  "Register the handlers of step 3.8 in the handler table TABLE."
  (dolist (key '(:section :dictionary :subsection :subsubsection
                 :subsubsubsection :subsubsubsubsection))
    (register-handler :mark key #'begin-section table))
  (register-handler :mark :chapter #'begin-chapter table)
  (register-handler :mark :simple-chapter #'begin-chapter table)
  (register-handler :mark :define-section #'define-section table)
  (register-handler :mark :define-chapter #'define-chapter table)
  ;; Every other \write (the table of contents, the index, the figure
  ;; list) is data the model rebuilds from the events: dropped.
  (register-handler :write nil
                    (lambda (builder event span)
                      (declare (ignore builder event span))
                      nil)
                    table)
  table)

(install-structure-handlers *handlers*)

;;; The standard

(defun job-version (expander)
  "The text of \\rev, the revision of the draft, in EXPANDER's job (its
macro body without the braces around it), or NIL when undefined."
  (let* ((state (cl-ansi-spec/expand:expander-state expander))
         (cs (cl-ansi-spec/tex:intern-control-sequence
              (cl-ansi-spec/expand:es-tex state) "rev"))
         (meaning (cl-ansi-spec/expand:meaning state cs)))
    (when (and meaning (cl-ansi-spec/expand:macro-p meaning))
      (string-trim "{}" (token-list-text expander
                                         (cl-ansi-spec/expand:macro-body meaning))))))

(defun build-standard (chapters &key version (registry *registry*))
  "The :DOCUMENT of the chapter nodes CHAPTERS (in the order of the jobs):
those with no number are the front matter, the others the chapters."
  (let ((*registry* registry))
    (make-node :document
               :span (and chapters (node-span (first chapters)))
               :version version
               :front-matter (remove-if (lambda (chapter) (node-field-value chapter :number))
                                        chapters)
               :chapters (remove-if-not (lambda (chapter) (node-field-value chapter :number))
                                        chapters))))
