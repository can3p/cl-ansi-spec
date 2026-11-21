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
               (:file "inventory"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call '#:cl-ansi-spec/tests '#:run-tests)
               (error "cl-ansi-spec test suite failed."))))
