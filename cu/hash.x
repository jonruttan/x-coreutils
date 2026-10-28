; # x-coreutils -- the small tools, as applets
;
; ## cu/hash.x -- MD5, SHA-1, and the two checksums
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; md5sum sha1sum cksum sum.  The digests are x/codec/md5's and x/codec/sha1's,
; read by count through hex-n and bytes-n, and the checksums x/codec/cksum's
; and x/codec/sum's, so a NUL in the input is a byte like any other.

(module cu/hash)

(import cu/cli cu-opts)
(import cu/prims bit-and byte-at cu-as-run cu-int->str length string-append
  string-concat)
(import cu/sha256 cu-sum-applet)
(import cu/text cu-each-run-said cu-pad-left cu-pad-zero cu-read-run-said
  cu-says-open)

(import x/codec/cksum)
(import x/codec/hex)
(import x/codec/md5)
(import x/codec/sha1)
(import x/codec/sum)

; the bytes of S from A to B
(def cu-bytes
  (fn (_ s a b)
    (let go ((i (- b 1)) (acc ()))
      (if (< i a) acc (go (- i 1) (pair (bit-and (byte-at s i) 255) acc))))))

; --- MD5 ----------------------------------------------------------------------

; TEXT's MD5 as hex: TEXT a string, or a run, digested by its count
(def cu-md5
  (fn (_ text)
    (def run (cu-as-run text))
    (Md5 hex-n (first run) (rest run))))

; MD5 of a list of bytes, as a list of sixteen bytes: what ntpd's keyed
; digests hash holds NULs, which a string would not carry
(def cu-md5-bytes
  (fn (_ bytes)
    (cu-bytes (Md5 bytes-n (bytes->str bytes) (length bytes)) 0 16)))

; crypt's base-64, which httpd's and cryptpw's random salts are written in

(def cu-crypt64 "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

; --- SHA-1 --------------------------------------------------------------------

; TEXT's SHA-1 as hex: TEXT a string, or a run, digested by its count
(def cu-sha1
  (fn (_ text)
    (def run (cu-as-run text))
    (Sha1 hex-n (first run) (rest run))))

; SHA-1 of a list of bytes, as a list of twenty bytes, as cu-md5-bytes
(def cu-sha1-bytes
  (fn (_ bytes)
    (Hex decode-bytes (Sha1 hex-n (bytes->str bytes) (length bytes)))))

; --- the digest applets -------------------------------------------------------
;
; md5sum, sha1sum, sha256sum and sha512sum are busybox's md5_sha1_sum.c: one
; driver, its messages and its statuses.  Writing, each line is the digest, two
; spaces and the name, `-` for stdin.  Checking (-c), each list is read back a
; line at a time and every file it names recomputed.

(def cu-md5sum
  (fn (_ argv stdin-thunk)
    (cu-sum-applet "md5sum" (fn (_ t) (cu-md5 t)) argv stdin-thunk)))

(def cu-sha1sum
  (fn (_ argv stdin-thunk)
    (cu-sum-applet "sha1sum" (fn (_ t) (cu-sha1 t)) argv stdin-thunk)))

; --- cksum: the POSIX CRC-32 --------------------------------------------------

; TEXT is a string or a run, digested by its count through x/codec/cksum
(def cu-cksum
  (fn (_ text)
    (def run (cu-as-run text))
    (Cksum of (first run) 0 (rest run))))

(def cu-cksum-applet
  (fn (_ argv stdin-thunk)
    (def one
      (fn (_ name text)
        (display
          (string-append (cu-int->str (cu-cksum text))
            (string-append " "
              (string-append (cu-int->str (rest text))
                (if (null? name) "\n"
                  (string-append " " (string-append name "\n")))))))))
    (if (null? argv)
      (do (one () (cu-read-run-said (cu-says-open "cksum") "-" stdin-thunk)) 0)
      (cu-each-run-said argv stdin-thunk (cu-says-open "cksum") one 0))))

; --- sum: the two historical checksums ----------------------------------------

; BSD (the default): a 16-bit rotate-then-add, blocks of 1024.  System V
; (-s): the byte sum, folded twice into 16 bits, blocks of 512.  Both are
; x/codec/sum's; TEXT is a string or a run.
(def cu-sum-bsd
  (fn (_ text)
    (def run (cu-as-run text))
    (Sum bsd (first run) 0 (rest run))))

(def cu-sum-sysv
  (fn (_ text)
    (def run (cu-as-run text))
    (Sum sysv (first run) 0 (rest run))))

; busybox's lines: the sum, the blocks, a space and the name.  -r wins over
; -s.  The name is shown under -s, standard input's as `-`, and for BSD only
; when there is more than one operand; a BSD line without it still ends in
; the space.
(def cu-sum
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "sum" argv))
    (def sysv? (if (Opts on? o "-r") #f (Opts on? o "-s")))
    (def ops (Opts operands o))
    (def named? (if sysv? #t (if (pair? ops) (pair? (rest ops)) #f)))
    (def one
      (fn (_ name text)
        (def n (rest text))
        (display
          (string-concat
            (list
              (if sysv?
                (string-append (cu-int->str (cu-sum-sysv text)) " "
                  (cu-int->str (/ (- (+ n 511) (% (+ n 511) 512)) 512)))
                (string-append (cu-pad-zero (cu-int->str (cu-sum-bsd text)) 5) " "
                  (cu-pad-left
                    (cu-int->str (/ (- (+ n 1023) (% (+ n 1023) 1024)) 1024)) 5)))
              " " (if named? name "") "\n")))))
    (if (null? ops)
      (do (one "-" (cu-read-run-said (cu-says-open "sum") "-" stdin-thunk)) 0)
      (cu-each-run-said ops stdin-thunk (cu-says-open "sum") one 0))))

(provide cu/hash cu-bytes cu-cksum-applet cu-crypt64 cu-md5 cu-md5-bytes
  cu-md5sum cu-sha1-bytes cu-sha1sum cu-sum)
