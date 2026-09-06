; # x-coreutils -- the small tools, as applets
;
; ## cu/sha512.x -- SHA-512, in x
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; FIPS 180-4's 64-bit sibling of cu/sha256.x, and the whole difference
; is the WORD.  The engine's & | ^ << >> are SIGNED 64-bit machine
; words: they neither promote to a bigint nor mask to a width, so a
; lane needs no masking on the way IN -- addition and xor wrap exactly
; as the specification wants -- but every right shift is ARITHMETIC
; and drags the sign bit down with it.  %cu-shr64 masks those copies
; off, and it is the only place the signedness shows.
;
; The constants are stored as the signed readings of the same 64-bit
; patterns, which is what the engine's reader will hand back anyway.

(def %cu-sha512-h
  (list
        7640891576956012808 -4942790177534073029 4354685564936845355 -6534734903238641935 5840696475078001361 -7276294671716946913 2270897969802886507 6620516959819538809))

(def %cu-sha512-k
  (list
        4794697086780616226 8158064640168781261 -5349999486874862801 -1606136188198331460
        4131703408338449720 6480981068601479193 -7908458776815382629 -6116909921290321640
        -2880145864133508542 1334009975649890238 2608012711638119052 6128411473006802146
        8268148722764581231 -9160688886553864527 -7215885187991268811 -4495734319001033068
        -1973867731355612462 -1171420211273849373 1135362057144423861 2597628984639134821
        3308224258029322869 5365058923640841347 6679025012923562964 8573033837759648693
        -7476448914759557205 -6327057829258317296 -5763719355590565569 -4658551843659510044
        -4116276920077217854 -3051310485924567259 489312712824947311 1452737877330783856
        2861767655752347644 3322285676063803686 5560940570517711597 5996557281743188959
        7280758554555802590 8532644243296465576 -9096487096722542874 -7894198246740708037
        -6719396339535248540 -6333637450476146687 -4446306890439682159 -4076793802049405392
        -3345356375505022440 -2983346525034927856 -860691631967231958 1182934255886127544
        1847814050463011016 2177327727835720531 2830643537854262169 3796741975233480872
        4115178125766777443 5681478168544905931 6601373596472566643 7507060721942968483
        8399075790359081724 8693463985226723168 -8878714635349349518 -8302665154208450068
        -8016688836872298968 -6606660893046293015 -4685533653050689259 -4147400797238176981
        -3880063495543823972 -3348786107499101689 -1523767162380948706 -757361751448694408
        500013540394364858 748580250866718886 1242879168328830382 1977374033974150939
        2944078676154940804 3659926193048069267 4368137639120453308 4836135668995329356
        5532061633213252278 6448918945643986474 6902733635092675308 7801388544844847127))

; THE LOW-BITS MASK, built without arithmetic.  (- (<< 1 63) 1) is the
; obvious spelling and it is WRONG on a host that loads the numeric
; tower: the subtraction overflows int64 and promotes, and the bitwise
; ops then refuse the bigint.  Shifting -1 up and flipping it never
; leaves the machine word.
(def %cu-low-mask
  (fn (_ w) (bit-xor (bit-shl (- 0 1) w) (- 0 1))))

; a LOGICAL right shift: the arithmetic one copies the sign bit down,
; so the copies are masked off.  A shift COUNT is taken mod 64, so a
; zero shift is answered directly rather than masked with a 64-wide
; mask that would come back as 1 - 1.
(def %cu-shr64
  (fn (_ x n)
    (if (= n 0) x
      (bit-and (bit-shr x n) (%cu-low-mask (- 64 n))))))

; ADDITION MODULO 2^64, in halves.  Under helium a machine-word sum
; wraps and this would be a plain +; under a host carrying the tower
; the same sum PROMOTES to a bigint that no bitwise op will touch, and
; the digest would depend on which host ran it.  Splitting into two
; 32-bit halves keeps every intermediate inside int64 on both.
(def %cu-add64
  (fn (_ a b)
    (def lo (+ (bit-and a 4294967295) (bit-and b 4294967295)))
    (def hi (+ (+ (%cu-shr64 a 32) (%cu-shr64 b 32)) (%cu-shr64 lo 32)))
    (bit-or (bit-shl (bit-and hi 4294967295) 32) (bit-and lo 4294967295))))

(def %cu-rotr64
  (fn (_ x n)
    (bit-or (%cu-shr64 x n) (bit-shl x (- 64 n)))))

; the padded message as a BYTE LIST (cu/sha256.x's rule: a NUL in the
; padding would truncate a C string).  SHA-512 pads to 112 mod 128 and
; writes a SIXTEEN-byte big-endian length -- the top eight are always
; zero for any message x can hold.
(def %cu-sha512-pad
  (fn (_ text)
    (def len (byte-len text))
    (def bytes
      (let ((go (fn (self i acc)
                  (if (< i 0) acc
                    (self (- i 1) (pair (byte-at text i) acc))))))
        (go (- len 1) ())))
    (def zeros
      (let ((k (% (- 239 (% len 128)) 128)))
        (let ((go (fn (self n acc)
                    (if (= n 0) acc (self (- n 1) (pair 0 acc))))))
          (go k ()))))
    (def bits (* len 8))
    (def len-bytes
      (let ((go (fn (self shift acc)
                  (if (< shift 0) (reverse acc)
                    (self (- shift 8)
                      (pair (bit-and (%cu-shr64 bits shift) 255) acc))))))
        (go 56 ())))
    (append bytes
      (append (list 128)
        (append zeros (append (%cu-zero-list 8) len-bytes))))))

(def %cu-zero-list
  (fn (self n) (if (= n 0) () (pair 0 (self (- n 1))))))

; sixteen big-endian 64-bit words from a 128-byte block, then sixty-four
; extended; the window rides a reversed list, as SHA-256's does
(def %cu-sha512-schedule
  (fn (_ block)
    (def w16
      (let ((go (fn (self bs acc)
                  (if (null? bs) (reverse acc)
                    (self (%cu-drop8 bs) (pair (%cu-be64 bs) acc))))))
        (go block ())))
    (def extend
      (fn (self t wrev)
        (if (> t 79) (reverse wrev)
          (let ((w2 (%cu-nth 1 wrev)))
            (def w7 (%cu-nth 6 wrev))
            (def w15 (%cu-nth 14 wrev))
            (def w16v (%cu-nth 15 wrev))
            (def s0 (bit-xor (%cu-rotr64 w15 1)
                      (bit-xor (%cu-rotr64 w15 8) (%cu-shr64 w15 7))))
            (def s1 (bit-xor (%cu-rotr64 w2 19)
                      (bit-xor (%cu-rotr64 w2 61) (%cu-shr64 w2 6))))
            (self (+ t 1)
              (pair (%cu-add64 (%cu-add64 w16v s0) (%cu-add64 w7 s1))
                wrev))))))
    (extend 16 (reverse w16))))

(def %cu-nthrest
  (fn (self n l) (if (= n 0) l (self (- n 1) (rest l)))))

(def %cu-drop8 (fn (_ bs) (%cu-nthrest 8 bs)))

(def %cu-be64
  (fn (_ bs)
    (def go
      (fn (self k xs acc)
        (if (= k 0) acc
          (self (- k 1) (rest xs) (bit-or (bit-shl acc 8) (first xs))))))
    (go 8 bs 0)))

(def %cu-sha512-block
  (fn (_ hs block)
    (def w (%cu-sha512-schedule block))
    (def round
      (fn (self ws ks a b c d e f g h)
        (if (null? ws)
          (list a b c d e f g h)
          (let ((s1 (bit-xor (%cu-rotr64 e 14)
                      (bit-xor (%cu-rotr64 e 18) (%cu-rotr64 e 41)))))
            (def ch (bit-xor (bit-and e f) (bit-and (bit-xor e (- 0 1)) g)))
            (def t1 (%cu-add64 h
                      (%cu-add64 s1
                        (%cu-add64 ch
                          (%cu-add64 (first ks) (first ws))))))
            (def s0 (bit-xor (%cu-rotr64 a 28)
                      (bit-xor (%cu-rotr64 a 34) (%cu-rotr64 a 39))))
            (def maj (bit-xor (bit-and a b)
                       (bit-xor (bit-and a c) (bit-and b c))))
            (def t2 (%cu-add64 s0 maj))
            (self (rest ws) (rest ks)
              (%cu-add64 t1 t2) a b c (%cu-add64 d t1) e f g)))))
    (def out
      (round w %cu-sha512-k
        (%cu-nth 0 hs) (%cu-nth 1 hs) (%cu-nth 2 hs) (%cu-nth 3 hs)
        (%cu-nth 4 hs) (%cu-nth 5 hs) (%cu-nth 6 hs) (%cu-nth 7 hs)))
    (def add2
      (fn (self a b acc)
        (if (null? a) (reverse acc)
          (self (rest a) (rest b)
            (pair (%cu-add64 (first a) (first b)) acc)))))
    (add2 hs out ())))

(def %cu-word-hex64
  (fn (_ w)
    (def go
      (fn (self shift acc)
        (if (< shift 0) (list->string (reverse acc))
          (self (- shift 4)
            (pair (integer->char
                    (%cu-hex-digit (bit-and (%cu-shr64 w shift) 15)))
              acc)))))
    (go 60 ())))

(def cu-sha512
  (fn (_ text)
    (def blocks
      (fn (self bs hs)
        (if (null? bs) hs
          (let ((take (let ((go (fn (self2 l n acc)
                                  (if (= n 0) (pair (reverse acc) l)
                                    (self2 (rest l) (- n 1)
                                      (pair (first l) acc))))))
                        (go bs 128 ()))))
            (self (rest take) (%cu-sha512-block hs (first take)))))))
    (def hs (blocks (%cu-sha512-pad text) %cu-sha512-h))
    (string-concat (map (fn (_ w) (%cu-word-hex64 w)) hs))))

(def %cu-sha512sum
  (fn (_ argv stdin-thunk)
    (%cu-sum-applet (fn (_ t) (cu-sha512 t)) argv stdin-thunk)))
