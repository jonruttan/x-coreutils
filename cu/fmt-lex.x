; # x-coreutils -- the small tools, as applets
;
; ## cu/fmt-lex.x -- one reader for every format string
;
; @description printf's %s, date's %Y, stat's %n and the escapes all have the
;   same shape; this reads them once so each applet keeps only its table.
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

(def %cu-fl-types (pair () ()))
(def %cu-fl-type!
  (fn (_ nm hs)
    (set-first! %cu-fl-types (pair (pair nm hs) (first %cu-fl-types)))))

(def %cu-fl-raw (pair () ()))

; Escapes are printf's, not every format's; a caller that does not want them
; gets the backslash and the character as written.
(def %cu-fl-escapes (pair #f ()))

(def %cu-fl-read-string (prim-ref (lit tok) (lit read-str)))
(def %cu-fl-token (prim-ref (lit buf) (lit tok)))

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

; --- the directive -----------------------------------------------------------
;
; One state consumes flags, width and precision, stopping at the conversion
; character -- any byte that is none of those. The score is set there,
; including it.

(def %cu-fl-pct-body ())
(set! %cu-fl-pct-body
  (fn (_ buffer score chr)
    (if (if (%cu-fl-flag-byte? chr) #t
          (if (%cu-fl-digit? chr) #t (= chr 46)))      ; .
      %cu-fl-pct-body
      (%score-set score 1 buffer))))

(def %cu-fl-t-pct
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (= chr 37)
          ; a % alone is still a match; read decides what it meant
          (%seq (%score-set score 1 buffer) %cu-fl-pct-body)
          ())))
    (pair (lit read)
      (fn (_ . args) (%cu-fl-directive (%cu-fl-token (first args)))))))
(%cu-fl-type! "CU-FMT-PCT" %cu-fl-t-pct)

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

; S with its escapes decoded: (RUN . STOPPED?), STOPPED? when a \c ended it.
; The run is bytes and their count (cu/prims.x) because \0 names a NUL, which
; no text can carry past: the bytes are gathered as the reader names them and
; packed once.
(def %cu-esc-run
  (fn (_ s variant) (%cu-esc-walk s 0 variant () 0)))

(def %cu-esc-walk
  (fn (self s i variant acc n)
    (match
      ((>= i (byte-len s)) (pair (%cu-run-bytes (reverse acc) n) #f))
      ((not (= (byte-at s i) 92))
        (self s (+ i 1) variant (pair (byte-at s i) acc) (+ n 1)))
      (#t
        (let ((e (%cu-esc-at s i variant)))
          (let ((next (%cu-esc-onto e acc)))
            (if (%cu-nth 2 e)
              (pair (%cu-run-bytes (reverse (first next)) (+ n (rest next))) #t)
              (self s (%cu-nth 1 e) variant (first next) (+ n (rest next))))))))))

; the bytes of the escape E onto ACC, which holds the run in reverse: the one
; byte E names, or the bytes of the text it stands for where it names none.
; Answers (ACC . HOW-MANY-MORE).
(def %cu-esc-onto
  (fn (_ e acc)
    (if (>= (%cu-nth 3 e) 0) (pair (pair (%cu-nth 3 e) acc) 1)
      (%cu-bytes-onto (first e) 0 acc 0))))

(def %cu-bytes-onto
  (fn (self s i acc n)
    (if (>= i (byte-len s)) (pair acc n)
      (self s (+ i 1) (pair (byte-at s i) acc) (+ n 1)))))

; the run one escape stands for, for a caller that holds the escape alone
(def %cu-esc-one-run
  (fn (_ e)
    (if (>= (%cu-nth 3 e) 0) (pair (%cu-b->s (%cu-nth 3 e)) 1)
      (%cu-run-of (first e)))))

; --- the escape, as the reader scores it --------------------------------------
;
; The token runs past the backslash for a number: three octal digits at most,
; or x and two hex digits at most.  Each state marks a match and goes on, so
; the longest one wins and \x with no digit after it is still the two bytes it
; was written as.

(def %cu-fl-t-esc
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (= chr 92) (%seq (%score-set score 1 buffer) %cu-fl-esc-tail) ())))
    (pair (lit read)
      (fn (_ . args) (%cu-fl-escape (%cu-fl-token (first args)))))))

(def %cu-fl-esc-tail ())
(def %cu-fl-esc-oct2 ())
(def %cu-fl-esc-oct3 ())
(def %cu-fl-esc-hex1 ())
(def %cu-fl-esc-hex2 ())
(set! %cu-fl-esc-tail
  (fn (_ buffer score chr)
    (match
      ((%cu-esc-octal? chr) (%seq (%score-set score 1 buffer) %cu-fl-esc-oct2))
      ((= chr 120) (%seq (%score-set score 1 buffer) %cu-fl-esc-hex1))   ; x
      (#t (%score-set score 1 buffer)))))
(set! %cu-fl-esc-oct2
  (fn (_ buffer score chr)
    (if (%cu-esc-octal? chr)
      (%seq (%score-set score 1 buffer) %cu-fl-esc-oct3)
      (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
(set! %cu-fl-esc-oct3
  (fn (_ buffer score chr)
    (if (%cu-esc-octal? chr) (%score-set score 1 buffer)
      (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
(set! %cu-fl-esc-hex1
  (fn (_ buffer score chr)
    (if (%cu-esc-hex? chr) (%seq (%score-set score 1 buffer) %cu-fl-esc-hex2)
      (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
(set! %cu-fl-esc-hex2
  (fn (_ buffer score chr)
    (if (%cu-esc-hex? chr) (%score-set score 1 buffer)
      (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))

(%cu-fl-type! "CU-FMT-ESC" %cu-fl-t-esc)

; the token an escape scored, as the run it stands for -- bytes and their
; count, since \0 names a NUL that no text carries past; a \c answers the stop
; its caller acts on, since a format's output ends there.  A caller that reads
; no escapes is handed the token's own text.
(def %cu-fl-escape
  (fn (_ tok)
    (if (not (first %cu-fl-escapes)) tok
      (if (< (byte-len tok) 2) tok
        (let ((e (%cu-esc-at tok 0 (lit format))))
          (if (%cu-nth 2 e) (lit stop) (%cu-esc-one-run e)))))))

; --- the literal run ---------------------------------------------------------

(def %cu-fl-plain?
  (fn (_ c) (if (= c 37) #f (not (= c 92)))))

(def %cu-fl-lit-more ())
(set! %cu-fl-lit-more
  (fn (_ buffer score chr)
    (if (%cu-fl-plain? chr)
      %cu-fl-lit-more
      (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))

(def %cu-fl-t-lit
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (%cu-fl-plain? chr)
          (%seq (%score-set score 1 buffer) %cu-fl-lit-more)
          ())))
    (pair (lit read)
      (fn (_ . args) (%cu-fl-token (first args))))))
(%cu-fl-type! "CU-FMT-LIT" %cu-fl-t-lit)

(def %cu-fl-base!
  (fn (_)
    (if (null? (first %cu-fl-raw))
      (let ((b (Base make-tok)))
        (do
          ((fn (self l)
             (if (null? l) ()
               (do (self (rest l))
                   (Base make-type b (first (first l)) (rest (first l))))))
           (first %cu-fl-types))
          (set-first! %cu-fl-raw (Base raw-of b))
          (first %cu-fl-raw)))
      (first %cu-fl-raw))))

; A format -> its tokens. ESCAPES? says whether a backslash means something
; here: printf says yes, a strftime format says no.
(def %cu-fmt-parse
  (fn (_ fmt escapes?)
    (do
      (set-first! %cu-fl-escapes escapes?)
      (if (= (byte-len fmt) 0) ()
        (%cu-fl-read-string (%cu-fl-base!) fmt)))))

; the parts of a directive token, named
(def %cu-fmt-dir? (fn (_ t) (if (pair? t) (eq? (first t) (lit dir)) #f)))
(def %cu-fmt-left? (fn (_ t) (%cu-nth 1 t)))
(def %cu-fmt-zero? (fn (_ t) (%cu-nth 2 t)))
(def %cu-fmt-width (fn (_ t) (%cu-nth 3 t)))
(def %cu-fmt-prec (fn (_ t) (%cu-nth 4 t)))
(def %cu-fmt-conv (fn (_ t) (%cu-nth 5 t)))
(def %cu-fmt-raw (fn (_ t) (%cu-nth 6 t)))
