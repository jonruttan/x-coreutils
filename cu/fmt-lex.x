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
    (list (lit dir) left? zero? (first wr) (first pr)
      (if (< conv end) (substring tok conv (+ conv 1)) ""))))

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

(def %cu-fl-t-esc
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (= chr 92) (%seq (%score-set score 1 buffer) %cu-fl-esc-tail) ())))
    (pair (lit read)
      (fn (_ . args) (%cu-fl-escape (%cu-fl-token (first args)))))))

(def %cu-fl-esc-tail ())
(set! %cu-fl-esc-tail
  (fn (_ buffer score chr) (%score-set score 1 buffer)))

(%cu-fl-type! "CU-FMT-ESC" %cu-fl-t-esc)

(def %cu-fl-escape
  (fn (_ tok)
    (if (not (first %cu-fl-escapes))
      tok
      (if (< (byte-len tok) 2)
        tok
        (let ((e (byte-at tok 1)))
          (match
            ((= e 110) "\n")
            ((= e 116) "\t")
            ((= e 114) "\r")
            ((= e 92) "\\")
            (#t (substring tok 1 2))))))))

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
