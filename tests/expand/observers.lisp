;;;; tests/expand/observers.lisp
;;;;
;;;; Markers and the expander's observers (src/expand/macro.lisp,
;;;; src/expand/nodes.lisp; docs/vocabulary.md, "Observers"): when an
;;;; observed call begins and ends, replacing a call, definitions, and
;;;; markers that TeX never sees.

(in-package #:cl-ansi-spec/tests)

(define-test observers
  :parent cl-ansi-spec
  :description "Markers and the observers of macro calls and definitions.")

(defun observe-macros (expander names &key replace)
  "Make EXPANDER mark the calls of the macros NAMES (strings): a
(:begin NAME) marker when a call begins, an (:end NAME) marker when its
body ends; the calls of REPLACE (names too) are replaced by a (:replaced
NAME :replaced t) marker."
  (flet ((key (token) (control-sequence-name (cs-token-control-sequence token))))
    (setf (expand:expander-call-observer expander)
          (lambda (expander token macro arguments)
            (declare (ignore macro arguments))
            (let ((name (key token)))
              (cond ((member name replace :test #'string=)
                     (expand:append-marker expander (list :begin name :replaced t))
                     :replace)
                    ((member name names :test #'string=)
                     (expand:append-marker expander (list :begin name))
                     (values nil name))))))
    (setf (expand:expander-level-end-observer expander)
          (lambda (expander name)
            (expand:append-marker expander (list :end name))))))

(defun observed-events (expander)
  "EXPANDER's events as STRIP-EVENT shows them, without the parskip glue,
indentation and text styles of plain paragraphs."
  (loop for event in (expand:job-events expander)
        for stripped = (strip-event expander event)
        unless (or (member (first stripped) '(:indent))
                   (and (eq (first stripped) :glue)
                        (equal (getf (rest stripped) :command) "parskip")))
          collect (if (eq (first stripped) :text)
                      (subseq stripped 0 2)
                      stripped)))

(defmacro check-observed (text names events &key replace (errors '()))
  "Run TEXT\\end observing NAMES (and replacing REPLACE); check its EVENTS
(unless :ANY) and ERRORS."
  `(let ((expander (make-test-expander (concatenate 'string ,text "\\end"))))
     (observe-macros expander ',names :replace ',replace)
     (multiple-value-bind (output messages) (run-job expander)
       (declare (ignore output))
       ,@(unless (eq events :any) `((is equal ',events (observed-events expander)
                             "events of ~S" ,text)))
       (is equal ',errors messages "errors of ~S" ,text))))

;;; When a call begins and ends

(define-test observed-calls
  :parent observers
  ;; The end comes once the body is read, before what follows; the begin
  ;; goes where the call is, here the vertical list (text nodes break
  ;; where spans do).
  (check-observed "\\def\\m#1{[#1]}\\m{x}y\\par" ("m")
                  ((:begin "m") (:begin :paragraph)
                   (:text "[x") (:text "]") (:end "m") (:text "y")
                   (:end :paragraph)))
  ;; A tail call ends its caller first; nested calls nest.
  (check-observed "\\def\\a{a\\b}\\def\\b{b}\\def\\c{(\\b)}\\a\\c\\par" ("a" "b" "c")
                  ((:begin "a") (:begin :paragraph)
                   (:text "a") (:end "a")
                   (:begin "b") (:text "b") (:end "b")
                   (:begin "c") (:text "(")
                   (:begin "b") (:text "b") (:end "b")
                   (:text ")") (:end "c")
                   (:end :paragraph)))
  ;; An empty body ends at once.
  (check-observed "\\def\\e{}x\\e y\\par" ("e")
                  ((:begin :paragraph) (:text "x") (:begin "e") (:end "e") (:text "y")
                   (:end :paragraph)))
  ;; A body whose last command reads ahead ends when it reads past it.
  (check-observed "\\def\\f{\\kern1pt\\futurelet\\n\\relax}x\\f\\kern2pt y\\par" ("f")
                  ((:begin :paragraph) (:text "x") (:begin "f") (:kern :width "1.0pt")
                   (:end "f") (:kern :width "2.0pt") (:text "y") (:end :paragraph)))
  ;; Bodies still being read end with the job.
  (check-observed "\\def\\g{x\\par\\end}\\g" ("g")
                  ((:begin "g") (:begin :paragraph) (:text "x") (:end :paragraph)
                   (:end "g"))))

(define-test replaced-calls
  :parent observers
  (check-observed "\\def\\r#1{[#1]}x\\r{y}z\\par" ()
                  ((:begin :paragraph) (:text "x") (:begin "r" :replaced t) (:text "z")
                   (:end :paragraph))
                  :replace ("r")))

(define-test definitions-are-observed
  :parent observers
  (let ((expander (make-test-expander "\\def\\a{}\\let\\b=\\a
\\chardef\\c=1 \\global\\edef\\d{}\\futurelet\\e\\relax\\relax\\end"))
        (seen '()))
    (setf (expand:expander-definition-observer expander)
          (lambda (expander cs meaning span)
            (declare (ignore expander))
            (push (list (control-sequence-name cs) (type-of meaning) (span-line span))
                  seen)))
    (run-job expander)
    (is equal '(("a" expand:macro 1) ("b" expand:macro 1) ("c" expand:shorthand 2)
                ("d" expand:macro 2) ("e" expand:primitive 2))
        (reverse seen))))

;;; Markers are invisible to TeX

(define-test markers-are-invisible
  :parent observers
  ;; \unskip and \lastskip see the glue before the marker.
  (check-observed "\\def\\m{}x\\hskip3pt\\m\\unskip\\par" ("m")
                  ((:begin :paragraph) (:text "x") (:begin "m") (:end "m")
                   (:end :paragraph)))
  (check-observed "\\def\\m{}x\\hskip3pt\\relax\\m\\skip0=\\lastskip\\hskip\\skip0 y\\par" ("m")
                  ((:begin :paragraph) (:text "x") (:glue :glue "3.0pt" :command "hskip")
                   (:begin "m") (:end "m") (:glue :glue "3.0pt" :command "hskip")
                   (:text "y") (:end :paragraph)))
  ;; A script goes to the noad before the marker.
  (check-observed (with-math-fonts "\\def\\m{}$x^2\\m^3$\\par") ("m")
                  :any
                  :errors ("Double superscript"))
  ;; \\lastbox and \\unkern see past markers; characters do not join
  ;; across one; a discretionary may hold them.
  (check-observed "\\def\\m{}\\setbox1\\hbox{\\hbox{}\\m\\setbox0\\lastbox\\kern1pt\\m\\unkern}%
\\unhbox1 a\\m b\\discretionary{c\\m}{}{}\\par" ("m")
                  ((:begin :paragraph)
                   (:begin "m") (:end "m") (:begin "m") (:end "m")
                   (:text "a") (:begin "m") (:end "m") (:text "b")
                   (:begin :discretionary :command "discretionary")
                   (:begin :pre-break) (:text "c") (:begin "m") (:end "m") (:end :pre-break)
                   (:end :discretionary)
                   (:end :paragraph)))
  ;; A paragraph holding only markers is dropped; they stay.
  (check-observed "\\def\\m{}\\noindent\\m\\par" ("m")
                  ((:begin "m") (:end "m"))))

(define-test appends-are-observed
  :parent observers
  ;; The append observer sees each node before it is appended, and the
  ;; text node a character is about to extend; a marker it appends then
  ;; ends that text node.
  (let ((expander (make-test-expander "ab\\kern1pt c\\par\\end"))
        (seen '()))
    (setf (expand:expander-append-observer expander)
          (lambda (expander node list)
            (push (expand:node-kind node) seen)
            ;; A text node already in LIST is about to be extended.
            (when (and (eq (expand:node-kind node) :text)
                       (eq node (first (expand:list-state-contents list))))
              (expand:append-marker expander (list :begin "m")))))
    (run-job expander)
    (is equal '(:glue :indent :text :text :marker :text :kern :text :paragraph)
        (reverse seen))
    (is equal '((:begin :paragraph) (:text "a") (:begin "m") (:text "b")
                (:kern :width "1.0pt") (:text "c") (:end :paragraph))
        (observed-events expander))))
