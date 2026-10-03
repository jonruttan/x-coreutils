; # x-coreutils -- the small tools, as applets
;
; ## cu/vi-set.x -- vi's options
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; :set and the options it sets, each busybox's (editors/vi.c, with
; FEATURE_VI_SETOPTS): autoindent, expandtab, flash, ignorecase, showmatch
; and tabstop.  An option is a bit of %vi-setops, as busybox's vi_setops.
; What each one does lives here, called from the places busybox checks it:
; char_insert for autoindent, expandtab and showmatch, indicate_error for
; flash, char_search for ignorecase.

; --- the options ------------------------------------------------------------

(def %vi-ai 1)          ; autoindent
(def %vi-et 2)          ; expandtab
(def %vi-fl 4)          ; flash for the bell
(def %vi-ic 8)          ; ignorecase
(def %vi-sm 16)         ; showmatch
(def %vi-ts 32)         ; tabstop, whose value is %vi-tabstop

(def %vi-setops 0)
(def %vi-indentcol 0)   ; the column of the autoindent just made, or 0
(def %vi-newindent -1)  ; the indent O and cc open a line with, or -1

; busybox's INIT_G: every option off, as each run starts
(def %vi-options-init!
  (fn (_)
    (set! %vi-setops 0)
    (set! %vi-indentcol 0)
    (set! %vi-newindent -1)))

(def %vi-opt? (fn (_ bit) (if (= (%vi& %vi-setops bit) 0) #f #t)))

; each name :set takes, short and long, and its bit
(def %vi-opt-names
  (list (pair "ai" %vi-ai) (pair "autoindent" %vi-ai)
        (pair "et" %vi-et) (pair "expandtab" %vi-et)
        (pair "fl" %vi-fl) (pair "flash" %vi-fl)
        (pair "ic" %vi-ic) (pair "ignorecase" %vi-ic)
        (pair "sm" %vi-sm) (pair "showmatch" %vi-sm)
        (pair "ts" %vi-ts) (pair "tabstop" %vi-ts)))

(def %vi-opt-bit
  (fn (self name opts)
    (match
      ((null? opts) 0)
      ((string=? name (first (first opts))) (rest (first opts)))
      (#t (self name (rest opts))))))

; --- :set -------------------------------------------------------------------

; :set -- with nothing or `all`, every option as it stands; else each word
; sets an option, `no` before it clears one, and ts=N sets the tab stop
(def %vi-colon-set
  (fn (_ args)
    (if (if (= (byte-len args) 0) #t (string=? args "all"))
      (%vi-status-line-bold! (%vi-options-shown))
      (%vi-set-words args 0))))

(def %vi-options-shown
  (fn (_)
    (string-concat
      (list (%vi-no %vi-ai) "autoindent " (%vi-no %vi-et) "expandtab "
            (%vi-no %vi-fl) "flash " (%vi-no %vi-ic) "ignorecase "
            (%vi-no %vi-sm) "showmatch tabstop=" (%vi-num->str %vi-tabstop)))))
(def %vi-no (fn (_ bit) (if (%vi-opt? bit) "" "no")))

(def %vi-set-words
  (fn (self args i)
    (def w (%vi-skip-word i args))
    (if (%vi< i (byte-len args))
      (do (%vi-setops! (%vi-bsub args i (%vi- w i)))
          (self args (%vi-skip-blanks w args)))
      ())))

; busybox's setops: WORD names an option, with `no` before it to clear it;
; only tabstop takes =N
(def %vi-setops!
  (fn (_ word)
    (def no (if (%vi< 1 (byte-len word)) (string=? (%vi-bsub word 0 2) "no") #f))
    (def from (if no 2 0))
    (def eq (%vi-eq-at word 0))
    (def bit (%vi-opt-bit (%vi-bsub word from (%vi- (if (%vi< eq 0) (byte-len word) eq) from))
               %vi-opt-names))
    (match
      ((= bit 0) (%vi-bad-option word))
      ((= bit %vi-ts) (%vi-set-tabstop word (if no -1 eq)))
      ((%vi< -1 eq) (%vi-bad-option word))
      (no (set! %vi-setops (if (%vi-opt? bit) (%vi- %vi-setops bit) %vi-setops)))
      (#t (set! %vi-setops (if (%vi-opt? bit) %vi-setops (%vi+ %vi-setops bit)))))))

(def %vi-eq-at
  (fn (self s i)
    (match
      ((%vi< i (byte-len s)) (if (= (byte-at s i) #\=) i (self s (%vi+ i 1))))
      (#t -1))))

(def %vi-bad-option
  (fn (_ word) (%vi-status-line-bold! (string-append "bad option: " word))))

; ts=N, N from 1 to 32; EQ is -1 when there is no =N, or for notabstop
(def %vi-set-tabstop
  (fn (_ word eq)
    (def t (if (%vi< eq 0) -1 (%vi-strtou word (%vi+ eq 1))))
    (if (if (%vi< 0 t) (%vi< t 33) #f)
      (set! %vi-tabstop t)
      (%vi-bad-option word))))

; the number at I of S as busybox's bb_strtou reads it: a digit or a letter
; first, and no digit or letter after the digits; -1 when it is not one.
; Past two digits after the leading zeros it is too big for a tab stop.
(def %vi-strtou
  (fn (_ s i)
    (def j (%vi-digits-end i s))
    (def k (%vi-zeros-end i j s))
    (match
      ((if (%vi< i (byte-len s)) (%vi-alnum? (byte-at s i)) #f)
        (match
          ((= j i) -1)
          ((if (%vi< j (byte-len s)) (%vi-alnum? (byte-at s j)) #f) -1)
          ((%vi< 2 (%vi- j k)) -1)
          (#t (%vi-num-from s k j 0))))
      (#t -1))))

(def %vi-zeros-end
  (fn (self i j s)
    (if (if (%vi< i j) (= (byte-at s i) #\0) #f) (self (%vi+ i 1) j s) i)))

(def %vi-alnum?
  (fn (_ c)
    (match
      ((%vi-digit? c) #t)
      ((%vi-in? c #\A #\Z) #t)
      (#t (%vi-in? c #\a #\z)))))

; --- flash ------------------------------------------------------------------

; busybox's flash: the screen reversed, for H hundredths of a second or until
; a key comes
(def %vi-flash
  (fn (_ h)
    (%vi-put (string-append %vi-esc "[?5h"))
    (%vi-src-ready? (%vi* h 10))
    (%vi-put (string-append %vi-esc "[?5l"))))

; --- ignorecase -------------------------------------------------------------

; the first PAT wholly in the ROOM bytes from FROM, any case, or -1.
; strcasestr stops at a NUL, so a miss goes on past the next NUL in the room;
; the text is given one after it for the call.
(def %vi-find-text-ic
  (fn (self from room pat len)
    (def at
      (%vi-found
        (%vi-with-nul-at-end
          (fn (_) (%cu-ptr-call %vi-c-strcasestr (%vi+ %vi-taddr from) pat)))))
    (def nul (if (%vi< at 0) (%vi-found (%cu-ptr-call %vi-c-memchr (%vi+ %vi-taddr from) 0 room)) -1))
    (match
      ((%vi< -1 at) (if (%vi< (%vi+ from room) (%vi+ at len)) -1 at))
      ((%vi< nul 0) -1)
      (#t (self (%vi+ nul 1) (%vi- room (%vi+ (%vi- nul from) 1)) pat len)))))

; --- showmatch --------------------------------------------------------------

; busybox's showmatching: the cursor on the bracket that P's closes, for 0.4 s
; or until a key comes; the bell when none does
(def %vi-showmatching
  (fn (_ p)
    (def q (%vi-find-pair p (%vi-byte p)))
    (def save %vi-dot)
    (if (null? q) (%vi-indicate-error)
      (do (set! %vi-dot q)
          (%vi-refresh! #f)
          (%vi-src-ready? 400)
          (set! %vi-dot save)
          (%vi-refresh! #f)))))

; --- autoindent and expandtab -----------------------------------------------

(def %vi-indent-reset (fn (_ p) (set! %vi-indentcol 0) p))

; after the byte C went in before P: showmatch for a closing bracket, and
; autoindent for a newline
(def %vi-after-insert
  (fn (_ p c undo)
    (if (if (%vi-opt? %vi-sm) (%vi-one-of? c (list #\) #\] #\})) #f)
      (%vi-showmatching (%vi- p 1))
      ())
    (if (if (%vi-opt? %vi-ai) (= c #\newline) #f)
      (%vi-autoindent p undo)
      (%vi-indent-reset p))))

; a new line's indent: the line before's, or for O and cc the indent they
; took, put before the newline unless that ends the text
(def %vi-autoindent
  (fn (_ p undo)
    (if (%vi< %vi-newindent 0)
      (%vi-indent-as-before p undo)
      (%vi-indent-by (if (= p (%vi- %vi-end 1)) p (%vi- p 1)) %vi-newindent undo))))

; a line empty but for the autoindent just made gives its indent to the new
; line after it -- a move busybox makes without a record
(def %vi-indent-as-before
  (fn (_ p undo)
    (def bol (%vi-prev-line p))
    (def len (%vi-indent-len bol))
    (def col (%vi-get-column (%vi+ bol len)))
    (if (if (%vi< 0 len) (= col %vi-indentcol) #f)
      (do (%vi-hole-delete! (%vi+ bol len) (%vi+ bol len) %vi-no-undo)
          (%vi-byte-insert! bol 10)
          p)
      (%vi-indent-by p col undo))))

; COL columns of indent in at P, in tabs and spaces or, with expandtab, all
; spaces; recorded as the autoindent while inserting
(def %vi-indent-by
  (fn (_ p col undo)
    (def ntab (if (%vi-opt? %vi-et) 0 (%vi/ col %vi-tabstop)))
    (def nspc (if (%vi-opt? %vi-et) col (%vi% col %vi-tabstop)))
    (if (= col 0) (%vi-indent-reset p)
      (do (set! %vi-indentcol (if (= %vi-cmd-mode 0) 0 col))
          (%vi-string-insert! p (string-append (%vi-run #\tab ntab) (%vi-run #\space nspc))
            undo)
          (%vi+ p (%vi+ ntab nspc))))))

; N of the byte B
(def %vi-run
  (fn (self b n)
    (match
      ((%vi< n 1) "")
      ((%vi< 32 n) (string-append (self b 32) (self b (%vi- n 32))))
      (#t (%vi-bsub (if (= b #\tab) %vi-tab-run %vi-space-run) 0 n)))))
(def %vi-tab-run (string-concat (List map (fn (_ i) (bytes->str (list 9))) (List range 0 32))))
(def %vi-space-run (string-concat (List map (fn (_ i) " ") (List range 0 32))))

; Tab with expandtab: spaces to the next tab stop, each recorded on its own
; as busybox puts them in one at a time
(def %vi-insert-expanded-tab
  (fn (_ p undo)
    (def col (%vi-get-column p))
    (def n (%vi+ (%vi- (%vi-next-tabstop col) col) 1))
    (%vi-push-each-insert! p n undo)
    (%vi-string-insert! p (%vi-run #\space n) %vi-no-undo)
    (%vi+ p n)))

(def %vi-push-each-insert!
  (fn (self p n undo)
    (if (%vi< 0 n)
      (do (%vi-undo-push-insert! p 1 undo) (self (%vi+ p 1) (%vi- n 1) undo))
      ())))

; Esc on a line that holds only the autoindent just made takes it out
(def %vi-strip-autoindent
  (fn (_ bol p undo)
    (def len (%vi-indent-len bol))
    (match
      ((if (%vi-opt? %vi-ai) (%vi< 0 len) #f)
        (if (if (= (%vi-get-column (%vi+ bol len)) %vi-indentcol)
              (= (byte-at %vi-text (%vi+ bol len)) #\newline)
              #f)
          (do (%vi-hole-delete! bol (%vi- (%vi+ bol len) 1) undo) bol)
          p))
      (#t p))))

; after ^D: a line that holds only its autoindent keeps it as the autoindent,
; at its new width
(def %vi-dedent-kept
  (fn (_ p bol)
    (if (match
          ((if (%vi-opt? %vi-ai) #f #t) #f)
          ((= %vi-indentcol 0) #f)
          (#t (= (%vi+ bol (%vi-indent-len bol)) (%vi-end-line p))))
      (do (set! %vi-indentcol (%vi-get-column p)) p)
      (%vi-indent-reset p))))

; THUNK's answer, with a NUL after the text while it runs: the byte there is
; left as busybox would leave it, and put back after
(def %vi-with-nul-at-end
  (fn (_ thunk)
    (def was (%vi& (byte-at %vi-text %vi-end) 255))
    (%vi-ptr-set! %vi-tptr %vi-end 0 1)
    (def r (thunk))
    (%vi-ptr-set! %vi-tptr %vi-end was 1)
    r))
