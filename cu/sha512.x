; # x-coreutils -- the small tools, as applets
;
; ## cu/sha512.x -- SHA-512 and SHA-384
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The digests are x/codec/sha512's and x/codec/sha384's, read by count
; through hex-n, so a NUL in the input is a byte like any other.

(module cu/sha512)

(import cu/prims cu-as-run)
(import cu/sha256 cu-sum-applet)

(import x/codec/sha384)
(import x/codec/sha512)

; TEXT's SHA-512 as hex: TEXT a string, or a run, digested by its count
(def cu-sha512
  (fn (_ text)
    (def run (cu-as-run text))
    (Sha512 hex-n (first run) (rest run))))

; TEXT's SHA-384 as hex, as cu-sha512
(def cu-sha384
  (fn (_ text)
    (def run (cu-as-run text))
    (Sha384 hex-n (first run) (rest run))))

(def cu-sha512sum
  (fn (_ argv stdin-thunk)
    (cu-sum-applet "sha512sum" (fn (_ t) (cu-sha512 t)) argv stdin-thunk)))

(def cu-sha384sum
  (fn (_ argv stdin-thunk)
    (cu-sum-applet "sha384sum" (fn (_ t) (cu-sha384 t)) argv stdin-thunk)))

(provide cu/sha512 cu-sha384sum cu-sha512sum)
