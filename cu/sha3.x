; # x-coreutils -- the small tools, as applets
;
; ## cu/sha3.x -- sha3sum: SHA-3, Keccak-f[1600], in x
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; FIPS 202's SHA3 as busybox computes it (libbb/hash_md5_sha.c): the state is
; twenty-five 64-bit lanes, a block of RATE bytes -- 200 less a quarter of the
; width -- is xored into it little-endian and the permutation run, and the
; message ends with SHA3's 0x06, the block's last byte or'd with 0x80.  The
; digest is the state's first WIDTH/8 bytes.  -a takes any width that is a
; multiple of 32 below 800, as busybox's does.  The lanes are signed machine
; words, so a right shift is cu/sha512.x's %cu-shr64.

(def %sha3-rc
  (list 1 32898 -9223372036854742902 -9223372034707259392 32907 2147483649
        -9223372034707259263 -9223372036854743031 138 136 2147516425 2147483658
        2147516555 -9223372036854775669 -9223372036854742903 -9223372036854743037
        -9223372036854743038 -9223372036854775680 32778 -9223372034707292150
        -9223372034707259263 -9223372036854742912 2147483649 -9223372034707259384))

; lane X+5Y's rotation, and where pi moves it: Y + 5((2X + 3Y) mod 5)
(def %sha3-rot
  (list 0 1 62 28 27 36 44 6 55 20 3 10 43 25 39 41 45 15 21 8 18 2 61 56 14))

(def %sha3-pi
  (map (fn (_ i) (let ((x (% i 5)) (y (%cal/ i 5))) (+ y (* 5 (% (+ (* 2 x) (* 3 y)) 5)))))
       (List range 0 25)))

(def %sha3-rotl
  (fn (_ x n) (if (= n 0) x (bit-or (bit-shl x n) (%cu-shr64 x (- 64 n))))))

(def %sha3-not (fn (_ x) (bit-xor x -1)))

; the permutation, its twenty-four rounds over the vector A
(def %sha3-permute!
  (fn (_ a)
    (def b (vec-make 25 0))
    (def c (vec-make 5 0))
    (def round
      (fn (self rcs)
        (if (null? rcs) ()
          (do
            ; theta: each column's parity, mixed into its neighbours
            (let cols ((x 0))
              (when (< x 5)
                (do (vec-set! c x (bit-xor (vec-ref a x) (bit-xor (vec-ref a (+ x 5))
                                     (bit-xor (vec-ref a (+ x 10)) (bit-xor (vec-ref a (+ x 15)) (vec-ref a (+ x 20)))))))
                    (cols (+ x 1)))))
            (let lanes ((i 0))
              (when (< i 25)
                (let ((x (% i 5)))
                  (do (vec-set! a i (bit-xor (vec-ref a i)
                                      (bit-xor (vec-ref c (% (+ x 4) 5))
                                               (%sha3-rotl (vec-ref c (% (+ x 1) 5)) 1))))
                      (lanes (+ i 1))))))
            ; rho and pi: each lane rotated and moved
            (let moves ((i 0) (rs %sha3-rot) (ps %sha3-pi))
              (when (< i 25)
                (do (vec-set! b (first ps) (%sha3-rotl (vec-ref a i) (first rs)))
                    (moves (+ i 1) (rest rs) (rest ps)))))
            ; chi: each row's lanes and-not'd with their neighbours
            (let rows ((i 0))
              (when (< i 25)
                (let ((x (% i 5)) (row (- i (% i 5))))
                  (do (vec-set! a i (bit-xor (vec-ref b i)
                                      (bit-and (%sha3-not (vec-ref b (+ row (% (+ x 1) 5))))
                                               (vec-ref b (+ row (% (+ x 2) 5))))))
                      (rows (+ i 1))))))
            ; iota
            (vec-set! a 0 (bit-xor (vec-ref a 0) (first rcs)))
            (self (rest rcs))))))
    (round %sha3-rc)))

; BYTES (a list) xored into A from lane 0, eight to a lane, little-endian
(def %sha3-absorb!
  (fn (_ a bytes)
    (def go
      (fn (self i bs)
        (if (null? bs) ()
          (let ((w (%sha3-le64 bs)))
            (do (vec-set! a i (bit-xor (vec-ref a i) w))
                (self (+ i 1) (%cu-nthrest 8 bs)))))))
    (go 0 bytes)))

(def %sha3-le64
  (fn (_ bs)
    (def go (fn (self k xs acc) (if (= k 8) acc (self (+ k 1) (rest xs) (bit-or acc (bit-shl (first xs) (* 8 k)))))))
    (go 0 bs 0)))

; TEXT's bytes and SHA3's padding, as a list, a whole number of RATE-byte blocks
(def %sha3-padded
  (fn (_ text rate)
    (def len (byte-len text))
    (def bytes (let go ((i (- len 1)) (acc ())) (if (< i 0) acc (go (- i 1) (pair (byte-at text i) acc)))))
    (def k (- rate (% len rate)))
    (append bytes
      (if (= k 1) (list 134)
        (append (list 6) (append (%cu-zero-list (- k 2)) (list 128)))))))

(def %sha3-hex
  (fn (_ text width)
    (def rate (- 200 (%cal/ width 4)))
    (def a (vec-make 25 0))
    (def blocks
      (fn (self bs i)
        (if (null? bs) ()
          (do (%sha3-absorb! a (%cu-take bs rate))
              (%sha3-permute! a)
              (%cu-sweep! (+ i 1))
              (self (%cu-nthrest rate bs) (+ i 1))))))
    (do (blocks (%sha3-padded text rate) 0)
        (%sha3-out-hex a (%cal/ width 8)))))

; the state's first N bytes, as hex
(def %sha3-out-hex
  (fn (_ a n)
    (def byte (fn (_ k) (& (%cu-shr64 (vec-ref a (%cal/ k 8)) (* 8 (% k 8))) 255)))
    (string-concat
      (map (fn (_ k) (let ((v (byte k)))
                       (bytes->str (list (%cu-hex-digit (%cu-shr64 v 4)) (%cu-hex-digit (& v 15))))))
           (List range 0 n)))))

(def %cu-sha3sum
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "sha3sum" argv))
    (def a (Opts value o "-a"))
    (def width (if (null? a) 224 (%cu-range-number "sha3sum" a 0 4294967295)))
    (match
      ((null? width) 1)
      ((if (>= width 800) #t (if (= width 0) #t (not (= (& width 31) 0))))
        (do (file-write 2 (string-append "sha3sum: bad -a" (%cu-int->str width) "\n")) 1))
      (#t (%cu-sum-applet "sha3sum" (fn (_ t) (%sha3-hex t width)) argv stdin-thunk)))))
