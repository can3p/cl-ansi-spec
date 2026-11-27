;;;; src/expand/alignments.lisp
;;;;
;;;; Alignments (TeX: The Program, §§768-812, 1126-1131, 1206): \halign
;;;; and \valign as TeX carries them out.  init_align reads the preamble
;;;; into columns of u and v templates and \tabskip glue; align_peek
;;;; starts each row (or takes \noalign, \crcr, or the `}' that ends the
;;;; alignment); each entry is its column's u template, the entry's own
;;;; tokens and its v template, which get_next inserts when `&', \span or
;;;; \cr comes at align_state 0 (expander.lisp), and which ends with the
;;;; frozen \endtemplate; endv (do_endv) then ends the entry (fin_col)
;;;; and, at \cr, the row (fin_row).  The templates are levels of the
;;;; input stack, :U-TEMPLATE and :V-TEMPLATE; the end of a u template
;;;; sets align_state to 0 (END-U-TEMPLATE, §324).
;;;;
;;;; No column widths and no packaging (docs/tex-fidelity.md, "Not
;;;; emulated"): an alignment becomes one :ALIGNMENT node of the
;;;; enclosing list, holding its preamble as scanned, its :ROW nodes
;;;; (each holding :CELL nodes) and its :NO-ALIGN material
;;;; (docs/events.md).

(in-package #:cl-ansi-spec/expand)

(defstruct (align-column (:constructor make-align-column (u v))
                         (:copier nil))
  "A column of an alignment's preamble (TeX's alignrecord, §770): its U
and V templates (token lists, V ending with the frozen \\endtemplate) and
the TABSKIP glue after it."
  (u '() :type list :read-only t)
  (v '() :type list :read-only t)
  (tabskip nil))

(defstruct (alignment (:constructor make-alignment
                          (command span saved-align-state))
                      (:copier nil))
  "One alignment in progress, an entry of TeX's alignment stack with the
variables it saves (§§770-772).  COMMAND is \"halign\" or \"valign\",
SPAN the command's; SAVED-ALIGN-STATE is align_state when it began.
TABSKIP is the glue before the first column and COLUMNS the preamble (a
vector of ALIGN-COLUMNs), of which the first SCANNED were scanned and
the rest repeat; REPEAT-FROM is the first column `&&' repeats and LOOP
the column the next repetition copies (TeX's cur_loop), both NIL
without `&&'.  CUR-ALIGN and CUR-SPAN are the current
column and the one its entry began in (TeX's cur_align and cur_span),
CUR-ALIGN NIL until the first row.  OMIT tells that the current column's
templates are omitted, OMITTED lists the omitted columns of the entry
(newest first), ENTRY-END is how the entry ended (:TAB, :SPAN, :CR or
:CRCR, TeX's extra_info) and END-SPAN where.  CELL-SPAN and ROW-SPAN are
where the entry and the row began; ROWS counts the rows; NO-ALIGNS are
(rows span end-span) for each \\noalign, newest first."
  (command "halign" :type string :read-only t)
  (span nil :read-only t)
  (saved-align-state 0 :type integer :read-only t)
  (tabskip nil)
  (columns (make-array 0 :adjustable t :fill-pointer t) :read-only t)
  (scanned 0 :type integer)
  (repeat-from nil :type (or null integer))
  (loop nil :type (or null integer))
  (cur-align nil :type (or null integer))
  (cur-span 0 :type integer)
  (omit nil :type boolean)
  (omitted '() :type list)
  (entry-end nil :type (member nil :tab :span :cr :crcr))
  (end-span nil)
  (cell-span nil)
  (row-span nil)
  (rows 0 :type integer)
  (no-aligns '() :type list))

(defun current-alignment (expander)
  "The innermost alignment of EXPANDER, or NIL."
  (first (expander-alignments expander)))

(defun halign-p (alignment)
  "True when ALIGNMENT is an \\halign."
  (string= (alignment-command alignment) "halign"))

(defun current-column (alignment)
  "The ALIGN-COLUMN of ALIGNMENT's current column."
  (aref (alignment-columns alignment) (alignment-cur-align alignment)))

;;; \endtemplate (§§375, 380, 780, 1130)

(defun end-template-meaning ()
  "The meaning of the frozen \\endtemplate that ends every v template
(TeX's end_template): it expands to the endv one, and counts as \\outer
when the scanner is not :NORMAL."
  (load-time-value
   (make-primitive "endtemplate"
                   :expandable-p t
                   :operation (lambda (expander token)
                                (back-token expander
                                            (frozen-template-token expander :endv
                                                                   (token-span token)))))
   t))

(defun endv-meaning ()
  "The meaning of the other frozen \\endtemplate (TeX's endv), main
control's do_endv."
  (load-time-value
   (make-primitive "endv"
                   :operation (lambda (expander token meaning)
                                (declare (ignore meaning))
                                (do-endv expander token)))
   t))

(defun frozen-template-token (expander which span)
  "A token at SPAN of EXPANDER's frozen \\endtemplate of meaning WHICH,
:END-TEMPLATE or :ENDV, made on first use."
  (let* ((table (expander-frozen expander))
         (key (ecase which (:end-template "endtemplate") (:endv "endv")))
         (cs (or (gethash key table)
                 (let ((cs (make-frozen-control-sequence "endtemplate")))
                   (set-meaning (expander-state expander) cs
                                (if (eq which :endv) (endv-meaning) (end-template-meaning))
                                :global t)
                   (setf (gethash key table) cs)))))
    (make-cs-token cs span)))

;;; The ends of entries (§§324, 342, 789)

(defun entry-end-kind (token meaning)
  "What TOKEN with MEANING ends an alignment entry as, or NIL: :TAB for
`&' (TeX's tab_mark), :SPAN, :CR or :CRCR (car_ret)."
  (cond ((eql (command-catcode token meaning) +alignment-tab+) :tab)
        ((not (primitive-p meaning)) nil)
        ((primitive-named-p meaning "span") :span)
        ((primitive-named-p meaning "cr") :cr)
        ((primitive-named-p meaning "crcr") :crcr)))

(defun interwoven-error ()
  "TeX's fatal error when alignments and their templates are out of step."
  (tex-fatal-error "(interwoven alignment preambles are not allowed)"))

(defun end-u-template (expander)
  "§324: a u template has been read; its entry's own tokens follow, at
align_state 0."
  (if (> (expander-align-state expander) 500000)
      (setf (expander-align-state expander) 0)
      (interwoven-error)))

(defun insert-v-template (expander token meaning)
  "§789: TOKEN with MEANING ends the current entry at align_state 0; it is
dropped, and its column's v template is read instead (the omit template,
\\endtemplate alone, after \\omit)."
  (let ((alignment (current-alignment expander)))
    (when (or (eq (expander-scanner-status expander) :aligning)
              (null alignment) (null (alignment-cur-align alignment)))
      (interwoven-error))
    (setf (alignment-entry-end alignment) (entry-end-kind token meaning)
          (alignment-end-span alignment) (token-span token))
    (push-tokens (expander-input expander)
                 (if (alignment-omit alignment)
                     (list (frozen-template-token expander :end-template
                                                  (token-span token)))
                     (align-column-v (current-column alignment)))
                 :v-template)
    (setf (expander-align-state expander) 1000000)))

;;; The preamble (§§774-784)

(defun parameter-command-p (token meaning)
  "True when TOKEN with MEANING is a `#' (TeX's mac_param)."
  (eql (command-catcode token meaning) +parameter+))

(defun get-preamble-token (expander)
  "TeX's get_preamble_token (§782): the next token of the preamble,
without expansion, but a token after \\span is expanded once and
\\tabskip assignments are carried out."
  (loop
    (multiple-value-bind (token meaning) (get-token expander)
      (loop while (primitive-named-p meaning "span")
            do (multiple-value-setq (token meaning) (get-token expander))
               (when (and token (expandable-p token meaning))
                 (expand expander token meaning)
                 (multiple-value-setq (token meaning) (get-token expander))))
      (when (eq meaning (endv-meaning))
        (interwoven-error))
      (if (primitive-named-p meaning "tabskip")
          (progn (scan-optional-equals expander)
                 (set-parameter (expander-state expander) :tabskip
                                (scan-glue expander :glue)))
          (return (values token meaning))))))

(defun preamble-delimiter-p (expander token meaning)
  "True when TOKEN with MEANING ends a template: `&' or \\cr at the
preamble's own brace level."
  (and token (= (expander-align-state expander) -1000000)
       (member (entry-end-kind token meaning) '(:tab :cr :crcr))))

(defun scan-u-template (expander alignment)
  "§783: the tokens of a u template, up to its `#', leading blanks
dropped.  A `&' first makes the columns from this one on repeat; a
template ended without `#' is `Missing # inserted in alignment
preamble'."
  (let ((tokens '()))
    (loop
      (multiple-value-bind (token meaning) (get-preamble-token expander)
        (cond ((or (null token) (parameter-command-p token meaning))
               (return))
              ((preamble-delimiter-p expander token meaning)
               (if (and (null tokens) (null (alignment-loop alignment))
                        (eq (entry-end-kind token meaning) :tab))
                   (setf (alignment-loop alignment)
                         (fill-pointer (alignment-columns alignment))
                         (alignment-repeat-from alignment)
                         (alignment-loop alignment))
                   (progn
                     (back-token expander token)
                     (tex-error "Missing # inserted in alignment preamble"
                                :span (token-span token))
                     (return))))
              ((or tokens (not (blank-p token meaning)))
               (push token tokens)))))
    (nreverse tokens)))

(defun scan-v-template (expander)
  "§784: the tokens of a v template, up to its `&' or \\cr, with the
frozen \\endtemplate at its end; another `#' is `Only one # is allowed
per tab' and dropped.  Returns the tokens and what ended them (see
ENTRY-END-KIND)."
  (let ((tokens '()))
    (loop
      (multiple-value-bind (token meaning) (get-preamble-token expander)
        (cond ((null token)
               (return (values (nreverse tokens) :cr)))
              ((preamble-delimiter-p expander token meaning)
               (return (values (nreverse (cons (frozen-template-token
                                                expander :end-template
                                                (token-span token))
                                               tokens))
                               (entry-end-kind token meaning))))
              ((parameter-command-p token meaning)
               (tex-error "Only one # is allowed per tab" :span (token-span token)))
              (t (push token tokens)))))))

(defun scan-preamble (expander alignment cs)
  "§777: read the preamble of ALIGNMENT, whose command is the control
sequence CS, up to its \\cr, recording each column's templates and the
\\tabskip glue before and after it."
  (let ((state (expander-state expander))
        (columns (alignment-columns alignment)))
    (setf (expander-scanner-status expander) :aligning
          (expander-warning-index expander) cs
          (expander-align-state expander) -1000000
          (alignment-tabskip alignment) (parameter state :tabskip))
    (loop
      (let ((u (scan-u-template expander alignment)))
        (multiple-value-bind (v end) (scan-v-template expander)
          (vector-push-extend (make-align-column u v) columns)
          (setf (align-column-tabskip (aref columns (1- (fill-pointer columns))))
                (parameter state :tabskip))
          (unless (eq end :tab)
            (return)))))
    (setf (alignment-scanned alignment) (fill-pointer columns)
          (expander-scanner-status expander) :normal)))

(defun init-align (expander token meaning)
  "TeX's init_align (§774) for the command TOKEN with MEANING: a new
alignment, a new list (internal vertical for \\halign, restricted
horizontal for \\valign), `to' or `spread', the preamble, then
\\everycr and the first row."
  (let* ((list (current-list expander))
         (mode (list-state-mode list))
         (alignment (make-alignment (primitive-name meaning) (token-span token)
                                    (expander-align-state expander))))
    (push alignment (expander-alignments expander))
    (setf (expander-align-state expander) -1000000)
    ;; §776
    (when (and (eq mode :display-math)
               (or (list-state-contents list) (list-state-incompleat list)))
      (tex-error (format nil "Improper ~A inside $$'s" (esc expander "halign"))
                 :span (token-span token))
      (setf (list-state-contents list) '()
            (list-state-incompleat list) nil))
    ;; §775
    (push-nest expander (case mode
                          ((:vertical :display-math) :internal-vertical)
                          (:horizontal :restricted-horizontal)
                          (t mode))
               (token-span token))
    (when (eq mode :display-math)
      (setf (list-state-prev-depth (current-list expander))
            (list-state-prev-depth (third (expander-nest expander)))))
    (scan-spec expander :align nil token meaning)
    (scan-preamble expander alignment (and (cs-token-p token)
                                           (cs-token-control-sequence token)))
    (new-save-level expander :align)
    (begin-token-list expander (parameter (expander-state expander) :everycr)
                      :every-cr)
    (align-peek expander)))

;;; Rows and entries (§§785-799)

(defun align-peek (expander)
  "TeX's align_peek (§785): after blanks, \\noalign begins its group,
`}' ends the alignment, \\crcr is ignored, and anything else begins a
row, as the first token of its first entry."
  (loop
    (setf (expander-align-state expander) 1000000)
    (multiple-value-bind (token meaning) (get-x-nonblank expander)
      (cond ((null token) (return))
            ((primitive-named-p meaning "noalign")
             (let ((alignment (current-alignment expander)))
               (push (list (alignment-rows alignment) (token-span token) nil)
                     (alignment-no-aligns alignment)))
             (scan-left-brace expander)
             (new-save-level expander :no-align)
             (when (eq (current-mode expander) :internal-vertical)
               (normal-paragraph expander))
             (return))
            ((eql (command-catcode token meaning) +end-group+)
             (fin-align expander token)
             (return))
            ((primitive-named-p meaning "crcr"))
            (t
             (init-row expander (token-span token))
             (init-col expander token meaning)
             (return))))))

(defun end-no-align (expander token)
  "§1133: the `}' TOKEN ends a \\noalign group."
  (end-graf expander (token-span token))
  (unsave expander)
  (setf (third (first (alignment-no-aligns (current-alignment expander))))
        (token-span token))
  (align-peek expander))

(defun init-row (expander span)
  "TeX's init_row (§786): a row begun at SPAN, a list of the other
orientation (restricted horizontal in an \\halign), and its first
entry."
  (let ((alignment (current-alignment expander)))
    (push-nest expander (if (eq (current-mode expander) :internal-vertical)
                            :restricted-horizontal
                            :internal-vertical)
               span)
    (let ((list (current-list expander)))
      (if (eq (list-state-mode list) :restricted-horizontal)
          (setf (list-state-space-factor list) 0)
          (setf (list-state-prev-depth list) 0)))
    (setf (alignment-cur-align alignment) 0
          (alignment-row-span alignment) span)
    (init-span expander 0)))

(defun init-span (expander column)
  "TeX's init_span (§787): the list of an entry beginning in COLUMN."
  (let ((alignment (current-alignment expander)))
    (push-nest expander (current-mode expander))
    (if (eq (current-mode expander) :restricted-horizontal)
        (setf (list-state-space-factor (current-list expander)) 1000)
        (progn (setf (list-state-prev-depth (current-list expander)) +ignore-depth+)
               (normal-paragraph expander)))
    (setf (alignment-cur-span alignment) column
          (alignment-omitted alignment) '()
          (alignment-cell-span alignment) nil)))

(defun init-col (expander token meaning)
  "TeX's init_col (§788): the current column begins with TOKEN, peeked
at.  After \\omit its tokens come at once (align_state 0); otherwise
TOKEN is read again, after the column's u template."
  (let ((alignment (current-alignment expander))
        (omit (primitive-named-p meaning "omit")))
    (unless (alignment-cell-span alignment)
      (setf (alignment-cell-span alignment) (and token (token-span token))))
    (setf (alignment-omit alignment) omit)
    (if omit
        (progn (push (1+ (alignment-cur-align alignment)) (alignment-omitted alignment))
               (setf (expander-align-state expander) 0))
        (progn (back-token expander token)
               (push-tokens (expander-input expander)
                            (align-column-u (current-column alignment))
                            :u-template)))))

(defun do-endv (expander token)
  "TeX's do_endv (§1131): the v template of the current entry has been
read.  In an entry's group the entry ends (and at \\cr its row); in any
other group what ends that group is inserted first."
  (unless (v-template-ended-p (expander-input expander))
    (interwoven-error))
  (if (eq (current-group-code expander) :align)
      (progn (end-graf expander (token-span token))
             (when (fin-col expander)
               (fin-row expander)))
      (off-save expander token (endv-meaning))))

(defun lengthen-preamble (alignment)
  "§793: a copy of the column LOOP of ALIGNMENT, and of the glue after
it, becomes the preamble's next column."
  (let* ((columns (alignment-columns alignment))
         (source (aref columns (alignment-loop alignment)))
         (copy (make-align-column (align-column-u source) (align-column-v source))))
    (setf (align-column-tabskip copy) (align-column-tabskip source))
    (vector-push-extend copy columns)
    (incf (alignment-loop alignment))))

(defun cell-node (alignment list)
  "The :CELL node of LIST, the current entry of ALIGNMENT, which ends
now.  Its VALUE is the kind of box TeX would make of it (§§795, 810)."
  (let* ((first (alignment-cur-span alignment))
         (columns (1+ (- (alignment-cur-align alignment) first))))
    (make-node :cell
               :properties (append (list :column (1+ first))
                                   (and (> columns 1) (list :columns columns))
                                   (and (alignment-omitted alignment)
                                        (list :omit (reverse (alignment-omitted alignment)))))
               :value (if (halign-p alignment) :hbox :vbox)
               :children (list-nodes list)
               :span (alignment-cell-span alignment)
               :end-span (alignment-end-span alignment))))

(defun fin-col (expander)
  "TeX's fin_col (§791): the current column ends.  Unless it was ended by
\\span, its entry becomes a cell of the row; true at the end of the
row, else the next column begins with the next non-blank token."
  (let* ((alignment (current-alignment expander))
         (next (1+ (alignment-cur-align alignment))))
    (when (< (expander-align-state expander) 500000)
      (interwoven-error))
    ;; §792
    (when (and (= next (fill-pointer (alignment-columns alignment)))
               (member (alignment-entry-end alignment) '(:tab :span)))
      (if (alignment-loop alignment)
          (lengthen-preamble alignment)
          (progn
            (setf (alignment-entry-end alignment) :cr)
            (tex-error (format nil "Extra alignment tab has been changed to ~A"
                               (esc expander "cr"))
                       :span (alignment-end-span alignment)))))
    (unless (eq (alignment-entry-end alignment) :span)
      (unsave expander)
      (new-save-level expander :align)
      (append-node expander (cell-node alignment (pop-nest expander)))
      (when (member (alignment-entry-end alignment) '(:cr :crcr))
        (return-from fin-col t))
      (init-span expander next))
    (setf (expander-align-state expander) 1000000)
    (multiple-value-bind (token meaning) (get-x-nonblank expander)
      (setf (alignment-cur-align alignment) next)
      (init-col expander token meaning))
    nil))

(defun fin-row (expander)
  "TeX's fin_row (§799): the row ends, a :ROW node of the alignment's
list; then \\everycr, and align_peek."
  (let* ((alignment (current-alignment expander))
         (row (pop-nest expander))
         (list (current-list expander)))
    (append-node expander (make-node :row :children (list-nodes row)
                                          :span (alignment-row-span alignment)
                                          :end-span (alignment-end-span alignment)))
    ;; No dimensions: a row's depth is 0.
    (if (halign-p alignment)
        (setf (list-state-prev-depth list) 0)
        (setf (list-state-space-factor list) 1000))
    (incf (alignment-rows alignment))
    (begin-token-list expander (parameter (expander-state expander) :everycr)
                      :every-cr)
    (align-peek expander)))

;;; The end (§§800, 812, 1206)

(defun alignment-children (alignment nodes)
  "The children of ALIGNMENT's node, from NODES, its list: the rows, and
between them the material of the \\noaligns there, as one :NO-ALIGN node
spanned from the first \\noalign to the last one's `}'."
  (let ((children '()) (pending '()) (rows 0)
        (records (reverse (alignment-no-aligns alignment))))
    (flet ((flush ()
             (let ((here (remove rows records :key #'first :test #'/=)))
               (when (or here pending)
                 (push (make-node :no-align :children (nreverse pending)
                                            :span (second (first here))
                                            :end-span (third (car (last here))))
                       children)
                 (setf pending '())))))
      (dolist (node nodes)
        (if (eq (node-kind node) :row)
            (progn (flush) (push node children) (incf rows))
            (push node pending)))
      (flush))
    (nreverse children)))

(defun alignment-properties (alignment spec display)
  "The properties of ALIGNMENT's node: its command, whether it is a
DISPLAY, its SPEC (as a box's), and its preamble as scanned."
  (destructuring-bind (spec-kind amount) spec
    (append (list :command (alignment-command alignment))
            (and display (list :display t))
            (and (or (eq spec-kind :exactly) (/= amount 0))
                 (list :spec (list spec-kind (format-dimen amount))))
            (list :tabskip (format-glue (alignment-tabskip alignment))
                  :preamble (loop for column across (alignment-columns alignment)
                                 repeat (alignment-scanned alignment)
                                 collect (list :u (align-column-u column)
                                               :v (butlast (align-column-v column))
                                               :tabskip (format-glue
                                                         (align-column-tabskip column)))))
            (let ((first (alignment-repeat-from alignment)))
              (and first (list :loop (1+ first)))))))

(defun fin-align (expander token)
  "TeX's fin_align (§800) at the `}' TOKEN: the alignment's groups and
list end, and its node goes into the enclosing list, or, in a display,
ends the display (§1206)."
  (let ((alignment (current-alignment expander)))
    (unsave expander)
    (let ((spec (group-record-spec (unsave expander))))
      (pop (expander-alignments expander))
      (setf (expander-align-state expander) (alignment-saved-align-state alignment))
      (let* ((list (pop-nest expander))
             (display (eq (current-mode expander) :display-math))
             (node (make-node :alignment
                              :properties (alignment-properties alignment spec display)
                              :children (alignment-children alignment (list-nodes list))
                              :span (alignment-span alignment)
                              :end-span (token-span token))))
        (if display
            (finish-display-alignment expander node list)
            (let ((outer (current-list expander)))
              (append-node expander node)
              ;; §812: aux goes on.
              (if (halign-p alignment)
                  (setf (list-state-prev-depth outer) (list-state-prev-depth list))
                  (setf (list-state-space-factor outer) (list-state-space-factor list)
                        (list-state-clang outer) (list-state-clang list)))
              (when (eq (current-mode expander) :vertical)
                (build-page expander))))))))

(defun finish-display-alignment (expander node list)
  "§1206: the alignment NODE, whose list was LIST, ends a display, after
assignments; `$$' must follow (`Missing $$ inserted')."
  (multiple-value-bind (token meaning) (do-assignments expander)
    (let ((end-span (node-end-span node)))
      (if (eql (command-catcode token meaning) +math-shift+)
          (setf end-span (check-display-end expander (token-span token)))
          (progn (back-token expander token)
                 (tex-error "Missing $$ inserted" :span (and token (token-span token)))))
      (pop-nest expander)
      (append-node expander node)
      (setf (list-state-prev-depth (current-list expander)) (list-state-prev-depth list))
      (resume-after-display expander end-span))))

;;; The commands (§§1126-1130)

(define-command ("halign" "valign") (expander token meaning)
  ;; §1130: \halign in vertical mode, \valign in horizontal mode (the
  ;; mode cases send the others away), \halign alone in a display.
  (if (eq (mode-kind (current-mode expander)) :math)
      (when (privileged-p expander token meaning)
        (if (eq (current-group-code expander) :math-shift)
            (init-align expander token meaning)
            (off-save expander token meaning)))
      (init-align expander token meaning)))

(defun align-error (expander token meaning)
  "TeX's align_error (§1127): `&', \\span or \\cr outside an entry.  Near
an entry's brace level a brace is inserted to reach it; elsewhere it is
`Misplaced' and dropped."
  (let ((state (expander-align-state expander))
        (span (token-span token)))
    (if (> (abs state) 2)
        (tex-error "Misplaced" :context (meaning-text expander token meaning) :span span)
        (let ((left (minusp state)))
          (back-token expander token)
          (insert-tokens expander
                         (list (if left
                                   (make-character-token (char-code #\{) +begin-group+ span)
                                   (make-character-token (char-code #\}) +end-group+ span))))
          (tex-error (if left "Missing { inserted" "Missing } inserted") :span span)))))

(define-command ("span" "cr" "crcr") (expander token meaning)
  (align-error expander token meaning))

(define-command ("noalign" "omit") (expander token meaning)
  ;; no_align_error and omit_error (§1129)
  (tex-error "Misplaced" :context (esc expander name) :span (token-span token)))

(defun missing-cr-error (expander token)
  "§1132: the `}' TOKEN within an entry: \\cr is inserted before it."
  (back-token expander token)
  (insert-tokens expander (list (make-cs-token (frozen-control-sequence expander "cr")
                                               (token-span token))))
  (tex-error (format nil "Missing ~A inserted" (esc expander "cr"))
             :span (token-span token)))
