;;;; src/expand/show-lists.lisp
;;;;
;;;; Showing lists (TeX: The Program, §§180-198, 218-219, 1293-1298):
;;;; \showbox and \showlists, and the diagnostics that show a list (a
;;;; discretionary's deleted sublist, a box being shipped out).  Nodes
;;;; have no dimensions, so the format is our own: one node per line, as
;;;; its event without spans, after a `.' per level of nesting, within
;;;; \showboxdepth and \showboxbreadth as TeX's show_box.  Like \show,
;;;; they are entries of the job's log (TeX also reports them as errors).

(in-package #:cl-ansi-spec/expand)

(defun show-value-text (value)
  "VALUE, a property of an event, as it is shown: a keyword as `:name',
a string in double quotes, a list in parentheses."
  (typecase value
    (keyword (format nil ":~(~A~)" (symbol-name value)))
    (string (format nil "~S" value))
    (list (format nil "(~{~A~^ ~})" (mapcar #'show-value-text value)))
    (t (princ-to-string value))))

(defun node-description (expander node)
  "NODE as a line of a shown list: its event (NODE-HEAD) without :SPAN
and :VIA, a token list as its text."
  (let ((head (node-head node)))
    (format nil "(~{~A~^ ~})"
            (append (list (show-value-text (first head)))
                    (and (eq (node-kind node) :text)
                         (list (show-value-text (second head))))
                    (loop for (key value) on (nthcdr (if (eq (node-kind node) :text) 2 1)
                                                     head)
                            by #'cddr
                          unless (member key '(:span :via))
                            append (list (show-value-text key)
                                         (show-value-text
                                          (if (eq key :tokens)
                                              (token-list-text expander value)
                                              value))))))))

(defun show-box-text (expander nodes)
  "TeX's show_box (§§180-182, 198) of NODES: each node on a line of its
own (each line begun by a newline) after a `.' per level; a level deeper
than \\showboxdepth is ` []', and the nodes of a list beyond
\\showboxbreadth (5 when it is not positive) are `etc.'."
  (let* ((state (expander-state expander))
         (depth-limit (parameter state :showboxdepth))
         (breadth (let ((b (parameter state :showboxbreadth))) (if (plusp b) b 5))))
    (with-output-to-string (out)
      (labels ((show (nodes depth)
                 (if (> depth depth-limit)
                     (when nodes (write-string " []" out))
                     (loop for node in nodes
                           for n from 1
                           do (terpri out)
                              (loop repeat depth do (write-char #\. out))
                              (when (> n breadth)
                                (write-string "etc." out)
                                (return))
                              (write-string (node-description expander node) out)
                              (when (node-composite node)
                                (show (node-children node) (1+ depth)))))))
        (show nodes 0)))))

(define-command "showbox" (expander token meaning)
  ;; §1296: `\box n=' and the box, or `void'.
  (let* ((n (scan-eight-bit-int expander))
         (box (register (expander-state expander) :box n)))
    (log-message expander :show
                 (format nil "~A~D=~A" (esc expander "box") n
                         (if box (show-box-text expander (list (box-node box))) "void"))
                 :span (token-span token))))

(defun nest-aux-text (expander list)
  "TeX's display of LIST's auxiliary field (§219): \\prevdepth and
\\prevgraf of a vertical list, \\spacefactor (and the language of a
paragraph) of a horizontal one, a math list's incompleat fraction."
  (let ((mode (list-state-mode list)))
    (case (mode-kind mode)
      (:vertical
       (let ((depth (list-state-prev-depth list))
             (graf (list-state-prev-graf list)))
         (format nil "prevdepth ~A~[~:;, prevgraf ~:*~D line~:P~]"
                 (if (<= depth +ignore-depth+) "ignored" (format-dimen depth))
                 graf)))
      (:horizontal
       (format nil "spacefactor ~D~@[, current language ~D~]"
               (list-state-space-factor list)
               (and (eq mode :horizontal) (plusp (list-state-clang list))
                    (list-state-clang list))))
      (:math
       (let ((fraction (list-state-incompleat list)))
         (and fraction
              (format nil "this will be denominator of:~A"
                      (show-box-text expander (list fraction)))))))))

(defun show-lists-text (expander)
  "TeX's show_activities (§218) in our format: each list of the nest,
innermost first, its mode and line, its nodes and its auxiliary field.
Of the outer vertical list only the nodes not yet on the page are shown
(no page is kept): TeX's recent contributions."
  (with-output-to-string (out)
    (loop for (list . rest) on (expander-nest expander)
          for mode = (list-state-mode list)
          for graf = (list-state-prev-graf list)
          for nodes = (if rest
                          (list-nodes list)
                          (reverse (loop for node in (list-state-contents list)
                                         until (eq node (list-state-contributed list))
                                         collect node)))
          do (format out "~&### ~A entered at line ~D" (mode-text mode)
                     (list-state-line list))
             ;; The hyphenation data a paragraph began with (§1091),
             ;; unless TeX's defaults (2, 3 and language 0).
             (when (and (eq mode :horizontal) (/= graf #o40600000))
               (format out " (language~D:hyphenmin~D,~D)" (mod graf 65536)
                       (floor graf #o20000000) (mod (floor graf 65536) 64)))
             (when (and (null rest) nodes)
               (format out "~%### recent contributions:"))
             (write-string (show-box-text expander nodes) out)
             (let ((aux (nest-aux-text expander list)))
               (when aux (format out "~%~A" aux))))))

(define-command "showlists" (expander token meaning)
  (log-message expander :show (show-lists-text expander) :span (token-span token)))
