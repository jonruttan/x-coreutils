# @weight 1

vi's command line and its start, as busybox's vi (editors/vi.c) reads them:
-R reads every file read-only, each -c is a colon command run as the first
file comes in, -H lists the features and -h gives the usage; $EXINIT's
commands, or when it is not set ~/.exrc's, run before any file.  A file
read-only stays so for every file after it, as busybox never clears that.
Each case types keys at the editor through `%vi-typed`, given the words
after `vi` and an environment of its own -- a case never reads the real
one -- in bursts with a pause between two, into a window 10 rows by 60 or 80
columns, and shows the exit status, the file, and the screen: the rows, the
bottom line, the cursor and the bells.  A case that ends without :wq ends
when its keys do, with status 1.

The screen is every byte vi wrote, drawn on a model of the terminal, the
same model that draws busybox's.  Every expectation is busybox vi's own,
built from its source with every vi feature on but regex search, given the
same words, environment and keys through a pipe with the same pauses.

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
; as (MODE TEXT), or nil for none
(def vi-run-case
  (fn (_ rows cols text bursts argv env exrc mode)
    (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-vo && mkdir -p /tmp/x-cu-vo"))
    (if (null? text) () (file-write-all "/tmp/x-cu-vo/f" text))
    (if (null? mode) () (proc-run (list "/bin/chmod" mode "/tmp/x-cu-vo/f")))
    (if (null? exrc) ()
      (do (file-write-all "/tmp/x-cu-vo/.exrc" (first (rest exrc)))
          (proc-run (list "/bin/chmod" (first exrc) "/tmp/x-cu-vo/.exrc"))))
    (set! %vi-typed-env env)
    (def st (%vi-typed argv bursts rows cols))
    (set! %vi-typed-env ())
    (def f (if (file-exists? "/tmp/x-cu-vo/f") (vi-shown (file-read-all "/tmp/x-cu-vo/f")) "no file\n"))
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

## the version

These two are not busybox's: busybox's :version gives busybox's version,
and vi's gives the one x-coreutils was installed as, from the `version`
file `make install` writes into the bundle.

### the version file make install writes

```cu
(def vi-saved-root (guard (e ()) %lang-root))
(proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-vo && mkdir -p /tmp/x-cu-vo && printf '1.2.3-4-gabcdef\n' > /tmp/x-cu-vo/version"))
(def %lang-root "/tmp/x-cu-vo")
(display (list (%vi-bundle-version) (byte-len (%vi-bundle-version))))
(set! %lang-root vi-saved-root)
```
---
    (1.2.3-4-gabcdef 15)

### a checkout, with no version file, is dev

```cu
(def vi-saved-root (guard (e ()) %lang-root))
(proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-vo && mkdir -p /tmp/x-cu-vo"))
(def %lang-root "/tmp/x-cu-vo")
(display (list (%vi-bundle-version) (byte-len (%vi-bundle-version))))
(set! %lang-root vi-saved-root)
```
---
    (dev 3)

## options

### -R reads the file read-only

```cu
(vi-run-case 10 60 "one\n" (list (vi-b (bytes->str (list 7)))) (list "-R" "/tmp/x-cu-vo/f") (list) () ())
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
status - /tmp/x-cu-vo/f [Readonly] 1/1 100%
cursor 0 0 bells 0
```

### :w is refused under -R

```cu
(vi-run-case 10 60 "one\n" (list (vi-b "x") (vi-b ":w" (lit cr))) (list "-R" "/tmp/x-cu-vo/f") (list) () ())
```
---
```output
exit 1
one
--
|ne
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vo/f' is read only
cursor 0 0 bells 0
```

### :w! writes under -R

```cu
(vi-run-case 10 60 "one\n" (list (vi-b "x") (vi-b ":w!" (lit cr))) (list "-R" "/tmp/x-cu-vo/f") (list) () ())
```
---
```output
exit 1
ne
--
|ne
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vo/f' 1L, 3C
cursor 0 0 bells 0
```

### -c runs a command before the first key

```cu
(vi-run-case 10 60 "one\ntwo\nthree\n" (list (vi-b (bytes->str (list 7)))) (list "-c" ":3" "/tmp/x-cu-vo/f") (list) () ())
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
status - /tmp/x-cu-vo/f 3/3 100%
cursor 2 0 bells 0
```

### two -c run in order

```cu
(vi-run-case 10 80 "one\n" (list) (list "-c" ":set ai" "-c" ":set" "/tmp/x-cu-vo/f") (list) () ())
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
status autoindent noexpandtab noflash noignorecase noshowmatch tabstop=8
cursor 0 0 bells 0
```

### -c with a command there is not

```cu
(vi-run-case 10 60 "one\n" (list (vi-b (bytes->str (list 7)))) (list "-c" ":xyz" "/tmp/x-cu-vo/f") (list) () ())
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
status - /tmp/x-cu-vo/f 1/1 100%
cursor 0 0 bells 0
```

### -c with a command there is not, its message

```cu
(vi-run-case 10 60 "one\n" (list) (list "-c" ":xyz" "/tmp/x-cu-vo/f") (list) () ())
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
status 'xyz' is not implemented
cursor 0 0 bells 0
```

### -c runs for the first file only

```cu
(vi-run-case 10 60 "one\ntwo\n" (list (vi-b ":w /tmp/x-cu-vo/g" (lit cr)) (vi-b ":n" (lit cr)) (vi-b (bytes->str (list 7)))) (list "-c" ":2" "/tmp/x-cu-vo/f" "/tmp/x-cu-vo/g") (list) () ())
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
status - /tmp/x-cu-vo/g 1/2 50%
cursor 0 0 bells 0
```

### -H lists the features

```cu
(vi-run-case 10 60 "one\n" (list) (list "-H") (list) () ())
```
---
```output
exit 1
one
--
|                                            Named buffers wi
|th "x
|     Some colon mode commands with :
|                                    Settable options with ":
|set"
|    Signal catching- ^C
|                       Job suspend and resume with ^Z
|                                                     Adapt t
|o window re-sizes
status 
cursor 0 0 bells 0
```

### -h

```cu
(vi-run-case 10 60 "one\n" (list) (list "-h") (list) () ())
```
---
```output
exit 1
one
--
|
|
|
|
|
|
|
|
|
status 
cursor 0 0 bells 0
```

### :features lists them and waits

```cu
(vi-run-case 10 60 "one\n" (list (vi-b ":features" (lit cr))) (list "/tmp/x-cu-vo/f") (list) () ())
```
---
```output
exit 1
one
--
|                                            Named buffers wi
|th "x
|     Some colon mode commands with :
|                                    Settable options with ":
|set"
|    Signal catching- ^C
|                       Job suspend and resume with ^Z
|                                                     Adapt t
|o window re-sizes
status                  [Hit return to continue]
cursor 0 0 bells 0
```

### :features, then Return

```cu
(vi-run-case 10 60 "one\n" (list (vi-b ":features" (lit cr)) (vi-b (lit cr))) (list "/tmp/x-cu-vo/f") (list) () ())
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
status - /tmp/x-cu-vo/f 1/1 100%
cursor 0 0 bells 0
```

### :fea is :features

```cu
(vi-run-case 10 60 "one\n" (list (vi-b ":fea" (lit cr))) (list "/tmp/x-cu-vo/f") (list) () ())
```
---
```output
exit 1
one
--
|                                            Named buffers wi
|th "x
|     Some colon mode commands with :
|                                    Settable options with ":
|set"
|    Signal catching- ^C
|                       Job suspend and resume with ^Z
|                                                     Adapt t
|o window re-sizes
status                  [Hit return to continue]
cursor 0 0 bells 0
```

### :version says the version x-coreutils was installed as

busybox gives its own version; a checkout of x-coreutils has none, and is dev

```cu
(vi-run-case 10 60 "one\n" (list (vi-b ":version" (lit cr))) (list "/tmp/x-cu-vo/f") (list) () ())
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
status dev
cursor 0 0 bells 0
```

### a read-only file makes the next one read-only too

```cu
(vi-run-case 10 60 "one\n" (list (vi-b ":n" (lit cr)) (vi-b (bytes->str (list 7)))) (list "/tmp/x-cu-vo/f" "/tmp/x-cu-vo/g") (list) () "444")
```
---
```output
exit 1
one
--
|
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vo/g [Readonly] 1/1 100%
cursor 0 0 bells 0
```

## EXINIT and .exrc

### EXINIT's commands run first

```cu
(vi-run-case 10 80 "one\n" (list (vi-b ":set" (lit cr))) (list "/tmp/x-cu-vo/f") (list (pair "EXINIT" "set ai")) () ())
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
status autoindent noexpandtab noflash noignorecase noshowmatch tabstop=8
cursor 0 0 bells 0
```

### two lines in EXINIT

```cu
(vi-run-case 10 80 "one\n" (list (vi-b ":set" (lit cr))) (list "/tmp/x-cu-vo/f") (list (pair "EXINIT" "set ai\nset ic")) () ())
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
status autoindent noexpandtab noflash ignorecase noshowmatch tabstop=8
cursor 0 0 bells 0
```

### EXINIT with a command there is not

```cu
(vi-run-case 10 60 "one\n" (list (vi-b (bytes->str (list 7)))) (list "/tmp/x-cu-vo/f") (list (pair "EXINIT" "xyz")) () ())
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
status - /tmp/x-cu-vo/f 1/1 100%
cursor 0 0 bells 0
```

### EXINIT with a command there is not, its message

```cu
(vi-run-case 10 60 "one\n" (list) (list "/tmp/x-cu-vo/f") (list (pair "EXINIT" "xyz")) () ())
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
status 'xyz' is not implemented
cursor 0 0 bells 0
```

### ~/.exrc when EXINIT is not set

```cu
(vi-run-case 10 80 "one\n" (list (vi-b ":set" (lit cr))) (list "/tmp/x-cu-vo/f") (list (pair "HOME" "/tmp/x-cu-vo")) (list "600" "set ai\n") ())
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
status autoindent noexpandtab noflash noignorecase noshowmatch tabstop=8
cursor 0 0 bells 0
```

### a .exrc others may write is refused

```cu
(vi-run-case 10 80 "one\n" (list (vi-b ":set" (lit cr))) (list "/tmp/x-cu-vo/f") (list (pair "HOME" "/tmp/x-cu-vo")) (list "666" "set ai\n") ())
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
status noautoindent noexpandtab noflash noignorecase noshowmatch tabstop=8
cursor 0 0 bells 0
```

### a .exrc others may write, the message

```cu
(vi-run-case 10 60 "one\n" (list) (list "/tmp/x-cu-vo/f") (list (pair "HOME" "/tmp/x-cu-vo")) (list "666" "set ai\n") ())
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
status .exrc: permission denied
cursor 0 0 bells 0
```

### EXINIT is read and the .exrc not

```cu
(vi-run-case 10 80 "one\n" (list (vi-b ":set" (lit cr))) (list "/tmp/x-cu-vo/f") (list (pair "HOME" "/tmp/x-cu-vo") (pair "EXINIT" "set ai")) (list "600" "set ic\n") ())
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
status autoindent noexpandtab noflash noignorecase noshowmatch tabstop=8
cursor 0 0 bells 0
```

### neither

```cu
(vi-run-case 10 80 "one\n" (list (vi-b ":set" (lit cr))) (list "/tmp/x-cu-vo/f") (list (pair "HOME" "/tmp/x-cu-vo")) () ())
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
status noautoindent noexpandtab noflash noignorecase noshowmatch tabstop=8
cursor 0 0 bells 0
```

