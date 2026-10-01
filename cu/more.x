; # x-coreutils -- the small tools, as applets
;
; ## cu/more.x -- more, clear, reset
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; busybox's more (util-linux/more.c): with standard output a terminal it pages,
; reading its keys from /dev/tty; otherwise it is cat.  The file goes out a
; byte at a time as busybox's does -- a tab to the next stop of eight, a line
; wider than the window folded -- and when the window's height less one is
; full it asks `--More--`, with how far it is through a file whose size it
; knows.  Space shows a page, Enter a line, r the rest, q quits; any other key
; is told those four.
;
; The keys come through x's Term, whose raw mode is cfmakeraw's: Enter arrives
; as a carriage return, a newline no longer returns the carriage, and Ctrl-C is
; a byte rather than a signal.  busybox's more turns off only the line editing
; and the echo, so here a carriage return is Enter, a newline goes out as a
; carriage return and a newline, and Ctrl-C or Ctrl-\ does what busybox's
; signal handler does: a newline on stderr, the terminal put back, status 1.
; The end of the keys ends the paging; busybox's would ask again for ever.
;
; Where the keys come from and where the screen goes are swappable, so a spec
; can type at it and read back what it drew.

(import x/repl/term)

; --- the doors --------------------------------------------------------------

(def %more/ (prim-ref (lit int) (lit /)))
(def %more-cr (bytes->str (list #\return)))
(def %more-esc (bytes->str (list #\escape)))
; the byte a control key types: Ctrl-C is 3
(def %more-ctrl (fn (_ c) (& c 31)))

(def %more-key ())          ; the next key's byte, or nil at the end of them
(def %more-sink ())         ; writes a string to the screen
(def %more-window ())       ; the window's (COLUMNS . ROWS)

; --- the state of a run -------------------------------------------------------

(def %more-out ())          ; what is to be written, newest first
(def %more-width 80)
(def %more-height 23)
(def %more-len 0)           ; the column the next byte goes to
(def %more-lines 0)         ; the lines shown since the last prompt
(def %more-please #f)       ; the prompt is due before the next byte
(def %more-spaces 0)        ; the spaces a tab still owes
(def %more-input 0)         ; the last key: Enter keeps a prompt on each line, r none
(def %more-pos 0)           ; the bytes of this file read
(def %more-size 0)          ; its size, 0 when unknown
(def %more-stop ())         ; nil, or the status the run ends with

(def %more-put (fn (_ s) (set! %more-out (pair s %more-out))))

(def %more-flush!
  (fn (_)
    (if (null? %more-out) ()
      (do (%more-sink (string-concat (reverse %more-out)))
          (set! %more-out ())))))

; busybox's get_wh: the window, never narrower or shorter than two, its height
; less the line the prompt takes
(def %more-measure!
  (fn (_)
    (let ((w (%more-window)))
      (do (set! %more-width (if (< (first w) 2) 2 (first w)))
          (set! %more-height (- (if (< (rest w) 2) 2 (rest w)) 1))))))

; --- the prompt ---------------------------------------------------------------

(def %more-help "(Enter:next line Space:next page Q:quit R:show the rest)")

; `--More-- `, with `(P% of S bytes)` when the size is known
(def %more-prompt-text
  (fn (_)
    (if (= %more-size 0) "--More-- "
      (let ((d (if (< %more-size 100) 1 (%more/ %more-size 100))))
        (string-concat
          (list "--More-- (" (%cu-int->str (%more/ %more-pos d))
                "% of " (%cu-int->str %more-size) " bytes)"))))))

; a key as busybox's tolower reads it, Enter as a newline
(def %more-lower
  (fn (_ k)
    (match
      ((= k #\return) #\newline)
      ((if (>= k #\A) (<= k #\Z) #f) (+ k (- #\a #\A)))
      (#t k))))

; Ask, and wait for a key that is one of the four.  Each key first erases what
; was asked -- a carriage return, as many spaces, a carriage return.
(def %more-ask!
  (fn (_)
    (def ask
      (fn (self len)
        (do (%more-flush!)
          (let ((k (%more-key)))
            (do (%more-put (string-concat (list %more-cr (%cu-pad-left "" len) %more-cr)))
              (match
                ((null? k) (set! %more-stop 0))
                ((if (= k (%more-ctrl #\C)) #t (= k (%more-ctrl #\\)))
                  (do (%more-flush!) (file-write 2 "\n") (set! %more-stop 1)))
                (#t
                  (let ((c (%more-lower k)))
                    (match
                      ((= c #\q) (set! %more-stop 0))
                      ((if (= c #\space) #t (if (= c #\newline) #t (= c #\r)))
                        (set! %more-input c))
                      (#t (do (%more-put %more-help)
                              (self (byte-len %more-help)))))))))))))
    (let ((text (%more-prompt-text)))
      (do (%more-put text)
          (ask (byte-len text))
          (set! %more-len 0)
          (set! %more-lines 0)
          (set! %more-please #f)
          (%more-measure!)))))

; --- the bytes ----------------------------------------------------------------

; One byte C to the screen, from busybox's loop_top: the prompt first if one is
; due, then the byte -- unless it is the first to pass the window's width, which
; ends the line and comes round again, for the next line, after any prompt.
(def %more-emit
  (fn (self c)
    (do
      (if (if %more-please (not (= %more-input #\r)) #f) (%more-ask!) ())
      (if (null? %more-stop)
        (let ((c (if (= c #\tab)
                   (do (set! %more-spaces (- 7 (% %more-len 8))) #\space)
                   c)))
          (do (set! %more-len (+ %more-len 1))
              (let ((wrap (> %more-len %more-width)))
                (do (if (if (= c #\newline) #t wrap)
                      (do (set! %more-lines (+ %more-lines 1))
                          (if (if (>= %more-lines %more-height) #t (= %more-input #\newline))
                            (set! %more-please #t) ())
                          (set! %more-len 0))
                      ())
                    (if (if wrap (not (= c #\newline)) #f)
                      (self c)
                      (do (%more-put (%cu-b->s c))
                          (if (= c #\newline) (%more-flush!) ())))))))
        ()))))

; A byte read from the file: it, and the spaces it leaves owed if it is a tab.
(def %more-byte
  (fn (_ c)
    (do (set! %more-pos (+ %more-pos 1))
        (%more-emit c)
        (def owed
          (fn (self)
            (if (if (null? %more-stop) (> %more-spaces 0) #f)
              (do (set! %more-spaces (- %more-spaces 1))
                  (%more-emit #\space)
                  (self))
              ())))
        (owed))))

; a piece of the file taken a byte at a time, sweeping as it goes; enough once
; the run is to stop
(def %more-take
  (fn (_ r s)
    (def text (first r))
    (def n (rest r))
    (def go
      (fn (self i)
        (if (if (< i n) (null? %more-stop) #f)
          (do (if (= (& i %cu-sweep-bytes) 0) (%cu-sweep! i) ())
              (%more-byte (byte-at text i))
              (self (+ i 1)))
          ())))
    (do (go 0)
        (if (null? %more-stop) s (%cu-enough s)))))

; the size more says it is through: a file's, or 0 for standard input
(def %more-size-of
  (fn (_ name)
    (if (string=? name "-") 0
      (let ((st (file-stat-full name)))
        (if (null? st) 0 (%cu-stat-get st (lit size)))))))

; each operand in turn, paged; one that will not open is said and passed
(def %more-page
  (fn (_ ops stdin-thunk)
    (def says (%cu-says "more"))
    (def each
      (fn (self names)
        (if (if (null? names) #t (not (null? %more-stop))) ()
          (do (set! %more-size (%more-size-of (first names)))
              (set! %more-pos 0)
              (set! %more-please #f)
              (set! %more-len 0)
              (set! %more-lines 0)
              (%more-measure!)
              (let ((r (%cu-fold-one (first names) stdin-thunk %more-take ())))
                (if (null? (rest r)) ()
                  (%cu-say says (first names) (rest r))))
              (%more-flush!)
              (self (rest names))))))
    (do (set! %more-out ())
        (set! %more-spaces 0)
        (set! %more-input 0)
        (set! %more-stop ())
        (each (if (null? ops) (list "-") ops))
        (%more-flush!)
        (if (null? %more-stop) 0 %more-stop))))

; --- the applet ---------------------------------------------------------------

; standard output not a terminal, or no terminal to read keys from: cat
(def %more-cat
  (fn (_ ops stdin-thunk)
    (rest (%cu-fold-said ops stdin-thunk (%cu-says "more")
            (fn (_ p s) (do (file-write-run 1 p) s)) ()))))

; the screen's bytes to standard output, a newline returning the carriage
(def %more-tty-write
  (fn (_ s)
    (let ((t (Str8 replace "\n" (string-append %more-cr "\n") s)))
      (file-write 1 t))))

(def %cu-more
  (fn (_ argv stdin-thunk)
    (def o (%cu-opts "more" argv))
    (def ops (Opts operands o))
    (def tty (if (sys-isatty 1) (file-open-or-err file-open-read "/dev/tty") ()))
    (if (if (null? tty) #t (Err err? tty)) (%more-cat ops stdin-thunk)
      (let ((saved (Term raw! tty)))
        (do (set! %more-key
              (fn (_)
                (let ((b (file-read-fd tty 1)))
                  (if (= (byte-len b) 0) () (byte-at b 0)))))
            (set! %more-sink %more-tty-write)
            (set! %more-window (fn (_) (Term window tty)))
            (let ((st (%more-page ops stdin-thunk)))
              (do (Term restore! tty saved)
                  (file-close tty)
                  st)))))))

; --- for the specs ------------------------------------------------------------

; A run with typed KEYS, a string, against a ROWS by COLS window, the file
; operands ARGV and standard input STDIN.  Answers (STATUS . DRAWN), DRAWN
; everything written to the screen, newlines as more writes them.
(def %more-typed
  (fn (_ argv stdin keys rows cols)
    (def drawn (list ()))
    (def i (list 0))
    (set! %more-key
      (fn (_)
        (if (>= (first i) (byte-len keys)) ()
          (let ((b (byte-at keys (first i))))
            (do (set-first! i (+ (first i) 1)) b)))))
    (set! %more-sink (fn (_ s) (set-first! drawn (pair s (first drawn)))))
    (set! %more-window (fn (_) (pair cols rows)))
    (let ((st (%more-page (Opts operands (%cu-opts "more" argv))
                (%cu-string-stdin stdin))))
      (pair st (string-concat (reverse (first drawn)))))))

; --- clear, reset -------------------------------------------------------------

; busybox's clear: the cursor home, and the screen cleared from there
(def %cu-clear
  (fn (_ argv stdin-thunk)
    (do (file-write 1 (string-concat (list %more-esc "[H" %more-esc "[J"))) 0)))

; busybox's reset, built without its own stty: with standard output a
; terminal, the console reset, the US character set, the attributes off, the
; screen cleared below and the cursor shown -- then `stty sane`, the terminal's
; settings put back, by whichever stty the path finds.  There being none is not
; a failure.
(def %reset-codes
  (string-concat (list %more-esc "c" %more-esc "(B" %more-esc "[m" %more-esc "[J"
                       %more-esc "[?25h")))

(def %cu-reset
  (fn (_ argv stdin-thunk)
    (if (sys-isatty 1)
      (do (file-write 1 %reset-codes)
          (cu-stdin-to-command!)
          (sys-exec "stty" (list "sane"))
          0)
      0)))
