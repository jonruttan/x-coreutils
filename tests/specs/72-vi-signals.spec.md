# @weight 1

vi and the signals busybox's vi catches, as its handlers answer them:
SIGWINCH measures the window and draws all of the screen again, SIGTSTP
gives the terminal back and stops vi until SIGCONT, and SIGINT (^C) goes
back to the top of the file in command mode, dropping what was being typed.
When nothing says how big the window is -- the terminal does not, and
neither $LINES nor $COLUMNS is set -- vi asks the terminal where its cursor
is after sending it past the bottom corner, and takes the answer as the
size.  Each case types keys at the editor through `%vi-typed`, given the
words after `vi` and an environment of its own, in bursts with a pause
between two; a burst may instead be a signal arriving in the pause.  Each
shows the exit status, the file, and the screen: the rows, the bottom line,
the cursor and the bells.  A case that ends without :wq ends when its keys
do, with status 1.

The screen is every byte vi wrote, drawn on a model of the terminal, the
same model that draws busybox's.  Every expectation is busybox vi's own,
built from its source with every vi feature on but regex search, given the
same words, environment, keys and signals through a pipe with the same
pauses, except the window resized, which a pipe cannot be.
## the fixtures

### a typist for vi

`vi-b` makes a burst from strings and named keys; `vi-case` writes the file,
types the bursts, and draws what came of them.

```cu
(def vi-keys
  (list (pair (lit esc) (bytes->str (list 27))) (pair (lit cr) (bytes->str (list 13)))
        (pair (lit bs) (bytes->str (list 127))) (pair (lit ctrl-c) (bytes->str (list 3)))
        (pair (lit up) (string-append (bytes->str (list 27)) "[A"))
        (pair (lit down) (string-append (bytes->str (list 27)) "[B"))
        (pair (lit right) (string-append (bytes->str (list 27)) "[C"))
        (pair (lit left) (string-append (bytes->str (list 27)) "[D"))))
(def vi-b
  (fn (_ . parts)
    (string-concat
      (List map (fn (_ p) (if (symbol? p) (Assoc get p vi-keys) p)) parts))))
(def vi-byte
  (fn (_ b)
    (if (if (= b #\newline) #t (if (< b #\space) #f (< b #\delete)))
      (bytes->str (list b))
      (bytes->str (list 92 (%vi+ 48 (%vi/ b 64)) (%vi+ 48 (%vi% (%vi/ b 8) 8)) (%vi+ 48 (%vi% b 8)))))))
(def vi-shown
  (fn (_ s)
    (string-concat
      (List map (fn (_ i) (vi-byte (& (byte-at s i) 255))) (List range 0 (byte-len s))))))
(def vi-trim
  (fn (self s)
    (if (if (< 0 (byte-len s)) (= (byte-at s (- (byte-len s) 1)) #\space) #f)
      (self (substring s 0 (- (byte-len s) 1)))
      s)))

; the terminal: ROWS rows of COLS bytes, the cursor, whether the next byte
; wraps first; the bottom row as it stood before its last clear and where
; the cursor was before it went there; the bells and the flashes
(def vt-rows 0)
(def vt-cols 0)
(def vt-grid ())
(def vt-r 0)
(def vt-c 0)
(def vt-wrap #f)
(def vt-lb "")
(def vt-lbr -1)
(def vt-lbc 0)
(def vt-pend #f)
(def vt-pr 0)
(def vt-pc 0)
(def vt-bells 0)
(def vt-flashes 0)

(def vt-draw
  (fn (_ drawn rows cols)
    (set! vt-rows rows)
    (set! vt-cols cols)
    (set! vt-grid (vt-grid-new rows cols))
    (set! vt-r 0)
    (set! vt-c 0)
    (set! vt-wrap #f)
    (set! vt-lb "")
    (set! vt-lbr -1)
    (set! vt-lbc 0)
    (set! vt-pend #f)
    (set! vt-pr 0)
    (set! vt-pc 0)
    (set! vt-bells 0)
    (set! vt-flashes 0)
    (vt-run! (string-concat (reverse drawn)) 0)
    (vt-shown)))

(def vt-row
  (fn (_ n)
    (def s (%str-make-raw n))
    (vt-fill (%vi-str->ptr s) 0 n)
    s))
(def vt-fill
  (fn (self p i n) (if (%vi< i n) (do (%vi-ptr-set! p i 32 1) (self p (%vi+ i 1) n)) ())))
(def vt-grid-new
  (fn (self n cols) (if (%vi< 0 n) (pair (vt-row cols) (self (%vi- n 1) cols)) ())))
(def vt-set! (fn (_ r c b) (%vi-ptr-set! (%vi-str->ptr (List ref r vt-grid)) c b 1)))
(def vt-clear-from!
  (fn (self r c) (if (%vi< c vt-cols) (do (vt-set! r c 32) (self r (%vi+ c 1))) ())))
(def vt-text (fn (_ r) (vi-trim (%vi-bsub (List ref r vt-grid) 0 vt-cols))))

(def vt-newline!
  (fn (_)
    (if (= vt-r (%vi- vt-rows 1))
      (set! vt-grid (List append (rest vt-grid) (list (vt-row vt-cols))))
      (set! vt-r (%vi+ vt-r 1)))))

(def vt-put!
  (fn (_ b)
    (if vt-wrap (do (set! vt-c 0) (vt-newline!) (set! vt-wrap #f)) ())
    (vt-set! vt-r vt-c b)
    (if (= vt-c (%vi- vt-cols 1)) (set! vt-wrap #t) (set! vt-c (%vi+ vt-c 1)))))

(def vt-run!
  (fn (self s i)
    (def n (byte-len s))
    (def x (if (%vi< i n) (%vi& (byte-at s i) 255) -1))
    (match
      ((%vi< x 0) ())
      ((if (= x #\escape) (if (%vi< (%vi+ i 1) n) (= (byte-at s (%vi+ i 1)) #\[) #f) #f)
        (self s (vt-csi-at s (%vi+ i 2) n)))
      ((= x #\escape) (self s (%vi+ i 1)))
      (#t (do (vt-byte! x) (self s (%vi+ i 1)))))))

(def vt-byte!
  (fn (_ x)
    (match
      ((= x #\alarm) (set! vt-bells (%vi+ vt-bells 1)))
      ((= x #\return) (do (set! vt-c 0) (set! vt-wrap #f)))
      ((= x #\newline) (vt-newline!))
      ((= x #\backspace) (do (if (%vi< 0 vt-c) (set! vt-c (%vi- vt-c 1)) ()) (set! vt-wrap #f)))
      ((if (%vi< x #\space) #f (%vi< x #\delete)) (vt-put! x))
      ((%vi< #\~ x) (vt-put! 63))
      (#t ()))))

; ESC [, its parameters -- digits, ; and ? -- and the byte that ends it
(def vt-csi-at
  (fn (_ s j n)
    (def k (vt-params-end s j n))
    (if (%vi< k n) (vt-csi! (%vi-bsub s j (%vi- k j)) (%vi& (byte-at s k) 255)) ())
    (%vi+ k 1)))
(def vt-params-end
  (fn (self s j n)
    (def b (if (%vi< j n) (%vi& (byte-at s j) 255) -1))
    (if (match ((= b #\;) #t) ((= b #\?) #t) (#t (%vi-in? b #\0 #\9)))
      (self s (%vi+ j 1) n)
      j)))

(def vt-csi!
  (fn (_ ps fin)
    (match
      ((= fin #\H) (vt-goto! (vt-param ps 0) (vt-param ps 1)))
      ((= fin #\K) (vt-clear-eol!))
      ((if (= fin #\h) (string=? ps "?5") #f) (set! vt-flashes (%vi+ vt-flashes 1)))
      ((= fin #\J) (vt-clear-eos!))
      (#t ()))))

; the Kth of PS's numbers, 1 when it is missing or empty
(def vt-param
  (fn (self ps k)
    (def semi (vt-index ps #\; 0))
    (match
      ((= k 0) (vt-num (if (%vi< semi 0) ps (%vi-bsub ps 0 semi))))
      ((%vi< semi 0) 1)
      (#t (self (%vi-bsub ps (%vi+ semi 1) (%vi- (byte-len ps) (%vi+ semi 1))) (%vi- k 1))))))
(def vt-num (fn (_ s) (if (= (byte-len s) 0) 1 (%vi-num-from s 0 (byte-len s) 0))))
(def vt-index
  (fn (self s b i)
    (match
      ((if (%vi< i (byte-len s)) #f #t) -1)
      ((= (byte-at s i) b) i)
      (#t (self s b (%vi+ i 1))))))

(def vt-goto!
  (fn (_ row col)
    (def nr (%vi- (%vi-max 1 (%vi-min row vt-rows)) 1))
    (if (if (= nr (%vi- vt-rows 1)) (if (= vt-r (%vi- vt-rows 1)) #f #t) #f)
      (do (set! vt-pr vt-r) (set! vt-pc vt-c) (set! vt-pend #t))
      ())
    (set! vt-r nr)
    (set! vt-c (%vi- (%vi-max 1 (%vi-min col vt-cols)) 1))
    (set! vt-wrap #f)))

(def vt-clear-eol!
  (fn (_)
    (if (= vt-r (%vi- vt-rows 1))
      (do (set! vt-lb (vt-text vt-r))
          (set! vt-lbr (if vt-pend vt-pr -1))
          (set! vt-lbc vt-pc))
      ())
    (vt-clear-from! vt-r vt-c)
    (set! vt-wrap #f)))

(def vt-clear-eos!
  (fn (self)
    (vt-clear-from! vt-r vt-c)
    (vt-clear-below! (%vi+ vt-r 1))))
(def vt-clear-below!
  (fn (self r) (if (%vi< r vt-rows) (do (vt-clear-from! r 0) (self (%vi+ r 1))) ())))

(def vt-shown
  (fn (_)
    (string-concat
      (list (string-concat
              (List map (fn (_ r) (string-append "|" (vt-text r) "\n"))
                (List range 0 (%vi- vt-rows 1))))
            "status " vt-lb "\n"
            "cursor " (if (%vi< vt-lbr 0) "0 0"
                        (string-append (%cu-int->str vt-lbr) " " (%cu-int->str vt-lbc)))
            " bells " (%cu-int->str vt-bells)
            (if (= vt-flashes 0) "" (string-append " flashes " (%cu-int->str vt-flashes)))
            "\n"))))

(def vi-case
  (fn (_ text bursts target . mode)
    (apply vi-case-in (List append (list 10 40 text bursts target) mode))))
(def vi-case-in
  (fn (_ rows cols text bursts target . mode)
    (vi-run-case rows cols text bursts (list target) () () (if (null? mode) () (first mode)))))
; the words after vi, the environment as ((NAME . VALUE) ...), and a .exrc
; as (MODE TEXT), or nil for none; vi-ask-case leaves the window without a
; size of its own, with WAITING already typed when vi starts; vi-pty-case
; starts it WROWS by WCOLS, a size the bursts may change, and draws the
; screen at ROWS by COLS, the size it ends at
(def vi-pty-case
  (fn (_ rows cols wrows wcols text bursts argv env exrc mode)
    (vi-run wrows wcols rows cols text bursts argv env exrc mode)))
(def vi-run-case
  (fn (_ rows cols text bursts argv env exrc mode)
    (vi-run rows cols rows cols text bursts argv env exrc mode)))
(def vi-ask-case
  (fn (_ rows cols waiting text bursts argv env exrc mode)
    (set! %vi-typed-waiting waiting)
    (vi-run 0 0 rows cols text bursts argv env exrc mode)))
(def vi-run
  (fn (_ wrows wcols rows cols text bursts argv env exrc mode)
    (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-vg && mkdir -p /tmp/x-cu-vg"))
    (if (null? text) () (file-write-all "/tmp/x-cu-vg/f" text))
    (if (null? mode) () (proc-run (list "/bin/chmod" mode "/tmp/x-cu-vg/f")))
    (if (null? exrc) ()
      (do (file-write-all "/tmp/x-cu-vg/.exrc" (first (rest exrc)))
          (proc-run (list "/bin/chmod" (first exrc) "/tmp/x-cu-vg/.exrc"))))
    (set! %vi-typed-env env)
    (def st (%vi-typed argv bursts wrows wcols))
    (set! %vi-typed-env ())
    (def f (if (file-exists? "/tmp/x-cu-vg/f") (vi-shown (file-read-all "/tmp/x-cu-vg/f")) "no file\n"))
    (display
      (string-concat
        (list "exit " (%cu-int->str st) "\n"
              (if (if (< 0 (byte-len f)) (= (byte-at f (- (byte-len f) 1)) #\newline) #t) f
                (string-append f " (no newline)\n"))
              "--\n"
              (vt-draw %vi-drawn rows cols))))))
(display "made")
```
---
    made

### the model of the terminal

Cursor moves, the bottom row cleared twice, a bell and a flash, a line that
wraps and scrolls the rows up, a backspace, and a clear to the end of the
screen: the same bytes vi-tools' model draws the same way.

```cu
(def vt-e (fn (_ s) (string-append (bytes->str (list 27)) s)))
(display
  (vt-draw
    (list (string-concat
            (list (vt-e "[1;1H") "hello" (vt-e "[2;3H") "ab" (vt-e "[3;1H") (vt-e "[K")
                  "status" (bytes->str (list 7)) (vt-e "[?5h") (vt-e "[3;1H") (vt-e "[K")
                  "wide line that wraps" (bytes->str (list 10 8)) "x" (vt-e "[1;4H") (vt-e "[J"))))
    3 10))
```
---
```output
|wid
|
status status
cursor 1 4 bells 1 flashes 1
```


### vi stops itself once for each SIGTSTP, and for nothing else

Stopped and continued, vi draws the screen it drew before, so the screens
below cannot tell a SIGTSTP answered from one ignored: the count of stops
can.

```cu
(proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-vg && mkdir -p /tmp/x-cu-vg"))
(file-write-all "/tmp/x-cu-vg/f" "one\ntwo\n")
(%vi-typed (list "/tmp/x-cu-vg/f") (list (vi-b "j") (lit tstp) (vi-b "x") (lit tstp)) 10 40)
(def vi-stops-tstp %vi-typed-stops)
(%vi-typed (list "/tmp/x-cu-vg/f") (list (vi-b "j") (lit winch) (lit int) (vi-b "x")) 10 40)
(display (list vi-stops-tstp %vi-typed-stops))
```
---
    (2 0)
## SIGWINCH draws the screen again

### in command mode, all of it drawn again at once

```cu
(vi-run-case 10 40 "one\ntwo\nthree\n" (list (vi-b "j") (lit winch) (vi-b "x")) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
two
three
--
|one
|wo
|three
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f [Modified] 2/3 66%
cursor 1 0 bells 0
```

### a count typed before it is kept

```cu
(vi-run-case 10 40 "one two three four\n" (list (vi-b "2") (lit winch) (vi-b "dw")) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one two three four
--
|three four
|~
|~
|~
|~
|~
|~
|~
|~
status Delete 0 lines (8 chars) from [D]
cursor 0 0 bells 0
```

### in insert mode, the text typed so far kept

```cu
(vi-run-case 10 40 "one\n" (list (vi-b "ihello") (lit winch) (vi-b "_world" (lit esc))) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
--
|hello_worldone
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f [Modified] 1/1 100%
cursor 0 10 bells 0
```

### while a : line is typed

```cu
(vi-run-case 10 40 "one\ntwo\n" (list (vi-b ":2") (lit winch) (vi-b (lit cr))) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
two
--
|one
|two
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f 2/2 100%
cursor 1 0 bells 0
```

### the bottom line's message kept

```cu
(vi-run-case 10 40 "one\n" (list (vi-b ":f" (lit cr)) (lit winch)) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
--
|one
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f 1/1 100%
cursor 0 0 bells 0
```

### two in a row

```cu
(vi-run-case 10 40 "one\ntwo\n" (list (vi-b "j") (lit winch) (lit winch) (vi-b "x")) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
two
--
|one
|wo
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f [Modified] 2/2 100%
cursor 1 0 bells 0
```

### with the screen scrolled down the file

```cu
(vi-run-case 6 40 "1\n2\n3\n4\n5\n6\n7\n8\n9\n" (list (vi-b "G") (lit winch) (vi-b "k")) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
1
2
3
4
5
6
7
8
9
--
|7
|8
|9
|~
|~
status - /tmp/x-cu-vg/f 8/9 88%
cursor 1 0 bells 0
```

## SIGTSTP stops vi, SIGCONT goes on

### in command mode

```cu
(vi-run-case 10 40 "one\ntwo\n" (list (vi-b "j") (lit tstp) (vi-b "x")) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
two
--
|one
|wo
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f [Modified] 2/2 100%
cursor 1 0 bells 0
```

### in insert mode, the text typed so far kept

```cu
(vi-run-case 10 40 "one\n" (list (vi-b "ihello") (lit tstp) (vi-b "_world" (lit esc))) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
--
|hello_worldone
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f [Modified] 1/1 100%
cursor 0 10 bells 0
```

### the bottom line's message

```cu
(vi-run-case 10 40 "one\n" (list (vi-b ":f" (lit cr)) (lit tstp)) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
--
|one
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f 1/1 100%
cursor 0 0 bells 0
```

## SIGINT goes back to the top of the file

### from the end of the file

```cu
(vi-run-case 10 40 "one\ntwo\nthree\n" (list (vi-b "G") (lit int) (vi-b "x")) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
two
three
--
|ne
|two
|three
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f [Modified] 1/3 33%
cursor 0 0 bells 0
```

### out of insert mode

```cu
(vi-run-case 10 40 "one\ntwo\n" (list (vi-b "jihello") (lit int) (vi-b "x")) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
two
--
|ne
|hellotwo
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f [Modified] 1/2 50%
cursor 0 0 bells 0
```

### a count typed before it is dropped

```cu
(vi-run-case 10 40 "one\ntwo\nthree\n" (list (vi-b "G2") (lit int) (vi-b "x")) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
two
three
--
|ne
|two
|three
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f [Modified] 1/3 33%
cursor 0 0 bells 0
```

### an operator waiting for its motion is dropped

```cu
(vi-run-case 10 40 "one\ntwo\n" (list (vi-b "jd") (lit int) (vi-b "j")) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
two
--
|one
|two
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f 2/2 100%
cursor 1 0 bells 0
```

### . after it repeats the change before it

```cu
(vi-run-case 10 40 "one\ntwo\nthree\n" (list (vi-b "Gx") (lit int) (vi-b ".")) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
two
three
--
|ne
|two
|hree
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f [Modified] 1/3 33%
cursor 0 0 bells 0
```

### out of a : line being typed

```cu
(vi-run-case 10 40 "one\ntwo\n" (list (vi-b "j:s/") (lit int) (vi-b "x")) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
two
--
|ne
|two
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f [Modified] 1/2 50%
cursor 0 0 bells 0
```

### with the screen scrolled down the file

```cu
(vi-run-case 6 40 "1\n2\n3\n4\n5\n6\n7\n8\n9\n" (list (vi-b "G") (lit int) (vi-b "x")) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
1
2
3
4
5
6
7
8
9
--
|
|2
|3
|4
|5
status - /tmp/x-cu-vg/f [Modified] 1/9 11%
cursor 0 0 bells 0
```

## ^C and ^Z through a pipe are only keys

### ^C typed

```cu
(vi-run-case 10 40 "one\n" (list (vi-b (lit ctrl-c))) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
--
|one
|~
|~
|~
|~
|~
|~
|~
|~
status '^C' is not implemented
cursor 0 0 bells 0
```

### ^Z typed

```cu
(vi-run-case 10 40 "one\n" (list (vi-b (bytes->str (list 26)))) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
--
|one
|~
|~
|~
|~
|~
|~
|~
|~
status '^Z' is not implemented
cursor 0 0 bells 0
```

## the terminal asked its size when nothing says it

### the answer sets the size

```cu
(vi-ask-case 5 40 (string-append (bytes->str (list 27)) "[5;40R") "one\ntwo\n" (list (vi-b "j")) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
two
--
|one
|two
|~
|~
status - /tmp/x-cu-vg/f 2/2 100%
cursor 1 0 bells 0
```

### no answer: 24 by 80

```cu
(vi-ask-case 24 80 "" "one\ntwo\n" (list (vi-b "j")) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
two
--
|one
|two
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f 2/2 100%
cursor 1 0 bells 0
```

### a key that is no answer is lost

```cu
(vi-ask-case 24 80 "j" "one\ntwo\n" (list (vi-b "x")) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
two
--
|ne
|two
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f [Modified] 1/2 50%
cursor 0 0 bells 0
```

### SIGWINCH after an answer measures again: 24 by 80

```cu
(vi-ask-case 24 80 (string-append (bytes->str (list 27)) "[5;40R") "one\ntwo\n" (list (vi-b "j") (lit winch) (vi-b "x")) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
two
--
|one
|wo
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f [Modified] 2/2 100%
cursor 1 0 bells 0
```

### $LINES set, so nothing asked

```cu
(vi-ask-case 7 80 "" "one\ntwo\n" (list (vi-b "j")) (list "/tmp/x-cu-vg/f") (list (pair "LINES" "7")) () ())
```
---
```output
exit 1
one
two
--
|one
|two
|~
|~
|~
|~
status - /tmp/x-cu-vg/f 2/2 100%
cursor 1 0 bells 0
```

### $COLUMNS set, so nothing asked

```cu
(vi-ask-case 24 30 "" "one\ntwo\n" (list (vi-b "j")) (list "/tmp/x-cu-vg/f") (list (pair "COLUMNS" "30")) () ())
```
---
```output
exit 1
one
two
--
|one
|two
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f 2/2 100%
cursor 1 0 bells 0
```

## the terminal's answer typed later

### in command mode, not implemented

```cu
(vi-run-case 10 40 "one\n" (list (vi-b (lit esc) "[5;5R")) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
--
|one
|~
|~
|~
|~
|~
|~
|~
|~
status '(NULL)' is not implemented
cursor 0 0 bells 0
```

### in insert mode

```cu
(vi-run-case 10 40 "one\n" (list (vi-b "i" (lit esc) "[5;5R") (vi-b "x" (lit esc))) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 1
one
--
|xone
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f [Modified] 1/1 100%
cursor 0 0 bells 0
```

## the window resized

### larger, all of it drawn at the new size

```cu
(vi-pty-case 12 50 10 40 "one\ntwo\n" (list (vi-b "j") (list (lit resize) 12 50) (vi-b "x") (vi-b ":q!" (lit cr))) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 0
one
two
--
|one
|wo
|~
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f [Modified] 2/2 100%
cursor 1 0 bells 0
```

### smaller, the cursor's line kept on the screen

```cu
(vi-pty-case 6 30 10 40 "1\n2\n3\n4\n5\n6\n7\n8\n9\n" (list (vi-b "G") (list (lit resize) 6 30) (vi-b "k") (vi-b ":q!" (lit cr))) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 0
1
2
3
4
5
6
7
8
9
--
|7
|8
|9
|~
|~
status - /tmp/x-cu-vg/f 8/9 88%
cursor 1 0 bells 0
```

### in insert mode, the text typed so far kept

```cu
(vi-pty-case 12 50 10 40 "one\n" (list (vi-b "ihello") (list (lit resize) 12 50) (vi-b "_world" (lit esc)) (vi-b ":q!" (lit cr))) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 0
one
--
|hello_worldone
|~
|~
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vg/f [Modified] 1/1 100%
cursor 0 10 bells 0
```

### wider only, a long line drawn wider

```cu
(vi-pty-case 10 60 10 40 "a long line that is wider than forty columns across\n" (list (vi-b "$") (list (lit resize) 10 60) (vi-b "x") (vi-b ":q!" (lit cr))) (list "/tmp/x-cu-vg/f") (list) () ())
```
---
```output
exit 0
a long line that is wider than forty columns across
--
| that is wider than forty columns acros
|
|
|
|
|
|
|
|
status - /tmp/x-cu-vg/f [Modified] 1/1 100%
cursor 0 38 bells 0
```

### $LINES and $COLUMNS set, so the new size is not taken

```cu
(vi-pty-case 12 50 10 40 "one\ntwo\n" (list (vi-b "j") (list (lit resize) 12 50) (vi-b "x") (vi-b ":q!" (lit cr))) (list "/tmp/x-cu-vg/f") (list (pair "LINES" "8") (pair "COLUMNS" "40")) () ())
```
---
```output
exit 0
one
two
--
|one
|wo
|~
|~
|~
|~
|~
|
|
|
|
status 
cursor 0 0 bells 0
```

