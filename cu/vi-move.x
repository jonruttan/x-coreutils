; # x-coreutils -- the small tools, as applets
;
; ## cu/vi-move.x -- vi's motions
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The commands that move the cursor or the screen and change nothing: words,
; characters searched for on the line, lines by number and by place on the
; screen, the matching bracket, paragraphs, and scrolling.  Each is busybox's
; (editors/vi.c), over cu/vi.x's buffer.  The classes of a byte are the C
; locale's: busybox reads the text as bytes, so a byte past 0x7F is none of
; space, word or punctuation.

; --- classes of a byte ------------------------------------------------------

; the byte at P, or 0 outside the text
(def %vi-byte
  (fn (_ p)
    (if (%vi< p 0) 0
      (if (%vi< p %vi-end) (%vi& (byte-at %vi-text p) 255) 0))))

; isalnum or `_`: a byte of a word
(def %vi-word?
  (fn (_ c)
    (match
      ((= c #\_) #t)
      ((%vi< c #\0) #f)
      ((if (%vi< #\9 c) #f #t) #t)
      ((%vi< c #\A) #f)
      ((if (%vi< #\Z c) #f #t) #t)
      ((%vi< c #\a) #f)
      (#t (if (%vi< #\z c) #f #t)))))

; ispunct: printable, and neither a space nor a letter or digit
(def %vi-punct?
  (fn (_ c)
    (match
      ((%vi< c #\!) #f)
      ((%vi< c #\0) #t)
      ((if (%vi< #\9 c) #f #t) #f)
      ((%vi< c #\A) #t)
      ((if (%vi< #\Z c) #f #t) #f)
      ((%vi< c #\a) #t)
      ((if (%vi< #\z c) #f #t) #f)
      (#t (if (%vi< #\~ c) #f #t)))))

; --- skip_thing -------------------------------------------------------------

; busybox's st_test: whether to go on past P for TYPE going DIR, and the byte
; that was tested, as (GO . BYTE).  The types: 1 up to the byte before a
; space, 2 to a space, 3 over spaces, 4 to the end of punctuation, 5 to the
; end of a word.
(def %vi-st-test
  (fn (_ p type dir)
    (def c0 (%vi-byte p))
    (def ci (%vi-byte (%vi+ p dir)))
    (match
      ((= type 1) (pair (if (%vi-space? ci) (= ci #\newline) #t) ci))
      ((= type 2) (pair (if (%vi-space? c0) (= c0 #\newline) #t) c0))
      ((= type 3) (pair (%vi-space? c0) c0))
      ((= type 4) (pair (%vi-punct? ci) ci))
      (#t (pair (%vi-word? ci) ci)))))

; busybox's skip_thing: from P, DIR a byte at a time while TYPE's test holds,
; crossing no more than LINECNT - 1 newlines and never past the text
(def %vi-skip-thing
  (fn (self p linecnt dir type)
    (def t (%vi-st-test p type dir))
    (match
      ((if (first t) #f #t) p)
      ((if (= (rest t) #\newline) (%vi< (%vi- linecnt 1) 1) #f) p)
      ((if (%vi< dir 0) #f (%vi< (%vi- %vi-end 2) p)) p)
      ((if (%vi< dir 0) (%vi< p 1) #f) p)
      (#t (self (%vi+ p dir) (if (= (rest t) #\newline) (%vi- linecnt 1) linecnt) dir type)))))

; --- words ------------------------------------------------------------------

; w: over the word or punctuation under the cursor, then over the spaces after
(def %vi-cmd-w
  (fn (_)
    (%vi-repeat
      (fn (_)
        (def c (%vi-byte %vi-dot))
        (match
          ((%vi-word? c) (set! %vi-dot (%vi-skip-thing %vi-dot 1 1 5)))
          ((%vi-punct? c) (set! %vi-dot (%vi-skip-thing %vi-dot 1 1 4)))
          (#t ()))
        (if (%vi< %vi-dot (%vi- %vi-end 1)) (set! %vi-dot (%vi+ %vi-dot 1)) ())
        (if (%vi-space? (%vi-byte %vi-dot))
          (set! %vi-dot (%vi-skip-thing %vi-dot 2 1 3))
          ())))))

; b and e: a byte back or on, over spaces, then to the start or the end of the
; word or punctuation found there
(def %vi-cmd-be
  (fn (_ c)
    (def dir (if (= c #\b) -1 1))
    (%vi-repeat
      (fn (_)
        (def to (%vi+ %vi-dot dir))
        (if (if (%vi< to 0) #t (%vi< (%vi- %vi-end 1) to)) (set! %vi-cmdcnt 0)
          (%vi-be-step to dir (if (= c #\e) 2 1)))))))

(def %vi-be-step
  (fn (_ to dir lines)
    (set! %vi-dot to)
    (if (%vi-space? (%vi-byte %vi-dot))
      (set! %vi-dot (%vi-skip-thing %vi-dot lines dir 3))
      ())
    (def c (%vi-byte %vi-dot))
    (match
      ((%vi-word? c) (set! %vi-dot (%vi-skip-thing %vi-dot 1 dir 5)))
      ((%vi-punct? c) (set! %vi-dot (%vi-skip-thing %vi-dot 1 dir 4)))
      (#t ()))))

; W, B and E: the same by blank-delimited words
(def %vi-cmd-wbe-blank
  (fn (_ c)
    (def dir (if (= c #\B) -1 1))
    (%vi-repeat
      (fn (_)
        (if (if (= c #\W) #t (%vi-space? (%vi-byte (%vi+ %vi-dot dir))))
          (do (set! %vi-dot (%vi-skip-thing %vi-dot 1 dir 2))
              (set! %vi-dot (%vi-skip-thing %vi-dot 2 dir 3)))
          ())
        (if (= c #\W) () (set! %vi-dot (%vi-skip-thing %vi-dot 1 dir 1)))))))

; --- characters on the line -------------------------------------------------

(def %vi-last-search-char 0)
(def %vi-last-search-cmd 0)

; f F t T: the next or last C on the line, or next to it
(def %vi-cmd-find
  (fn (_ cmd)
    (set! %vi-last-search-char (%vi-get-one-char))
    (set! %vi-last-search-cmd cmd)
    (%vi-dot-to-char cmd)))

; ; and , -- the last search again, or the other way
(def %vi-cmd-refind
  (fn (_ c)
    (%vi-dot-to-char
      (if (= c #\,) (%vi^ %vi-last-search-cmd 32) %vi-last-search-cmd))))
(def %vi^ (prim-ref (lit int) (lit ^)))

; busybox's dot_to_char: COUNT times to the searched-for byte, never past the
; line; t stops before it and T after
(def %vi-dot-to-char
  (fn (_ cmd)
    (if (= %vi-last-search-char 0) ()
      (%vi-to-char-from %vi-dot (if (%vi< cmd #\a) -1 1) cmd))))

(def %vi-to-char-from
  (fn (_ q dir cmd)
    (def found (%vi-char-scan (%vi+ q dir) dir))
    (match
      ((null? found) (do (set! %vi-cmdcnt 0) (%vi-indicate-error)))
      ((%vi< 1 %vi-cmdcnt)
        (do (set! %vi-cmdcnt (%vi- %vi-cmdcnt 1)) (%vi-to-char-from found dir cmd)))
      (#t (do (set! %vi-cmdcnt 0) (set! %vi-dot found) (%vi-to-char-land cmd))))))

(def %vi-to-char-land
  (fn (_ cmd)
    (match
      ((= cmd #\t) (%vi-dot-left!))
      ((= cmd #\T) (%vi-dot-right!))
      (#t ()))))

; the next Q going DIR that holds the searched-for byte, or nil at the edge of
; the text or of the line
(def %vi-char-scan
  (fn (self q dir)
    (match
      ((if (%vi< dir 0) (%vi< q 0) (%vi< (%vi- %vi-end 1) q)) ())
      ((= (%vi-byte q) #\newline) ())
      ((= (%vi-byte q) (%vi& %vi-last-search-char 255)) q)
      (#t (self (%vi+ q dir) dir)))))

; --- lines ------------------------------------------------------------------

; G: line COUNT, or the last; gg: line COUNT, or the first
(def %vi-cmd-G
  (fn (_)
    (set! %vi-dot (if (%vi< 0 %vi-cmdcnt) (%vi-find-line %vi-cmdcnt) (%vi- %vi-end 1)))
    (%vi-dot-begin!)
    (%vi-dot-skip-over-ws!)))

(def %vi-cmd-g
  (fn (_)
    (def c (%vi-get-one-char))
    (if (= c #\g)
      (do (if (= %vi-cmdcnt 0) (set! %vi-cmdcnt 1) ()) (%vi-cmd-G))
      (do (%vi-not-implemented (bytes->str (list 103 (if (%vi< c 0) 42 (%vi& c 255)))))
          (set! %vi-cmd-error #t)))))

; H and L: COUNT lines from the top or the bottom of the screen
(def %vi-cmd-HL
  (fn (_ c)
    (set! %vi-dot (if (= c #\H) %vi-screenbegin (%vi-end-screen)))
    (if (%vi< (%vi- %vi-rows 1) %vi-cmdcnt) (set! %vi-cmdcnt (%vi- %vi-rows 1)) ())
    (%vi-HL-steps (if (= c #\H) %vi-dot-next! %vi-dot-prev!))
    (%vi-dot-begin!)
    (%vi-dot-skip-over-ws!)))

(def %vi-HL-steps
  (fn (self step)
    (set! %vi-cmdcnt (%vi- %vi-cmdcnt 1))
    (if (%vi< 0 %vi-cmdcnt) (do (step) (self step)) ())))

; M: the middle line of the screen
(def %vi-cmd-M
  (fn (_)
    (set! %vi-dot (%vi-next-lines %vi-screenbegin (%vi/ (%vi- %vi-rows 1) 2)))
    (%vi-dot-skip-over-ws!)))

(def %vi-cmd-caret
  (fn (_) (%vi-dot-begin!) (%vi-dot-skip-over-ws!)))

; |: column COUNT
(def %vi-cmd-bar
  (fn (_) (set! %vi-dot (%vi-move-to-col %vi-dot (%vi- %vi-cmdcnt 1)))))

; --- the matching bracket ---------------------------------------------------

; %: the first bracket from the cursor to the end of the line, and its match
(def %vi-cmd-percent
  (fn (_)
    (%vi-percent-from %vi-dot)))

(def %vi-percent-from
  (fn (self q)
    (def c (%vi-byte q))
    (match
      ((if (%vi< q %vi-end) (= c #\newline) #t) (%vi-indicate-error))
      ((%vi-bracket? c) (%vi-percent-at q c))
      (#t (self (%vi+ q 1))))))

(def %vi-percent-at
  (fn (_ q c)
    (def p (%vi-find-pair q c))
    (if (null? p) (%vi-indicate-error) (set! %vi-dot p))))

(def %vi-bracket? (fn (_ c) (%vi-one-of? c (list #\( #\) #\[ #\] #\{ #\}))))

; busybox's find_pair: the bracket that closes or opens C at P, counting
; levels, or nil
(def %vi-find-pair
  (fn (_ p c)
    (def open? (%vi-one-of? c (list #\( #\[ #\{)))
    (%vi-pair-walk (%vi+ p (if open? 1 -1)) (if open? 1 -1) c (%vi-mate c) 1)))

(def %vi-mate
  (fn (_ c)
    (match
      ((= c #\() #\)) ((= c #\)) #\()
      ((= c #\[) #\]) ((= c #\]) #\[)
      ((= c #\{) #\})
      (#t #\{))))

(def %vi-pair-walk
  (fn (self p dir c mate level)
    (def b (%vi-byte p))
    (match
      ((if (%vi< p 0) #t (%vi< (%vi- %vi-end 1) p)) ())
      ((= b c) (self (%vi+ p dir) dir c mate (%vi+ level 1)))
      ((= b mate) (if (= level 1) p (self (%vi+ p dir) dir c mate (%vi- level 1))))
      (#t (self (%vi+ p dir) dir c mate level)))))

; --- paragraphs -------------------------------------------------------------

; { and }: back or on to the next empty line after some text, COUNT times; at
; the start or the end of the text, stay there
(def %vi-cmd-paragraph
  (fn (_ c)
    (def dir (if (= c #\}) 1 -1))
    (%vi-paragraph-count dir)))

(def %vi-paragraph-count
  (fn (self dir)
    (if (%vi-paragraph-step dir #t)
      (do (set! %vi-cmdcnt (%vi- %vi-cmdcnt 1))
          (if (%vi< 0 %vi-cmdcnt) (self dir) ()))
      (set! %vi-cmdcnt 0))))

; one paragraph: answers whether one was found
(def %vi-paragraph-step
  (fn (self dir skip)
    (match
      ((if (%vi< 0 dir) (%vi< %vi-dot (%vi- %vi-end 1)) (%vi< 0 %vi-dot)) (%vi-paragraph-at self dir skip))
      (#t #f))))

(def %vi-paragraph-at
  (fn (_ step dir skip)
    (def blank? (if (= (%vi-byte %vi-dot) #\newline) (= (%vi-byte (%vi+ %vi-dot dir)) #\newline) #f))
    (match
      ((if blank? (if skip #f #t) #f)
        (do (if (%vi< 0 dir) (set! %vi-dot (%vi+ %vi-dot 1)) ()) #t))
      (#t (do (set! %vi-dot (%vi+ %vi-dot dir)) (step dir (if blank? skip #f)))))))

; --- scrolling --------------------------------------------------------------

; busybox's dot_scroll: the screen CNT lines up or down, the cursor kept on it
(def %vi-dot-scroll
  (fn (_ cnt dir)
    (%vi-undo-queue-commit!)
    (set! %vi-screenbegin
      (if (%vi< dir 0) (%vi-prev-lines %vi-screenbegin cnt) (%vi-next-lines %vi-screenbegin cnt)))
    (if (%vi< %vi-dot %vi-screenbegin) (set! %vi-dot %vi-screenbegin) ())
    (def q (%vi-end-screen))
    (if (%vi< q %vi-dot) (set! %vi-dot (%vi-begin-line q)) ())
    (%vi-dot-skip-over-ws!)))

; ^B ^F and the page keys by a screen, ^U ^D by half, ^Y ^E by a line
(def %vi-cmd-scroll
  (fn (_ c)
    (def page (%vi- %vi-rows 2))
    (match
      ((%vi-one-of? c (list (%vi-ctrl #\B) %vi-key-page-up)) (%vi-dot-scroll page -1))
      ((%vi-one-of? c (list (%vi-ctrl #\F) %vi-key-page-down)) (%vi-dot-scroll page 1))
      ((= c (%vi-ctrl #\U)) (%vi-dot-scroll (%vi/ page 2) -1))
      ((= c (%vi-ctrl #\D)) (%vi-dot-scroll (%vi/ page 2) 1))
      ((= c (%vi-ctrl #\Y)) (%vi-dot-scroll 1 -1))
      (#t (%vi-dot-scroll 1 1)))))

; z. z- z<anything>: the cursor's line to the middle, the bottom or the top
(def %vi-cmd-z-scroll
  (fn (_)
    (def c (%vi-get-one-char))
    (set! %vi-screenbegin (%vi-begin-line %vi-dot))
    (%vi-dot-scroll
      (match ((= c #\.) (%vi/ (%vi- %vi-rows 2) 2)) ((= c #\-) (%vi- %vi-rows 2)) (#t 0))
      -1)))
