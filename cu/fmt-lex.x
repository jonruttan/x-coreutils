; # x-coreutils -- the small tools, as applets
;
; ## cu/fmt-lex.x -- one reader for every format string
;
; @description printf's %s, date's %Y, stat's %n and the escapes all parse
;   the same way; this reads them once so each applet keeps only its table.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; A format string is literal text, backslash escapes, and directives introduced
; by %. The scanning is the same wherever one appears; only the meaning of a
; conversion differs, and that is the part belonging to the applet. So the
; scanning lives here and printf, date and stat keep their tables.
;
; The tokens:
;
;   a literal run   the text, as a string
;   an escape       the character it names
;   a directive     (dir LEFT? ZERO? WIDTH PREC "<conv>")
;
; Width and precision are -1 when the format did not give them, which differs
; from 0: "%.0f" asked for no decimals and "%f" did not ask. A lone % at the
; end is a literal %.
;
; ## THE PLATFORM'S LEXER, ITS STATES COMPILED
;
; The scanning is x/reader/lexer's: a directive is a pattern -- %, then any
; flags, width and precision, then the one byte that names the conversion --
; and an escape is a backslash and up to three octal digits, or x and up to
; two hex digits, or whichever byte follows.  The rules make a tokenizer base
; whose states run as native code, made on the first format and kept; it
; rebuilds itself after a state image loads.  What a token means stays here:
; the directive's parts, and the byte an escape names, are read off the
; token's text once it is cut, and no x code runs inside the base.

(import x/reader/lexer)

(def %cu-fl-flag-byte?
  (fn (_ c)
    (match
      ((= c 45) #t)  ; -
      ((= c 48) #t)  ; 0
      ((= c 43) #t)  ; +
      ((= c 32) #t)  ; space
      ((= c 35) #t)  ; #
      (#t #f))))

(def %cu-fl-digit? (fn (_ c) (if (>= c 48) (<= c 57) #f)))

; --- the rules ---------------------------------------------------------------
;
; The escape rules are listed longest-match first, and the two-byte escape
; last: a tie between an octal escape of one digit and the plain escape is
; the same two bytes either way.  Each has a tag of its own, since a tag
; names the type on the base; a consumer takes every tag but lit and dir as
; an escape.  A literal run is every byte but % and the backslash.
;
; THE END TEXT IS A %.  The lexer appends it so the last token meets a
; delimiter, and a byte in the literal class would be swallowed by a trailing
; literal run and lost with it; a % ends the run, and alone at the end it is
; no token, since a directive wants a byte after it.  A format's own trailing
; % or backslash takes the appended byte and the lexer cuts it back off, so
; "a%" is the literal a and the directive %, which printf refuses by name.

(def %cu-fl-escape-rules
  (fn (_ zero?)
    (list
      (Lexer pattern (lit oct)
        (if zero?
          (list (list "\\" 1 1) (list "0" 0 1) (list "01234567" 1 3))
          (list (list "\\" 1 1) (list "01234567" 1 3))))
      (Lexer pattern (lit hex)
        (list (list "\\" 1 1) (list "x" 1 1) (list "0123456789abcdefABCDEF" 1 2)))
      (Lexer escape (lit esc) 92))))

(def %cu-fl-lexer-cell (pair () ()))
(def %cu-fl-lexer
  (fn (_)
    (if (null? (first %cu-fl-lexer-cell))
      ((fn (_ other)
         (set-first! %cu-fl-lexer-cell
           (Lexer make
             (pair
               (Lexer pattern (lit dir)
                 (list (list "%" 1 1) (list "-0+ #123456789." 0 ()) (list #t 1 1)))
               (append (%cu-fl-escape-rules #f)
                 (list (Lexer run (lit lit) other other))))
             "%")))
       ; every byte but % (37) and the backslash (92), high bytes either way
       ; the engine hands them over
       (list (pair 0 36) (pair 38 91) (pair 93 255) (pair -128 -1))))
    (first %cu-fl-lexer-cell)))

; echo -e and %b read the same escapes with the leading 0 their manuals spell
; (\0NNN), so the octal escape may open with one; and there is no %, so the
; end text is a backslash, which a literal run ends at and which alone at the
; end is no token
(def %cu-fl-arg-lexer-cell (pair () ()))
(def %cu-fl-arg-lexer
  (fn (_)
    (if (null? (first %cu-fl-arg-lexer-cell))
      ((fn (_ other)
         (set-first! %cu-fl-arg-lexer-cell
           (Lexer make
             (append (%cu-fl-escape-rules #t)
               (list (Lexer run (lit lit) other other)))
             "\\")))
       (list (pair 0 91) (pair 93 255) (pair -128 -1))))
    (first %cu-fl-arg-lexer-cell)))

; --- the directive -----------------------------------------------------------

; "%-05.2f" -> (dir #t #t 5 2 "f"). The token always opens with % and, when the
; format ran out, holds nothing else.
(def %cu-fl-directive
  (fn (_ tok)
    (def end (byte-len tok))
    (def flags
      (let ((go (fn (self i)
                  (if (>= i end) i
                    (if (%cu-fl-flag-byte? (byte-at tok i))
                      (self (+ i 1)) i)))))
        (go 1)))
    (def left?
      (%cu-fl-has-byte? tok 1 flags 45))
    (def zero?
      (%cu-fl-has-byte? tok 1 flags 48))
    (def wr (%cu-fl-number tok flags end))
    (def afterw (rest wr))
    (def pr
      (if (if (< afterw end) (= (byte-at tok afterw) 46) #f)
        (%cu-fl-number tok (+ afterw 1) end)
        (pair (- 0 1) afterw)))
    (def conv (rest pr))
    ; the token itself rides along: printf names the directive it refuses
    (list (lit dir) left? zero? (first wr) (first pr)
      (if (< conv end) (substring tok conv (+ conv 1)) "") tok)))

(def %cu-fl-has-byte?
  (fn (self tok i end b)
    (if (>= i end) #f
      (if (= (byte-at tok i) b) #t (self tok (+ i 1) end b)))))

; digits at I -> (VALUE . NEXT); -1 when there were none, which is how a caller
; tells "%5s" from "%s"
(def %cu-fl-number
  (fn (_ tok i end)
    (def go
      (fn (self k acc got)
        (if (if (< k end) (%cu-fl-digit? (byte-at tok k)) #f)
          (self (+ k 1) (+ (* acc 10) (- (byte-at tok k) 48)) #t)
          (pair (if got acc (- 0 1)) k))))
    (go i 0 #f)))

; --- the escape --------------------------------------------------------------

; What a backslash escape means.  The named ones are \a \b \f \n \r \t \v and
; \\, with \e for escape where the tool has it; a number follows \ as up to
; three octal digits, or \x and up to two hex digits.  The tools differ in
; three places, which VARIANT names:
;
;   format  printf's format: \NNN, \xHH, \" , \e, and an unknown escape as
;           written -- printf '\q' prints \q
;   arg     echo -e and printf's %b: the same, with the leading 0 their manuals
;           spell (\0NNN), and no \"
;   tr      a tr SET: \NNN only, no \x and no \e, and an unknown escape without
;           its backslash -- tr reads \q as q.  Three digits that would pass
;           255 are read as two, which is what GNU tr calls the ambiguous
;           octal escape \400
;
; \c is the caller's: it ends printf's and echo's output, and answers here as
; the empty string with a stop.

(def %cu-esc-named
  (fn (_ c variant)
    (match
      ((= c 97) 7)                                               ; a
      ((= c 98) 8)                                               ; b
      ((= c 102) 12)                                             ; f
      ((= c 110) 10)                                             ; n
      ((= c 114) 13)                                             ; r
      ((= c 116) 9)                                              ; t
      ((= c 118) 11)                                             ; v
      ((= c 92) 92)                                              ; backslash
      ((if (= c 101) (not (eq? variant (lit tr))) #f) 27)         ; e
      ((if (= c 34) (eq? variant (lit format)) #f) 34)            ; "
      (#t (- 0 1)))))

(def %cu-esc-octal? (fn (_ c) (if (>= c 48) (<= c 55) #f)))
(def %cu-esc-hex?
  (fn (_ c)
    (match
      ((if (>= c 48) (<= c 57) #f) #t)
      ((if (>= c 97) (<= c 102) #f) #t)
      (#t (if (>= c 65) (<= c 70) #f)))))
(def %cu-esc-hex-value
  (fn (_ c)
    (match
      ((<= c 57) (- c 48))
      ((>= c 97) (- c 87))
      (#t (- c 55)))))

; the digits of S from I, at most MAX of them and of base BASE: (VALUE . NEXT)
(def %cu-esc-digits
  (fn (self s i max base acc)
    (if (if (> max 0)
          (if (< i (byte-len s))
            (if (= base 8) (%cu-esc-octal? (byte-at s i))
              (%cu-esc-hex? (byte-at s i)))
            #f)
          #f)
      (self s (+ i 1) (- max 1) base
        (+ (* acc base) (%cu-esc-hex-value (byte-at s i))))
      (pair acc i))))

; The escape at I, where S holds a backslash: (TEXT NEXT STOP? BYTE).  TEXT is
; what it stands for, NEXT the index after it, STOP? true for the \c that ends
; the output, and BYTE the one byte it names, or -1 where it names other text.
; The byte is there because a NUL cannot travel in TEXT: a string's length
; stops at one, so a caller that works in bytes -- tr's set -- reads it here.
(def %cu-esc-at
  (fn (_ s i variant)
    (let ((c (if (< (+ i 1) (byte-len s)) (byte-at s (+ i 1)) (- 0 1))))
      (let ((named (if (< c 0) (- 0 1) (%cu-esc-named c variant))))
        (match
          ((< c 0) (list "\\" (+ i 1) #f 92))
          ((>= named 0) (list (%cu-b->s named) (+ i 2) #f named))
          ((if (= c 99) (not (eq? variant (lit tr))) #f)             ; c
            (list "" (+ i 2) #t (- 0 1)))
          ((%cu-esc-octal? c) (%cu-esc-number s (+ i 1) variant))
          ((if (= c 120) (not (eq? variant (lit tr))) #f)            ; x
            (%cu-esc-hex-at s (+ i 2) i))
          ((eq? variant (lit tr)) (list (%cu-b->s c) (+ i 2) #f c))
          (#t (list (substring s i (+ i 2)) (+ i 2) #f (- 0 1))))))))

; an octal escape at I, where S[I] is the first digit
(def %cu-esc-number
  (fn (_ s i variant)
    (let ((from (if (if (eq? variant (lit arg)) (= (byte-at s i) 48) #f)
                  (+ i 1) i)))                    ; \0NNN: the 0 is not a digit
      (let ((d (%cu-esc-digits s from 3 8 0)))
        (if (if (eq? variant (lit tr)) (> (first d) 255) #f)
          ; three digits past 255 are two, as GNU tr reads \400
          (let ((two (%cu-esc-digits s from 2 8 0)))
            (list (%cu-b->s (first two)) (rest two) #f (first two)))
          (let ((b (bit-and (first d) 255)))
            (list (%cu-b->s b) (rest d) #f b)))))))

; a hex escape, where I is past the x and AT the backslash: without a digit
; after it, \x is what was written
(def %cu-esc-hex-at
  (fn (_ s i at)
    (let ((d (%cu-esc-digits s i 2 16 0)))
      (if (= (rest d) i) (list (substring s at (+ at 2)) i #f (- 0 1))
        (let ((b (bit-and (first d) 255)))
          (list (%cu-b->s b) (rest d) #f b))))))

; S with its escapes decoded: (RUNS . STOPPED?), STOPPED? when a \c ended it.
; RUNS is a list of runs -- bytes and their count (cu/prims.x) -- one a
; piece: a literal token is its own text, by reference, and an escape is the
; byte it names, which may be the NUL no text carries past.  The pieces are
; written one after another rather than packed, since packing them meant
; gathering every literal byte in x.  The tokens are the arg lexer's, whose
; escapes open as echo's do; VARIANT names them to the decoder.
(def %cu-esc-run
  (fn (_ s variant)
    (def go
      (fn (self ts acc)
        (if (null? ts) (pair (reverse acc) #f)
          (let ((tag (first (first ts))) (tx (first (rest (first ts)))))
            (if (eq? tag (lit lit))
              (self (rest ts) (pair (%cu-run-of tx) acc))
              (let ((e (%cu-esc-token tag tx variant)))
                (if (%cu-nth 2 e)
                  (pair (reverse acc) #t)
                  (self (rest ts) (pair (%cu-esc-one-run e) acc)))))))))
    (if (= (byte-len s) 0) (pair () #f)
      (go ((%cu-fl-arg-lexer) read-str s) ()))))

; RUNS onto ACC, which holds runs in reverse, so the first run goes deepest
(def %cu-runs-onto
  (fn (self runs acc)
    (if (null? runs) acc (self (rest runs) (pair (first runs) acc)))))

; RUNS to FD, in order, each through the counted write
(def %cu-write-runs
  (fn (self fd runs)
    (if (null? runs) ()
      (do (file-write-run fd (first runs)) (self fd (rest runs))))))

; The escape token TX, read by the rule TAG names, decoded as %cu-esc-at
; decodes one: the tag says what the token holds, so an octal or hex escape
; goes straight to its digits.
(def %cu-esc-token
  (fn (_ tag tx variant)
    (match
      ((eq? tag (lit oct)) (%cu-esc-number tx 1 variant))
      ((eq? tag (lit hex)) (%cu-esc-hex-at tx 2 0))
      (#t (%cu-esc-at tx 0 variant)))))

; the run one escape stands for, for a caller that holds the escape alone
(def %cu-esc-one-run
  (fn (_ e)
    (if (>= (%cu-nth 3 e) 0) (pair (%cu-b->s (%cu-nth 3 e)) 1)
      (%cu-run-of (first e)))))

; the token an escape scored, as the run it stands for -- bytes and their
; count, since \0 names a NUL that no text carries past; a \c answers the stop
; its caller acts on, since a format's output ends there.  A caller that reads
; no escapes is handed the token's own text.
(def %cu-fl-escape
  (fn (_ tag tok escapes?)
    (if (not escapes?) tok
      (if (< (byte-len tok) 2) tok
        (let ((e (%cu-esc-token tag tok (lit format))))
          (if (%cu-nth 2 e) (lit stop) (%cu-esc-one-run e)))))))

; A format -> its tokens. ESCAPES? says whether a backslash means something
; here: printf says yes, a strftime format says no.
(def %cu-fmt-parse
  (fn (_ fmt escapes?)
    (def go
      (fn (self ts acc)
        (if (null? ts) (reverse acc)
          (let ((tag (first (first ts))) (tx (first (rest (first ts)))))
            (self (rest ts)
              (pair
                (match
                  ((eq? tag (lit dir)) (%cu-fl-directive tx))
                  ((eq? tag (lit lit)) tx)
                  (#t (%cu-fl-escape tag tx escapes?)))
                acc))))))
    (if (= (byte-len fmt) 0) ()
      (go ((%cu-fl-lexer) read-str fmt) ()))))

; the parts of a directive token, named
(def %cu-fmt-dir? (fn (_ t) (if (pair? t) (eq? (first t) (lit dir)) #f)))
(def %cu-fmt-left? (fn (_ t) (%cu-nth 1 t)))
(def %cu-fmt-zero? (fn (_ t) (%cu-nth 2 t)))
(def %cu-fmt-width (fn (_ t) (%cu-nth 3 t)))
(def %cu-fmt-prec (fn (_ t) (%cu-nth 4 t)))
(def %cu-fmt-conv (fn (_ t) (%cu-nth 5 t)))
(def %cu-fmt-raw (fn (_ t) (%cu-nth 6 t)))
