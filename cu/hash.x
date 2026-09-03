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
; the padding would truncate a C string.  The 32-bit helpers -- %cu-m32
; %cu-add32 %cu-word-hex %cu-nth -- are that file's, reused here.
;
; MD5 is little-endian where SHA is big-endian: the block words and the
; trailing bit-length both reverse, and the digest prints byte-swapped.
; That is the only structural difference between the two paddings.

; --- shared 32-bit rotation ---------------------------------------------------

(def %cu-rotl32
  (fn (_ x n)
    (bit-and (bit-or (bit-shl x n) (bit-shr x (- 32 n))) %cu-m32)))

(def %cu-not32
  (fn (_ x) (bit-xor x %cu-m32)))

; the message as bytes: the raw bytes, then 0x80, zeros to 56 mod 64,
; and eight bytes of bit length -- LOW byte first for MD5.
(def %cu-md5-pad
  (fn (_ text)
    (def len (byte-len text))
    (def bytes
      (let ((go (fn (self i acc)
                  (if (< i 0) acc
                    (self (- i 1) (pair (byte-at text i) acc))))))
        (go (- len 1) ())))
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
    (if (< i 16) (bit-or (bit-and b c) (bit-and (%cu-not32 b) d))
      (if (< i 32) (bit-or (bit-and d b) (bit-and (%cu-not32 d) c))
        (if (< i 48) (bit-xor b (bit-xor c d))
          (bit-xor c (bit-or b (%cu-not32 d))))))))

(def %cu-md5-g
  (fn (_ i)
    (if (< i 16) i
      (if (< i 32) (% (+ (* 5 i) 1) 16)
        (if (< i 48) (% (+ (* 3 i) 5) 16)
          (% (* 7 i) 16))))))

(def %cu-md5-block
  (fn (_ hs block)
    (def m (%cu-md5-words block))
    (def round
      (fn (self i ks ss a b c d)
        (if (> i 63) (list a b c d)
          (let ((f (%cu-add32
                     (%cu-add32 (%cu-md5-f i b c d) a)
                     (%cu-add32 (first ks) (%cu-nth (%cu-md5-g i) m)))))
            (self (+ i 1) (rest ks) (rest ss)
              d
              (%cu-add32 b (%cu-rotl32 f (first ss)))
              b c)))))
    (def out
      (round 0 %cu-md5-k %cu-md5-s
        (%cu-nth 0 hs) (%cu-nth 1 hs) (%cu-nth 2 hs) (%cu-nth 3 hs)))
    (def add2
      (fn (self a b acc)
        (if (null? a) (reverse acc)
          (self (rest a) (rest b)
            (pair (%cu-add32 (first a) (first b)) acc)))))
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
                  (list (integer->char (%cu-hex-digit (bit-shr b 4)))
                        (integer->char (%cu-hex-digit (bit-and b 15))))))
              acc)))))
    (go 0 ())))

; the block walk both digests share: 64 bytes at a time, state in/out
(def %cu-hash-blocks
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
      (%cu-hash-blocks (%cu-md5-pad text)
        (list 1732584193 4023233417 2562383102 271733878)
        (fn (_ hs block) (%cu-md5-block hs block))))
    (string-concat (map (fn (_ w) (%cu-word-hex-le w)) hs))))

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
                    (bit-xor (%cu-nth 2 wrev)
                      (bit-xor (%cu-nth 7 wrev)
                        (bit-xor (%cu-nth 13 wrev) (%cu-nth 15 wrev))))
                    1)
              wrev)))))
    (extend 16 (reverse w16))))

(def %cu-sha1-f
  (fn (_ t b c d)
    (if (< t 20) (bit-or (bit-and b c) (bit-and (%cu-not32 b) d))
      (if (< t 40) (bit-xor b (bit-xor c d))
        (if (< t 60)
          (bit-or (bit-and b c) (bit-or (bit-and b d) (bit-and c d)))
          (bit-xor b (bit-xor c d)))))))

(def %cu-sha1-kt
  (fn (_ t)
    (if (< t 20) 1518500249
      (if (< t 40) 1859775393
        (if (< t 60) 2400959708 3395469782)))))

(def %cu-sha1-block
  (fn (_ hs block)
    (def w (%cu-sha1-schedule block))
    (def round
      (fn (self t ws a b c d e)
        (if (null? ws) (list a b c d e)
          (let ((tmp (%cu-add32
                       (%cu-add32 (%cu-rotl32 a 5) (%cu-sha1-f t b c d))
                       (%cu-add32 (%cu-add32 e (%cu-sha1-kt t))
                         (first ws)))))
            (self (+ t 1) (rest ws)
              tmp a (%cu-rotl32 b 30) c d)))))
    (def out
      (round 0 w
        (%cu-nth 0 hs) (%cu-nth 1 hs) (%cu-nth 2 hs)
        (%cu-nth 3 hs) (%cu-nth 4 hs)))
    (def add2
      (fn (self a b acc)
        (if (null? a) (reverse acc)
          (self (rest a) (rest b)
            (pair (%cu-add32 (first a) (first b)) acc)))))
    (add2 hs out ())))

(def cu-sha1
  (fn (_ text)
    (def hs
      (%cu-hash-blocks (%cu-sha-pad text)
        (list 1732584193 4023233417 2562383102 271733878 3285377520)
        (fn (_ hs block) (%cu-sha1-block hs block))))
    (string-concat (map (fn (_ w) (%cu-word-hex w)) hs))))

; --- the digest applets -------------------------------------------------------

; md5sum/sha1sum/sha256sum share one shape: DIGEST then two spaces then
; the name, with `-` standing for stdin.
(def %cu-sum-applet
  (fn (_ digest argv stdin-thunk)
    (def one
      (fn (_ name text)
        (display
          (string-append (digest text)
            (string-append "  " (string-append name "\n"))))))
    (if (null? argv)
      (do (one "-" (stdin-thunk)) 0)
      (let ((go (fn (self ops)
                  (if (null? ops) 0
                    (do (one (first ops)
                          (if (string=? (first ops) "-")
                            (stdin-thunk)
                            (file-read-all (first ops))))
                        (self (rest ops)))))))
        (go argv)))))

(def %cu-md5sum
  (fn (_ argv stdin-thunk)
    (%cu-sum-applet (fn (_ t) (cu-md5 t)) argv stdin-thunk)))

(def %cu-sha1sum
  (fn (_ argv stdin-thunk)
    (%cu-sum-applet (fn (_ t) (cu-sha1 t)) argv stdin-thunk)))

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
          %cu-m32)))))

(def %cu-crc-build
  (fn (_)
    (def v (vec-make 256 0))
    (def go
      (fn (self i)
        (if (> i 255) v
          (do (vec-set! v i (%cu-crc-bit8 8 (bit-and (bit-shl i 24) %cu-m32)))
              (self (+ i 1))))))
    (go 0)))

(def %cu-crc-table (%cu-crc-build))

(def %cu-crc-byte
  (fn (_ crc b)
    (bit-xor (bit-and (bit-shl crc 8) %cu-m32)
      (vec-ref %cu-crc-table
        (bit-and (bit-xor (bit-shr crc 24) b) 255)))))

(def cu-cksum
  (fn (_ text)
    (def end (byte-len text))
    (def over
      (fn (self i crc)
        (if (>= i end) crc
          (self (+ i 1) (%cu-crc-byte crc (byte-at text i))))))
    ; POSIX folds the LENGTH in after the bytes, low octet first
    (def tail
      (fn (self n crc)
        (if (= n 0) crc
          (self (bit-shr n 8) (%cu-crc-byte crc (bit-and n 255))))))
    (bit-and (%cu-not32 (tail end (over 0 0))) %cu-m32)))

(def %cu-cksum
  (fn (_ argv stdin-thunk)
    (def one
      (fn (_ name text)
        (display
          (string-append (%cu-int->str (cu-cksum text))
            (string-append " "
              (string-append (%cu-int->str (byte-len text))
                (if (null? name) "\n"
                  (string-append " " (string-append name "\n")))))))))
    (if (null? argv)
      (do (one () (stdin-thunk)) 0)
      (let ((go (fn (self ops)
                  (if (null? ops) 0
                    (do (one (first ops)
                          (if (string=? (first ops) "-")
                            (stdin-thunk)
                            (file-read-all (first ops))))
                        (self (rest ops)))))))
        (go argv)))))

; --- sum: the two historical checksums ----------------------------------------

; BSD (the default): a 16-bit rotate-then-add, blocks of 1024
(def cu-sum-bsd
  (fn (_ text)
    (def end (byte-len text))
    (def go
      (fn (self i s)
        (if (>= i end) s
          (self (+ i 1)
            (bit-and
              (+ (+ (bit-shr s 1) (bit-shl (bit-and s 1) 15))
                (byte-at text i))
              65535)))))
    (go 0 0)))

; System V (-s): the byte sum, folded twice into 16 bits, blocks of 512
(def cu-sum-sysv
  (fn (_ text)
    (def end (byte-len text))
    (def total
      (let ((go (fn (self i s)
                  (if (>= i end) s (self (+ i 1) (+ s (byte-at text i)))))))
        (go 0 0)))
    (def r (+ (bit-and total 65535) (bit-shr total 16)))
    (bit-and (+ (bit-and r 65535) (bit-shr r 16)) 65535)))

(def %cu-sum
  (fn (_ argv stdin-thunk)
    (def sysv? (if (pair? argv) (string=? (first argv) "-s") #f))
    (def ops (if sysv? (rest argv) argv))
    (def one
      (fn (_ name text)
        (def n (byte-len text))
        (display
          (if sysv?
            (string-append (%cu-int->str (cu-sum-sysv text))
              (string-append " "
                (string-append (%cu-int->str (/ (- (+ n 511) (% (+ n 511) 512)) 512))
                  (if (null? name) "\n"
                    (string-append " " (string-append name "\n"))))))
            (string-append (%cu-pad-zero (%cu-int->str (cu-sum-bsd text)) 5)
              (string-append " "
                (string-append
                  (%cu-pad-left
                    (%cu-int->str (/ (- (+ n 1023) (% (+ n 1023) 1024)) 1024)) 5)
                  (if (null? name) "\n"
                    (string-append " " (string-append name "\n"))))))))))
    (if (null? ops)
      (do (one () (stdin-thunk)) 0)
      (let ((go (fn (self os)
                  (if (null? os) 0
                    (do (one (first os)
                          (if (string=? (first os) "-")
                            (stdin-thunk)
                            (file-read-all (first os))))
                        (self (rest os)))))))
        (go ops)))))

(def %cu-pad-zero
  (fn (_ s w)
    (def gap (- w (byte-len s)))
    (def z (fn (self k) (if (<= k 0) "" (string-append "0" (self (- k 1))))))
    (if (<= gap 0) s (string-append (z gap) s))))
