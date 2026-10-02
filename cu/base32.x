; # x-coreutils -- the small tools, as applets
;
; ## cu/base32.x -- base32
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's base32 (coreutils/uudecode.c, libbb/uuencode.c).  Encoding takes
; five bytes to eight characters of A-Z and 2-7, = padding the last group,
; in lines of 76 (-w COL, 0 for none -- and then no newline at all).  -d
; decodes: blanks and controls are passed over, so is a character that is
; not of the alphabet, and = counts from a group's third character on; a
; group the input ends inside is `truncated input`.  -i is taken and changes
; nothing.  One file at most; `-` and none are standard input.

(def %b32-alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

; --- encoding -------------------------------------------------------------

; the eight characters of the five bytes in BS (nil past the input), the
; places past it =, as busybox's bb_b32encode pads them
(def %b32-group
  (fn (_ bs)
    (def n (length bs))
    (def b (fn (_ i) (if (< i n) (%cu-nth i bs) 0)))
    (def v (+ (* (b 0) 4294967296) (+ (* (b 1) 16777216) (+ (* (b 2) 65536) (+ (* (b 3) 256) (b 4))))))
    (def kept (match ((= n 1) 2) ((= n 2) 4) ((= n 3) 5) ((= n 4) 7) (#t 8)))
    (def go
      (fn (self i acc)
        (if (= i 8) (bytes->str (reverse acc))
          (self (+ i 1)
            (pair (if (< i kept)
                    (byte-at %b32-alphabet (& (>> v (- 35 (* 5 i))) 31))
                    #\=)
                  acc)))))
    (go 0 ())))

; The state of an encoding: the bytes waiting for a group of five, newest
; first, and the characters on the line so far.  COL 0 is no wrapping.
(def %b32-encode-take
  (fn (_ col)
    (fn (_ p s)
      (def text (first p))
      (def n (rest p))
      (def out (list ()))
      (def put
        (fn (self str k0)
          ; STR's characters onto the output, a newline each COL of them;
          ; answers the line's count after it
          (def len (byte-len str))
          (def go
            (fn (self2 i k)
              (match
                ((= i len) k)
                ((if (> col 0) (= (+ k 1) col) #f)
                  (do (%set-first! out (pair (string-append (substring str i (+ i 1)) "\n") (first out)))
                      (self2 (+ i 1) 0)))
                (#t (do (%set-first! out (pair (substring str i (+ i 1)) (first out)))
                        (self2 (+ i 1) (+ k 1)))))))
          (go 0 k0)))
      (def go
        (fn (self i held line)
          (match
            ((= i n) (pair held line))
            ((= (length held) 4)
              (self (+ i 1) () (put (%b32-group (reverse (pair (byte-at text i) held))) line)))
            (#t (self (+ i 1) (pair (byte-at text i) held) line)))))
      (let ((r (go 0 (first s) (rest s))))
        (do (file-write 1 (string-concat (reverse (first out))))
            (%cu-sweep-tick! %cu-sweep-lines)
            r)))))

(def %b32-encode
  (fn (_ name stdin-thunk col)
    (let ((r (%cu-fold-one name stdin-thunk (%b32-encode-take col) (pair () 0))))
      (let ((held (first (first r))) (k (rest (first r))))
        (do (if (pair? held)
              (let ((g (%b32-group (reverse held))))
                (file-write 1 (if (= col 0) g (%b32-wrap g k col))))
              (if (if (> col 0) (> k 0) #f) (file-write 1 "\n") ()))
            (rest r))))))

; the last group G, the line holding K0 characters before it, wrapped at COL,
; with the newline that ends the output
(def %b32-wrap
  (fn (_ g k0 col)
    (def go
      (fn (self i k acc)
        (if (= i 8)
          (string-concat (reverse (if (> k 0) (pair "\n" acc) acc)))
          (let ((c (substring g i (+ i 1))))
            (if (= (+ k 1) col)
              (self (+ i 1) 0 (pair "\n" (pair c acc)))
              (self (+ i 1) (+ k 1) (pair c acc)))))))
    (go 0 k0 ())))

; --- decoding -------------------------------------------------------------

; A character's value in the alphabet, either case, or -1
(def %b32-value
  (fn (_ c)
    (match
      ((if (>= c #\2) (<= c #\7) #f) (+ (- c #\2) 26))
      ((if (>= (| c 32) #\a) (<= (| c 32) #\z) #f) (- (| c 32) #\a))
      (#t -1))))

; The state of a decoding, in a vector: the group's value so far, its
; characters counted, and the = characters that ended the last of them.
(def %b32-decode-take
  (fn (_ p st)
    (def text (first p))
    (def n (rest p))
    (def out (list ()))
    (def put! (fn (_ b) (%set-first! out (pair (& b 255) (first out)))))
    ; the five bytes of V, all of them or, ended by EQ = characters, fewer
    (def emit
      (fn (_ v eq)
        (def all (list (>> v 32) (>> v 24) (>> v 16) (>> v 8) v))
        (def keep (if (= eq 0) 5 (- 5 (%cal/ (* (+ eq 1) 2) 3))))
        (map put! (%cu-take all keep))))
    (def go
      (fn (self i v k eq)
        (if (= i n) (list v k eq)
          (let ((c (byte-at text i)))
            (let ((d (match ((<= c #\space) -2) ((if (= c #\=) (> k 1) #f) 0) (#t (%b32-value c)))))
              (match
                ; a blank or control ends a run of =; anything else not of
                ; the alphabet is passed over
                ((= d -2) (self (+ i 1) v k 0))
                ((< d 0) (self (+ i 1) v k 0))
                (#t
                  (let ((v2 (+ (* v 32) d)) (eq2 (if (= c #\=) (+ eq 1) 0)))
                    (if (= k 7)
                      (do (emit (& v2 1099511627775) eq2) (self (+ i 1) 0 0 0))
                      (self (+ i 1) v2 (+ k 1) eq2))))))))))
    (let ((r (go 0 (vec-ref st 0) (vec-ref st 1) (vec-ref st 2))))
      (do (if (null? (first out)) ()
            (let ((bs (reverse (first out))))
              (file-write-run 1 (pair (bytes->str bs) (length bs)))))
          (vec-set! st 0 (first r))
          (vec-set! st 1 (%cu-nth 1 r))
          (vec-set! st 2 (%cu-nth 2 r))
          (%cu-sweep-tick! %cu-sweep-lines)
          st))))

(def %b32-decode
  (fn (_ name stdin-thunk)
    (let ((r (%cu-fold-one name stdin-thunk %b32-decode-take (vec-make 3 0))))
      (if (not (null? (rest r))) (rest r)
        (if (= (vec-ref (first r) 1) 0) ()
          (lit truncated))))))

(def %b32-usage
  (fn (_)
    (do (file-write 2
          (string-concat
            (list "Usage: base32 [-d] [-w COL] [FILE]\n\n"
                  "Base32 encode or decode FILE to standard output\n\n"
                  "\t-d\tDecode data\n"
                  "\t-w COL\tWrap lines at COL (default 76, 0 disables)\n")))
        1)))

; base32 [-d] [-w COL] [FILE]
(def %cu-base32
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "base32" argv))
    (def ops (Opts operands o))
    (def name (if (null? ops) "-" (first ops)))
    (def w (Opts value o "-w"))
    (def col (if (null? w) 76 (%cu-range-number "base32" w 0 2147483647)))
    (def said
      (fn (_ err)
        (match
          ((null? err) 0)
          ((eq? err (lit truncated))
            (do (file-write 2 "base32: truncated input\n") 1))
          (#t (do (file-write 2 (string-concat (list "base32: " name ": " (file-err-text err) "\n")))
                  1)))))
    (match
      ((> (length ops) 1) (%b32-usage))
      ((null? col) 1)
      ((Opts on? o "-d") (said (%b32-decode name stdin-thunk)))
      (#t (said (%b32-encode name stdin-thunk col))))))
