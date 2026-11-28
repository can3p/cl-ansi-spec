;;;; tests/export/generate.lisp
;;;;
;;;; The exports' suite, and the registry of generated files
;;;; (src/export/generate.lisp): no committed generated file is stale.

(in-package #:cl-ansi-spec/tests)

(define-test exports
  :parent cl-ansi-spec
  :description "Phase 5, the exports.")

(define-test generated-files-current
  :parent exports
  ;; `make generate' rewrites what this lists.
  (is equal '() (exports:stale-generated-files
                 (asdf:system-relative-pathname "cl-ansi-spec" ""))
      "Stale generated files (run make generate)"))

(define-test generator-registry
  :parent exports
  ;; A generator is registered by name, replaced in place, and its file
  ;; is stale until written.
  (let ((exports::*generators* '())
        (root (uiop:ensure-directory-pathname
               (uiop:merge-pathnames* (format nil "generate-test-~D-~36R/" (sb-unix:unix-getpid)
                                              (random (expt 36 8) (make-random-state t)))
                                      (uiop:temporary-directory)))))
    (unwind-protect
         (progn
           (exports:define-generator test-a "a.txt" (lambda () "one"))
           (exports:define-generator test-b "sub/b.txt" (lambda () "two"))
           (exports:define-generator test-a "a.txt" (lambda () "three"))
           (is equal '(test-a test-b) (mapcar #'exports:generator-name (exports:generators)))
           (is equal '("a.txt" "sub/b.txt") (exports:stale-generated-files root))
           (is equal '("a.txt" "sub/b.txt") (exports:write-generated-files root))
           (is equal '() (exports:stale-generated-files root))
           (is equal '() (exports:write-generated-files root))
           (is string= "three" (uiop:read-file-string (merge-pathnames "a.txt" root))))
      (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore))))
