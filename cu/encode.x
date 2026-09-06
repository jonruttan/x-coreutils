; # x-coreutils -- the small tools, as applets
;
; ## cu/encode.x -- od, uuencode, uudecode
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The dump and the two historical transfer encodings.  od follows the
; GNU/busybox layout, NOT the BSD one macOS ships: no trailing pad to a
; fixed line width, and `*` for a repeated line.

; --- number formatting, zero- and space-padded ---------------------------------

(def %cu-zero-pad
  (fn (_ s w)
    (def gap (- w (byte-len s)))
    (def z (fn (self k) (if (<= k 0) "" (string-append "0" (self (- k 1))))))
    (if (<= gap 0) s (string-append (z gap) s))))

; --- od ------------------------------------------------------------------------

; the escapes od -c spells; everything printable is itself, everything
; else is three octal digits
(def %cu-od-char
  (fn (_ b)
    (if (= b 0) "\\0"
      (if (= b 7) "\\a"
        (if (= b 8) "\\b"
          (if (= b 9) "\\t"
            (if (= b 10) "\\n"
              (if (= b 11) "\\v"
                (if (= b 12) "\\f"
                  (if (= b 13) "\\r"
                    (if (if (>= b 32) (<= b 126) #f) (%cu-b->s b)
                      (%cu-zero-pad (%cu-oct->str b) 3))))))))))))

; a word of `size` bytes, LITTLE-endian, from position i
(def %cu-od-word
  (fn (_ s i size)
    (def end (byte-len s))
    (def go
      (fn (self k acc)
        (if (>= k size) acc
          (self (+ k 1)
            (+ acc
              (bit-shl (if (< (+ i k) end) (byte-at s (+ i k)) 0)
                (* 8 k)))))))
    (go 0 0)))

; the signed reading of the same word
(def %cu-od-signed
  (fn (_ v size)
    (def top (bit-shl 1 (- (* 8 size) 1)))
    (if (< v top) v (- v (* top 2)))))

; one field, padded to the width its type prints
(def %cu-od-field
  (fn (_ s i kind size)
    (if (eq? kind (lit c)) (%cu-pad-left (%cu-od-char (byte-at s i)) 4)
      (let ((v (%cu-od-word s i size)))
        (if (eq? kind (lit o))
          (string-append " "
            (%cu-zero-pad (%cu-oct->str v)
              (if (= size 1) 3 (if (= size 2) 6 11))))
          (if (eq? kind (lit x))
            (string-append " "
              (%cu-zero-pad (%cu-hexs v)
                (if (= size 1) 2 (if (= size 2) 4 8))))
            (if (eq? kind (lit u))
              (%cu-pad-left (%cu-int->str v)
                (if (= size 1) 4 (if (= size 2) 6 11)))
              (%cu-pad-left (%cu-int->str (%cu-od-signed v size))
                (if (= size 1) 5 (if (= size 2) 7 12))))))))))

(def %cu-od-address
  (fn (_ n radix)
    (if (eq? radix (lit n)) ""
      (if (eq? radix (lit d)) (%cu-zero-pad (%cu-int->str n) 7)
        (if (eq? radix (lit x)) (%cu-zero-pad (%cu-hexs n) 7)
          (%cu-zero-pad (%cu-oct->str n) 7))))))

; -t's argument is a letter and an optional size: o2, x1, c, d4
(def %cu-od-type
  (fn (_ spec)
    (def c (byte-at spec 0))
    (def size
      (if (> (byte-len spec) 1) (%cu-num-prefix (substring spec 1 (byte-len spec)))
        (if (= c 99) 1 (if (= c 97) 1 2))))
    (pair
      (if (= c 111) (lit o)
        (if (= c 120) (lit x)
          (if (= c 100) (lit d)
            (if (= c 117) (lit u) (lit c)))))
      size)))

(def %cu-od-line
  (fn (_ s from stop kind size)
    (def go
      (fn (self i acc)
        (if (>= i stop) (string-concat (reverse acc))
          (self (+ i size) (pair (%cu-od-field s i kind size) acc)))))
    (go from ())))

(def %cu-od-radix
  (fn (_ s)
    (let ((c (byte-at s 0)))
      (if (= c 110) (lit n)
        (if (= c 100) (lit d)
          (if (= c 120) (lit x) (lit o)))))))

; the settings a scan collects, read back with a default
(def %cu-od-opt
  (fn (_ st key dflt)
    (let ((e (Assoc entry key st)))
      (if (null? e) dflt (rest e)))))

; -A -t -N take an argument; -c -b -x -d -o are shorthands for a -t;
; anything else is an operand.  The scan RETURNS its settings rather
; than writing cells, which keeps the walk one level deep -- the
; nested-cell version of this was the file's one misnesting.
(def %cu-od-scan
  (fn (self as st)
    (if (null? as) st
      (let ((a (first as)))
        (if (string=? a "-A")
          (self (rest (rest as))
            (pair (pair (lit radix) (%cu-od-radix (first (rest as)))) st))
          (if (string=? a "-t")
            (self (rest (rest as))
              (pair (pair (lit type) (%cu-od-type (first (rest as)))) st))
            (if (string=? a "-N")
              (self (rest (rest as))
                (pair (pair (lit limit) (%cu-num-prefix (first (rest as)))) st))
              (if (string=? a "-v")
                (self (rest as) (pair (pair (lit verbose) #t) st))
                (self (rest as) (pair (%cu-od-short a) st))))))))))

; a shorthand letter, or the operand it turns out to be
(def %cu-od-short
  (fn (_ a)
    (if (string=? a "-c") (pair (lit type) (pair (lit c) 1))
      (if (string=? a "-b") (pair (lit type) (pair (lit o) 1))
        (if (string=? a "-x") (pair (lit type) (pair (lit x) 2))
          (if (string=? a "-d") (pair (lit type) (pair (lit u) 2))
            (if (string=? a "-o") (pair (lit type) (pair (lit o) 2))
              (pair (lit op) a))))))))

; a line repeated from the one before collapses to `*`, unless -v
(def %cu-od-dump
  (fn (_ text kind size rad v?)
    (def end (byte-len text))
    (def tail
      (fn (_)
        (do (if (eq? rad (lit n)) ()
              (display (string-append (%cu-od-address end rad) "\n")))
            0)))
    (def go
      (fn (self i prev starred)
        (if (>= i end) (tail)
          (let ((stop (if (> (+ i 16) end) end (+ i 16))))
            (let ((body (%cu-od-line text i stop kind size)))
              (if (%cu-od-repeat? v? body prev (- stop i))
                (do (if starred () (display "*\n"))
                    (self stop body #t))
                (do (display
                      (string-append (%cu-od-address i rad)
                        (string-append body "\n")))
                    (self stop body #f))))))))
    (go 0 () #f)))

(def %cu-od-repeat?
  (fn (_ v? body prev width)
    (if v? #f
      (if (null? prev) #f
        (if (string=? body prev) (= width 16) #f)))))

; -An, -tx1, -N10: the argument may ride the flag.  Splitting it off
; first keeps the scan a plain token walk.
(def %cu-od-attached?
  (fn (_ a)
    (if (< (byte-len a) 3) #f
      (let ((h (substring a 0 2)))
        (if (string=? h "-A") #t
          (if (string=? h "-t") #t (string=? h "-N")))))))

(def %cu-od-normalize
  (fn (self as acc)
    (if (null? as) (reverse acc)
      (let ((a (first as)))
        (if (%cu-od-attached? a)
          (self (rest as)
            (pair (substring a 2 (byte-len a))
              (pair (substring a 0 2) acc)))
          (self (rest as) (pair a acc)))))))

(def %cu-od
  (fn (_ argv stdin-thunk)
    (def st (%cu-od-scan (%cu-od-normalize argv ()) ()))
    (def ops
      (reverse
        (map (fn (_ e) (rest e))
          (filter (fn (_ e) (eq? (first e) (lit op))) st))))
    (def ty (%cu-od-opt st (lit type) (pair (lit o) 2)))
    (def lim (%cu-od-opt st (lit limit) (- 0 1)))
    (def text0 (%cu-gather ops stdin-thunk))
    (def text
      (if (if (>= lim 0) (< lim (byte-len text0)) #f)
        (substring text0 0 lim) text0))
    (%cu-od-dump text (first ty) (rest ty)
      (%cu-od-opt st (lit radix) (lit o))
      (%cu-od-opt st (lit verbose) #f))))
; --- uuencode / uudecode --------------------------------------------------------

; the historical alphabet: six bits plus 32, with 0 written as a
; backtick rather than a space (the busybox table)
(def %cu-uu-char
  (fn (_ v) (if (= v 0) 96 (+ v 32))))

(def %cu-uu-value
  (fn (_ b) (if (= b 96) 0 (bit-and (- b 32) 63))))

(def %cu-uu-line
  (fn (_ s from stop)
    (def n (- stop from))
    (def go
      (fn (self i acc)
        (if (>= i stop) (string-concat (reverse acc))
          (let ((b0 (byte-at s i)))
            (def b1 (if (< (+ i 1) stop) (byte-at s (+ i 1)) 0))
            (def b2 (if (< (+ i 2) stop) (byte-at s (+ i 2)) 0))
            (def w (+ (bit-shl b0 16) (+ (bit-shl b1 8) b2)))
            (self (+ i 3)
              (pair
                (list->string
                  (list
                    (integer->char (%cu-uu-char (bit-and (bit-shr w 18) 63)))
                    (integer->char (%cu-uu-char (bit-and (bit-shr w 12) 63)))
                    (integer->char (%cu-uu-char (bit-and (bit-shr w 6) 63)))
                    (integer->char (%cu-uu-char (bit-and w 63)))))
                acc))))))
    (string-append (%cu-b->s (%cu-uu-char n)) (go from ()))))

(def %cu-uuencode
  (fn (_ argv stdin-thunk)
    (def m? (%cu-has-flag? argv "-m"))
    (def ops (filter (fn (_ x) (not (%cu-option-token? x))) argv))
    ; uuencode NAME, or uuencode FILE NAME
    (def name (if (null? ops) "-" (%cu-last ops)))
    (def src (if (pair? (rest ops)) (list (first ops)) ()))
    (def text (%cu-gather src stdin-thunk))
    (def end (byte-len text))
    (if m?
      (do (display (string-concat (list "begin-base64 644 " name "\n")))
          (display (%cu-b64-encode text 76))
          (display "====\n")
          0)
      (let ((go (fn (self i)
                  (if (>= i end) ()
                    (let ((stop (if (> (+ i 45) end) end (+ i 45))))
                      (do (display (string-append (%cu-uu-line text i stop) "\n"))
                          (self stop)))))))
        (do (display (string-concat (list "begin 644 " name "\n")))
            (go 0)
            (display "`\nend\n")
            0)))))

(def %cu-uu-decode-line
  (fn (_ line)
    (def n (%cu-uu-value (byte-at line 0)))
    (def end (byte-len line))
    (def go
      (fn (self i out acc)
        (if (if (>= i end) #t (>= out n)) (string-concat (reverse acc))
          (let ((c0 (%cu-uu-value (byte-at line i))))
            (def c1 (if (< (+ i 1) end) (%cu-uu-value (byte-at line (+ i 1))) 0))
            (def c2 (if (< (+ i 2) end) (%cu-uu-value (byte-at line (+ i 2))) 0))
            (def c3 (if (< (+ i 3) end) (%cu-uu-value (byte-at line (+ i 3))) 0))
            (def w (+ (bit-shl c0 18)
                     (+ (bit-shl c1 12) (+ (bit-shl c2 6) c3))))
            (def three
              (list (bit-and (bit-shr w 16) 255)
                    (bit-and (bit-shr w 8) 255)
                    (bit-and w 255)))
            (def keep (let ((left (- n out))) (if (> left 3) 3 left)))
            (self (+ i 4) (+ out 3)
              (pair (string-concat
                      (map (fn (_ b) (%cu-b->s b)) (%cu-take three keep)))
                acc))))))
    (if (= n 0) "" (go 1 0 ()))))

; uudecode reads either encoding, choosing on the begin line
(def %cu-uudecode
  (fn (_ argv stdin-thunk)
    (def ls (%cu-lines (%cu-gather argv stdin-thunk)))
    (def b64?
      (let ((go (fn (self xs)
                  (if (null? xs) #f
                    (if (if (> (byte-len (first xs)) 12)
                          (string=? (substring (first xs) 0 12) "begin-base64")
                          #f)
                      #t (self (rest xs)))))))
        (go ls)))
    ; the body is what lies between the begin line and the terminator
    (def body
      (let ((skip (fn (self xs)
                    (if (null? xs) ()
                      (if (if (> (byte-len (first xs)) 5)
                            (string=? (substring (first xs) 0 5) "begin") #f)
                        (rest xs)
                        (self (rest xs)))))))
        (let ((stop (fn (self xs acc)
                      (if (null? xs) (reverse acc)
                        (if (if (string=? (first xs) "`") #t
                              (if (string=? (first xs) "end") #t
                                (string=? (first xs) "====")))
                          (reverse acc)
                          (self (rest xs) (pair (first xs) acc)))))))
          (stop (skip ls) ()))))
    (do (display
          (if b64?
            (%cu-b64-decode (%cu-join-with body "\n"))
            (string-concat
              (map (fn (_ l) (%cu-uu-decode-line l))
                (filter (fn (_ l) (> (byte-len l) 0)) body)))))
        0)))
