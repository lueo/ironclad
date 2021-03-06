;;;; -*- mode: lisp; indent-tabs-mode: nil -*-
;;;; public-key.lisp -- implementation of common public key components

(in-package :crypto)


;;; generic definitions

(defgeneric make-public-key (kind &key &allow-other-keys)
  (:documentation "Return a public key of KIND, initialized according to
the specified keyword arguments."))

(defgeneric make-private-key (kind &key &allow-other-keys)
  (:documentation "Return a private key of KIND, initialized according to
the specified keyword arguments."))

(defgeneric sign-message (key message &key start end)
  (:documentation "Produce a key-specific signature of MESSAGE; MESSAGE is a
(VECTOR (UNSIGNED-BYTE 8)).  START and END bound the extent of the
message."))

(defgeneric verify-signature (key message signature &key start end)
  (:documentation "Verify that SIGNATURE is the signature of MESSAGE using
KEY.  START and END bound the extent of the message."))

(defgeneric encrypt-message (key message &key start end)
  (:documentation "Encrypt MESSAGE with KEY.  START and END bound the extent
of the message.  Returns a fresh octet vector."))

(defgeneric decrypt-message (key message &key start end)
  (:documentation "Decrypt MESSAGE with KEY.  START and END bound the extent
of the message.  Returns a fresh octet vector."))


;;; converting from integers to octet vectors

(defun octets-to-integer (octet-vec &key (start 0) end (big-endian t) n-bits)
  (declare (type (simple-array (unsigned-byte 8) (*)) octet-vec))
  (let ((end (or end (length octet-vec))))
    (multiple-value-bind (complete-bytes extra-bits)
        (if n-bits
            (truncate n-bits 8)
            (values (- end start) 0))
      (declare (ignorable complete-bytes extra-bits))
      (if big-endian
          (do ((j start (1+ j))
               (sum 0))
              ((>= j end) sum)
            (setf sum (+ (aref octet-vec j) (ash sum 8))))
          (loop for i from (- end start 1) downto 0
                for j from (1- end) downto start
                sum (ash (aref octet-vec j) (* i 8)))))))

(defun integer-to-octets (bignum &key (n-bits (integer-length bignum))
                                (big-endian t))
  (let* ((n-bytes (ceiling n-bits 8))
         (octet-vec (make-array n-bytes :element-type '(unsigned-byte 8))))
    (declare (type (simple-array (unsigned-byte 8) (*)) octet-vec))
    (if big-endian
        (loop for i from (1- n-bytes) downto 0
              for index from 0
              do (setf (aref octet-vec index) (ldb (byte 8 (* i 8)) bignum))
              finally (return octet-vec))
        (loop for i from 0 below n-bytes
              for byte from 0 by 8
              do (setf (aref octet-vec i) (ldb (byte 8 byte) bignum))
              finally (return octet-vec)))))

(defun maybe-integerize (thing)
  (etypecase thing
    (integer thing)
    ((simple-array (unsigned-byte 8) (*)) (octets-to-integer thing))))


;;; modular arithmetic utilities

(defun modular-inverse (N modulus)
  "Returns M such that N * M mod MODULUS = 1"
  (declare (type (integer 1 *) modulus))
  (declare (type (integer 0 *) n))
  (when (or (zerop n) (and (evenp n) (evenp modulus)))
    (return-from modular-inverse 0))
  (loop with remainder = (list n modulus)
     and auxiliary = '(1 0)
     for i from 2
     while (> (first remainder) 1)
     do (multiple-value-bind (quotient new-remainder)
            (floor (second remainder) (first remainder))
          (push new-remainder remainder)
          (push (+ (* (- quotient) (first auxiliary)) (second auxiliary))
                auxiliary))
     finally (return (let ((inverse (first auxiliary)))
                       (when (< inverse 0)
                         (setf inverse (mod inverse modulus)))
                       ;; check to see if the inverse is zero
                       (if (zerop (mod (* n inverse) modulus))
                           0
                           inverse)))))

;;; direct from CLiki
(defun expt-mod (n exponent modulus)
  "As (mod (expt n exponent) modulus), but more efficient."
  (declare (optimize (speed 3) (safety 0) (space 0) (debug 0)))  
  (loop with result = 1
        for i of-type fixnum from 0 below (integer-length exponent)
        for sqr = n then (mod (* sqr sqr) modulus)
        when (logbitp i exponent) do
        (setf result (mod (* result sqr) modulus))
        finally (return result)))
