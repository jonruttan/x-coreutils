; # x-coreutils -- the small tools, as applets
;
; ## cu/hash.x -- MD5, SHA-1, and the two checksums
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; md5sum sha1sum cksum sum.  SHA-256 built the pattern (cu/sha256.x):
; the padded message is a BYTE LIST, never a string, because a NUL in
; the padding would truncate a C string.  The 32-bit helpers -- cu-m32
; cu-add32 cu-word-hex cu-nth -- are that file's, reused here.
;
; MD5 is little-endian where SHA is big-endian: the block words and the
; trailing bit-length both reverse, and the digest prints byte-swapped.
; That is the only structural difference between the two paddings.

; --- shared 32-bit rotation ---------------------------------------------------

(module cu/hash)

(import cu/cli cu-opts)
(import cu/prims append bit-and bit-or bit-shl bit-shr bit-xor byte-at
  cu-as-run cu-int->str cu-nth cu-run-list cu-sweep! cu-sweep-bytes
  cu-sweep-steps integer->char length list->string map reverse string-append
  string-concat vec-make vec-ref vec-set!)
(import cu/sha256 cu-add32 cu-hex-digit cu-m32 cu-sha-pad cu-sum-applet
  cu-word-hex)
(import cu/text cu-each-run-said cu-pad-left cu-pad-zero cu-read-run-said
  cu-says-open)

(def %cu-rotl32
  (fn (_ x n)
    (bit-and (bit-or (bit-shl x n) (bit-shr x (- 32 n))) cu-m32)))

(def %cu-not32
  (fn (_ x) (bit-xor x cu-m32)))

; the message as bytes: the raw bytes, then 0x80, zeros to 56 mod 64,
; and eight bytes of bit length -- LOW byte first for MD5.  TEXT is a string
; or a run, so a NUL in it is a byte like any other.
(def %cu-md5-pad
  (fn (_ text)
    (def run (cu-as-run text))
    (def len (rest run))
    (def bytes (cu-run-list run ()))
    (def zeros
      (let ((k (% (- 119 (% len 64)) 64)))
        (let ((go (fn (self n acc)
                    (if (= n 0) acc (self (- n 1) (pair 0 acc))))))
          (go k ()))))
    (def bits (* len 8))
    (def len-bytes
      (let ((go (fn (self shift acc)
                  (if (> shift 56) (reverse acc)
                    (self (+ shift 8)
                      (pair (bit-and (bit-shr bits shift) 255) acc))))))
        (go 0 ())))
    (append bytes (append (list 128) (append zeros len-bytes)))))

; --- MD5 ----------------------------------------------------------------------

(def %cu-md5-k
  (list 3614090360 3905402710 606105819 3250441966
        4118548399 1200080426 2821735955 4249261313
        1770035416 2336552879 4294925233 2304563134
        1804603682 4254626195 2792965006 1236535329
        4129170786 3225465664 643717713 3921069994
        3593408605 38016083 3634488961 3889429448
        568446438 3275163606 4107603335 1163531501
        2850285829 4243563512 1735328473 2368359562
        4294588738 2272392833 1839030562 4259657740
        2763975236 1272893353 4139469664 3200236656
        681279174 3936430074 3572445317 76029189
        3654602809 3873151461 530742520 3299628645
        4096336452 1126891415 2878612391 4237533241
        1700485571 2399980690 4293915773 2240044497
        1873313359 4264355552 2734768916 1309151649
        4149444226 3174756917 718787259 3951481745))

(def %cu-md5-s
  (list 7 12 17 22 7 12 17 22 7 12 17 22 7 12 17 22
        5 9 14 20 5 9 14 20 5 9 14 20 5 9 14 20
        4 11 16 23 4 11 16 23 4 11 16 23 4 11 16 23
        6 10 15 21 6 10 15 21 6 10 15 21 6 10 15 21))

; sixteen LITTLE-endian words from a 64-byte block
(def %cu-md5-words
  (fn (_ block)
    (def go
      (fn (self bs acc)
        (if (null? bs) (reverse acc)
          (self (rest (rest (rest (rest bs))))
            (pair
              (+ (first bs)
                (+ (bit-shl (first (rest bs)) 8)
                  (+ (bit-shl (first (rest (rest bs))) 16)
                    (bit-shl (first (rest (rest (rest bs)))) 24))))
              acc)))))
    (go block ())))

; the round's mixing function and its message index, by round number
(def %cu-md5-f
  (fn (_ i b c d)
    (match
      ((< i 16) (bit-or (bit-and b c) (bit-and (%cu-not32 b) d)))
      ((< i 32) (bit-or (bit-and d b) (bit-and (%cu-not32 d) c)))
      ((< i 48) (bit-xor b (bit-xor c d)))
      (#t (bit-xor c (bit-or b (%cu-not32 d)))))))

(def %cu-md5-g
  (fn (_ i)
    (match
      ((< i 16) i)
      ((< i 32) (% (+ (* 5 i) 1) 16))
      ((< i 48) (% (+ (* 3 i) 5) 16))
      (#t (% (* 7 i) 16)))))

(def %cu-md5-block
  (fn (_ hs block)
    (def m (%cu-md5-words block))
    (def round
      (fn (self i ks ss a b c d)
        (if (> i 63) (list a b c d)
          (let ((f (cu-add32
                     (cu-add32 (%cu-md5-f i b c d) a)
                     (cu-add32 (first ks) (cu-nth (%cu-md5-g i) m)))))
            (self (+ i 1) (rest ks) (rest ss)
              d
              (cu-add32 b (%cu-rotl32 f (first ss)))
              b c)))))
    (def out
      (round 0 %cu-md5-k %cu-md5-s
        (cu-nth 0 hs) (cu-nth 1 hs) (cu-nth 2 hs) (cu-nth 3 hs)))
    (def add2
      (fn (self a b acc)
        (if (null? a) (reverse acc)
          (self (rest a) (rest b)
            (pair (cu-add32 (first a) (first b)) acc)))))
    (add2 hs out ())))

; MD5 prints each word LOW byte first: the hex of the byte-swapped word
(def %cu-word-hex-le
  (fn (_ w)
    (def go
      (fn (self shift acc)
        (if (> shift 24) (string-concat (reverse acc))
          (self (+ shift 8)
            (pair
              (let ((b (bit-and (bit-shr w shift) 255)))
                (list->string
                  (list (integer->char (cu-hex-digit (bit-shr b 4)))
                        (integer->char (cu-hex-digit (bit-and b 15))))))
              acc)))))
    (go 0 ())))

; the block walk both digests share: 64 bytes at a time, state in/out
(def cu-hash-blocks
  (fn (self bs hs step)
    (if (null? bs) hs
      (let ((take64 (let ((go (fn (self2 l n acc)
                                (if (= n 0) (pair (reverse acc) l)
                                  (self2 (rest l) (- n 1)
                                    (pair (first l) acc))))))
                      (go bs 64 ()))))
        (self (rest take64) (step hs (first take64)) step)))))

(def cu-md5
  (fn (_ text)
    (def hs
      (cu-hash-blocks (%cu-md5-pad text)
        (list 1732584193 4023233417 2562383102 271733878)
        (fn (_ hs block) (%cu-md5-block hs block))))
    (string-concat (map (fn (_ w) (%cu-word-hex-le w)) hs))))

; MD5 of a list of bytes, as a list of sixteen bytes: what md5-crypt hashes
; holds NULs, which a string would not carry
(def cu-md5-bytes
  (fn (_ bytes)
    (def n (length bytes))
    (def zeros (let go ((k (% (- 119 (% n 64)) 64)) (acc ())) (if (= k 0) acc (go (- k 1) (pair 0 acc)))))
    (def len-bytes (let go ((shift 0) (acc ()))
                     (if (> shift 56) (reverse acc)
                       (go (+ shift 8) (pair (bit-and (bit-shr (* n 8) shift) 255) acc)))))
    (def hs (cu-hash-blocks (append bytes (list 128) zeros len-bytes)
              (list 1732584193 4023233417 2562383102 271733878)
              (fn (_ st block) (%cu-md5-block st block))))
    (let go ((ws (reverse hs)) (acc ()))
      (if (null? ws) acc
        (let ((w (first ws)))
          (go (rest ws)
              (pair (bit-and w 255) (pair (bit-and (bit-shr w 8) 255)
                (pair (bit-and (bit-shr w 16) 255) (pair (bit-and (bit-shr w 24) 255) acc))))))))))

; the bytes of S from A to B
(def cu-bytes
  (fn (_ s a b)
    (let go ((i (- b 1)) (acc ()))
      (if (< i a) acc (go (- i 1) (pair (bit-and (byte-at s i) 255) acc))))))

; crypt's base-64, which httpd's and cryptpw's random salts are written in

(def cu-crypt64 "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

; --- SHA-1 --------------------------------------------------------------------

(def %cu-sha1-schedule
  (fn (_ block)
    (def w16
      (let ((go (fn (self bs acc)
                  (if (null? bs) (reverse acc)
                    (self (rest (rest (rest (rest bs))))
                      (pair
                        (+ (bit-shl (first bs) 24)
                          (+ (bit-shl (first (rest bs)) 16)
                            (+ (bit-shl (first (rest (rest bs))) 8)
                              (first (rest (rest (rest bs)))))))
                        acc))))))
        (go block ())))
    ; the window rides a REVERSED list, so w[t-3] w[t-8] w[t-14] w[t-16]
    ; are constant offsets from its head (the SHA-256 trick)
    (def extend
      (fn (self t wrev)
        (if (> t 79) (reverse wrev)
          (self (+ t 1)
            (pair (%cu-rotl32
                    (bit-xor (cu-nth 2 wrev)
                      (bit-xor (cu-nth 7 wrev)
                        (bit-xor (cu-nth 13 wrev) (cu-nth 15 wrev))))
                    1)
              wrev)))))
    (extend 16 (reverse w16))))

(def %cu-sha1-f
  (fn (_ t b c d)
    (match
      ((< t 20) (bit-or (bit-and b c) (bit-and (%cu-not32 b) d)))
      ((< t 40) (bit-xor b (bit-xor c d)))
      ((< t 60) (bit-or (bit-and b c) (bit-or (bit-and b d) (bit-and c d))))
      (#t (bit-xor b (bit-xor c d))))))

(def %cu-sha1-kt
  (fn (_ t)
    (match
      ((< t 20) 1518500249)
      ((< t 40) 1859775393)
      ((< t 60) 2400959708)
      (#t 3395469782))))

(def cu-sha1-block
  (fn (_ hs block)
    (def w (%cu-sha1-schedule block))
    (def round
      (fn (self t ws a b c d e)
        (if (null? ws) (list a b c d e)
          (let ((tmp (cu-add32
                       (cu-add32 (%cu-rotl32 a 5) (%cu-sha1-f t b c d))
                       (cu-add32 (cu-add32 e (%cu-sha1-kt t))
                         (first ws)))))
            (self (+ t 1) (rest ws)
              tmp a (%cu-rotl32 b 30) c d)))))
    (def out
      (round 0 w
        (cu-nth 0 hs) (cu-nth 1 hs) (cu-nth 2 hs)
        (cu-nth 3 hs) (cu-nth 4 hs)))
    (def add2
      (fn (self a b acc)
        (if (null? a) (reverse acc)
          (self (rest a) (rest b)
            (pair (cu-add32 (first a) (first b)) acc)))))
    (add2 hs out ())))

(def cu-sha1
  (fn (_ text)
    (def hs
      (cu-hash-blocks (cu-sha-pad text)
        (list 1732584193 4023233417 2562383102 271733878 3285377520)
        (fn (_ hs block) (cu-sha1-block hs block))))
    (string-concat (map (fn (_ w) (cu-word-hex w)) hs))))

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

(provide cu/hash cu-bytes cu-cksum-applet cu-crypt64 cu-hash-blocks cu-md5
  cu-md5-bytes cu-md5sum cu-sha1-block cu-sha1sum cu-sum)
