;;;; -*- mode: lisp; indent-tabs-mode: nil -*-
;;;; fortuna.lisp -- Fortuna PRNG

(in-package :crypto)

(defvar fortuna :fortuna)


(defparameter +min-pool-size+
  128
  "Minimum pool size before a reseed is allowed.  This should be the
  number of bytes of pool data that are likely to contain 128 bits of
  entropy.  Defaults to a pessimistic estimate of 1 bit of entropy per
  byte.")

(defclass pool ()
  ((digest :initform (make-digest :sha256))
   (length :initform 0))
  (:documentation "A Fortuna entropy pool.  DIGEST contains its current
  state; LENGTH the length in bytes of the entropy it contains."))

(defclass fortuna-prng (pseudo-random-number-generator)
  ((pools :initform (loop for i from 1 to 32
                       collect (make-instance 'pool)))
   (reseed-count :initform 0)
   (last-reseed :initform 0)
   (generator))
  (:documentation "A Fortuna random number generator.  Contains 32
  entropy pools which are used to reseed GENERATOR."))

(defmethod internal-random-data (num-bytes
                                 (pseudo-random-number-generator
                                  fortuna-prng))
  (when (plusp num-bytes)
    (with-slots (pools generator reseed-count last-reseed)
        pseudo-random-number-generator
      (when (and (>= (slot-value (first pools) 'length) +min-pool-size+)
                 (> (- (get-internal-run-time) last-reseed) 100))
        (incf reseed-count)
        (loop for i from 0 below (length pools)
           with seed = (make-array (* (digest-length :sha256)
                                      (integer-length
                                       (logand reseed-count
                                               (- reseed-count))))
                                   :element-type '(unsigned-byte 8))
           while (zerop (mod reseed-count (expt 2 i)))
           collect (with-slots (digest length) (nth i pools)
                     (digest-sequence digest :digest seed :digest-start)
                     (digest-sequence :sha256 :digest seed :digest-start)
                     (setf length 0)
                     (reinitialize-instance digest))
           finally (reseed generator seed)))
      (assert (plusp reseed-count))
      (pseudo-random-data generator num-bytes))))

(defun add-random-event (source pool-id event
                         &optional (pseudo-random-number-generator *prng*))
  (assert (and (<= 1 (length event) 32)
               (<= 0 source 255)
               (<= 0 pool-id 31)))
  (let ((pool (nth pool-id (slot-value pseudo-random-number-generator 'pools))))
    (update-digest (slot-value pool 'digest)
                            (concatenate '(vector (unsigned-byte 8))
                                         (integer-to-octets source)
                                         (integer-to-octets
                                          (length event))
                                         event))
    (incf (slot-value pool 'length) (length event))))

(defmethod internal-write-seed (path (pseudo-random-number-generator
fortuna-prng))
  (with-open-file (seed-file path
                             :direction :output
                             :if-exists :supersede
                             :if-does-not-exist :create
                             :element-type '(unsigned-byte 8))
    (write-sequence (random-data 64 pseudo-random-number-generator) seed-file))
  t)

(defmethod internal-read-os-random-seed (source
                                         (pseudo-random-number-generator
                                          fortuna-prng))
  "Read a random seed from /dev/random or equivalent."
  (reseed (slot-value pseudo-random-number-generator 'generator)
          (os-random-seed source 64))
  (incf (slot-value pseudo-random-number-generator 'reseed-count)))

(defmethod internal-read-seed (path
                               (pseudo-random-number-generator fortuna-prng))
  (with-open-file (seed-file path
                             :direction :input
                             :element-type '(unsigned-byte 8))
    (let ((seq (make-array 64 :element-type '(unsigned-byte 8))))
      (assert (>= (read-sequence seq seed-file) 64))
      (reseed (slot-value pseudo-random-number-generator 'generator) seq)
      (incf (slot-value pseudo-random-number-generator 'reseed-count ))))
  (write-seed path pseudo-random-number-generator))

(defun feed-fifo (pseudo-random-number-generator path)
  "Feed random data into a FIFO"
  (loop while
       (handler-case (with-open-file 
                         (fortune-out path :direction :output
                                      :if-exists :overwrite
                                      :element-type '(unsigned-byte 8))
                       (loop do (write-sequence
                                 (random-data (1- (expt 2 20))
                                              pseudo-random-number-generator)
                                 fortune-out)))
         (stream-error () t))))

(defun make-fortuna (cipher)
  (let ((prng (make-instance 'fortuna-prng)))
    (setf (slot-value prng 'generator)
          (make-instance 'generator :cipher cipher))
    prng))

(defmethod make-prng ((name (eql :fortuna)) &key seed (cipher :aes))
  (declare (ignorable seed))
  (make-fortuna cipher))

;; FIXME: this is more than a little ugly; maybe there should be a
;; prng-registry or something?
(defmethod make-prng ((name (eql 'fortuna)) &key seed (cipher :aes))
  (declare (ignorable seed))
  (make-fortuna cipher))
