; # x-coreutils -- the small tools, as applets
;
; ## cu/expr.x -- expr, and the anchored matcher it needs
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; expr(1) is a recursive-descent parser over the ARGUMENT LIST -- the
; shell already tokenised it, so there is no lexer.  Each level answers
; (pair value remaining-tokens) and the levels chain by precedence:
;
;   |  &  <= < != = == >= >  + -  * / %  :  primary
;
; The `:` operator and `match` need a regular expression, and this
; bundle chains no dependency on x-grep's regex layer, so a small
; anchored BRE matcher lives here: literals, `.`, `*`, `[...]` with
; ranges and negation, `$`, and one `\(...\)` capture.  That is the
; grammar expr's own manual documents; the interval and alternation
; forms are not part of it.

; --- the matcher ---------------------------------------------------------------

; an atom is (KIND DATA STAR?): ch/any/cls take a byte, gopen/gclose
; mark the capture, eol anchors the end.
(def %cu-re-kind (fn (_ a) (%cu-nth 0 a)))
(def %cu-re-data (fn (_ a) (%cu-nth 1 a)))
(def %cu-re-star? (fn (_ a) (%cu-nth 2 a)))

; a bracket expression: an optional leading ^ negates, a ] first is
; literal, and A-Z is a range.  Answers (pair (NEG . RANGES) next-i).
(def %cu-re-class
  (fn (_ pat i)
    (def end (byte-len pat))
    (def neg (if (< i end) (= (byte-at pat i) 94) #f))          ; ^
    (def start (if neg (+ i 1) i))
    (def go
      (fn (self j acc first?)
        (if (>= j end) (pair (pair neg (reverse acc)) j)
          (let ((b (byte-at pat j)))
            (if (if (= b 93) (not first?) #f)                   ; ]
              (pair (pair neg (reverse acc)) (+ j 1))
              (if (if (< (+ j 2) end)
                    (if (= (byte-at pat (+ j 1)) 45)            ; -
                      (not (= (byte-at pat (+ j 2)) 93)) #f)
                    #f)
                (self (+ j 3) (pair (pair b (byte-at pat (+ j 2))) acc) #f)
                (self (+ j 1) (pair (pair b b) acc) #f)))))))
    (go start () #t)))

(def %cu-re-in-class?
  (fn (_ data b)
    (def neg (first data))
    (def go
      (fn (self rs)
        (if (null? rs) #f
          (if (if (>= b (first (first rs))) (<= b (rest (first rs))) #f)
            #t (self (rest rs))))))
    (let ((hit (go (rest data)))) (if neg (not hit) hit))))

; The pattern to a list of atoms; `*` binds to the atom before it.
;
; A \(...\) group SPLICES in between gopen/gclose markers, so the flat
; matcher backtracks through it exactly as it would through the same
; atoms written out.  A group with a trailing `*` cannot be spelled
; that way -- the repetition is over the whole subsequence -- so it
; becomes one `rep` atom, matched greedily.  Answers (ATOMS . NEXT-I).
(def %cu-re-parse-to
  (fn (self pat i closing? acc)
    (def end (byte-len pat))
    (if (>= i end) (pair (reverse acc) i)
      (let ((b (byte-at pat i)))
        (if (= b 92) (%cu-re-parse-escape self pat i closing? acc)
          (if (if (= b 36) (= (+ i 1) end) #f)                 ; $ at the end
            (self pat (+ i 1) closing? (pair (list (lit eol) 0 #f) acc))
            (if (= b 91)                                       ; [
              (let ((c (%cu-re-class pat (+ i 1))))
                (self pat (%cu-re-after (rest c) pat) closing?
                  (pair (list (lit cls) (first c)
                          (%cu-re-starred? pat (rest c)))
                    acc)))
              (self pat (%cu-re-after (+ i 1) pat) closing?
                (pair (list (if (= b 46) (lit any) (lit ch)) b
                        (%cu-re-starred? pat (+ i 1)))
                  acc)))))))))

; \( opens a group, \) closes the one being parsed, and anything else
; escaped is the literal byte
(def %cu-re-parse-escape
  (fn (_ self pat i closing? acc)
    (def end (byte-len pat))
    (def e (if (< (+ i 1) end) (byte-at pat (+ i 1)) 92))
    (if (= e 41)                                               ; \)
      (if closing? (pair (reverse acc) (+ i 2))
        (self pat (+ i 2) closing? (pair (list (lit ch) 41 #f) acc)))
      (if (= e 40)                                             ; \(
        (%cu-re-parse-group self pat (+ i 2) closing? acc)
        (self pat (%cu-re-after (+ i 2) pat) closing?
          (pair (list (lit ch) e (%cu-re-starred? pat (+ i 2))) acc)))))))

(def %cu-re-parse-group
  (fn (_ self pat i closing? acc)
    (def inner (%cu-re-parse-to pat i #t ()))
    (def after (rest inner))
    (if (%cu-re-starred? pat after)
      (self pat (+ after 1) closing?
        (pair (list (lit rep) (first inner) #t) acc))
      (self pat after closing?
        (pair (list (lit gclose) 0 #f)
          (append (reverse (first inner))
            (pair (list (lit gopen) 0 #f) acc)))))))

(def %cu-re-parse
  (fn (_ pat i acc) (first (%cu-re-parse-to pat i #f acc))))

(def %cu-re-starred?
  (fn (_ pat j)
    (if (>= j (byte-len pat)) #f (= (byte-at pat j) 42))))       ; *

(def %cu-re-after
  (fn (_ j pat) (if (%cu-re-starred? pat j) (+ j 1) j)))

(def %cu-re-one?
  (fn (_ a s i)
    (if (>= i (byte-len s)) #f
      (let ((k (%cu-re-kind a)))
        (def b (byte-at s i))
        (if (eq? k (lit ch)) (= b (%cu-re-data a))
          (if (eq? k (lit any)) #t
            (if (eq? k (lit cls)) (%cu-re-in-class? (%cu-re-data a) b)
              #f)))))))

(def %cu-re-run
  (fn (self a s i n)
    (if (%cu-re-one? a s (+ i n)) (self a s i (+ n 1)) n)))

; a starred atom takes the LONGEST run that lets the rest match, so the
; try walks the run length down to zero
(def %cu-re-star-try
  (fn (_ atoms s i gs ge)
    (def go
      (fn (self n)
        (if (< n 0) ()
          (let ((r (%cu-re-match (rest atoms) s (+ i n) gs ge)))
            (if (null? r) (self (- n 1)) r)))))
    (go (%cu-re-run (first atoms) s i 0))))

; answers () for no match, else (END GROUP-START GROUP-END)
; a starred GROUP repeats greedily, without backtracking into the
; repetition count: expr uses the form to skip a run, and the capture
; it leaves behind is the LAST iteration.
(def %cu-re-rep
  (fn (_ atoms s i gs ge)
    (def sub (%cu-re-data (first atoms)))
    (def go
      (fn (self at last)
        (let ((r (%cu-re-match sub s at (- 0 1) (- 0 1))))
          (if (null? r) (pair at last)
            (if (= (first r) at) (pair at last)
              (self (first r) at))))))
    (def done (go i i))
    (if (= (first done) i)
      (%cu-re-match (rest atoms) s i gs ge)
      (%cu-re-match (rest atoms) s (first done) (rest done) (first done)))))

(def %cu-re-match
  (fn (self atoms s i gs ge)
    (if (null? atoms) (list i gs ge)
      (let ((a (first atoms)))
        (def k (%cu-re-kind a))
        (if (eq? k (lit rep)) (%cu-re-rep atoms s i gs ge)
          (if (eq? k (lit gopen)) (self (rest atoms) s i i ge)
            (if (eq? k (lit gclose)) (self (rest atoms) s i gs i)
              (if (eq? k (lit eol))
                (if (= i (byte-len s)) (self (rest atoms) s i gs ge) ())
                (if (%cu-re-star? a)
                  (%cu-re-star-try atoms s i gs ge)
                  (if (%cu-re-one? a s i)
                    (self (rest atoms) s (+ i 1) gs ge)
                    ()))))))))))))

; a capture is either a spliced group or a starred one
(def %cu-re-has-group?
  (fn (self atoms)
    (if (null? atoms) #f
      (if (eq? (%cu-re-kind (first atoms)) (lit gopen)) #t
        (if (eq? (%cu-re-kind (first atoms)) (lit rep)) #t
          (self (rest atoms)))))))

; expr's `:`: a capture answers the captured text, a plain pattern
; answers how many characters it spanned.  No match is "" or 0.
(def %cu-expr-colon
  (fn (_ s pat)
    (def atoms (%cu-re-parse pat 0 ()))
    (def r (%cu-re-match atoms s 0 (- 0 1) (- 0 1)))
    (if (%cu-re-has-group? atoms)
      (if (null? r) ""
        (if (< (%cu-nth 1 r) 0) ""
          (substring s (%cu-nth 1 r) (%cu-nth 2 r))))
      (if (null? r) "0" (%cu-int->str (first r))))))

; --- values --------------------------------------------------------------------

(def %cu-expr-num?
  (fn (_ s)
    (def end (byte-len s))
    (def start (if (= end 0) 0 (if (= (byte-at s 0) 45) 1 0)))
    (def go
      (fn (self i)
        (if (>= i end) (> end start)
          (let ((b (byte-at s i)))
            (if (if (>= b 48) (<= b 57) #f) (self (+ i 1)) #f)))))
    (if (= end 0) #f (go start))))

(def %cu-expr-int (fn (_ s) (%cu-num-prefix s)))

; the truth expr tests: neither empty nor the number zero
(def %cu-expr-true?
  (fn (_ v)
    (if (= (byte-len v) 0) #f
      (if (%cu-expr-num? v) (not (= (%cu-expr-int v) 0)) #t))))

(def %cu-expr-arith
  (fn (_ op a b)
    (def x (%cu-expr-int a))
    (def y (%cu-expr-int b))
    (if (string=? op "+") (%cu-int->str (+ x y))
      (if (string=? op "-") (%cu-int->str (- x y))
        (if (string=? op "*") (%cu-int->str (* x y))
          (if (= y 0) (Err raise (lit cu) "expr: division by zero" ())
            (if (string=? op "/")
              (%cu-int->str (/ (- x (% x y)) y))
              (%cu-int->str (% x y)))))))))

; a comparison is numeric when BOTH sides look like numbers, and a
; byte-wise string comparison otherwise
(def %cu-expr-compare
  (fn (_ op a b)
    (def numeric? (if (%cu-expr-num? a) (%cu-expr-num? b) #f))
    (def c
      (if numeric?
        (let ((x (%cu-expr-int a)) (y (%cu-expr-int b)))
          (if (< x y) (- 0 1) (if (> x y) 1 0)))
        (if (string=? a b) 0 (if (%cu-str< a b) (- 0 1) 1))))
    (def yes
      (if (string=? op "=") (= c 0)
        (if (string=? op "==") (= c 0)
          (if (string=? op "!=") (not (= c 0))
            (if (string=? op "<") (< c 0)
              (if (string=? op "<=") (<= c 0)
                (if (string=? op ">") (> c 0) (>= c 0))))))))
    (if yes "1" "0")))

; --- the grammar ---------------------------------------------------------------

(def %cu-expr-cmp-op?
  (fn (_ s)
    (if (string=? s "<") #t
      (if (string=? s "<=") #t
        (if (string=? s "=") #t
          (if (string=? s "==") #t
            (if (string=? s "!=") #t
              (if (string=? s ">=") #t (string=? s ">")))))))))

(def %cu-expr-or
  (fn (_ ts)
    (def r (%cu-expr-and ts))
    (def go
      (fn (self v xs)
        (if (null? xs) (pair v xs)
          (if (not (string=? (first xs) "|")) (pair v xs)
            (let ((r2 (%cu-expr-and (rest xs))))
              (self (if (%cu-expr-true? v) v
                      (if (%cu-expr-true? (first r2)) (first r2) "0"))
                (rest r2)))))))
    (go (first r) (rest r))))

(def %cu-expr-and
  (fn (_ ts)
    (def r (%cu-expr-cmp ts))
    (def go
      (fn (self v xs)
        (if (null? xs) (pair v xs)
          (if (not (string=? (first xs) "&")) (pair v xs)
            (let ((r2 (%cu-expr-cmp (rest xs))))
              (self (if (if (%cu-expr-true? v)
                          (%cu-expr-true? (first r2)) #f)
                      v "0")
                (rest r2)))))))
    (go (first r) (rest r))))

(def %cu-expr-cmp
  (fn (_ ts)
    (def r (%cu-expr-add ts))
    (def go
      (fn (self v xs)
        (if (null? xs) (pair v xs)
          (if (not (%cu-expr-cmp-op? (first xs))) (pair v xs)
            (let ((r2 (%cu-expr-add (rest xs))))
              (self (%cu-expr-compare (first xs) v (first r2))
                (rest r2)))))))
    (go (first r) (rest r))))

(def %cu-expr-add
  (fn (_ ts)
    (def r (%cu-expr-mul ts))
    (def go
      (fn (self v xs)
        (if (null? xs) (pair v xs)
          (if (not (if (string=? (first xs) "+") #t
                     (string=? (first xs) "-")))
            (pair v xs)
            (let ((r2 (%cu-expr-mul (rest xs))))
              (self (%cu-expr-arith (first xs) v (first r2))
                (rest r2)))))))
    (go (first r) (rest r))))

(def %cu-expr-mul
  (fn (_ ts)
    (def r (%cu-expr-match ts))
    (def go
      (fn (self v xs)
        (if (null? xs) (pair v xs)
          (if (not (if (string=? (first xs) "*") #t
                     (if (string=? (first xs) "/") #t
                       (string=? (first xs) "%"))))
            (pair v xs)
            (let ((r2 (%cu-expr-match (rest xs))))
              (self (%cu-expr-arith (first xs) v (first r2))
                (rest r2)))))))
    (go (first r) (rest r))))

(def %cu-expr-match
  (fn (_ ts)
    (def r (%cu-expr-prim ts))
    (def go
      (fn (self v xs)
        (if (null? xs) (pair v xs)
          (if (not (string=? (first xs) ":")) (pair v xs)
            (let ((r2 (%cu-expr-prim (rest xs))))
              (self (%cu-expr-colon v (first r2)) (rest r2)))))))
    (go (first r) (rest r))))

; the named operators, the parenthesised group, and the bare word
(def %cu-expr-prim
  (fn (_ ts)
    (if (null? ts) (pair "" ())
      (let ((t (first ts)))
        (if (string=? t "(") (%cu-expr-group (rest ts))
          (if (string=? t "length")
            (let ((r (%cu-expr-prim (rest ts))))
              (pair (%cu-int->str (byte-len (first r))) (rest r)))
            (if (string=? t "match") (%cu-expr-match-op (rest ts))
              (if (string=? t "substr") (%cu-expr-substr (rest ts))
                (if (string=? t "index") (%cu-expr-index (rest ts))
                  (pair t (rest ts)))))))))))

(def %cu-expr-group
  (fn (_ ts)
    (def r (%cu-expr-or ts))
    (if (null? (rest r)) r
      (if (string=? (first (rest r)) ")")
        (pair (first r) (rest (rest r)))
        r))))

(def %cu-expr-match-op
  (fn (_ ts)
    (def a (%cu-expr-prim ts))
    (def b (%cu-expr-prim (rest a)))
    (pair (%cu-expr-colon (first a) (first b)) (rest b))))

; substr is 1-BASED, and any position or length out of range answers ""
(def %cu-expr-substr
  (fn (_ ts)
    (def s (%cu-expr-prim ts))
    (def p (%cu-expr-prim (rest s)))
    (def n (%cu-expr-prim (rest p)))
    (def str (first s))
    (def pos (%cu-expr-int (first p)))
    (def len (%cu-expr-int (first n)))
    (def end (byte-len str))
    (def from (- pos 1))
    (def stop (let ((e (+ from len))) (if (> e end) end e)))
    (pair
      (if (if (< from 0) #t (if (>= from end) #t (< len 1))) ""
        (substring str from stop))
      (rest n))))

; index answers the 1-based position of the first byte of S found in
; CHARS, and 0 when none is
(def %cu-expr-index
  (fn (_ ts)
    (def s (%cu-expr-prim ts))
    (def c (%cu-expr-prim (rest s)))
    (def str (first s))
    (def set (first c))
    (def end (byte-len str))
    (def has?
      (fn (_ b)
        (let ((go (fn (self j)
                    (if (>= j (byte-len set)) #f
                      (if (= (byte-at set j) b) #t (self (+ j 1)))))))
          (go 0))))
    (def go
      (fn (self i)
        (if (>= i end) 0
          (if (has? (byte-at str i)) (+ i 1) (self (+ i 1))))))
    (pair (%cu-int->str (go 0)) (rest c))))

(def %cu-expr
  (fn (_ argv stdin-thunk)
    (if (null? argv)
      (do (file-write 2 "expr: missing operand\n") 2)
      (let ((r (%cu-expr-or argv)))
        (do (display (string-append (first r) "\n"))
            (if (%cu-expr-true? (first r)) 0 1))))))
