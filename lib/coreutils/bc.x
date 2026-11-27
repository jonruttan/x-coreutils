; # x-coreutils -- the small tools, as applets
;
; ## lib/coreutils/bc.x -- bc
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's bc (miscutils/bc.c), the arbitrary-precision calculator language,
; on the numbers it shares with dc (coreutils/bcnum).  As busybox does: the
; program is read a statement at a time, each turned to instructions and run
; before the next is read; input is read a line at a time, so a statement
; that fails stops what comes after it but not what came before; a number
; is read in the input base current when it is used; variables are dynamic,
; a function's parameters and autos pushed over the caller's and popped on
; return; && and || evaluate both sides; quit ends bc as it is read, halt as
; it runs; limits prints as it is read.  An error, or a POSIX warning made
; an error by -s, is said under the file's name and line where a file is
; read and ends bc with status 1.  -w says the warnings and goes on.
;
; Standard input is read as a program, not a terminal: there is no banner
; and no recovery from an error at a prompt.  continue outside a loop,
; which busybox crashes on, is a bad token.

(module coreutils/bc)

(import coreutils/bcnum bn-add bn-big* bn-big- bn-big< bn-cmp bn-col bn-col!
  bn-digits bn-div bn-emit! bn-flush! bn-line-len bn-max bn-mul bn-parse bn-pow
  bn-print-num! bn-print-str! bn-rem bn-sqrt bn-start! bn-sub bn-ulong bn-zero?)
(import coreutils/cli cu-opts)
(import coreutils/dump dp-find)
(import coreutils/prims append byte-at byte-len cu-err-label cu-hexs cu-int->str
  cu-sweep-at cu-sweep-lines cu-sweep-steps cu-sweep-tick! file-err-text
  file-write length map reverse string-append string=? substring sys-getenv
  vec-build vec-make vec-ref vec-set!)
(import coreutils/text cu-pad-zero cu-pieces cu-run-text)

; --- growing vectors -------------------------------------------------------------
;
; In a vector: the items' vector, how many are held, how many it has room for.

(def %gv-new
  (fn (_) (let ((g (vec-make 3 0))) (do (vec-set! g 0 (vec-make 8 ())) (vec-set! g 2 8) g))))

(def %gv-len (fn (_ g) (vec-ref g 1)))
(def %gv-ref (fn (_ g i) (vec-ref (vec-ref g 0) i)))
(def %gv-set! (fn (_ g i v) (vec-set! (vec-ref g 0) i v)))

; V put at the end of G: its index
(def %gv-push!
  (fn (_ g v)
    (def n (vec-ref g 1))
    (do (if (= n (vec-ref g 2)) (%gv-room! g (* n 2)) ())
        (vec-set! (vec-ref g 0) n v)
        (vec-set! g 1 (+ n 1))
        n)))

(def %gv-room!
  (fn (_ g cap)
    (let ((new (vec-make cap ())) (old (vec-ref g 0)))
      (do (let go ((i 0)) (if (< i (vec-ref g 1)) (do (vec-set! new i (vec-ref old i)) (go (+ i 1))) ()))
          (vec-set! g 0 new)
          (vec-set! g 2 cap)))))

(def %gv-clear! (fn (_ g) (do (vec-set! g 0 (vec-make 8 ())) (vec-set! g 1 0) (vec-set! g 2 8))))

(def %gv-copy
  (fn (_ g)
    (let ((c (%gv-new)))
      (do (let go ((i 0)) (if (< i (%gv-len g)) (do (%gv-push! c (%gv-ref g i)) (go (+ i 1))) ())) c))))

(def %bc-in? (fn (self x l) (if (null? l) #f (if (eq? x (first l)) #t (self x (rest l))))))

; --- the machine's state ---------------------------------------------------------
;
; In a vector: the results stack (top first), the frames run (top first, a
; frame a vector of its function's index and where in its code), the
; functions, the names of the functions ((NAME . INDEX) each), the
; variables (a stack of numbers each, top first), their names, the arrays (a
; stack of arrays each), their names, the scale, the input and output bases,
; last, POSIX's check (nil, (lit w) or (lit s)), the reader of standard
; input's lines, the line an error names.
;
; A function, in a vector: its name, how many parameters, its parameters and
; autos ((NAME TYPE ID) each, in order; TYPE (lit var), (lit array) or (lit
; ref)), its code, its labels (where in the code each jump goes), whether it
; is void.  The main program is function 0, read()'s function 1.

(def %bc ())
(def %bg (fn (_ i) (vec-ref %bc i)))
(def %bg! (fn (_ i v) (vec-set! %bc i v)))

(def %bc-zero (pair 0 0))

(def %bc-die (fn (_ msg) (Err raise (lit bc) msg ())))
(def %bc-quit (fn (_) (Err raise (lit bc-quit) "" ())))
(def %bc-few (fn (_) (%bc-die "stack has too few elements")))
(def %bc-wrong (fn (_) (%bc-die "variable is wrong type")))

(def %bc-func-new
  (fn (_ name)
    (vec-build 6 (fn (_ i) (match ((= i 0) name) ((= i 1) 0) ((= i 3) (%gv-new)) ((= i 4) (%gv-new)) ((= i 5) #f) (#t ()))))))

(def %bc-func (fn (_ i) (%gv-ref (%bg 2) i)))

(def %bc-find
  (fn (self alist name) (match ((null? alist) -1) ((string=? (first (first alist)) name) (rest (first alist))) (#t (self (rest alist) name)))))

; NAME's function, made empty where it is already defined: its index
(def %bc-func-add!
  (fn (_ name)
    (let ((i (%bc-find (%bg 3) name)))
      (if (>= i 0) (do (%gv-set! (%bg 2) i (%bc-func-new name)) i)
        (let ((n (%gv-push! (%bg 2) (%bc-func-new name))))
          (do (%bg! 3 (pair (pair name n) (%bg 3))) n))))))

; NAME's variable or array, made where it is new: its index
(def %bc-var-id (fn (_ name) (%bc-id name 4 5 (fn (_) (list %bc-zero)))))
(def %bc-arr-id (fn (_ name) (%bc-id name 6 7 (fn (_) (list (%gv-new))))))

(def %bc-id
  (fn (_ name slots names fresh)
    (let ((i (%bc-find (%bg names) name)))
      (if (>= i 0) i
        (let ((n (%gv-push! (%bg slots) (fresh))))
          (do (%bg! names (pair (pair name n) (%bg names))) n))))))

; --- the writer's errors and warnings ------------------------------------------------

; the parser's state, in a vector: the line being read, where in it, the
; line's number, a thunk for the next line (nil for none), the token, the
; token before it, the token's text, where in the line the token began (nil
; before the first), the function code goes to, the operators waiting, the
; loops' exits and their continues, how deep in a function definition, the
; file read (nil for none)
(def %bp ())
(def %pg (fn (_ i) (vec-ref %bp i)))
(def %pg! (fn (_ i v) (vec-set! %bp i v)))

(def %bp-new
  (fn (_ text more file line)
    (vec-build 14 (fn (_ i) (match ((= i 0) text) ((= i 1) 0) ((= i 2) line) ((= i 3) more) ((= i 4) (lit invalid))
                                   ((= i 5) (lit invalid)) ((= i 6) "") ((= i 8) 0) ((= i 12) 0) ((= i 13) file) (#t ()))))))

; the text from where the token began to its line's end, nil before a token
(def %bc-at-text
  (fn (_)
    (let ((at (%pg 7)) (text (%pg 0)))
      (if (null? at) ()
        (let ((nl (dp-find text at #\newline)))
          (substring text at (if (< nl 0) (byte-len text) nl)))))))

; bc_error_at: the error, and the text it was met at
(def %bc-die-at
  (fn (_ msg) (let ((t (%bc-at-text))) (%bc-die (if (null? t) msg (%str-concat (list msg " at '" t "'")))))))

(def %bc-bad-token (fn (_) (%bc-die-at "bad token")))
(def %bc-bad-expr (fn (_) (%bc-die-at "bad expression")))
(def %bc-bad-assign (fn (_) (%bc-die-at "bad assignment: left side must be variable or array element")))
(def %bc-bad-def (fn (_) (%bc-die-at "bad function definition")))

; what goes before a message: the file and line where a file is read
(def %bc-where
  (fn (_) (if (null? (%pg 13)) "" (%str-concat (list (%pg 13) ":" (cu-int->str (%bg 14)) ": ")))))

(def %bc-say (fn (_ msg) (do (bn-flush!) (file-write 2 (%str-concat (list "bc: " (%bc-where) msg "\n"))))))

; a construct POSIX does not have: nothing, said under -w, an error under -s
(def %bc-posix
  (fn (_ msg)
    (match ((null? (%bg 12)) ()) ((eq? (%bg 12) (lit s)) (%bc-die msg)) (#t (%bc-say msg)))))

(def %bc-not-allow (fn (_ what) (%bc-posix (string-append "POSIX does not allow " what))))
(def %bc-requires (fn (_ what) (%bc-posix (string-append "POSIX requires " what))))

; --- lines ---------------------------------------------------------------------------
;
; A thunk for SRC's pieces a line at a time, nil at the end, as xc_read_line
; reads them: a NUL dropped, any other byte below a space but a tab, return
; or newline, or past ~, an error.

(def %bc-lines
  (fn (_ src)
    (def st (vec-make 3 #f))
    (do (vec-set! st 0 "") (vec-set! st 1 0)
        (fn (_)
          (let go ()
            (let ((text (vec-ref st 0)) (pos (vec-ref st 1)))
              (let ((nl (dp-find text pos #\newline)))
                (match
                  ((>= nl 0) (do (vec-set! st 1 (+ nl 1)) (%bc-clean (substring text pos (+ nl 1)))))
                  ((vec-ref st 2)
                    (if (>= pos (byte-len text)) () (do (vec-set! st 1 (byte-len text)) (%bc-clean (substring text pos (byte-len text))))))
                  (#t (let ((p (src)))
                        (do (if (if (Err err? p) #t (= (rest p) 0)) (vec-set! st 2 #t)
                              (do (vec-set! st 0 (string-append (substring text pos (byte-len text)) (cu-run-text p)))
                                  (vec-set! st 1 0)))
                            (go))))))))))))

(def %bc-clean
  (fn (_ line)
    (let go ((i 0) (nul #f))
      (if (>= i (byte-len line)) (if nul (%bc-drop-nul line) line)
        (let ((c (byte-at line i)))
          (match
            ((= c 0) (go (+ i 1) #t))
            ((if (< c 32) (not (if (= c 9) #t (if (= c 10) #t (= c 13)))) (> c 126))
              (%bc-die (string-append "illegal character 0x" (cu-pad-zero (cu-hexs c) 2))))
            (#t (go (+ i 1) nul))))))))

(def %bc-drop-nul
  (fn (_ s)
    (let go ((i 0) (acc ()))
      (let ((z (dp-find s i 0)))
        (if (< z 0) (%str-concat (reverse (pair (substring s i (byte-len s)) acc)))
          (go (+ z 1) (pair (substring s i z) acc)))))))

; --- the lexer -----------------------------------------------------------------------

; the byte where the parser is, the next line read where the line is done
(def %bl-peek
  (fn (_)
    (if (< (%pg 1) (byte-len (%pg 0))) (byte-at (%pg 0) (%pg 1))
      (if (null? (%pg 3)) 0
        (let ((line ((%pg 3))))
          (do (%pg! 0 (if (null? line) "" line)) (%pg! 1 0) (%pg! 7 0)
              (if (null? line) (%pg! 3 ()) ())
              (%bl-at 0)))))))

; the byte K on from where the parser is, in the line read; 0 past it
(def %bl-at (fn (_ k) (let ((i (+ (%pg 1) k))) (if (< i (byte-len (%pg 0))) (byte-at (%pg 0) i) 0))))

(def %bl-skip! (fn (_ n) (%pg! 1 (+ (%pg 1) n))))
(def %bl-eat (fn (_) (let ((c (%bl-peek))) (do (if (= c 0) () (%bl-skip! 1)) c))))
(def %bl-set! (fn (_ t) (%pg! 4 t)))
(def %bl-is? (fn (_ t) (eq? (%pg 4) t)))
(def %bl-line! (fn (_) (%pg! 2 (+ (%pg 2) 1))))

(def %bl-upper? (fn (_ c) (if (>= c #\A) (<= c #\Z) #f)))
(def %bl-lower? (fn (_ c) (if (>= c #\a) (<= c #\z) #f)))
(def %bl-name-ch? (fn (_ c) (if (%bl-lower? c) #t (if (Char numeric? c) #t (= c #\_)))))
(def %bl-space? (fn (_ c) (if (= c 32) #t (if (>= c 9) (<= c 13) #f))))

; zxc_lex_next: the next token that is not white space or a comment
(def %bl-next
  (fn (_)
    (do (%bg! 14 (%pg 2))
        (%pg! 5 (%pg 4))
        (let go ()
          (if (if (= (%bl-at 0) 0) (do (%bl-set! (lit eof)) (= (%bl-peek) 0)) #f) ()
            (do (%pg! 7 (%pg 1))
                (%bl-token)
                (if (%bl-is? (lit ws)) (go) ())))))))

; the token with the = after it, or without
(def %bl-eq
  (fn (_ with without) (if (= (%bl-at 0) #\=) (do (%bl-skip! 1) (%bl-set! with)) (%bl-set! without))))

(def %bl-bad
  (fn (_ c) (%bc-die (%str-concat (list "bad character '" (bytes->str (list c)) "'")))))

(def %bl-bool (fn (_ text) (%bc-not-allow (string-append "boolean operators; this is bad: " text))))

; && or ||, a single & or | a bad character
(def %bl-double
  (fn (_ c tok text)
    (if (= (%bl-at 0) c) (do (%bl-bool text) (%bl-skip! 1) (%bl-set! tok))
      (do (%bl-set! (lit invalid)) (%bl-bad c)))))

(def %bl-token
  (fn (_)
    (def c (%bl-eat))
    (match
      ((= c 10) (do (%bl-line!) (%bl-set! (lit nl))))
      ((%bl-space? c) (%bl-white))
      ((= c #\!) (do (%bl-eq (lit ne) (lit not)) (if (%bl-is? (lit not)) (%bl-bool "!") ())))
      ((= c 34) (%bl-string))
      ((= c #\#) (do (%bc-not-allow "'#' script comments") (%bl-comment-line)))
      ((= c 37) (%bl-eq (lit amod) (lit mod)))
      ((= c 38) (%bl-double c (lit and) "&&"))
      ((= c 40) (%bl-set! (lit lparen)))
      ((= c 41) (%bl-set! (lit rparen)))
      ((= c 42) (%bl-eq (lit amul) (lit mul)))
      ((= c 43) (if (= (%bl-at 0) 43) (do (%bl-skip! 1) (%bl-set! (lit inc))) (%bl-eq (lit aplus) (lit plus))))
      ((= c 44) (%bl-set! (lit comma)))
      ((= c 45) (if (= (%bl-at 0) 45) (do (%bl-skip! 1) (%bl-set! (lit dec))) (%bl-eq (lit aminus) (lit minus))))
      ((= c #\.) (if (Char numeric? (%bl-at 0)) (%bl-number c) (do (%bl-set! (lit klast)) (%bc-not-allow "'.' as 'last'"))))
      ((= c 47) (if (= (%bl-at 0) 42) (%bl-comment) (%bl-eq (lit adiv) (lit div))))
      ((if (Char numeric? c) #t (%bl-upper? c)) (%bl-number c))
      ((= c 59) (%bl-set! (lit scolon)))
      ((= c #\<) (%bl-eq (lit le) (lit lt)))
      ((= c #\=) (%bl-eq (lit eq) (lit assign)))
      ((= c #\>) (%bl-eq (lit ge) (lit gt)))
      ((= c #\[) (%bl-set! (lit lbracket)))
      ((= c #\]) (%bl-set! (lit rbracket)))
      ((= c #\\) (if (= (%bl-at 0) 10) (do (%bl-set! (lit ws)) (%bl-skip! 1)) (%bl-bad c)))
      ((= c 94) (%bl-eq (lit apow) (lit pow)))
      ((%bl-lower? c) (%bl-ident))
      ((= c 123) (%bl-set! (lit lbrace)))
      ((= c 125) (%bl-set! (lit rbrace)))
      ((= c 124) (%bl-double c (lit or) "||"))
      (#t (do (%bl-set! (lit invalid)) (%bl-bad c))))))

(def %bl-white
  (fn (_)
    (do (%bl-set! (lit ws))
        (let go () (let ((c (%bl-at 0))) (if (if (= c 10) #f (%bl-space? c)) (do (%bl-skip! 1) (go)) ()))))))

(def %bl-comment-line
  (fn (_)
    (do (%bl-set! (lit ws))
        (let go () (let ((c (%bl-at 0))) (if (if (= c 10) #f (not (= c 0))) (do (%bl-skip! 1) (go)) ()))))))

; /* to */, across lines; the parser is at the *
(def %bl-comment
  (fn (_)
    (do (%bl-set! (lit ws))
        (let go ()
          (do (%bl-skip! 1)
              (let star ((c (%bl-peek)))
                (match
                  ((= c 42) (do (%bl-skip! 1) (let ((c2 (%bl-at 0))) (if (= c2 47) (do (%bl-skip! 1) (%bg! 14 (%pg 2))) (star c2)))))
                  ((= c 0) (%bc-die "unterminated comment"))
                  (#t (do (if (= c 10) (%bl-line!) ()) (go))))))))))

; a number's text from its first character C: digits, A to Z, one point, a
; backslash and newline passed over; a point at its end dropped
(def %bl-number
  (fn (_ c0)
    (do (%bl-set! (lit num))
        (let go ((acc (list c0)) (pt (= c0 #\.)) (last c0))
          (let ((c (%bl-at 0)))
            (match
              ((if (= c #\\) (= (%bl-at 1) 10) #f) (do (%bl-skip! 2) (%bl-line!) (%bl-peek) (go acc pt last)))
              ((if (Char numeric? c) #t (%bl-upper? c)) (do (%bl-skip! 1) (go (pair c acc) pt c)))
              ((if (= c #\.) (not pt) #f) (do (%bl-skip! 1) (go (pair c acc) #t c)))
              (#t (do (%pg! 6 (bytes->str (reverse (if (= last #\.) (rest acc) acc))))
                      (%bg! 14 (%pg 2))))))))))

; a string's text up to its closing quote, across lines
(def %bl-string
  (fn (_)
    (do (%bl-set! (lit str))
        (let go ((acc ()))
          (let ((c (%bl-peek)))
            (match
              ((= c 0) (%bc-die "unterminated string"))
              ((= c 34) (do (%pg! 6 (bytes->str (reverse acc))) (%bl-skip! 1) (%bg! 14 (%pg 2))))
              (#t (do (if (= c 10) (%bl-line!) ()) (%bl-skip! 1) (go (pair c acc))))))))))

; the keywords: (TEXT TOKEN POSIX'S)
(def %bc-keywords
  (list (list "auto" (lit kauto) #t) (list "break" (lit kbreak) #t) (list "continue" (lit kcontinue) #f)
        (list "define" (lit kdefine) #t) (list "else" (lit kelse) #f) (list "for" (lit kfor) #t)
        (list "halt" (lit khalt) #f) (list "ibase" (lit kibase) #t) (list "obase" (lit kobase) #t)
        (list "if" (lit kif) #t) (list "last" (lit klast) #f) (list "length" (lit klength) #t)
        (list "limits" (lit klimits) #f) (list "print" (lit kprint) #f) (list "quit" (lit kquit) #t)
        (list "read" (lit kread) #f) (list "return" (lit kreturn) #t) (list "scale" (lit kscale) #t)
        (list "sqrt" (lit ksqrt) #t) (list "while" (lit kwhile) #t)))

(def %bc-keyword
  (fn (self ks w) (match ((null? ks) ()) ((string=? (first (first ks)) w) (first ks)) (#t (self (rest ks) w)))))

; a keyword, or a name: a keyword's letters with a capital after them are a
; name and a number, as zbc_lex_identifier reads them
(def %bl-ident
  (fn (_)
    (def text (%pg 0))
    (def start (- (%pg 1) 1))
    (def end (let go ((i start)) (if (if (< i (byte-len text)) (%bl-name-ch? (byte-at text i)) #f) (go (+ i 1)) i)))
    (def word (substring text start end))
    (def kw (if (if (< end (byte-len text)) (%bl-upper? (byte-at text end)) #f) () (%bc-keyword %bc-keywords word)))
    (do (%pg! 1 end)
        (if (pair? kw)
          (do (%bl-set! (first (rest kw)))
              (if (first (rest (rest kw))) () (%bc-not-allow (%str-concat (list "the '" word "' keyword")))))
          (do (%bl-set! (lit name))
              (%pg! 6 word)
              (if (> (byte-len word) 1)
                (let ((nl (dp-find text start #\newline)))
                  (%bc-posix (%str-concat (list "POSIX only allows one character names; this is bad: '"
                                                (substring text start (if (< nl 0) (byte-len text) nl)) "'"))))
                ()))))))

; --- code ---------------------------------------------------------------------------
;
; An instruction is (HANDLER . ARGUMENT); the machine calls the handler on
; the argument.

(def %bp-func (fn (_) (%bc-func (%pg 8))))
(def %bp-emit! (fn (_ h arg) (%gv-push! (vec-ref (%bp-func) 3) (pair h arg))))
(def %bp-label! (fn (_ v) (%gv-push! (vec-ref (%bp-func) 4) v)))
(def %bp-here (fn (_) (%gv-len (vec-ref (%bp-func) 3))))
(def %bp-relabel! (fn (_ i) (%gv-set! (vec-ref (%bp-func) 4) i (%bp-here))))

; --- the parser ----------------------------------------------------------------------
;
; The expression parser is busybox's: operators wait on a stack until one
; that binds less tightly comes, the instruction before (PREV) says whether
; what comes next is a leaf or an operator, and the flags say what the
; expression may hold -- (PRINT REL ARRAY NOCALL), as BC_PARSE_ has them.

(def %bf-none (list #f #f #f #f))
(def %bf-print (list #t #f #f #f))
(def %bf-rel (list #f #t #f #f))
(def %bf-print? (fn (_ f) (first f)))
(def %bf-rel? (fn (_ f) (first (rest f))))
(def %bf-array? (fn (_ f) (first (rest (rest f)))))
(def %bf-nocall? (fn (_ f) (first (rest (rest (rest f))))))
(def %bf-inner (fn (_ f) (list #f #f (%bf-array? f) (%bf-nocall? f))))
(def %bf-args (fn (_ f) (list #f #f #t (%bf-nocall? f))))
(def %bf-call (fn (_ f) (list (%bf-print? f) (%bf-rel? f) (%bf-array? f) #f)))
(def %bf-no-call (fn (_ f) (list (%bf-print? f) (%bf-rel? f) (%bf-array? f) #t)))

(def %bc-rel-ops (list (lit eq) (lit le) (lit ge) (lit ne) (lit lt) (lit gt)))
(def %bc-assign-ops (list (lit apow) (lit amul) (lit adiv) (lit amod) (lit aplus) (lit aminus) (lit assign)))
(def %bc-binary-ops
  (list (lit pow) (lit mul) (lit div) (lit mod) (lit plus) (lit eq) (lit le) (lit ge) (lit ne) (lit lt) (lit gt)
        (lit not) (lit or) (lit and)))
(def %bc-lvals (list (lit var) (lit elem) (lit scale) (lit ibase) (lit obase) (lit last)))
(def %bc-leaves
  (list (lit num) (lit var) (lit elem) (lit array) (lit scalefn) (lit ibase) (lit obase) (lit scale) (lit last)
        (lit length) (lit read) (lit sqrt) (lit incpost) (lit decpost)))

; the tokens an expression is read through, as lex_allowed_in_bc_expr has them
(def %bc-expr-toks
  (list (lit name) (lit num) (lit eq) (lit le) (lit ge) (lit ne) (lit lt) (lit gt) (lit pow) (lit mul) (lit div)
        (lit mod) (lit plus) (lit minus) (lit not) (lit or) (lit and) (lit apow) (lit amul) (lit adiv) (lit amod)
        (lit aplus) (lit aminus) (lit assign) (lit inc) (lit dec) (lit lparen) (lit rparen) (lit kibase)
        (lit kobase) (lit klast) (lit klength) (lit kread) (lit kscale) (lit ksqrt)))

; an operator's precedence, the lower the tighter, and whether it groups left
(def %bc-prec
  (fn (_ t)
    (match
      ((if (eq? t (lit neg)) #t (eq? t (lit not))) 1)
      ((eq? t (lit pow)) 2)
      ((%bc-in? t (list (lit mul) (lit div) (lit mod))) 3)
      ((if (eq? t (lit plus)) #t (eq? t (lit minus))) 4)
      ((%bc-in? t %bc-assign-ops) 5)
      ((%bc-in? t %bc-rel-ops) 6)
      ((if (eq? t (lit or)) #t (eq? t (lit and))) 7)
      (#t 0))))

(def %bc-left?
  (fn (_ t)
    (if (%bc-in? t %bc-rel-ops) #t
      (%bc-in? t (list (lit mul) (lit div) (lit mod) (lit plus) (lit minus) (lit or) (lit and))))))

; the handler of operator T
(def %bc-op-of
  (fn (_ t)
    (match
      ((eq? t (lit neg)) %bx-neg) ((eq? t (lit not)) %bx-not)
      ((eq? t (lit pow)) %bx-pow) ((eq? t (lit mul)) %bx-mul) ((eq? t (lit div)) %bx-div)
      ((eq? t (lit mod)) %bx-mod) ((eq? t (lit plus)) %bx-plus) ((eq? t (lit minus)) %bx-minus)
      ((eq? t (lit eq)) %bx-eq) ((eq? t (lit le)) %bx-le) ((eq? t (lit ge)) %bx-ge)
      ((eq? t (lit ne)) %bx-ne) ((eq? t (lit lt)) %bx-lt) ((eq? t (lit gt)) %bx-gt)
      ((eq? t (lit or)) %bx-or) ((eq? t (lit and)) %bx-and)
      ((eq? t (lit apow)) %bx-apow) ((eq? t (lit amul)) %bx-amul) ((eq? t (lit adiv)) %bx-adiv)
      ((eq? t (lit amod)) %bx-amod) ((eq? t (lit aplus)) %bx-aplus) ((eq? t (lit aminus)) %bx-aminus)
      (#t %bx-assign))))

(def %bp-op! (fn (_ t) (%bp-emit! (%bc-op-of t) ())))

(def %bp-ops (fn (_) (%pg 9)))
(def %bp-ops-len (fn (_) (length (%pg 9))))
(def %bp-push-op! (fn (_ t) (%pg! 9 (pair t (%pg 9)))))
(def %bp-pop-op! (fn (_) (%pg! 9 (rest (%pg 9)))))

; An expression's state, in a vector: PREV, and how many values it makes.
(def %ex-prev (fn (_ ex) (vec-ref ex 0)))
(def %ex-prev! (fn (_ ex v) (vec-set! ex 0 v)))
(def %ex-n+! (fn (_ ex k) (vec-set! ex 1 (+ (vec-ref ex 1) k))))
(def %ex-n- (fn (_ ex t) (if (if (eq? t (lit not)) #t (eq? t (lit neg))) () (%ex-n+! ex -1))))

; bc_parse_operator: the operators that bind as tightly or more, put out
(def %bp-operator
  (fn (_ ex t bgn)
    (def r (%bc-prec t))
    (def left (%bc-left? t))
    (do (let go ()
          (if (> (%bp-ops-len) bgn)
            (let ((top (first (%bp-ops))))
              (if (eq? top (lit lparen)) ()
                (let ((l (%bc-prec top)))
                  (if (if (>= l r) (if (not (= l r)) #t (not left)) #f) ()
                    (do (%bp-op! top) (%bp-pop-op!) (%ex-n- ex top) (go))))))
            ()))
        (%bp-push-op! t))))

(def %bp-right-paren
  (fn (_ ex bgn)
    (do (if (<= (%bp-ops-len) bgn) (%bc-bad-expr) ())
        (let go ()
          (let ((top (first (%bp-ops))))
            (if (eq? top (lit lparen)) (%bp-pop-op!)
              (do (%bp-op! top) (%bp-pop-op!) (%ex-n- ex top)
                  (if (<= (%bp-ops-len) bgn) (%bc-bad-expr) ())
                  (go))))))))

(def %bp-leaf? (fn (_ ex bin-last rprn) (if bin-last #f (if rprn #t (%bc-in? (%ex-prev ex) %bc-leaves)))))

; a leaf cannot follow a leaf
(def %bp-no-leaf (fn (_ ex bin-last rprn) (if (%bp-leaf? ex bin-last rprn) (%bc-bad-expr) ())))

; a binary or assignment operator: what may come before it checked, then
; the operators it outranks put out
(def %bp-binary
  (fn (_ ex t bgn bin-last)
    (do (if (%bc-in? t %bc-assign-ops) (if (%bc-in? (%ex-prev ex) %bc-lvals) () (%bc-bad-assign)) ())
        (if (eq? t (lit not))
          (if (if bin-last #f (not (eq? (%pg 5) (lit not)))) (%bc-bad-expr) ())
          (if (eq? (%ex-prev ex) (lit not)) (%bc-bad-expr) ()))
        (%ex-prev! ex t)
        (%bp-operator ex t bgn)
        (%bl-next))))

; a ) cannot follow an operator or !
(def %bp-closing
  (fn (_ ex bin-last) (if (if bin-last #t (eq? (%ex-prev ex) (lit not))) (%bc-bad-expr) ())))

; the leaves one token makes: a number, ibase obase last, length sqrt, read
(def %bc-leaf-toks
  (list (lit num) (lit kibase) (lit kobase) (lit klast) (lit klength) (lit ksqrt) (lit kread)))
(def %bp-leaf
  (fn (_ ex t flags)
    (match
      ((eq? t (lit num)) (do (%bp-emit! %bx-num (%pg 6)) (%ex-prev! ex (lit num))))
      ((eq? t (lit kread)) (do (%bp-read) (%ex-prev! ex (lit read))))
      ((if (eq? t (lit klength)) #t (eq? t (lit ksqrt))) (%bp-builtin ex t flags))
      (#t (%bp-global! ex t)))))

; zbc_parse_expr
(def %bp-expr
  (fn (_ flags)
    (def ex (vec-make 2 0))
    (def bgn (%bp-ops-len))
    (def paren-first (%bl-is? (lit lparen)))
    (do (%ex-prev! ex (lit print))
        (let go ((nparens 0) (nrelops 0) (rprn #f) (bin-last #t) (incdec #f))
          (let ((t (%pg 4)))
            (match
              ((not (%bc-in? t %bc-expr-toks)) (%bp-expr-end ex bgn flags paren-first nrelops))
              ((if (eq? t (lit inc)) #t (eq? t (lit dec)))
                (do (if incdec (%bc-bad-assign) ()) (%bp-incdec ex flags) (go nparens nrelops #f #f #t)))
              ((eq? t (lit minus))
                (do (%bp-minus ex bgn rprn bin-last)
                    (let ((bl (eq? (%ex-prev ex) (lit minus)))) (go nparens nrelops #f bl (if bl #f incdec)))))
              ((if (%bc-in? t %bc-assign-ops) #t (%bc-in? t %bc-binary-ops))
                (do (%bp-binary ex t bgn bin-last)
                    (go nparens (if (%bc-in? t %bc-rel-ops) (+ nrelops 1) nrelops) #f (not (eq? t (lit not))) #f)))
              ((eq? t (lit lparen))
                (do (%bp-no-leaf ex bin-last rprn) (%bp-push-op! t) (%bl-next) (go (+ nparens 1) nrelops #f bin-last #f)))
              ((eq? t (lit rparen))
                (do (%bp-closing ex bin-last)
                    (if (= nparens 0) (%bp-expr-end ex bgn flags paren-first nrelops)
                      (do (%bp-right-paren ex bgn) (%bl-next) (go (- nparens 1) nrelops #t #f #f)))))
              ((eq? t (lit name))
                (do (%bp-no-leaf ex bin-last rprn) (%bp-name ex (%bf-call flags)) (%ex-n+! ex 1)
                    (go nparens nrelops (eq? (%ex-prev ex) (lit call)) #f incdec)))
              ((%bc-in? t %bc-leaf-toks)
                (do (%bp-no-leaf ex bin-last rprn) (%bp-leaf ex t flags) (%ex-n+! ex 1) (%bl-next)
                    (go nparens nrelops #f #f (if (%bc-in? t (list (lit klength) (lit ksqrt) (lit kread))) #f incdec))))
              (#t
                (do (%bp-no-leaf ex bin-last rprn) (%bp-scale ex flags) (%ex-n+! ex 1) (go nparens nrelops #f #f incdec)))))))))

; the operators left put out, the expression checked, and at a statement's
; head its value printed unless it is an assignment not in parentheses
(def %bp-expr-end
  (fn (_ ex bgn flags paren-first nrelops)
    (def assign
      (let go ((seen #f))
        (if (> (%bp-ops-len) bgn)
          (let ((top (first (%bp-ops))))
            (do (if (if (eq? top (lit lparen)) #t (eq? top (lit rparen))) (%bc-bad-expr) ())
                (%bp-op! top) (%ex-n- ex top) (%bp-pop-op!)
                (go (%bc-in? top %bc-assign-ops))))
          seen)))
    (do (if (if (eq? (%ex-prev ex) (lit not)) #t (not (= (vec-ref ex 1) 1))) (%bc-bad-expr) ())
        (if (if (not (%bf-rel? flags)) (> nrelops 0) #f) (%bc-not-allow "comparison operators outside if or loops")
          (if (if (%bf-rel? flags) (> nrelops 1) #f) (%bc-requires "exactly one comparison operator per condition") ()))
        (if (%bf-print? flags)
          (do (if (if paren-first #t (not assign)) (%bp-emit! %bx-print ()) ()) (%bp-emit! %bx-pop ()))
          ()))))

(def %bp-global!
  (fn (_ ex t)
    (match
      ((eq? t (lit kibase)) (do (%ex-prev! ex (lit ibase)) (%bp-emit! %bx-ibase ())))
      ((eq? t (lit kobase)) (do (%ex-prev! ex (lit obase)) (%bp-emit! %bx-obase ())))
      (#t (do (%ex-prev! ex (lit last)) (%bp-emit! %bx-last ()))))))

; a minus: binary after a leaf, else a negation
(def %bp-minus
  (fn (_ ex bgn rprn bin-last)
    (do (%bl-next)
        (if (%bp-leaf? ex bin-last rprn)
          (do (%ex-prev! ex (lit minus)) (%bp-operator ex (lit minus) bgn))
          (do (%ex-prev! ex (lit neg)) (%bp-push-op! (lit neg)))))))

; ++ and --: after what can be assigned, the old value; before it, the new
(def %bp-incdec
  (fn (_ ex flags)
    (def inc (%bl-is? (lit inc)))
    (if (%bc-in? (%ex-prev ex) %bc-lvals)
      (do (%ex-prev! ex (if inc (lit incpost) (lit decpost)))
          (%bp-emit! (if inc %bx-incpost %bx-decpost) ())
          (%bl-next))
      (do (%ex-prev! ex (if inc (lit incpre) (lit decpre)))
          (%bl-next)
          (%ex-n+! ex 1)
          (let ((t (%pg 4)))
            (match
              ((eq? t (lit name)) (%bp-name ex (%bf-no-call flags)))
              ((eq? t (lit kibase)) (do (%bp-emit! %bx-ibase ()) (%bl-next)))
              ((eq? t (lit klast)) (do (%bp-emit! %bx-last ()) (%bl-next)))
              ((eq? t (lit kobase)) (do (%bp-emit! %bx-obase ()) (%bl-next)))
              ((eq? t (lit kscale)) (do (%bl-next) (if (%bl-is? (lit lparen)) (%bc-bad-token) (%bp-emit! %bx-scale ()))))
              (#t (%bc-bad-token))))
          (%bp-emit! (if inc %bx-incpre %bx-decpre) ())))))

; a name: a variable, an array's element, a whole array, or a call
(def %bp-name
  (fn (_ ex flags)
    (def name (%pg 6))
    (do (%bl-next)
        (match
          ((%bl-is? (lit lbracket))
            (do (%bl-next)
                (if (%bl-is? (lit rbracket))
                  (do (if (%bf-array? flags) () (%bc-bad-expr)) (%ex-prev! ex (lit array)) (%bl-next)
                      (%bp-emit! %bx-array (%bc-arr-id name)))
                  (do (%ex-prev! ex (lit elem)) (%bp-expr (%bf-inner flags)) (%bl-next)
                      (%bp-emit! %bx-elem (%bc-arr-id name))))))
          ((%bl-is? (lit lparen))
            (do (if (%bf-nocall? flags) (%bc-bad-token) ()) (%ex-prev! ex (lit call)) (%bp-call name flags)))
          (#t (do (%ex-prev! ex (lit var)) (%bp-emit! %bx-var (%bc-var-id name))))))))

; NAME's call: its arguments, then the function, made empty where it is new
(def %bp-call
  (fn (_ name flags)
    (def f (%bf-args flags))
    (do (%bl-next)
        (let ((n (if (%bl-is? (lit rparen)) 0
                   (let go ((k 1))
                     (do (%bp-expr f)
                         (match
                           ((%bl-is? (lit comma)) (do (%bl-next) (go (+ k 1))))
                           ((%bl-is? (lit rparen)) k)
                           (#t (%bc-bad-token))))))))
          (let ((i (%bc-find (%bg 3) name)))
            (do (%bp-emit! %bx-call (pair n (if (>= i 0) i (%bc-func-add! name))))
                (%bl-next)))))))

(def %bp-read
  (fn (_)
    (do (%bl-next) (if (%bl-is? (lit lparen)) () (%bc-bad-token))
        (%bl-next) (if (%bl-is? (lit rparen)) () (%bc-bad-token))
        (%bp-emit! %bx-read ()))))

; length( and sqrt(: the closing parenthesis left for the expression
(def %bp-builtin
  (fn (_ ex t flags)
    (do (%bl-next) (if (%bl-is? (lit lparen)) () (%bc-bad-token))
        (%bl-next)
        (%bp-expr (%bf-args flags))
        (if (%bl-is? (lit rparen)) () (%bc-bad-token))
        (if (eq? t (lit klength)) (do (%ex-prev! ex (lit length)) (%bp-emit! %bx-length ()))
          (do (%ex-prev! ex (lit sqrt)) (%bp-emit! %bx-sqrt ()))))))

; scale, or scale( ): the variable or a number's scale
(def %bp-scale
  (fn (_ ex flags)
    (do (%bl-next)
        (if (not (%bl-is? (lit lparen))) (do (%ex-prev! ex (lit scale)) (%bp-emit! %bx-scale ()))
          (do (%ex-prev! ex (lit scalefn))
              (%bl-next)
              (%bp-expr (%bf-inner flags))
              (if (%bl-is? (lit rparen)) () (%bc-bad-token))
              (%bp-emit! %bx-scalefn ())
              (%bl-next))))))

; --- statements ----------------------------------------------------------------------

(def %bc-expr-heads
  (list (lit minus) (lit inc) (lit dec) (lit not) (lit lparen) (lit name) (lit num) (lit kibase) (lit klast)
        (lit klength) (lit kobase) (lit kread) (lit kscale) (lit ksqrt)))

(def %bc-limits
  (%str-concat
    (list "BC_BASE_MAX     = 999\n" "BC_DIM_MAX      = 2147483647\n" "BC_SCALE_MAX    = 4294967295\n"
          "BC_STRING_MAX   = 4294967294\n" "MAX Exponent    = 999999999\n" "Number of vars  = 999999999\n")))

; zbc_parse_stmt_possibly_auto
(def %bp-stmt
  (fn (_ auto)
    (def t (%pg 4))
    (match
      ((if (eq? t (lit nl)) #t (eq? t (lit scolon))) ())
      ((eq? t (lit lbrace)) (%bp-block auto))
      ((%bc-in? t %bc-expr-heads) (%bp-expr %bf-print))
      ((eq? t (lit str)) (do (%bp-str!) (%bp-emit! %bx-print-str ())))
      ((eq? t (lit kbreak))
        (do (if (null? (%pg 10)) (%bc-bad-token) ()) (%bp-emit! %bx-jump (first (%pg 10))) (%bl-next)))
      ((eq? t (lit kcontinue))
        (do (if (null? (%pg 11)) (%bc-bad-token) ()) (%bp-emit! %bx-jump (first (%pg 11))) (%bl-next)))
      ((eq? t (lit kfor)) (%bp-for))
      ((eq? t (lit khalt)) (do (%bp-emit! %bx-halt ()) (%bl-next)))
      ((eq? t (lit kif)) (%bp-if))
      ((eq? t (lit klimits)) (do (bn-emit! %bc-limits) (%bl-next)))
      ((eq? t (lit kprint)) (%bp-print))
      ((eq? t (lit kquit)) (%bc-quit))
      ((eq? t (lit kreturn)) (do (if (= (%pg 12) 0) (%bc-die "'return' not in a function") ()) (%bp-return)))
      ((eq? t (lit kwhile)) (%bp-while))
      (#t (%bc-bad-token)))))

(def %bp-block
  (fn (_ auto)
    (do (let go () (do (%bl-next) (if (%bl-is? (lit nl)) (go) ())))
        (if (if auto (%bl-is? (lit kauto)) #f) (%bp-auto) ())
        (let go ()
          (if (%bl-is? (lit rbrace)) ()
            (do (%bp-stmt #f)
                (if (%bl-is? (lit rbrace)) ()
                  (do (if (if (%bl-is? (lit scolon)) #t (%bl-is? (lit nl))) () (%bc-die-at "bad statement terminator"))
                      (%bl-next)
                      (go))))))
        (%bl-next))))

(def %bp-str! (fn (_) (do (%bp-emit! %bx-str (%pg 6)) (%bl-next))))

; the statement after if(...), else, while(...) or for(...): one newline may
; come before it
(def %bp-body
  (fn (_ after)
    (do (%bl-next)
        (if (%bl-is? (lit nl)) (%bl-next) ())
        (if (%bl-is? (lit nl)) (%bc-die (%str-concat (list "no statement after '" after "'"))) ())
        (%bp-stmt #f))))

(def %bp-open
  (fn (_) (do (%bl-next) (if (%bl-is? (lit lparen)) () (%bc-bad-token)) (%bl-next))))

(def %bp-close (fn (_) (if (%bl-is? (lit rparen)) () (%bc-bad-token))))

(def %bp-if
  (fn (_)
    (do (%bp-open)
        (%bp-expr %bf-rel)
        (%bp-close)
        (let ((ip (%bp-label! 0)))
          (do (%bp-emit! %bx-jz ip)
              (%bp-body "if")
              (if (%bl-is? (lit kelse))
                (let ((ip2 (%bp-label! 0)))
                  (do (%bp-emit! %bx-jump ip2)
                      (%bp-relabel! ip)
                      (%bp-body "else")
                      (%bp-relabel! ip2)))
                (%bp-relabel! ip)))))))

(def %bp-while
  (fn (_)
    (do (%bp-open)
        (let ((cond (%bp-label! (%bp-here))))
          (do (%pg! 11 (pair cond (%pg 11)))
              (%pg! 10 (pair (+ cond 1) (%pg 10)))
              (%bp-label! 0)
              (%bp-expr %bf-rel)
              (%bp-close)
              (%bp-emit! %bx-jz (+ cond 1))
              (%bp-body "while")
              (%bp-emit! %bx-jump cond)
              (%bp-relabel! (+ cond 1))
              (%pg! 10 (rest (%pg 10)))
              (%pg! 11 (rest (%pg 11))))))))

(def %bp-for
  (fn (_)
    (do (%bp-open)
        (if (%bl-is? (lit scolon)) (%bc-not-allow "an empty init expression in 'for()'")
          (do (%bp-expr %bf-none) (%bp-emit! %bx-pop ())))
        (if (%bl-is? (lit scolon)) () (%bc-bad-token))
        (%bl-next)
        (let ((cond (%bp-label! (%bp-here))))
          (do (if (%bl-is? (lit scolon))
                (do (%bp-emit! %bx-num "1") (%bc-not-allow "an empty condition expression in 'for()'"))
                (%bp-expr %bf-rel))
              (if (%bl-is? (lit scolon)) () (%bc-bad-token))
              (%bl-next)
              (%bp-emit! %bx-jz (+ cond 3))
              (%bp-emit! %bx-jump (+ cond 2))
              (%pg! 11 (pair (+ cond 1) (%pg 11)))
              (%bp-label! (%bp-here))
              (if (%bl-is? (lit rparen)) (%bc-not-allow "an empty update expression in 'for()'")
                (do (%bp-expr %bf-none) (%bp-close) (%bp-emit! %bx-pop ())))
              (%bp-emit! %bx-jump cond)
              (%bp-label! (%bp-here))
              (%pg! 10 (pair (+ cond 3) (%pg 10)))
              (%bp-label! 0)
              (%bp-body "for")
              (%bp-emit! %bx-jump (+ cond 1))
              (%bp-relabel! (+ cond 3))
              (%pg! 10 (rest (%pg 10)))
              (%pg! 11 (rest (%pg 11))))))))

(def %bp-print
  (fn (_)
    (let go ()
      (do (%bl-next)
          (if (%bl-is? (lit str)) (%bp-str!) (%bp-expr %bf-none))
          (%bp-emit! %bx-print-pop ())
          (if (%bl-is? (lit comma)) (go) ())))))

(def %bp-return
  (fn (_)
    (do (%bl-next)
        (let ((t (%pg 4)))
          (if (%bc-in? t (list (lit nl) (lit scolon) (lit rbrace))) (%bp-emit! %bx-ret0 ())
            (do (%bp-expr %bf-none)
                (if (if (eq? t (lit lparen)) (eq? (%pg 5) (lit rparen)) #f) ()
                  (%bc-requires "parentheses around return expressions"))
                (%bp-emit! %bx-ret ())))))))

; NAME, of TYPE, among the function's parameters and autos
(def %bp-insert!
  (fn (_ name type)
    (def f (%bp-func))
    (do (map (fn (_ a) (if (if (string=? (first a) name) (eq? (first (rest a)) type) #f)
                         (%bc-die "duplicate function parameter or auto name") ()))
             (vec-ref f 2))
        (vec-set! f 2 (append (vec-ref f 2)
                              (list (list name type (if (eq? type (lit var)) (%bc-var-id name) (%bc-arr-id name)))))))))

; define [void] NAME(PARAMETERS) { BODY }
(def %bp-define
  (fn (_)
    (do (%bl-next)
        (if (%bl-is? (lit name)) () (%bc-bad-def))
        (let ((void (string=? (%pg 6) "void")))
          (do (%bl-next)
              (let ((void2 (if void (%bl-is? (lit name)) #f)))
                (do (if void2 (%bl-next) ())
                    (if (%bl-is? (lit lparen)) () (%bc-bad-def))
                    (%pg! 8 (%bc-func-add! (%pg 6)))
                    (vec-set! (%bp-func) 5 void2)
                    (%bl-next)
                    (if (%bp-params #f) (%bc-bad-def) ())
                    (%bl-next)
                    (if (%bl-is? (lit lbrace)) () (%bc-requires "the left brace be on the same line as the function header"))
                    (if (%bl-is? (lit nl)) (%bl-next) ())
                    (if (%bl-is? (lit lbrace)) () (%bc-die "function { body } expected"))
                    (%pg! 12 (+ (%pg 12) 1))
                    (%bp-stmt #t)
                    (%pg! 12 (- (%pg 12) 1))
                    (%bp-emit! %bx-ret0 ())
                    (%pg! 8 0))))))))

; the parameters up to the closing parenthesis: whether a comma came last
(def %bp-params
  (fn (self comma)
    (if (%bl-is? (lit rparen)) comma
      (let ((ref (%bl-is? (lit mul))))
        (do (if ref (do (%bl-next) (%bc-not-allow "references")) ())
            (if (%bl-is? (lit name)) () (%bc-bad-def))
            (vec-set! (%bp-func) 1 (+ (vec-ref (%bp-func) 1) 1))
            (let ((name (%pg 6)))
              (do (%bl-next)
                  (let ((type (if (%bl-is? (lit lbracket))
                                (do (%bl-next) (if (%bl-is? (lit rbracket)) () (%bc-bad-def)) (%bl-next)
                                    (if ref (lit ref) (lit array)))
                                (if ref (%bc-die-at "vars can't be references") (lit var)))))
                    (let ((c (%bl-is? (lit comma))))
                      (do (if c (%bl-next) ())
                          (%bp-insert! name type)
                          (self c)))))))))))

(def %bp-auto
  (fn (_)
    (do (%bl-next)
        (let go ()
          (do (if (%bl-is? (lit name)) () (%bc-die-at "bad 'auto' syntax"))
              (let ((name (%pg 6)))
                (do (%bl-next)
                    (let ((type (if (%bl-is? (lit lbracket))
                                  (do (%bl-next) (if (%bl-is? (lit rbracket)) () (%bc-die-at "bad 'auto' syntax")) (%bl-next)
                                      (lit array))
                                  (lit var))))
                      (%bp-insert! name type))))
              (match
                ((if (%bl-is? (lit nl)) #t (%bl-is? (lit scolon))) ())
                ((%bl-is? (lit comma)) (do (%bl-next) (go)))
                (#t (%bc-die-at "bad 'auto' syntax"))))))))

; --- the machine -------------------------------------------------------------------
;
; A result, on the results stack: (KIND . VALUE) -- (lit temp) a number,
; (lit const) a number's text not yet read, (lit var) a variable's index,
; (lit elem) (ARRAY . INDEX), (lit array) an array's index, (lit ibase),
; (lit obase) and (lit scale) their numbers, (lit last), (lit one), (lit str)
; a string's text, (lit void) a void function's nothing.

(def %bx-push! (fn (_ r) (%bg! 0 (pair r (%bg 0)))))
(def %bx-top (fn (_) (if (null? (%bg 0)) (%bc-few) (first (%bg 0)))))
(def %bx-pop! (fn (_) (%bg! 0 (rest (%bg 0)))))
(def %bx-replace! (fn (_ n r) (%bg! 0 (pair r (if (= n 1) (rest (%bg 0)) (rest (rest (%bg 0))))))))
(def %bx-temp (fn (_ n) (pair (lit temp) n)))

(def %bx-array-of (fn (_ id) (first (%gv-ref (%bg 6) id))))

; the array's element at IDX, the array grown to hold it as busybox's does
(def %bx-cell
  (fn (_ a idx)
    (do (let go () (if (<= (%gv-len a) idx) (do (%gv-push! a %bc-zero) (go)) ()))
        (%gv-ref a idx))))

; the number R holds, #f for an array or a string
(def %bx-num-of
  (fn (_ r)
    (def k (first r))
    (match
      ((eq? k (lit temp)) (rest r))
      ((eq? k (lit var)) (first (%gv-ref (%bg 4) (rest r))))
      ((eq? k (lit const)) (bn-parse (rest r) (%bg 9)))
      ((eq? k (lit elem)) (%bx-cell (%bx-array-of (first (rest r))) (rest (rest r))))
      ((eq? k (lit last)) (%bg 11))
      ((eq? k (lit one)) (pair 1 0))
      ((if (eq? k (lit array)) #t (eq? k (lit str))) #f)
      (#t (rest r)))))

; the top's number: too few, or the wrong type
(def %bx-prep
  (fn (_) (let ((n (%bx-num-of (%bx-top)))) (if (eq? n #f) (%bc-wrong) n))))

; the top two as (LEFT LEFT'S RIGHT RIGHT'S), both numbers
(def %bx-two
  (fn (_)
    (if (if (null? (%bg 0)) #t (null? (rest (%bg 0)))) (%bc-few)
      (let ((r (first (%bg 0))) (l (first (rest (%bg 0)))))
        (let ((ln (%bx-num-of l)))
          (let ((rn (%bx-num-of r)))
            (if (if (eq? ln #f) #t (eq? rn #f)) (%bc-wrong) (list l ln r rn))))))))

(def %bx-binary
  (fn (_ f) (let ((x (%bx-two))) (%bx-replace! 2 (%bx-temp (f (first (rest x)) (first (rest (rest (rest x)))) (%bg 8)))))))

(def %bx-pow (fn (_ _) (%bx-binary bn-pow)))
(def %bx-mul (fn (_ _) (%bx-binary bn-mul)))
(def %bx-div (fn (_ _) (%bx-binary bn-div)))
(def %bx-mod (fn (_ _) (%bx-binary bn-rem)))
(def %bx-plus (fn (_ _) (%bx-binary (fn (_ x y _) (bn-add x y)))))
(def %bx-minus (fn (_ _) (%bx-binary (fn (_ x y _) (bn-sub x y)))))

(def %bx-bool (fn (_ t) (%bx-temp (if t (pair 1 0) %bc-zero))))

(def %bx-logical
  (fn (_ f) (let ((x (%bx-two))) (%bx-replace! 2 (%bx-bool (f (first (rest x)) (first (rest (rest (rest x))))))))))

(def %bx-eq (fn (_ _) (%bx-logical (fn (_ x y) (= (bn-cmp x y) 0)))))
(def %bx-le (fn (_ _) (%bx-logical (fn (_ x y) (<= (bn-cmp x y) 0)))))
(def %bx-ge (fn (_ _) (%bx-logical (fn (_ x y) (>= (bn-cmp x y) 0)))))
(def %bx-ne (fn (_ _) (%bx-logical (fn (_ x y) (not (= (bn-cmp x y) 0))))))
(def %bx-lt (fn (_ _) (%bx-logical (fn (_ x y) (< (bn-cmp x y) 0)))))
(def %bx-gt (fn (_ _) (%bx-logical (fn (_ x y) (> (bn-cmp x y) 0)))))
(def %bx-and (fn (_ _) (%bx-logical (fn (_ x y) (if (bn-zero? x) #f (not (bn-zero? y)))))))
(def %bx-or (fn (_ _) (%bx-logical (fn (_ x y) (if (bn-zero? x) (not (bn-zero? y)) #t)))))

(def %bx-not (fn (_ _) (%bx-replace! 1 (%bx-bool (bn-zero? (%bx-prep))))))

(def %bx-neg
  (fn (_ _) (let ((n (%bx-prep))) (%bx-replace! 1 (%bx-temp (if (bn-zero? n) n (pair (bn-big- 0 (first n)) (rest n))))))))

; an assignment: F makes the value from the left's and the right's; the
; bases and the scale are checked before they are set
(def %bx-assigning
  (fn (_ f)
    (def x (%bx-two))
    (def l (first x))
    (def k (first l))
    (do (if (%bc-in? k (list (lit const) (lit temp) (lit void))) (%bc-bad-assign) ())
        (let ((v (f (first (rest x)) (first (rest (rest (rest x)))) (%bg 8))))
          (do (%bx-store! l v)
              (%bx-replace! 2 (%bx-temp v)))))))

; BC_MAX_SCALE, an unsigned int's most, made where it is asked for
(def %bc-uint-max (fn (_) (bn-big- (bn-big* 65536 65536) 1)))

(def %bx-store!
  (fn (_ l v)
    (def k (first l))
    (match
      ((eq? k (lit var)) (%gv-set! (%bg 4) (rest l) (pair v (rest (%gv-ref (%bg 4) (rest l))))))
      ((eq? k (lit elem))
        (let ((a (%bx-array-of (first (rest l)))))
          (do (%bx-cell a (rest (rest l))) (%gv-set! a (rest (rest l)) v))))
      ((eq? k (lit last)) (%bg! 11 v))
      ((eq? k (lit scale))
        (let ((s (bn-ulong v))) (if (bn-big< (%bc-uint-max) s) (%bc-die "bad scale; must be [0,4294967295]") (%bg! 8 s))))
      ((eq? k (lit ibase))
        (let ((b (bn-ulong v))) (if (if (bn-big< b 2) #t (bn-big< 36 b)) (%bc-die "bad ibase; must be [2,16]") (%bg! 9 b))))
      (#t
        (let ((b (bn-ulong v))) (if (if (bn-big< b 2) #t (bn-big< 999 b)) (%bc-die "bad obase; must be [2,999]") (%bg! 10 b)))))))

(def %bx-assign (fn (_ _) (%bx-assigning (fn (_ x y _) y))))
(def %bx-apow (fn (_ _) (%bx-assigning bn-pow)))
(def %bx-amul (fn (_ _) (%bx-assigning bn-mul)))
(def %bx-adiv (fn (_ _) (%bx-assigning bn-div)))
(def %bx-amod (fn (_ _) (%bx-assigning bn-rem)))
(def %bx-aplus (fn (_ _) (%bx-assigning (fn (_ x y _) (bn-add x y)))))
(def %bx-aminus (fn (_ _) (%bx-assigning (fn (_ x y _) (bn-sub x y)))))

; ++ and --, as an assignment of one; after, the value before it
(def %bx-incdec
  (fn (_ inc post)
    (def old (%bx-prep))
    (do (%bx-push! (pair (lit one) ()))
        (if inc (%bx-aplus ()) (%bx-aminus ()))
        (if post (%bx-replace! 1 (%bx-temp old)) ()))))

(def %bx-incpre (fn (_ _) (%bx-incdec #t #f)))
(def %bx-decpre (fn (_ _) (%bx-incdec #f #f)))
(def %bx-incpost (fn (_ _) (%bx-incdec #t #t)))
(def %bx-decpost (fn (_ _) (%bx-incdec #f #t)))

(def %bx-num (fn (_ text) (%bx-push! (pair (lit const) text))))
(def %bx-str (fn (_ text) (%bx-push! (pair (lit str) text))))
(def %bx-var (fn (_ id) (%bx-push! (pair (lit var) id))))
(def %bx-array (fn (_ id) (%bx-push! (pair (lit array) id))))
(def %bx-last (fn (_ _) (%bx-push! (pair (lit last) ()))))
(def %bx-ibase (fn (_ _) (%bx-push! (pair (lit ibase) (pair (%bg 9) 0)))))
(def %bx-obase (fn (_ _) (%bx-push! (pair (lit obase) (pair (%bg 10) 0)))))
(def %bx-scale (fn (_ _) (%bx-push! (pair (lit scale) (pair (%bg 8) 0)))))

; an element: the index popped, under BC_MAX_DIM
(def %bx-elem
  (fn (_ id)
    (let ((i (bn-ulong (%bx-prep))))
      (if (> i 2147483647) (%bc-die "array too long; must be [1,2147483647]")
        (%bx-replace! 1 (pair (lit elem) (pair id i)))))))

(def %bx-pop (fn (_ _) (do (%bx-top) (%bx-pop!))))

; xc_program_len, as bc counts: zero is its scale or 1, a number past its
; point the digits after its leading zeros
(def %bx-len-of
  (fn (_ n)
    (if (bn-zero? n) (if (= (rest n) 0) 1 (rest n))
      (let ((d (bn-digits (first n))))
        (let ((l (bn-max d (rest n)))) (if (= l (rest n)) d l))))))

(def %bx-builtin
  (fn (_ f)
    (let ((r (%bx-top)))
      (let ((n (%bx-num-of r)))
        (%bx-replace! 1 (%bx-temp (f r n)))))))

(def %bx-length
  (fn (_ _)
    (%bx-builtin (fn (_ r n) (match ((eq? (first r) (lit array)) (pair (%gv-len (%bx-array-of (rest r))) 0))
                                     ((eq? n #f) (%bc-wrong))
                                     (#t (pair (%bx-len-of n) 0)))))))

(def %bx-sqrt (fn (_ _) (%bx-builtin (fn (_ r n) (if (eq? n #f) (%bc-wrong) (bn-sqrt n (%bg 8)))))))
(def %bx-scalefn (fn (_ _) (%bx-builtin (fn (_ r n) (if (eq? n #f) (%bc-wrong) (pair (rest n) 0))))))

; PRINT, the statement's value: a number and a newline, a void call nothing
(def %bx-print
  (fn (_ _)
    (let ((r (%bx-top)))
      (if (eq? (first r) (lit void)) ()
        (let ((n (%bx-num-of r)))
          (if (eq? n #f) (do (bn-print-str! (rest r)) (bn-emit! "\n"))
            (do (bn-print-num! n (%bg 10) #t) (%bg! 11 n))))))))

; print's items: a number with no newline, a string with its escapes made
(def %bx-print-pop
  (fn (_ _)
    (let ((r (%bx-top)))
      (let ((n (%bx-num-of r)))
        (do (if (eq? n #f) (bn-print-str! (rest r)) (do (bn-print-num! n (%bg 10) #f) (%bg! 11 n)))
            (%bx-pop!))))))

; a string standing as a statement: written as it is
(def %bx-print-str
  (fn (_ _)
    (let ((s (rest (%bx-top))))
      (do (bn-emit! s)
          (let go ((i (- (byte-len s) 1)))
            (match ((< i 0) (bn-col! (+ (bn-col) (byte-len s))))
                   ((= (byte-at s i) 10) (bn-col! (- (byte-len s) (+ i 1))))
                   (#t (go (- i 1)))))
          (%bx-pop!)))))

(def %bx-frame (fn (_) (first (%bg 1))))
(def %bx-goto! (fn (_ label) (let ((fr (%bx-frame))) (vec-set! fr 1 (%gv-ref (vec-ref (%bc-func (vec-ref fr 0)) 4) label)))))

(def %bx-jump (fn (_ label) (%bx-goto! label)))
(def %bx-jz (fn (_ label) (let ((n (%bx-prep))) (do (%bx-pop!) (if (bn-zero? n) (%bx-goto! label) ())))))
(def %bx-halt (fn (_ _) (%bc-quit)))

(def %bx-frame-new (fn (_ f) (let ((fr (vec-make 2 0))) (do (vec-set! fr 0 f) fr))))

; a call: (ARGUMENTS . FUNCTION); the arguments, last first, pushed onto
; the parameters, then the autos made
(def %bx-call
  (fn (_ a)
    (def nargs (first a))
    (def func (%bc-func (rest a)))
    (do (if (= (%gv-len (vec-ref func 3)) 0) (%bc-die "undefined function") ())
        (if (= nargs (vec-ref func 1)) ()
          (%bc-die (%str-concat (list "function has " (cu-int->str (vec-ref func 1)) " parameters, but called with "
                                      (cu-int->str nargs)))))
        (map %bx-bind! (reverse (%bc-take (vec-ref func 2) nargs)))
        (map %bx-auto! (%bc-drop (vec-ref func 2) nargs))
        (%bg! 1 (pair (%bx-frame-new (rest a)) (%bg 1))))))

(def %bc-take (fn (self l k) (if (= k 0) () (pair (first l) (self (rest l) (- k 1))))))
(def %bc-drop (fn (self l k) (if (= k 0) l (self (rest l) (- k 1)))))

(def %bx-stack-push! (fn (_ slots id v) (%gv-set! (%bg slots) id (pair v (%gv-ref (%bg slots) id)))))
(def %bx-stack-pop! (fn (_ slots id) (%gv-set! (%bg slots) id (rest (%gv-ref (%bg slots) id)))))

; the top argument made parameter A: a number copied, an array copied, a
; reference the array itself
(def %bx-bind!
  (fn (_ a)
    (def type (first (rest a)))
    (def id (first (rest (rest a))))
    (def arg (%bx-top))
    (do (if (eq? (eq? type (lit var)) (eq? (first arg) (lit array))) (%bc-wrong) ())
        (match
          ((eq? type (lit var)) (%bx-stack-push! 4 id (%bx-num-of arg)))
          ((eq? type (lit ref)) (%bx-stack-push! 6 id (%bx-array-of (rest arg))))
          (#t (%bx-stack-push! 6 id (%gv-copy (%bx-array-of (rest arg))))))
        (%bx-pop!))))

(def %bx-auto!
  (fn (_ a)
    (if (eq? (first (rest a)) (lit var)) (%bx-stack-push! 4 (first (rest (rest a))) %bc-zero)
      (%bx-stack-push! 6 (first (rest (rest a))) (%gv-new)))))

; a return: the value pushed, the frame left, the parameters and autos popped
(def %bx-return
  (fn (_ r)
    (def func (%bc-func (vec-ref (%bx-frame) 0)))
    (do (%bx-push! r)
        (%bg! 1 (rest (%bg 1)))
        (map (fn (_ a) (%bx-stack-pop! (if (eq? (first (rest a)) (lit var)) 4 6) (first (rest (rest a))))) (vec-ref func 2)))))

(def %bx-ret
  (fn (_ _) (let ((n (%bx-num-of (%bx-top)))) (do (%bx-pop!) (%bx-return (%bx-temp n))))))

(def %bx-ret0
  (fn (_ _) (%bx-return (if (vec-ref (%bc-func (vec-ref (%bx-frame) 0)) 5) (pair (lit void) %bc-zero) (%bx-temp %bc-zero)))))

; read(): a line of standard input read as an expression, and run
(def %bx-read
  (fn (_ _)
    (def line ((%bg 13)))
    (def saved %bp)
    (def func (%bc-func 1))
    (do (%gv-clear! (vec-ref func 3))
        (%gv-clear! (vec-ref func 4))
        (set! %bp (%bp-new (if (null? line) "" line) () () 0))
        (%pg! 8 1)
        (%bl-next)
        (%bp-expr %bf-none)
        (if (if (%bl-is? (lit nl)) #t (%bl-is? (lit eof))) () (%bc-die-at "bad read() expression"))
        (%bp-emit! %bx-ret ())
        (set! %bp saved)
        (%bg! 1 (pair (%bx-frame-new 1) (%bg 1))))))

; the instructions run until the main program's are done
(def %bc-exec
  (fn (_)
    (let go ((n 1))
      (let ((fr (%bx-frame)))
        (let ((code (vec-ref (%bc-func (vec-ref fr 0)) 3)) (ip (vec-ref fr 1)))
          (if (>= ip (%gv-len code)) ()
            (let ((ins (%gv-ref code ip)))
              (do (vec-set! fr 1 (+ ip 1))
                  ((first ins) (rest ins))
                  (cu-sweep-at n cu-sweep-steps)
                  (go (+ n 1))))))))))

; --- the applet ----------------------------------------------------------------------

; P's statements, each read then run as busybox's zxc_vm_process runs them;
; the main program's code dropped after each
(def %bc-process
  (fn (_ p)
    (do (set! %bp p)
        (%bl-next)
        (let go ()
          (if (%bl-is? (lit eof)) ()
            (do (if (%bl-is? (lit kdefine)) (%bp-define) (%bp-stmt #f))
                (if (%bc-in? (%pg 4) (list (lit scolon) (lit nl) (lit eof))) () (%bc-die-at "bad statement terminator"))
                (%bc-exec)
                (bn-flush!)
                (%gv-clear! (vec-ref (%bc-func 0) 3))
                (%gv-clear! (vec-ref (%bc-func 0) 4))
                (vec-set! (%bx-frame) 1 0)
                (cu-sweep-tick! cu-sweep-lines)
                (%bl-next)
                (go)))))))

; FILE's program run, its name and line before an error's words
(def %bc-file
  (fn (_ file)
    (let ((p (cu-pieces file ())))
      (if (Err err? p) (Err raise (lit bc-open) (%str-concat (list "can't open '" file "': " (file-err-text p))) ())
        (do (%bg! 14 1)
            (%bc-process (%bp-new "" (%bc-lines p) file 1))
            (p (lit close))
            (%pg! 13 ()))))))

; the math library -l loads, as busybox has it
(def %bc-lib
  (list "scale=20"
        "define e(x){" "auto b,s,n,r,d,i,p,f,v" "b=ibase" "ibase=A" "if(x<0){" "n=1" "x=-x" "}" "s=scale"
        "r=6+s+.44*x" "scale=scale(x)+1" "while(x>1){" "d+=1" "x/=2" "scale+=1" "}" "scale=r" "r=x+1" "p=x"
        "f=v=1" "for(i=2;v;++i){" "p*=x" "f*=i" "v=p/f" "r+=v" "}" "while(d--)r*=r" "scale=s" "ibase=b"
        "if(n)return(1/r)" "return(r/1)" "}"
        "define l(x){" "auto b,s,r,p,a,q,i,v" "b=ibase" "ibase=A" "if(x<=0){" "r=(1-10^scale)/1" "ibase=b"
        "return(r)" "}" "s=scale" "scale+=6" "p=2" "while(x>=2){" "p*=2" "x=sqrt(x)" "}" "while(x<=.5){" "p*=2"
        "x=sqrt(x)" "}" "r=a=(x-1)/(x+1)" "q=a*a" "v=1" "for(i=3;v;i+=2){" "a*=q" "v=a/i" "r+=v" "}" "r*=p"
        "scale=s" "ibase=b" "return(r/1)" "}"
        "define s(x){" "auto b,s,r,a,q,i" "if(x<0)return(-s(-x))" "b=ibase" "ibase=A" "s=scale" "scale=1.1*s+2"
        "a=a(1)" "scale=0" "q=(x/a+2)/4" "x-=4*q*a" "if(q%2)x=-x" "scale=s+2" "r=a=x" "q=-x*x"
        "for(i=3;a;i+=2){" "a*=q/(i*(i-1))" "r+=a" "}" "scale=s" "ibase=b" "return(r/1)" "}"
        "define c(x){" "auto b,s" "b=ibase" "ibase=A" "s=scale" "scale*=1.2" "x=s(2*a(1)+x)" "scale=s" "ibase=b"
        "return(x/1)" "}"
        "define a(x){" "auto b,s,r,n,a,m,t,f,i,u" "b=ibase" "ibase=A" "n=1" "if(x<0){" "n=-1" "x=-x" "}"
        "if(scale<65){"
        "if(x==1)return(.7853981633974483096156608458198757210492923498437764552437361480/n)"
        "if(x==.2)return(.1973955598498807583700497651947902934475851037878521015176889402/n)"
        "}" "s=scale" "if(x>.2){" "scale+=5" "a=a(.2)" "}" "scale=s+3" "while(x>.2){" "m+=1"
        "x=(x-.2)/(1+.2*x)" "}" "r=u=x" "f=-x*x" "t=1" "for(i=3;t;i+=2){" "u*=f" "t=u/i" "r+=t" "}" "scale=s"
        "ibase=b" "return((m*a+r)/n)" "}"
        "define j(n,x){" "auto b,s,o,a,i,v,f" "b=ibase" "ibase=A" "s=scale" "scale=0" "n/=1" "if(n<0){" "n=-n"
        "o=n%2" "}" "a=1" "for(i=2;i<=n;++i)a*=i" "scale=1.5*s" "a=(x^n)/2^n/a" "r=v=1" "f=-x*x/4"
        "scale+=length(a)-scale(a)" "for(i=1;v;++i){" "v=v*f/i/(n+i)" "r+=v" "}" "scale=s" "ibase=b"
        "if(o)a=-a" "return(a*r/1)" "}"))

(def %bc-join
  (fn (_ lines) (%str-concat (rest (reverse (let go ((l lines) (acc ())) (if (null? l) acc (go (rest l) (pair (first l) (pair "\n" acc))))))))))

; S's words, split at white space
(def %bc-words
  (fn (_ s)
    (let go ((i 0) (start -1) (acc ()))
      (if (>= i (byte-len s)) (reverse (if (< start 0) acc (pair (substring s start i) acc)))
        (if (%bl-space? (byte-at s i))
          (go (+ i 1) -1 (if (< start 0) acc (pair (substring s start i) acc)))
          (go (+ i 1) (if (< start 0) i start) acc))))))

(def %bc-on? (fn (_ os short long) (if (null? os) #f (if (if (Opts on? (first os) short) #t (Opts on? (first os) long)) #t (%bc-on? (rest os) short long)))))

(def %bc-info "bc 1.36.1\nAdapted from https://github.com/gavinhoward/bc\nOriginal code (c) 2018 Gavin D. Howard and contributors\n")

(def %bc-start!
  (fn (_ posix stdin-thunk)
    (do (set! %bc (vec-build 15 (fn (_ i) (match ((= i 2) (%gv-new)) ((= i 4) (%gv-new)) ((= i 6) (%gv-new)) ((= i 8) 0) ((= i 9) 10)
                                                ((= i 10) 10) ((= i 11) %bc-zero) ((= i 12) posix) ((= i 14) 1) (#t ())))))
        (%bc-func-add! "")
        (%bc-func-add! "1")
        (%bg! 1 (list (%bx-frame-new 0)))
        (%bg! 13 (%bc-lines (cu-pieces "-" stdin-thunk)))
        (set! %bp (%bp-new "" () () 0)))))

; bc [-sqlw] [FILE]...: BC_ENV_ARGS's words read first, as if before the
; arguments
(def cu-bc
  (fn (_ argv stdin-thunk)
    (def env (sys-getenv "BC_ENV_ARGS"))
    (def os (append (if (null? env) () (list (cu-opts "bc" (%bc-words env)))) (list (cu-opts "bc" argv))))
    (def files (let go ((l os) (acc ())) (if (null? l) acc (go (rest l) (append acc (Opts operands (first l)))))))
    (def posix (match ((if (%bc-on? os "-s" "--standard") #t (not (null? (sys-getenv "POSIXLY_CORRECT")))) (lit s))
                      ((%bc-on? os "-w" "--warn") (lit w))
                      (#t ())))
    (if (%bc-on? os "-v" "--version") (do (file-write 1 %bc-info) 0)
      (do (bn-start! (lit bc) (bn-line-len "BC_LINE_LENGTH" #t))
          (%bc-start! posix stdin-thunk)
          (guard (e (do (bn-flush!)
                        (match
                          ((eq? (cu-err-label e) (lit bc-quit)) 0)
                          ((eq? (cu-err-label e) (lit bc)) (do (file-write 2 (%str-concat (list "bc: " (%bc-where) (e msg) "\n"))) 1))
                          ((eq? (cu-err-label e) (lit bc-open)) (do (file-write 2 (%str-concat (list "bc: " (e msg) "\n"))) 1))
                          (#t (error e)))))
            (do (if (%bc-on? os "-l" "--mathlib") (%bc-process (%bp-new (%bc-join %bc-lib) () () 0)) ())
                (map %bc-file files)
                (%bg! 14 1)
                (%bc-process (%bp-new "" (%bg 13) () 1))
                0))))))

(provide coreutils/bc cu-bc)
