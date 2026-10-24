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

(module cu/sha256)

(import cu/cli cu-opts cu-usage)
(import cu/prims append bit-and bit-or bit-shl bit-shr bit-xor byte-at
  byte-len cu-as-run cu-int->str cu-lines cu-max-status cu-nth cu-run-list
  file-err-op file-err-text file-or-err file-read-all file-write integer->char
  list->string map reverse string-append string-concat string=? substring)
(import cu/text cu-each-run-said cu-read-run-said cu-say cu-says)

(def cu-m32 4294967295)

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

(def %cu-rotr
  (fn (_ x n)
    (bit-and (bit-or (bit-shr x n) (bit-shl x (- 32 n))) cu-m32)))

(def cu-add32
  (fn (_ a b) (bit-and (+ a b) cu-m32)))

; the message as bytes, padded: 0x80, zeros to 56 mod 64, 8-byte
; big-endian bit length
(def cu-sha-pad
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
          (let ((w2 (cu-nth 1 wrev)))
            (def w7 (cu-nth 6 wrev))
            (def w15 (cu-nth 14 wrev))
            (def w16v (cu-nth 15 wrev))
            (def s0 (bit-xor (%cu-rotr w15 7)
                      (bit-xor (%cu-rotr w15 18) (bit-shr w15 3))))
            (def s1 (bit-xor (%cu-rotr w2 17)
                      (bit-xor (%cu-rotr w2 19) (bit-shr w2 10))))
            (self (+ t 1)
              (pair (cu-add32 (cu-add32 w16v s0) (cu-add32 w7 s1))
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
                      (bit-and (bit-xor e cu-m32) g)))
            (def t1 (cu-add32 h
                      (cu-add32 s1
                        (cu-add32 ch
                          (cu-add32 (first ks) (first ws))))))
            (def s0 (bit-xor (%cu-rotr a 2)
                      (bit-xor (%cu-rotr a 13) (%cu-rotr a 22))))
            (def maj (bit-xor (bit-and a b)
                       (bit-xor (bit-and a c) (bit-and b c))))
            (def t2 (cu-add32 s0 maj))
            (self (rest ws) (rest ks)
              (cu-add32 t1 t2) a b c
              (cu-add32 d t1) e f g)))))
    (def out
      (round w %cu-sha-k
        (cu-nth 0 hs) (cu-nth 1 hs) (cu-nth 2 hs) (cu-nth 3 hs)
        (cu-nth 4 hs) (cu-nth 5 hs) (cu-nth 6 hs) (cu-nth 7 hs)))
    (def add2
      (fn (self a b acc)
        (if (null? a) (reverse acc)
          (self (rest a) (rest b)
            (pair (cu-add32 (first a) (first b)) acc)))))
    (add2 hs out ())))

(def cu-hex-digit
  (fn (_ d) (if (< d 10) (+ 48 d) (+ 87 d))))

(def cu-word-hex
  (fn (_ w)
    (def go
      (fn (self shift acc)
        (if (< shift 0) (list->string (reverse acc))
          (self (- shift 4)
            (pair (integer->char
                    (cu-hex-digit (bit-and (bit-shr w shift) 15)))
              acc)))))
    (go 28 ())))

(def cu-sha256
  (fn (_ text)
    (def padded (cu-sha-pad text))
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
    (string-concat (map (fn (_ w) (cu-word-hex w)) hs))))

; The shared driver, not a second copy: md5sum, sha1sum and sha256sum emit
; through one loop, so a change (like growing -c) reaches all of them.
(def cu-sha256sum
  (fn (_ argv stdin-thunk)
    (cu-sum-applet "sha256sum" (fn (_ t) (cu-sha256 t)) argv stdin-thunk)))

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

; A digest is compared case-insensitively -- a checksum file may spell its hex
; either way -- and only at the comparison, not by lowering the whole string
; first.
(def %cu-lc-byte
  (fn (_ b) (if (if (>= b 65) (<= b 90) #f) (+ b 32) b)))

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
              (let ((text (cu-read-run-said says (rest row) stdin-thunk)))
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
              (list name ": WARNING: " (cu-int->str failed) " of " (cu-int->str total)
                    " computed checksums did NOT match\n"))))
        (if (= total 0)
          (file-write 2 (string-concat (list name ": " shown ": no checksum lines found\n")))
          ())
        (if (if (= total 0) #t (> failed 0)) 1 0))))

; -c: each list in turn, `-` for stdin.  A list that will not open is said and
; ends the run, answering 1; one that opens and will not read -- a directory --
; is a list of no lines.  Answers 1 once any list failed.
(def %cu-sum-check-lists
  (fn (self name digest lists stdin-thunk status? warn? st)
    (if (null? lists) st
      (let ((text (if (string=? (first lists) "-") (stdin-thunk)
                    (file-or-err (fn (_) (file-read-all (first lists)))))))
        (if (if (Err err? text) (not (eq? (file-err-op text) (lit read))) #f)
          (do (cu-say (cu-says name) (first lists) text) 1)
          (self name digest (rest lists) stdin-thunk status? warn?
            (cu-max-status st
              (%cu-sum-check-lines name digest (first lists)
                (if (Err err? text) () (cu-lines text)) stdin-thunk
                status? warn?))))))))

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

; -s and -w shape only what -c says: without it busybox refuses them with its
; usage text.  No operand is stdin.
(def cu-sum-applet
  (fn (_ name digest argv stdin-thunk)
    (def o (cu-opts name argv))
    (def ops (if (null? (Opts operands o)) (list "-") (Opts operands o)))
    (def one
      (fn (_ path text)
        (display (string-concat (list (digest text) "  " path "\n")))))
    (match
      ((Opts on? o "-c")
        (%cu-sum-check-lists name digest ops stdin-thunk
          (Opts on? o "-s") (Opts on? o "-w") 0))
      ((if (Opts on? o "-s") #t (Opts on? o "-w")) (cu-usage name))
      (#t (cu-each-run-said ops stdin-thunk (%cu-sum-says name) one 0)))))

(provide cu/sha256 cu-add32 cu-hex-digit cu-m32 cu-sha-pad cu-sha256
  cu-sha256sum cu-sum-applet cu-word-hex)
