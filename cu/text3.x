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
; counter.  Each write leaves objects behind, so the line goes out as
; many copies of it at a time as fill up to 8,192 bytes, as GNU's yes
; fills a buffer, and the loop sweeps every 512 writes, since there is
; no end to them.
(module cu/text3)

(import cu/cli cu-operands cu-opts)
(import cu/prims byte-at byte-len cu% cu& cu+ cu- cu-b->s cu-int->str cu-lines
  cu-nth cu-nthrest cu-run-bytes cu-sweep! cu-sweep-at cu-sweep-bytes
  cu-sweep-lines cu-sweep-steps cu-take cu-words-line cu< cu<< cu>>
  date-now-unix file-close file-err-op file-err-text file-open-or-err
  file-open-write file-write file-write-run integer->char length list->string
  reverse rng-int rng-make set-first! string-append substring vec-build
  vec-ref vec-set!)
(import cu/text cu-delim-fields-said cu-enough cu-file-pieces
  cu-fold-lines-said cu-fold-pieces cu-fold-said cu-fold-stdin cu-gather-said
  cu-map-swept cu-newlines-from cu-num-prefix cu-print-fields
  cu-print-fields-to cu-print-lines cu-print-lines-to cu-read-error
  cu-run-join cu-run-part cu-say cu-says)

(import x/codec/base64)
(import x/core/doors str-byte-sub)

(def cu-yes
  (fn (_ argv stdin-thunk)
    (def buf
      (%cu-yes-copies
        (string-append
          (if (null? argv) "y" (Str8 join " " argv))
          "\n")))
    (def go
      (fn (self i)
        (if (< (file-write 1 buf) 0) 0
          (do (cu-sweep-at i cu-sweep-steps) (self (+ i 1))))))
    (go 1)))

; LINE doubled until another doubling would pass 8,192 bytes: a dozen appends
; where a copy at a time would cost hundreds of objects a copy
(def %cu-yes-copies
  (fn (_ line)
    (def go
      (fn (self s) (if (> (* 2 (byte-len s)) 8192) s (self (string-append s s)))))
    (go line)))

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

; S as factor reads a number: blanks and a + may lead the digits, and there
; must be one digit and nothing else -- or nil
(def %cu-factor-number
  (fn (_ s)
    (def end (byte-len s))
    (def lead
      (fn (self i)
        (if (if (< i end) (if (= (byte-at s i) 32) #t (= (byte-at s i) 9)) #f)
          (self (+ i 1)) i)))
    (def i0 (lead 0))
    (def i1 (if (if (< i0 end) (= (byte-at s i0) 43) #f) (+ i0 1) i0))
    (def digits?
      (fn (self i)
        (if (>= i end) #t
          (if (if (>= (byte-at s i) 48) (<= (byte-at s i) 57) #f)
            (self (+ i 1)) #f))))
    (if (if (< i1 end) (digits? i1) #f)
      (cu-num-prefix (substring s i1 end))
      ())))

; the factors PS as factor puts them: each on its own, or under -h a factor
; repeated once, with its exponent, 2^2 for 2 2
(def %cu-factor-spelt
  (fn (self ps h?)
    (if (null? ps) ""
      (let ((k (if h? (%cu-factor-run ps (first ps) 0) 1)))
        (string-append " "
          (string-append (cu-int->str (first ps))
            (string-append (if (> k 1) (string-append "^" (cu-int->str k)) "")
              (self (cu-nthrest k ps) h?))))))))

; how many of PS, from the start, are P
(def %cu-factor-run
  (fn (self ps p k)
    (if (if (null? ps) #t (not (= (first ps) p))) k
      (self (rest ps) p (+ k 1)))))

; S factored, a line out -- or #f once factor has said S is not a number
(def %cu-factor-line
  (fn (_ s h?)
    (def n (%cu-factor-number s))
    (if (null? n)
      (do (file-write 2
            (%str-concat
              (list "factor: '" s "' is not a valid positive integer\n")))
          #f)
      (do (display
            (string-append (cu-int->str n)
              (string-append ":"
                (string-append (%cu-factor-spelt (%cu-factor-of n) h?) "\n"))))
          #t))))

; factor [-h] [NUMBER...]: the operands, or else the words of standard input,
; each with its prime factors; one that is not a number is said, the rest are
; still factored, and the status is 1
(def cu-factor
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "factor" argv))
    (def h? (Opts on? o "-h"))
    (def each
      (fn (self ws st)
        (if (null? ws) st
          (self (rest ws) (if (%cu-factor-line (first ws) h?) st 1)))))
    (if (null? (Opts operands o))
      (each (cu-words-line (Str8 join " " (cu-lines (stdin-thunk)))) 0)
      (each (Opts operands o) 0))))

; --- expand / unexpand --------------------------------------------------------

; expand and unexpand read -t off the declaration now.

(def cu-spaces
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
        (if (>= i end) (%str-concat (reverse acc))
          (let ((b (byte-at s i)))
            (match
              ((if (= b 9) (if init? lead? #t) #f)
                (let ((gap (- w (% col w))))
                  (self (+ i 1) (+ col gap) lead? (pair (cu-spaces gap) acc))))
              ((= b 32) (self (+ i 1) (+ col 1) lead? (pair " " acc)))
              (#t (self (+ i 1) (+ col 1) #f (pair (cu-b->s b) acc))))))))
    (go 0 0 #t ())))

(def cu-expand
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "expand" argv))
    (def w (cu-num-prefix (Opts value o "-t" "8")))
    (def init? (Opts on? o "-i"))
    ; each block of whole lines expanded and put out as it is read
    (rest
      (cu-fold-lines-said (Opts operands o) stdin-thunk (cu-says "expand")
        (fn (_ block s)
          (do (cu-print-lines
                (cu-map-swept (fn (_ l) (%cu-expand-line l w init?))
                  (cu-lines block)))
              s))
        ()))))

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
      ((= stops 0) (cu-spaces (- to from)))
      (#t (string-append (%cu-tabs stops) (cu-spaces (% to w)))))))

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
        (if (>= i end) (%str-concat (reverse acc))
          (let ((b (byte-at s i)))
            (match
              ((not (if (= b 32) #t (= b 9)))
                (self (+ i 1) (+ col 1) #f (pair (cu-b->s b) acc)))
              ((if all? #t lead?)
                (let ((r (run-end i col 0)))
                  (def to (first (rest r)))
                  (def n (first (rest (rest r))))
                  (self (first r) to #f
                    (pair (%cu-unexpand-run col to w (if (= n 1) (= b 32) #f))
                          acc))))
              (#t (%str-concat (reverse (pair (substring s i end) acc)))))))))
    (go 0 0 #t ())))

; Which runs are respelled: the leading one, unless -a -- or -t, which says it
; too -- asks for every one; and -f, first only, keeps it to the leading run
; whatever else was given, and in whichever order.
(def cu-unexpand
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "unexpand" argv))
    (def w (cu-num-prefix (Opts value o "-t" "8")))
    (def all? (match
                ((Opts on? o "-f") #f)
                ((Opts on? o "-a") #t)
                (#t (not (null? (Opts value o "-t"))))))
    ; each block of whole lines respelled and put out as it is read
    (rest
      (cu-fold-lines-said (Opts operands o) stdin-thunk (cu-says "unexpand")
        (fn (_ block s)
          (do (cu-print-lines
                (cu-map-swept (fn (_ l) (%cu-unexpand-line l w all?))
                  (cu-lines block)))
              s))
        ()))))

; --- dos2unix / unix2dos ------------------------------------------------------

; Run R with its carriage returns taken out and, under DOS?, one put before each
; newline: each byte on its own, so an input converted a piece at a time comes
; out the same.  The bytes are gathered as bytes and handed to PUT as a run of
; 4,096 at a time, so the list the walk holds never grows long and a NUL goes
; through with the rest, and the walk sweeps as it goes.
(def %cu-crlf-walk
  (fn (_ r dos? put)
    (def s (first r))
    (def end (rest r))
    ; RUN the bytes since the last put, newest first, and N how many
    (def go
      (fn (self i run n)
        (match
          ((cu< 4095 n) (do (put (cu-run-bytes (reverse run) n)) (self i () 0)))
          ((cu< i end)
            (do (def b (byte-at s i))
                (if (= (cu& i cu-sweep-bytes) 0) (cu-sweep! i) ())
                (match
                  ((= b 13) (self (cu+ i 1) run n))
                  ((if dos? (= b 10) #f)
                    (self (cu+ i 1) (pair 10 (pair 13 run)) (cu+ n 2)))
                  (#t (self (cu+ i 1) (pair b run) (cu+ n 1))))))
          ((cu< 0 n) (put (cu-run-bytes (reverse run) n)))
          (#t ()))))
    (go 0 () 0)))

; NAME's bytes as its pieces, a list of runs, or the io Err it would not open
; or read with, said by SAYS
(def %cu-runs-said
  (fn (_ says name)
    (let ((src (cu-file-pieces name)))
      (if (Err err? src) (do (cu-say says name src) src)
        (let ((g (cu-fold-pieces src (fn (_ p acc) (pair p acc)) ())))
          (do (src (lit close))
              (if (null? (rest g)) (reverse (first g))
                (do (cu-say says name (rest g)) (rest g)))))))))

; RUNS converted back into the file PATH, or the io Err it would not open with
(def %cu-crlf-back
  (fn (_ path runs dos?)
    (def fd (file-open-or-err file-open-write path))
    (def go
      (fn (self rs)
        (if (null? rs) (file-close fd)
          (do (%cu-crlf-walk (first rs) dos? (fn (_ c) (file-write-run fd c)))
              (self (rest rs))))))
    (if (Err err? fd) fd (go runs))))

; both rewrite a named file IN PLACE (as busybox does) and filter
; stdin to stdout when given no operand
; -u converts to unix endings and -d to dos, whichever applet was named:
; the two are one tool with a default, and the flags say which direction
; is wanted outright.
(def %cu-crlf-applet
  (fn (_ name to-dos-by-default? argv stdin-thunk)
    (def o (cu-opts name argv))
    (def ops (Opts operands o))
    (def to-dos?
      (match
        ((Opts on? o "-d") #t)
        ((Opts on? o "-u") #f)
        (#t to-dos-by-default?)))
    (if (null? ops)
      (do (cu-fold-stdin stdin-thunk
            (fn (_ p s)
              (do (%cu-crlf-walk p to-dos? (fn (_ c) (file-write-run 1 c))) s))
            ())
          0)
      ; a file that cannot be read, or written back, is said, and the rest are
      ; still converted
      (let ((go (fn (self os st)
                  (if (null? os) st
                    (let ((runs (%cu-runs-said (cu-says name) (first os))))
                      (if (Err err? runs) (self (rest os) 1)
                        (let ((w (%cu-crlf-back (first os) runs to-dos?)))
                          (if (Err err? w)
                            (do (file-write 2
                                  (string-append
                                    ((cu-says name) (first os) w) "\n"))
                                (self (rest os) 1))
                            (self (rest os) st)))))))))
        (go ops 0)))))

(def cu-dos2unix
  (fn (_ argv stdin-thunk)
    (%cu-crlf-applet "dos2unix" #f argv stdin-thunk)))

(def cu-unix2dos
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

; whether file N is past the last suffix WIDTH letters spell, 26 to the
; WIDTH of them; past 12 letters that is more than a 64-bit count reaches
(def %cu-split-past?
  (fn (_ n width)
    (def room (fn (self w) (if (<= w 0) 1 (* 26 (self (- w 1))))))
    (if (> width 12) #f (>= n (room width)))))

; file N's descriptor, made new -- or nil once split has said why it was
; not: past the last suffix, or refused
(def %cu-split-open
  (fn (_ prefix n width)
    (if (%cu-split-past? n width)
      (do (file-write 2 "split: output file suffixes exhausted\n") ())
      (let ((path (string-append prefix (%cu-split-suffix n width))))
        (let ((fd (file-open-or-err file-open-write path)))
          (if (Err err? fd)
            (do (file-write 2
                  (%str-concat
                    (list "split: " path ": " (file-err-text fd) "\n")))
                ())
            fd))))))

; split's TAKE: the state is (N FD USED BAD) -- the number of the next file,
; the file open and what it holds so far, bytes or lines, and 1 once a file
; would not be made.  A piece goes out in parts, each to the file open while
; there is room in it and to the next one made when there is not, so a file is
; made only when there is something to go in it.  A part that starts past its
; piece's start is copied into a run of its own.
(def %cu-split-take
  (fn (_ prefix width size lines?)
    (fn (_ r s)
      (def go
        (fn (self i n fd used)
          (match
            ((>= i (rest r)) (list n fd used 0))
            ((if (null? fd) #t (>= used size))
              (let ((next (%cu-split-open prefix n width)))
                (if (null? next) (cu-enough (list n fd used 1))
                  (do (if (null? fd) () (file-close fd))
                      (self i (+ n 1) next 0)))))
            (#t
              (let ((cut (if lines? (cu-newlines-from r i (- size used))
                           (let ((k (- size used)) (left (- (rest r) i)))
                             (pair (+ i (if (< k left) k left)) 0)))))
                (do (file-write-run fd
                      (if (= i 0) (pair (first r) (first cut))
                        (cu-run-part r i (first cut))))
                    (self (first cut) n fd
                      (+ used (if lines? (rest cut) (- (first cut) i))))))))))
      (go 0 (first s) (cu-nth 1 s) (cu-nth 2 s)))))

; split [FILE [PREFIX]]: a third operand is refused
(def cu-split
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "split" argv))
    (cu-operands "split" (Opts operands o) 0 2
      (fn (_) (%cu-split-run o stdin-thunk)))))

(def %cu-split-run
  (fn (_ o stdin-thunk)
    (def bv (Opts value o "-b"))
    (def lv (Opts value o "-l"))
    (def width
      (let ((v (Opts value o "-a"))) (if (null? v) 2 (cu-num-prefix v))))
    (def by-bytes? (not (null? bv)))
    (def size
      (let ((v (if (null? bv) lv bv)))
        (if (null? v) 1000 (cu-num-prefix v))))
    (def ops (Opts operands o))
    (def prefix (if (if (pair? ops) (pair? (rest ops)) #f) (first (rest ops)) "x"))
    ; the input is read a piece at a time and put out as it is read
    (if (<= size 0)
      (do (file-write 2
            (%str-concat
              (list "split: invalid number of " (if by-bytes? "bytes" "lines")
                    ": '" (if by-bytes? bv lv) "'\n")))
          1)
      (let ((g (cu-fold-said (if (null? ops) () (list (first ops))) stdin-thunk
                 %cu-split-says
                 (%cu-split-take prefix width size (not by-bytes?))
                 (list 0 () 0 0))))
        (let ((s (first g)))
          (do (if (null? (cu-nth 1 s)) () (file-close (cu-nth 1 s)))
              (if (if (> (rest g) 0) #t (= (cu-nth 3 s) 1)) 1 0)))))))

; a file split cannot read, said as split says it: "cannot open 'F' for
; reading" for one that would not open, "F: REASON" for one that would not read
(def %cu-split-says
  (fn (_ name err)
    (if (eq? (file-err-op err) (lit read))
      (%str-concat (list "split: " name ": " (file-err-text err)))
      (%str-concat
        (list "split: cannot open '" name "' for reading: " (file-err-text err))))))

; --- shuf ---------------------------------------------------------------------

; Fisher-Yates over a vector, seeded from the clock; -n truncates the
; result, -e takes the operands themselves as the lines

; the N items of L as a vector.  Vector build asks for each slot in turn, and
; the filler walks L, sweeping as it goes; a vector made first and set after
; would pay for filling every slot twice, the first time in a loop of the
; platform's that no sweep reaches.
(def cu-list->vec
  (fn (_ l n)
    (let ((cur (list l)))
      (vec-build n
        (fn (_ i)
          (let ((xs (first cur)))
            (do (cu-sweep-at i cu-sweep-steps)
                (set-first! cur (rest xs))
                (first xs))))))))

(def cu-vec->list
  (fn (_ v n)
    (def go
      (fn (self i acc)
        (if (< i 0) acc
          (do (cu-sweep-at i cu-sweep-steps)
              (self (- i 1) (pair (vec-ref v i) acc))))))
    (go (- n 1) ())))

(def %cu-shuffle
  (fn (_ items)
    (def n (length items))
    (def v (cu-list->vec items n))
    (def r (rng-make (date-now-unix)))
    (def go
      (fn (self i)
        (if (<= i 0) (cu-vec->list v n)
          (let ((j (do (cu-sweep-at i cu-sweep-lines) (rng-int r (+ i 1)))))
            (let ((tmp (vec-ref v i)))
              (do (vec-set! v i (vec-ref v j))
                  (vec-set! v j tmp)
                  (self (- i 1))))))))
    (go (- n 1))))

; With -e the operands are what is shuffled, as many as are given; -i shuffles
; a range and takes none; otherwise there is one FILE at most.
(def cu-shuf
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "shuf" argv))
    (cu-operands "shuf" (Opts operands o) 0
      (match
        ((Opts on? o "-e") ())
        ((not (null? (Opts value o "-i"))) 0)
        (#t 1))
      (fn (_) (%cu-shuf-run o stdin-thunk)))))

(def %cu-shuf-run
  (fn (_ o stdin-thunk)
    (def nv (Opts value o "-n"))
    (def count (if (null? nv) 0 (cu-num-prefix nv)))
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
        ((not (null? iv)) (pair (cu-shuf-range iv) 0))
        (echo? (pair rest1 0))
        (z? (cu-delim-fields-said rest1 stdin-thunk 0 (cu-read-error "shuf")
               #f))
        (#t (let ((g (cu-gather-said rest1 stdin-thunk (cu-read-error "shuf")
                       #f)))
              (pair (cu-lines (first g)) (rest g))))))
    (def items (first read))
    (def out (%cu-shuffle items))
    (def picked (if (null? nv) out (cu-take out count)))
    ; -o writes where the shuffle goes, so a caller can shuffle a file in
    ; place without a shell redirect reading it at the same time.
    (def dest (Opts value o "-o"))
    (match
      ((> (rest read) 0) 1)
      ((if (null? dest) z? #f) (do (cu-print-fields picked 0) 0))
      ((null? dest) (do (cu-print-lines picked) 0))
      (z?
        (let ((fd (file-open-or-err file-open-write dest)))
          (if (Err err? fd) (%cu-shuf-cannot dest fd)
            (do (cu-print-fields-to fd picked 0) (file-close fd) 0))))
      ; each line put out as it is walked, which sweeps as it goes
      (#t
        (let ((fd (file-open-or-err file-open-write dest)))
          (if (Err err? fd) (%cu-shuf-cannot dest fd)
            (do (cu-print-lines-to fd picked) (file-close fd) 0)))))))

; an -o file shuf cannot write, said as shuf says it
(def %cu-shuf-cannot
  (fn (_ dest r)
    (do (file-write 2
          (%str-concat (list "shuf: " dest ": " (file-err-text r) "\n")))
        1)))

; "LO-HI" -> the integers from LO to HI, as strings.
(def cu-shuf-range
  (fn (_ spec)
    (def dash
      (let ((go (fn (self i)
                  (if (>= i (byte-len spec)) (- 0 1)
                    (if (= (byte-at spec i) 45) i (self (+ i 1)))))))
        (go 0)))
    (if (< dash 0) ()
      (let ((lo (cu-num-prefix (substring spec 0 dash)))
            (hi (cu-num-prefix (substring spec (+ dash 1) (byte-len spec)))))
        ; K counts the numbers made, for the sweeps
        (let ((go (fn (self n k acc)
                    (if (< n lo) acc
                      (do (cu-sweep-at k cu-sweep-steps)
                          (self (- n 1) (+ k 1) (pair (cu-int->str n) acc)))))))
          (go hi 0 ()))))))

; --- base64 -------------------------------------------------------------------
;
; Encoding is x/codec/base64's encode-region: whole groups of three bytes as
; each piece comes, by count, so a NUL is a byte, and the rest padded out at
; the end.  Decoding is busybox's own reading, ported from its libbb
; decode_base64 and read_base64, because the codec's decoder is strict by
; x-lang's ruling #61 and busybox's is not: a character outside the alphabet
; is passed over, a = counts only third or fourth in a group (and third only
; before another =), the bytes go on decoding after a pad, and the one
; refusal is a group cut short at the end, "truncated input".

; --- encoding

; The encoding of run R's whole groups, and under LAST? of the one or two
; bytes after them too, put out on lines of WRAP characters carried on from
; column COL; WRAP 0 is one line and no newline.  Answers (NEXT . COL), NEXT
; where the bytes encoded stop.
(def cu-b64-put-from
  (fn (_ r wrap col last?)
    (def n (rest r))
    (def whole (if last? n (cu- n (cu% n 3))))
    (pair whole
          (%cu-b64-put-text (Base64 encode-region (list (first r) 0 whole))
            wrap col))))

; the encoded text E, a region from 0, out on lines of WRAP from column COL:
; the new column.  The text is all of the alphabet and =, so it goes out as
; strings, the lines of one piece in one write.
(def %cu-b64-put-text
  (fn (_ e wrap col)
    (def s (first e))
    (def m (cu-nth 2 e))
    (if (= wrap 0)
      (do (if (> m 0) (file-write 1 (str-byte-sub s 0 m)) ()) 0)
      (let go ((at 0) (c col) (acc ()))
        (if (cu< at m)
          (let ((k (if (cu< (cu- m at) (cu- wrap c)) (cu- m at) (cu- wrap c))))
            (if (cu< (cu+ c k) wrap)
              (go (cu+ at k) (cu+ c k) (pair (str-byte-sub s at k) acc))
              (go (cu+ at k) 0 (pair "\n" (pair (str-byte-sub s at k) acc)))))
          (do (if (null? acc) () (file-write 1 (%str-concat (reverse acc)))) c))))))

; the newline that ends the last line, when it holds any and lines wrap
(def cu-b64-put-end
  (fn (_ wrap col)
    (if (if (> col 0) (> wrap 0) #f) (file-write 1 "\n") ())))

; base64's TAKE: the state is (LEFT . COL), LEFT the bytes of a group the
; pieces before could not finish, fewer than three, as a run
(def %cu-b64-take
  (fn (_ wrap)
    (fn (_ piece s)
      (let ((text (if (= (rest (first s)) 0) piece
                    (cu-run-join (first s) piece 0 (rest piece)))))
        (let ((r (cu-b64-put-from text wrap (rest s) #f)))
          (pair (cu-run-part text (first r) (rest text)) (rest r)))))))

; --- decoding

; byte T's six bits, or nil for anything outside the alphabet, the = among
; them
(def %cu-b64-value
  (fn (_ t)
    (match
      ((if (>= t 65) (<= t 90) #f) (- t 65))
      ((if (>= t 97) (<= t 122) #f) (- t 71))
      ((if (>= t 48) (<= t 57) #f) (+ t 4))
      ((= t 43) 62)
      ((= t 47) 63)
      (#t ()))))

; decode_base64 over CHARS, LEN bytes: their bytes onto OUT, newest first,
; and N, how many it holds -- (OUT N TAIL).  A group's characters build CH
; six bits at a time, a = as a mark above its 24 bits.  The fourth puts the
; group's three bytes out, less one for each = among them, and a = ends the
; decoding: TAIL is the characters after it.  Run to the end, TAIL is the
; last I characters, the group not finished -- the raw characters, whatever
; was passed over among them, as busybox backs its pointer up by I.
(def cu-b64-decode-chars
  (fn (_ chars len out n)
    (def go
      (fn (self l i ch out n)
        (if (null? l) (list out n (cu-nthrest (- len i) chars))
          (do (def t (first l))
              (def v (%cu-b64-value t))
              (def pad? (if (= t 61)
                          (if (= i 3) #t
                            (if (= i 2) (if (null? (rest l)) #f (= (first (rest l)) 61)) #f))
                          #f))
              (match
                ((if (null? v) (not pad?) #f) (self (rest l) i ch out n))
                ((< i 3) (self (rest l) (+ i 1) (cu+ (cu<< ch 6) (if pad? 16777216 v)) out n))
                (#t
                  (do (def c (cu+ (cu<< ch 6) (if pad? 16777216 v)))
                      (def k (- 3 (+ (if (= (cu& c 16777216) 0) 0 1)
                                     (if (= (cu& c 1073741824) 0) 0 1))))
                      (def o1 (pair (cu& (cu>> c 16) 255) out))
                      (def o2 (if (> k 1) (pair (cu& (cu>> c 8) 255) o1) o1))
                      (def o3 (if (> k 2) (pair (cu& c 255) o2) o2))
                      (if (< k 3) (list o3 (+ n k) (rest l))
                        (self (rest l) 0 0 o3 (+ n 3))))))))))
    (go chars 0 0 out n)))

; S decoded by decode_base64 alone, as httpd decodes a password: the bytes,
; as a run
(def cu-b64-decode-string
  (fn (_ s)
    (def chars (let go ((i (- (byte-len s) 1)) (acc ()))
                 (if (< i 0) acc (go (- i 1) (pair (cu& (byte-at s i) 255) acc)))))
    (def d (cu-b64-decode-chars chars (byte-len s) () 0))
    (cu-run-bytes (reverse (first d)) (cu-nth 1 d))))

; read_base64, a byte at a time.  The state is (CHUNK K OUT N): the chunk
; read so far, newest first, and K its length; OUT the bytes decoded and not
; yet put, newest first, and N how many.  A chunk ends at a control byte or
; a space, which is passed over, or at 80 bytes, and is decoded then: what
; its last group left begins the next.  The bytes go to PUT a run at a time,
; once there are 4,096.  Under UU? a chunk of just ==== is uuencode's end:
; the reading stops there, and cu-b64-feed answers (lit stop).
(def cu-b64-fresh (list () 0 () 0))

(def cu-b64-feed
  (fn (_ st b put uu?)
    (match
      ((cu< 32 b)
        (if (= (cu+ (cu-nth 1 st) 1) 80)
          (%cu-b64-chunk (pair b (first st)) 80 st put uu?)
          (list (pair b (first st)) (cu+ (cu-nth 1 st) 1) (cu-nth 2 st) (cu-nth 3 st))))
      (#t (%cu-b64-chunk (first st) (cu-nth 1 st) st put uu?)))))

; the chunk CHUNK, K bytes newest first, decoded from ST: the next state, or
; (lit stop)
(def %cu-b64-chunk
  (fn (_ chunk k st put uu?)
    (def chars (reverse chunk))
    (if (if uu? (%cu-b64-uu-end? chars) #f) (do (%cu-b64-put put (cu-nth 2 st) (cu-nth 3 st)) (lit stop))
      (let ((d (cu-b64-decode-chars chars k (cu-nth 2 st) (cu-nth 3 st))))
        (let ((tail (cu-nth 2 d)))
          (if (cu< 4095 (cu-nth 1 d))
            (do (%cu-b64-put put (first d) (cu-nth 1 d))
                (list (reverse tail) (length tail) () 0))
            (list (reverse tail) (length tail) (first d) (cu-nth 1 d))))))))

; whether CHARS are ====, uuencode -m's last line
(def %cu-b64-uu-end?
  (fn (_ chars)
    (if (= (length chars) 4)
      (let go ((l chars)) (if (null? l) #t (if (= (first l) 61) (go (rest l)) #f)))
      #f)))

; the end of the input: the last chunk decoded and everything put.  #t, or
; #f where a group was left unfinished -- "truncated input".  An empty chunk
; ends it as it stands.
(def cu-b64-finish
  (fn (_ st put uu?)
    (if (= (cu-nth 1 st) 0) (do (%cu-b64-put put (cu-nth 2 st) (cu-nth 3 st)) #t)
      (let ((after (%cu-b64-chunk (first st) (cu-nth 1 st) st put uu?)))
        (if (eq? after (lit stop)) #t
          (do (%cu-b64-put put (cu-nth 2 after) (cu-nth 3 after))
              (= (cu-nth 1 after) 0)))))))

; OUT's N bytes, newest first, to PUT as a run
(def %cu-b64-put
  (fn (_ put out n)
    (if (> n 0) (put (cu-run-bytes (reverse out) n)) ())))

; run R's bytes fed in turn from ST: the state after them, sweeping as it
; goes
(def %cu-b64-feed-run
  (fn (_ r st put)
    (def s (first r))
    (def end (rest r))
    (def go
      (fn (self i st)
        (if (cu< i end)
          (do (if (= (cu& i cu-sweep-steps) 0) (cu-sweep! i) ())
              (self (cu+ i 1) (cu-b64-feed st (cu& (byte-at s i) 255) put #f)))
          st)))
    (go 0 st)))

(def cu-base64
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "base64" argv))
    (cu-operands "base64" (Opts operands o) 0 1
      (fn (_) (%cu-base64-run o stdin-thunk)))))

; -w's column, as busybox's xatoi_positive reads it: decimal digits and
; nothing else, a leading 0 among them.  Answers the column, or the words
; of the refusal: "invalid number 'V'" for anything else or past
; 4294967295, and "number N is not in 0..2147483647 range" between.
(def %cu-b64-wrap
  (fn (_ v)
    (def end (byte-len v))
    ; the digits' value, or -1 once it passes 4294967295
    (def digits
      (fn (self i acc)
        (match
          ((>= i end) acc)
          ((if (>= (byte-at v i) 48) (<= (byte-at v i) 57) #f)
            (self (+ i 1)
              (if (< acc 0) acc
                (let ((n (+ (* acc 10) (- (byte-at v i) 48))))
                  (if (> n 4294967295) (- 0 1) n)))))
          (#t ()))))
    (def n (if (= end 0) () (digits 0 0)))
    (match
      ((null? n) (%str-concat (list "invalid number '" v "'")))
      ((< n 0) (%str-concat (list "invalid number '" v "'")))
      ((> n 2147483647)
        (%str-concat (list "number " (cu-int->str n) " is not in 0..2147483647 range")))
      (#t n))))

(def %cu-base64-run
  (fn (_ o stdin-thunk)
    (def d? (Opts on? o "-d"))
    (def wv (Opts value o "-w"))
    ; -w sets the wrap column, 0 one unbroken line; it is read before the input
    (def wrap (if (null? wv) 76 (%cu-b64-wrap wv)))
    (if (str? wrap)
      (do (file-write 2 (%str-concat (list "base64: " wrap "\n"))) 1)
      ; the input is encoded or decoded as it is read.  One that could not be
      ; read is said and fails, and nothing more is put out.
      (let ((ops (Opts operands o))
            (says (cu-read-error "base64"))
            (put (fn (_ r) (file-write-run 1 r))))
        (if d?
          (let ((g (cu-fold-said ops stdin-thunk says
                     (fn (_ p st) (%cu-b64-feed-run p st put)) cu-b64-fresh)))
            (match
              ((> (rest g) 0) 1)
              ((cu-b64-finish (first g) put #f) 0)
              (#t (do (file-write 2 "base64: truncated input\n") 1))))
          (let ((g (cu-fold-said ops stdin-thunk says (%cu-b64-take wrap)
                     (pair (pair "" 0) 0))))
            (if (> (rest g) 0) 1
              (let ((s (first g)))
                (do (cu-b64-put-end wrap
                      (rest (cu-b64-put-from (first s) wrap (rest s) #t)))
                    0)))))))))

(provide cu/text3 cu-b64-decode-chars cu-b64-decode-string cu-b64-feed
  cu-b64-finish cu-b64-fresh cu-b64-put-end cu-b64-put-from cu-base64
  cu-dos2unix cu-expand cu-factor cu-list->vec cu-shuf cu-shuf-range cu-spaces
  cu-split cu-unexpand cu-unix2dos cu-vec->list cu-yes)
