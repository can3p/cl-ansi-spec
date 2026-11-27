;;;; src/sha256/digest.lisp
;;;;
;;;; The SHA-256 computation (FIPS 180-4, section 6.2): padding, the message
;;;; schedule and the compression function over 512-bit blocks, big-endian
;;;; throughout.  Octets are (unsigned-byte 8); every word is an unsigned
;;;; 32-bit integer, and every sum is reduced modulo 2^32.

(in-package #:cl-ansi-spec/sha256)

(deftype word () '(unsigned-byte 32))

(defconstant +block-octets+ 64
  "Octets in a message block.")

(defconstant +chunk-octets+ 65536
  "Octets read at a time from a file.")

(defparameter *round-constants*
  (make-array
   64 :element-type 'word
      :initial-contents
      '(#x428a2f98 #x71374491 #xb5c0fbcf #xe9b5dba5 #x3956c25b #x59f111f1
        #x923f82a4 #xab1c5ed5 #xd807aa98 #x12835b01 #x243185be #x550c7dc3
        #x72be5d74 #x80deb1fe #x9bdc06a7 #xc19bf174 #xe49b69c1 #xefbe4786
        #x0fc19dc6 #x240ca1cc #x2de92c6f #x4a7484aa #x5cb0a9dc #x76f988da
        #x983e5152 #xa831c66d #xb00327c8 #xbf597fc7 #xc6e00bf3 #xd5a79147
        #x06ca6351 #x14292967 #x27b70a85 #x2e1b2138 #x4d2c6dfc #x53380d13
        #x650a7354 #x766a0abb #x81c2c92e #x92722c85 #xa2bfe8a1 #xa81a664b
        #xc24b8b70 #xc76c51a3 #xd192e819 #xd6990624 #xf40e3585 #x106aa070
        #x19a4c116 #x1e376c08 #x2748774c #x34b0bcb5 #x391c0cb3 #x4ed8aa4a
        #x5b9cca4f #x682e6ff3 #x748f82ee #x78a5636f #x84c87814 #x8cc70208
        #x90befffa #xa4506ceb #xbef9a3f7 #xc67178f2))
  "The first 32 bits of the fractional parts of the cube roots of the first
64 primes (FIPS 180-4, section 4.2.2).")

(defparameter *initial-hash*
  (make-array
   8 :element-type 'word
     :initial-contents
     '(#x6a09e667 #xbb67ae85 #x3c6ef372 #xa54ff53a
       #x510e527f #x9b05688c #x1f83d9ab #x5be0cd19))
  "The first 32 bits of the fractional parts of the square roots of the
first eight primes (FIPS 180-4, section 5.3.3).")

(defstruct (digest (:constructor make-digest ()))
  "An incremental SHA-256 computation.  HASH holds the eight chaining
words, BUFFER the octets of the block not yet compressed (FILL of them),
and TOTAL the number of octets absorbed so far."
  (hash (copy-seq *initial-hash*)
   :type (simple-array word (8)))
  (buffer (make-array +block-octets+ :element-type '(unsigned-byte 8))
   :type (simple-array (unsigned-byte 8) (*)))
  (filled 0 :type (integer 0 64))
  (total 0 :type unsigned-byte))

(defmacro add32 (&rest terms)
  "The sum of TERMS modulo 2^32."
  `(ldb (byte 32 0) (+ ,@terms)))

(declaim (inline rotate-right))
(defun rotate-right (word count)
  "WORD rotated right by COUNT bits, as a 32-bit word."
  (declare (type word word) (type (integer 1 31) count))
  (logior (ash word (- count))
          (ldb (byte 32 0) (ash word (- 32 count)))))

(defun big-endian-word (octets start)
  "The 32-bit big-endian word of the four octets from START."
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type fixnum start))
  (logior (ash (aref octets start) 24)
          (ash (aref octets (+ start 1)) 16)
          (ash (aref octets (+ start 2)) 8)
          (aref octets (+ start 3))))

(defun compress-block (hash buffer)
  "Fold the 64 octets of BUFFER into the chaining words HASH (in place)."
  (declare (type (simple-array word (8)) hash)
           (type (simple-array (unsigned-byte 8) (*)) buffer))
  (let ((schedule (make-array 64 :element-type 'word)))
    (dotimes (i 16)
      (setf (aref schedule i) (big-endian-word buffer (* 4 i))))
    (loop for i from 16 below 64
          for w15 = (aref schedule (- i 15))
          for w2 = (aref schedule (- i 2))
          do (setf (aref schedule i)
                   (add32 (aref schedule (- i 16))
                          (logxor (rotate-right w15 7) (rotate-right w15 18)
                                  (ash w15 -3))
                          (aref schedule (- i 7))
                          (logxor (rotate-right w2 17) (rotate-right w2 19)
                                  (ash w2 -10)))))
    (destructuring-bind (a b c d e f g h) (list (aref hash 0) (aref hash 1) (aref hash 2) (aref hash 3) (aref hash 4) (aref hash 5) (aref hash 6) (aref hash 7))
      (dotimes (i 64)
        (let* ((big-sigma1 (logxor (rotate-right e 6) (rotate-right e 11)
                                   (rotate-right e 25)))
               (choose (logxor (logand e f) (logand (lognot e) g)))
               (temp1 (add32 h big-sigma1 choose
                             (aref *round-constants* i) (aref schedule i)))
               (big-sigma0 (logxor (rotate-right a 2) (rotate-right a 13)
                                   (rotate-right a 22)))
               (majority (logxor (logand a b) (logand a c) (logand b c)))
               (temp2 (add32 big-sigma0 majority)))
          (psetf h g
                 g f
                 f e
                 e (add32 d temp1)
                 d c
                 c b
                 b a
                 a (add32 temp1 temp2))))
      (loop for i from 0
            for value in (list a b c d e f g h)
            do (setf (aref hash i) (add32 (aref hash i) value))))))

(defun digest-update (digest octets &key (start 0) (end (length octets)))
  "Absorb the octets of OCTETS from START below END into DIGEST.  Return
DIGEST."
  (let ((offset start))
    (loop while (< offset end)
          do (let* ((filled (digest-filled digest))
                    (n (min (- +block-octets+ filled) (- end offset)))
                    (buffer (digest-buffer digest)))
               (replace buffer octets
                        :start1 filled :start2 offset :end2 (+ offset n))
               (incf (digest-filled digest) n)
               (incf offset n)
               (when (= (digest-filled digest) +block-octets+)
                 (compress-block (digest-hash digest) buffer)
                 (setf (digest-filled digest) 0))))
    (incf (digest-total digest) (- end start))
    digest))

(defun digest-finish (digest)
  "Pad the message absorbed into DIGEST (FIPS 180-4, section 5.1.1) and
return its 32-octet digest.  DIGEST must not be updated afterwards."
  (let* ((bit-length (* 8 (digest-total digest)))
         (zeros (mod (- 56 (1+ (digest-filled digest))) +block-octets+))
         (padding (make-array (+ 1 zeros 8) :element-type '(unsigned-byte 8)
                                            :initial-element 0)))
    (setf (aref padding 0) #x80)
    (loop for i from 0 below 8
          do (setf (aref padding (- (length padding) 1 i))
                   (ldb (byte 8 (* 8 i)) bit-length)))
    (digest-update digest padding)
    (let ((result (make-array 32 :element-type '(unsigned-byte 8))))
      (loop for word across (digest-hash digest)
            for i from 0 by 4
            do (loop for shift from 24 downto 0 by 8
                     for j from i
                     do (setf (aref result j) (ldb (byte 8 shift) word))))
      result)))
