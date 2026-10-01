; # x-coreutils -- the small tools, as applets
;
; ## cu/vi-edit.x -- vi's operators, registers and marks
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The commands that change the text by a range or a register: d c y < > over
; any motion, p P, "x, the marks m and ', and r R J ~ D C s U.  Each is
; busybox's (editors/vi.c).  A range is found by running its motion as a
; command of its own, as busybox's find_range runs do_cmd, so every motion
; the editor knows is a range too.  A register holds its text and whether
; that is part of a line (0), whole lines (1) or text across lines (2).

; --- ranges -----------------------------------------------------------------

; busybox's at_eof: S at the last byte, or the one before a final newline
(def %vi-at-eof?
  (fn (_ s)
    (if (= s (%vi- %vi-end 1)) #t
      (if (= s (%vi- %vi-end 2)) (= (%vi-byte (%vi+ s 1)) #\newline) #f))))

; busybox's find_range: the motion typed after the operator CMD run from the
; cursor, answering (TYPE P . Q) -- the range P through Q and its register
; type -- or nil when the motion made none
(def %vi-find-range
  (fn (_ cmd)
    (def p %vi-dot)
    (def c (if (= cmd #\Y) 121 (%vi-get-motion-char)))
    (def type (%vi-range-motion cmd c p))
    (if (= type -1)
      (do (if (= c #\escape) () (%vi-indicate-error)) ())
      (%vi-range-ends type c (%vi-min p %vi-dot) (%vi-max p %vi-dot)))))

; the motion C run for the operator CMD from P, answering the range's type,
; -1 for none; the cursor is left at the range's other end
(def %vi-range-motion
  (fn (_ cmd c p)
    (match
      ((if (if (= cmd #\Y) #t (= cmd c)) (%vi-one-of? c (list #\c #\d #\y #\> #\<)) #f)
        (%vi-range-lines))
      ((%vi-one-of? c (list #\^ #\% #\$ #\0 #\b #\B #\e #\E #\f #\F #\t #\T #\h #\n #\N #\/ #\?
                            #\| #\{ #\} #\backspace #\delete))
        (do (%vi-do-cmd c)
            (if (= p %vi-dot) -1 (if (%vi-one-of? c (list #\n #\N #\/ #\?)) 2 0))))
      ((%vi-one-of? c (list #\w #\W)) (%vi-range-words cmd c p))
      ((%vi-one-of? c (list #\G #\H #\L #\+ #\- #\g #\j #\k #\' #\return #\newline))
        (do (%vi-do-cmd c) (if %vi-cmd-error -1 1)))
      ((%vi-one-of? c (list #\space #\l)) (%vi-range-right c p))
      (#t -1))))

; dd cc yy << >>: whole lines, COUNT of them
(def %vi-range-lines
  (fn (_)
    (set! %vi-cmdcnt (%vi- %vi-cmdcnt 1))
    (if (%vi< 0 %vi-cmdcnt)
      (do (%vi-do-cmd 106) (if %vi-cmd-error -1 1))
      1)))

; w and W as a range: up to the next word, the blanks after the last word left
; out, and for all but c the blanks up to a newline too
(def %vi-range-words
  (fn (_ cmd c p)
    (%vi-do-cmd c)
    (if (if (%vi< p %vi-dot)
          (if (%vi-at-eof? %vi-dot) (if (= c #\w) (%vi-punct? (%vi-byte %vi-dot)) #f) #t)
          #f)
      (set! %vi-dot (%vi- %vi-dot 1))
      ())
    (def t (%vi-words-back p %vi-dot))
    (if (match ((= cmd #\c) #f) ((= %vi-dot t) #f) (#t (if (= (%vi-byte %vi-dot) #\newline) #f #t)))
      (set! %vi-dot t)
      ())
    2))

; the cursor back over spaces toward P; answers the place just before the
; last newline passed, or where it started
(def %vi-words-back
  (fn (self p t)
    (def c (%vi-byte %vi-dot))
    (if (if (%vi< p %vi-dot) (%vi-space? c) #f)
      (do (set! %vi-dot (%vi- %vi-dot 1))
          (self p (if (= c #\newline) %vi-dot t)))
      t)))

; l and space as a range: COUNT bytes, the last left out when the line ended
; first
(def %vi-range-right
  (fn (_ c p)
    (def n (if (= %vi-cmdcnt 0) 1 %vi-cmdcnt))
    (%vi-do-cmd c)
    (if (= n (%vi- %vi-dot p)) (set! %vi-dot (%vi- %vi-dot 1)) ())
    0))

; the ends of a range from P to Q: a motion that stops short of its target
; leaves the target out, and { } take whole lines when they start and end a
; line
(def %vi-range-ends
  (fn (_ type c p q)
    (match
      ((if (%vi< p q)
         (%vi-one-of? c (list #\^ #\0 #\b #\B #\F #\T #\h #\n #\N #\/ #\? #\| #\backspace #\delete))
         #f)
        (pair type (pair p (%vi- q 1))))
      ((if (%vi< p q) (%vi-one-of? c (list #\{ #\})) #f) (%vi-range-braces p q))
      (#t (pair type (pair p q))))))

(def %vi-range-braces
  (fn (_ p q)
    (def type
      (if (if (= p (%vi-begin-line p)) (if (= (%vi-byte q) #\newline) #t (%vi-at-eof? q)) #f) 1 2))
    (def q1 (if (%vi-at-eof? q) q (%vi- q 1)))
    (pair type
      (pair p (if (if (%vi-at-eof? q) #f (if (%vi< p q1) (if (= p (%vi-begin-line p)) #f #t) #f))
                (%vi- q1 1)
                q1)))))

; --- c d y ------------------------------------------------------------------

; c, d, y and Y over the motion typed next: the range into the register, and
; out of the text but for y; whole lines leave the cursor at their first
; non-blank (d), where the range began (y), or on a new empty line (c).  c
; goes on into insert mode.
(def %vi-cmd-cdy
  (fn (_ c)
    (def yanks %vi-yank-count)
    (def range (%vi-find-range c))
    (if (null? range) (%vi-end-cmd-q!)
      (%vi-cdy-range c (first range) (first (rest range)) (rest (rest range)) yanks))))

(def %vi-cdy-range
  (fn (_ c type p q yanks)
    (def whole? (= type 1))
    (def from (if whole? (%vi-begin-line p) p))
    (def to (if whole? (%vi-end-line q) q))
    (if (if whole? (= c #\c) #f)
      (set! %vi-newindent (%vi-get-column (%vi+ from (%vi-indent-len from))))
      ())
    (set! %vi-dot
      (%vi-yank-delete from to type (if (%vi-one-of? c (list #\y #\Y)) #f #t) %vi-allow-undo))
    (if whole? (%vi-cdy-whole c p) ())
    (match
      ((= c #\c) (%vi-start-insert!))
      (#t (do (if (= yanks %vi-yank-count) ()
                (%vi-yank-status! (if (= c #\d) "Delete" "Yank")
                  (first (%vi-reg %vi-ydreg)) 1))
              (%vi-end-cmd-q!))))))

(def %vi-cdy-whole
  (fn (_ c save)
    (match
      ((= c #\c)
        (do (set! %vi-cmd-mode 1)
            (set! %vi-dot (%vi-char-insert %vi-dot 10 %vi-allow-undo-chain))
            (if (if (= %vi-dot (%vi- %vi-end 1)) #t (%vi-opt? %vi-ai)) () (%vi-dot-prev!))))
      ((= c #\d) (do (%vi-dot-begin!) (%vi-dot-skip-over-ws!)))
      (#t (set! %vi-dot save)))))

; --- < and > ----------------------------------------------------------------

; < and > over the lines of the motion typed next: a tab put before each line
; that has text, or a tab or up to a tab stop of spaces taken from the front
(def %vi-cmd-shift
  (fn (_ c)
    (def line (%vi-lines-before (%vi+ (%vi-end-line %vi-dot) 1)))
    (def range (%vi-find-range c))
    (if (null? range) ()
      (%vi-shift-lines c (%vi-begin-line (first (rest range)))
        (%vi-count-lines (first (rest range)) (rest (rest range))) (list %vi-allow-undo)))
    (if (null? range) ()
      (do (set! %vi-dot (%vi-find-line line)) (%vi-dot-skip-over-ws!)))
    (%vi-end-cmd-q!)))

; each line's change chained to the one before; UNDO is a cell, as busybox's
; allow_undo is one variable for the whole command
(def %vi-shift-lines
  (fn (self c p n undo)
    (if (%vi< 0 n)
      (do (if (= c #\<) (%vi-shift-left p undo) (%vi-shift-right p undo))
          (set-first! undo %vi-allow-undo-chain)
          (self c (%vi-next-line p) (%vi- n 1) undo))
      ())))

(def %vi-shift-left
  (fn (_ p undo)
    (match
      ((= (%vi-byte p) #\tab) (%vi-hole-delete! p p (first undo)))
      ((= (%vi-byte p) #\space) (%vi-unindent p 0 undo))
      (#t ()))))

(def %vi-unindent
  (fn (self p j undo)
    (if (if (= (%vi-byte p) #\space) (%vi< j %vi-tabstop) #f)
      (do (%vi-hole-delete! p p (first undo))
          (set-first! undo %vi-allow-undo-chain)
          (self p (%vi+ j 1) undo))
      ())))

(def %vi-shift-right
  (fn (_ p undo)
    (if (= p (%vi-end-line p)) () (%vi-char-insert p 9 (first undo)))))

; --- p and P ----------------------------------------------------------------

; p and P: the register COUNT times after or before the cursor -- whole lines
; below or above the cursor's line
(def %vi-cmd-put
  (fn (_ c)
    (def r (%vi-reg %vi-ydreg))
    (if (null? r)
      (%vi-status-line-bold!
        (string-append "Nothing in register " (bytes->str (list (%vi-what-reg)))))
      (%vi-put-reg c (first r) (rest r)))))

(def %vi-put-reg
  (fn (_ c s type)
    (def times (if (= %vi-cmdcnt 0) 1 %vi-cmdcnt))
    (if (= type 1) (%vi-put-whole-at c) (if (= c #\p) (%vi-dot-right!) ()))
    (def cnt
      (if (if (= type 1) #t (%vi-has-newline? s)) 0 (%vi- (%vi* times (byte-len s)) 1)))
    (def undo (list %vi-allow-undo))
    (%vi-repeat
      (fn (_)
        (%vi-string-insert! %vi-dot s (first undo))
        (set-first! undo %vi-allow-undo-chain)))
    (set! %vi-dot (%vi+ %vi-dot cnt))
    (%vi-dot-skip-over-ws!)
    (%vi-yank-status! "Put" s times)
    (%vi-end-cmd-q!)))

(def %vi-put-whole-at
  (fn (_ c)
    (match
      ((= c #\P) (%vi-dot-begin!))
      ((= (%vi-end-line %vi-dot) (%vi- %vi-end 1)) (set! %vi-dot %vi-end))
      (#t (%vi-dot-next!)))))

(def %vi-has-newline?
  (fn (_ s) (%vi< 0 (%vi-newlines-of s))))

; busybox's string_insert: S put in at P, recorded as UNDO says
(def %vi-string-insert!
  (fn (_ p s undo)
    (def n (byte-len s))
    (%vi-undo-push-insert! p n undo)
    (%vi-hole-make! p n)
    (%cu-ptr-call %vi-c-memcpy (%vi+ %vi-taddr p) s n)
    (set! %vi-nl-total (%vi+ %vi-nl-total (%vi-newlines-of s)))))

; "x: the register the next command yanks into or puts from
(def %vi-cmd-name-reg
  (fn (_)
    (def c (%vi- (%vi| (%vi-get-one-char) 32) #\a))
    (if (if (%vi< c 0) #f (%vi< c 26)) (set! %vi-ydreg c) (%vi-indicate-error))))
(def %vi| (prim-ref (lit int) (lit |)))

; --- marks ------------------------------------------------------------------

; the marks: a to z, then 26 the place the last jump left and 27 the one
; before it; -1 where none is set
(def %vi-marks ())
(def %vi-mark (fn (_ i) (Vector ref i %vi-marks)))
(def %vi-mark! (fn (_ i p) (Vector set! i p %vi-marks)))

; m: the cursor's place kept under a letter
(def %vi-cmd-mark
  (fn (_)
    (def c (%vi- (%vi| (%vi-get-one-char) 32) #\a))
    (if (if (%vi< c 0) #f (%vi< c 26)) (%vi-mark! c %vi-dot) (%vi-indicate-error))))

; ': to the line of a mark, or with '' back to where the last jump began
(def %vi-cmd-goto-mark
  (fn (_)
    (def c (%vi| (%vi-get-one-char) 32))
    (match
      ((%vi-in? c #\a #\z) (%vi-goto-mark (%vi-mark (%vi- c #\a))))
      ((= c #\')
        (do (set! %vi-dot (%vi-swap-context %vi-dot))
            (%vi-dot-begin!)
            (%vi-dot-skip-over-ws!)
            (set! %vi-orig-dot %vi-dot)))
      (#t (%vi-indicate-error)))))

(def %vi-goto-mark
  (fn (_ q)
    (if (if (%vi< q 0) #f (%vi< q %vi-end))
      (do (set! %vi-dot q) (%vi-dot-begin!) (%vi-dot-skip-over-ws!))
      (%vi-indicate-error))))

; busybox's check_context: after a jump, the place it left becomes mark 26
; and the one before that 27
(def %vi-check-context
  (fn (_ c)
    (if (%vi-one-of? c (list #\: #\% #\{ #\} #\' #\G #\H #\L #\M #\z #\/ #\? #\N #\n))
      (do (%vi-mark! 27 (%vi-mark 26)) (%vi-mark! 26 %vi-dot))
      ())))

(def %vi-swap-context
  (fn (_ p)
    (def m (%vi-mark 27))
    (if (if (%vi< m 0) #f (%vi< m %vi-end))
      (do (%vi-mark! 27 p) (%vi-mark! 26 m) m)
      p)))

; --- the rest ---------------------------------------------------------------

; r: the byte under the cursor, COUNT of them, replaced by the one typed
(def %vi-cmd-r
  (fn (_)
    (def c (%vi-get-one-char))
    (if (= c #\escape) ()
      (if (%vi< (%vi- (%vi-end-line %vi-dot) %vi-dot) (if (= %vi-cmdcnt 0) 1 %vi-cmdcnt))
        (%vi-indicate-error)
        (%vi-r-replace c)))
    (%vi-end-cmd-q!)))

; the first byte out undoable on its own, all after it chained
(def %vi-r-replace
  (fn (_ c)
    (def undo (list %vi-allow-undo))
    (%vi-repeat
      (fn (_)
        (set! %vi-dot (%vi-hole-delete! %vi-dot %vi-dot (first undo)))
        (set-first! undo %vi-allow-undo-chain)
        (set! %vi-dot (%vi-char-insert %vi-dot c (first undo)))))
    (%vi-dot-left!)))

; J: the next line joined on with a space, its leading blanks dropped; the
; newline's record first, all after it chained
(def %vi-cmd-J
  (fn (_)
    (%vi-repeat
      (fn (_)
        (%vi-dot-end!)
        (if (%vi< %vi-dot (%vi- %vi-end 1))
          (do (%vi-undo-push! %vi-dot 1 %vi-u-del)
              (%vi-byte-set! %vi-dot 32)
              (set! %vi-dot (%vi+ %vi-dot 1))
              (%vi-undo-push! (%vi- %vi-dot 1) 1 %vi-u-ins-chain)
              (%vi-drop-blanks))
          ())))
    (%vi-end-cmd-q!)))

(def %vi-drop-blanks
  (fn (self)
    (if (%vi-blank? (%vi-byte %vi-dot))
      (do (%vi-hole-delete! %vi-dot %vi-dot %vi-allow-undo-chain) (self))
      ())))

; ~: the case of the letter under the cursor flipped, COUNT times rightward;
; each flip the old letter out and the new in, chained to the flip before
(def %vi-cmd-tilde
  (fn (_)
    (def del (list %vi-u-del))
    (%vi-repeat
      (fn (_)
        (def c (%vi-byte %vi-dot))
        (match
          ((%vi-in? c #\a #\z) (%vi-flip-case (%vi- c 32) del))
          ((%vi-in? c #\A #\Z) (%vi-flip-case (%vi+ c 32) del))
          (#t ()))
        (%vi-dot-right!)))
    (%vi-end-cmd-q!)))

(def %vi-flip-case
  (fn (_ c del)
    (%vi-undo-push! %vi-dot 1 (first del))
    (%vi-byte-set! %vi-dot c)
    (%vi-undo-push! %vi-dot 1 %vi-u-ins-chain)
    (set-first! del %vi-u-del-chain)))

; D and C: to the end of the line out; C goes on into insert mode
(def %vi-cmd-DC
  (fn (_ c)
    (def from %vi-dot)
    (set! %vi-dot (%vi-yank-delete from (%vi-dollar-line %vi-dot) 0 #t %vi-allow-undo))
    (if (= c #\C) (%vi-start-insert!) (%vi-end-cmd-q!))))

; the byte before a line's newline, or the newline of an empty line
(def %vi-dollar-line
  (fn (_ p)
    (def e (%vi-end-line p))
    (if (if (= (%vi-byte e) #\newline) (%vi< 0 (%vi- e (%vi-begin-line e))) #f)
      (%vi- e 1)
      e)))

; U: the line as it was when the cursor came to it
(def %vi-cmd-U
  (fn (_)
    (def r (%vi-reg 27))
    (if (null? r) ()
      (%vi-undo-line (first r)))))

(def %vi-undo-line
  (fn (_ s)
    (def p (%vi-hole-delete! (%vi-begin-line %vi-dot) (%vi-end-line %vi-dot) %vi-allow-undo))
    (%vi-string-insert! p s %vi-allow-undo-chain)
    (set! %vi-dot p)
    (%vi-dot-skip-over-ws!)
    (%vi-yank-status! "Undo" s 1)))

; the line the cursor is on kept in register 27 whenever it moves to
; another, for U
(def %vi-cur-line -1)
(def %vi-line-kept!
  (fn (_)
    (def b (%vi-begin-line %vi-dot))
    (if (= b %vi-cur-line) ()
      (do (set! %vi-cur-line b)
          (%vi-text-yank! b (%vi-end-line %vi-dot) 27 0)))))

; busybox's end_cmd_q: the register named for a command reverts to the
; default when the command is done
(def %vi-end-cmd-q!
  (fn (_) (set! %vi-ydreg 26) (set! %vi-adding2q #f)))
