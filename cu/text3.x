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
        (match
          ((< t 2) (reverse acc))
          ((> (* d d) t) (reverse (pair t acc)))
          ((= (% t d) 0) (self (/ (- t (% t d)) d) d (pair d acc)))
          (#t (self t (if (= d 2) 3 (+ d 2)) acc)))))
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
; other byte advances the column by one.  Under -i only the leading run
; of blanks is expanded: LEAD? holds while nothing but blanks has been
; seen, and a tab past that point is copied.
(def %cu-expand-line
  (fn (_ s w init?)
    (def end (byte-len s))
    (def go
      (fn (self i col lead? acc)
        (if (>= i end) (string-concat (reverse acc))
          (let ((b (byte-at s i)))
            (match
              ((if (= b 9) (if init? lead? #t) #f)
                (let ((gap (- w (% col w))))
                  (self (+ i 1) (+ col gap) lead? (pair (%cu-spaces gap) acc))))
              ((= b 32) (self (+ i 1) (+ col 1) lead? (pair " " acc)))
              (#t (self (+ i 1) (+ col 1) #f (pair (%cu-b->s b) acc))))))))
    (go 0 0 #t ())))

(def %cu-expand
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "expand" argv))
    (def w (%cu-num-prefix (Opts value o "-t" "8")))
    (def init? (Opts on? o "-i"))
    (def g (%cu-gather-said (Opts operands o) stdin-thunk (%cu-says "expand") #f))
    (do (%cu-print-lines
          (%cu-map-swept (fn (_ l) (%cu-expand-line l w init?)) (%cu-lines (first g))))
        (rest g))))

(def %cu-tabs
  (fn (self k) (if (<= k 0) "" (string-append "\t" (self (- k 1))))))

; A run of blanks that carried the column from FROM to TO, respelled: a
; tab for each stop it crossed, then spaces for what is left past the
; last stop -- or the whole run as spaces when it crossed none.  A run
; that is one lone space stays a space even on a stop; a lone tab is a
; tab already and comes back as one.
(def %cu-unexpand-run
  (fn (_ from to w one-space?)
    (def stops (- (/ (- to (% to w)) w) (/ (- from (% from w)) w)))
    (match
      (one-space? " ")
      ((= stops 0) (%cu-spaces (- to from)))
      (#t (string-append (%cu-tabs stops) (%cu-spaces (% to w)))))))

; unexpand: the leading run of blanks -- spaces and tabs both -- becomes
; tabs plus a remainder; with ALL? every run does.  When only the leading
; run is respelled, the line past it is copied as it is.
(def %cu-unexpand-line
  (fn (_ s w all?)
    (def end (byte-len s))
    ; The run of blanks at I, from column COL: (END-INDEX COLUMN COUNT).
    (def run-end
      (fn (self i col n)
        (if (>= i end) (list i col n)
          (let ((b (byte-at s i)))
            (match
              ((= b 32) (self (+ i 1) (+ col 1) (+ n 1)))
              ((= b 9)  (self (+ i 1) (+ col (- w (% col w))) (+ n 1)))
              (#t (list i col n)))))))
    (def go
      (fn (self i col lead? acc)
        (if (>= i end) (string-concat (reverse acc))
          (let ((b (byte-at s i)))
            (match
              ((not (if (= b 32) #t (= b 9)))
                (self (+ i 1) (+ col 1) #f (pair (%cu-b->s b) acc)))
              ((if all? #t lead?)
                (let ((r (run-end i col 0)))
                  (def to (first (rest r)))
                  (def n (first (rest (rest r))))
                  (self (first r) to #f
                    (pair (%cu-unexpand-run col to w (if (= n 1) (= b 32) #f))
                          acc))))
              (#t (string-concat (reverse (pair (substring s i end) acc)))))))))
    (go 0 0 #t ())))

; Which runs are respelled: the leading one, unless -a -- or -t, which says it
; too -- asks for every one; and -f, first only, keeps it to the leading run
; whatever else was given, and in whichever order.
(def %cu-unexpand
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "unexpand" argv))
    (def w (%cu-num-prefix (Opts value o "-t" "8")))
    (def all? (match
                ((Opts on? o "-f") #f)
                ((Opts on? o "-a") #t)
                (#t (not (null? (Opts value o "-t"))))))
    (def g
      (%cu-gather-said (Opts operands o) stdin-thunk (%cu-says "unexpand") #f))
    (do (%cu-print-lines
          (map (fn (_ l) (%cu-unexpand-line l w all?)) (%cu-lines (first g))))
        (rest g))))

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
      ; a file that cannot be read, or written back, is said, and the rest are
      ; still converted
      (let ((go (fn (self os st)
                  (if (null? os) st
                    (let ((text (%cu-read-said (%cu-says name) (first os))))
                      (if (Err err? text) (self (rest os) 1)
                        (let ((w (file-or-err
                                   (fn (_)
                                     (file-write-all (first os) (conv text))))))
                          (if (Err err? w)
                            (do (file-write 2
                                  (string-append
                                    ((%cu-says name) (first os) w) "\n"))
                                (self (rest os) 1))
                            (self (rest os) st)))))))))
        (go ops 0)))))

(def %cu-dos2unix
  (fn (_ argv stdin-thunk)
    (%cu-crlf-applet "dos2unix" #f argv stdin-thunk)))

(def %cu-unix2dos
  (fn (_ argv stdin-thunk)
    (%cu-crlf-applet "unix2dos" #t argv stdin-thunk)))

; --- split --------------------------------------------------------------------

; the suffix alphabet: aa ab ... az ba ...  (two letters, as split(1))
; the Nth suffix of WIDTH letters, counting in base 26 with the last
; letter moving fastest: aa ab ... under the default width of two
(def %cu-split-suffix
  (fn (_ n width)
    (def go
      (fn (self k v acc)
        (if (<= k 0) (list->string acc)
          (self (- k 1) (/ (- v (% v 26)) 26)
            (pair (integer->char (+ 97 (% v 26))) acc)))))
    (go width n ())))

(def %cu-split-write
  (fn (_ prefix n width text)
    (file-write-all (string-append prefix (%cu-split-suffix n width)) text)))

; split [FILE [PREFIX]]: a third operand is refused
(def %cu-split
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "split" argv))
    (%cu-operands "split" (Opts operands o) 0 2
      (fn (_) (%cu-split-run o stdin-thunk)))))

(def %cu-split-run
  (fn (_ o stdin-thunk)
    (def bv (Opts value o "-b"))
    (def lv (Opts value o "-l"))
    (def width
      (let ((v (Opts value o "-a"))) (if (null? v) 2 (%cu-num-prefix v))))
    (def by-bytes? (not (null? bv)))
    (def size
      (let ((v (if (null? bv) lv bv)))
        (if (null? v) 1000 (%cu-num-prefix v))))
    (def ops (Opts operands o))
    (def prefix (if (if (pair? ops) (pair? (rest ops)) #f) (first (rest ops)) "x"))
    (def text
      (if (null? ops) (stdin-thunk)
        (if (string=? (first ops) "-") (stdin-thunk)
          (%cu-read-said %cu-split-says (first ops)))))
    (if (Err err? text) 1
      (if by-bytes?
        (let ((end (byte-len text)))
          (def go
            (fn (self i n)
              (if (>= i end) 0
                (let ((stop (if (> (+ i size) end) end (+ i size))))
                  (do (%cu-split-write prefix n width (substring text i stop))
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
                  (do (%cu-split-write prefix n width
                        (string-concat
                          (map (fn (_ l) (string-append l "\n"))
                            (first take))))
                      (self (rest take) (+ n 1)))))))
          (go ls 0))))))

; a file split cannot read, said as split says it: "cannot open 'F' for
; reading" for one that would not open, "F: REASON" for one that would not read
(def %cu-split-says
  (fn (_ name err)
    (if (eq? (file-err-op err) (lit read))
      (string-concat (list "split: " name ": " (file-err-text err)))
      (string-concat
        (list "split: cannot open '" name "' for reading: " (file-err-text err))))))

; --- shuf ---------------------------------------------------------------------

; Fisher-Yates over a vector, seeded from the clock; -n truncates the
; result, -e takes the operands themselves as the lines

; the N items of L as a vector.  Vector build asks for each slot in turn, and
; the filler walks L, sweeping as it goes; a vector made first and set after
; would pay for filling every slot twice, the first time in a loop of the
; platform's that no sweep reaches.
(def %cu-list->vec
  (fn (_ l n)
    (let ((cur (list l)))
      (vec-build n
        (fn (_ i)
          (let ((xs (first cur)))
            (do (%cu-sweep-at i %cu-sweep-steps)
                (set-first! cur (rest xs))
                (first xs))))))))

(def %cu-vec->list
  (fn (_ v n)
    (def go
      (fn (self i acc)
        (if (< i 0) acc
          (do (%cu-sweep-at i %cu-sweep-steps)
              (self (- i 1) (pair (vec-ref v i) acc))))))
    (go (- n 1) ())))

(def %cu-shuffle
  (fn (_ items)
    (def n (length items))
    (def v (%cu-list->vec items n))
    (def r (rng-make (date-now-unix)))
    (def go
      (fn (self i)
        (if (<= i 0) (%cu-vec->list v n)
          (let ((j (do (%cu-sweep-at i %cu-sweep-lines) (rng-int r (+ i 1)))))
            (let ((tmp (vec-ref v i)))
              (do (vec-set! v i (vec-ref v j))
                  (vec-set! v j tmp)
                  (self (- i 1))))))))
    (go (- n 1))))

(def %cu-take
  (fn (self l k)
    (if (if (<= k 0) #t (null? l)) ()
      (pair (first l) (self (rest l) (- k 1))))))

; With -e the operands are what is shuffled, as many as are given; -i shuffles
; a range and takes none; otherwise there is one FILE at most.
(def %cu-shuf
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "shuf" argv))
    (%cu-operands "shuf" (Opts operands o) 0
      (match
        ((Opts on? o "-e") ())
        ((not (null? (Opts value o "-i"))) 0)
        (#t 1))
      (fn (_) (%cu-shuf-run o stdin-thunk)))))

(def %cu-shuf-run
  (fn (_ o stdin-thunk)
    (def nv (Opts value o "-n"))
    (def count (if (null? nv) 0 (%cu-num-prefix nv)))
    (def echo? (Opts on? o "-e"))
    (def z? (Opts on? o "-z"))
    (def rest1 (Opts operands o))
    ; -i LO-HI shuffles the range itself and reads nothing.
    (def iv (Opts value o "-i"))
    ; -z makes the NUL the delimiter on both sides, so a line may hold a
    ; newline; the input is then read as bytes (cu/prims.x).
    ; what is shuffled, and whether reading it failed
    (def read
      (match
        ((not (null? iv)) (pair (%cu-shuf-range iv) 0))
        (echo? (pair rest1 0))
        (z? (%cu-delim-fields-said rest1 stdin-thunk 0 (%cu-read-error "shuf")
               #f))
        (#t (let ((g (%cu-gather-said rest1 stdin-thunk (%cu-read-error "shuf")
                       #f)))
              (pair (%cu-lines (first g)) (rest g))))))
    (def items (first read))
    (def out (%cu-shuffle items))
    (def picked (if (null? nv) out (%cu-take out count)))
    ; -o writes where the shuffle goes, so a caller can shuffle a file in
    ; place without a shell redirect reading it at the same time.
    (def dest (Opts value o "-o"))
    (match
      ((> (rest read) 0) 1)
      ((if (null? dest) z? #f) (do (%cu-print-fields picked 0) 0))
      ((null? dest) (do (%cu-print-lines picked) 0))
      (z?
        (let ((fd (file-open-or-err file-open-write dest)))
          (if (Err err? fd) (%cu-shuf-cannot dest fd)
            (do (%cu-print-fields-to fd picked 0) (file-close fd) 0))))
      ; each line put out as it is walked, which sweeps as it goes
      (#t
        (let ((fd (file-open-or-err file-open-write dest)))
          (if (Err err? fd) (%cu-shuf-cannot dest fd)
            (do (%cu-print-lines-to fd picked) (file-close fd) 0)))))))

; an -o file shuf cannot write, said as shuf says it
(def %cu-shuf-cannot
  (fn (_ dest r)
    (do (file-write 2
          (string-concat (list "shuf: " dest ": " (file-err-text r) "\n")))
        1)))

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
        ; K counts the numbers made, for the sweeps
        (let ((go (fn (self n k acc)
                    (if (< n lo) acc
                      (do (%cu-sweep-at k %cu-sweep-steps)
                          (self (- n 1) (+ k 1) (pair (%cu-int->str n) acc)))))))
          (go hi 0 ()))))))

; --- base64 -------------------------------------------------------------------

(def %cu-b64-alphabet
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(def %cu-b64-char
  (fn (_ v) (byte-at %cu-b64-alphabet v)))

; the inverse: -1 for anything outside the alphabet, the pad among them
(def %cu-b64-value
  (fn (_ b)
    (match
      ((if (>= b 65) (<= b 90) #f) (- b 65))
      ((if (>= b 97) (<= b 122) #f) (+ (- b 97) 26))
      ((if (>= b 48) (<= b 57) #f) (+ (- b 48) 52))
      ((= b 43) 62)
      ((= b 47) 63)
      (#t (- 0 1)))))

; S in base64, put out as it is made: lines of WRAP characters, each ended by a
; newline, the last one too when it holds any; WRAP 0 is one line and no
; newline.  LINE holds the characters made since the last write, newest first,
; and COL how many: a line goes out as it fills, and an unwrapped encoding
; every 4,096 characters, so the encoding is never held whole.  A step takes
; three bytes, and the walk sweeps as it goes.
(def %cu-b64-put
  (fn (_ s wrap)
    (def end (byte-len s))
    (def full (if (= wrap 0) 4096 wrap))
    (def out
      (fn (_ line)
        (display (bytes->str (reverse (if (= wrap 0) line (pair 10 line)))))))
    ; the characters CS onto LINE, and a line out when it fills
    (def push
      (fn (self cs line col)
        (match
          ((null? cs) (pair line col))
          ((= (+ col 1) full) (do (out (pair (first cs) line)) (self (rest cs) () 0)))
          (#t (self (rest cs) (pair (first cs) line) (+ col 1))))))
    (def go
      (fn (self i line col)
        (if (>= i end) (if (= col 0) () (out line))
          (let ((b0 (byte-at s i)))
            (def have (- end i))
            (def b1 (if (> have 1) (byte-at s (+ i 1)) 0))
            (def b2 (if (> have 2) (byte-at s (+ i 2)) 0))
            (def n (+ (bit-shl b0 16) (+ (bit-shl b1 8) b2)))
            (def r
              (push
                (list (%cu-b64-char (bit-and (bit-shr n 18) 63))
                      (%cu-b64-char (bit-and (bit-shr n 12) 63))
                      (if (> have 1) (%cu-b64-char (bit-and (bit-shr n 6) 63)) 61)
                      (if (> have 2) (%cu-b64-char (bit-and n 63)) 61))
                line col))
            (do (%cu-sweep-at i %cu-sweep-lines)
                (self (+ i 3) (first r) (rest r)))))))
    (go 0 () 0)))

; S decoded, as GNU's base64 -d reads it: newlines are passed over, the rest is
; taken four characters at a time, and the last one or two of a quantum may be
; the pad, which ends it -- decoding goes on after it.  At the end of the input
; a quantum of two or three characters stands without its pad.  What decodes
; goes to PUT a run at a time -- bytes and their count, so a NUL goes too --
; every 4,096 bytes, and at the end.
;
; Answers #t, or #f at the first thing that is not base64: a byte outside the
; alphabet, a pad early in a quantum or followed by more of it, or a quantum
; cut short by the end of the input after one character or after a pad.  The
; bytes the characters before it in that quantum spell are put first, as GNU
; puts them.  GARBAGE? passes over what is not base64 instead, which is how
; uudecode reads a body.
(def %cu-b64-decode-to
  (fn (_ s put garbage?)
    (def end (byte-len s))
    ; the bytes K characters spell, BITS their value, onto OUT
    (def spell
      (fn (_ k bits out)
        (match
          ((= k 4) (pair (bit-and bits 255)
                     (pair (bit-and (bit-shr bits 8) 255)
                       (pair (bit-shr bits 16) out))))
          ((= k 3) (pair (bit-and (bit-shr bits 2) 255)
                     (pair (bit-shr bits 10) out)))
          ((= k 2) (pair (bit-shr bits 4) out))
          (#t out))))
    (def spelt (fn (_ k) (match ((= k 4) 3) ((= k 3) 2) ((= k 2) 1) (#t 0))))
    (def flush (fn (_ out n) (put (%cu-run-bytes (reverse out) n))))
    ; OUT the bytes decoded since the last put, newest first, and N how many;
    ; K the quantum's characters so far, BITS their value, PADS its pads
    (def go
      (fn (self i out n k bits pads)
        (match
          ((>= n 4096) (do (flush out n) (self i () 0 k bits pads)))
          ((>= i end)
            (do (flush (spell k bits out) (+ n (spelt k)))
                (if (> pads 0) #f (not (= k 1)))))
          (#t
            (let ((b (byte-at s i)))
              (def v (%cu-b64-value b))
              (do (if (= (& i %cu-sweep-steps) 0) (%cu-sweep! i) ())
                (match
                  ((= b 10) (self (+ i 1) out n k bits pads))
                  ((if (= b 61) (>= k 2) #f)
                    (if (= (+ k pads 1) 4)
                      (self (+ i 1) (spell k bits out) (+ n (spelt k)) 0 0 0)
                      (self (+ i 1) out n k bits (+ pads 1))))
                  ((if (>= v 0) (= pads 0) #f)
                    (if (= k 3)
                      (self (+ i 1) (spell 4 (+ (bit-shl bits 6) v) out) (+ n 3) 0 0 0)
                      (self (+ i 1) out n (+ k 1) (+ (bit-shl bits 6) v) 0)))
                  (garbage? (self (+ i 1) out n k bits pads))
                  (#t (do (flush (spell k bits out) (+ n (spelt k))) #f)))))))))
    (go 0 () 0 0 0 0)))

; S decoded to a string, what is not base64 passed over: uudecode's -m body
(def %cu-b64-decode
  (fn (_ s)
    (let ((texts (list ())))
      (do (%cu-b64-decode-to s
            (fn (_ r) (set-first! texts (pair (first r) (first texts)))) #t)
          (string-concat (reverse (first texts)))))))

(def %cu-base64
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "base64" argv))
    (%cu-operands "base64" (Opts operands o) 0 1
      (fn (_) (%cu-base64-run o stdin-thunk)))))

; -w's column, as GNU reads it: blanks, a sign, and decimal digits, nothing
; after them.  Past the largest 64-bit integer it is 0, no wrapping, as it is
; in GNU; below zero, anything else, or no digits at all is nil.
(def %cu-b64-wrap
  (fn (_ v)
    (def end (byte-len v))
    (def skip
      (fn (self i)
        (if (if (< i end) (if (= (byte-at v i) 32) #t (= (byte-at v i) 9)) #f)
          (self (+ i 1)) i)))
    (def i0 (skip 0))
    (def minus? (if (< i0 end) (= (byte-at v i0) 45) #f))
    (def i1 (if (if (< i0 end) (if minus? #t (= (byte-at v i0) 43)) #f) (+ i0 1) i0))
    ; the digits' value, -1 once it passes the largest 64-bit integer -- the
    ; arithmetic would wrap past it -- or nil at anything but a digit
    (def digits
      (fn (self i acc)
        (match
          ((>= i end) acc)
          ((if (>= (byte-at v i) 48) (<= (byte-at v i) 57) #f)
            (self (+ i 1)
              (let ((d (- (byte-at v i) 48)))
                (match
                  ((< acc 0) acc)
                  ((> acc 922337203685477580) (- 0 1))
                  ((if (= acc 922337203685477580) (> d 7) #f) (- 0 1))
                  (#t (+ (* acc 10) d))))))
          (#t ()))))
    (if (>= i1 end) ()
      (let ((n (digits i1 0)))
        (match
          ((null? n) ())
          ((< n 0) (if minus? () 0))
          ((if minus? (> n 0) #f) ())
          (#t n))))))

(def %cu-base64-run
  (fn (_ o stdin-thunk)
    (def d? (Opts on? o "-d"))
    (def wv (Opts value o "-w"))
    ; -w sets the wrap column, 0 one unbroken line; it is read before the input
    (def wrap (if (null? wv) 76 (%cu-b64-wrap wv)))
    (if (null? wrap)
      (do (file-write 2 (string-concat (list "base64: invalid wrap size: '" wv "'\n")))
          1)
      (let ((g (%cu-gather-said (Opts operands o) stdin-thunk
                 (%cu-read-error "base64") #f)))
        (match
          ; an input that could not be read has nothing to encode, and says so
          ((> (rest g) 0) 1)
          (d? (if (%cu-b64-decode-to (first g) (fn (_ r) (file-write-run 1 r)) #f) 0
                (do (file-write 2 "base64: invalid input\n") 1)))
          (#t (do (%cu-b64-put (first g) wrap) 0)))))))
