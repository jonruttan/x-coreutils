; # x-coreutils -- the small tools, as applets
;
; ## lib/coreutils/xatonum.x -- numbers as libbb's xatonum reads them
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; libbb/xatonum_template.c's xstrtoull_range_sfx at base 10, 0..ULLONG_MAX,
; with libbb/xatonum.c's kmg_i_suffixes: what xatoull_sfx(s, kmg_i_suffixes)
; answers.  The count is kept as the bits of an unsigned long long in a
; 64-bit word, so a value past 2^63-1 is the negative number C reads in
; an off_t.

(module coreutils/xatonum)

(import coreutils/prims byte-at byte-len cu-int->str cu-member-s? substring)

(def %xn-two64 (* 0x100000000 0x100000000))
(def %xn-ullong-max (- %xn-two64 1))
(def %xn-llong-max 0x7FFFFFFFFFFFFFFF)

; kmg_i_suffixes, libbb/xatonum.c
(def %xn-kmg-i
  (list (pair (list "KiB" "kiB" "K" "k") 1024)
        (pair (list "MiB" "miB" "M" "m") 1048576)
        (pair (list "GiB" "giB" "G" "g") 1073741824)))

; the multiplier TAIL names: 1 for none, nil where no suffix is TAIL
(def %xn-scale
  (fn (_ tail)
    (if (= (byte-len tail) 0) 1
      (let go ((ss %xn-kmg-i))
        (match
          ((null? ss) ())
          ((cu-member-s? tail (first (first ss))) (rest (first ss)))
          (#t (go (rest ss))))))))

(def %xn-digit? (fn (_ c) (if (>= c 48) (<= c 57) #f)))

; S's count, as a 64-bit word's bits, or the Err libbb would die with: no
; sign, no leading space and at least one digit, then a suffix or nothing.
; strtoull's overflow is an invalid number; a suffix that carries the count
; past ULLONG_MAX is out of range.
(def cu-xatoull-kmg
  (fn (_ s)
    (def n (byte-len s))
    (def end (let go ((i 0)) (if (if (< i n) (%xn-digit? (byte-at s i)) #f) (go (+ i 1)) i)))
    (def v (let go ((i 0) (acc 0))
             (if (< i end) (go (+ i 1) (+ (* acc 10) (- (byte-at s i) 48))) acc)))
    (def scale (%xn-scale (substring s end n)))
    (match
      ((if (= end 0) #t (if (> v %xn-ullong-max) #t (null? scale)))
        (Err make (lit number) (%str-concat (list "invalid number '" s "'")) ()))
      ((> (* v scale) %xn-ullong-max)
        (Err make (lit number)
          (%str-concat (list "number " s " is not in 0.." (cu-int->str %xn-ullong-max) " range")) ()))
      (#t (cu-ull-bits (* v scale))))))

; the 64-bit word holding unsigned V
(def cu-ull-bits (fn (_ v) (if (> v %xn-llong-max) (- v %xn-two64) v)))

; the unsigned decimal of the 64-bit word W, as %llu prints it
(def cu-ull->str (fn (_ w) (cu-int->str (if (< w 0) (+ w %xn-two64) w))))
