;;;; cl-ansi-spec.asd

(defsystem "cl-ansi-spec"
  :description "Parser and renderer for the TeX sources of the ANSI Common
Lisp draft standard (dpANS3)."
  :license "GPL-3.0"
  :version "0.0.1"
  :depends-on ("uiop")
  :pathname "src/"
  :serial t
  :components ((:file "package")
               (:file "source")
               (:module "tex"
                :serial t
                :components ((:file "package")
                             (:file "state")
                             (:file "token")
                             (:file "line")
                             (:file "scanner")
                             (:file "input-stack")))
               (:module "expand"
                :serial t
                :components ((:file "package")
                             (:file "arithmetic")
                             (:file "units")
                             (:file "glue")
                             (:file "print")
                             (:file "font")
                             (:file "meaning")
                             (:file "parameters")
                             (:file "state")
                             (:file "errors")
                             (:file "primitives")
                             (:file "nest")
                             (:file "expander")
                             (:file "nodes")
                             (:file "show")
                             (:file "macro")
                             (:file "expandable")
                             (:file "scan")
                             (:file "internal")
                             (:file "dimen-scan")
                             (:file "toks")
                             (:file "conditionals")
                             (:file "commands")
                             (:file "groups")
                             (:file "modes")
                             (:file "boxes")
                             (:file "prefixed")
                             (:file "assignments")
                             (:file "main-control")
                             (:file "log")
                             (:file "messages")
                             (:file "streams")
                             (:file "list-commands")
                             (:file "show-lists")
                             (:file "discretionaries")
                             (:file "inserts")
                             (:file "whatsits")
                             (:file "math-lists")
                             (:file "alignments")
                             (:file "format")))
               (:module "inventory"
                :serial t
                :components ((:file "package")
                             (:file "survey"))))
  :in-order-to ((test-op (test-op "cl-ansi-spec/tests"))))

(defsystem "cl-ansi-spec/tests"
  :description "Test suite for cl-ansi-spec."
  :license "GPL-3.0"
  :depends-on ("cl-ansi-spec" "parachute")
  :pathname "tests/"
  :serial t
  :components ((:file "package")
               (:file "source")
               (:file "docs")
               (:module "tex"
                :serial t
                :components ((:file "state")
                             (:file "scanner")
                             (:file "input-stack")))
               (:module "expand"
                :serial t
                :components ((:file "quantities")
                             (:file "state")
                             (:file "expander")
                             (:file "scan")
                             (:file "conditionals")
                             (:file "main-control")
                             (:file "assignments")
                             (:file "streams")
                             (:file "events")
                             (:file "other-nodes")
                             (:file "math-lists")
                             (:file "alignments")
                             (:file "format")))
               (:file "inventory"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call '#:cl-ansi-spec/tests '#:run-tests)
               (error "cl-ansi-spec test suite failed."))))
