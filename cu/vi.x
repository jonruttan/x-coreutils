; # x-coreutils -- the small tools, as applets
;
; ## cu/vi.x -- vi, the editor
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's vi (editors/vi.c) is the spec -- its screen, its keys, its
; messages -- and its shape is kept: one buffer of bytes, every line ending in
; a newline, with the cursor, the top of the screen and every range an offset
; into it.  A motion is a search of that buffer, made by libc's memchr and
; strcspn through the FFI: a byte loop in x costs hundreds of objects a byte,
; a libc call two.  Offsets and counts are small integers, so their arithmetic
; rides the integer doors, which allocate nothing where the tower's + and <
; cost a hundred objects a call.
;
; The terminal is x's Term: raw mode and the window's size.  Keys are read a
; byte at a time and decoded here as busybox's read_key decodes them: after an
; Escape, each further byte of a sequence must come within 50 ms, so a lone
; Escape is a key of its own.  Where the bytes come from and where the screen
; goes are swappable, so a spec can type at the editor in bursts -- the pause
; between two bursts outlasts the 50 ms -- and read back what it drew.
;
; x has no automatic collect.  The editor sweeps once a key, after drawing the
; screen: a collect walks the whole heap, ~6 ms, and a key leaves tens of
; thousands of objects.

(import x/repl/term)

; --- doors ------------------------------------------------------------------

(def %vi+ (prim-ref (lit int) (lit +)))
(def %vi- (prim-ref (lit int) (lit -)))
(def %vi* (prim-ref (lit int) (lit *)))
(def %vi/ (prim-ref (lit int) (lit /)))
(def %vi% (prim-ref (lit int) (lit %)))
(def %vi< (prim-ref (lit int) (lit <)))
(def %vi& (prim-ref (lit int) (lit &)))
(def %vi-bsub (prim-ref (lit str) (lit byte-sub)))
(def %vi-str->ptr (prim-ref (lit str) (lit ->ptr)))
(def %vi-ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %vi-ptr-set! (prim-ref (lit ptr) (lit set!)))

(def %vi-min (fn (_ a b) (if (%vi< a b) a b)))
(def %vi-max (fn (_ a b) (if (%vi< a b) b a)))

; libc's entry points, looked up at the start of each run: a handle is a fact
; of the process, and a state image is written by another one
(def %vi-c-memchr ())
(def %vi-c-memmove ())
(def %vi-c-memcpy ())
(def %vi-c-strcspn ())
(def %vi-c-poll ())
(def %vi-c-read ())
(def %vi-c-write ())
(def %vi-c-access ())
(def %vi-c-memmem ())

(def %vi-resolve!
  (fn (_)
    (def lib (%cu-dlopen () 1))
    (set! %vi-c-memchr (%cu-dlsym lib "memchr"))
    (set! %vi-c-memmove (%cu-dlsym lib "memmove"))
    (set! %vi-c-memcpy (%cu-dlsym lib "memcpy"))
    (set! %vi-c-strcspn (%cu-dlsym lib "strcspn"))
    (set! %vi-c-poll (%cu-dlsym lib "poll"))
    (set! %vi-c-read (%cu-dlsym lib "read"))
    (set! %vi-c-write (%cu-dlsym lib "write"))
    (set! %vi-c-access (%cu-dlsym lib "access"))
    (set! %vi-c-memmem (%cu-dlsym lib "memmem"))))

; --- the terminal's words ---------------------------------------------------

(def %vi-esc (bytes->str (list 27)))
(def %vi-bell (bytes->str (list 7)))
(def %vi-bold (string-append %vi-esc "[7m"))
(def %vi-norm (string-append %vi-esc "[m"))
(def %vi-clear-eol (string-append %vi-esc "[K"))
(def %vi-home-clear (string-append %vi-esc "[H" %vi-esc "[J"))
(def %vi-alt-on (string-append %vi-esc "[?1049h"))
(def %vi-alt-off (string-append %vi-esc "[?1049l"))

; the bytes a screen line shows as something other than themselves: the
; controls, which show as ^X or a tab's spaces, and the bytes past 0x7F, which
; show as a dot.  strcspn stops at the first of them, or at the NUL kept after
; the text.
(def %vi-reject
  (bytes->str
    (List append (List range 1 32) (pair 127 (List range 128 256)))))

; --- the editor's state, busybox's globals ----------------------------------

(def %vi-text "")           ; the buffer, a string made raw
(def %vi-tptr ())           ; its address as a pointer, for ptr set!
(def %vi-taddr 0)           ; and as an integer, for libc
(def %vi-room 0)            ; the bytes it holds, less the NUL after the text
(def %vi-end 0)             ; the bytes of text in it
(def %vi-dot 0)             ; the cursor
(def %vi-screenbegin 0)     ; the first byte on the screen
(def %vi-rows 24)
(def %vi-columns 80)
(def %vi-crow 0)
(def %vi-ccol 0)
(def %vi-offset 0)          ; the columns scrolled off to the left
(def %vi-old-offset 0)
(def %vi-cindex 0)          ; the column j and k aim for; -1 is the line's end
(def %vi-keep-index #f)
(def %vi-cmd-mode 0)        ; 0 command, 1 insert, 2 replace
(def %vi-cmdcnt 0)
(def %vi-cmd-error #f)
(def %vi-editing 0)
(def %vi-modified 0)
(def %vi-readonly 0)
(def %vi-filename ())
(def %vi-files ())
(def %vi-optind 0)
(def %vi-tabstop 8)
(def %vi-status "")         ; a message waiting for the bottom line
(def %vi-have-status 0)     ; 1 when one is waiting, 2 in reverse video
(def %vi-last-status ())    ; the status line's bufsum, nil to draw it again
(def %vi-screen ())         ; the text rows as last drawn, top first
(def %vi-blanks "")         ; spaces enough for a row, sliced for padding
(def %vi-out ())            ; output not yet written, last first
(def %vi-nl-total 0)        ; the newlines in the text
(def %vi-lc-pos 0)          ; a place in the text and the newlines before it
(def %vi-lc-n 0)

; --- the text ---------------------------------------------------------------

; ROOM bytes of buffer, spaces, with the NUL after them
(def %vi-text-room!
  (fn (_ room)
    (def old %vi-text)
    (def old-end %vi-end)
    (set! %vi-text (%str-make-raw (%vi+ room 1)))
    (set! %vi-tptr (%vi-str->ptr %vi-text))
    (set! %vi-taddr (%vi-ptr->int %vi-tptr))
    (set! %vi-room room)
    (if (%vi< 0 old-end)
      (%cu-ptr-call %vi-c-memcpy %vi-taddr old old-end)
      ())))

(def %vi-text-init!
  (fn (_)
    (set! %vi-end 0)
    (%vi-text-room! 10240)
    (%vi-ptr-set! %vi-tptr 0 0 1)
    (set! %vi-dot 0)
    (set! %vi-screenbegin 0)
    (set! %vi-nl-total 0)
    (%vi-lc-forget!)))

; the line-number cache holds for the text before %vi-lc-pos, so any change
; there drops it
(def %vi-lc-forget!
  (fn (_) (set! %vi-lc-pos 0) (set! %vi-lc-n 0)))
(def %vi-touch!
  (fn (_ p) (if (%vi< p %vi-lc-pos) (%vi-lc-forget!) ())))

; busybox's text_hole_make: SIZE bytes of spaces opened at P
(def %vi-hole-make!
  (fn (_ p size)
    (if (%vi< 0 size)
      (%vi-hole-open! p size (%vi+ %vi-end size))
      ())))

(def %vi-hole-open!
  (fn (_ p size new-end)
    (if (%vi< %vi-room new-end)
      (%vi-text-room! (%vi+ new-end 10240))
      ())
    (%vi-touch! p)
    (%cu-ptr-call %vi-c-memmove (%vi+ %vi-taddr (%vi+ p size)) (%vi+ %vi-taddr p)
      (%vi- %vi-end p))
    (set! %vi-end new-end)
    (%vi-ptr-set! %vi-tptr new-end 0 1)
    (%vi-fill! p size 32)))

(def %vi-fill!
  (fn (self p n b)
    (if (%vi< 0 n)
      (do (%vi-ptr-set! %vi-tptr p b 1) (self (%vi+ p 1) (%vi- n 1) b))
      ())))

; one byte of the text replaced, the newline count kept
(def %vi-byte-set!
  (fn (_ p b)
    (def was (byte-at %vi-text p))
    (if (= was 10) (set! %vi-nl-total (%vi- %vi-nl-total 1)) ())
    (if (= b 10) (set! %vi-nl-total (%vi+ %vi-nl-total 1)) ())
    (%vi-touch! p)
    (%vi-ptr-set! %vi-tptr p b 1)))

; busybox's text_hole_delete: P through Q, both kept, answering where the text
; after them now starts
(def %vi-hole-delete!
  (fn (_ p q)
    (def src (if (%vi< q p) (%vi+ p 1) (%vi+ q 1)))
    (def dest (if (%vi< q p) q p))
    (match
      ((%vi< %vi-end src) dest)
      ((%vi< dest 0) dest)
      ((%vi< dest %vi-end) (%vi-hole-close! dest src))
      (#t dest))))

(def %vi-hole-close!
  (fn (_ dest src)
    (set! %vi-modified (%vi+ %vi-modified 1))
    (set! %vi-nl-total (%vi- %vi-nl-total (%vi-newlines-in dest src)))
    (%vi-touch! dest)
    (if (%vi< src %vi-end)
      (%cu-ptr-call %vi-c-memmove (%vi+ %vi-taddr dest) (%vi+ %vi-taddr src)
        (%vi- %vi-end src))
      ())
    (set! %vi-end (%vi- %vi-end (%vi- src dest)))
    (%vi-ptr-set! %vi-tptr %vi-end 0 1)
    (match
      ((%vi< %vi-end 1) (do (set! %vi-end 0) 0))
      ((%vi< dest %vi-end) dest)
      (#t (%vi- %vi-end 1)))))

; the byte C put in at P, as busybox's stupid_insert
(def %vi-byte-insert!
  (fn (_ p c)
    (%vi-hole-make! p 1)
    (%vi-byte-set! p c)
    (set! %vi-modified (%vi+ %vi-modified 1))))

; --- lines ------------------------------------------------------------------

; the first newline in [A, B), or -1
(def %vi-find-nl
  (fn (_ a b)
    (if (%vi< a b)
      (%vi-nl-found (%cu-ptr-call %vi-c-memchr (%vi+ %vi-taddr a) 10 (%vi- b a)))
      -1)))
(def %vi-nl-found (fn (_ r) (if (= r 0) -1 (%vi- r %vi-taddr))))

; the newlines in [A, B)
(def %vi-newlines-in
  (fn (self a b)
    (def at (%vi-find-nl a b))
    (if (= at -1) 0 (%vi+ 1 (self (%vi+ at 1) b)))))

; the last newline in [LO, HI), or FOUND
(def %vi-last-nl-in
  (fn (self lo hi found)
    (def at (%vi-find-nl lo hi))
    (if (= at -1) found (self (%vi+ at 1) hi at))))

; the last newline before P, or -1: libc has no backward memchr everywhere,
; so the text before P is searched forward, 128 bytes at a time from P back
(def %vi-nl-before
  (fn (self p)
    (def lo (if (%vi< p 128) 0 (%vi- p 128)))
    (def at (%vi-last-nl-in lo p -1))
    (match
      ((%vi< -1 at) at)
      ((= lo 0) -1)
      (#t (self lo)))))

(def %vi-begin-line
  (fn (_ p) (if (%vi< 0 p) (%vi+ (%vi-nl-before p) 1) p)))

(def %vi-end-line
  (fn (_ p)
    (def last (%vi- %vi-end 1))
    (if (%vi< p last)
      (%vi-end-line-at (%vi-find-nl p last) last)
      p)))
(def %vi-end-line-at (fn (_ at last) (if (= at -1) last at)))

(def %vi-prev-line
  (fn (_ p)
    (def b (%vi-begin-line p))
    (%vi-begin-line
      (if (if (%vi< 0 b) (= (byte-at %vi-text (%vi- b 1)) 10) #f) (%vi- b 1) b))))

(def %vi-next-line
  (fn (_ p)
    (def e (%vi-end-line p))
    (if (if (%vi< e (%vi- %vi-end 1)) (= (byte-at %vi-text e) 10) #f) (%vi+ e 1) e)))

(def %vi-end-screen
  (fn (_)
    (%vi-end-line (%vi-next-lines %vi-screenbegin (%vi- %vi-rows 2)))))

(def %vi-next-lines
  (fn (self p n) (if (%vi< 0 n) (self (%vi-next-line p) (%vi- n 1)) p)))

; busybox's count_lines: the newlines from START through the end of STOP's line
(def %vi-count-lines
  (fn (_ start stop)
    (if (%vi< stop start)
      (%vi-count-lines-from stop start)
      (%vi-count-lines-from start stop))))
(def %vi-count-lines-from
  (fn (_ a b) (%vi-newlines-in a (%vi+ (%vi-end-line b) 1))))

; the newlines before P, counted from the cached place nearest it
(def %vi-lines-before
  (fn (_ p)
    (def n
      (if (%vi< p %vi-lc-pos)
        (%vi- %vi-lc-n (%vi-newlines-in p %vi-lc-pos))
        (%vi+ %vi-lc-n (%vi-newlines-in %vi-lc-pos p))))
    (set! %vi-lc-pos p)
    (set! %vi-lc-n n)
    n))

; busybox's find_line: where line LI starts, counting from 1
(def %vi-find-line (fn (_ li) (%vi-next-lines 0 (%vi- li 1))))

; --- columns ----------------------------------------------------------------

(def %vi-next-tabstop
  (fn (_ col) (%vi+ col (%vi- (%vi- %vi-tabstop 1) (%vi% col %vi-tabstop)))))

; the column after the byte C shown at column CO
(def %vi-next-column
  (fn (_ c co)
    (match
      ((= c 9) (%vi+ (%vi-next-tabstop co) 1))
      ((%vi< c 32) (%vi+ co 2))
      ((= c 127) (%vi+ co 2))
      (#t (%vi+ co 1)))))

; where the bytes shown as themselves end, from A on
(def %vi-plain-end
  (fn (_ a)
    (%vi+ a (%cu-ptr-call %vi-c-strcspn (%vi+ %vi-taddr a) %vi-reject))))

; the column after the bytes [A, P), from column CO
(def %vi-columns-over
  (fn (self a p co)
    (def q (%vi-plain-end a))
    (if (%vi< q p)
      (self (%vi+ q 1) p
        (%vi-next-column (byte-at %vi-text q) (%vi+ co (%vi- q a))))
      (%vi+ co (%vi- p a)))))

(def %vi-get-column
  (fn (_ p) (%vi-columns-over (%vi-begin-line p) p 0)))

; busybox's move_to_col: the byte of P's line that covers column L, or the
; line's newline
(def %vi-move-to-col
  (fn (_ p l) (%vi-col-walk (%vi-begin-line p) 0 (%vi-max l 0))))

(def %vi-col-walk
  (fn (self a co l)
    (def q (%vi-plain-end a))
    (match
      ((%vi< l (%vi+ co (%vi- q a))) (%vi+ a (%vi- l co)))
      ((%vi< q %vi-end) (%vi-col-special self q (%vi+ co (%vi- q a)) l))
      (#t (%vi- %vi-end 1)))))

(def %vi-col-special
  (fn (_ walk q co l)
    (def c (byte-at %vi-text q))
    (def next (%vi-next-column c co))
    (match
      ((= c 10) q)
      ((%vi< l next) q)
      (#t (walk (%vi+ q 1) next l)))))

; --- output -----------------------------------------------------------------

; where finished output goes: the terminal, or a spec's list
(def %vi-sink ())
(def %vi-put (fn (_ s) (set! %vi-out (pair s %vi-out))))
(def %vi-flush!
  (fn (_)
    (if (null? %vi-out) ()
      (do (%vi-sink (string-concat (reverse %vi-out)))
          (set! %vi-out ())))))

(def %vi-place-cursor
  (fn (_ row col)
    (def r (%vi-max 0 (%vi-min row (%vi- %vi-rows 1))))
    (def c (%vi-max 0 (%vi-min col (%vi- %vi-columns 1))))
    (%vi-put (string-concat
               (list %vi-esc "[" (%cu-int->str (%vi+ r 1)) ";"
                     (%cu-int->str (%vi+ c 1)) "H")))))

(def %vi-bottom-clear
  (fn (_)
    (%vi-place-cursor (%vi- %vi-rows 1) 0)
    (%vi-put %vi-clear-eol)))

(def %vi-indicate-error
  (fn (_)
    (set! %vi-cmd-error #t)
    (%vi-put %vi-bell)))

(def %vi-spaces
  (fn (_ n) (if (%vi< 0 n) (%vi-bsub %vi-blanks 0 n) "")))

; --- the screen -------------------------------------------------------------

; busybox's new_screen: blank rows, each after the first marked as past the
; text, ROWS - 1 of them
(def %vi-new-screen!
  (fn (_)
    (set! %vi-blanks (%str-make-raw (%vi+ %vi-columns 16)))
    (def blank (%vi-spaces %vi-columns))
    (def tilde (string-append "~" (%vi-spaces (%vi- %vi-columns 1))))
    (set! %vi-screen (pair blank (%vi-rows-of tilde (%vi- %vi-rows 2) ())))))

(def %vi-rows-of
  (fn (self s n acc) (if (%vi< 0 n) (self s (%vi- n 1) (pair s acc)) acc)))

(def %vi-screen-erase!
  (fn (_)
    (set! %vi-screen
      (%vi-rows-of (%vi-spaces %vi-columns) (%vi- %vi-rows 1) ()))))

; busybox's format_line: the row the line at SRC shows, COLUMNS wide, from
; the column %vi-offset; a row past the text shows a ~
(def %vi-format-line
  (fn (_ src)
    (def shown
      (if (%vi< src %vi-end)
        (%vi-shown src (%vi+ %vi-offset %vi-columns))
        "~"))
    (def len (byte-len shown))
    (def row
      (if (%vi< %vi-offset len)
        (%vi-bsub shown %vi-offset (%vi-min %vi-columns (%vi- len %vi-offset)))
        ""))
    (def short (%vi- %vi-columns (byte-len row)))
    (if (%vi< 0 short) (string-append row (%vi-spaces short)) row)))

; the line at SRC as shown, until it reaches column LIM
(def %vi-shown
  (fn (_ src lim)
    (def pieces (%vi-shown-from src 0 lim ()))
    (if (null? (rest pieces)) (first pieces) (string-concat (reverse pieces)))))

(def %vi-shown-from
  (fn (self a co lim acc)
    (def q (%vi-plain-end a))
    (def n (%vi-min (%vi- q a) (%vi- lim co)))
    (def acc2 (if (%vi< 0 n) (pair (%vi-bsub %vi-text a n) acc) acc))
    (def co2 (%vi+ co n))
    (match
      ((%vi< co2 lim) (%vi-shown-special self q co2 lim acc2))
      ((null? acc2) (list ""))
      (#t acc2))))

(def %vi-shown-special
  (fn (_ walk q co lim acc)
    (def c (byte-at %vi-text q))
    (match
      ((= c 10) (if (null? acc) (list "") acc))
      ((if (%vi< q %vi-end) #f #t) (if (null? acc) (list "") acc))
      (#t (walk (%vi+ q 1) (%vi-next-column c co) lim
            (pair (%vi-shown-byte c co) acc))))))

; how the byte C at column CO shows
(def %vi-shown-byte
  (fn (_ c co)
    (match
      ((= c 9) (%vi-spaces (%vi- (%vi-next-column c co) co)))
      ((= c 127) "^?")
      ((%vi< c 32) (bytes->str (list 94 (%vi+ c 64))))
      (#t "."))))

; busybox's sync_cursor: the top of the screen and the left offset moved so D
; shows, then D's row and column
(def %vi-sync-cursor!
  (fn (_ d)
    (def beg (%vi-begin-line d))
    (if (%vi< beg %vi-screenbegin)
      (%vi-scroll-up-to! beg (%vi-count-lines beg %vi-screenbegin))
      (%vi-scroll-down-to! beg (%vi-end-screen)))
    (set! %vi-crow (%vi-row-of beg %vi-screenbegin 0))
    (def co (%vi-cursor-column d beg))
    (if (%vi< co %vi-offset) (set! %vi-offset co) ())
    (if (%vi< co (%vi+ %vi-columns %vi-offset)) ()
      (set! %vi-offset (%vi+ (%vi- co %vi-columns) 1)))
    (if (if (= d beg) (= (byte-at %vi-text d) 9) #f) (set! %vi-offset 0) ())
    (set! %vi-ccol (%vi- co %vi-offset))))

(def %vi-scroll-up-to!
  (fn (_ beg cnt)
    (set! %vi-screenbegin beg)
    (def half (%vi/ (%vi- %vi-rows 1) 2))
    (if (%vi< half cnt)
      (set! %vi-screenbegin (%vi-prev-lines %vi-screenbegin half))
      ())))

(def %vi-prev-lines
  (fn (self p n) (if (%vi< 0 n) (self (%vi-prev-line p) (%vi- n 1)) p)))

(def %vi-scroll-down-to!
  (fn (_ beg end-scr)
    (if (%vi< end-scr beg)
      (%vi-scroll-down-by! beg (%vi-count-lines end-scr beg))
      ())))

(def %vi-scroll-down-by!
  (fn (_ beg cnt)
    (if (%vi< (%vi/ (%vi- %vi-rows 1) 2) cnt)
      (%vi-scroll-up-to! beg cnt)
      (set! %vi-screenbegin (%vi-next-lines %vi-screenbegin (%vi- cnt 1))))))

(def %vi-row-of
  (fn (self beg tp ro)
    (match
      ((= tp beg) ro)
      ((%vi< ro (%vi- %vi-rows 2)) (self beg (%vi-next-line tp) (%vi+ ro 1)))
      (#t (%vi+ ro 1)))))

; the column the cursor shows at on the byte D: a byte's last cell, where a
; newline shows none and an insert before a tab sits on its first
(def %vi-cursor-column
  (fn (_ d beg)
    (def c (byte-at %vi-text d))
    (def start (%vi-columns-over beg d 0))
    (match
      ((= c 10) start)
      ((if (= c 9) (if (= %vi-cmd-mode 0) #f (%vi< beg d)) #f) start)
      (#t (%vi- (%vi-next-column c start) 1)))))

; busybox's refresh: each row that differs from what the screen shows is
; written again, and the cursor put on the dot
(def %vi-refresh!
  (fn (_ full?)
    (def full (%vi-window-check full?))
    (%vi-sync-cursor! %vi-dot)
    (def moved (if (= %vi-offset %vi-old-offset) #f #t))
    (set! %vi-screen
      (%vi-refresh-rows %vi-screenbegin 0 %vi-screen (if full #t moved) ()))
    (%vi-place-cursor %vi-crow %vi-ccol)
    (if %vi-keep-index () (set! %vi-cindex (%vi+ %vi-ccol %vi-offset)))
    (set! %vi-old-offset %vi-offset)))

(def %vi-refresh-rows
  (fn (self tp li old force acc)
    (if (%vi< li (%vi- %vi-rows 1))
      (self (%vi-row-next tp) (%vi+ li 1) (if (null? old) () (rest old)) force
        (pair (%vi-row-drawn li (%vi-format-line tp) old force) acc))
      (reverse acc))))

(def %vi-row-next
  (fn (_ tp)
    (if (%vi< tp %vi-end)
      (%vi+ (%vi-end-line-at (%vi-find-nl tp %vi-end) (%vi- %vi-end 1)) 1)
      tp)))

(def %vi-row-drawn
  (fn (_ li row old force)
    (if (match (force #t) ((null? old) #t) (#t (if (string=? row (first old)) #f #t)))
      (do (%vi-place-cursor li 0) (%vi-put row))
      ())
    row))

; the window measured again; a change of size redraws it all
(def %vi-window ())
(def %vi-window-check
  (fn (_ full?)
    (def w (%vi-window))
    (def cols (%vi-min (first w) 4096))
    (def rows (%vi-min (rest w) 4096))
    (if (if (= cols %vi-columns) (= rows %vi-rows) #f) full?
      (do (set! %vi-columns cols)
          (set! %vi-rows rows)
          (%vi-new-screen!)
          #t))))

(def %vi-redraw!
  (fn (_ full?)
    (%vi-put %vi-home-clear)
    (%vi-screen-erase!)
    (set! %vi-last-status ())
    (%vi-refresh! full?)
    (%vi-show-status-line!)))

; --- the status line --------------------------------------------------------

; a message for the bottom line, plain or in reverse video
(def %vi-status-line!
  (fn (_ s) (set! %vi-status s) (set! %vi-have-status 1)))

(def %vi-status-line-bold!
  (fn (_ s) (set! %vi-status s) (set! %vi-have-status 2)))

; busybox's format_edit_status: the mode, the file, where the cursor is
(def %vi-edit-status
  (fn (_)
    (def eol (%vi-end-line %vi-dot))
    (def cur (%vi-lines-before (%vi+ eol 1)))
    (def before (if (= (byte-at %vi-text eol) 10) (%vi- cur 1) cur))
    (def tot (%vi- (%vi+ cur (%vi- %vi-nl-total before)) 1))
    (def s
      (string-concat
        (list (%vi-bsub "-IR-" (%vi% %vi-cmd-mode 4) 1) " "
              (if (null? %vi-filename) "No file" %vi-filename)
              (if (= %vi-readonly 0) "" " [Readonly]")
              (if (= %vi-modified 0) "" " [Modified]")
              " " (%cu-int->str (if (%vi< 0 tot) cur 0))
              "/" (%cu-int->str (if (%vi< 0 tot) tot 0))
              " " (%cu-int->str (if (%vi< 0 tot) (%vi/ (%vi* 100 cur) tot) 100))
              "%")))
    (def most (%vi-min %vi-columns 199))
    (if (%vi< most (byte-len s)) (%vi-bsub s 0 most) s)))

; busybox's show_status_line: a waiting message, or the edit status when its
; checksum changed -- busybox's bufsum, the sum of its bytes, so two statuses
; that sum the same, like "15/30 50%" and "11/30 36%", leave the old one up; a
; message too wide for the line waits for a Return
(def %vi-show-status-line!
  (fn (_)
    (def msg? (%vi< 0 %vi-have-status))
    (def s (if msg? %vi-status (%vi-edit-status)))
    (if (match (msg? #t) ((null? %vi-last-status) #t) (#t (if (= (%vi-bufsum s) %vi-last-status) #f #t)))
      (%vi-status-drawn! s msg?)
      ())
    (%vi-flush!)))

(def %vi-bufsum
  (fn (_ s)
    (%vi-sum-from s 0 0)))
(def %vi-sum-from
  (fn (self s i n)
    (if (%vi< i (byte-len s)) (self s (%vi+ i 1) (%vi+ n (%vi& (byte-at s i) 255))) n)))

; the bottom line's text as last drawn, without its video codes
(def %vi-bottom "")

(def %vi-status-drawn!
  (fn (_ s msg?)
    (set! %vi-last-status (if msg? () (%vi-bufsum s)))
    (set! %vi-bottom s)
    (%vi-bottom-clear)
    (%vi-put (if (= %vi-have-status 2) (string-append %vi-bold s %vi-norm) s))
    (if msg? (%vi-status-shown! s) ())
    (%vi-place-cursor %vi-crow %vi-ccol)))

; a message wider than the screen waits for a Return.  It is shown once:
; busybox's redraw shows it again and waits again, for every Return, so its
; vi never gets back to taking commands.
(def %vi-status-shown!
  (fn (_ s)
    (set! %vi-have-status 0)
    (if (%vi< (byte-len s) %vi-columns) () (%vi-hit-return s))))

(def %vi-hit-return
  (fn (_ s)
    (set! %vi-bottom (string-append s "[Hit return to continue]"))
    (%vi-put (string-append %vi-bold "[Hit return to continue]" %vi-norm))
    (%vi-until-return)
    (%vi-redraw! #t)))

(def %vi-until-return
  (fn (self)
    (def c (%vi-get-one-char))
    (if (if (= c 10) #t (= c 13)) () (self))))

; busybox's print_literal: S with its controls spelled ^X
(def %vi-literal
  (fn (_ s)
    (if (= (byte-len s) 0) "(NULL)"
      (string-concat (reverse (%vi-literal-from s 0 ()))))))

(def %vi-literal-from
  (fn (self s i acc)
    (if (%vi< i (byte-len s))
      (self s (%vi+ i 1) (pair (%vi-literal-byte (%vi& (byte-at s i) 255)) acc))
      acc)))

(def %vi-literal-byte
  (fn (_ c)
    (match
      ((= c 127) "^?")
      ((%vi< c 32) (bytes->str (list 94 (%vi+ c 64))))
      ((%vi< 127 c) "?")
      (#t (bytes->str (list c))))))

(def %vi-not-implemented
  (fn (_ s)
    (%vi-status-line-bold! (string-append "'" (%vi-literal s) "' is not implemented"))))

; --- keys -------------------------------------------------------------------

; where bytes come from: READ answers the next one, blocking, or nil at the
; end; READY? answers whether one comes within MS milliseconds
(def %vi-src-read ())
(def %vi-src-ready? ())
(def %vi-kbuf ())           ; bytes read after an Escape and not yet used
(def %vi-tty? #f)           ; the keys come from a terminal busybox keeps ISIG on

; busybox's escape sequences (libbb/read_key.c), each with its key code
(def %vi-key-up -2)
(def %vi-key-down -3)
(def %vi-key-right -4)
(def %vi-key-left -5)
(def %vi-key-home -6)
(def %vi-key-end -7)
(def %vi-key-insert -8)
(def %vi-key-delete -9)

; each sequence as the bytes after the Escape, with its code; shortest first,
; as busybox orders them
(def %vi-sequences
  (list (pair (bytes->str (list 127)) -44) (pair (bytes->str (list 8)) -44)
        (pair "d" -45) (pair "f" -36) (pair "b" -37)
        (pair "OA" -2) (pair "OB" -3) (pair "OC" -4) (pair "OD" -5)
        (pair "OH" -6) (pair "OF" -7)
        (pair "[A" -2) (pair "[B" -3) (pair "[C" -4) (pair "[D" -5)
        (pair "[H" -6) (pair "[F" -7)
        (pair "[1~" -6) (pair "[2~" -8) (pair "[3~" -9) (pair "[4~" -7)
        (pair "[5~" -10) (pair "[6~" -11) (pair "[7~" -6) (pair "[8~" -7)
        (pair "[1;3C" -36) (pair "[1;3D" -37)
        (pair "[1;5C" -68) (pair "[1;5D" -69)))

; the next byte: one read after an Escape first
(def %vi-next-byte
  (fn (_)
    (if (null? %vi-kbuf)
      (do (%vi-flush!) (%vi-src-read))
      (%vi-pop-kbuf))))
(def %vi-pop-kbuf
  (fn (_) (def b (first %vi-kbuf)) (set! %vi-kbuf (rest %vi-kbuf)) b))

; busybox's read_key: a byte, or the code of a known escape sequence; nil at
; the end of the input
(def %vi-read-key
  (fn (self)
    (def c (%vi-next-byte))
    (match
      ((null? c) ())
      ((= c 27) (%vi-escape self))
      (#t c))))

; After an Escape the sequences are tried in order, each further byte waited
; for 50 ms.  A lone Escape, or one with a single byte after it, is the Escape
; key and the byte is kept; a longer run nobody knows is dropped and the next
; key read instead.  The bytes already read after it (%vi-kbuf) are where the
; matching starts, in the order they came.
(def %vi-escape
  (fn (_ again)
    (def got (%vi-seq-match %vi-sequences (%vi-list->str %vi-kbuf)))
    (set! %vi-kbuf ())
    (match
      ((null? got) ())
      ((number? got) got)
      ((null? (rest got)) (%vi-escape-rest again (%vi-drain (first got))))
      (#t (%vi-escape-rest again (first got))))))

; a code on a match; (BUF) when no sequence matched with the bytes BUF; (BUF .
; stop) when the bytes stopped coming first; nil at the end of the input
(def %vi-seq-match
  (fn (self seqs buf)
    (if (null? seqs) (list buf)
      (%vi-seq-try self seqs buf 0))))

(def %vi-seq-try
  (fn (_ walk seqs buf i)
    (def want (first (first seqs)))
    (match
      ((= i (byte-len want)) (rest (first seqs)))
      ((%vi< i (byte-len buf))
        (if (= (byte-at buf i) (byte-at want i))
          (%vi-seq-try walk seqs buf (%vi+ i 1))
          (walk (rest seqs) buf)))
      ((%vi-src-ready? 50) (%vi-seq-read walk seqs buf i))
      (#t (pair buf (lit stop))))))

(def %vi-seq-read
  (fn (_ walk seqs buf i)
    (def b (%vi-src-read))
    (if (null? b) ()
      (%vi-seq-try walk seqs (string-append buf (bytes->str (list b))) i))))

; no sequence matched: more bytes read while they come, up to busybox's 15
(def %vi-drain
  (fn (self buf)
    (if (if (%vi< (byte-len buf) 15) (%vi-src-ready? 50) #f)
      (%vi-drained self buf (%vi-src-read))
      buf)))
(def %vi-drained
  (fn (_ again buf b)
    (if (null? b) () (again (string-append buf (bytes->str (list b)))))))

(def %vi-escape-rest
  (fn (_ again buf)
    (match
      ((null? buf) ())
      ((%vi< (byte-len buf) 2) (do (set! %vi-kbuf (%vi-str->list buf)) 27))
      (#t (again)))))

(def %vi-list->str (fn (_ l) (if (null? l) "" (bytes->str l))))
(def %vi-str->list
  (fn (_ s) (if (= (byte-len s) 0) () (list (%vi& (byte-at s 0) 255)))))

; busybox's readit: a key, or the editor ends when the input does.  A
; terminal's ^C interrupts whatever is under way, as vi's SIGINT handler does.
(def %vi-get-one-char
  (fn (_)
    (def c (%vi-read-key))
    (match
      ((null? c) (Err raise (lit vi-eof) "vi: can't read user input" ()))
      ((if %vi-tty? (= c 3) #f) (Err raise (lit vi-interrupt) "vi: interrupt" ()))
      (#t c))))

; busybox's get_input_line: PROMPT on the bottom line and a line typed after
; it, ended by Return or Escape; backing up past the prompt ends it empty
(def %vi-get-input-line
  (fn (_ prompt)
    (set! %vi-last-status ())
    (%vi-bottom-clear)
    (%vi-put prompt)
    (def line (%vi-input-from (reverse (%vi-bytes-of prompt 0))))
    (set! %vi-bottom line)
    (%vi-refresh! #f)
    line))

(def %vi-bytes-of
  (fn (self s i)
    (if (%vi< i (byte-len s))
      (pair (%vi& (byte-at s i) 255) (self s (%vi+ i 1)))
      ())))

; the line so far is ACC, its bytes last first
(def %vi-input-from
  (fn (self acc)
    (def c (%vi-get-one-char))
    (match
      ((if (= c 10) #t (if (= c 13) #t (= c 27))) (%vi-list->str (reverse acc)))
      ((if (= c 8) #t (= c 127)) (%vi-input-back self (rest acc)))
      ((if (%vi< 0 c) (%vi< c 256) #f)
        (do (%vi-put (bytes->str (list c))) (self (pair c acc))))
      (#t (self acc)))))

(def %vi-input-back
  (fn (_ again acc)
    (%vi-bottom-clear)
    (if (null? acc) ""
      (do (%vi-put (bytes->str (reverse acc))) (again acc)))))

; --- editing ----------------------------------------------------------------

(def %vi-dot-left!
  (fn (_)
    (if (if (%vi< 0 %vi-dot) (if (= (byte-at %vi-text (%vi- %vi-dot 1)) 10) #f #t) #f)
      (set! %vi-dot (%vi- %vi-dot 1))
      ())))

(def %vi-dot-right!
  (fn (_)
    (if (if (%vi< %vi-dot (%vi- %vi-end 1)) (if (= (byte-at %vi-text %vi-dot) 10) #f #t) #f)
      (set! %vi-dot (%vi+ %vi-dot 1))
      ())))

(def %vi-dot-begin! (fn (_) (set! %vi-dot (%vi-begin-line %vi-dot))))
(def %vi-dot-end! (fn (_) (set! %vi-dot (%vi-end-line %vi-dot))))
(def %vi-dot-next! (fn (_) (set! %vi-dot (%vi-next-line %vi-dot))))
(def %vi-dot-prev! (fn (_) (set! %vi-dot (%vi-prev-line %vi-dot))))

(def %vi-blank? (fn (_ c) (if (= c 32) #t (= c 9))))
(def %vi-space? (fn (_ c) (if (= c 32) #t (if (%vi< c 9) #f (%vi< c 14)))))

(def %vi-dot-skip-over-ws!
  (fn (self)
    (def c (byte-at %vi-text %vi-dot))
    (if (if (%vi-space? c) (if (= c 10) #f (%vi< %vi-dot (%vi- %vi-end 1))) #f)
      (do (set! %vi-dot (%vi+ %vi-dot 1)) (self))
      ())))

; busybox's bound_dot: P kept inside the text
(def %vi-bound-dot
  (fn (_ p)
    (match
      ((if (%vi< p %vi-end) #f (%vi< 0 %vi-end)) (do (%vi-indicate-error) (%vi- %vi-end 1)))
      ((%vi< p 0) (do (%vi-indicate-error) 0))
      (#t p))))

; busybox's char_insert, less its options: C typed at P in insert mode,
; answering where the cursor goes
(def %vi-char-insert
  (fn (_ p c)
    (match
      ((= c 22) (%vi-insert-literal p))
      ((= c 27) (%vi-insert-escape p))
      ((= c 4) (%vi-insert-dedent p))
      ((if (= c 8) #t (= c 127)) (%vi-insert-backspace p))
      (#t (do (%vi-byte-insert! p (if (= c 13) 10 c)) (%vi+ p 1))))))

(def %vi-insert-literal
  (fn (_ p)
    (%vi-byte-insert! p 94)
    (%vi-refresh! #f)
    (%vi-byte-set! p (%vi& (%vi-get-one-char) 255))
    (%vi+ p 1)))

(def %vi-insert-escape
  (fn (_ p)
    (set! %vi-cmd-mode 0)
    (set! %vi-cmdcnt 0)
    (%vi-end-cmd-q!)
    (set! %vi-last-status ())
    (if (if (%vi< 0 %vi-dot) (if (= (byte-at %vi-text (%vi- p 1)) 10) #f #t) #f)
      (%vi- p 1)
      p)))

(def %vi-insert-backspace
  (fn (_ p)
    (match
      ((= %vi-cmd-mode 2) (if (%vi< %vi-rstart p) (%vi- p 1) p))
      ((%vi< 0 p) (%vi-hole-delete! (%vi- p 1) (%vi- p 1)))
      (#t p))))
(def %vi-rstart 0)

; ^D: the indent of P's line back to the tab stop before it
(def %vi-insert-dedent
  (fn (_ p)
    (def bol (%vi-begin-line p))
    (def r (%vi+ bol (%vi-indent-len bol)))
    (%vi-dedent-to p bol r (%vi-prev-tabstop (%vi-get-column r)))))

(def %vi-dedent-to
  (fn (self p bol r prev)
    (if (if (%vi< bol r) (%vi< prev (%vi-get-column r)) #f)
      (self (if (%vi< bol p) (%vi- p 1) p) bol
        (%vi-hole-delete! (%vi- r 1) (%vi- r 1)) prev)
      p)))

(def %vi-prev-tabstop
  (fn (_ col)
    (def m (%vi% col %vi-tabstop))
    (%vi- col (if (= m 0) %vi-tabstop m))))

(def %vi-indent-len
  (fn (self p)
    (if (if (%vi< p (%vi- %vi-end 1)) (%vi-blank? (byte-at %vi-text p)) #f)
      (%vi+ 1 (self (%vi+ p 1)))
      0)))

; the registers: a to z, 26 the one d and y use when none is named, 27 the
; line U puts back; each the text it holds and its type, busybox's -- 0 part
; of a line, 1 whole lines, 2 text across lines.  The count of yanks tells a
; command whether it yanked.
(def %vi-regs ())
(def %vi-ydreg 26)
(def %vi-yank-count 0)

(def %vi-reg (fn (_ i) (Vector ref i %vi-regs)))

; busybox's text_yank: P through Q copied into register DEST, as a C string
(def %vi-text-yank!
  (fn (_ p q dest type)
    (def a (%vi-min p q))
    (Vector set! dest (pair (%vi-bsub %vi-text a (%vi+ (%vi- (%vi-max p q) a) 1)) type)
      %vi-regs)
    (set! %vi-yank-count (%vi+ %vi-yank-count 1))
    a))

(def %vi-what-reg
  (fn (_)
    (match
      ((%vi< %vi-ydreg 26) (%vi+ 97 %vi-ydreg))
      ((= %vi-ydreg 27) 85)
      (#t 68))))

; busybox's yank_status: what a command did to a register, in lines and bytes
(def %vi-yank-status!
  (fn (_ op s cnt)
    (%vi-status-line!
      (string-concat
        (list op " " (%cu-int->str (%vi* (%vi-newlines-of s) cnt)) " lines ("
              (%cu-int->str (%vi* (byte-len s) cnt)) " chars) from ["
              (bytes->str (list (%vi-what-reg))) "]")))))

(def %vi-newlines-of
  (fn (self s)
    (%vi-count-in s 0 0)))
(def %vi-count-in
  (fn (self s i n)
    (if (%vi< i (byte-len s))
      (self s (%vi+ i 1) (if (= (byte-at s i) 10) (%vi+ n 1) n))
      n)))

; busybox's yank_delete: START through STOP into the register as TYPE, then
; out of the text when DEL?; a partial range never starts on a newline
(def %vi-yank-delete
  (fn (_ start stop type del?)
    (def a (%vi-min start stop))
    (def b (%vi-max start stop))
    (if (if (= type 0) (= (byte-at %vi-text a) 10) #f) a
      (do (%vi-text-yank! a b %vi-ydreg type)
          (if del? (%vi-hole-delete! a b) a)))))

; --- the commands -----------------------------------------------------------

; busybox's do_cmd: one key, in whichever mode the editor is in
;
; Where the command started is kept for dc1, which remembers a jump; '' moves
; it.  An operator's motion runs as a command of its own inside this one, so
; the outer command's start is put back when the inner is done.
(def %vi-orig-dot 0)
(def %vi-do-cmd
  (fn (_ c)
    (def outer %vi-orig-dot)
    (set! %vi-orig-dot %vi-dot)
    (set! %vi-keep-index #f)
    (set! %vi-cmd-error #f)
    (%vi-show-status-line!)
    (match
      ((%vi-cursor-key? c) (%vi-key-cmd c))
      ((= %vi-cmd-mode 2) (%vi-replace-key c))
      ((= %vi-cmd-mode 1) (%vi-insert-key c))
      (#t (%vi-key-cmd c)))
    (%vi-dc1 c)
    (set! %vi-orig-dot outer)))

; the keys that move the cursor in every mode: the arrows, Home, End, the
; pages and Delete -- codes -2 to -11, less Insert's -8
(def %vi-cursor-key?
  (fn (_ c) (if (%vi< c -1) (if (%vi< -12 c) (if (= c -8) #f #t) #f) #f)))

(def %vi-insert-key
  (fn (_ c)
    (match
      ((= c %vi-key-insert) (%vi-start-replace!))
      ((%vi< 0 c) (set! %vi-dot (%vi-char-insert %vi-dot c)))
      (#t ()))))

(def %vi-replace-key
  (fn (_ c)
    (match
      ((= c %vi-key-insert) (%vi-start-insert!))
      ((= (byte-at %vi-text %vi-dot) 10) (do (set! %vi-cmd-mode 1) (%vi-insert-key c)))
      ((%vi< 0 c) (%vi-replace-char c))
      (#t ()))))

(def %vi-replace-char
  (fn (_ c)
    (if (%vi-one-of? c (list 27 8 127)) ()
      (set! %vi-dot (%vi-yank-delete %vi-dot %vi-dot 0 #t)))
    (set! %vi-dot (%vi-char-insert %vi-dot c))))

; what every command ends with: an empty text gets its line back, the dot is
; kept in the text, a jump is remembered, and in command mode the dot is kept
; off a newline
(def %vi-dc1
  (fn (_ c)
    (if (= %vi-end 0)
      (do (%vi-byte-insert! 0 10) (set! %vi-dot 0))
      ())
    (if (= %vi-dot %vi-end) () (set! %vi-dot (%vi-bound-dot %vi-dot)))
    (if (= %vi-dot %vi-orig-dot) () (%vi-check-context c))
    (if (%vi-digit? c) () (set! %vi-cmdcnt 0))
    (if (if (= (byte-at %vi-text %vi-dot) 10)
          (if (%vi< 0 (%vi- %vi-dot (%vi-begin-line %vi-dot))) (= %vi-cmd-mode 0) #f)
          #f)
      (set! %vi-dot (%vi- %vi-dot 1))
      ())))

(def %vi-digit? (fn (_ c) (if (%vi< 47 c) (%vi< c 58) #f)))

; whether the key C is one of CS
(def %vi-one-of?
  (fn (self c cs)
    (match
      ((null? cs) #f)
      ((= c (first cs)) #t)
      (#t (self c (rest cs))))))

; a command COUNT times: the count typed before it, at least once
(def %vi-repeat
  (fn (self thunk)
    (thunk)
    (set! %vi-cmdcnt (%vi- %vi-cmdcnt 1))
    (if (%vi< 0 %vi-cmdcnt) (self thunk) ())))

(def %vi-start-insert!
  (fn (_) (set! %vi-cmd-mode 1)))

(def %vi-start-replace!
  (fn (_) (set! %vi-cmd-mode 2) (set! %vi-rstart %vi-dot)))

(def %vi-key-cmd
  (fn (_ c)
    (match
      ((= c 0) ())
      ((%vi-one-of? c (list 104 %vi-key-left 8 127))
        (%vi-repeat %vi-dot-left!))
      ((%vi-one-of? c (list 108 32 %vi-key-right))
        (%vi-repeat %vi-dot-right!))
      ((%vi-one-of? c (list 106 %vi-key-down 10 13 43))
        (%vi-cmd-down c))
      ((%vi-one-of? c (list 107 %vi-key-up 45)) (%vi-cmd-up c))
      ((%vi-digit? c) (%vi-cmd-digit c))
      ((if (= c 36) #t (= c %vi-key-end)) (%vi-cmd-dollar))
      ((= c %vi-key-home) (%vi-dot-begin!))
      ((if (= c 105) #t (= c %vi-key-insert)) (%vi-start-insert!))
      ((= c 97) (%vi-cmd-append))
      ((= c 65) (do (%vi-dot-end!) (%vi-cmd-append)))
      ((= c 73) (do (%vi-dot-begin!) (%vi-dot-skip-over-ws!) (%vi-start-insert!)))
      ((= c 111) (%vi-cmd-open-below))
      ((= c 79) (%vi-cmd-open-above))
      ((%vi-one-of? c (list 120 88 115)) (%vi-cmd-x c))
      ((= c %vi-key-delete) (%vi-cmd-delete-key))
      ((%vi-one-of? c (list 99 100 121 89)) (%vi-cmd-cdy c))
      ((%vi-one-of? c (list 60 62)) (%vi-cmd-shift c))
      ((%vi-one-of? c (list 112 80)) (%vi-cmd-put c))
      ((= c 34) (%vi-cmd-name-reg))
      ((= c 109) (%vi-cmd-mark))
      ((= c 39) (%vi-cmd-goto-mark))
      ((= c 114) (%vi-cmd-r))
      ((= c 82) (%vi-start-replace!))
      ((= c 74) (%vi-cmd-J))
      ((= c 126) (%vi-cmd-tilde))
      ((%vi-one-of? c (list 68 67)) (%vi-cmd-DC c))
      ((= c 85) (%vi-cmd-U))
      ((= c 58) (%vi-colon (%vi-get-input-line ":")))
      ((if (= c 12) #t (= c 18)) (%vi-redraw! #t))
      ((= c 7) (set! %vi-last-status ()))
      ((= c 27) (%vi-cmd-escape))
      ((= c 90) (%vi-cmd-z))
      ((= c 119) (%vi-cmd-w))
      ((%vi-one-of? c (list 98 101)) (%vi-cmd-be c))
      ((%vi-one-of? c (list 87 66 69)) (%vi-cmd-wbe-blank c))
      ((%vi-one-of? c (list 102 70 116 84)) (%vi-cmd-find c))
      ((%vi-one-of? c (list 59 44)) (%vi-cmd-refind c))
      ((= c 71) (%vi-cmd-G))
      ((= c 103) (%vi-cmd-g))
      ((%vi-one-of? c (list 72 76)) (%vi-cmd-HL c))
      ((= c 77) (%vi-cmd-M))
      ((= c 94) (%vi-cmd-caret))
      ((= c 124) (%vi-cmd-bar))
      ((= c 37) (%vi-cmd-percent))
      ((%vi-one-of? c (list 123 125)) (%vi-cmd-paragraph c))
      ((%vi-one-of? c (list 2 6 21 4 25 5 -10 -11)) (%vi-cmd-scroll c))
      ((= c 122) (%vi-cmd-z-scroll))
      ((%vi-one-of? c (list 47 63)) (%vi-cmd-search c))
      ((= c 110) (%vi-search-again 1))
      ((= c 78) (%vi-search-again -1))
      (#t (do (%vi-not-implemented (bytes->str (list (%vi& c 255))))
              (%vi-end-cmd-q!))))))

; j, Return, + and the arrow: down a line, to the column aimed at, or past
; the blanks for Return and +
(def %vi-cmd-down
  (fn (_ c)
    (def q (%vi-lines-down %vi-dot))
    (if (null? q) (%vi-indicate-error)
      (do (set! %vi-dot q)
          (if (if (= c 13) #t (= c 43))
            (%vi-dot-skip-over-ws!)
            (%vi-to-cindex!))))))

(def %vi-lines-down
  (fn (self q)
    (def p (%vi-next-line q))
    (match
      ((= p (%vi-end-line q)) ())
      ((%vi< 1 %vi-cmdcnt) (do (set! %vi-cmdcnt (%vi- %vi-cmdcnt 1)) (self p)))
      (#t p))))

(def %vi-cmd-up
  (fn (_ c)
    (def q (%vi-lines-up %vi-dot))
    (if (null? q) (%vi-indicate-error)
      (do (set! %vi-dot q)
          (if (= c 45) (%vi-dot-skip-over-ws!) (%vi-to-cindex!))))))

(def %vi-lines-up
  (fn (self q)
    (def p (%vi-prev-line q))
    (match
      ((= p (%vi-begin-line q)) ())
      ((%vi< 1 %vi-cmdcnt) (do (set! %vi-cmdcnt (%vi- %vi-cmdcnt 1)) (self p)))
      (#t p))))

(def %vi-to-cindex!
  (fn (_)
    (set! %vi-dot
      (if (= %vi-cindex -1) (%vi-end-line %vi-dot) (%vi-move-to-col %vi-dot %vi-cindex)))
    (set! %vi-keep-index #t)))

(def %vi-cmd-digit
  (fn (_ c)
    (if (if (= c 48) (%vi< %vi-cmdcnt 1) #f)
      (%vi-dot-begin!)
      (set! %vi-cmdcnt (%vi+ (%vi* %vi-cmdcnt 10) (%vi- c 48))))))

(def %vi-cmd-dollar
  (fn (self)
    (%vi-dot-end!)
    (set! %vi-cmdcnt (%vi- %vi-cmdcnt 1))
    (if (%vi< 0 %vi-cmdcnt) (do (%vi-dot-next!) (self)) ())
    (set! %vi-cindex -1)
    (set! %vi-keep-index #t)))

(def %vi-cmd-append
  (fn (_)
    (if (= (byte-at %vi-text %vi-dot) 10) () (set! %vi-dot (%vi+ %vi-dot 1)))
    (%vi-start-insert!)))

(def %vi-cmd-open-below
  (fn (_)
    (%vi-dot-end!)
    (%vi-cmd-open)))

(def %vi-cmd-open-above
  (fn (_)
    (%vi-dot-begin!)
    (%vi-cmd-open)
    (%vi-dot-prev!)))

(def %vi-cmd-open
  (fn (_)
    (set! %vi-cmd-mode 1)
    (set! %vi-dot (%vi-char-insert %vi-dot 10))))

; x, X and s: the byte under the cursor, or before it, COUNT times, never a
; newline; s goes on into insert mode
(def %vi-cmd-x
  (fn (_ c)
    (%vi-repeat
      (fn (_)
        (def at (if (= c 88) (%vi- %vi-dot 1) %vi-dot))
        (if (if (%vi< at 0) #t (= (byte-at %vi-text at) 10)) ()
          (do (set! %vi-dot at)
              (set! %vi-dot (%vi-yank-delete %vi-dot %vi-dot 0 #t))))))
    (%vi-end-cmd-q!)
    (if (= c 115) (%vi-start-insert!) ())))

(def %vi-cmd-delete-key
  (fn (_)
    (if (%vi< %vi-dot (%vi- %vi-end 1))
      (set! %vi-dot (%vi-yank-delete %vi-dot %vi-dot 0 #t))
      ())))

; busybox's get_motion_char: the key after an operator, a count typed before
; it multiplying the operator's
(def %vi-get-motion-char
  (fn (_)
    (def c (%vi-get-one-char))
    (if (if (%vi-digit? c) (if (= c 48) #f #t) #f)
      (%vi-motion-count c 0)
      (do (if (= c 48) (set! %vi-cmdcnt 0) ()) c))))

(def %vi-motion-count
  (fn (self c cnt)
    (if (%vi-digit? c)
      (self (%vi-get-one-char) (%vi+ (%vi* cnt 10) (%vi- c 48)))
      (do (set! %vi-cmdcnt (%vi* (if (= %vi-cmdcnt 0) 1 %vi-cmdcnt) cnt)) c))))

(def %vi-cmd-escape
  (fn (_)
    (if (= %vi-cmd-mode 0) (%vi-indicate-error) ())
    (set! %vi-cmd-mode 0)
    (%vi-end-cmd-q!)
    (set! %vi-last-status ())))

; ZZ writes a changed file and ends, unless files are left to edit; ZQ ends
(def %vi-cmd-z
  (fn (_)
    (def c (%vi-get-one-char))
    (match
      ((= c 81) (do (set! %vi-editing 0) (set! %vi-optind (length %vi-files))))
      ((if (= c 90) #f #t) (%vi-indicate-error))
      ((= %vi-modified 0) (%vi-zz-ends))
      ((if (= %vi-readonly 0) #f (if (null? %vi-filename) #f #t))
        (%vi-status-line-bold! (string-append "'" %vi-filename "' is read only")))
      (#t (%vi-zz-written (%vi-file-write %vi-filename 0 %vi-end))))))

(def %vi-zz-written
  (fn (_ cnt)
    (match
      ((Err err? cnt) (%vi-status-line-bold! (string-append "Write error: " (file-err-text cnt))))
      ((= cnt %vi-end) (%vi-zz-ends))
      (#t ()))))

(def %vi-zz-ends
  (fn (_)
    (def more (%vi- (%vi- (length %vi-files) %vi-optind) 1))
    (if (%vi< 0 more)
      (do (set! %vi-modified 0)
          (%vi-status-line-bold! (string-append (%cu-int->str more) " more file(s) to edit")))
      (set! %vi-editing 0))))

; --- files ------------------------------------------------------------------

; busybox's file_write: the text [FROM, TO) into NAME, opened without O_TRUNC
; and cut to what was written; answers the bytes written, -2 with no name, or
; the io Err the open failed with
(def %vi-file-write
  (fn (_ name from to)
    (if (null? name) -2
      (%vi-write-fd (file-open-or-err (fn (_ p) (File open p (list (lit wronly) (lit creat)) 438)) name)
        from to))))

(def %vi-write-fd
  (fn (_ fd from to)
    (if (Err err? fd) fd
      (%vi-write-close fd (%vi-write-all fd from (%vi- to from) 0)))))

(def %vi-write-close
  (fn (_ fd n)
    (file-truncate fd n)
    (file-close fd)
    n))

(def %vi-write-all
  (fn (self fd at left done)
    (if (%vi< 0 left)
      (%vi-wrote self fd at left done
        (%cu-ptr-call %vi-c-write fd (%vi+ %vi-taddr at) left))
      done)))
(def %vi-wrote
  (fn (_ again fd at left done r)
    (if (%vi< 0 r)
      (again fd (%vi+ at r) (%vi- left r) (%vi+ done r))
      done)))

; busybox's file_insert: NAME's bytes put in at P; answers the count read, or
; -1 when it could not be opened.  The first file read is read-only when it
; cannot be written.
(def %vi-file-insert
  (fn (_ name p initial?)
    (def fd (file-open-or-err file-open-read name))
    (if (Err err? fd)
      (do (if initial? () (%vi-status-line-bold! (string-append "'" name "' " (file-err-text fd))))
          -1)
      (%vi-file-insert-fd name fd p initial?))))

(def %vi-file-insert-fd
  (fn (_ name fd p initial?)
    (def st (file-stat-full name))
    (def cnt
      (if (if (null? st) #f (eq? (Assoc get (lit kind) st) (lit file)))
        (%vi-read-in fd p (Assoc get (lit size) st) name)
        (do (%vi-status-line-bold! (string-append "'" name "' is not a regular file")) -1)))
    (file-close fd)
    (if (if initial? (%vi-unwritable? name st) #f) (set! %vi-readonly 1) ())
    cnt))

(def %vi-unwritable?
  (fn (_ name st)
    (if (%vi< (%cu-ptr-call %vi-c-access name 2) 0) #t
      (if (null? st) #f (= (%vi& (Assoc get (lit mode) st) 146) 0)))))

(def %vi-read-in
  (fn (_ fd p size name)
    (%vi-hole-make! p size)
    (def cnt (%vi-read-all fd p size 0))
    (if (%vi< cnt size)
      (do (%vi-hole-delete! (%vi+ p cnt) (%vi- (%vi+ p size) 1))
          (%vi-status-line-bold! (string-append "can't read '" name "'")))
      ())
    (set! %vi-nl-total (%vi+ %vi-nl-total (%vi-newlines-in p (%vi+ p cnt))))
    cnt))

(def %vi-read-all
  (fn (self fd at left done)
    (if (%vi< 0 left)
      (%vi-read-got self fd at left done
        (%cu-ptr-call %vi-c-read fd (%vi+ %vi-taddr at) left))
      done)))
(def %vi-read-got
  (fn (_ again fd at left done r)
    (if (%vi< 0 r) (again fd (%vi+ at r) (%vi- left r) (%vi+ done r)) done)))

; busybox's init_text_buffer: the text is NAME's, or one empty line
(def %vi-init-text-buffer!
  (fn (_ name)
    (%vi-text-init!)
    (%vi-update-filename! name)
    (set! %vi-readonly 0)
    (def rc (if (null? name) -1 (%vi-file-insert name 0 #t)))
    (if (if (%vi< rc 1) #t (if (= (byte-at %vi-text (%vi- %vi-end 1)) 10) #f #t))
      (%vi-byte-insert! %vi-end 10)
      ())
    (set! %vi-modified 0)
    (set! %vi-marks (Vector make 28 -1))
    rc))

; --- the session ------------------------------------------------------------

; the terminal's settings while raw, and the ways back
(def %vi-raw! ())
(def %vi-cooked! ())

; busybox's edit_file: NAME read, then keys until a command ends the editing
(def %vi-edit-file
  (fn (_ name)
    (set! %vi-editing 1)
    (%vi-raw!)
    (set! %vi-rows 24)
    (set! %vi-columns 80)
    (%vi-window-check #t)
    (%vi-new-screen!)
    (%vi-init-text-buffer! name)
    (%vi-mark! 26 0)
    (%vi-mark! 27 0)
    (set! %vi-crow 0)
    (set! %vi-ccol 0)
    (%vi-reset!)
    (%vi-redraw! #f)
    (def end (%vi-keys ()))
    (%vi-bottom-clear)
    (%vi-flush!)
    (%vi-cooked!)
    end))

(def %vi-reset!
  (fn (_)
    (set! %vi-cmd-mode 0)
    (set! %vi-cmdcnt 0)
    (set! %vi-offset 0)))

; one key at a time while the editing lasts; answers nil, or the Err that
; ended the input
(def %vi-keys
  (fn (self ended)
    (if (if (%vi< 0 %vi-editing) (null? ended) #f)
      (self (%vi-one-key))
      ended)))

(def %vi-one-key
  (fn (_)
    (guard (e (%vi-caught e))
      (%vi-key-step))))

; a key done, then the screen drawn and the heap swept -- unless more keys are
; already waiting, as when text is pasted: then they come first
(def %vi-key-step
  (fn (_)
    (def c (%vi-get-one-char))
    (%vi-line-kept!)
    (%vi-do-cmd c)
    (if (if (null? %vi-kbuf) (if (%vi-src-ready? 0) #f #t) #f)
      (do (%vi-refresh! #f) (%vi-show-status-line!) (%cu-heap-collect))
      ())
    ()))

; ^C from a terminal: back to the top in command mode, as busybox's
; siglongjmp to its restart point; the end of the input ends the editing
(def %vi-caught
  (fn (_ e)
    (match
      ((eq? (%cu-err-label e) (lit vi-interrupt))
        (do (set! %vi-screenbegin 0) (set! %vi-dot 0) (%vi-reset!) (%vi-redraw! #f) ()))
      ((eq? (%cu-err-label e) (lit vi-eof)) e)
      (#t (error e)))))

; busybox's INIT_G: every run starts from the same state, whatever the run
; before it left -- the column j aims for, the registers, the left offset
(def %vi-init-g!
  (fn (_)
    (set! %vi-optind 0)
    (set! %vi-kbuf ())
    (set! %vi-out ())
    (set! %vi-status "")
    (set! %vi-have-status 0)
    (set! %vi-bottom "")
    (set! %vi-last-status ())
    (set! %vi-regs (Vector make 28 ()))
    (set! %vi-yank-count 0)
    (set! %vi-cur-line -1)
    (set! %vi-ydreg 26)
    (set! %vi-cindex 0)
    (set! %vi-keep-index #f)
    (set! %vi-cmd-error #f)
    (set! %vi-offset 0)
    (set! %vi-old-offset 0)
    (set! %vi-rstart 0)
    (set! %vi-tabstop 8)
    (set! %vi-last-search-char 0)
    (set! %vi-last-search-cmd 0)
    (set! %vi-last-search-pattern "")
    (set! %vi-filename ())
    (set! %vi-alt-filename ())
    (set! %vi-screen ())))

; busybox's vi_main: each file in turn on the alternate screen
(def %vi-main
  (fn (_ files)
    (%vi-resolve!)
    (%vi-init-g!)
    (set! %vi-files files)
    (%vi-put %vi-alt-on)
    (guard (e (do (%vi-cooked!) (error e)))
      (%vi-each-file))))

(def %vi-each-file
  (fn (self)
    (def ended (%vi-edit-file (if (null? %vi-files) () (List ref %vi-optind %vi-files))))
    (set! %vi-optind (%vi+ %vi-optind 1))
    (match
      ((not (null? ended)) (%vi-input-ended))
      ((%vi< %vi-optind (length %vi-files)) (self))
      (#t (do (%vi-put %vi-alt-off) (%vi-flush!) 0)))))

(def %vi-input-ended
  (fn (_)
    (file-write 2 "vi: can't read user input\n")
    1))

; the applet: keys from the terminal on stdin, the screen to stdout
(def %cu-vi
  (fn (_ argv . stdin)
    (cu-stdin-to-command!)
    (set! %vi-src-read %vi-tty-read)
    (set! %vi-src-ready? %vi-tty-ready?)
    (set! %vi-sink %vi-tty-write)
    (set! %vi-window (fn (_) (Term window 0)))
    (def saved (list ()))
    (set! %vi-raw! (fn (_) (set-first! saved (Term raw! 0)) (set! %vi-tty? (if (null? (first saved)) #f #t))))
    (set! %vi-cooked! (fn (_) (Term restore! 0 (first saved))))
    (%vi-main argv)))

; busybox's readit: wait until a byte can be read, then read it.  stdin may
; come non-blocking, so a read that would block, or was interrupted, is tried
; again; any other failure, like the end, ends the input.
(def %vi-byte-buf (%str-make-raw 1))
(def %vi-tty-read
  (fn (self)
    (%vi-poll 0 1 -1)
    (def r (File read 0 %vi-byte-buf 1))
    (match
      ((%vi< 0 r) (%vi& (byte-at %vi-byte-buf 0) 255))
      ((= r 0) ())
      ((%vi-again? r) (self))
      (#t ()))))

(def %vi-again?
  (fn (_ r)
    (def sym (file-err-sym (Err from-errno (Err errno-of r) (lit read) "stdin")))
    (if (eq? sym (lit eagain)) #t (eq? sym (lit eintr)))))

(def %vi-tty-ready?
  (fn (_ ms)
    (%vi-flush!)
    (%vi< 0 (%vi-poll 0 1 ms))))

; poll(2) on FD for EVENTS (1 in, 4 out), MS milliseconds, -1 for ever: struct
; pollfd is an int fd and two shorts, the events first
(def %vi-pollfd (%str-make-raw 8))
(def %vi-poll
  (fn (_ fd events ms)
    (def p (%vi-str->ptr %vi-pollfd))
    (%vi-ptr-set! p 0 fd 4)
    (%vi-ptr-set! p 4 events 2)
    (%vi-ptr-set! p 6 0 2)
    (%cu-ptr-call %vi-c-poll p 1 ms)))

; the screen's bytes all written to stdout, waiting while it is full
(def %vi-tty-write
  (fn (self s)
    (def n (byte-len s))
    (def r (File write 1 s n))
    (match
      ((= r n) ())
      ((%vi< 0 r) (self (%vi-bsub s r (%vi- n r))))
      ((%vi-again? r) (do (%vi-poll 1 4 -1) (self s)))
      (#t ()))))

; --- for the specs ----------------------------------------------------------

; a run with typed keys: BURSTS a list of strings, each typed at once, with a
; pause between them; ROWS by COLS the window.  Answers the exit status; what
; was drawn is in %vi-drawn.
(def %vi-drawn ())
(def %vi-burst "")
(def %vi-burst-i 0)
(def %vi-bursts ())

(def %vi-typed
  (fn (_ files bursts rows cols tty?)
    (set! %vi-burst "")
    (set! %vi-burst-i 0)
    (set! %vi-bursts bursts)
    (set! %vi-drawn ())
    (set! %vi-src-read %vi-typed-read)
    (set! %vi-src-ready? (fn (_ . ms) (%vi< %vi-burst-i (byte-len %vi-burst))))
    (set! %vi-sink (fn (_ s) (set! %vi-drawn (pair s %vi-drawn))))
    (set! %vi-window (fn (_) (pair cols rows)))
    (set! %vi-raw! (fn (_) (set! %vi-tty? tty?)))
    (set! %vi-cooked! (fn (_) ()))
    (%vi-main files)))

(def %vi-typed-read
  (fn (self)
    (match
      ((%vi< %vi-burst-i (byte-len %vi-burst))
        (do (set! %vi-burst-i (%vi+ %vi-burst-i 1))
            (%vi& (byte-at %vi-burst (%vi- %vi-burst-i 1)) 255)))
      ((null? %vi-bursts) ())
      (#t (do (set! %vi-burst (first %vi-bursts))
              (set! %vi-bursts (rest %vi-bursts))
              (set! %vi-burst-i 0)
              (self))))))
