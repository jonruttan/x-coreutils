; # x-coreutils -- the small tools, as applets
;
; ## cu/sha3.x -- sha3sum: SHA-3, through x-lang's Sha3
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; FIPS 202's SHA3 as busybox computes it (libbb/hash_md5_sha.c), from
; x/codec/sha3.  -a takes any width that is a multiple of 32 below 800, as
; busybox's does; 224 when it is not given.

(module cu/sha3)

(import cu/cli cu-opts)
(import cu/prims cal/ cu-as-run cu-int->str file-write string-append substring)
(import cu/sha256 cu-sum-applet)
(import cu/strings cu-range-number)

(import x/codec/sha3)

; TEXT's digest at WIDTH bits, as hex: TEXT a string, or a run, digested by
; its count.  Past 512 bits busybox writes only the state's first 64 bytes
; and zeros after them, as its sha3_end copies 64.
(def %cu-sha3-hex
  (fn (_ width text)
    (def run (cu-as-run text))
    (def hex (Sha3 hex-n width (first run) (rest run)))
    (if (<= width 512) hex
      (string-append (substring hex 0 128) (Str pad-left (- (cal/ width 4) 128) #\0 "")))))

(def cu-sha3sum
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "sha3sum" argv))
    (def a (Opts value o "-a"))
    (def width (if (null? a) 224 (cu-range-number "sha3sum" a 0 4294967295)))
    (match
      ((null? width) 1)
      ((if (>= width 800) #t (if (= width 0) #t (not (= (& width 31) 0))))
        (do (file-write 2 (string-append "sha3sum: bad -a" (cu-int->str width) "\n")) 1))
      (#t (cu-sum-applet "sha3sum" (fn (_ t) (%cu-sha3-hex width t)) argv stdin-thunk)))))

(provide cu/sha3 cu-sha3sum)
