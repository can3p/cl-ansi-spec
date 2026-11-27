;;;; src/expand/inserts.lisp
;;;;
;;;; Insertions and vertical adjustments (TeX: The Program, §§1097-1100):
;;;; \insert n{...} and \vadjust{...} read an internal vertical list in an
;;;; insert group; at its `}' the list becomes the children of an
;;;; :INSERT node (with the number and the \splittopskip,
;;;; \splitmaxdepth and \floatingpenalty in force inside the group) or
;;;; of a :VADJUST node.  No page builder takes the inserts, and no line
;;;; breaking moves them out of a paragraph: they stay where appended,
;;;; as marks do (boxes.lisp, SPLIT-MARKS).

(in-package #:cl-ansi-spec/expand)

(define-command ("insert" "vadjust") (expander token meaning)
  ;; begin_insert_or_adjust (§1099); \vadjust is illegal in vertical
  ;; mode (main control).  The group keeps the number, 255 for \vadjust.
  (let ((n (if (string= name "vadjust") 255 (scan-eight-bit-int expander))))
    (when (and (= n 255) (string= name "insert"))
      (tex-error (format nil "You can't ~A255" (esc expander "insert"))
                 :span (token-span token))
      (setf n 0))
    (new-save-level expander :insert :context n :token token :meaning meaning)
    (scan-left-brace expander)
    (normal-paragraph expander)
    (push-nest expander :internal-vertical (token-span token))
    (setf (list-state-prev-depth (current-list expander)) +ignore-depth+)))

(defun end-insert (expander token)
  "The `}' TOKEN of an insert group (§1100): the paragraph inside ends,
and the list becomes an :INSERT or :VADJUST node of the enclosing list;
in the outer vertical list the page builder runs."
  (end-graf expander (token-span token))
  (let* ((state (expander-state expander))
         ;; The values in force inside the group, before unsave.
         (properties (list :split-top-skip (format-glue (parameter state :splittopskip))
                           :split-max-depth (format-dimen (parameter state :splitmaxdepth))
                           :floating-penalty (parameter state :floatingpenalty)))
         (group (unsave expander))
         (n (group-record-context group))
         (start (group-record-token group))
         (children (list-nodes (pop-nest expander))))
    (append-node expander
                 (if (< n 255)
                     (make-node :insert :properties (list* :number n properties)
                                        :children children
                                        :span (token-span start)
                                        :end-span (token-span token))
                     (make-node :vadjust :children children :span (token-span start)
                                         :end-span (token-span token))))
    (when (null (rest (expander-nest expander)))
      (build-page expander))))
