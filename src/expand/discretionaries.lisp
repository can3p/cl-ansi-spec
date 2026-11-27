;;;; src/expand/discretionaries.lisp
;;;;
;;;; Discretionaries and accents (TeX: The Program, §§1117-1125).
;;;; \- and \discretionary append a :DISCRETIONARY node, whose children
;;;; are its non-empty lists, each a composite node: (:PRE-BREAK ...),
;;;; (:POST-BREAK ...) and (:NO-BREAK ...).  TeX puts the no-break list
;;;; after the disc node, counted by its replace_count (§1120); nesting it
;;;; is the same to every command that reads the list's end: the
;;;; node's VISIBLE-TAIL is the no-break list's last node, and
;;;; PROTECTED-TAIL-P keeps \unkern and \lastbox from taking it (§§1080,
;;;; 1105).  \discretionary reads its three lists in disc groups, each a
;;;; restricted horizontal list, pruned of what a discretionary may not
;;;; hold (§1121).  \accent appends an :ACCENT node holding the accent
;;;; and, when one follows, the accented character, each a :TEXT node of
;;;; its own font; without metrics TeX's kerns between them are 0 and
;;;; are not kept.

(in-package #:cl-ansi-spec/expand)

(defconstant +max-replace-count+ 255
  "TeX's max_quarterword: the longest no-break list (§1120).")

(defparameter *disc-list-kinds* #(:pre-break :post-break :no-break)
  "The kinds of a discretionary's lists, by TeX's saved(-1) (§1119).")

;;; \- and \discretionary (§§1117-1121)

(defun begin-disc-list (expander disc index)
  "Read list INDEX (0, 1 or 2, see *DISC-LIST-KINDS*) of the
discretionary node DISC: a disc group, its `{' and a restricted
horizontal list (§§1117, 1119)."
  (new-save-level expander :disc :context disc :spec index)
  (scan-left-brace expander)
  (push-nest expander :restricted-horizontal (node-span disc))
  (setf (list-state-space-factor (current-list expander)) 1000))

(define-command ("-" "discretionary") (expander token meaning)
  ;; §1117: the disc node first; \- pre-breaks the font's \hyphenchar
  ;; when it is a character code.
  (let* ((span (token-span token))
         (disc (append-node expander (make-node :discretionary
                                                :properties (list :command name)
                                                :children '() :span span))))
    (if (string= name "-")
        (let ((font (current-font (expander-state expander))))
          (when (<= 0 (tex-font-hyphen-char font) 255)
            (setf (node-children disc)
                  (list (make-node :pre-break
                                   :children (list (character-node
                                                    (tex-font-hyphen-char font) span
                                                    (font-style-name font)))
                                   :span span)))))
        (begin-disc-list expander disc 0))))

(defun proper-disc-node-p (node)
  "True when a discretionary's list may hold NODE (§1121): a character,
a box (the indentation is one), a rule or a kern."
  (and (member (node-kind node) '(:text :box :indent :rule :kern)) t))

(defun prune-disc-list (expander nodes)
  "§1121: NODES up to the first one a discretionary may not hold; that
one and the rest are deleted, with `Improper discretionary list' and
TeX's diagnostic in the log."
  (let ((bad (position-if-not #'proper-disc-node-p nodes)))
    (if (null bad)
        nodes
        (let ((deleted (nthcdr bad nodes)))
          (tex-error "Improper discretionary list" :span (node-span (first deleted)))
          (log-message expander :diagnostic
                       (format nil "The following discretionary sublist has been deleted:~A"
                               (show-box-text expander deleted))
                       :span (node-span (first deleted)))
          (subseq nodes 0 bad)))))

(defun disc-list-length (nodes)
  "The number of TeX's nodes in NODES: one per character of a :TEXT
node."
  (loop for node in nodes
        sum (if (eq (node-kind node) :text) (length (node-value node)) 1)))

(defun build-discretionary (expander token)
  "TeX's build_discretionary (§§1119-1121), at the `}' TOKEN of a disc
group: the list is pruned and becomes one of the disc node's, and the
next list is read.  A no-break list is `Illegal math \\discretionary'
in math, and dropped; one of more than 255 nodes is `Discretionary list
is too long', and its nodes follow the disc node as ordinary ones."
  (let* ((group (unsave expander))
         (disc (group-record-context group))
         (index (group-record-spec group))
         (nodes (prune-disc-list expander (list-nodes (pop-nest expander))))
         (span (token-span token)))
    (flet ((attach ()
             (when nodes
               (setf (node-children disc)
                     (append (node-children disc)
                             (list (make-node (aref *disc-list-kinds* index)
                                              :children nodes :span (node-span disc)
                                              :end-span span)))))))
      (if (< index 2)
          (progn (attach)
                 (begin-disc-list expander disc (1+ index)))
          (let ((n (disc-list-length nodes)))
            (cond ((and (plusp n) (eq (mode-kind (current-mode expander)) :math))
                   (tex-error (format nil "Illegal math ~A" (esc expander "discretionary"))
                              :span span))
                  ((<= n +max-replace-count+) (attach))
                  (t
                   (tex-error "Discretionary list is too long" :span span)
                   (dolist (node nodes)
                     (append-node expander node)))))))))

;;; \accent (§§1122-1125)

(defun accent-base-code (expander token meaning)
  "The character code of the accented character that TOKEN with MEANING
begins (§1124): a character, a \\chardef or \\char and its number; else
NIL, and TOKEN is read again."
  (let ((key (command-key token meaning)))
    (cond ((member key '(:letter :other-char))
           (if (character-meaning-p meaning)
               (character-meaning-code meaning)
               (character-token-code token)))
          ((eq key :char-given) (shorthand-value meaning))
          ((equal key "char") (scan-char-num expander))
          (t (back-token expander token) nil))))

(defun make-accent (expander token)
  "TeX's make_accent (§1123) for \\accent read as TOKEN: the accent's
code in the current font, the assignments that follow, then the
accented character in the font they leave, if one comes."
  (let* ((state (expander-state expander))
         (span (token-span token))
         (accent (character-node (scan-char-num expander) span
                                 (font-style-name (current-font state)))))
    (multiple-value-bind (next next-meaning) (do-assignments expander)
      (let ((code (and next (accent-base-code expander next next-meaning))))
        (append-node expander
                     (make-node :accent
                                :children (if code
                                              (list accent
                                                    (character-node
                                                     code (token-span next)
                                                     (font-style-name (current-font state))))
                                              (list accent))
                                :span span))
        (setf (list-state-space-factor (current-list expander)) 1000)))))

(define-command "accent" (expander token meaning)
  ;; §1165: in math, \mathaccent's.
  (if (eq (mode-kind (current-mode expander)) :math)
      (math-accent expander token meaning)
      (make-accent expander token)))
