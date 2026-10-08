; # x-coreutils -- the small tools, as applets
;
; ## cu/crypt.x -- cryptpw and mkpasswd: crypt(3)'s DES, and md5-crypt
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's cryptpw (loginutils/cryptpw.c), which is mkpasswd too.  -m names
; the method -- des (the default), md5 -- and -S, or a second word, the salt; a
; salt with no -m is a whole one, its $1$ choosing md5.  Without a salt, one is
; made from /dev/urandom.
;
; The DES is the traditional crypt(3)'s (FIPS 46, as libbb/pw_encrypt_des.c
; computes it): the password's first eight bytes, each shifted left one,
; are the key; the salt's two characters, read in crypt's base-64, swap
; twelve pairs of the E box's outputs; a block of zeros is encrypted
; twenty-five times, and its 64 bits written six at a time after the salt.
; The bits ride vectors of 0s and 1s, a permutation a table of positions.

(def %des-ip
  (list 58 50 42 34 26 18 10 2 60 52 44 36 28 20 12 4 62 54 46 38 30 22 14 6
        64 56 48 40 32 24 16 8 57 49 41 33 25 17 9 1 59 51 43 35 27 19 11 3
        61 53 45 37 29 21 13 5 63 55 47 39 31 23 15 7))

(def %des-fp
  (list 40 8 48 16 56 24 64 32 39 7 47 15 55 23 63 31 38 6 46 14 54 22 62 30
        37 5 45 13 53 21 61 29 36 4 44 12 52 20 60 28 35 3 43 11 51 19 59 27
        34 2 42 10 50 18 58 26 33 1 41 9 49 17 57 25))

(def %des-e
  (list 32 1 2 3 4 5 4 5 6 7 8 9 8 9 10 11 12 13 12 13 14 15 16 17
        16 17 18 19 20 21 20 21 22 23 24 25 24 25 26 27 28 29 28 29 30 31 32 1))

(def %des-p
  (list 16 7 20 21 29 12 28 17 1 15 23 26 5 18 31 10
        2 8 24 14 32 27 3 9 19 13 30 6 22 11 4 25))

(def %des-pc1
  (list 57 49 41 33 25 17 9 1 58 50 42 34 26 18 10 2 59 51 43 35 27 19 11 3 60 52 44 36
        63 55 47 39 31 23 15 7 62 54 46 38 30 22 14 6 61 53 45 37 29 21 13 5 28 20 12 4))

(def %des-pc2
  (list 14 17 11 24 1 5 3 28 15 6 21 10 23 19 12 4 26 8 16 7 27 20 13 2
        41 52 31 37 47 55 30 40 51 45 33 48 44 49 39 56 34 53 46 42 50 36 29 32))

(def %des-shifts (list 1 1 2 2 2 2 2 2 1 2 2 2 2 2 2 1))

(def %des-s
  (list
    (list 14 4 13 1 2 15 11 8 3 10 6 12 5 9 0 7 0 15 7 4 14 2 13 1 10 6 12 11 9 5 3 8
          4 1 14 8 13 6 2 11 15 12 9 7 3 10 5 0 15 12 8 2 4 9 1 7 5 11 3 14 10 0 6 13)
    (list 15 1 8 14 6 11 3 4 9 7 2 13 12 0 5 10 3 13 4 7 15 2 8 14 12 0 1 10 6 9 11 5
          0 14 7 11 10 4 13 1 5 8 12 6 9 3 2 15 13 8 10 1 3 15 4 2 11 6 7 12 0 5 14 9)
    (list 10 0 9 14 6 3 15 5 1 13 12 7 11 4 2 8 13 7 0 9 3 4 6 10 2 8 5 14 12 11 15 1
          13 6 4 9 8 15 3 0 11 1 2 12 5 10 14 7 1 10 13 0 6 9 8 7 4 15 14 3 11 5 2 12)
    (list 7 13 14 3 0 6 9 10 1 2 8 5 11 12 4 15 13 8 11 5 6 15 0 3 4 7 2 12 1 10 14 9
          10 6 9 0 12 11 7 13 15 1 3 14 5 2 8 4 3 15 0 6 10 1 13 8 9 4 5 11 12 7 2 14)
    (list 2 12 4 1 7 10 11 6 8 5 3 15 13 0 14 9 14 11 2 12 4 7 13 1 5 0 15 10 3 9 8 6
          4 2 1 11 10 13 7 8 15 9 12 5 6 3 0 14 11 8 12 7 1 14 2 13 6 15 0 9 10 4 5 3)
    (list 12 1 10 15 9 2 6 8 0 13 3 4 14 7 5 11 10 15 4 2 7 12 9 5 6 1 13 14 0 11 3 8
          9 14 15 5 2 8 12 3 7 0 4 10 1 13 11 6 4 3 2 12 9 5 15 10 11 14 1 7 6 0 8 13)
    (list 4 11 2 14 15 0 8 13 3 12 9 7 5 10 6 1 13 0 11 7 4 9 1 10 14 3 5 12 2 15 8 6
          1 4 11 13 12 3 7 14 10 15 6 8 0 5 9 2 6 11 13 8 1 4 10 7 9 5 0 15 14 2 3 12)
    (list 13 2 8 4 6 15 11 1 10 9 3 14 5 0 12 7 1 15 13 8 10 3 7 4 12 5 6 11 0 14 9 2
          7 11 4 1 9 12 14 2 0 6 10 13 15 3 5 8 2 1 14 7 4 10 8 13 15 12 9 0 3 5 6 11)))

; the S boxes as vectors, for a lookup that does not walk a list
(def %des-sv (map (fn (_ box) (vec-build 64 (fn (_ i) (%cu-nth i box)))) %des-s))

; V's bits picked by TABLE, its positions counted from 1, as a fresh vector
(def %des-permute
  (fn (_ v table)
    (def out (vec-make (length table) 0))
    (let go ((i 0) (t table))
      (if (null? t) out
        (do (vec-set! out i (vec-ref v (- (first t) 1))) (go (+ i 1) (rest t)))))))

; the sixteen 48-bit round keys from a 64-bit key, as a list of vectors
(def %des-subkeys
  (fn (_ key)
    (def cd (%des-permute key %des-pc1))
    (def rot
      (fn (_ v n)
        ; each 28-bit half rotated left N
        (vec-build 56 (fn (_ i) (let ((half (if (< i 28) 0 28)))
                                  (vec-ref v (+ half (% (+ (- i half) n) 28))))))))
    (let go ((ss %des-shifts) (v cd) (acc ()))
      (if (null? ss) (reverse acc)
        (let ((nv (rot v (first ss))))
          (go (rest ss) nv (pair (%des-permute nv %des-pc2) acc)))))))

; f: R expanded through E (salted), xored with K, through the S boxes and P
(def %des-f
  (fn (_ r k e)
    (def x (vec-build 48 (fn (_ i) (bit-xor (vec-ref r (- (%cu-nth i e) 1)) (vec-ref k i)))))
    (def out (vec-make 32 0))
    (let boxes ((b 0) (sv %des-sv))
      (when (< b 8)
        (let ((o (* 6 b)))
          (let ((row (+ (* 2 (vec-ref x o)) (vec-ref x (+ o 5))))
                (col (+ (* 8 (vec-ref x (+ o 1))) (* 4 (vec-ref x (+ o 2)))
                        (* 2 (vec-ref x (+ o 3))) (vec-ref x (+ o 4)))))
            (let ((val (vec-ref (first sv) (+ (* 16 row) col))))
              (do (vec-set! out (* 4 b) (& (bit-shr val 3) 1))
                  (vec-set! out (+ (* 4 b) 1) (& (bit-shr val 2) 1))
                  (vec-set! out (+ (* 4 b) 2) (& (bit-shr val 1) 1))
                  (vec-set! out (+ (* 4 b) 3) (& val 1))
                  (boxes (+ b 1) (rest sv))))))))
    (%des-permute out %des-p)))

; BLOCK (64 bits) encrypted under the round keys KS, the E box E
(def %des-encrypt
  (fn (_ block ks e)
    (def lr (%des-permute block %des-ip))
    (def l (vec-build 32 (fn (_ i) (vec-ref lr i))))
    (def r (vec-build 32 (fn (_ i) (vec-ref lr (+ i 32)))))
    (let go ((ks ks) (l l) (r r))
      (if (null? ks)
        ; the halves swapped, then the final permutation
        (%des-permute (vec-build 64 (fn (_ i) (if (< i 32) (vec-ref r i) (vec-ref l (- i 32))))) %des-fp)
        (let ((fr (%des-f r (first ks) e)))
          (go (rest ks) r (vec-build 32 (fn (_ i) (bit-xor (vec-ref l i) (vec-ref fr i))))))))))

; a salt character's value in crypt's base-64 (. / 0-9 A-Z a-z, 0 to 63), 0 for
; any other, as busybox's ascii_to_bin reads one
(def %des-a64
  (fn (_ c) (let ((i (%dp-find %cu-crypt64 0 c))) (if (< i 0) 0 i))))

; E with the salt's twelve bits each swapping a pair of its entries
(def %des-salted-e
  (fn (_ s0 s1)
    (def e (vec-build 48 (fn (_ i) (%cu-nth i %des-e))))
    (def bits (+ (%des-a64 s0) (bit-shl (%des-a64 s1) 6)))
    (let go ((i 0))
      (when (< i 12)
        (do (when (= (& (bit-shr bits i) 1) 1)
              (let ((t (vec-ref e i))) (do (vec-set! e i (vec-ref e (+ i 24))) (vec-set! e (+ i 24) t))))
            (go (+ i 1)))))
    (%des-vec->list e)))

(def %des-vec->list (fn (_ v) (let go ((i (- (Vector length v) 1)) (acc ())) (if (< i 0) acc (go (- i 1) (pair (vec-ref v i) acc))))))

; crypt(3)'s DES of KEY with SALT's first two characters
(def %cu-des-crypt
  (fn (_ key salt)
    (def s0 (if (> (byte-len salt) 0) (byte-at salt 0) #\.))
    (def s1 (if (> (byte-len salt) 1) (byte-at salt 1) s0))
    (def kv (vec-make 64 0))
    (let keys ((i 0))
      (when (< i 8)
        (let ((c (if (< i (byte-len key)) (& (bit-shl (char->integer (byte-at key i)) 1) 255) 0)))
          (do (let bits ((j 0))
                (when (< j 8)
                  (do (vec-set! kv (+ (* 8 i) j) (& (bit-shr c (- 7 j)) 1)) (bits (+ j 1)))))
              (keys (+ i 1))))))
    (def ks (%des-subkeys kv))
    (def e (%des-salted-e s0 s1))
    (def out
      (let go ((n 0) (b (vec-make 64 0)))
        (if (= n 25) b (do (%cu-sweep! (+ n 1)) (go (+ n 1) (%des-encrypt b ks e))))))
    (string-append (bytes->str (list s0 s1))
      (string-concat
        (map (fn (_ g)
               (let ((v (let go ((j 0) (acc 0))
                          (if (= j 6) acc
                            (let ((k (+ (* 6 g) j)))
                              (go (+ j 1) (+ (* 2 acc) (if (< k 64) (vec-ref out k) 0))))))))
                 (substring %cu-crypt64 v (+ v 1))))
             (List range 0 11))))))

; --- cryptpw, mkpasswd ---------------------------------------------------------

(def %cu-cryptpw (fn (_ argv stdin-thunk) (%cp-run "cryptpw" argv stdin-thunk)))
(def %cu-mkpasswd (fn (_ argv stdin-thunk) (%cp-run "mkpasswd" argv stdin-thunk)))

(def %cp-run
  (fn (_ applet argv stdin-thunk)
    (def o (%cu-opts applet argv))
    (def val (fn (_ a b) (let ((v (Opts value o a))) (if (null? v) (Opts value o b) v))))
    (def ops (Opts operands o))
    (def m (let ((v (val "-m" "--method"))) (if (null? v) (Opts value o "-a") v)))
    (def s (let ((v (val "-S" "--salt")))
             (let ((given (if (null? v) (if (pair? ops) (if (pair? (rest ops)) (first (rest ops)) ()) ()) v)))
               (if (if (null? given) #f (= (byte-len given) 0)) () given))))
    (def fd (let ((p (val "-P" "--password-fd"))) (if (null? p) 0 (%cu-range-number applet p 0 2147483647))))
    (match
      ((> (length ops) 2) (%cu-usage applet))
      ((null? fd) 1)
      (#t
        (let ((salt (%cp-salt m s)))
          (if (null? salt) (do (file-write 2 (string-append applet ": that method needs SHA-256 or SHA-512, which this x-lang has not\n")) 1)
            (let ((pw (if (pair? ops) (first ops) (%cp-read-line fd stdin-thunk))))
              (do (if (null? pw) () (file-write 1 (string-append (%cp-encrypt pw salt) "\n")))
                  0))))))))

; the salt to hash with, as busybox's crypt_make_pw_salt and cryptpw make it:
; -m's method prefix and random characters, S put in place of them; or S
; whole; or a random DES salt.  Nil for a method this cannot compute.
(def %cp-salt
  (fn (_ m s)
    (match
      ((null? m) (if (null? s) (%hd-salt 2) s))
      ((= (| (char->integer (byte-at m 0)) 32) 100) (if (null? s) (%hd-salt 2) s))
      ((= (| (char->integer (byte-at m 0)) 32) 115) ())
      ((= (| (char->integer (byte-at m 0)) 32) 121) ())
      (#t (string-append "$1$" (if (null? s) (%hd-salt 8) s))))))

; pw_encrypt: $1$ is md5-crypt, anything else the DES of its first two
(def %cp-encrypt
  (fn (_ pw salt)
    (if (%cp-prefix? salt "$1$")
      (%cu-md5-crypt pw (substring salt 3 (byte-len salt)))
      (%cu-des-crypt pw salt))))

(def %cp-prefix?
  (fn (_ s p) (if (>= (byte-len s) (byte-len p)) (string=? (substring s 0 (byte-len p)) p) #f)))

; a line from FD, its newline dropped; nil at the end before any byte.
; Standard input is the applet's own, read through its thunk.
(def %cp-read-line
  (fn (_ fd stdin-thunk)
    (if (= fd 0)
      (let ((p ((%cu-stdin-pieces stdin-thunk))))
        (if (= (rest p) 0) ()
          (let ((t (if (= (rest p) (byte-len (first p))) (first p) (substring (first p) 0 (rest p)))))
            (let ((nl (%dp-find t 0 #\newline))) (if (< nl 0) t (substring t 0 nl))))))
      (let ((buf (%str-make-raw 1)))
        (let go ((acc ()))
          (let ((r (File read fd buf 1)))
            (match
              ((<= r 0) (if (null? acc) () (bytes->str (reverse acc))))
              ((= (char->integer (byte-at buf 0)) 10) (bytes->str (reverse acc)))
              (#t (go (pair (char->integer (byte-at buf 0)) acc))))))))))
