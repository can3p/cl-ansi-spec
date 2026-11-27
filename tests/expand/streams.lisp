;;;; tests/expand/streams.lisp
;;;;
;;;; Input, output and messages (src/expand/log.lisp, messages.lisp,
;;;; streams.lisp): \message, \errmessage and \errhelp, \show, \showthe,
;;;; \uppercase and \lowercase, \openin, \closein and \read, \openout,
;;;; \write, \closeout and \immediate (TeX: The Program, §§480-486, 1225,
;;;; 1275, 1279-1298, 1340-1375).  The sources only allocate \read
;;;; (plain.tex) and only write non-immediately, so the rest is tested on
;;;; fixtures.

(in-package #:cl-ansi-spec/tests)

(define-test streams
  :parent cl-ansi-spec
  :description "Input and output streams, the job's log and messages.")

(defun log-of (expander)
  "EXPANDER's log as (KIND TEXT) lists, or (KIND TEXT STREAM) for a write."
  (mapcar (lambda (entry)
            (append (list (expand:log-entry-kind entry) (expand:log-entry-text entry))
                    (and (expand:log-entry-stream entry)
                         (list (expand:log-entry-stream entry)))))
          (expand:job-log expander)))

(defun events-of (expander)
  "EXPANDER's events with their spans removed and token lists shown."
  (mapcar (lambda (event)
            (loop for (key value) on (rest event) by #'cddr
                  unless (eq key :span)
                    append (list key (if (eq key :tokens)
                                         (expand:token-list-text expander value)
                                         value))
                      into properties
                  finally (return (cons (first event) properties))))
          (expand:job-events expander)))

(defmacro check-log (text log &key (errors '()) events files setup (fatal nil fatal-p))
  "Run TEXT (ended by \\end unless FATAL is given) with FILES for \\input
and \\openin, after SETUP, and check its LOG, ERRORS, EVENTS (when
given) and FATAL message."
  `(let ((expander (make-test-expander
                    ,(if fatal-p text `(concatenate 'string ,text "\\end"))
                    :files ,files)))
     (declare (ignorable expander))
     ,@setup
     (multiple-value-bind (output messages contexts modes fatal-message)
         (run-job expander)
       (declare (ignore output contexts modes))
       (is equal ',log (log-of expander) "log of ~S" ,text)
       (is equal ',errors messages "errors of ~S" ,text)
       ,@(when events `((is equal ',events (events-of expander) "events of ~S" ,text)))
       (is equal ,(if fatal-p fatal nil) fatal-message "fatal error of ~S" ,text))))

;;; Messages

(define-test message-and-errmessage
  :parent streams
  (check-log "\\def\\a{x}\\message{a\\a\\relax #\\noexpand\\a}"
             ((:message "ax\\relax ##\\a ")))
  (check-log "\\errmessage{oops}" ((:errmessage "oops")) :errors ("oops"))
  (let ((expander (make-test-expander "\\errhelp{help \\me}\\errmessage{oops}\\end")))
    (run-job expander)
    (is equal "help \\me " (expand:log-entry-help (first (expand:job-log expander))))))

(define-test show-and-showthe
  :parent streams
  (check-log "\\def\\a#1{x#1}\\show\\a \\show a\\show\\par"
             ((:show "\\a=macro:#1->x#1") (:show "the letter a") (:show "\\par=\\par")))
  (check-log "\\show\\undefined" ((:show "\\undefined=undefined")))
  (check-log "\\count1=-7 \\toks0{\\a #}\\showthe\\count1 \\showthe\\toks0 \\showthe\\hsize"
             ((:show "-7") (:show "\\a ##") (:show "0.0pt"))))

(define-test shift-case
  :parent streams
  (check-job "\\def\\x{q}\\uppercase{a\\x b}" "AqB")
  (check-job "\\lowercase{A1}" "a1")
  ;; Categories are kept; an active character becomes another one.
  (check-job "\\uccode`\\1=`\\b \\uppercase{\\ifcat 1.y\\fi 1}" "Yb")
  (check-job "\\catcode`\\~=13 \\catcode`\\!=13 \\def~{T}\\def!{E}\\uccode`\\~=`\\!
\\uppercase{~}" "E")
  (check-job "\\uppercase{}" ""))

;;; \openin, \closein, \read

(defparameter *read-files*
  (list (cons "data" (format nil "a b~%{c~%d}e~%~%"))
        (cons "unbalanced" "{a")
        (cons "excess" (format nil "a}b c~%x"))
        (cons "outer" "a\\o b"))
  "Fixtures for \\read.")

(defmacro check-read (text log &rest keys)
  "CHECK-LOG of TEXT with \\endlinechar 13 and the \\read fixtures."
  `(check-log ,(concatenate 'string "\\endlinechar=13 " text) ,log
              :files *read-files* ,@keys))

(define-test openin-and-ifeof
  :parent streams
  (check-read "\\openin1=missing \\ifeof1 \\message{y}\\fi" ((:message "y")))
  (check-read "\\openin1=data \\ifeof1 \\else\\message{n}\\fi
\\closein1 \\ifeof1 \\message{y}\\fi" ((:message "n") (:message "y")))
  ;; A bad stream number is 0.
  (check-read "\\openin16=data \\ifeof0 \\else\\message{n}\\fi" ((:message "n"))
              :errors ("Bad number")))

(define-test read-lines
  :parent streams
  (check-read "\\openin1=data \\read1 to\\x\\show\\x \\read1 to\\x\\show\\x
\\read1 to\\x\\show\\x \\ifeof1 \\else\\message{open}\\fi
\\read1 to\\x\\show\\x \\ifeof1 \\message{closed}\\fi"
              ((:show "\\x=macro:->a b ") (:show "\\x=macro:->{c d}e ")
               (:show "\\x=macro:->\\par ") (:message "open")
               (:show "\\x=macro:->\\par ") (:message "closed")))
  ;; A right brace that closes more than was opened ends the line.
  (check-read "\\openin2=excess \\read2 to\\x \\show\\x \\read2 to\\x \\show\\x"
              ((:show "\\x=macro:->a") (:show "\\x=macro:->x ")))
  (check-read "\\let\\x=\\relax \\openin2=excess \\read2 \\x \\show\\x"
              ((:show "\\x=macro:->a")) :errors ("Missing `to' inserted"))
  (check-read "\\openin3=unbalanced \\read3 to\\x \\show\\x \\ifeof3 \\message{eof}\\fi"
              ((:show "\\x=macro:->{a \\par ") (:message "eof"))
              :errors ("File ended within"))
  ;; An \outer macro on a line of \read becomes a space, not read again.
  (check-read "\\outer\\def\\o{}\\openin4=outer \\read4 to\\x \\show\\x"
              ((:show "\\x=macro:->a ")) :errors ("Forbidden control sequence found")))

(define-test read-assignment
  :parent streams
  (check-read "\\openin1=data {\\global\\read1 to\\x}\\show\\x {\\read1 to\\y}\\show\\y"
              ((:show "\\x=macro:->a b ") (:show "\\y=undefined")))
  (check-read "\\openin1=data \\long\\read1 to\\x" ()
              :errors ("You can't use `\\long' or `\\outer' with"))
  (check-read "\\read1 to\\x" () :fatal "*** (cannot \\read from terminal in nonstop modes)")
  (check-read "\\read-1 to\\x" () :fatal "*** (cannot \\read from terminal in nonstop modes)"))

(define-test read-line-level
  :parent streams
  (let* ((state (make-plain-state))
         (stack (make-input-stack state :resolver (alist-resolver
                                                   (list (cons "f" "x")
                                                         (cons "g" "ab")))))
         (source (resolve-input stack "g")))
    (push-file stack "f")
    (push-read-line stack (read-line-tokens source state))
    (true (reading-line-p stack))
    (is equal '("a 11" "b 11" "  10") (texts (list (next-token stack) (next-token stack)
                                            (next-token stack))))
    (false (next-token stack))
    (end-read-line stack)
    (is equal "x 11" (token-text (next-token stack)))
    (multiple-value-bind (tokens end) (read-line-tokens source state)
      (is equal '("\\par") (texts tokens))
      (true end))
    (false (resolve-input stack "h"))))

;;; \openout, \write, \closeout, \immediate

(define-test deferred-whatsits
  :parent streams
  (check-log "\\def\\a{x}\\openout3=out \\write3{\\a b}\\write-2{}\\write99{}\\closeout3
\\closeout-1 "
             ()
             :events ((:openout :stream 3 :file "out") (:write :stream 3 :tokens "\\a b")
                      (:write :stream 17 :tokens "") (:write :stream 16 :tokens "")
                      (:closeout :stream 3) (:closeout :stream 17)))
  (check-log "\\openout16=out" () :errors ("Bad number")
                                  :events ((:openout :stream 0 :file "out"))))

(define-test immediate-whatsits
  :parent streams
  (check-log "\\def\\a{x}\\immediate\\write16{\\a\\noexpand\\a}\\immediate\\write-1{y}
\\immediate\\write3{z}"
             ((:write "x\\a " 16) (:write "y" 17) (:write "z" 3))
             :events ())
  (check-log "\\def\\a{x}\\immediate\\openout3=out \\immediate\\write3{\\a}
\\immediate\\closeout3 \\immediate\\write3{\\a}\\immediate\\closeout16 "
             ((:write "x" 3))
             :events ((:openout :stream 3 :file "out" :immediate t)
                      (:write :stream 3 :tokens "x" :text "x" :immediate t)
                      (:closeout :stream 3 :immediate t)))
  ;; Anything else after \immediate is read again.
  (check-log "\\immediate\\message{m}\\immediate\\relax" ((:message "m")) :events ()))

(define-test write-expansion
  :parent streams
  ;; The mode is none while the text is expanded, and is restored.
  (check-log "\\immediate\\write16{\\ifvmode v\\fi\\ifhmode h\\fi n}\\ifvmode
\\message{v}\\fi" ((:write "n" 16) (:message "v")))
  ;; Fewer left braces than right ones: the rest is skipped.
  (check-log "\\def\\r{\\iffalse{\\fi}}\\immediate\\write16{a\\r b}\\message{c}"
             ((:write "a" 16) (:message "c")) :errors ("Unbalanced write command"))
  ;; More: \endwrite is \outer, so the text is a runaway.
  (check-log "\\def\\l{{\\iffalse}\\fi}\\immediate\\write16{a\\l b}"
             ((:write "a{b} " 16)) :errors ("Forbidden control sequence found"))
  (check-job "\\setbox0\\hbox{}" "\\hbox " :errors ("Improper")
                                    :setup ((setf (expand:expander-set-box-allowed expander)
                                                  nil))))
