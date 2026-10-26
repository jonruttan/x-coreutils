; # x-coreutils -- the small tools, as applets
;
; ## cu/hash.x -- MD5, SHA-1, and the two checksums
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; md5sum sha1sum cksum sum.  The digests are x/codec/md5's and
; x/codec/sha1's, read by count through hex-n and bytes-n, so a NUL in the
; input is a byte like any other.

(module cu/hash)

(import cu/cli cu-opts)
(import cu/prims bit-and bit-shl bit-shr bit-xor byte-at cu-as-run
  cu-int->str cu-sweep! cu-sweep-bytes cu-sweep-steps length string-append
  string-concat vec-make vec-ref vec-set!)
(import cu/sha256 cu-m32 cu-sum-applet)
(import cu/text cu-each-run-said cu-pad-left cu-pad-zero cu-read-run-said
  cu-says-open)

(import x/codec/hex)
(import x/codec/md5)
(import x/codec/sha1)

(def %cu-not32
  (fn (_ x) (bit-xor x cu-m32)))

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

; the table is COMPUTED, not embedded: 256 entries from the polynomial
; 0x04C11DB7, MSB-first, which is shorter to read than to transcribe.
(def %cu-crc-bit8
  (fn (self k c)
    (if (= k 0) c
      (self (- k 1)
        (bit-and
          (if (= (bit-and c 2147483648) 0)
            (bit-shl c 1)
            (bit-xor (bit-shl c 1) 79764919))
          cu-m32)))))

(def %cu-crc-build
  (fn (_)
    (def v (vec-make 256 0))
    (def go
      (fn (self i)
        (if (> i 255) v
          (do (vec-set! v i (%cu-crc-bit8 8 (bit-and (bit-shl i 24) cu-m32)))
              (self (+ i 1))))))
    (go 0)))

(def %cu-crc-table (%cu-crc-build))

(def %cu-crc-byte
  (fn (_ crc b)
    (bit-xor (bit-and (bit-shl crc 8) cu-m32)
      (vec-ref %cu-crc-table
        (bit-and (bit-xor (bit-shr crc 24) b) 255)))))

; TEXT is a string or a run, so a NUL in it is a byte like any other
(def cu-cksum
  (fn (_ text)
    (def run (cu-as-run text))
    (def end (rest run))
    ; a byte here costs a few thousand objects, a table lookup's dispatch
    ; with it, so the walk sweeps as often as a loop of cheap steps
    (def over
      (fn (self i crc)
        (if (>= i end) crc
          (do (if (= (& i cu-sweep-steps) 0) (cu-sweep! i) ())
              (self (+ i 1) (%cu-crc-byte crc (byte-at (first run) i)))))))
    ; POSIX folds the LENGTH in after the bytes, low octet first
    (def tail
      (fn (self n crc)
        (if (= n 0) crc
          (self (bit-shr n 8) (%cu-crc-byte crc (bit-and n 255))))))
    (bit-and (%cu-not32 (tail end (over 0 0))) cu-m32)))

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

; BSD (the default): a 16-bit rotate-then-add, blocks of 1024.  TEXT, here
; and for System V, is a string or a run.
(def cu-sum-bsd
  (fn (_ text)
    (def run (cu-as-run text))
    (def end (rest run))
    (def go
      (fn (self i s)
        (if (>= i end) s
          (do (if (= (& i cu-sweep-bytes) 0) (cu-sweep! i) ())
              (self (+ i 1)
                (bit-and
                  (+ (+ (bit-shr s 1) (bit-shl (bit-and s 1) 15))
                    (byte-at (first run) i))
                  65535))))))
    (go 0 0)))

; System V (-s): the byte sum, folded twice into 16 bits, blocks of 512
(def cu-sum-sysv
  (fn (_ text)
    (def run (cu-as-run text))
    (def end (rest run))
    (def total
      (let ((go (fn (self i s)
                  (if (>= i end) s
                    (do (if (= (& i cu-sweep-bytes) 0) (cu-sweep! i) ())
                        (self (+ i 1) (+ s (byte-at (first run) i))))))))
        (go 0 0)))
    (def r (+ (bit-and total 65535) (bit-shr total 16)))
    (bit-and (+ (bit-and r 65535) (bit-shr r 16)) 65535)))

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
