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

(module cu/ascii)

(import cu/cli cu-opts)
(import cu/dump dp-udigits)
(import cu/prims cu-int->str cu-nth file-err-text file-write map string-append)
(import cu/text cu-fold-pieces cu-pad-left cu-pad-zero cu-pieces)

(import x/codec/crc32)

(def %ascii-names
  (list "NUL" "SOH" "STX" "ETX" "EOT" "ENQ" "ACK" "BEL" "BS " "HT " "NL " "VT "
        "FF " "CR " "SO " "SI " "DLE" "DC1" "DC2" "DC3" "DC4" "NAK" "SYN" "ETB"
        "CAN" "EM " "SUB" "ESC" "FS " "GS " "RS " "US "))

; a column: the number in decimal, WIDE wide, its hex in two, and what it is
(def %ascii-cell
  (fn (_ n wide shown)
    (%str-concat
      (list (cu-pad-left (cu-int->str n) wide) " "
            (cu-pad-zero (dp-udigits n 16 #f) 2) " " shown))))

(def %ascii-row
  (fn (_ i)
    (def ch (fn (_ n) (bytes->str (list n))))
    (%str-concat
      (list (%ascii-cell i 3 (cu-nth i %ascii-names))
            (%ascii-cell (+ i 16) 4 (cu-nth (+ i 16) %ascii-names))
            (%ascii-cell (+ i 32) 4 (ch (+ i 32)))
            (%ascii-cell (+ i 48) 4 (ch (+ i 48)))
            (%ascii-cell (+ i 64) 4 (ch (+ i 64)))
            (%ascii-cell (+ i 80) 4 (ch (+ i 80)))
            (%ascii-cell (+ i 96) 5 (ch (+ i 96)))
            (%ascii-cell (+ i 112) 5 (if (= i 15) "DEL" (ch (+ i 112))))
            "\n"))))

(def cu-ascii
  (fn (_ argv stdin-thunk)
    (do (file-write 1
          (%str-concat
            (pair "Dec Hex    Dec Hex    Dec Hex  Dec Hex  Dec Hex  Dec Hex   Dec Hex   Dec Hex\n"
                  (map %ascii-row (List range 0 16)))))
        0)))

; --- crc32 --------------------------------------------------------------------

; a piece P folded into the CRC so far, by x/codec/crc32's
(def %crc32-take
  (fn (_ p crc) (Crc32 update crc (first p) 0 (rest p))))

; crc32 [FILE]...: each file's CRC, and its name; with none, standard
; input's, unnamed.  A file that will not open is said and passed; one that
; will not read ends the run.
(def cu-crc32
  (fn (_ argv stdin-thunk)
    (def ops (Opts operands (cu-opts "crc32" argv)))
    (def one
      (fn (_ name shown)
        (let ((src (cu-pieces name stdin-thunk)))
          (if (Err err? src)
            (do (file-write 2 (%str-concat (list "crc32: can't open '" name "': "
                                                   (file-err-text src) "\n")))
                (lit missing))
            (let ((r (cu-fold-pieces src %crc32-take 0)))
              (do (src (lit close))
                  (if (not (null? (rest r)))
                    (do (file-write 2 (%str-concat (list "crc32: " name ": "
                                                           (file-err-text (rest r)) "\n")))
                        (lit fatal))
                    (do (file-write 1
                          (%str-concat
                            (list (cu-pad-zero (dp-udigits (first r) 16 #f) 8)
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
(def cu-uuidgen
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "uuidgen" argv))
    (if (pair? (Opts operands o)) (%uuidgen-usage)
      (do (file-write 1 (string-append ((Random hw) uuid) "\n")) 0))))

(provide cu/ascii cu-ascii cu-crc32 cu-uuidgen)
