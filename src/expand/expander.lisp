;;;; src/expand/expander.lisp
;;;;
;;;; The expander of one TeX job and its token-level protocol: get_next,
;;;; get_token, get_x_token and expand (TeX: The Program, §§332-366).
;;;;
;;;; A token is returned together with its meaning, as TeX sets cur_tok
;;;; with cur_cmd/cur_chr: the MEANING of a control sequence or active
;;;; character (see meaning.lisp), NIL for a character token.  A token
;;;; read through \noexpand comes back as itself with the meaning
;;;; DONT-EXPAND-MEANING when it would have expanded (§358).

(in-package #:cl-ansi-spec/expand)

(deftype scanner-status ()
  "TeX's scanner_status (§305): what is being scanned, for the \\outer and
end-of-file checks."
  '(member :normal :skipping :defining :matching :aligning :absorbing))

(defstruct (expander (:constructor %make-expander (state input job-name))
                     (:constructor %make-format-expander
                         (state input job-name frozen font-identifiers))
                     (:copier nil))
  "One TeX job: its STATE (an EXPANDER-STATE), its input stack and its
\\jobname, plus the scanner variables TeX keeps beside them."
  (state nil :type expander-state :read-only t)
  (input nil :type input-stack :read-only t)
  (job-name "" :type string :read-only t)
  (scanner-status :normal :type scanner-status)
  ;; The control sequence whose definition or use is being scanned.
  (warning-index nil)
  ;; While matching a macro's arguments: :CALL, :LONG, or :OUTER-CALL
  ;; after a runaway was reported (§§389, 339).
  (long-state :call :type (member :call :long :outer-call))
  ;; TeX's align_state: braces read minus braces closed, offset (§309).
  (align-state 1000000 :type integer)
  ;; TeX's alignment stack (§770), the innermost alignment first
  ;; (alignments.lisp).
  (alignments '() :type list)
  ;; \topmark, \firstmark, \botmark, \splitfirstmark, \splitbotmark.
  (marks (make-array 5 :initial-element nil) :read-only t)
  (name-in-progress nil :type boolean)
  ;; The control sequence \par (TeX's par_loc), cached for the checks of
  ;; every token read while matching arguments.
  (par nil)
  ;; Frozen control sequences by name, made on first use.
  (frozen (make-hash-table :test 'equal) :read-only t)
  ;; The frozen font identifier of each font \the has shown (TeX's
  ;; font_id_base + f), made on first use.
  (font-identifiers (make-hash-table :test 'equal) :read-only t)
  ;; The semantic nest, innermost list first (nest.lisp), and the page.
  (nest (list (make-list-state)) :type cons)
  (page (make-page-state) :type page-state :read-only t)
  ;; TeX's mag_set (§286): the \mag a `true' dimension first used, or 0.
  (mag-set 0 :type integer)
  ;; TeX's last_badness (§646): no box is packaged, so it stays 0.
  (last-badness 0 :type integer)
  ;; The condition stack, innermost conditional first (conditionals.lisp,
  ;; TeX's cond_ptr list with if_limit, cur_if and if_line, §489), and
  ;; the line where the current skipping began (skip_line, §493).
  (conditionals '() :type list)
  (skip-line 0 :type integer)
  ;; TeX's read_open and read_file (§480): each of the sixteen \read
  ;; streams is :CLOSED or the line source it reads (streams.lisp).
  (read-streams (make-array 16 :initial-element :closed) :read-only t)
  ;; TeX's write_open (§1342): the file name each of the sixteen \write
  ;; streams was opened on by an \immediate\openout, or NIL.
  (write-streams (make-array 16 :initial-element nil) :read-only t)
  ;; TeX's set_box_allowed (§1241): false while a \write is expanded.
  (set-box-allowed t :type boolean)
  ;; What the job printed (log.lisp), newest first.
  (log '() :type list)
  ;; The token \afterassignment saved (after_token, §1266), or NIL.
  (after-token nil)
  ;; The interaction mode last set (§1264); recorded only: every job
  ;; recovers from errors as in \batchmode.
  (interaction :error-stop :type (member :batch :nonstop :scroll :error-stop))
  ;; Hyphenation data kept as read (§§934-963): \patterns as (language
  ;; letters levels) lists, \hyphenation exceptions as (language letters
  ;; positions) lists, newest first; TeX's trie_not_ready.
  (patterns '() :type list)
  (hyphenation-exceptions '() :type list)
  (trie-not-ready t :type boolean)
  ;; How the job ended: NIL while it runs, :END after \end, :DUMP after
  ;; \dump (§1335).
  (ended nil :type (member nil :end :dump))
  ;; Observers of the job, NIL or functions (docs/vocabulary.md,
  ;; "Observers"): CALL-OBSERVER (expander token macro arguments) before a
  ;; matched macro's body is read, returning an action (NIL or :REPLACE)
  ;; and a tag; LEVEL-END-OBSERVER (expander tag) when the body of a call
  ;; given a tag ends; DEFINITION-OBSERVER (expander control-sequence
  ;; meaning span) after a definition; APPEND-OBSERVER (expander node list)
  ;; before NODE is appended to LIST.
  (call-observer nil :type (or null function))
  (level-end-observer nil :type (or null function))
  (definition-observer nil :type (or null function))
  (append-observer nil :type (or null function))
  ;; The CALL-CONTEXT of the macro call being observed, while
  ;; CALL-OBSERVER runs (CALL-ORIGIN-SPAN).
  (call-context '() :type list))

(defstruct (dont-expand-token (:include cs-token)
                              (:constructor make-dont-expand-token
                                  (control-sequence &optional span))
                              (:copier nil))
  "The token after \\noexpand, marked so that GET-NEXT suppresses its
expansion (TeX's frozen_dont_expand, §§358, 369).")

(defun dont-expand-meaning ()
  "The meaning a \\noexpand-ed expandable token has: \\relax (§358)."
  (load-time-value (make-primitive "relax" :operation :dont-expand) t))

(defun make-expander (&key (state (make-expander-state))
                           (resolver nil resolver-p)
                           (job-name ""))
  "A new TeX job over STATE (a fresh INITEX state by default), reading
through RESOLVER (default: the source search path), called JOB-NAME.
The primitives are installed in STATE."
  (let* ((input (if resolver-p
                    (make-input-stack (es-tex state) :resolver resolver)
                    (make-input-stack (es-tex state))))
         (expander (%make-expander state input job-name)))
    (install-primitives state)
    (install-input-hooks expander)))

(defun install-input-hooks (expander)
  "Make EXPANDER's input stack call back into it at the end of a file (the
\\outer check, §362), of a u template (§324) and of an observed macro
body; return EXPANDER."
  (let ((input (expander-input expander)))
    (setf (input-stack-file-end-hook input)
          (lambda (stack name)
            (declare (ignore stack name))
            (check-outer-validity expander nil)))
    (setf (input-stack-u-template-end-hook input)
          (lambda (stack)
            (declare (ignore stack))
            (end-u-template expander)))
    (setf (input-stack-level-end-hook input)
          (lambda (stack tag)
            (declare (ignore stack))
            (end-observed-body expander tag))))
  expander)

(defun expander-tex (expander)
  "The reader state of EXPANDER."
  (es-tex (expander-state expander)))

(defun frozen-control-sequence (expander name)
  "EXPANDER's frozen copy of the primitive NAME (\"relax\", \"fi\",
\"cr\", ...), which no definition can change (§222)."
  (let ((table (expander-frozen expander)))
    (or (gethash name table)
        (let ((cs (make-frozen-control-sequence name)))
          (set-meaning (expander-state expander) cs (find-primitive name)
                       :global t)
          (setf (gethash name table) cs)))))

(defun named-token (expander name &optional span)
  "A token for the control sequence NAME of EXPANDER's state."
  (make-cs-token (intern-control-sequence (expander-tex expander) name) span))

(defun par-token-p (expander token)
  "True when TOKEN is TeX's par_token: the control sequence \\par, whatever
its meaning."
  (and (cs-token-p token)
       (eq (cs-token-control-sequence token)
           (or (expander-par expander)
               (setf (expander-par expander)
                     (intern-control-sequence (expander-tex expander) "par"))))))

(defun character-catcode-p (token catcode)
  "True when TOKEN is a character token of category CATCODE."
  (and (character-token-p token) (= (character-token-catcode token) catcode)))

(defun expandable-p (token meaning)
  "True when TOKEN with MEANING expands: a macro, an expandable primitive,
or an undefined control sequence (which expansion reports, §366)."
  (and (cs-token-p token)
       (or (null meaning)
           (macro-p meaning)
           (and (primitive-p meaning) (primitive-expandable-p meaning)))))

;;; Reading tokens

(defun get-next (expander)
  "TeX's get_next (§341): the next token of the input and its meaning, or
NIL at the end of all input.  Keeps align_state, suppresses the expansion
of a \\noexpand-ed token, checks an \\outer macro (or \\endtemplate)
against the scanner status, and at the end of an alignment entry inserts
its v template (§342) and reads on."
  (loop
    (multiple-value-bind (token meaning) (read-next-token expander)
      (if (and (zerop (expander-align-state expander)) token
               (entry-end-kind token meaning))
          (insert-v-template expander token meaning)
          (return (values token meaning))))))

(defun read-next-token (expander)
  "The next token of the input and its meaning, as GET-NEXT reads it
before it looks for the end of an alignment entry."
  (let ((token (next-token (expander-input expander)))
        (state (expander-state expander)))
    (typecase token
      (null (values nil nil))
      (dont-expand-token
       (let* ((cs (cs-token-control-sequence token))
              (plain (make-cs-token cs (token-span token)))
              (meaning (meaning state cs)))
         (values plain (if (expandable-p plain meaning)
                           (dont-expand-meaning)
                           meaning))))
      (cs-token
       (let ((meaning (meaning state (cs-token-control-sequence token))))
         (if (and (or (and (macro-p meaning) (macro-outer-p meaning))
                      (eq meaning (end-template-meaning)))
                  (not (eq (expander-scanner-status expander) :normal)))
             (values (check-outer-validity expander token) nil)
             (values token meaning))))
      (t
       (cond ((character-catcode-p token +begin-group+)
              (incf (expander-align-state expander)))
             ((character-catcode-p token +end-group+)
              (decf (expander-align-state expander))))
       (values token nil)))))

(defun get-token (expander)
  "TeX's get_token: GET-NEXT, without expansion.  (TeX's two differ only
in setting cur_tok, which here is always the token returned.)"
  (get-next expander))

(defun back-token (expander token)
  "TeX's back_input (§325): TOKEN is read next; align_state is restored,
after the exhausted lists are removed (so after the end of a u template
has set it).  Returns TOKEN."
  (when token
    (back-input (expander-input expander) token)
    (cond ((character-catcode-p token +begin-group+)
           (decf (expander-align-state expander)))
          ((character-catcode-p token +end-group+)
           (incf (expander-align-state expander))))
    token))

(defun insert-tokens (expander tokens)
  "TeX's ins_list: TOKENS are read next, as an inserted list."
  (when tokens
    (push-tokens (expander-input expander) tokens :inserted)))

(defun get-x-token (expander)
  "TeX's get_x_token (§380): the next unexpandable token and its meaning,
expanding macros and expandable primitives on the way; NIL at the end of
all input."
  (loop
    (multiple-value-bind (token meaning) (get-next expander)
      (cond ((null token) (return (values nil nil)))
            ;; §380: \endtemplate is endv at once.
            ((eq meaning (end-template-meaning))
             (return (values (frozen-template-token expander :endv
                                                    (token-span token))
                             (endv-meaning))))
            ((expandable-p token meaning) (expand expander token meaning))
            (t (return (values token meaning)))))))

(defun expand (expander token meaning)
  "TeX's expand (§366): expand TOKEN, whose MEANING is expandable."
  (cond ((null meaning)
         (tex-error "Undefined control sequence"
                    :context (cs-name-text expander (cs-token-control-sequence token))
                    :span (token-span token)))
        ((macro-p meaning) (macro-call expander token meaning))
        (t (funcall (primitive-operation meaning) expander token))))

(defun get-token-normally (expander)
  "GET-TOKEN with the scanner status :NORMAL, so that an \\outer macro is
allowed, as \\noexpand, \\string and \\meaning read their token (§§367, 470)."
  (let ((saved (expander-scanner-status expander)))
    (setf (expander-scanner-status expander) :normal)
    (unwind-protect (get-token expander)
      (setf (expander-scanner-status expander) saved))))

;;; Runaways (§§336-339)

(defun check-outer-validity (expander token)
  "TeX's check_outer_validity: an \\outer macro TOKEN, or the end of a file
when TOKEN is NIL, met while the scanner is not :NORMAL.  Reports the
runaway and inserts what TeX inserts to end it; TOKEN is put back to be
read again, unless it came from a line of \\read.  Returns the token to use instead: a space (or NIL)."
  (let ((status (expander-scanner-status expander))
        (span (and token (token-span token))))
    (when (eq status :normal)
      (return-from check-outer-validity token))
    ;; §339: a token read from a line of \read is not read again.
    (when (and token (not (reading-line-p (expander-input expander))))
      (back-input (expander-input expander) token))
    (if (eq status :skipping)
        (progn
          (insert-tokens expander
                         (list (make-cs-token
                                (frozen-control-sequence expander "fi") span)))
          (tex-error "Incomplete"
                     :context (incomplete-conditional-text expander)
                     :span span))
        (let ((brace (make-character-token (char-code #\}) +end-group+ span)))
          (insert-tokens
           expander
           (ecase status
             ((:defining :absorbing) (list brace))
             (:matching (setf (expander-long-state expander) :outer-call)
              (list (named-token expander "par" span)))
             (:aligning (setf (expander-align-state expander) -1000000)
              (list (make-cs-token (frozen-control-sequence expander "cr") span)
                    brace))))
          (tex-error (if token
                         "Forbidden control sequence found"
                         "File ended")
                     :context (format nil "while scanning ~A of ~A"
                                      (ecase status
                                        (:defining "definition")
                                        (:matching "use")
                                        (:aligning "preamble")
                                        (:absorbing "text"))
                                      (let ((cs (expander-warning-index expander)))
                                        (if cs (cs-name-text expander cs) "?")))
                     :span span)))
    (and token (make-character-token 32 +space+ span))))

(defun current-list (expander)
  "The innermost level of EXPANDER's semantic nest, a LIST-STATE."
  (first (expander-nest expander)))
