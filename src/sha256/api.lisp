;;;; src/sha256/api.lisp
;;;;
;;;; The entry points: digests of octet vectors and of files, one-shot and
;;;; as lowercase hexadecimal text.

(in-package #:cl-ansi-spec/sha256)

(defun sha256 (octets &key (start 0) (end (length octets)))
  "The SHA-256 digest of the octets of OCTETS from START below END, as a
fresh 32-octet vector."
  (digest-finish (digest-update (make-digest) octets :start start :end end)))

(defun octets-hex (octets)
  "OCTETS as a string of lowercase hexadecimal digits, two per octet."
  (with-output-to-string (out)
    (loop for octet across octets
          do (format out "~(~2,'0x~)" octet))))

(defun sha256-hex (octets &key (start 0) (end (length octets)))
  "The SHA-256 digest of the octets of OCTETS from START below END, as
lowercase hexadecimal text (the form `sha256sum` prints)."
  (octets-hex (sha256 octets :start start :end end)))

(defun sha256-file (pathname)
  "The SHA-256 digest of the bytes of the file PATHNAME, as a 32-octet
vector.  The file is read in chunks, never whole."
  (with-open-file (in pathname :element-type '(unsigned-byte 8))
    (let ((digest (make-digest))
          (chunk (make-array +chunk-octets+ :element-type '(unsigned-byte 8))))
      (loop for count = (read-sequence chunk in)
            while (plusp count)
            do (digest-update digest chunk :end count))
      (digest-finish digest))))

(defun sha256-file-hex (pathname)
  "The SHA-256 digest of the file PATHNAME as lowercase hexadecimal text."
  (octets-hex (sha256-file pathname)))
