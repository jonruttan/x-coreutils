# @weight 1

vi's u and . as busybox's vi (editors/vi.c, with FEATURE_VI_UNDO, its
queue, and FEATURE_VI_DOT_CMD) makes them.  u takes back the last change,
and the ones chained to it: a run of typing or backspacing, a count's
worth of x, every substitution of one :s.  Its message counts the changes
still to undo.  . replays the keys of the last command that changed the
text, with its count, or with the one typed before the dot.  Each case types
keys at the editor through `%vi-typed`, in bursts with a pause between two,
into a window 10 rows by 60 columns, and shows the exit status, the file,
and the screen: the rows, the bottom line, the cursor and the bells.  A case
that ends without :wq ends when its keys do, with status 1.

The screen is every byte vi wrote, drawn on a model of the terminal, the
same model that draws busybox's.  Every expectation is busybox vi's own,
built from its source with every vi feature on but regex search, typed the
same keys through a pipe with the same pauses.

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
    (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-vu && mkdir -p /tmp/x-cu-vu"))
    (if (null? text) () (file-write-all "/tmp/x-cu-vu/f" text))
    (if (null? mode) () (proc-run (list "/bin/chmod" (first mode) "/tmp/x-cu-vu/f")))
    (def st (%vi-typed (list target) bursts rows cols))
    (def f (if (file-exists? "/tmp/x-cu-vu/f") (vi-shown (file-read-all "/tmp/x-cu-vu/f")) "no file\n"))
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

## u

### u takes back an insert

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "ifoo" (lit esc)) (vi-b "u")) "/tmp/x-cu-vu/f")
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
status Undo [1] deleted 3 chars at position 0
cursor 0 0 bells 0
```

### u takes back only the last insert

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "ifoo" (lit esc)) (vi-b "ibar" (lit esc)) (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one
--
|fooone
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [2] deleted 3 chars at position 2
cursor 0 2 bells 0
```

### u with nothing to undo

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "u")) "/tmp/x-cu-vu/f")
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
status Already at oldest change
cursor 0 0 bells 0
```

### u twice

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "x") (vi-b "x") (vi-b "u") (vi-b "u")) "/tmp/x-cu-vu/f")
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
status Undo [1] restored 1 chars at position 0
cursor 0 0 bells 0
```

### u past the oldest change

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "x") (vi-b "u") (vi-b "u")) "/tmp/x-cu-vu/f")
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
status Already at oldest change
cursor 0 0 bells 0
```

### 3x comes back with one u

```cu
(vi-case-in 10 60 "abcdef\n" (list (vi-b "3x") (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
abcdef
--
|abcdef
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [1] restored 1 chars at position 0
cursor 0 0 bells 0
```

### u after X

```cu
(vi-case-in 10 60 "abcdef\n" (list (vi-b "$X") (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
abcdef
--
|abcdef
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [1] restored 1 chars at position 4
cursor 0 4 bells 0
```

### u after dd

```cu
(vi-case-in 10 60 "one\ntwo\nthree\n" (list (vi-b "j") (vi-b "dd") (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one
two
three
--
|one
|two
|three
|~
|~
|~
|~
|~
|~
status Undo [1] restored 4 chars at position 4
cursor 1 0 bells 0
```

### u after 2dd

```cu
(vi-case-in 10 60 "one\ntwo\nthree\n" (list (vi-b "2dd") (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one
two
three
--
|one
|two
|three
|~
|~
|~
|~
|~
|~
status Undo [1] restored 8 chars at position 0
cursor 0 0 bells 0
```

### u after deleting every line

```cu
(vi-case-in 10 60 "one\ntwo\n" (list (vi-b "2dd") (vi-b "u")) "/tmp/x-cu-vu/f")
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
status Undo [1] restored 7 chars at position 0
cursor 0 0 bells 0
```

### u after cw

```cu
(vi-case-in 10 60 "one two\n" (list (vi-b "cwxyz" (lit esc)) (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one two
--
| two
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [2] deleted 3 chars at position 0
cursor 0 0 bells 0
```

### u after cc

```cu
(vi-case-in 10 60 "one\ntwo\n" (list (vi-b "ccnew" (lit esc)) (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one
two
--
|
|two
|~
|~
|~
|~
|~
|~
|~
status Undo [3] deleted 3 chars at position 0
cursor 0 0 bells 0
```

### u after o

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "onew" (lit esc)) (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one
--
|one
|
|~
|~
|~
|~
|~
|~
|~
status Undo [2] deleted 3 chars at position 4
cursor 1 0 bells 0
```

### u after O

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "Onew" (lit esc)) (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one
--
|
|one
|~
|~
|~
|~
|~
|~
|~
status Undo [2] deleted 3 chars at position 0
cursor 0 0 bells 0
```

### u after J

```cu
(vi-case-in 10 60 "one\n  two\n" (list (vi-b "J") (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one
  two
--
|one
|  two
|~
|~
|~
|~
|~
|~
|~
status Undo [1] restored 1 chars at position 3
cursor 0 2 bells 0
```

### u after 3~

```cu
(vi-case-in 10 60 "abcd\n" (list (vi-b "3~") (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
abcd
--
|abcd
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [1] restored 1 chars at position 0
cursor 0 0 bells 0
```

### u after r

```cu
(vi-case-in 10 60 "abc\n" (list (vi-b "rx") (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
abc
--
|abc
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [1] restored 1 chars at position 0
cursor 0 0 bells 0
```

### u after 3r

```cu
(vi-case-in 10 60 "abcdef\n" (list (vi-b "3rx") (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
abcdef
--
|abcdef
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [1] restored 1 chars at position 0
cursor 0 0 bells 0
```

### u after R

```cu
(vi-case-in 10 60 "abcdef\n" (list (vi-b "Rxy" (lit esc)) (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
abcdef
--
|xbcdef
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [3] restored 1 chars at position 1
cursor 0 1 bells 0
```

### Backspace in R puts the old bytes back

```cu
(vi-case-in 10 60 "abcdef\n" (list (vi-b "Rxyz" (lit bs) (lit bs) (lit esc))) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
abcdef
--
|xbcdef
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vu/f [Modified] 1/1 100%
cursor 0 0 bells 0
```

### u after p

```cu
(vi-case-in 10 60 "one\ntwo\n" (list (vi-b "yy") (vi-b "p") (vi-b "u")) "/tmp/x-cu-vu/f")
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
status Undo [1] deleted 4 chars at position 4
cursor 1 0 bells 0
```

### u after 3p

```cu
(vi-case-in 10 60 "ab\n" (list (vi-b "yl") (vi-b "3p") (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
ab
--
|ab
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [1] deleted 1 chars at position 1
cursor 0 1 bells 0
```

### u after 3>>

```cu
(vi-case-in 10 60 "a\nb\nc\n" (list (vi-b "3>>") (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
a
b
c
--
|a
|b
|c
|~
|~
|~
|~
|~
|~
status Undo [1] deleted 1 chars at position 0
cursor 0 0 bells 0
```

### u after <<

```cu
(vi-case-in 10 60 "        a\n" (list (vi-b "<<") (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
        a
--
|        a
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [1] restored 1 chars at position 0
cursor 0 0 bells 0
```

### u after D

```cu
(vi-case-in 10 60 "one two\n" (list (vi-b "wD") (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one two
--
|one two
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [1] restored 3 chars at position 4
cursor 0 4 bells 0
```

### u after C

```cu
(vi-case-in 10 60 "one two\n" (list (vi-b "wCxy" (lit esc)) (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one two
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
status Undo [2] deleted 2 chars at position 4
cursor 0 3 bells 0
```

### u after s

```cu
(vi-case-in 10 60 "abc\n" (list (vi-b "sxy" (lit esc)) (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
abc
--
|bc
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [2] deleted 2 chars at position 0
cursor 0 0 bells 0
```

### u after U

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "x") (vi-b "x") (vi-b "U") (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one
--
|e
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [3] restored 1 chars at position 0
cursor 0 0 bells 0
```

### u after :s

```cu
(vi-case-in 10 60 "a a a\n" (list (vi-b ":s/a/bb/g" (lit cr)) (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
a a a
--
|a a a
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [1] restored 1 chars at position 0
cursor 0 0 bells 0
```

### u after :d

```cu
(vi-case-in 10 60 "one\ntwo\n" (list (vi-b ":1d" (lit cr)) (vi-b "u")) "/tmp/x-cu-vu/f")
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
status Undo [1] restored 4 chars at position 0
cursor 0 0 bells 0
```

### u after :r

```cu
(vi-case-in 10 60 "one\n" (list (vi-b ":r /tmp/x-cu-vu/f" (lit cr)) (vi-b "u")) "/tmp/x-cu-vu/f")
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
status Undo [1] deleted 4 chars at position 4
cursor 1 3 bells 0
```

### typing and backspacing come back together

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "Aabc" (lit bs) (lit bs) "d" (lit esc)) (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one
--
|onea
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [3] deleted 1 chars at position 4
cursor 0 3 bells 0
```

### u after backspacing alone

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "Aabc" (lit esc)) (vi-b "A" (lit bs) (lit bs) (lit esc)) (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one
--
|oneabc
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [2] restored 2 chars at position 4
cursor 0 4 bells 0
```

### an arrow key ends a run of typing

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "Aab") (vi-b (lit left)) (vi-b "cd" (lit esc)) (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one
--
|oneab
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [2] deleted 2 chars at position 4
cursor 0 4 bells 0
```

### a newline ends a run of typing

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "Aab" (lit cr) "cd" (lit esc)) (vi-b "u")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one
--
|oneab
|~
|~
|~
|~
|~
|~
|~
|~
status Undo [2] deleted 3 chars at position 5
cursor 0 4 bells 0
```

### u twice after a newline

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "Aab" (lit cr) "cd" (lit esc)) (vi-b "u") (vi-b "u")) "/tmp/x-cu-vu/f")
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
status Undo [1] deleted 2 chars at position 3
cursor 0 2 bells 0
```

### u back to the text as read

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "x") (vi-b "u") (vi-b (bytes->str (list 7)))) "/tmp/x-cu-vu/f")
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
status - /tmp/x-cu-vu/f 1/1 100%
cursor 0 0 bells 0
```

### u after :w

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "x") (vi-b ":w" (lit cr)) (vi-b "u") (vi-b (bytes->str (list 7)))) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
ne
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
status - /tmp/x-cu-vu/f [Modified] 1/1 100%
cursor 0 0 bells 0
```

## .

### . after x

```cu
(vi-case-in 10 60 "abcdef\n" (list (vi-b "x") (vi-b ".")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
abcdef
--
|cdef
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vu/f [Modified] 1/1 100%
cursor 0 0 bells 0
```

### . after 2x keeps the count

```cu
(vi-case-in 10 60 "abcdefgh\n" (list (vi-b "2x") (vi-b ".")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
abcdefgh
--
|efgh
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vu/f [Modified] 1/1 100%
cursor 0 0 bells 0
```

### 3. after x

```cu
(vi-case-in 10 60 "abcdefgh\n" (list (vi-b "x") (vi-b "3.")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
abcdefgh
--
|efgh
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vu/f [Modified] 1/1 100%
cursor 0 0 bells 0
```

### . after dd

```cu
(vi-case-in 10 60 "one\ntwo\nthree\n" (list (vi-b "dd") (vi-b ".")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one
two
three
--
|three
|~
|~
|~
|~
|~
|~
|~
|~
status Delete 1 lines (4 chars) from [D]
cursor 0 0 bells 0
```

### . after an insert

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "ifoo" (lit esc)) (vi-b ".")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one
--
|fofoooone
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vu/f [Modified] 1/1 100%
cursor 0 4 bells 0
```

### . after A

```cu
(vi-case-in 10 60 "one\ntwo\n" (list (vi-b "A!" (lit esc)) (vi-b "j") (vi-b ".")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one
two
--
|one!
|two!
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vu/f [Modified] 2/2 100%
cursor 1 3 bells 0
```

### . after o

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "onew" (lit esc)) (vi-b ".")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one
--
|one
|new
|new
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vu/f [Modified] 3/3 100%
cursor 2 2 bells 0
```

### . after cw

```cu
(vi-case-in 10 60 "a b c\n" (list (vi-b "cwx" (lit esc)) (vi-b "w") (vi-b ".")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
a b c
--
|x x
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vu/f [Modified] 1/1 100%
cursor 0 2 bells 0
```

### . after p

```cu
(vi-case-in 10 60 "ab\n" (list (vi-b "yl") (vi-b "p") (vi-b ".")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
ab
--
|aaab
|~
|~
|~
|~
|~
|~
|~
|~
status Put 0 lines (1 chars) from [D]
cursor 0 2 bells 0
```

### . after J

```cu
(vi-case-in 10 60 "a\nb\nc\n" (list (vi-b "J") (vi-b ".")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
a
b
c
--
|a b c
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vu/f [Modified] 1/1 100%
cursor 0 4 bells 0
```

### . after ~

```cu
(vi-case-in 10 60 "abc\n" (list (vi-b "~") (vi-b ".")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
abc
--
|ABc
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vu/f [Modified] 1/1 100%
cursor 0 2 bells 0
```

### . after r

```cu
(vi-case-in 10 60 "abc\n" (list (vi-b "rx") (vi-b "l") (vi-b ".")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
abc
--
|xxc
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vu/f [Modified] 1/1 100%
cursor 0 1 bells 0
```

### . after >>

```cu
(vi-case-in 10 60 "a\n" (list (vi-b ">>") (vi-b ".")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
a
--
|                a
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vu/f [Modified] 1/1 100%
cursor 0 16 bells 0
```

### . with nothing to repeat

```cu
(vi-case-in 10 60 "abc\n" (list (vi-b ".")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
abc
--
|abc
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vu/f 1/1 100%
cursor 0 0 bells 0
```

### . after u repeats the change

```cu
(vi-case-in 10 60 "abcdef\n" (list (vi-b "x") (vi-b "u") (vi-b ".")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
abcdef
--
|bcdef
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vu/f [Modified] 1/1 100%
cursor 0 0 bells 0
```

### . after d/text

```cu
(vi-case-in 10 60 "a x b x c\n" (list (vi-b "d/x" (lit cr)) (vi-b ".")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
a x b x c
--
|x c
|~
|~
|~
|~
|~
|~
|~
|~
status Delete 0 lines (4 chars) from [D]
cursor 0 0 bells 0
```

### . after a move

```cu
(vi-case-in 10 60 "abcdef\n" (list (vi-b "x") (vi-b "l") (vi-b ".")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
abcdef
--
|bdef
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vu/f [Modified] 1/1 100%
cursor 0 1 bells 0
```

### . after an insert with an arrow key in it

```cu
(vi-case-in 10 60 "one\n" (list (vi-b "Aab") (vi-b (lit left)) (vi-b "c" (lit esc)) (vi-b "0.")) "/tmp/x-cu-vu/f")
```
---
```output
exit 1
one
--
|oneacbab.c
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vu/f [Modified] 1/1 100%
cursor 0 9 bells 0
```

### . after an insert too long to keep

```cu
(vi-case-in 10 60 "x\n" (list (vi-b "i0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789" (lit esc)) (vi-b ".") (vi-b ":wq" (lit cr))) "/tmp/x-cu-vu/f")
```
---
```output
exit 0
0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789x
--
|012345678901234567890123456789012345678901234567890123456789
|
|
|
|
|
|
|
|
status '/tmp/x-cu-vu/f' 1L, 132C
cursor 0 59 bells 0
```

### a command letter typed after the keys overflow

```cu
(vi-case-in 10 60 "x\n" (list (vi-b "i0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789abc" (lit esc)) (vi-b "0.") (vi-b ":wq" (lit cr))) "/tmp/x-cu-vu/f")
```
---
```output
exit 0
0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789abcx
--
|012345678901234567890123456789012345678901234567890123456789
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vu/f' 1L, 135C
cursor 0 0 bells 0
```

