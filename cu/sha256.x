; # x-coreutils -- the small tools, as applets
;
; ## cu/sha256.x -- SHA-256, in x
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; FIPS 180-4, on the engine's machine-word ops (& | ^ << >>), every
; value masked to 32 bits.  The padded message lives as a BYTE LIST,
; never a string: x strings are C strings, and the padding's NUL bytes
; would truncate one (the Str8-make lesson, applied).  The schedule
; window rides a reversed list, so w[t-2] w[t-7] w[t-15] w[t-16] are
; constant offsets from the head.
;
; Retires the build's sha256sum/shasum fallback dance (155 calls in
; the measured closure).

(def %cu-m32 4294967295)

(def %cu-sha-h
  (list 1779033703 3144134277 1013904242 2773480762
        1359893119 2600822924 528734635 1541459225))

(def %cu-sha-k
  (list 1116352408 1899447441 3049323471 3921009573
        961987163 1508970993 2453635748 2870763221
        3624381080 310598401 607225278 1426881987
        1925078388 2162078206 2614888103 3248222580
        3835390401 4022224774 264347078 604807628
        770255983 1249150122 1555081692 1996064986
        2554220882 2821834349 2952996808 3210313671
        3336571891 3584528711 113926993 338241895
        666307205 773529912 1294757372 1396182291
        1695183700 1986661051 2177026350 2456956037
        2730485921 2820302411 3259730800 3345764771
        3516065817 3600352804 4094571909 275423344
        430227734 506948616 659060556 883997877
        958139571 1322822218 1537002063 1747873779
        1955562222 2024104815 2227730452 2361852424
        2428436474 2756734187 3204031479 3329325298))

(def %cu-nth
  (fn (self n l) (if (= n 0) (first l) (self (- n 1) (rest l)))))

(def %cu-rotr
  (fn (_ x n)
    (bit-and (bit-or (bit-shr x n) (bit-shl x (- 32 n))) %cu-m32)))

(def %cu-add32
  (fn (_ a b) (bit-and (+ a b) %cu-m32)))

; the message as bytes, padded: 0x80, zeros to 56 mod 64, 8-byte
; big-endian bit length
(def %cu-sha-pad
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
      (let ((go (fn (self n shift acc)
                  (if (< shift 0) (reverse acc)
                    (self n (- shift 8)
                      (pair (bit-and (bit-shr n shift) 255) acc))))))
        (go bits 56 ())))
    (append bytes (append (list 128) (append zeros len-bytes)))))

; the schedule: 16 words from the block, 48 extended; answers the
; 64-word list in order
(def %cu-sha-schedule
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
    (def extend
      (fn (self t wrev)
        (if (> t 63) (reverse wrev)
          (let ((w2 (%cu-nth 1 wrev)))
            (def w7 (%cu-nth 6 wrev))
            (def w15 (%cu-nth 14 wrev))
            (def w16v (%cu-nth 15 wrev))
            (def s0 (bit-xor (%cu-rotr w15 7)
                      (bit-xor (%cu-rotr w15 18) (bit-shr w15 3))))
            (def s1 (bit-xor (%cu-rotr w2 17)
                      (bit-xor (%cu-rotr w2 19) (bit-shr w2 10))))
            (self (+ t 1)
              (pair (%cu-add32 (%cu-add32 w16v s0) (%cu-add32 w7 s1))
                wrev))))))
    (extend 16 (reverse w16))))

; 64 rounds over one block's schedule; H in, H out (lists of 8)
(def %cu-sha-block
  (fn (_ hs block)
    (def w (%cu-sha-schedule block))
    (def round
      (fn (self ws ks a b c d e f g h)
        (if (null? ws)
          (list a b c d e f g h)
          (let ((s1 (bit-xor (%cu-rotr e 6)
                      (bit-xor (%cu-rotr e 11) (%cu-rotr e 25)))))
            (def ch (bit-xor (bit-and e f)
                      (bit-and (bit-xor e %cu-m32) g)))
            (def t1 (%cu-add32 h
                      (%cu-add32 s1
                        (%cu-add32 ch
                          (%cu-add32 (first ks) (first ws))))))
            (def s0 (bit-xor (%cu-rotr a 2)
                      (bit-xor (%cu-rotr a 13) (%cu-rotr a 22))))
            (def maj (bit-xor (bit-and a b)
                       (bit-xor (bit-and a c) (bit-and b c))))
            (def t2 (%cu-add32 s0 maj))
            (self (rest ws) (rest ks)
              (%cu-add32 t1 t2) a b c
              (%cu-add32 d t1) e f g)))))
    (def out
      (round w %cu-sha-k
        (%cu-nth 0 hs) (%cu-nth 1 hs) (%cu-nth 2 hs) (%cu-nth 3 hs)
        (%cu-nth 4 hs) (%cu-nth 5 hs) (%cu-nth 6 hs) (%cu-nth 7 hs)))
    (def add2
      (fn (self a b acc)
        (if (null? a) (reverse acc)
          (self (rest a) (rest b)
            (pair (%cu-add32 (first a) (first b)) acc)))))
    (add2 hs out ())))

(def %cu-hex-digit
  (fn (_ d) (if (< d 10) (+ 48 d) (+ 87 d))))

(def %cu-word-hex
  (fn (_ w)
    (def go
      (fn (self shift acc)
        (if (< shift 0) (list->string (reverse acc))
          (self (- shift 4)
            (pair (integer->char
                    (%cu-hex-digit (bit-and (bit-shr w shift) 15)))
              acc)))))
    (go 28 ())))

(def cu-sha256
  (fn (_ text)
    (def padded (%cu-sha-pad text))
    (def blocks
      (fn (self bs hs)
        (if (null? bs) hs
          (let ((take64 (let ((go (fn (self2 l n acc)
                                    (if (= n 0) (pair (reverse acc) l)
                                      (self2 (rest l) (- n 1)
                                        (pair (first l) acc))))))
                          (go bs 64 ()))))
            (self (rest take64)
              (%cu-sha-block hs (first take64)))))))
    (def hs (blocks padded %cu-sha-h))
    (string-concat (map (fn (_ w) (%cu-word-hex w)) hs))))

(def %cu-sha256sum
  (fn (_ argv stdin-thunk)
    (def one
      (fn (_ name text)
        (display
          (string-append (cu-sha256 text)
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
