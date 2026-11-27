;;;; src/sha256/package.lisp
;;;;
;;;; SHA-256 (FIPS 180-4) of octet vectors and files, as lowercase hex
;;;; where text is wanted.  The digests pin the sources and the exports
;;;; (schemaVersion, the export manifest, the patch records).  No
;;;; dependency beyond Common Lisp.

(defpackage #:cl-ansi-spec/sha256
  (:use #:cl)
  (:export
   ;; One-shot digests
   #:sha256 #:sha256-hex #:sha256-file #:sha256-file-hex
   ;; Incremental digests
   #:make-digest #:digest-update #:digest-finish))
