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
               (:module "semantic"
                :serial t
                :components ((:file "package")
                             (:file "vocabulary")
                             (:file "observe")
                             (:file "handlers")
                             (:static-file "vocabulary.sexp")))
               (:module "patch"
                :serial t
                :components ((:file "package")
                             (:file "conditions")
                             (:file "parse")
                             (:file "apply")))
               (:module "inventory"
                :serial t
                :components ((:file "package")
                             (:file "survey")))
               (:module "sha256"
                :serial t
                :components ((:file "package")
                             (:file "digest")
                             (:file "api")))
               (:module "json"
                :serial t
                :components ((:file "package")
                             (:file "reader")
                             (:file "writer")))
               (:module "model"
                :serial t
                :components ((:file "package")
                             (:file "owners")
                             (:file "define-node")
                             (:file "nodes-structure")
                             (:file "nodes-entries")
                             (:file "nodes-blocks")
                             (:file "nodes-tables")
                             (:file "nodes-inlines")
                             (:file "nodes-glossary")
                             (:file "nodes-bnf")
                             (:file "nodes-math")
                             (:file "build")
                             (:file "print")
                             (:file "build-text")
                             (:file "build-structure")
                             (:file "build-entries")
                             (:file "build-blocks")
                             (:file "build-tables")
                             (:file "build-inlines")
                             (:file "build-glossary")
                             (:file "build-bnf")
                             (:file "build-math")
                             (:file "ids")
                             (:file "resolve-sections")
                             (:file "resolve-operators")
                             (:file "resolve-terms")
                             (:static-file "owners.sexp")))
               (:module "export"
                :serial t
                :components ((:file "package")
                             (:file "generate")
                             (:file "schema")
                             (:file "reference")
                             (:file "validate")
                             (:file "write-sexp")
                             (:file "write-json")
                             (:file "files")
                             (:file "manifest"))))
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
                             (:file "format")
                             (:file "observers")))
               (:module "semantic"
                :serial t
                :components ((:file "observe")
                             (:file "vocabulary")
                             (:file "spec-jobs")))
               (:module "patch"
                :serial t
                :components ((:file "patch")))
               (:file "inventory")
               (:file "sha256")
               (:file "json")
               (:module "model"
                :serial t
                :components ((:file "owners")
                             (:file "define-node")
                             (:file "documentation")
                             (:file "build")
                             (:file "text")
                             (:file "structure")
                             (:file "entries")
                             (:file "blocks")
                             (:file "tables")
                             (:file "inlines")
                             (:file "glossary")
                             (:file "bnf")
                             (:file "math")
                             (:file "whole-spec")
                             (:file "resolve-sections")
                             (:file "resolve-operators")
                             (:file "resolve-terms")))
               (:module "export"
                :serial t
                :components ((:file "generate")
                             (:file "schema")
                             (:file "reference")
                             (:file "validate")
                             (:file "writers")
                             (:file "whole-spec")
                             (:file "sample"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call '#:cl-ansi-spec/tests '#:run-tests)
               (error "cl-ansi-spec test suite failed."))))
