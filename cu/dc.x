; # x-coreutils -- the small tools, as applets
;
; ## cu/dc.x -- dc
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's dc, the one built on bc's numbers (miscutils/bc.c, FEATURE_DC_BIG):
; a stack calculator of arbitrary precision.  A number is an exact integer and
; a scale, the digits after its point, and every operation follows bc's rules
; for the scale of its answer and truncates, never rounds.  Registers hold
; stacks of numbers and strings, arrays hold numbers by index, and a string is
; a macro x runs.
;
; As busybox does: the token after the one being run is read before it runs,
; so a bad character stops the command before it; a macro is read whole
; before it runs; a number is read in the input base current when it is
; first used; an array element pushed by ; stays a reference to its place;
; n prints as p does, with a newline and without popping, and P does not pop.
; An error is said, under the file's name and line where a file is read, and
; ends dc with status 1.

(module cu/dc)

(import cu/cli cu-opts)
(import cu/dump dp-find)
(import cu/prims byte-at byte-len cu-err-label cu-int->str cu-nthrest
  cu-ptr-set! cu-str->ptr cu-sweep-lines cu-sweep-tick! file-err-text
  file-write file-write-run filter length map reverse str-make-raw
  string-append string-concat string=? substring sys-getenv vec-build vec-make
  vec-ref vec-set!)
(import cu/sysinfo si-digits?)
(import cu/text cu-num-prefix cu-pad-zero cu-pieces cu-run-text)

(def %dc-big+ (fn (_ a b) (Bigint + a b)))
(def %dc-big- (fn (_ a b) (Bigint - a b)))
(def %dc-big* (fn (_ a b) (Bigint * a b)))
(def %dc-big/ (fn (_ a b) (Bigint / a b)))
(def %dc-big% (fn (_ a b) (Bigint % a b)))
(def %dc-big< (fn (_ a b) (Bigint < a b)))
(def %dc-big= (fn (_ a b) (Bigint = a b)))

(def %dc-die (fn (_ msg) (Err raise (lit dc) msg ())))

; --- numbers ---------------------------------------------------------------------
;
; A number is (M . S): the value M / 10^S, S its scale.  Zero is never negative.

(def %dcn-tens (vec-make 64 ()))

; 10^N
(def %dcn-ten
  (fn (_ n)
    (if (< n 64)
      (let ((c (vec-ref %dcn-tens n)))
        (if (null? c) (let ((v (%dcn-ten-go n))) (do (vec-set! %dcn-tens n v) v)) c))
      (%dcn-ten-go n))))

(def %dcn-ten-go
  (fn (_ n) (let go ((k n) (acc 1)) (if (= k 0) acc (go (- k 1) (%dc-big* acc 10))))))

(def %dcn-m (fn (_ x) (first x)))
(def %dcn-s (fn (_ x) (rest x)))
(def %dcn-zero? (fn (_ x) (%dc-big= (first x) 0)))
(def %dcn-neg? (fn (_ x) (%dc-big< (first x) 0)))
(def %dcn-abs (fn (_ m) (if (%dc-big< m 0) (%dc-big- 0 m) m)))

; X's integer at scale S, S at least its own
(def %dcn-at (fn (_ x s) (%dc-big* (first x) (%dcn-ten (- s (rest x))))))

; X cut to scale S, its digits past S dropped
(def %dcn-cut
  (fn (_ x s)
    (if (>= s (rest x)) (pair (%dcn-at x s) s)
      (pair (%dc-big/ (first x) (%dcn-ten (- (rest x) s))) s))))

(def %dcn-max (fn (_ a b) (if (> a b) a b)))
(def %dcn-min (fn (_ a b) (if (< a b) a b)))

(def %dcn-add
  (fn (_ a b)
    (let ((s (%dcn-max (rest a) (rest b))))
      (pair (%dc-big+ (%dcn-at a s) (%dcn-at b s)) s))))

(def %dcn-sub
  (fn (_ a b)
    (let ((s (%dcn-max (rest a) (rest b))))
      (pair (%dc-big- (%dcn-at a s) (%dcn-at b s)) s))))

; -1, 0 or 1 as A is below, at or above B
(def %dcn-cmp
  (fn (_ a b)
    (let ((s (%dcn-max (rest a) (rest b))))
      (let ((x (%dcn-at a s)) (y (%dcn-at b s)))
        (match ((%dc-big< x y) -1) ((%dc-big< y x) 1) (#t 0))))))

; bc's multiply: the product cut to the lesser of the operands' scales summed
; and the greatest of SCALE and theirs
(def %dcn-mul
  (fn (_ a b scale)
    (let ((full (+ (rest a) (rest b))))
      (%dcn-cut (pair (%dc-big* (first a) (first b)) full)
                (%dcn-min full (%dcn-max scale (%dcn-max (rest a) (rest b))))))))

; A / B at SCALE, truncated
(def %dcn-div
  (fn (_ a b scale)
    (if (%dcn-zero? b) (%dc-die "divide by zero")
      (pair (%dc-big/ (%dc-big* (first a) (%dcn-ten (+ (rest b) scale)))
                      (%dc-big* (first b) (%dcn-ten (rest a))))
            scale))))

; (QUOTIENT . REMAINDER) as bc's divmod makes them: the quotient at SCALE,
; the remainder A less it times B, at the greater of SCALE plus B's scale and
; A's
(def %dcn-divmod
  (fn (_ a b scale)
    (def ts (%dcn-max (+ scale (rest b)) (rest a)))
    (if (%dcn-zero? b) (%dc-die "divide by zero")
      (if (%dcn-zero? a) (pair (pair 0 scale) (pair 0 ts))
        (let ((q (%dcn-div a b scale)))
          (pair q (%dcn-cut (%dcn-sub a (%dcn-mul q b (+ scale (rest b)))) ts)))))))

(def %dcn-rem (fn (_ a b scale) (rest (%dcn-divmod a b scale))))

; X's integer part as a count: an error where X is negative
(def %dcn-ulong
  (fn (_ x)
    (if (%dcn-neg? x) (%dc-die "negative number")
      (%dc-big/ (first x) (%dcn-ten (rest x))))))

(def %dcn-int? (fn (_ x) (%dc-big= (%dc-big% (first x) (%dcn-ten (rest x))) 0)))

; X is exactly 1 or -1 with no digits past the point, as BC_NUM_ONE asks
(def %dcn-one? (fn (_ x) (if (= (rest x) 0) (%dc-big= (%dcn-abs (first x)) 1) #f)))

; bc's zbc_num_p: A^B, B an integer, by squaring, each multiply cut as bc's are
(def %dcn-pow
  (fn (_ a b scale)
    (match
      ((not (%dcn-int? b)) (%dc-die "not an integer"))
      ((%dcn-zero? b) (pair 1 0))
      ((%dcn-zero? a) (pair 0 scale))
      ((%dcn-one? b) (if (%dcn-neg? b) (%dcn-div (pair 1 0) a scale) a))
      (#t (%dcn-pow-go a (%dcn-neg? b) (%dc-big/ (%dcn-abs (first b)) (%dcn-ten (rest b))) scale)))))

(def %dcn-pow-go
  (fn (_ a neg pow scale0)
    (def ar (rest a))
    (def scale
      (if neg scale0
        (let ((s (%dcn-max scale0 ar)))
          (if (%dc-big< (%dc-big* ar pow) s) (%dc-big* ar pow) s))))
    ; the lowest set bit of POW, squaring as it is passed
    (def low
      (fn (self copy p prdx)
        (if (%dc-big= (%dc-big% p 2) 1) (list copy p prdx)
          (let ((r2 (* prdx 2))) (self (%dcn-mul copy copy r2) (%dc-big/ p 2) r2)))))
    (def high
      (fn (self c copy p prdx rrdx)
        (if (%dc-big= p 0) c
          (let ((r2 (* prdx 2)))
            (let ((sq (%dcn-mul copy copy r2)))
              (if (%dc-big= (%dc-big% p 2) 1)
                (let ((rr (+ rrdx r2))) (self (%dcn-mul c sq rr) sq (%dc-big/ p 2) r2 rr))
                (self c sq (%dc-big/ p 2) r2 rrdx)))))))
    (def l (low a pow ar))
    (def c (high (first l) (first l) (%dc-big/ (first (rest l)) 2) (first (rest (rest l))) (first (rest (rest l)))))
    (def c2 (if neg (%dcn-div (pair 1 0) c scale) c))
    (def c3 (if (> (rest c2) scale) (%dcn-cut c2 scale) c2))
    (if (%dcn-zero? c3) (pair 0 scale) c3)))

; the integer square root of N
(def %dcn-isqrt
  (fn (_ n)
    (if (%dc-big< n 2) n
      (let go ((x (%dcn-ten (+ (%dcn-digits n) 1))))
        (let ((y (%dc-big/ (%dc-big+ x (%dc-big/ n x)) 2)))
          (if (%dc-big< y x) (go y) x))))))

; how many decimal digits N has, 0 for 0
(def %dcn-digits
  (fn (_ n) (let go ((k 0) (v (%dcn-abs n))) (if (%dc-big= v 0) k (go (+ k 1) (%dc-big/ v 10))))))

; bc's sqrt: at the greater of SCALE and A's own, truncated
(def %dcn-sqrt
  (fn (_ a scale)
    (match
      ((%dcn-zero? a) (pair 0 scale))
      ((%dcn-neg? a) (%dc-die "negative number"))
      ((%dcn-one? a) (pair (%dcn-ten scale) scale))
      (#t (let ((s (%dcn-max scale (rest a))))
            (pair (%dcn-isqrt (%dc-big* (first a) (%dcn-ten (- (* 2 s) (rest a))))) s))))))

; dc's |: A^B mod C, all integers
(def %dcn-modexp
  (fn (_ a b c)
    (match
      ((%dcn-zero? c) (%dc-die "divide by zero"))
      ((if (> (rest a) 0) #t (if (> (rest b) 0) #t (> (rest c) 0))) (%dc-die "not an integer"))
      ((%dcn-neg? b) (%dc-die "negative number"))
      (#t (let go ((d 1) (base (%dc-big% (first a) (first c))) (e (first b)))
            (if (%dc-big= e 0) (pair d 0)
              (let ((d2 (if (%dc-big= (%dc-big% e 2) 1) (%dc-big% (%dc-big* d base) (first c)) d)))
                (go d2 (%dc-big% (%dc-big* base base) (first c)) (%dc-big/ e 2)))))))))

; the value of TEXT read in BASE, as zxc_num_parse reads it: a single digit
; is itself; in base 10 a digit past 9 is 9; in another base, a digit past
; it is the base less 1, and the digits after the point make the scale
(def %dcn-parse
  (fn (_ text base)
    (def t (%dcn-strip0 text))
    (match
      ((%dcn-all-zero? t) (pair 0 0))
      ((= (byte-len t) 1) (pair (%dcn-digit (byte-at t 0) 36) 0))
      ((= base 10) (%dcn-parse10 t))
      (#t (%dcn-parse-base t base)))))

(def %dcn-strip0
  (fn (_ s) (let go ((i 0)) (if (if (< i (byte-len s)) (= (byte-at s i) #\0) #f) (go (+ i 1)) (substring s i (byte-len s))))))

(def %dcn-all-zero?
  (fn (_ s) (let go ((i 0)) (match ((>= i (byte-len s)) #t) ((if (= (byte-at s i) #\0) #t (= (byte-at s i) #\.)) (go (+ i 1))) (#t #f)))))

; a digit's value, no more than MAX
(def %dcn-digit
  (fn (_ c max) (let ((v (if (<= c #\9) (- c #\0) (+ (- c #\A) 10)))) (if (> v max) max v))))

(def %dcn-parse10
  (fn (_ t)
    (def dot (dp-find t 0 #\.))
    (let go ((i 0) (m 0))
      (if (>= i (byte-len t)) (pair m (if (< dot 0) 0 (- (byte-len t) (+ dot 1))))
        (if (= i dot) (go (+ i 1) m)
          (go (+ i 1) (%dc-big+ (%dc-big* m 10) (%dcn-digit (byte-at t i) 9))))))))

(def %dcn-parse-base
  (fn (_ t base)
    (def dot (dp-find t 0 #\.))
    (def end (if (< dot 0) (byte-len t) dot))
    (def int (let go ((i 0) (m 0)) (if (>= i end) m (go (+ i 1) (%dc-big+ (%dc-big* m base) (%dcn-digit (byte-at t i) (- base 1)))))))
    (if (< dot 0) (pair int 0)
      (let go ((i (+ dot 1)) (r 0) (mult 1) (digits 0))
        (if (< i (byte-len t))
          (go (+ i 1) (%dc-big+ (%dc-big* r base) (%dcn-digit (byte-at t i) (- base 1))) (%dc-big* mult base) (+ digits 1))
          (let ((sum (%dcn-add (pair int 0) (%dcn-div (pair r 0) (pair mult 0) digits))))
            (if (%dcn-zero? sum) (pair 0 0)
              (if (< (rest sum) digits) (%dcn-cut sum digits) sum))))))))

; --- the machine's state ---------------------------------------------------------
;
; In a vector: the stack (top first), the registers ((NAME . VALUES) each, top
; first), the arrays ((NAME . ((INDEX . VALUE) ...)) each), the scale, the input
; and output bases, the characters on the line being written, the line's
; length, -x, how many frames run (the main one is 1), the file read and the
; line in it, the reader of standard input.
(def %dc ())
(def %dg (fn (_ i) (vec-ref %dc i)))
(def %dg! (fn (_ i v) (vec-set! %dc i v)))

; A stack item, in a vector: its kind and what it holds -- (lit num) a
; number, (lit str) a string, (lit const) a number's text not yet read,
; (lit elem) an array's (NAME . INDEX).
(def %dc-item (fn (_ kind v) (vec-build 2 (fn (_ i) (if (= i 0) kind v)))))
(def %dc-kind (fn (_ it) (vec-ref it 0)))
(def %dc-val (fn (_ it) (vec-ref it 1)))
(def %dc-numi (fn (_ n) (%dc-item (lit num) n)))

(def %dc-push! (fn (_ it) (%dg! 0 (pair it (%dg 0)))))

(def %dc-few (fn (_) (%dc-die "stack has too few elements")))

; the stack's top N items, or the error
(def %dc-need (fn (_ n) (if (< (length (%dg 0)) n) (%dc-few) ())))

(def %dc-pop!
  (fn (_) (do (%dc-need 1) (let ((it (first (%dg 0)))) (do (%dg! 0 (rest (%dg 0))) it)))))

; the number item IT holds: a constant read now, in the input base, and
; kept; an element read from its array; #f for a string
(def %dc-num-of
  (fn (_ it)
    (match
      ((eq? (%dc-kind it) (lit num)) (%dc-val it))
      ((eq? (%dc-kind it) (lit const))
        (let ((n (%dcn-parse (%dc-val it) (%dg 4))))
          (do (vec-set! it 0 (lit num)) (vec-set! it 1 n) n)))
      ((eq? (%dc-kind it) (lit elem)) (%dc-elem-get (first (%dc-val it)) (rest (%dc-val it))))
      (#t #f))))

; IT's number, or the wrong-type error
(def %dc-num!
  (fn (_ it) (let ((n (%dc-num-of it))) (if (eq? n #f) (%dc-die "variable is wrong type") n))))

; --- registers and arrays ---------------------------------------------------------

; NAME's values, top first: one zero for a register never set
(def %dc-reg
  (fn (_ name)
    (let ((e (filter (fn (_ r) (string=? (first r) name)) (%dg 1))))
      (if (pair? e) (rest (first e)) (list (%dc-numi (pair 0 0)))))))

(def %dc-reg!
  (fn (_ name vals)
    (%dg! 1 (pair (pair name vals) (filter (fn (_ r) (not (string=? (first r) name))) (%dg 1))))))

(def %dc-elem-get
  (fn (_ name idx)
    (let ((a (filter (fn (_ r) (string=? (first r) name)) (%dg 2))))
      (let ((e (if (pair? a) (filter (fn (_ c) (%dc-big= (first c) idx)) (rest (first a))) ())))
        (if (pair? e) (rest (first e)) (pair 0 0))))))

(def %dc-elem-set!
  (fn (_ name idx n)
    (let ((a (filter (fn (_ r) (string=? (first r) name)) (%dg 2))))
      (let ((cells (if (pair? a) (filter (fn (_ c) (not (%dc-big= (first c) idx))) (rest (first a))) ())))
        (%dg! 2 (pair (pair name (pair (pair idx n) cells))
                      (filter (fn (_ r) (not (string=? (first r) name))) (%dg 2))))))))

; an item as a register holds it: a number or a string, never a reference
(def %dc-held
  (fn (_ it) (if (eq? (%dc-kind it) (lit str)) it (%dc-numi (%dc-num! it)))))

; --- printing ------------------------------------------------------------------------
;
; What is printed goes to a list, written at the end of the command; the
; characters on the line are counted across commands, as bc's are, and a
; number breaks its line with a backslash at one short of the line's length.

(def %dc-out ())

(def %dc-emit! (fn (_ s) (set! %dc-out (pair s %dc-out))))

; the list written: runs of text joined, each NUL (lit nul) written alone
(def %dc-flush!
  (fn (_)
    (def write (fn (_ acc) (if (null? acc) () (file-write 1 (string-concat (reverse acc))))))
    (def go
      (fn (self cs acc)
        (match
          ((null? cs) (write acc))
          ((eq? (first cs) (lit nul)) (do (write acc) (file-write-run 1 (pair (%dc-nul-str) 1)) (self (rest cs) ())))
          (#t (self (rest cs) (pair (first cs) acc))))))
    (let ((cs (reverse %dc-out))) (do (set! %dc-out ()) (go cs ())))))

(def %dc-put! (fn (_ s) (%dc-emit! s)))
(def %dc-nul! (fn (_) (%dc-emit! (lit nul))))

(def %dc-nul-str
  (fn (_) (let ((b (str-make-raw 2))) (do (cu-ptr-set! (cu-str->ptr b) 0 0 1) b))))

; one character counted on the line
(def %dc-char! (fn (_ s) (do (%dc-put! s) (%dg! 6 (+ (%dg 6) 1)))))

; bc_num_printNewline: the line broken where it is one short of full
(def %dc-wrap!
  (fn (_) (if (= (%dg 6) (- (%dg 7) 1)) (do (%dc-put! "\\\n") (%dg! 6 0)) ())))

(def %dc-hexdig (fn (_ d) (bytes->str (list (if (< d 10) (+ #\0 d) (+ #\A (- d 10)))))))

; a digit as bc_num_printHex prints it, the point before it where RADIX
(def %dc-hex!
  (fn (_ d radix)
    (do (if radix (do (%dc-wrap!) (%dc-char! ".")) ())
        (%dc-wrap!)
        (%dc-char! (%dc-hexdig d)))))

; a digit as bc_num_printDigits prints it, past base 16: a space, or the
; point, then WIDTH decimal digits
(def %dc-digits!
  (fn (_ d width radix)
    (def text (cu-pad-zero (cu-int->str d) width))
    (do (%dc-wrap!)
        (%dc-char! (if radix "." " "))
        (map (fn (_ i) (do (%dc-wrap!) (%dc-char! (substring text i (+ i 1))))) (List range 0 width)))))

; N printed in the output base, then a newline where NL
(def %dc-print-num!
  (fn (_ n nl)
    (do (%dc-wrap!)
        (match
          ((%dcn-zero? n) (%dc-char! "0"))
          ((= (%dg 5) 10) (%dc-print-dec! n))
          (#t (%dc-print-base! n)))
        (if nl (do (%dc-put! "\n") (%dg! 6 0)) ()))))

(def %dc-print-dec!
  (fn (_ n)
    (def digits (cu-pad-zero (cu-int->str (%dcn-abs (first n))) (rest n)))
    (def point (- (byte-len digits) (rest n)))
    (do (if (%dcn-neg? n) (%dc-char! "-") ())
        (map (fn (_ i) (%dc-hex! (- (byte-at digits i) #\0) (= i point))) (List range 0 (byte-len digits))))))

(def %dc-print-base!
  (fn (_ n)
    (def base (%dg 5))
    (def width (byte-len (cu-int->str (- base 1))))
    (def put (if (<= base 16) (fn (_ d radix) (%dc-hex! d radix)) (fn (_ d radix) (%dc-digits! d width radix))))
    (do (if (%dcn-neg? n) (%dc-char! "-") ())
        (%dc-print-in! (pair (%dcn-abs (first n)) (rest n)) base put))))

; bc's zxc_num_printNum: N's integer part a digit of BASE at a time, then
; digits after the point until BASE to their count has more digits than N's
; scale
(def %dc-print-in!
  (fn (_ n base put)
    (def s (rest n))
    (def int (%dc-big/ (first n) (%dcn-ten s)))
    (def frac (%dc-big- (first n) (%dc-big* int (%dcn-ten s))))
    (def ints (let go ((v int) (acc ())) (if (%dc-big= v 0) acc (go (%dc-big/ v base) (pair (%dc-big% v base) acc)))))
    (do (map (fn (_ d) (put d #f)) ints)
        (if (= s 0) ()
          (let go ((f frac) (len 1) (radix #t))
            (if (> (%dcn-digits len) s) ()
              (let ((m (%dc-big* f base)))
                (let ((d (%dc-big/ m (%dcn-ten s))))
                  (do (put d radix)
                      (go (%dc-big- m (%dc-big* d (%dcn-ten s))) (%dc-big* len base) #f))))))))))

; a string as xc_program_printString prints it: its backslash escapes made,
; an empty one a NUL
(def %dc-print-str!
  (fn (_ s)
    (def n (byte-len s))
    (def go
      (fn (self i)
        (if (>= i n) ()
          (let ((c (byte-at s i)))
            (if (not (= c #\\)) (do (%dc-char! (bytes->str (list c))) (self (+ i 1)))
              (let ((e (if (< (+ i 1) n) (byte-at s (+ i 1)) 0)))
                (match
                  ((= e 0) (%dc-char! "\\"))
                  ((= e #\n) (do (%dc-put! "\n") (%dg! 6 0) (self (+ i 2))))
                  ((%dc-esc e) (do (%dc-char! (%dc-esc e)) (self (+ i 2))))
                  (#t (do (%dc-char! "\\") (%dc-char! (bytes->str (list e))) (self (+ i 2)))))))))))
    (if (= n 0) (%dc-nul!) (go 0))))

(def %dc-esc
  (fn (_ e)
    (match ((= e #\a) (bytes->str (list 7))) ((= e #\b) (bytes->str (list 8))) ((= e #\f) (bytes->str (list 12)))
           ((= e #\r) (bytes->str (list 13))) ((= e #\t) (bytes->str (list 9)))
           ((if (= e #\e) #t (= e #\\)) "\\") (#t #f))))

; IT printed as p prints it
(def %dc-print-item!
  (fn (_ it)
    (let ((n (%dc-num-of it)))
      (if (eq? n #f) (do (%dc-print-str! (%dc-val it)) (%dc-put! "\n"))
        (%dc-print-num! n #t)))))

; P: a string as it is, a number as bytes of base 256
(def %dc-stream!
  (fn (_ it)
    (let ((n (%dc-num-of it)))
      (match
        ((eq? n #f) (%dc-put! (%dc-val it)))
        ((%dcn-zero? n) (%dc-nul!))
        ((%dcn-neg? n) (%dc-die "negative number"))
        (#t (%dc-print-in! n 256
              (fn (_ d radix) (do (if (= d 0) (%dc-nul!) (%dc-put! (bytes->str (list d))))
                                  (%dg! 6 (+ (%dg 6) 1))))))))))

; --- reading the program -------------------------------------------------------------
;
; A source, in a vector: its text, where in it, the line, a thunk for more
; text (nil for none), and the text from the last token read to its line's
; end, which an error names.

(def %dcl-make
  (fn (_ text more) (vec-build 5 (fn (_ i) (match ((= i 0) text) ((= i 1) 0) ((= i 2) 1) ((= i 3) more) (#t ""))))))

; the byte K on from where SRC is, 0 at its end, more text read where wanted
(def %dcl-peek
  (fn (_ src k)
    (let ((text (vec-ref src 0)) (pos (vec-ref src 1)))
      (if (< (+ pos k) (byte-len text)) (byte-at text (+ pos k))
        (let ((more (if (null? (vec-ref src 3)) () ((vec-ref src 3)))))
          (if (null? more) 0
            (do (vec-set! src 0 (string-append (substring text pos (byte-len text)) more))
                (vec-set! src 1 0)
                (%dcl-peek src k))))))))

(def %dcl-skip! (fn (_ src n) (vec-set! src 1 (+ (vec-ref src 1) n))))

(def %dcl-take!
  (fn (_ src) (let ((c (%dcl-peek src 0))) (do (if (= c 0) () (%dcl-skip! src 1)) c))))

; the text from where SRC is to its line's end
(def %dcl-rest
  (fn (_ src)
    (let ((text (vec-ref src 0)) (pos (vec-ref src 1)))
      (let ((nl (dp-find text pos #\newline)))
        (substring text pos (if (< nl 0) (byte-len text) nl))))))

(def %dc-space? (fn (_ c) (if (= c #\space) #t (if (>= c 9) (<= c 13) #f))))
(def %dc-digit? (fn (_ c) (if (>= c #\0) (<= c #\9) #f)))
(def %dc-numch? (fn (_ c) (if (%dc-digit? c) #t (if (>= c #\A) (<= c #\F) #f))))

; the characters dc reads as commands on their own
(def %dc-ops "%(*+-/:;<=>?GIKLNOPQRSXZ^_acdefiklnopqrsvxz{|~")

; The next token from SRC: (lit eof), (lit nl), (num TEXT), (str TEXT),
; (ch TEXT) or, where REG, (name TEXT) -- the register a command names.
(def %dcl-next
  (fn (self src reg)
    (do (%dg! 11 (vec-ref src 2))
        (if (= (%dcl-peek src 0) 0) (list (lit eof))
          (do (vec-set! src 4 (%dcl-rest src))
              (if reg (%dcl-reg src)
                (let ((t (%dcl-token src)))
                  (if (eq? (first t) (lit space)) (self src #f) t))))))))

; a register's name: one character, any at all, or under -x after blanks a word
(def %dcl-reg
  (fn (_ src)
    (if (if (%dg 8) (%dc-space? (%dcl-peek src 0)) #f)
      (do (let go () (if (if (%dc-space? (%dcl-peek src 0)) (not (= (%dcl-peek src 0) #\newline)) #f)
                       (do (%dcl-skip! src 1) (go)) ()))
          (list (lit name)
                (let go ((acc ()))
                  (let ((c (%dcl-peek src 0)))
                    (if (if (if (>= c #\a) (<= c #\z) #f) #t (if (%dc-digit? c) #t (= c #\_)))
                      (do (%dcl-skip! src 1) (go (pair c acc)))
                      (bytes->str (reverse acc)))))))
      (list (lit name) (bytes->str (list (%dcl-take! src)))))))

(def %dcl-token
  (fn (_ src)
    (def c (%dcl-take! src))
    (match
      ((= c #\newline) (do (vec-set! src 2 (+ (vec-ref src 2) 1)) (list (lit nl))))
      ((%dc-space? c)
        (do (let go () (if (if (%dc-space? (%dcl-peek src 0)) (not (= (%dcl-peek src 0) #\newline)) #f)
                         (do (%dcl-skip! src 1) (go)) ()))
            (list (lit space))))
      ((= c #\#)
        (do (let go () (if (if (= (%dcl-peek src 0) 0) #f (not (= (%dcl-peek src 0) #\newline)))
                         (do (%dcl-skip! src 1) (go)) ()))
            (list (lit space))))
      ((= c #\!)
        (let ((c2 (%dcl-peek src 0)))
          (if (if (= c2 #\=) #t (if (= c2 #\<) #t (= c2 #\>)))
            (do (%dcl-skip! src 1) (list (lit ch) (bytes->str (list c c2))))
            (%dc-bad-char c))))
      ((= c #\.) (if (%dc-digit? (%dcl-peek src 0)) (%dcl-number src c) (%dc-bad-char c)))
      ((%dc-numch? c) (%dcl-number src c))
      ((= c #\[) (%dcl-string src))
      ((if (> c 0) (>= (dp-find %dc-ops 0 c) 0) #f) (list (lit ch) (bytes->str (list c))))
      (#t (%dc-bad-char c)))))

(def %dc-bad-char
  (fn (_ c) (if (= c 0) (%dc-die "NUL character") (%dc-die (string-concat (list "bad character '" (bytes->str (list c)) "'"))))))

; a number's text from its first character C: digits, A to F, one point, a
; backslash and newline passed over; a point at its end dropped
(def %dcl-number
  (fn (_ src c)
    (def go
      (fn (self acc pt)
        (let ((d (%dcl-peek src 0)))
          (match
            ((if (= d #\\) (= (%dcl-peek src 1) #\newline) #f)
              (do (%dcl-skip! src 2) (vec-set! src 2 (+ (vec-ref src 2) 1)) (self acc pt)))
            ((%dc-numch? d) (do (%dcl-skip! src 1) (self (pair d acc) pt)))
            ((if (= d #\.) (not pt) #f) (do (%dcl-skip! src 1) (self (pair d acc) #t)))
            (#t (let ((cs (if (= (first acc) #\.) (rest acc) acc))) (list (lit num) (bytes->str (reverse cs)))))))))
    (go (list c) (= c #\.))))

; a string's text up to its matching ], the brackets inside it kept
(def %dcl-string
  (fn (_ src)
    (def go
      (fn (self acc depth)
        (let ((c (%dcl-take! src)))
          (match
            ((= c 0) (%dc-die "unterminated string"))
            ((if (= c #\]) (= depth 1) #f) (list (lit str) (bytes->str (reverse acc))))
            (#t (do (if (= c #\newline) (vec-set! src 2 (+ (vec-ref src 2) 1)) ())
                    (self (pair c acc) (match ((= c #\[) (+ depth 1)) ((= c #\]) (- depth 1)) (#t depth)))))))))
    (go () 1)))

(def %dc-bad-token
  (fn (_ src) (%dc-die (string-concat (list "bad token at '" (vec-ref src 4) "'")))))

(def %dc-reg-ops (list "<" "=" ">" "!=" "!<" "!>" ":" ";" "s" "S" "l" "L"))

; TOK's command and the token after it: (COMMAND . NEXT); nil for none
(def %dcp-parse
  (fn (_ src tok)
    (def k (first tok))
    (def v (if (null? (rest tok)) () (first (rest tok))))
    (match
      ((eq? k (lit nl)) (pair () (%dcl-next src #f)))
      ((eq? k (lit num)) (pair (list (lit num) v) (%dcl-next src #f)))
      ((eq? k (lit str)) (pair (list (lit str) v) (%dcl-next src #f)))
      ((string=? v "_")
        (let ((t2 (%dcl-next src #f)))
          (if (eq? (first t2) (lit num)) (pair (list (lit negnum) (first (rest t2))) (%dcl-next src #f))
            (%dc-bad-token src))))
      ((string=? v "e") (%dc-bad-token src))
      ((pair? (filter (fn (_ o) (string=? o v)) %dc-reg-ops)) (%dcp-reg src v))
      ((if (string=? v "i") #t (if (string=? v "k") #t (string=? v "o")))
        (pair (list (lit setg) v) (%dcl-next src #f)))
      ((string=? v "?") (pair (list (lit read)) (%dcl-next src #f)))
      (#t (pair (list (lit op) v) (%dcl-next src #f))))))


; a command naming a register: a comparison takes another after e
(def %dcp-reg
  (fn (_ src v)
    (def r (%dcl-next src #t))
    (def name (if (eq? (first r) (lit name)) (first (rest r)) (%dc-bad-token src)))
    (if (pair? (filter (fn (_ o) (string=? o v)) (list "<" "=" ">" "!=" "!<" "!>")))
      (let ((t3 (%dcl-next src #f)))
        (if (if (eq? (first t3) (lit ch)) (string=? (first (rest t3)) "e") #f)
          (let ((r2 (%dcl-next src #t)))
            (if (eq? (first r2) (lit name))
              (pair (list (lit cond) v name (first (rest r2))) (%dcl-next src #f))
              (%dc-bad-token src)))
          (pair (list (lit cond) v name ()) t3)))
      (pair (list (lit reg) v name) (%dcl-next src #f)))))

; all of SRC's commands, read before any runs
(def %dcp-all
  (fn (_ src)
    (let go ((tok (%dcl-next src #f)) (acc ()))
      (if (eq? (first tok) (lit eof)) (reverse acc)
        (let ((r (%dcp-parse src tok)))
          (go (rest r) (if (null? (first r)) acc (pair (first r) acc))))))))

; --- running it ----------------------------------------------------------------------
;
; A command answers how many frames are to be left: 0 to go on, more where q
; or Q leaves macros.

; the top two items as numbers, the second first: (A . B)
(def %dc-two
  (fn (_) (do (%dc-need 2) (pair (%dc-num! (first (rest (%dg 0)))) (%dc-num! (first (%dg 0)))))))

; the top N items replaced by IT
(def %dc-replace! (fn (_ n it) (%dg! 0 (pair it (cu-nthrest n (%dg 0))))))

(def %dc-binop!
  (fn (_ f)
    (let ((ab (%dc-two))) (%dc-replace! 2 (%dc-numi (f (first ab) (rest ab) (%dg 3)))))))

(def %dc-bool (fn (_ t) (%dc-numi (pair (if t 1 0) 0))))

; a comparison's answer for A and B: < > ( { and the rest as bc's REL_ ops
(def %dc-rel
  (fn (_ op a b)
    (let ((c (%dcn-cmp a b)))
      (match
        ((string=? op "=") (= c 0)) ((string=? op "G") (= c 0)) ((string=? op "!=") (not (= c 0)))
        ((string=? op ">") (< c 0)) ((string=? op "<") (> c 0)) ((string=? op "(") (> c 0))
        ((string=? op "!<") (<= c 0)) ((string=? op "!>") (>= c 0)) ((string=? op "{") (>= c 0))
        (#t #f)))))

; Z: how many digits a number has, as xc_program_len counts them
(def %dc-len
  (fn (_ n)
    (if (%dcn-zero? n) 1
      (let ((d (%dcn-digits (first n))))
        (let ((l (%dcn-max d (rest n))))
          (if (= l (rest n)) d l))))))

; the string run as a macro, a frame deeper: how many frames are left after
(def %dc-run-macro
  (fn (_ text)
    (def cmds (%dcp-all (%dcl-make text ())))
    (do (%dg! 9 (+ (%dg 9) 1))
        (let ((u (%dc-run-all cmds)))
          (do (%dg! 9 (- (%dg 9) 1))
              (if (> u 0) (- u 1) 0))))))

(def %dc-run-all
  (fn (self cmds)
    (if (null? cmds) 0
      (let ((u (%dc-run (first cmds))))
        (if (> u 0) u (self (rest cmds)))))))

(def %dc-quit (fn (_) (Err raise (lit dc-quit) "" ())))

(def %dc-run
  (fn (_ cmd)
    (def k (first cmd))
    (match
      ((eq? k (lit num)) (do (%dc-push! (%dc-item (lit const) (first (rest cmd)))) 0))
      ((eq? k (lit negnum))
        (let ((n (%dcn-parse (first (rest cmd)) (%dg 4))))
          (do (%dc-push! (%dc-numi (pair (%dc-big- 0 (first n)) (rest n)))) 0)))
      ((eq? k (lit str)) (do (%dc-push! (%dc-item (lit str) (first (rest cmd)))) 0))
      ((eq? k (lit op)) (%dc-op (first (rest cmd))))
      ((eq? k (lit cond)) (%dc-cond (first (rest cmd)) (first (rest (rest cmd))) (first (rest (rest (rest cmd))))))
      ((eq? k (lit reg)) (do (%dc-reg-cmd (first (rest cmd)) (first (rest (rest cmd)))) 0))
      ((eq? k (lit setg)) (do (%dc-setg (first (rest cmd))) 0))
      ((eq? k (lit read)) (%dc-read))
      (#t 0))))

(def %dc-cond
  (fn (_ op then else)
    (let ((ab (%dc-two)))
      (do (%dc-replace! 2 (%dc-bool (%dc-rel op (first ab) (rest ab))))
          (let ((yes (not (%dcn-zero? (%dc-num! (first (%dg 0)))))))
            (let ((name (if yes then else)))
              (do (%dc-pop!)
                  (if (null? name) 0
                    (let ((top (first (%dc-reg name))))
                      (if (eq? (%dc-kind top) (lit str)) (%dc-run-macro (%dc-val top))
                        (%dc-die "variable is wrong type")))))))))))

; one of the commands that stand alone
(def %dc-op
  (fn (_ c)
    (match
      ((string=? c "+") (do (%dc-binop! (fn (_ a b k) (%dcn-add a b))) 0))
      ((string=? c "-") (do (%dc-binop! (fn (_ a b k) (%dcn-sub a b))) 0))
      ((string=? c "*") (do (%dc-binop! %dcn-mul) 0))
      ((string=? c "/") (do (%dc-binop! %dcn-div) 0))
      ((string=? c "%") (do (%dc-binop! %dcn-rem) 0))
      ((string=? c "^") (do (%dc-binop! %dcn-pow) 0))
      ((string=? c "~")
        (let ((ab (%dc-two)))
          (let ((qr (%dcn-divmod (first ab) (rest ab) (%dg 3))))
            (do (%dc-replace! 2 (%dc-numi (first qr))) (%dc-push! (%dc-numi (rest qr))) 0))))
      ((string=? c "|")
        (do (%dc-need 3)
            (let ((ab (%dc-two)) (a0 (%dc-num! (first (rest (rest (%dg 0)))))))
              (do (%dc-replace! 3 (%dc-numi (%dcn-modexp a0 (first ab) (rest ab)))) 0))))
      ((pair? (filter (fn (_ o) (string=? o c)) (list "(" "{" "G")))
        (let ((ab (%dc-two))) (do (%dc-replace! 2 (%dc-bool (%dc-rel c (first ab) (rest ab)))) 0)))
      (#t (%dc-op1 c)))))

(def %dc-op1
  (fn (_ c)
    (match
      ((string=? c "v") (do (%dc-need 1) (%dc-replace! 1 (%dc-numi (%dcn-sqrt (%dc-num! (first (%dg 0))) (%dg 3)))) 0))
      ((string=? c "N") (do (%dc-need 1) (%dc-replace! 1 (%dc-bool (%dcn-zero? (%dc-num! (first (%dg 0)))))) 0))
      ((if (string=? c "p") #t (string=? c "n")) (do (%dc-need 1) (%dc-print-item! (first (%dg 0))) 0))
      ((string=? c "P") (do (%dc-need 1) (%dc-stream! (first (%dg 0))) 0))
      ((string=? c "f") (do (map %dc-print-item! (%dg 0)) 0))
      ((string=? c "c") (do (%dg! 0 ()) 0))
      ((string=? c "d") (do (%dc-need 1) (%dc-push! (%dc-item (%dc-kind (first (%dg 0))) (%dc-val (first (%dg 0))))) 0))
      ((string=? c "r") (do (%dc-need 2) (%dg! 0 (pair (first (rest (%dg 0))) (pair (first (%dg 0)) (rest (rest (%dg 0)))))) 0))
      ((string=? c "R") (do (%dc-pop!) 0))
      ((string=? c "z") (do (%dc-push! (%dc-numi (pair (length (%dg 0)) 0))) 0))
      ((string=? c "K") (do (%dc-push! (%dc-numi (pair (%dg 3) 0))) 0))
      ((string=? c "I") (do (%dc-push! (%dc-numi (pair (%dg 4) 0))) 0))
      ((string=? c "O") (do (%dc-push! (%dc-numi (pair (%dg 5) 0))) 0))
      (#t (%dc-op2 c)))))

(def %dc-op2
  (fn (_ c)
    (match
      ((string=? c "Z")
        (do (%dc-need 1)
            (let ((it (first (%dg 0))))
              (let ((n (%dc-num-of it)))
                (%dc-replace! 1 (%dc-numi (pair (if (eq? n #f) (byte-len (%dc-val it)) (%dc-len n)) 0)))))
            0))
      ((string=? c "X") (do (%dc-need 1) (%dc-replace! 1 (%dc-numi (pair (rest (%dc-num! (first (%dg 0)))) 0))) 0))
      ((string=? c "a") (do (%dc-need 1) (%dc-replace! 1 (%dc-item (lit str) (%dc-ascii (first (%dg 0))))) 0))
      ((string=? c "x")
        (do (%dc-need 1)
            (let ((it (first (%dg 0))))
              (if (eq? (%dc-kind it) (lit str)) (do (%dc-pop!) (%dc-run-macro (%dc-val it))) 0))))
      ((string=? c "q") (if (<= (%dg 9) 2) (%dc-quit) 2))
      ((string=? c "Q")
        (let ((n (%dcn-ulong (%dc-num! (do (%dc-need 1) (first (%dg 0)))))))
          (do (%dc-pop!)
              (match ((%dc-big< (%dg 9) n) (%dc-few))
                     ((%dc-big= (%dg 9) n) (%dc-quit))
                     (#t n)))))
      (#t 0))))

; a: a number's low byte, or a string's first, as a string of one
(def %dc-ascii
  (fn (_ it)
    (let ((n (%dc-num-of it)))
      (if (eq? n #f)
        (let ((s (%dc-val it))) (if (= (byte-len s) 0) "" (substring s 0 1)))
        (let ((b (%dcn-ulong (pair (%dc-big% (%dc-big/ (first n) (%dcn-ten (rest n))) 256) 0))))
          (if (= b 0) "" (bytes->str (list b))))))))

; s S l L : and ; on the register NAME
(def %dc-reg-cmd
  (fn (_ c name)
    (def vals (%dc-reg name))
    (match
      ((string=? c "s") (do (%dc-need 1) (%dc-reg! name (pair (%dc-held (%dc-pop!)) (rest vals)))))
      ((string=? c "S") (%dc-reg! name (pair (%dc-held (%dc-pop!)) vals)))
      ((string=? c "l") (%dc-push! (first vals)))
      ((string=? c "L") (if (null? (rest vals)) (%dc-few) (do (%dc-push! (first vals)) (%dc-reg! name (rest vals)))))
      ((string=? c ";") (%dc-push! (%dc-item (lit elem) (pair name (%dc-index (%dc-pop!))))))
      (#t
        (let ((idx (%dc-index (do (%dc-need 1) (first (%dg 0))))))
          (do (%dg! 0 (rest (%dg 0)))
              (%dc-need 1)
              (let ((v (%dc-pop!)))
                (if (eq? (%dc-kind v) (lit str)) (%dc-die "variable is wrong type")
                  (%dc-elem-set! name idx (%dc-num! v))))))))))

; an array's index from IT
(def %dc-index (fn (_ it) (%dcn-ulong (%dc-num! it))))

; i k o: the top popped and made the input base, the scale or the output base
(def %dc-setg
  (fn (_ c)
    (do (%dc-need 1)
        (let ((it (first (%dg 0))))
          (do (if (eq? (%dc-kind it) (lit str)) (%dc-die "variable is wrong type") ())
              (let ((v (%dcn-ulong (%dc-num! it))))
                (match
                  ((string=? c "k") (%dg! 3 v))
                  ((string=? c "i") (if (if (< v 2) #t (> v 36)) (%dc-die "bad ibase; must be [2,16]") (%dg! 4 v)))
                  (#t (if (if (< v 2) #t (> v 999)) (%dc-die "bad obase; must be [2,999]") (%dg! 5 v)))))
              (%dc-pop!))))))

; ?: a line of standard input read and run, a frame deeper
(def %dc-read
  (fn (_)
    (def src (%dc-stdin))
    (def line (let go ((acc ())) (let ((c (%dcl-take! src))) (if (if (= c 0) #t (= c #\newline)) (bytes->str (reverse acc)) (go (pair c acc))))))
    (%dc-run-macro line)))

(def %dc-stdin
  (fn (_)
    (if (null? (%dg 12)) (%dg! 12 (%dcl-make "" (%dc-more (cu-pieces "-" %dc-stdin-thunk)))) ())
    (%dg 12)))

(def %dc-stdin-thunk ())

; a thunk for SRC's pieces as text, nil at the end
(def %dc-more
  (fn (_ src)
    (fn (_) (let ((p (src))) (if (if (Err err? p) #t (= (rest p) 0)) () (cu-run-text p))))))

; --- the applet ----------------------------------------------------------------------

; TEXT's commands run as busybox's zxc_vm_process runs them: each read, the
; token after it read, then it run
(def %dc-process
  (fn (_ src)
    (let go ((tok (%dcl-next src #f)))
      (if (eq? (first tok) (lit eof)) ()
        (let ((r (%dcp-parse src tok)))
          (do (if (null? (first r)) () (%dc-run (first r)))
              (%dc-flush!)
              (cu-sweep-tick! cu-sweep-lines)
              (go (rest r))))))))

; FILE's commands run, its name and line before an error's words
(def %dc-file
  (fn (_ file)
    (let ((p (cu-pieces file ())))
      (if (Err err? p) (%dc-die (string-concat (list "can't open '" file "': " (file-err-text p))))
        (do (%dg! 10 file) (%dc-process (%dcl-make "" (%dc-more p))) (p (lit close)) (%dg! 10 ()))))))

; DC_LINE_LENGTH, as xc_vm_init reads it
(def %dc-line-len
  (fn (_)
    (let ((e (sys-getenv "DC_LINE_LENGTH")))
      (if (null? e) 70
        (let ((n (if (si-digits? e) (cu-num-prefix e) ())))
          (match ((null? n) 70) ((= n 0) 2147483647) ((< n 2) 70) (#t n)))))))

; the -e and -f options in the order given, as getopt meets them: (FLAG . VALUE)
(def %dc-scripts
  (fn (self argv)
    (if (null? argv) ()
      (let ((w (first argv)))
        (match
          ((string=? w "--") ())
          ((if (< (byte-len w) 2) #t (not (= (byte-at w 0) #\-))) (self (rest argv)))
          (#t (%dc-cluster self w 1 (rest argv))))))))

(def %dc-cluster
  (fn (_ again w i more)
    (if (>= i (byte-len w)) (again more)
      (let ((c (byte-at w i)))
        (if (if (= c #\e) #t (= c #\f))
          (if (< (+ i 1) (byte-len w))
            (pair (pair c (substring w (+ i 1) (byte-len w))) (again more))
            (if (null? more) () (pair (pair c (first more)) (again (rest more)))))
          (%dc-cluster again w (+ i 1) more))))))

; dc [-x] [-eSCRIPT]... [-fFILE]... [FILE]...
(def cu-dc
  (fn (_ argv stdin-thunk)
    (def o (cu-opts "dc" argv))
    (do (set! %dc (vec-build 13 (fn (_ i) (match ((= i 3) 0) ((= i 4) 10) ((= i 5) 10) ((= i 6) 0) ((= i 7) (%dc-line-len))
                                                ((= i 8) (Opts on? o "-x")) ((= i 9) 1) ((= i 11) 1) (#t ())))))
        (set! %dc-out ())
        (set! %dc-stdin-thunk stdin-thunk)
        (guard (e (do (%dc-flush!)
                      (match
                        ((eq? (cu-err-label e) (lit dc-quit)) 0)
                        ((eq? (cu-err-label e) (lit dc))
                          (do (file-write 2 (string-concat (list "dc: " (if (null? (%dg 10)) ""
                                                                           (string-concat (list (%dg 10) ":" (cu-int->str (%dg 11)) ": ")))
                                                                 (e msg) "\n")))
                              1))
                        (#t (error e)))))
          (let ((scripts (%dc-scripts argv)) (files (Opts operands o)))
            (do (map (fn (_ s) (if (= (first s) #\e) (%dc-process (%dcl-make (rest s) ())) (%dc-file (rest s)))) scripts)
                (map %dc-file files)
                (if (if (null? scripts) (null? files) #f) (%dc-process (%dc-stdin)) ())
                0))))))

(provide cu/dc cu-dc)
