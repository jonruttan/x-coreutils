; # x-coreutils -- the small tools, as applets
;
; ## cu/ascii.x -- ascii, crc32, uuidgen
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Three of busybox's small ones.  ascii (miscutils/ascii.c) prints the ASCII
; table, eight columns of decimal, hex and the character or its name, and
; takes no notice of its arguments.  crc32 (coreutils/cksum.c) is cksum's
; sibling: the zlib CRC-32, least significant bit first, in eight hex digits,
; with no length folded in.  uuidgen (util-linux/uuidgen.c) prints a random
; version-4 UUID -- the platform's, from the kernel's random source.

; --- ascii --------------------------------------------------------------------

(def %ascii-names
  (list "NUL" "SOH" "STX" "ETX" "EOT" "ENQ" "ACK" "BEL" "BS " "HT " "NL " "VT "
        "FF " "CR " "SO " "SI " "DLE" "DC1" "DC2" "DC3" "DC4" "NAK" "SYN" "ETB"
        "CAN" "EM " "SUB" "ESC" "FS " "GS " "RS " "US "))

; a column: the number in decimal, WIDE wide, its hex in two, and what it is
(def %ascii-cell
  (fn (_ n wide shown)
    (string-concat
      (list (%cu-pad-left (%cu-int->str n) wide) " "
            (%cu-pad-zero (%dp-udigits n 16 #f) 2) " " shown))))

(def %ascii-row
  (fn (_ i)
    (def ch (fn (_ n) (bytes->str (list n))))
    (string-concat
      (list (%ascii-cell i 3 (%cu-nth i %ascii-names))
            (%ascii-cell (+ i 16) 4 (%cu-nth (+ i 16) %ascii-names))
            (%ascii-cell (+ i 32) 4 (ch (+ i 32)))
            (%ascii-cell (+ i 48) 4 (ch (+ i 48)))
            (%ascii-cell (+ i 64) 4 (ch (+ i 64)))
            (%ascii-cell (+ i 80) 4 (ch (+ i 80)))
            (%ascii-cell (+ i 96) 5 (ch (+ i 96)))
            (%ascii-cell (+ i 112) 5 (if (= i 15) "DEL" (ch (+ i 112))))
            "\n"))))

(def %cu-ascii
  (fn (_ argv stdin-thunk)
    (do (file-write 1
          (string-concat
            (pair "Dec Hex    Dec Hex    Dec Hex  Dec Hex  Dec Hex  Dec Hex   Dec Hex   Dec Hex\n"
                  (map %ascii-row (List range 0 16)))))
        0)))

; --- crc32 --------------------------------------------------------------------

; the table, computed: each byte's CRC under the reflected polynomial
; 0xEDB88320, the low bit shifted out first
(def %crc32-entry
  (fn (self k c)
    (if (= k 0) c
      (self (- k 1) (if (= (& c 1) 0) (>> c 1) (^ (>> c 1) 3988292384))))))

(def %crc32-table (vec-build 256 (fn (_ i) (%crc32-entry 8 i))))

; a piece P folded into the CRC so far
(def %crc32-take
  (fn (_ p crc)
    (def text (first p))
    (def n (rest p))
    (def go
      (fn (self i acc)
        (if (= i n) acc
          (do (if (= (& i %cu-sweep-steps) 0) (%cu-sweep! i) ())
              (self (+ i 1)
                (^ (vec-ref %crc32-table (& (^ acc (byte-at text i)) 255)) (>> acc 8)))))))
    (go 0 crc)))

; crc32 [FILE]...: each file's CRC, and its name; with none, standard
; input's, unnamed.  A file that will not open is said and passed; one that
; will not read ends the run.
(def %cu-crc32
  (fn (_ argv stdin-thunk)
    (def ops (Opts operands (%cu-opts "crc32" argv)))
    (def one
      (fn (_ name shown)
        (let ((src (%cu-pieces name stdin-thunk)))
          (if (Err err? src)
            (do (file-write 2 (string-concat (list "crc32: can't open '" name "': "
                                                   (file-err-text src) "\n")))
                (lit missing))
            (let ((r (%cu-fold-pieces src %crc32-take 4294967295)))
              (do (src (lit close))
                  (if (not (null? (rest r)))
                    (do (file-write 2 (string-concat (list "crc32: " name ": "
                                                           (file-err-text (rest r)) "\n")))
                        (lit fatal))
                    (do (file-write 1
                          (string-concat
                            (list (%cu-pad-zero (%dp-udigits (& (^ (first r) 4294967295) 4294967295) 16 #f) 8)
                                  (if shown (string-append " " name) "") "\n")))
                        (lit ok)))))))))
    (def each
      (fn (self names st)
        (if (null? names) st
          (let ((r (one (first names) #t)))
            (match
              ((eq? r (lit fatal)) 1)
              ((eq? r (lit missing)) (self (rest names) 1))
              (#t (self (rest names) st)))))))
    (if (null? ops)
      (if (eq? (one "-" #f) (lit ok)) 0 1)
      (each ops 0))))

; --- uuidgen ------------------------------------------------------------------

(def %uuidgen-usage
  (fn (_) (do (file-write 2 "Usage: uuidgen\n\nGenerate a random UUID\n") 1)))

; uuidgen [-r]: -r, a random UUID, is the only kind
(def %cu-uuidgen
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "uuidgen" argv))
    (if (pair? (Opts operands o)) (%uuidgen-usage)
      (do (file-write 1 (string-append ((Random hw) uuid) "\n")) 0))))
