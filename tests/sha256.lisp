;;;; tests/sha256.lisp
;;;;
;;;; SHA-256 (src/sha256/): the FIPS 180-4 example vectors, incremental
;;;; and ranged digests agreeing with one-shot ones, and a file of the
;;;; pristine sources against its line of spec/SHA256SUMS (the output of
;;;; sha256sum).

(in-package #:cl-ansi-spec/tests)

(define-test sha256
  :parent cl-ansi-spec
  :description "SHA-256 of octet vectors and files.")

(defun ascii-octets (string)
  "The octets of the ASCII STRING."
  (map '(vector (unsigned-byte 8)) #'char-code string))

(defparameter *fips-vectors*
  '(("" . "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    ("abc" . "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    ;; 448 bits: the padding needs a second block.
    ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
     . "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    ;; 896 bits.
    ("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"
     . "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"))
  "The FIPS 180-4 example messages and their digests.")

(define-test fips-vectors
  :parent sha256
  :description "The example messages of FIPS 180-4 (appendix B)."
  (loop for (message . digest) in *fips-vectors*
        do (is equal digest (cl-ansi-spec/sha256:sha256-hex (ascii-octets message))
               "digest of ~S" message)))

(define-test million-a
  :parent sha256
  :description "A million octets, many blocks: FIPS 180-4 appendix B.3."
  (is equal "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
      (cl-ansi-spec/sha256:sha256-hex
       (make-array 1000000 :element-type '(unsigned-byte 8) :initial-element 97))))

(define-test incremental
  :parent sha256
  :description "Feeding octets one at a time gives the one-shot digest."
  (let* ((octets (ascii-octets (car (second *fips-vectors*))))
         (digest (cl-ansi-spec/sha256:make-digest)))
    (loop for octet across octets
          do (cl-ansi-spec/sha256:digest-update
              digest (make-array 1 :element-type '(unsigned-byte 8)
                                   :initial-element octet)))
    (is equal (cl-ansi-spec/sha256:sha256-hex octets)
        (cl-ansi-spec/sha256::octets-hex
         (cl-ansi-spec/sha256:digest-finish digest)))))

(define-test ranges
  :parent sha256
  :description "START and END select the octets digested."
  (is equal (cl-ansi-spec/sha256:sha256-hex (ascii-octets "abc"))
      (cl-ansi-spec/sha256:sha256-hex (ascii-octets "xxabcyy") :start 2 :end 5)))

(define-test padding-boundaries
  :parent sha256
  :description "Lengths around the block and padding boundaries agree
between one-shot and byte-by-byte digests."
  (dolist (length '(55 56 57 63 64 65 119 120 128))
    (let* ((octets (make-array length :element-type '(unsigned-byte 8)
                                      :initial-element 90))
           (digest (cl-ansi-spec/sha256:make-digest)))
      (loop for i below length
            do (cl-ansi-spec/sha256:digest-update digest octets :start i :end (1+ i)))
      (is equalp (cl-ansi-spec/sha256:sha256 octets)
          (cl-ansi-spec/sha256:digest-finish digest)
          "length ~D" length))))

(defun manifest-digest (manifest name)
  "The digest MANIFEST (a sha256sum listing) records for the file NAME."
  (let ((line (find-if (lambda (line)
                         (let ((suffix (concatenate 'string "  ./" name)))
                           (and (>= (length line) (length suffix))
                                (string= suffix line
                                         :start2 (- (length line) (length suffix))))))
                       (uiop:read-file-lines manifest))))
    (subseq line 0 64)))

(define-test sha256sum-of-a-spec-file
  :parent sha256
  :description "A pristine source file digests as sha256sum recorded it."
  (let ((name "Reviewer-Notes.text"))
    (is equal
        (manifest-digest (asdf:system-relative-pathname "cl-ansi-spec" "spec/SHA256SUMS")
                         name)
        (cl-ansi-spec/sha256:sha256-file-hex
         (asdf:system-relative-pathname "cl-ansi-spec" (concatenate 'string "spec/tex/" name))))))
