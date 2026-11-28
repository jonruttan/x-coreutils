; # x-coreutils -- the small tools, as applets
;
; ## lib/coreutils/bcnum.x -- bc's numbers and their printing, for bc and dc
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's bc and dc share one number library (miscutils/bc.c): a number is
; an exact integer and a scale, the digits after its point, and every
; operation follows bc's rules for the scale of its answer and truncates,
; never rounds.  Both print through one writer that counts the characters on
; the line and breaks a long number with a backslash.  An error here is
; raised under the label of the applet that started the writer.

(module coreutils/bcnum)

(import coreutils/dump dp-find)
(import coreutils/prims byte-at byte-len cu-int->str cu-ptr-set! cu-str->ptr
  file-write file-write-run map reverse str-make-raw substring sys-getenv
  vec-make vec-ref vec-set!)
(import coreutils/sysinfo si-digits?)
(import coreutils/text cu-num-prefix cu-pad-zero)

(def bn-big+ (fn (_ a b) (Bigint + a b)))
(def bn-big- (fn (_ a b) (Bigint - a b)))
(def bn-big* (fn (_ a b) (Bigint * a b)))
(def bn-big/ (fn (_ a b) (Bigint / a b)))
(def bn-big% (fn (_ a b) (Bigint % a b)))
(def bn-big< (fn (_ a b) (Bigint < a b)))
(def bn-big= (fn (_ a b) (Bigint = a b)))

; --- the writer ----------------------------------------------------------------------
;
; In a vector: what is printed, newest first, written when flushed; the
; characters on the line, counted across statements as bc's are; the line's
; length, a number breaking its line with a backslash at one short of it;
; the label an error is raised under.

(def %bn-pr (vec-make 4 ()))

(def bn-start!
  (fn (_ label len)
    (do (vec-set! %bn-pr 0 ()) (vec-set! %bn-pr 1 0) (vec-set! %bn-pr 2 len) (vec-set! %bn-pr 3 label))))

(def bn-die (fn (_ msg) (Err raise (vec-ref %bn-pr 3) msg ())))

(def bn-col (fn (_) (vec-ref %bn-pr 1)))
(def bn-col! (fn (_ n) (vec-set! %bn-pr 1 n)))

(def bn-emit! (fn (_ s) (vec-set! %bn-pr 0 (pair s (vec-ref %bn-pr 0)))))
(def bn-nul! (fn (_) (bn-emit! (lit nul))))

; the list written: runs of text joined, each NUL (lit nul) written alone
(def bn-flush!
  (fn (_)
    (def write (fn (_ acc) (if (null? acc) () (file-write 1 (%str-concat (reverse acc))))))
    (def go
      (fn (self cs acc)
        (match
          ((null? cs) (write acc))
          ((eq? (first cs) (lit nul)) (do (write acc) (file-write-run 1 (pair (%bn-nul-str) 1)) (self (rest cs) ())))
          (#t (self (rest cs) (pair (first cs) acc))))))
    (let ((cs (reverse (vec-ref %bn-pr 0)))) (do (vec-set! %bn-pr 0 ()) (go cs ())))))

(def %bn-nul-str
  (fn (_) (let ((b (str-make-raw 2))) (do (cu-ptr-set! (cu-str->ptr b) 0 0 1) b))))

; one character counted on the line
(def bn-char! (fn (_ s) (do (bn-emit! s) (bn-col! (+ (bn-col) 1)))))

; a newline, the count begun again
(def bn-newline! (fn (_) (do (bn-emit! "\n") (bn-col! 0))))

; bc_num_printNewline: the line broken where it is one short of full
(def bn-wrap!
  (fn (_) (if (= (bn-col) (- (vec-ref %bn-pr 2) 1)) (do (bn-emit! "\\\n") (bn-col! 0)) ())))

; the line's length from the environment variable NAME, as xc_vm_envLen
; reads it: 70 unset or unread, 0 the most there is; bc's one shorter
; (BC where bc asks), and under 2 the default
(def bn-line-len
  (fn (_ name bc)
    (def e (sys-getenv name))
    (def n (if (null? e) 70 (let ((v (if (si-digits? e) (cu-num-prefix e) ()))) (match ((null? v) 70) ((= v 0) 2147483647) (#t v)))))
    (def len (if bc (- n 1) n))
    (if (< len 2) (if bc 69 70) len)))

; --- numbers ---------------------------------------------------------------------
;
; A number is (M . S): the value M / 10^S, S its scale.  Zero is never negative.

(def %bn-tens (vec-make 64 ()))

; 10^N
(def bn-ten
  (fn (_ n)
    (if (< n 64)
      (let ((c (vec-ref %bn-tens n)))
        (if (null? c) (let ((v (%bn-ten-go n))) (do (vec-set! %bn-tens n v) v)) c))
      (%bn-ten-go n))))

(def %bn-ten-go
  (fn (_ n) (let go ((k n) (acc 1)) (if (= k 0) acc (go (- k 1) (bn-big* acc 10))))))

(def bn-zero? (fn (_ x) (bn-big= (first x) 0)))
(def bn-neg? (fn (_ x) (bn-big< (first x) 0)))
(def bn-abs (fn (_ m) (if (bn-big< m 0) (bn-big- 0 m) m)))

; X's integer at scale S, S at least its own
(def bn-at (fn (_ x s) (bn-big* (first x) (bn-ten (- s (rest x))))))

; X cut to scale S, its digits past S dropped
(def bn-cut
  (fn (_ x s)
    (if (>= s (rest x)) (pair (bn-at x s) s)
      (pair (bn-big/ (first x) (bn-ten (- (rest x) s))) s))))

(def bn-max (fn (_ a b) (if (> a b) a b)))
(def bn-min (fn (_ a b) (if (< a b) a b)))

(def bn-add
  (fn (_ a b)
    (let ((s (bn-max (rest a) (rest b))))
      (pair (bn-big+ (bn-at a s) (bn-at b s)) s))))

(def bn-sub
  (fn (_ a b)
    (let ((s (bn-max (rest a) (rest b))))
      (pair (bn-big- (bn-at a s) (bn-at b s)) s))))

; -1, 0 or 1 as A is below, at or above B
(def bn-cmp
  (fn (_ a b)
    (let ((s (bn-max (rest a) (rest b))))
      (let ((x (bn-at a s)) (y (bn-at b s)))
        (match ((bn-big< x y) -1) ((bn-big< y x) 1) (#t 0))))))

; bc's multiply: the product cut to the lesser of the operands' scales summed
; and the greatest of SCALE and theirs
(def bn-mul
  (fn (_ a b scale)
    (let ((full (+ (rest a) (rest b))))
      (bn-cut (pair (bn-big* (first a) (first b)) full)
              (bn-min full (bn-max scale (bn-max (rest a) (rest b))))))))

; A / B at SCALE, truncated
(def bn-div
  (fn (_ a b scale)
    (if (bn-zero? b) (bn-die "divide by zero")
      (pair (bn-big/ (bn-big* (first a) (bn-ten (+ (rest b) scale)))
                     (bn-big* (first b) (bn-ten (rest a))))
            scale))))

; (QUOTIENT . REMAINDER) as bc's divmod makes them: the quotient at SCALE,
; the remainder A less it times B, at the greater of SCALE plus B's scale and
; A's
(def bn-divmod
  (fn (_ a b scale)
    (def ts (bn-max (+ scale (rest b)) (rest a)))
    (if (bn-zero? b) (bn-die "divide by zero")
      (if (bn-zero? a) (pair (pair 0 scale) (pair 0 ts))
        (let ((q (bn-div a b scale)))
          (pair q (bn-cut (bn-sub a (bn-mul q b (+ scale (rest b)))) ts)))))))

(def bn-rem (fn (_ a b scale) (rest (bn-divmod a b scale))))

; X's integer part as a count, as zbc_num_ulong takes it: an error where X
; is negative or past an unsigned long
(def bn-ulong
  (fn (_ x)
    (if (bn-neg? x) (bn-die "negative number")
      (let ((v (bn-big/ (first x) (bn-ten (rest x)))))
        (if (if (> (bn-digits v) 19) (not (bn-big< v (%bn-two-to 64))) #f) (bn-die "overflow") v)))))

(def %bn-two-to (fn (_ n) (let go ((k n) (acc 1)) (if (= k 0) acc (go (- k 1) (bn-big* acc 2))))))

(def bn-int? (fn (_ x) (bn-big= (bn-big% (first x) (bn-ten (rest x))) 0)))

; X is exactly 1 or -1 with no digits past the point, as BC_NUM_ONE asks
(def bn-one? (fn (_ x) (if (= (rest x) 0) (bn-big= (bn-abs (first x)) 1) #f)))

; bc's zbc_num_p: A^B, B an integer, by squaring, each multiply cut as bc's are
(def bn-pow
  (fn (_ a b scale)
    (match
      ((not (bn-int? b)) (bn-die "not an integer"))
      ((bn-zero? b) (pair 1 0))
      ((bn-zero? a) (pair 0 scale))
      ((bn-one? b) (if (bn-neg? b) (bn-div (pair 1 0) a scale) a))
      (#t (%bn-pow-go a (bn-neg? b) (bn-big/ (bn-abs (first b)) (bn-ten (rest b))) scale)))))

(def %bn-pow-go
  (fn (_ a neg pow scale0)
    (def ar (rest a))
    (def scale
      (if neg scale0
        (let ((s (bn-max scale0 ar)))
          (if (bn-big< (bn-big* ar pow) s) (bn-big* ar pow) s))))
    ; the lowest set bit of POW, squaring as it is passed
    (def low
      (fn (self copy p prdx)
        (if (bn-big= (bn-big% p 2) 1) (list copy p prdx)
          (let ((r2 (* prdx 2))) (self (bn-mul copy copy r2) (bn-big/ p 2) r2)))))
    (def high
      (fn (self c copy p prdx rrdx)
        (if (bn-big= p 0) c
          (let ((r2 (* prdx 2)))
            (let ((sq (bn-mul copy copy r2)))
              (if (bn-big= (bn-big% p 2) 1)
                (let ((rr (+ rrdx r2))) (self (bn-mul c sq rr) sq (bn-big/ p 2) r2 rr))
                (self c sq (bn-big/ p 2) r2 rrdx)))))))
    (def l (low a pow ar))
    (def c (high (first l) (first l) (bn-big/ (first (rest l)) 2) (first (rest (rest l))) (first (rest (rest l)))))
    (def c2 (if neg (bn-div (pair 1 0) c scale) c))
    (def c3 (if (> (rest c2) scale) (bn-cut c2 scale) c2))
    (if (bn-zero? c3) (pair 0 scale) c3)))

; the integer square root of N
(def bn-isqrt
  (fn (_ n)
    (if (bn-big< n 2) n
      (let go ((x (bn-ten (+ (bn-digits n) 1))))
        (let ((y (bn-big/ (bn-big+ x (bn-big/ n x)) 2)))
          (if (bn-big< y x) (go y) x))))))

; how many decimal digits N has, 0 for 0
(def bn-digits
  (fn (_ n) (let go ((k 0) (v (bn-abs n))) (if (bn-big= v 0) k (go (+ k 1) (bn-big/ v 10))))))

; bc's sqrt: at the greater of SCALE and A's own, truncated
(def bn-sqrt
  (fn (_ a scale)
    (match
      ((bn-zero? a) (pair 0 scale))
      ((bn-neg? a) (bn-die "negative number"))
      ((bn-one? a) (pair (bn-ten scale) scale))
      (#t (let ((s (bn-max scale (rest a))))
            (pair (bn-isqrt (bn-big* (first a) (bn-ten (- (* 2 s) (rest a))))) s))))))

; dc's |: A^B mod C, all integers
(def bn-modexp
  (fn (_ a b c)
    (match
      ((bn-zero? c) (bn-die "divide by zero"))
      ((if (> (rest a) 0) #t (if (> (rest b) 0) #t (> (rest c) 0))) (bn-die "not an integer"))
      ((bn-neg? b) (bn-die "negative number"))
      (#t (let go ((d 1) (base (bn-big% (first a) (first c))) (e (first b)))
            (if (bn-big= e 0) (pair d 0)
              (let ((d2 (if (bn-big= (bn-big% e 2) 1) (bn-big% (bn-big* d base) (first c)) d)))
                (go d2 (bn-big% (bn-big* base base) (first c)) (bn-big/ e 2)))))))))

; the value of TEXT read in BASE, as zxc_num_parse reads it: a single digit
; is itself; in base 10 a digit past 9 is 9; in another base, a digit past
; it is the base less 1, and the digits after the point make the scale
(def bn-parse
  (fn (_ text base)
    (def t (%bn-strip0 text))
    (match
      ((%bn-all-zero? t) (pair 0 0))
      ((= (byte-len t) 1) (pair (%bn-digit (byte-at t 0) 36) 0))
      ((= base 10) (%bn-parse10 t))
      (#t (%bn-parse-base t base)))))

(def %bn-strip0
  (fn (_ s) (let go ((i 0)) (if (if (< i (byte-len s)) (= (byte-at s i) #\0) #f) (go (+ i 1)) (substring s i (byte-len s))))))

(def %bn-all-zero?
  (fn (_ s) (let go ((i 0)) (match ((>= i (byte-len s)) #t) ((if (= (byte-at s i) #\0) #t (= (byte-at s i) #\.)) (go (+ i 1))) (#t #f)))))

; a digit's value, no more than MAX
(def %bn-digit
  (fn (_ c max) (let ((v (if (<= c #\9) (- c #\0) (+ (- c #\A) 10)))) (if (> v max) max v))))

(def %bn-parse10
  (fn (_ t)
    (def dot (dp-find t 0 #\.))
    (let go ((i 0) (m 0))
      (if (>= i (byte-len t)) (pair m (if (< dot 0) 0 (- (byte-len t) (+ dot 1))))
        (if (= i dot) (go (+ i 1) m)
          (go (+ i 1) (bn-big+ (bn-big* m 10) (%bn-digit (byte-at t i) 9))))))))

(def %bn-parse-base
  (fn (_ t base)
    (def dot (dp-find t 0 #\.))
    (def end (if (< dot 0) (byte-len t) dot))
    (def int (let go ((i 0) (m 0)) (if (>= i end) m (go (+ i 1) (bn-big+ (bn-big* m base) (%bn-digit (byte-at t i) (- base 1)))))))
    (if (< dot 0) (pair int 0)
      (let go ((i (+ dot 1)) (r 0) (mult 1) (digits 0))
        (if (< i (byte-len t))
          (go (+ i 1) (bn-big+ (bn-big* r base) (%bn-digit (byte-at t i) (- base 1))) (bn-big* mult base) (+ digits 1))
          (let ((sum (bn-add (pair int 0) (bn-div (pair r 0) (pair mult 0) digits))))
            (if (bn-zero? sum) (pair 0 0)
              (if (< (rest sum) digits) (bn-cut sum digits) sum))))))))

; --- printing ------------------------------------------------------------------------

(def %bn-hexdig (fn (_ d) (bytes->str (list (if (< d 10) (+ #\0 d) (+ #\A (- d 10)))))))

; a digit as bc_num_printHex prints it, the point before it where RADIX
(def %bn-hex!
  (fn (_ d radix)
    (do (if radix (do (bn-wrap!) (bn-char! ".")) ())
        (bn-wrap!)
        (bn-char! (%bn-hexdig d)))))

; a digit as bc_num_printDigits prints it, past base 16: a space, or the
; point, then WIDTH decimal digits
(def %bn-digits!
  (fn (_ d width radix)
    (def text (cu-pad-zero (cu-int->str d) width))
    (do (bn-wrap!)
        (bn-char! (if radix "." " "))
        (map (fn (_ i) (do (bn-wrap!) (bn-char! (substring text i (+ i 1))))) (List range 0 width)))))

; N printed in BASE, then a newline where NL
(def bn-print-num!
  (fn (_ n base nl)
    (do (bn-wrap!)
        (match
          ((bn-zero? n) (bn-char! "0"))
          ((= base 10) (%bn-print-dec! n))
          (#t (%bn-print-base! n base)))
        (if nl (bn-newline!) ()))))

(def %bn-print-dec!
  (fn (_ n)
    (def digits (cu-pad-zero (cu-int->str (bn-abs (first n))) (rest n)))
    (def point (- (byte-len digits) (rest n)))
    (do (if (bn-neg? n) (bn-char! "-") ())
        (map (fn (_ i) (%bn-hex! (- (byte-at digits i) #\0) (= i point))) (List range 0 (byte-len digits))))))

(def %bn-print-base!
  (fn (_ n base)
    (def width (byte-len (cu-int->str (- base 1))))
    (def put (if (<= base 16) (fn (_ d radix) (%bn-hex! d radix)) (fn (_ d radix) (%bn-digits! d width radix))))
    (do (if (bn-neg? n) (bn-char! "-") ())
        (bn-print-in! (pair (bn-abs (first n)) (rest n)) base put))))

; bc's zxc_num_printNum: N's integer part a digit of BASE at a time, then
; digits after the point until BASE to their count has more digits than N's
; scale
(def bn-print-in!
  (fn (_ n base put)
    (def s (rest n))
    (def int (bn-big/ (first n) (bn-ten s)))
    (def frac (bn-big- (first n) (bn-big* int (bn-ten s))))
    (def ints (let go ((v int) (acc ())) (if (bn-big= v 0) acc (go (bn-big/ v base) (pair (bn-big% v base) acc)))))
    (do (map (fn (_ d) (put d #f)) ints)
        (if (= s 0) ()
          (let go ((f frac) (len 1) (radix #t))
            (if (> (bn-digits len) s) ()
              (let ((m (bn-big* f base)))
                (let ((d (bn-big/ m (bn-ten s))))
                  (do (put d radix)
                      (go (bn-big- m (bn-big* d (bn-ten s))) (bn-big* len base) #f))))))))))

; a string as xc_program_printString prints it, its backslash escapes made:
; \n \a \b \f \r \t, \e and \\ a backslash, any other the backslash and it
(def bn-print-str!
  (fn (_ s)
    (def n (byte-len s))
    (def go
      (fn (self i)
        (if (>= i n) ()
          (let ((c (byte-at s i)))
            (if (not (= c #\\)) (do (bn-char! (bytes->str (list c))) (self (+ i 1)))
              (let ((e (if (< (+ i 1) n) (byte-at s (+ i 1)) 0)))
                (match
                  ((= e 0) (bn-char! "\\"))
                  ((= e #\n) (do (bn-newline!) (self (+ i 2))))
                  ((%bn-esc e) (do (bn-char! (%bn-esc e)) (self (+ i 2))))
                  (#t (do (bn-char! "\\") (bn-char! (bytes->str (list e))) (self (+ i 2)))))))))))
    (go 0)))

(def %bn-esc
  (fn (_ e)
    (match ((= e #\a) (bytes->str (list 7))) ((= e #\b) (bytes->str (list 8))) ((= e #\f) (bytes->str (list 12)))
           ((= e #\r) (bytes->str (list 13))) ((= e #\t) (bytes->str (list 9)))
           ((if (= e #\e) #t (= e #\\)) "\\") (#t #f))))

(provide coreutils/bcnum bn-abs bn-add bn-at bn-big% bn-big* bn-big+ bn-big-
  bn-big/ bn-big< bn-big= bn-char! bn-cmp bn-col bn-col! bn-cut bn-die
  bn-digits bn-div bn-divmod bn-emit! bn-flush! bn-int? bn-isqrt bn-line-len
  bn-max bn-min bn-modexp bn-mul bn-neg? bn-newline! bn-nul! bn-one? bn-parse
  bn-pow bn-print-in! bn-print-num! bn-print-str! bn-rem bn-sqrt bn-start!
  bn-sub bn-ten bn-ulong bn-wrap! bn-zero?)
