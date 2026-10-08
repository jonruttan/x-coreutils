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

; MD5 of a list of bytes, as a list of sixteen bytes: what md5-crypt hashes
; holds NULs, which a string would not carry
(def %cu-md5-bytes
  (fn (_ bytes)
    (def n (length bytes))
    (def zeros (let go ((k (% (- 119 (% n 64)) 64)) (acc ())) (if (= k 0) acc (go (- k 1) (pair 0 acc)))))
    (def len-bytes (let go ((shift 0) (acc ()))
                     (if (> shift 56) (reverse acc)
                       (go (+ shift 8) (pair (bit-and (bit-shr (* n 8) shift) 255) acc)))))
    (def hs (%cu-hash-blocks (append bytes (list 128) zeros len-bytes)
              (list 1732584193 4023233417 2562383102 271733878)
              (fn (_ st block) (%cu-md5-block st block))))
    (let go ((ws (reverse hs)) (acc ()))
      (if (null? ws) acc
        (let ((w (first ws)))
          (go (rest ws)
              (pair (bit-and w 255) (pair (bit-and (bit-shr w 8) 255)
                (pair (bit-and (bit-shr w 16) 255) (pair (bit-and (bit-shr w 24) 255) acc))))))))))

; the bytes of S from A to B
(def %cu-bytes
  (fn (_ s a b)
    (let go ((i (- b 1)) (acc ()))
      (if (< i a) acc (go (- i 1) (pair (bit-and (byte-at s i) 255) acc))))))

; --- md5-crypt ------------------------------------------------------------------
;
; The $1$ password hash busybox's md5_crypt writes (FreeBSD's): KEY with up to
; eight bytes of SALT, mixed through a thousand rounds of MD5, the sixteen bytes
; at the end written in crypt's base-64 in its own order.

(def %cu-crypt64 "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

; N base-64 characters of V, its low six bits first
(def %cu-to64
  (fn (self v n)
    (if (= n 0) ""
      (string-append (substring %cu-crypt64 (bit-and v 63) (+ (bit-and v 63) 1))
                     (self (bit-shr v 6) (- n 1))))))

(def %cu-md5-crypt
  (fn (_ key salt)
    (def pw (%cu-bytes key 0 (byte-len key)))
    (def s (let ((end (let go ((i 0)) (if (if (< i (byte-len salt)) (if (< i 8) (not (= (byte-at salt i) #\$)) #f) #f) (go (+ i 1)) i))))
             (%cu-bytes salt 0 end)))
    (def alt (%cu-md5-bytes (append pw s pw)))
    (def lead
      (append pw (%cu-bytes "$1$" 0 3) s
        (let go ((pl (length pw)) (acc ()))
          (if (<= pl 0) acc (go (- pl 16) (append acc (%cu-take alt (if (> pl 16) 16 pl))))))
        (let go ((i (length pw)) (acc ()))
          (if (= i 0) acc
            (go (bit-shr i 1) (append acc (list (if (= (bit-and i 1) 1) 0 (first pw)))))))))
    (def final
      (let go ((i 0) (f (%cu-md5-bytes lead)))
        (if (= i 1000) f
          (do (when (= (% i 50) 49) (%cu-sweep! i))
          (go (+ i 1)
              (%cu-md5-bytes
                (append (if (= (bit-and i 1) 1) pw f)
                        (if (= (% i 3) 0) () s)
                        (if (= (% i 7) 0) () pw)
                        (if (= (bit-and i 1) 1) f pw))))))))
    (def b (fn (_ k) (%cu-nth k final)))
    (string-concat
      (list "$1$" (bytes->str s) "$"
            (%cu-to64 (+ (bit-shl (b 0) 16) (bit-shl (b 6) 8) (b 12)) 4)
            (%cu-to64 (+ (bit-shl (b 1) 16) (bit-shl (b 7) 8) (b 13)) 4)
            (%cu-to64 (+ (bit-shl (b 2) 16) (bit-shl (b 8) 8) (b 14)) 4)
            (%cu-to64 (+ (bit-shl (b 3) 16) (bit-shl (b 9) 8) (b 15)) 4)
            (%cu-to64 (+ (bit-shl (b 4) 16) (bit-shl (b 10) 8) (b 5)) 4)
            (%cu-to64 (b 11) 2)))))

; the first N of L
(def %cu-take
  (fn (self l n) (if (if (= n 0) #t (null? l)) () (pair (first l) (self (rest l) (- n 1))))))

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
;
; md5sum, sha1sum, sha256sum and sha512sum are busybox's md5_sha1_sum.c: one
; driver, its messages and its statuses.  Writing, each line is the digest, two
; spaces and the name, `-` for stdin.  Checking (-c), each list is read back a
; line at a time and every file it names recomputed.

; A digest is compared case-insensitively -- a checksum file may spell its hex
; either way -- and only at the comparison, not by lowering the whole string
; first.
(def %cu-lc-byte
  (fn (_ b) (if (if (>= b 65) (<= b 90) #f) (+ b 32) b)))

(def %cu-hex=?
  (fn (_ a b)
    (def n (byte-len a))
    (if (not (= n (byte-len b)))
      #f
      (let ((go (fn (self i)
                  (if (>= i n) #t
                    (if (= (%cu-lc-byte (byte-at a i))
                           (%cu-lc-byte (byte-at b i)))
                      (self (+ i 1))
                      #f)))))
        (go 0)))))

; busybox's words for a file a digest could not read: `can't open 'NAME'` for
; one that would not open, `can't read 'NAME'` for one that opened and would
; not read, as a directory does
(def %cu-sum-says
  (fn (_ applet)
    (fn (_ name err)
      (string-concat
        (list applet
              (if (eq? (file-err-op err) (lit read)) ": can't read '" ": can't open '")
              name "': " (file-err-text err))))))

; One line of a checksum file -> (DIGEST . NAME), or nil for a line with no
; space in it.  The digest is everything before the first space; one space or
; star after that is the separator, and passed over -- the two spaces these
; tools write, the " *" of a binary read, or no second character at all, as
; coreutils 9.1 writes -- and the rest of the line is the name.
(def %cu-sum-parse-line
  (fn (_ line)
    (def end (byte-len line))
    (def sp
      (let ((go (fn (self i)
                  (match
                    ((>= i end) ())
                    ((= (byte-at line i) #\space) i)
                    (#t (self (+ i 1)))))))
        (go 0)))
    (if (null? sp) ()
      (let ((from (if (< (+ sp 1) end)
                    (let ((c (byte-at line (+ sp 1))))
                      (if (if (= c #\space) #t (= c #\*)) (+ sp 2) (+ sp 1)))
                    (+ sp 1))))
        (pair (substring line 0 sp) (substring line from end))))))

; -c: each list in turn, `-` for stdin.  A list that will not open is said and
; ends the run, answering 1; one that opens and will not read -- a directory --
; is a list of no lines.  Answers 1 once any list failed.
(def %cu-sum-check-lists
  (fn (self name digest lists stdin-thunk status? warn? st)
    (if (null? lists) st
      (let ((text (if (string=? (first lists) "-") (stdin-thunk)
                    (file-or-err (fn (_) (file-read-all (first lists)))))))
        (if (if (Err err? text) (not (eq? (file-err-op text) (lit read))) #f)
          (do (%cu-say (%cu-says name) (first lists) text) 1)
          (self name digest (rest lists) stdin-thunk status? warn?
            (%cu-max-status st
              (%cu-sum-check-lines name digest (first lists)
                (if (Err err? text) () (%cu-lines text)) stdin-thunk
                status? warn?))))))))

; The lines of the list SHOWN checked in turn, and what the list comes to.
; Every line counts, a blank one too.  One with no space in it fails, and -w
; says `invalid format` for it, under -s as well.  A listed file that will not
; read is said, and FAILED.  A list where anything failed ends with how many of
; its lines did, unless -s; a list of no lines is said whatever the flags.
; Answers 1 for either, else 0.
(def %cu-sum-check-lines
  (fn (_ name digest shown lines stdin-thunk status? warn?)
    (def says (%cu-sum-says name))
    (def say (fn (_ line) (if status? () (display (string-append line "\n")))))
    (def check
      (fn (self ls total failed)
        (if (null? ls) (list total failed)
          (let ((row (%cu-sum-parse-line (first ls))))
            (if (null? row)
              (do (if warn? (file-write 2 (string-append name ": invalid format\n")) ())
                  (self (rest ls) (+ total 1) (+ failed 1)))
              (let ((text (if (string=? (rest row) "-") (stdin-thunk)
                            (%cu-read-said says (rest row)))))
                (if (if (Err err? text) #f (%cu-hex=? (digest text) (first row)))
                  (do (say (string-append (rest row) ": OK"))
                      (self (rest ls) (+ total 1) failed))
                  (do (say (string-append (rest row) ": FAILED"))
                      (self (rest ls) (+ total 1) (+ failed 1))))))))))
    (def counts (check lines 0 0))
    (def total (first counts))
    (def failed (first (rest counts)))
    (do (if (if status? #t (= failed 0)) ()
          (file-write 2
            (string-concat
              (list name ": WARNING: " (%cu-int->str failed) " of " (%cu-int->str total)
                    " computed checksums did NOT match\n"))))
        (if (= total 0)
          (file-write 2 (string-concat (list name ": " shown ": no checksum lines found\n")))
          ())
        (if (if (= total 0) #t (> failed 0)) 1 0))))

; -s and -w shape only what -c says: without it busybox refuses them with its
; usage text.  No operand is stdin.
(def %cu-sum-applet
  (fn (_ name digest argv stdin-thunk)
    (def o (%cu-opts name argv))
    (def ops (if (null? (Opts operands o)) (list "-") (Opts operands o)))
    (def one
      (fn (_ path text)
        (display (string-concat (list (digest text) "  " path "\n")))))
    (match
      ((Opts on? o "-c")
        (%cu-sum-check-lists name digest ops stdin-thunk
          (Opts on? o "-s") (Opts on? o "-w") 0))
      ((if (Opts on? o "-s") #t (Opts on? o "-w")) (%cu-usage name))
      (#t (%cu-each-said ops stdin-thunk (%cu-sum-says name) one 0)))))

(def %cu-md5sum
  (fn (_ argv stdin-thunk)
    (%cu-sum-applet "md5sum" (fn (_ t) (cu-md5 t)) argv stdin-thunk)))

(def %cu-sha1sum
  (fn (_ argv stdin-thunk)
    (%cu-sum-applet "sha1sum" (fn (_ t) (cu-sha1 t)) argv stdin-thunk)))

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
    ; a byte here costs a few thousand objects, a table lookup's dispatch
    ; with it, so the walk sweeps as often as a loop of cheap steps
    (def over
      (fn (self i crc)
        (if (>= i end) crc
          (do (if (= (& i %cu-sweep-steps) 0) (%cu-sweep! i) ())
              (self (+ i 1) (%cu-crc-byte crc (byte-at text i)))))))
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
      (%cu-each-said argv stdin-thunk (%cu-says "cksum") one 0))))

; --- sum: the two historical checksums ----------------------------------------

; BSD (the default): a 16-bit rotate-then-add, blocks of 1024
(def cu-sum-bsd
  (fn (_ text)
    (def end (byte-len text))
    (def go
      (fn (self i s)
        (if (>= i end) s
          (do (if (= (& i %cu-sweep-bytes) 0) (%cu-sweep! i) ())
              (self (+ i 1)
                (bit-and
                  (+ (+ (bit-shr s 1) (bit-shl (bit-and s 1) 15))
                    (byte-at text i))
                  65535))))))
    (go 0 0)))

; System V (-s): the byte sum, folded twice into 16 bits, blocks of 512
(def cu-sum-sysv
  (fn (_ text)
    (def end (byte-len text))
    (def total
      (let ((go (fn (self i s)
                  (if (>= i end) s
                    (do (if (= (& i %cu-sweep-bytes) 0) (%cu-sweep! i) ())
                        (self (+ i 1) (+ s (byte-at text i))))))))
        (go 0 0)))
    (def r (+ (bit-and total 65535) (bit-shr total 16)))
    (bit-and (+ (bit-and r 65535) (bit-shr r 16)) 65535)))

(def %cu-sum
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "sum" argv))
    (def sysv? (Opts on? o "-s"))
    (def ops (Opts operands o))
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
      (%cu-each-said ops stdin-thunk (%cu-says "sum") one 0))))
