; # x-coreutils -- the small tools, as applets
;
; ## cu/text3.x -- the parity expansion, text half
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; yes factor expand unexpand dos2unix unix2dos split shuf base64.
; The busybox set's remaining line tools: nothing here needs a door
; the bundle does not already hold.

; --- yes ----------------------------------------------------------------------

; yes(1) does not terminate; it ends when its writer fails, which is
; what a closed pipe does.  The loop therefore tests the write, not a
; counter -- the one applet with no bounded spec.
(def %cu-yes
  (fn (_ argv stdin-thunk)
    (def line
      (string-append
        (if (null? argv) "y" (%cu-join-with argv " "))
        "\n"))
    (def go
      (fn (self)
        (if (< (file-write 1 line) 0) 0 (self))))
    (go)))

; --- factor -------------------------------------------------------------------

; trial division: 2, then the odds, stopping at sqrt(n) by SQUARING the
; divisor rather than taking a root -- there is no sqrt on integers here
; and d*d <= n is the same test.
(def %cu-factor-of
  (fn (_ n)
    (def go
      (fn (self t d acc)
        (if (< t 2) (reverse acc)
          (if (> (* d d) t) (reverse (pair t acc))
            (if (= (% t d) 0)
              (self (/ (- t (% t d)) d) d (pair d acc))
              (self t (if (= d 2) 3 (+ d 2)) acc))))))
    (if (< n 2) () (go n 2 ()))))

(def %cu-factor-line
  (fn (_ s)
    (def n (%cu-num-prefix s))
    (display
      (string-append (%cu-int->str n)
        (string-append ":"
          (string-append
            (string-concat
              (map (fn (_ p) (string-append " " (%cu-int->str p)))
                (%cu-factor-of n)))
            "\n"))))))

(def %cu-factor
  (fn (_ argv stdin-thunk)
    (def each
      (fn (self ws)
        (if (null? ws) 0
          (do (%cu-factor-line (first ws)) (self (rest ws))))))
    (if (null? argv)
      (each (%cu-words-line (%cu-join-with (%cu-lines (stdin-thunk)) " ")))
      (each argv))))

; --- expand / unexpand --------------------------------------------------------

; expand and unexpand read -t off the declaration now.

(def %cu-spaces
  (fn (self k) (if (<= k 0) "" (string-append " " (self (- k 1))))))

; expand: a TAB advances to the next multiple of the tab width; every
; other byte advances the column by one
(def %cu-expand-line
  (fn (_ s w)
    (def end (byte-len s))
    (def go
      (fn (self i col acc)
        (if (>= i end) (string-concat (reverse acc))
          (let ((b (byte-at s i)))
            (if (= b 9)
              (let ((gap (- w (% col w))))
                (self (+ i 1) (+ col gap) (pair (%cu-spaces gap) acc)))
              (self (+ i 1) (+ col 1) (pair (%cu-b->s b) acc)))))))
    (go 0 0 ())))

(def %cu-expand
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "expand" argv))
    (def w (%cu-num-prefix (Opts value o "-t" "8")))
    (do (%cu-print-lines
          (map (fn (_ l) (%cu-expand-line l w))
            (%cu-lines (%cu-gather (Opts operands o) stdin-thunk))))
        0)))

; unexpand: the LEADING run of blanks becomes tabs plus a remainder
; (-a would fold interior runs too; the leading form is the default)
(def %cu-unexpand-line
  (fn (_ s w)
    (def end (byte-len s))
    (def lead
      (let ((go (fn (self i)
                  (if (>= i end) i
                    (if (= (byte-at s i) 32) (self (+ i 1)) i)))))
        (go 0)))
    (def tabs (/ (- lead (% lead w)) w))
    (def keep (% lead w))
    (def tab-run
      (let ((go (fn (self k) (if (<= k 0) "" (string-append "\t" (self (- k 1)))))))
        (go tabs)))
    (if (= tabs 0) s
      (string-append tab-run
        (string-append (%cu-spaces keep) (substring s lead end))))))

(def %cu-unexpand
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "unexpand" argv))
    (def w (%cu-num-prefix (Opts value o "-t" "8")))
    (do (%cu-print-lines
          (map (fn (_ l) (%cu-unexpand-line l w))
            (%cu-lines (%cu-gather (Opts operands o) stdin-thunk))))
        0)))

; --- dos2unix / unix2dos ------------------------------------------------------

(def %cu-strip-cr
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i acc)
        (if (>= i end) (string-concat (reverse acc))
          (if (= (byte-at s i) 13) (self (+ i 1) acc)
            (self (+ i 1) (pair (%cu-b->s (byte-at s i)) acc))))))
    (go 0 ())))

(def %cu-add-cr
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i acc)
        (if (>= i end) (string-concat (reverse acc))
          (if (= (byte-at s i) 10)
            (self (+ i 1) (pair "\r\n" acc))
            (self (+ i 1) (pair (%cu-b->s (byte-at s i)) acc))))))
    (go 0 (list))))

; both rewrite a named file IN PLACE (busybox's shape) and filter
; stdin to stdout when given no operand
; -u converts to unix endings and -d to dos, whichever applet was named:
; the two are one tool with a default, and the flags say which direction
; is wanted outright.
(def %cu-crlf-applet
  (fn (_ name to-dos-by-default? argv stdin-thunk)
    (def o (%cu-opts name argv))
    (def ops (Opts operands o))
    (def to-dos?
      (match
        ((Opts on? o "-d") #t)
        ((Opts on? o "-u") #f)
        (#t to-dos-by-default?)))
    (def conv
      (fn (_ s)
        (if to-dos? (%cu-add-cr (%cu-strip-cr s)) (%cu-strip-cr s))))
    (if (null? ops)
      (do (display (conv (stdin-thunk))) 0)
      (let ((go (fn (self os)
                  (if (null? os) 0
                    (do (file-write-all (first os)
                          (conv (file-read-all (first os))))
                        (self (rest os)))))))
        (go ops)))))

(def %cu-dos2unix
  (fn (_ argv stdin-thunk)
    (%cu-crlf-applet "dos2unix" #f argv stdin-thunk)))

(def %cu-unix2dos
  (fn (_ argv stdin-thunk)
    (%cu-crlf-applet "unix2dos" #t argv stdin-thunk)))

; --- split --------------------------------------------------------------------

; the suffix alphabet: aa ab ... az ba ...  (two letters, as split(1))
(def %cu-split-suffix
  (fn (_ n)
    (list->string
      (list (integer->char (+ 97 (/ (- n (% n 26)) 26)))
            (integer->char (+ 97 (% n 26)))))))

(def %cu-split-write
  (fn (_ prefix n text)
    (file-write-all (string-append prefix (%cu-split-suffix n)) text)))

(def %cu-split
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "split" argv))
    (def bv (Opts value o "-b"))
    (def lv (Opts value o "-l"))
    (def by-bytes? (not (null? bv)))
    (def size
      (let ((v (if (null? bv) lv bv)))
        (if (null? v) 1000 (%cu-num-prefix v))))
    (def ops (Opts operands o))
    (def prefix (if (pair? (rest ops)) (first (rest ops)) "x"))
    (def text
      (if (null? ops) (stdin-thunk)
        (if (string=? (first ops) "-") (stdin-thunk)
          (file-read-all (first ops)))))
    (if by-bytes?
      (let ((end (byte-len text)))
        (def go
          (fn (self i n)
            (if (>= i end) 0
              (let ((stop (if (> (+ i size) end) end (+ i size))))
                (do (%cu-split-write prefix n (substring text i stop))
                    (self stop (+ n 1)))))))
        (go 0 0))
      (let ((ls (%cu-lines text)))
        (def go
          (fn (self rest-ls n)
            (if (null? rest-ls) 0
              (let ((take (let ((go2 (fn (self2 l k acc)
                                       (if (if (= k 0) #t (null? l))
                                         (pair (reverse acc) l)
                                         (self2 (rest l) (- k 1)
                                           (pair (first l) acc))))))
                            (go2 rest-ls size ()))))
                (do (%cu-split-write prefix n
                      (string-concat
                        (map (fn (_ l) (string-append l "\n"))
                          (first take))))
                    (self (rest take) (+ n 1)))))))
        (go ls 0)))))

; --- shuf ---------------------------------------------------------------------

; Fisher-Yates over a vector, seeded from the clock; -n truncates the
; result, -e takes the operands themselves as the lines
(def %cu-list->vec
  (fn (_ l n)
    (def v (vec-make n ""))
    (def go
      (fn (self i xs)
        (if (null? xs) v
          (do (vec-set! v i (first xs)) (self (+ i 1) (rest xs))))))
    (go 0 l)))

(def %cu-vec->list
  (fn (_ v n)
    (def go
      (fn (self i acc)
        (if (< i 0) acc (self (- i 1) (pair (vec-ref v i) acc)))))
    (go (- n 1) ())))

(def %cu-shuffle
  (fn (_ items)
    (def n (length items))
    (def v (%cu-list->vec items n))
    (def r (rng-make (date-now-unix)))
    (def go
      (fn (self i)
        (if (<= i 0) (%cu-vec->list v n)
          (let ((j (rng-int r (+ i 1))))
            (let ((tmp (vec-ref v i)))
              (do (vec-set! v i (vec-ref v j))
                  (vec-set! v j tmp)
                  (self (- i 1))))))))
    (go (- n 1))))

(def %cu-take
  (fn (self l k)
    (if (if (<= k 0) #t (null? l)) ()
      (pair (first l) (self (rest l) (- k 1))))))

(def %cu-shuf
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "shuf" argv))
    (def nv (Opts value o "-n"))
    (def count (if (null? nv) 0 (%cu-num-prefix nv)))
    (def echo? (Opts on? o "-e"))
    (def rest1 (Opts operands o))
    ; -i LO-HI shuffles the range itself and reads nothing.
    (def iv (Opts value o "-i"))
    (def items
      (match
        ((not (null? iv)) (%cu-shuf-range iv))
        (echo? rest1)
        (#t (%cu-lines (%cu-gather rest1 stdin-thunk)))))
    (def out (%cu-shuffle items))
    (def picked (if (null? nv) out (%cu-take out count)))
    ; -o writes where the shuffle goes, so a caller can shuffle a file in
    ; place without a shell redirect reading it at the same time.
    (def dest (Opts value o "-o"))
    (if (null? dest)
      (do (%cu-print-lines picked) 0)
      (do (file-write-all dest
            (string-concat
              (map (fn (_ l) (string-append l "\n")) picked)))
          0))))

; "LO-HI" -> the integers from LO to HI, as strings.
(def %cu-shuf-range
  (fn (_ spec)
    (def dash
      (let ((go (fn (self i)
                  (if (>= i (byte-len spec)) (- 0 1)
                    (if (= (byte-at spec i) 45) i (self (+ i 1)))))))
        (go 0)))
    (if (< dash 0) ()
      (let ((lo (%cu-num-prefix (substring spec 0 dash)))
            (hi (%cu-num-prefix (substring spec (+ dash 1) (byte-len spec)))))
        (let ((go (fn (self n acc)
                    (if (< n lo) acc
                      (self (- n 1) (pair (%cu-int->str n) acc))))))
          (go hi ()))))))

; --- base64 -------------------------------------------------------------------

(def %cu-b64-alphabet
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(def %cu-b64-char
  (fn (_ v) (byte-at %cu-b64-alphabet v)))

; the inverse: -1 for anything outside the alphabet, so whitespace and
; the pad both fall out of the decoder's accumulator
(def %cu-b64-value
  (fn (_ b)
    (if (if (>= b 65) (<= b 90) #f) (- b 65)
      (if (if (>= b 97) (<= b 122) #f) (+ (- b 97) 26)
        (if (if (>= b 48) (<= b 57) #f) (+ (- b 48) 52)
          (if (= b 43) 62
            (if (= b 47) 63 (- 0 1))))))))

(def %cu-b64-encode
  (fn (_ s wrap)
    (def end (byte-len s))
    (def go
      (fn (self i col acc)
        (if (>= i end) (string-concat (reverse acc))
          (let ((b0 (byte-at s i)))
            (def have (- end i))
            (def b1 (if (> have 1) (byte-at s (+ i 1)) 0))
            (def b2 (if (> have 2) (byte-at s (+ i 2)) 0))
            (def n (+ (bit-shl b0 16) (+ (bit-shl b1 8) b2)))
            (def quad
              (list->string
                (list
                  (integer->char (%cu-b64-char (bit-and (bit-shr n 18) 63)))
                  (integer->char (%cu-b64-char (bit-and (bit-shr n 12) 63)))
                  (integer->char
                    (if (> have 1) (%cu-b64-char (bit-and (bit-shr n 6) 63)) 61))
                  (integer->char
                    (if (> have 2) (%cu-b64-char (bit-and n 63)) 61)))))
            (def col2 (+ col 4))
            (self (+ i 3) (if (>= col2 wrap) 0 col2)
              (if (>= col2 wrap) (pair "\n" (pair quad acc)) (pair quad acc)))))))
    (def body (go 0 0 ()))
    ; a final partial line still ends in a newline
    (if (= (byte-len body) 0) ""
      (if (= (byte-at body (- (byte-len body) 1)) 10) body
        (string-append body "\n")))))

(def %cu-b64-decode
  (fn (_ s)
    (def end (byte-len s))
    (def go
      (fn (self i acc bits nbits)
        (if (>= i end) (string-concat (reverse acc))
          (let ((v (%cu-b64-value (byte-at s i))))
            (if (< v 0) (self (+ i 1) acc bits nbits)
              (let ((bits2 (+ (bit-shl bits 6) v)))
                (if (>= (+ nbits 6) 8)
                  (self (+ i 1)
                    (pair (%cu-b->s
                            (bit-and (bit-shr bits2 (- (+ nbits 6) 8)) 255))
                      acc)
                    bits2 (- (+ nbits 6) 8))
                  (self (+ i 1) acc bits2 (+ nbits 6)))))))))
    (go 0 () 0 0)))

(def %cu-base64
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "base64" argv))
    (def d? (Opts on? o "-d"))
    (def text (%cu-gather (Opts operands o) stdin-thunk))
    ; -w sets the wrap column; 0 means one unbroken line.
    (def wrap (let ((v (Opts value o "-w"))) (if (null? v) 76 (%cu-num-prefix v))))
    (do (display (if d? (%cu-b64-decode text) (%cu-b64-encode text wrap))) 0)))
