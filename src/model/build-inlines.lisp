;;;; src/model/build-inlines.lisp
;;;;
;;;; The handlers that build semantic inlines and unresolved references
;;;; from their events (docs/model.md, "Inlines"): terms, parameters,
;;;; fonts by meaning, references to names, sections and figures with
;;;; their key text (resolved later, by the resolve-* files), example notation,
;;;; citations, index entries and issues as anchors.

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

(defun inlines-math-piece (item kind)
  "The inlines ITEM, in the content of a KIND node in a formula, stands
for: a character its text; an ordinary noad without scripts whose
nucleus is characters and inlines (the letters of \\i{e}, the box of
\\ff{log}) what its nucleus stands for; a KIND node its content (the
{\\tt log} in \\ff's box); anything else itself."
  (cond ((not (typep item 'node)) (list item))
        ((eq (node-kind item) :math-char) (list (math-char-text item)))
        ((eq (node-kind item) kind) (copy-list (node-field-value item 'content)))
        ((and (eq (node-kind item) :math-noad)
              (eq (math-noad-class item) :ord)
              (null (math-noad-superscript item))
              (null (math-noad-subscript item))
              (math-noad-nucleus item)
              (every (lambda (part)
                       (or (stringp part)
                           (and (typep part 'node)
                                (or (eq (node-kind part) :math-char)
                                    (eq (node-kind part) kind)
                                    (member (node-kind part) (expand-kinds '(:inline)))))))
                     (math-noad-nucleus item)))
         (mapcan (lambda (part) (inlines-math-piece part kind))
                 (copy-list (math-noad-nucleus item))))
        (t (list item))))

(defun inlines-math-text (items kind)
  "ITEMS, the content of a KIND node in a formula, as inlines
(INLINES-MATH-PIECE), adjacent strings joined and the space around them
(\\ff's trailing space) trimmed."
  (let ((result '()))
    (dolist (item (mapcan (lambda (item) (inlines-math-piece item kind)) items))
      (if (and (stringp item) (stringp (first result)))
          (setf (first result) (concatenate 'string (first result) item))
          (push item result)))
    (trim-title (nreverse result))))

(defun inlines-math-only-p (items)
  "True when ITEMS hold a node that is math but no inline: what a font
command in a formula holds when its letters carry scripts
(`\\i{e}^{…}')."
  (some (lambda (item)
          (and (typep item 'node)
               (not (member (node-kind item) (expand-kinds '(:inline))))))
        items))

(defun inlines-finish-content (kind)
  "The on-close function of a container of a KIND node with content: its
items, in a formula as text (INLINES-MATH-TEXT), become the node, checked
here.  In a formula, a font command left empty is dropped: what it set
went to a script, which TeX scans as a field of its own (`$0^\\i{x}$');
one that still holds math (letters with scripts) is no node either, its
math stays in the formula: the letters' font is math italic anyway."
  (lambda (builder container)
    (let* ((in-math (find-container builder :math))
           (items (if in-math
                      (inlines-math-text (container-contents container) kind)
                      (container-contents container))))
      (setf (container-items container)
            (cond ((and in-math (null items)) '())
                  ((and in-math (inlines-math-only-p items))
                   (container-contents container))
                  (t
                   (let ((node (make-builder-node builder kind
                                                  :content items
                                                  :span (join-spans (container-span container)
                                                                    (container-closing-span container)))))
                     (dolist (problem (node-problems node (builder-registry builder)))
                       (report-problem builder :node (node-span node) :message problem))
                     (list node))))))))

(defun open-content-container (builder key span kind)
  "Open a container of KEY at SPAN for a new node of KIND whose items
go to its :CONTENT field (INLINES-FINISH-CONTENT)."
  (open-container builder key span :on-close (inlines-finish-content kind)))

(defun finish-lambda-list-keyword (builder container)
  "Set the name of the :LAMBDA-LIST-KEYWORD node of CONTAINER to the
strings its macro typeset."
  (setf (node-field-value (container-node container) :name (builder-registry builder))
        (apply #'concatenate 'string
               (remove-if-not #'stringp (container-contents container)))))

(defun reference-text-without-conditionals (text)
  "TEXT without the `\\fi' tokens (and the spaces TeX skips after each) it
holds.  A reference set in a table cell that begins with an active
character (`*' is `\\ST', a conditional) is read by TeX after the
conditional's branch, and the `\\fi's that close the conditional stay in the
cell: `*\\fi \\fi package*' is the cell `*package*'."
  (with-output-to-string (out)
    (let ((position 0) (end (length text)))
      (loop
        (let ((fi (search "\\fi" text :start2 position)))
          (cond ((null fi) (write-string text out :start position) (return))
                ((and (< (+ fi 3) end) (alpha-char-p (char text (+ fi 3))))
                 (write-string text out :start position :end (+ fi 3))
                 (setf position (+ fi 3)))
                (t
                 (write-string text out :start position :end fi)
                 (setf position (position #\Space text :start (+ fi 3) :test #'char/=))
                 (unless position (return)))))))))

(defparameter *reference-math-glyphs*
  '(("{$\\spGT $}" . ">") ("{$\\spLT $}" . "<"))
  "What a table cell's `>' and `<' (active, `\\GT' and `\\LT') leave in a
reference's argument when the cell is set bold: the math symbol the
character stands for.")

(defun reference-text (text)
  "The name a reference's last argument TEXT stands for, trimmed: without
the `\\fi's of a cell's active first character
(REFERENCE-TEXT-WITHOUT-CONDITIONALS), with the math symbols such a
character was set as (*REFERENCE-MATH-GLYPHS*) as the character."
  (let ((text (reference-text-without-conditionals text)))
    (loop for (glyph . character) in *reference-math-glyphs*
          do (loop for at = (search glyph text)
                   while at
                   do (setf text (concatenate 'string (subseq text 0 at) character
                                              (subseq text (+ at (length glyph)))))))
    (string-trim '(#\Space #\Tab #\Newline) text)))

(defun reference-code-text-p (text)
  "True when TEXT is a reference's argument set as code with `\\f' (a type
specifier, `\\f {(eql 't)}'): the reference names no entry, its content
is the code."
  (and (> (length text) 2)
       (string= "\\f" text :end2 2)
       (not (alpha-char-p (char text 2)))))

(defun open-reference (builder event key span via)
  "The handler of a reference macro of KEY: an unresolved :OPERATOR-REF
with the name its last argument sets; but no node for a reference with no
name (an empty cell of a table whose template wraps each cell in `\\misc',
set as nothing), and a :CODE for one set as code with `\\f'."
  (let ((text (reference-text (last-argument-text builder event))))
    (cond ((string= text "") (open-container builder key span))
          ((reference-code-text-p text) (open-content-container builder key span :code))
          (t (open-node-container builder key span :operator-ref :text text :via via)))))

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
                            (open-reference builder event key span via)))))
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
