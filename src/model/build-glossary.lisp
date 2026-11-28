;;;; src/model/build-glossary.lisp
;;;;
;;;; The handlers that build the glossary from their events: the groups of
;;;; one letter, their entries, the entries' senses and the notation the
;;;; senses carry (docs/model.md, "Glossary").
;;;; Owner: step 3.14 of docs/plan/m3.md.

(in-package #:cl-ansi-spec/model)

;;; What the notation's texts mean

(defparameter *part-of-speech-texts*
  '(("n." . :noun) ("v." . :verb) ("v.t." . :transitive-verb)
    ("adj." . :adjective) ("adv." . :adverb))
  "The text \\Noun, \\Verb, \\TransitiveVerb, \\Adjective and \\Adverb
set (concept-glossary.tex:55-59), and the part of speech it is.")

(defparameter *usage-texts*
  '(("ANSI" . :ansi) ("IEEE" . :ieee) ("ISO" . :iso) ("Trad." . :traditional)
    ("Math." . :mathematics) ("Idiom." . :idiomatic) ("Comp." . :computers))
  "The text \\ANSI, \\IEEE, \\ISO, \\Traditional, \\Mathematics,
\\Idiomatic and \\Computers set (concept-glossary.tex:61-67), and the
usage it is.")

;;; Tags: what a notation leaves in an entry until the entry closes

(defstruct (glossary-tag (:constructor make-glossary-tag (kind value)))
  "A part of speech, a usage or a pronunciation found in an entry's
items: its KIND (:PART-OF-SPEECH, :USAGE or :PRONUNCIATION) and VALUE
(an enum value, or a list of inlines)."
  (kind nil :type symbol :read-only t)
  (value nil :read-only t))

(defun inline-item-p (builder item)
  "True when ITEM is a string or a node of the category :INLINE."
  (or (stringp item)
      (and (typep item 'node)
           (member (node-kind item) (category-kinds :inline (builder-registry builder))))))

(defun in-entry-p (builder)
  "True when the innermost container of BUILDER is a glossary entry's."
  (eq (container-key (current-container builder)) :glossary-entry))

(defun tag-opener (table-name table kind)
  "A handler that opens a container for a notation whose argument text is
one of the keys of the alist TABLE (named TABLE-NAME in reports).  When
it closes in a glossary entry it leaves a tag of KIND with the value the
text maps to; anywhere else (the glossary's introduction shows the
notation) the text stays in italics."
  (lambda (builder event span)
    (let ((text (first (event-argument-texts builder event))))
      (open-container
       builder (event-key event) span
       :on-close (lambda (builder container)
                   (let ((value (cdr (assoc text table :test #'equal))))
                     (cond ((not (in-entry-p builder))
                            (add-item builder (make-builder-node builder :emphasis
                                                                 :span (container-span container)
                                                                 :content (list text))))
                           (value
                            (add-item builder (make-glossary-tag kind value)))
                           (t
                            (report-problem builder :diagnostic (container-span container)
                                            :message (format nil "~S is not one of ~A."
                                                             text table-name))))
                     (setf (container-items container) '())))))))

(defun pronunciation-inlines (items)
  "ITEMS, the text of a \\pronounced, without its layout: \\pronounced sets
the text in square brackets in a formula, and the brackets are the
notation of a pronunciation, as the glossary's introduction says, so the
formula is unwrapped to what is inside them (its bracket noads dropped,
the characters of the others as text), and a formula that holds nothing,
the mark of a stress, is dropped."
  (loop for item in items
        append (if (typep item 'node)
                   (case (node-kind item)
                     (:math (pronunciation-inlines (node-field-value item :content)))
                     (:math-noad
                      (unless (member (node-field-value item :class) '(:open :close))
                        (pronunciation-inlines (node-field-value item :nucleus))))
                     (:math-char (list (node-field-value item :text)))
                     ((:strong :emphasis :code)
                      (setf (node-field-value item :content)
                            (pronunciation-inlines (node-field-value item :content)))
                      (list item))
                     (t (list item)))
                   (list item))))

(defun finish-pronunciation (builder container)
  "The end of a \\pronounced: in an entry, its inlines are the pronunciation,
left as a tag in the container below; elsewhere they stay where they are."
  (when (in-entry-p builder)
    (let ((inlines (remove-if-not (lambda (item) (inline-item-p builder item))
                                  (pronunciation-inlines (container-contents container)))))
      (when inlines
        (add-item builder (make-glossary-tag :pronunciation inlines)))
      (setf (container-items container) '()))))

(defun sense-number (text)
  "The integer a \\meaning's TEXT starts with, and whether TEXT has more:
`2a' is sense 2, a sub-sense of it; `n' has no number."
  (multiple-value-bind (number end) (parse-integer text :junk-allowed t)
    (values number (and number (< end (length text))))))

(defun finish-sense-mark (builder container text)
  "The end of a \\meaning whose argument is TEXT: its number is the :SENSE of
the term reference that comes before it, which it follows directly.  What
the \\meaning set (a subscript) is dropped."
  (let ((previous (first (container-items (current-container builder))))
        (span (container-span container)))
    (setf (container-items container) '())
    (multiple-value-bind (number sub) (sense-number text)
      (cond ((not (and (typep previous 'node) (eq (node-kind previous) :term-ref)))
             (report-problem builder :diagnostic span
                             :message "A \\meaning does not follow a term reference."))
            ((null number)
             (report-problem builder :diagnostic span
                             :message (format nil "The sense ~S is not a number." text)))
            (t
             (setf (node-field-value previous :sense (builder-registry builder)) number)
             (when sub
               (report-problem builder :diagnostic span
                               :message (format nil "The sense ~S is a sub-sense of ~D, kept as ~D."
                                                text number number))))))))

;;; Splitting an entry's items into senses

(defun glossary-blank-string-p (item)
  "True when ITEM is a string of nothing but spaces."
  (and (stringp item) (every (lambda (char) (member char '(#\Space #\Tab #\Newline))) item)))

(defun sense-marker (string number)
  "The start and end of the first marker `NUMBER.' in STRING: set off by a
space or the string's start before it, and by a space after it (a
number that ends the string is a sentence's, \"the integer 1.\"); NIL
when there is none."
  (let ((marker (format nil "~D." number)))
    (loop for start = (search marker string) then (search marker string :start2 (1+ start))
          while start
          for end = (+ start (length marker))
          when (and (or (zerop start) (char= (char string (1- start)) #\Space))
                    (< end (length string)) (char= (char string end) #\Space))
            do (return (values start end)))))

(defun split-segments (items)
  "ITEMS (an entry's, oldest first) cut at the sense numbers `1.', `2.', …
that run from 1 in the strings: a list of (NUMBER . ITEMS), the first
for what comes before `1.' with NUMBER NIL.  The numbers are told by
their order, so that the `2.' of `version 2.' in the text of sense 1 does
not count."
  (let ((segments '())
        (current '())
        (number nil)
        (next 1))
    (flet ((close-segment ()
             (push (cons number (nreverse current)) segments)
             (setf current '())))
      (dolist (item items)
        (if (stringp item)
            (loop
              (multiple-value-bind (start end) (sense-marker item next)
                (cond (start
                       (when (plusp start) (push (subseq item 0 start) current))
                       (close-segment)
                       (setf number next
                             item (subseq item end)
                             next (1+ next)))
                      (t (when (plusp (length item)) (push item current))
                         (return)))))
            (push item current)))
      (close-segment))
    (nreverse segments)))

(defun glossary-trim-inlines (items)
  "ITEMS without the spaces around them and the empty strings: the
leading space of the first string and the trailing space of the last."
  (let ((items (remove-if #'glossary-blank-string-p items)))
    (when (stringp (first items))
      (setf (first items) (string-left-trim " " (first items))))
    (let ((last (last items)))
      (when (stringp (first last))
        (setf (first last) (string-right-trim " " (first last)))))
    (remove "" items :test #'equal)))

(defun heading-item-p (item term)
  "True when ITEM only repeats the entry's heading: the term in bold, the
index entry of the term, a space."
  (or (glossary-blank-string-p item)
      (and (stringp item) (string= (string-trim " " item) term))
      (and (typep item 'node)
           (case (node-kind item)
             (:index-entry t)
             (:strong (equal (apply #'concatenate 'string
                                    (remove-if-not #'stringp (node-field-value item :content)))
                             term))))))

(defun sense-of (builder number items span)
  "The :GLOSSARY-SENSE of ITEMS numbered NUMBER (NIL for none): its tags
give its parts of speech and usages, the :GLOSSARY-EXAMPLE nodes its
examples, the rest its definition."
  (let ((tags (remove-if-not #'glossary-tag-p items))
        (examples (remove-if-not (lambda (item)
                                   (and (typep item 'node)
                                        (eq (node-kind item) :glossary-example)))
                                 items))
        (content (remove-if (lambda (item)
                              (or (glossary-tag-p item)
                                  (and (typep item 'node)
                                       (eq (node-kind item) :glossary-example))))
                            items)))
    (make-builder-node builder :glossary-sense
                       :span span :number number
                       :parts-of-speech (tags-of tags :part-of-speech)
                       :usages (tags-of tags :usage)
                       :content (glossary-trim-inlines content)
                       :examples examples)))

(defun tags-of (tags kind)
  "The values of the tags of KIND among TAGS, in order."
  (loop for tag in tags
        when (eq (glossary-tag-kind tag) kind) collect (glossary-tag-value tag)))

(defun glossary-separator-p (item)
  "True when ITEM is a string of the commas and spaces that set the
notation of an entry apart (`\\Noun, \\TransitiveVerb')."
  (and (stringp item) (every (lambda (char) (member char '(#\, #\Space))) item)))

(defun drop-separators (items)
  "ITEMS without the separator strings (SEPARATOR-P) next to a tag: the
comma of `\\Noun, \\TransitiveVerb' is notation, the comma between two
references is text."
  (loop for (previous item next) on (cons nil items)
        while item
        unless (and (glossary-separator-p item)
                    (or (glossary-tag-p previous) (glossary-tag-p next)))
          collect item))

(defun finish-entry (builder container)
  "The end of a \\gentry: its items become its pronunciation, its parts
of speech and usages (those before the first sense number) and its senses."
  (let* ((node (container-node container))
         (term (node-field-value node :term))
         (span (container-span container))
         (registry (builder-registry builder))
         (items (member-if-not (lambda (item) (heading-item-p item term))
                               (container-contents container)))
         (segments (split-segments items))
         (head (drop-separators (rest (first segments))))
         (numbered (rest segments))
         (head-tags (remove-if-not #'glossary-tag-p head))
         (head-body (remove-if #'glossary-tag-p head)))
    (flet ((set-field (field value)
             (when value (setf (node-field-value node field registry) value))))
      (set-field :pronunciation (first (tags-of head-tags :pronunciation)))
      (set-field :parts-of-speech (tags-of head-tags :part-of-speech))
      (set-field :usages (tags-of head-tags :usage))
      (set-field :senses
                 (if numbered
                     (append (when (notevery #'glossary-blank-string-p head-body)
                               (list (sense-of builder nil head-body span)))
                             (loop for (number . body) in numbered
                                   collect (sense-of builder number (drop-separators body) span)))
                     (list (sense-of builder nil head-body span)))))
    (setf (container-items container) '())))

(defun finish-group (builder container)
  "The end of a letter's group: the entries it held are its entries; the
letter set in bold before the first is dropped, it repeats the letter."
  (declare (ignore builder))
  (let ((node (container-node container)))
    (setf (node-field-value node :entries)
          (remove-if-not (lambda (item)
                           (and (typep item 'node) (eq (node-kind item) :glossary-entry)))
                         (container-contents container))
          (container-items container) '())))

;;; Entries and groups run until the next one

;;; The layout of the glossary is the macros' own: `\beginlist' around it,
;;; one list and one item for each letter (`\indextab' ends the list and
;;; begins another), one paragraph for each entry.  None of it is the
;;; glossary's structure, which the marks give, so it is dropped here.

(defvar *glossary-lists* (make-hash-table :test 'eq :weakness :key)
  "The number of lists the glossary's macros have open, by builder: its
own `\\beginlist' and the one each letter begins.  A list's end is
dropped while one is open.")

(defun glossary-lists (builder)
  "The number of lists the glossary has open in BUILDER's build."
  (gethash builder *glossary-lists* 0))

(defun (setf glossary-lists) (count builder)
  (setf (gethash builder *glossary-lists*) count))

(defun glossary-layout-p (builder event)
  "True when EVENT is the layout of the glossary (paragraphs, items,
lists) and so is dropped; a list's begin and end are counted."
  (let ((type (event-type event))
        (key (event-key event)))
    (case key
      (:paragraph (member type '(:begin :end)))
      ((:item :item-2) (eq type :mark))
      (:list (case type
               (:begin (incf (glossary-lists builder)) t)
               (:end (when (plusp (glossary-lists builder))
                       (decf (glossary-lists builder))
                       t)))))))

(defun ends-outside-p (builder container event)
  "True when EVENT is the end of a container below CONTAINER (the stack
is innermost first), which therefore ends the glossary's text as well."
  (and (eq (event-type event) :end)
       (let ((outer (find-container builder (event-key event))))
         (and outer (member outer (rest (member container (builder-stack builder))))))))

(defun run-until (builder container stop-p)
  "Hand the events that follow to their handlers, but for the glossary's
layout, until one satisfies STOP-P (a function of the event) or ends a
container below CONTAINER, or the events end.  Return the span of the
last event handled."
  (let ((last nil))
    (loop
      (let ((event (peek-event builder)))
        (when (or (null event)
                  (funcall stop-p event)
                  (ends-outside-p builder container event))
          (return last))
        (multiple-value-bind (event span) (next-event builder)
          (unless (glossary-layout-p builder event)
            (dispatch builder event span))
          (setf last span))))))

(defun glossary-mark-p (event &rest keys)
  "True when EVENT is a :MARK of one of KEYS."
  (and (eq (event-type event) :mark) (member (event-key event) keys)))

(defun open-and-run (builder key span node on-close stop-p)
  "Open a container of KEY with NODE, run it until STOP-P, then close it."
  (let ((container (open-container builder key span :node node :on-close on-close)))
    (let ((end (run-until builder container stop-p)))
      (close-container builder key (or end span)))))

(defun drop-glossary-list (builder)
  "The glossary's own `\\beginlist', open when its first letter begins, is
dropped, and counted as open so that its end is."
  (let ((container (current-container builder)))
    (when (and (eq (container-key container) :list)
               (null (container-items container)))
      (pop (builder-stack builder))
      (incf (glossary-lists builder)))))

(defun letter-handler (builder event span)
  "A \\firstindextab or \\indextab: a group of entries, to the next letter."
  (let ((letter (first (event-argument-texts builder event))))
    (drop-glossary-list builder)
    (open-and-run builder :glossary-letter span
                  (make-builder-node builder :glossary-group :letter letter)
                  #'finish-group
                  (lambda (event) (glossary-mark-p event :glossary-letter)))))

(defun entry-handler (builder event span)
  "A \\gentry: an entry, to the next entry or letter."
  (let ((term (first (event-argument-texts builder event))))
    (open-and-run builder :glossary-entry span
                  (make-builder-node builder :glossary-entry :id term :term term)
                  #'finish-entry
                  (lambda (event) (glossary-mark-p event :glossary-entry :glossary-letter)))))

(defun install-glossary-handlers (table)
  "Register the handlers of step 3.14 in the handler table TABLE."
  (register-handler :mark :glossary-letter #'letter-handler table)
  (register-handler :mark :glossary-entry #'entry-handler table)
  (register-handler :begin :part-of-speech
                    (tag-opener "the parts of speech" *part-of-speech-texts* :part-of-speech)
                    table)
  (register-handler :begin :usage
                    (tag-opener "the usages" *usage-texts* :usage)
                    table)
  (register-handler :begin :pronunciation
                    (lambda (builder event span)
                      (declare (ignore event))
                      (open-container builder :pronunciation span
                                      :on-close #'finish-pronunciation))
                    table)
  (register-handler :begin :glossary-example
                    (lambda (builder event span)
                      (declare (ignore event))
                      (open-container builder :glossary-example span
                                      :node (make-builder-node builder :glossary-example)
                                      :field 'content))
                    table)
  (register-handler :begin :sense
                    (lambda (builder event span)
                      (let ((text (first (event-argument-texts builder event))))
                        (open-container builder :sense span
                                        :on-close (lambda (builder container)
                                                    (finish-sense-mark builder container text)))))
                    table)
  table)

(install-glossary-handlers *handlers*)
