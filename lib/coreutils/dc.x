; # x-coreutils -- the small tools, as applets
;
; ## lib/coreutils/dc.x -- dc
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

(module coreutils/dc)

(import coreutils/bcnum bn-add bn-big% bn-big- bn-big/ bn-big< bn-big= bn-cmp
  bn-col bn-col! bn-digits bn-div bn-divmod bn-emit! bn-flush! bn-line-len
  bn-max bn-modexp bn-mul bn-neg? bn-newline! bn-nul! bn-parse bn-pow
  bn-print-in! bn-print-num! bn-print-str! bn-rem bn-sqrt bn-start! bn-sub
  bn-ten bn-ulong bn-zero?)
(import coreutils/cli cu-opts)
(import coreutils/dump dp-find)
(import coreutils/prims byte-at byte-len cu-err-label cu-int->str cu-nthrest
  cu-sweep-lines cu-sweep-tick! file-err-text file-write filter length map
  reverse string-append string=? substring vec-build vec-ref vec-set!)
(import coreutils/text cu-pieces cu-run-text)

(def %dc-die (fn (_ msg) (Err raise (lit dc) msg ())))


; --- the machine's state ---------------------------------------------------------
;
; In a vector: the stack (top first), the registers ((NAME . VALUES) each, top
; first), the arrays ((NAME . ((INDEX . VALUE) ...)) each), the scale, the input
; and output bases, -x, how many frames run (the main one is 1), the file
; read and the line in it, the reader of standard input.
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
        (let ((n (bn-parse (%dc-val it) (%dg 4))))
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
      (let ((e (if (pair? a) (filter (fn (_ c) (bn-big= (first c) idx)) (rest (first a))) ())))
        (if (pair? e) (rest (first e)) (pair 0 0))))))

(def %dc-elem-set!
  (fn (_ name idx n)
    (let ((a (filter (fn (_ r) (string=? (first r) name)) (%dg 2))))
      (let ((cells (if (pair? a) (filter (fn (_ c) (not (bn-big= (first c) idx))) (rest (first a))) ())))
        (%dg! 2 (pair (pair name (pair (pair idx n) cells))
                      (filter (fn (_ r) (not (string=? (first r) name))) (%dg 2))))))))

; an item as a register holds it: a number or a string, never a reference
(def %dc-held
  (fn (_ it) (if (eq? (%dc-kind it) (lit str)) it (%dc-numi (%dc-num! it)))))

; --- printing ------------------------------------------------------------------------
;
; What is printed goes to bc's writer, written at the end of the command.

; IT printed as p prints it: a string's escapes made, an empty one a NUL
(def %dc-print-item!
  (fn (_ it)
    (let ((n (%dc-num-of it)))
      (if (eq? n #f)
        (do (if (= (byte-len (%dc-val it)) 0) (bn-nul!) (bn-print-str! (%dc-val it))) (bn-emit! "\n"))
        (bn-print-num! n (%dg 5) #t)))))

; P: a string as it is, a number as bytes of base 256
(def %dc-stream!
  (fn (_ it)
    (let ((n (%dc-num-of it)))
      (match
        ((eq? n #f) (bn-emit! (%dc-val it)))
        ((bn-zero? n) (bn-nul!))
        ((bn-neg? n) (%dc-die "negative number"))
        (#t (bn-print-in! n 256
              (fn (_ d radix) (do (if (= d 0) (bn-nul!) (bn-emit! (bytes->str (list d))))
                                  (bn-col! (+ (bn-col) 1))))))))))

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
(def %dc-numch? (fn (_ c) (if (Char numeric? c) #t (if (>= c #\A) (<= c #\F) #f))))

; the characters dc reads as commands on their own
(def %dc-ops "%(*+-/:;<=>?GIKLNOPQRSXZ^_acdefiklnopqrsvxz{|~")

; The next token from SRC: (lit eof), (lit nl), (num TEXT), (str TEXT),
; (ch TEXT) or, where REG, (name TEXT) -- the register a command names.
(def %dcl-next
  (fn (self src reg)
    (do (%dg! 9 (vec-ref src 2))
        (if (= (%dcl-peek src 0) 0) (list (lit eof))
          (do (vec-set! src 4 (%dcl-rest src))
              (if reg (%dcl-reg src)
                (let ((t (%dcl-token src)))
                  (if (eq? (first t) (lit space)) (self src #f) t))))))))

; a register's name: one character, any at all, or under -x after blanks a word
(def %dcl-reg
  (fn (_ src)
    (if (if (%dg 6) (%dc-space? (%dcl-peek src 0)) #f)
      (do (let go () (if (if (%dc-space? (%dcl-peek src 0)) (not (= (%dcl-peek src 0) #\newline)) #f)
                       (do (%dcl-skip! src 1) (go)) ()))
          (list (lit name)
                (let go ((acc ()))
                  (let ((c (%dcl-peek src 0)))
                    (if (if (if (>= c #\a) (<= c #\z) #f) #t (if (Char numeric? c) #t (= c #\_)))
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
      ((= c #\.) (if (Char numeric? (%dcl-peek src 0)) (%dcl-number src c) (%dc-bad-char c)))
      ((%dc-numch? c) (%dcl-number src c))
      ((= c #\[) (%dcl-string src))
      ((if (> c 0) (>= (dp-find %dc-ops 0 c) 0) #f) (list (lit ch) (bytes->str (list c))))
      (#t (%dc-bad-char c)))))

(def %dc-bad-char
  (fn (_ c) (if (= c 0) (%dc-die "NUL character") (%dc-die (%str-concat (list "bad character '" (bytes->str (list c)) "'"))))))

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
  (fn (_ src) (%dc-die (%str-concat (list "bad token at '" (vec-ref src 4) "'")))))

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
    (let ((c (bn-cmp a b)))
      (match
        ((string=? op "=") (= c 0)) ((string=? op "G") (= c 0)) ((string=? op "!=") (not (= c 0)))
        ((string=? op ">") (< c 0)) ((string=? op "<") (> c 0)) ((string=? op "(") (> c 0))
        ((string=? op "!<") (<= c 0)) ((string=? op "!>") (>= c 0)) ((string=? op "{") (>= c 0))
        (#t #f)))))

; Z: how many digits a number has, as xc_program_len counts them
(def %dc-len
  (fn (_ n)
    (if (bn-zero? n) 1
      (let ((d (bn-digits (first n))))
        (let ((l (bn-max d (rest n))))
          (if (= l (rest n)) d l))))))

; the string run as a macro, a frame deeper: how many frames are left after
(def %dc-run-macro
  (fn (_ text)
    (def cmds (%dcp-all (%dcl-make text ())))
    (do (%dg! 7 (+ (%dg 7) 1))
        (let ((u (%dc-run-all cmds)))
          (do (%dg! 7 (- (%dg 7) 1))
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
        (let ((n (bn-parse (first (rest cmd)) (%dg 4))))
          (do (%dc-push! (%dc-numi (pair (bn-big- 0 (first n)) (rest n)))) 0)))
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
          (let ((yes (not (bn-zero? (%dc-num! (first (%dg 0)))))))
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
      ((string=? c "+") (do (%dc-binop! (fn (_ a b k) (bn-add a b))) 0))
      ((string=? c "-") (do (%dc-binop! (fn (_ a b k) (bn-sub a b))) 0))
      ((string=? c "*") (do (%dc-binop! bn-mul) 0))
      ((string=? c "/") (do (%dc-binop! bn-div) 0))
      ((string=? c "%") (do (%dc-binop! bn-rem) 0))
      ((string=? c "^") (do (%dc-binop! bn-pow) 0))
      ((string=? c "~")
        (let ((ab (%dc-two)))
          (let ((qr (bn-divmod (first ab) (rest ab) (%dg 3))))
            (do (%dc-replace! 2 (%dc-numi (first qr))) (%dc-push! (%dc-numi (rest qr))) 0))))
      ((string=? c "|")
        (do (%dc-need 3)
            (let ((ab (%dc-two)) (a0 (%dc-num! (first (rest (rest (%dg 0)))))))
              (do (%dc-replace! 3 (%dc-numi (bn-modexp a0 (first ab) (rest ab)))) 0))))
      ((pair? (filter (fn (_ o) (string=? o c)) (list "(" "{" "G")))
        (let ((ab (%dc-two))) (do (%dc-replace! 2 (%dc-bool (%dc-rel c (first ab) (rest ab)))) 0)))
      (#t (%dc-op1 c)))))

(def %dc-op1
  (fn (_ c)
    (match
      ((string=? c "v") (do (%dc-need 1) (%dc-replace! 1 (%dc-numi (bn-sqrt (%dc-num! (first (%dg 0))) (%dg 3)))) 0))
      ((string=? c "N") (do (%dc-need 1) (%dc-replace! 1 (%dc-bool (bn-zero? (%dc-num! (first (%dg 0)))))) 0))
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
      ((string=? c "q") (if (<= (%dg 7) 2) (%dc-quit) 2))
      ((string=? c "Q")
        (let ((n (bn-ulong (%dc-num! (do (%dc-need 1) (first (%dg 0)))))))
          (do (%dc-pop!)
              (match ((bn-big< (%dg 7) n) (%dc-few))
                     ((bn-big= (%dg 7) n) (%dc-quit))
                     (#t n)))))
      (#t 0))))

; a: a number's low byte, or a string's first, as a string of one
(def %dc-ascii
  (fn (_ it)
    (let ((n (%dc-num-of it)))
      (if (eq? n #f)
        (let ((s (%dc-val it))) (if (= (byte-len s) 0) "" (substring s 0 1)))
        (let ((b (bn-ulong (pair (bn-big% (bn-big/ (first n) (bn-ten (rest n))) 256) 0))))
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
(def %dc-index (fn (_ it) (bn-ulong (%dc-num! it))))

; i k o: the top popped and made the input base, the scale or the output base
(def %dc-setg
  (fn (_ c)
    (do (%dc-need 1)
        (let ((it (first (%dg 0))))
          (do (if (eq? (%dc-kind it) (lit str)) (%dc-die "variable is wrong type") ())
              (let ((v (bn-ulong (%dc-num! it))))
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
    (if (null? (%dg 10)) (%dg! 10 (%dcl-make "" (%dc-more (cu-pieces "-" %dc-stdin-thunk)))) ())
    (%dg 10)))

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
              (bn-flush!)
              (cu-sweep-tick! cu-sweep-lines)
              (go (rest r))))))))

; FILE's commands run, its name and line before an error's words
(def %dc-file
  (fn (_ file)
    (let ((p (cu-pieces file ())))
      (if (Err err? p) (%dc-die (%str-concat (list "can't open '" file "': " (file-err-text p))))
        (do (%dg! 8 file) (%dc-process (%dcl-make "" (%dc-more p))) (p (lit close)) (%dg! 8 ()))))))

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
    (do (set! %dc (vec-build 11 (fn (_ i) (match ((= i 3) 0) ((= i 4) 10) ((= i 5) 10)
                                                ((= i 6) (Opts on? o "-x")) ((= i 7) 1) ((= i 9) 1) (#t ())))))
        (bn-start! (lit dc) (bn-line-len "DC_LINE_LENGTH" #f))
        (set! %dc-stdin-thunk stdin-thunk)
        (guard (e (do (bn-flush!)
                      (match
                        ((eq? (cu-err-label e) (lit dc-quit)) 0)
                        ((eq? (cu-err-label e) (lit dc))
                          (do (file-write 2 (%str-concat (list "dc: " (if (null? (%dg 8)) ""
                                                                           (%str-concat (list (%dg 8) ":" (cu-int->str (%dg 9)) ": ")))
                                                                 (e msg) "\n")))
                              1))
                        (#t (error e)))))
          (let ((scripts (%dc-scripts argv)) (files (Opts operands o)))
            (do (map (fn (_ s) (if (= (first s) #\e) (%dc-process (%dcl-make (rest s) ())) (%dc-file (rest s)))) scripts)
                (map %dc-file files)
                (if (if (null? scripts) (null? files) #f) (%dc-process (%dc-stdin)) ())
                0))))))

(provide coreutils/dc cu-dc)
