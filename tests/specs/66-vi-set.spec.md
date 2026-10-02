# @weight 1

vi's options, as busybox's vi (editors/vi.c, with FEATURE_VI_SETOPTS)
makes them: :set, and what autoindent, expandtab, flash, ignorecase,
showmatch and tabstop do.  Each case types keys at the editor through
`%vi-typed`, in bursts with a pause between two, into a window 10 rows by
40 columns unless it says otherwise, and shows the exit status, the file,
the rows as drawn, the bottom line, the cursor, the bells, and the flashes
when there are some.  A case that ends without :wq ends when its keys do,
with status 1.  :set's list of every option is wider than 40 columns, so
those cases run 80 wide.

Every expectation is busybox vi's own, built from its source with every vi
feature on but regex search, typed the same keys through a pipe with the
same pauses, its output read by a model of the terminal.

## the fixtures

### a typist for vi

`vi-b` makes a burst from strings and named keys; `vi-case` writes the file,
types the bursts, and shows what came of them.

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
(def vi-trim
  (fn (self s)
    (if (if (< 0 (byte-len s)) (= (byte-at s (- (byte-len s) 1)) #\space) #f)
      (self (substring s 0 (- (byte-len s) 1)))
      s)))
(def vi-bells-in
  (fn (self s i n)
    (if (< i (byte-len s)) (self s (+ i 1) (if (= (byte-at s i) #\alarm) (+ n 1) n)) n)))
(def vi-bells
  (fn (self ds n)
    (if (null? ds) n (self (rest ds) (vi-bells-in (first ds) 0 n)))))
; the screen reversed for a flash, ESC [ ? 5 h, counted where an ESC is
(def vi-flash (string-append (bytes->str (list 27)) "[?5h"))
(def vi-flashes-in
  (fn (self s i n)
    (if (< (+ i 4) (byte-len s))
      (self s (+ i 1)
        (if (if (= (byte-at s i) #\escape) (string=? (substring s i (+ i 5)) vi-flash) #f) (+ n 1) n))
      n)))
(def vi-flashes
  (fn (self ds n)
    (if (null? ds) n (self (rest ds) (vi-flashes-in (first ds) 0 n)))))
(def vi-flashes-shown
  (fn (_ n) (if (= n 0) "" (string-append " flashes " (%cu-int->str n)))))
(def vi-case
  (fn (_ text bursts target . mode)
    (apply vi-case-in (List append (list 10 40 text bursts target) mode))))
; a text with a NUL in it, from its pieces -- strings, and bytes as numbers --
; as (BUFFER . LENGTH), since a string's length ends at its first NUL
(def vi-raw
  (fn (_ . parts)
    (def n (vi-raw-len parts))
    (def s (%str-make-raw n))
    (vi-raw-fill (%vi-str->ptr s) 0 parts)
    (pair s n)))
(def vi-raw-len
  (fn (self ps)
    (if (null? ps) 0
      (+ (if (str? (first ps)) (byte-len (first ps)) 1) (self (rest ps))))))
(def vi-raw-fill
  (fn (self ptr i ps)
    (match
      ((null? ps) ())
      ((str? (first ps)) (self ptr (vi-raw-copy ptr i (first ps) 0) (rest ps)))
      (#t (do (%vi-ptr-set! ptr i (first ps) 1) (self ptr (+ i 1) (rest ps)))))))
(def vi-raw-copy
  (fn (self ptr i s j)
    (if (< j (byte-len s))
      (do (%vi-ptr-set! ptr i (byte-at s j) 1) (self ptr (+ i 1) s (+ j 1)))
      i)))
; the file written and read back by count, so a NUL in it stays
(def vi-write-file
  (fn (_ path text)
    (def fd (File open path (list (lit wronly) (lit creat) (lit trunc)) 420))
    (if (str? text) (File write fd text (byte-len text)) (File write fd (first text) (rest text)))
    (File close fd)))
(def vi-file-shown
  (fn (_ path)
    (def fd (File open path (lit rdonly)))
    (def buf (%str-make-raw 65536))
    (def n (File read fd buf 65536))
    (File close fd)
    (string-concat (List map (fn (_ i) (vi-byte (& (byte-at buf i) 255))) (List range 0 n)))))
(def vi-case-in
  (fn (_ rows cols text bursts target . mode)
    (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-vs && mkdir -p /tmp/x-cu-vs"))
    (if (null? text) () (vi-write-file "/tmp/x-cu-vs/f" text))
    (if (null? mode) () (proc-run (list "/bin/chmod" (first mode) "/tmp/x-cu-vs/f")))
    (def st (%vi-typed (list target) bursts rows cols))
    (def f (if (file-exists? "/tmp/x-cu-vs/f") (vi-file-shown "/tmp/x-cu-vs/f") "no file\n"))
    (display
      (string-concat
        (list "exit " (%cu-int->str st) "\n"
              (if (if (< 0 (byte-len f)) (= (byte-at f (- (byte-len f) 1)) #\newline) #t) f
                (string-append f " (no newline)\n"))
              "--\n"
              (string-concat (List map (fn (_ r) (string-append "|" (vi-trim r) "\n")) %vi-screen))
              "status " (vi-trim %vi-bottom) "\n"
              "cursor " (%cu-int->str %vi-crow) " " (%cu-int->str %vi-ccol)
              " bells " (%cu-int->str (vi-bells %vi-drawn 0))
              (vi-flashes-shown (vi-flashes %vi-drawn 0)) "\n")))))
(display "made")
```
---
    made

## :set

### :set alone shows every option

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
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

### :set all shows every option

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set all" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
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

### :set sets several at once

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set ai ic ts=4" (lit cr)) (vi-b ":set" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status autoindent noexpandtab noflash ignorecase noshowmatch tabstop=4
cursor 0 0 bells 0
```

### no before an option clears it

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set ai sm" (lit cr)) (vi-b ":set noai" (lit cr)) (vi-b ":set" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status noautoindent noexpandtab noflash noignorecase showmatch tabstop=8
cursor 0 0 bells 0
```

### no before an option that is off

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set noai noic" (lit cr)) (vi-b ":set" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
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

### the long names

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set autoindent expandtab flash ignorecase showmatch tabstop=2" (lit cr)) (vi-b ":set" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status autoindent expandtab flash ignorecase showmatch tabstop=2
cursor 0 0 bells 0
```

### :se is :set

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":se et" (lit cr)) (vi-b ":se" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status noautoindent expandtab noflash noignorecase noshowmatch tabstop=8
cursor 0 0 bells 0
```

### an option there is not

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set xyz" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status bad option: xyz
cursor 0 0 bells 0
```

### a bad option among good ones

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set ai xyz ic" (lit cr)) (vi-b ":set" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
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

### no alone

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set no" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status bad option: no
cursor 0 0 bells 0
```

### a switch given a value

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set ai=1" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status bad option: ai=1
cursor 0 0 bells 0
```

### tabstop without a value

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set ts" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status bad option: ts
cursor 0 0 bells 0
```

### notabstop

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set nots=4" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status bad option: nots=4
cursor 0 0 bells 0
```

### tabstop=0

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set ts=0" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status bad option: ts=0
cursor 0 0 bells 0
```

### tabstop=33

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set ts=33" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status bad option: ts=33
cursor 0 0 bells 0
```

### tabstop=32

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set ts=32" (lit cr)) (vi-b ":set" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status noautoindent noexpandtab noflash noignorecase noshowmatch tabstop=32
cursor 0 0 bells 0
```

### tabstop with a letter after

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set ts=4x" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status bad option: ts=4x
cursor 0 0 bells 0
```

### tabstop with a dot after

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set ts=4." (lit cr)) (vi-b ":set" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status noautoindent noexpandtab noflash noignorecase noshowmatch tabstop=4
cursor 0 0 bells 0
```

### tabstop with leading zeros

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set ts=0004" (lit cr)) (vi-b ":set" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status noautoindent noexpandtab noflash noignorecase noshowmatch tabstop=4
cursor 0 0 bells 0
```

### tabstop given a word

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set ts=abc" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status bad option: ts=abc
cursor 0 0 bells 0
```

### tabstop given nothing

```cu
(vi-case-in 10 80 "x\n" (list (vi-b ":set ts=" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status bad option: ts=
cursor 0 0 bells 0
```

## tabstop

### a tab shown to the tab stop

```cu
(vi-case "\tx\n\t\ty\n" (list (vi-b ":set ts=4" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
\011x
\011\011y
--
|    x
|        y
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vs/f 1/2 50%
cursor 0 3 bells 0
```

### the cursor on a tab's last column

```cu
(vi-case "a\tb\n" (list (vi-b ":set ts=4" (lit cr)) (vi-b "l")) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
a\011b
--
|a   b
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vs/f 1/1 100%
cursor 0 3 bells 0
```

### ^D back to the tab stop

```cu
(vi-case "x\n" (list (vi-b ":set ts=4" (lit cr)) (vi-b "A" (lit cr) "        y" (bytes->str (list 4)) (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
x
    y
--
|x
|    y
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 8C
cursor 1 4 bells 0
```

### < takes a tab stop of spaces

```cu
(vi-case "      x\n" (list (vi-b ":set ts=4" (lit cr)) (vi-b "<<") (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
  x
--
|  x
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 1L, 4C
cursor 0 2 bells 0
```

## expandtab

### Tab puts in spaces to the tab stop

```cu
(vi-case "x\n" (list (vi-b ":set et" (lit cr)) (vi-b "i\tx" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
        xx
--
|        xx
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 1L, 11C
cursor 0 8 bells 0
```

### a Tab after text

```cu
(vi-case "x\n" (list (vi-b ":set et ts=4" (lit cr)) (vi-b "ia\tb" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
a   bx
--
|a   bx
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 1L, 7C
cursor 0 4 bells 0
```

### > puts in spaces

```cu
(vi-case "x\n" (list (vi-b ":set et" (lit cr)) (vi-b ">>") (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
        x
--
|        x
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 1L, 10C
cursor 0 8 bells 0
```

### r and a Tab

```cu
(vi-case "abc\n" (list (vi-b ":set et" (lit cr)) (vi-b "lr\t") (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
a       c
--
|a       c
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 1L, 10C
cursor 0 7 bells 0
```

## autoindent

### Return takes the line's indent

```cu
(vi-case "    foo\n" (list (vi-b ":set ai" (lit cr)) (vi-b "A" (lit cr) "bar" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
    foo
    bar
--
|    foo
|    bar
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 16C
cursor 1 6 bells 0
```

### an indent of tabs stays tabs

```cu
(vi-case "\t\tfoo\n" (list (vi-b ":set ai" (lit cr)) (vi-b "A" (lit cr) "bar" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
\011\011foo
\011\011bar
--
|                foo
|                bar
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 12C
cursor 1 18 bells 0
```

### tabs and then spaces

```cu
(vi-case "\t   foo\n" (list (vi-b ":set ai" (lit cr)) (vi-b "A" (lit cr) "bar" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
\011   foo
\011   bar
--
|           foo
|           bar
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 16C
cursor 1 13 bells 0
```

### with expandtab the indent is spaces

```cu
(vi-case "\tfoo\n" (list (vi-b ":set ai et" (lit cr)) (vi-b "A" (lit cr) "bar" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
\011foo
        bar
--
|        foo
|        bar
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 17C
cursor 1 10 bells 0
```

### the indent in tabs of the tab stop

```cu
(vi-case "        foo\n" (list (vi-b ":set ai ts=4" (lit cr)) (vi-b "A" (lit cr) "bar" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
        foo
\011\011bar
--
|        foo
|        bar
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 18C
cursor 1 10 bells 0
```

### Esc on a line of only autoindent empties it

```cu
(vi-case "    foo\n" (list (vi-b ":set ai" (lit cr)) (vi-b "A" (lit cr) (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
    foo

--
|    foo
|
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 9C
cursor 1 0 bells 0
```

### two Returns move the indent down

```cu
(vi-case "    foo\n" (list (vi-b ":set ai" (lit cr)) (vi-b "A" (lit cr) (lit cr) "bar" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
    foo

    bar
--
|    foo
|
|    bar
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 3L, 17C
cursor 2 6 bells 0
```

### Return inside a line

```cu
(vi-case "    foo bar\n" (list (vi-b ":set ai" (lit cr)) (vi-b "fbi" (lit cr) (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
    foo 
    bar
--
|    foo
|    bar
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 17C
cursor 1 3 bells 0
```

### a line with no indent gives none

```cu
(vi-case "foo\n" (list (vi-b ":set ai" (lit cr)) (vi-b "A" (lit cr) "bar" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
foo
bar
--
|foo
|bar
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 8C
cursor 1 2 bells 0
```

### o opens with the indent

```cu
(vi-case "    foo\n" (list (vi-b ":set ai" (lit cr)) (vi-b "obar" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
    foo
    bar
--
|    foo
|    bar
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 16C
cursor 1 6 bells 0
```

### O opens above with the indent

```cu
(vi-case "x\n    foo\n" (list (vi-b ":set ai" (lit cr)) (vi-b "j") (vi-b "Obar" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
x
    bar
    foo
--
|x
|    bar
|    foo
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 3L, 18C
cursor 1 6 bells 0
```

### O leaves the cursor on the new line

```cu
(vi-case "x\n    foo\n" (list (vi-b ":set ai" (lit cr)) (vi-b "j") (vi-b "O" (lit esc))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
    foo
--
|x
|
|    foo
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vs/f [Modified] 2/3 66%
cursor 1 0 bells 0
```

### O and a Return after its text

```cu
(vi-case "x\n    foo\n" (list (vi-b ":set ai" (lit cr)) (vi-b "j") (vi-b "Oa" (lit cr) "b" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
x
    a
    b
    foo
--
|x
|    a
|    b
|    foo
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 4L, 22C
cursor 2 4 bells 0
```

### O above the first line

```cu
(vi-case "  foo\n" (list (vi-b ":set ai" (lit cr)) (vi-b "Obar" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
  bar
  foo
--
|  bar
|  foo
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 12C
cursor 0 4 bells 0
```

### cc keeps the line's indent

```cu
(vi-case "    foo\nx\n" (list (vi-b ":set ai" (lit cr)) (vi-b "ccbar" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
    bar
x
--
|    bar
|x
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 10C
cursor 0 6 bells 0
```

### cc on the last line

```cu
(vi-case "x\n    foo\n" (list (vi-b ":set ai" (lit cr)) (vi-b "j") (vi-b "ccbar" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
x
    bar
--
|x
|    bar
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 10C
cursor 1 6 bells 0
```

### ^D after an autoindent

```cu
(vi-case "\t\tfoo\n" (list (vi-b ":set ai" (lit cr)) (vi-b "A" (lit cr) (bytes->str (list 4)) "bar" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
\011\011foo
\011bar
--
|                foo
|        bar
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 11C
cursor 1 10 bells 0
```

### ^D and then Esc

```cu
(vi-case "\t\tfoo\n" (list (vi-b ":set ai" (lit cr)) (vi-b "A" (lit cr) (bytes->str (list 4)) (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
\011\011foo

--
|                foo
|
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 7C
cursor 1 0 bells 0
```

### r and Return

```cu
(vi-case "    foo\n" (list (vi-b ":set ai" (lit cr)) (vi-b "$r" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
    fo
    
--
|    fo
|
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 12C
cursor 1 3 bells 0
```

### r and Return, then i and Esc on its indent

```cu
(vi-case "    foo\n" (list (vi-b ":set ai" (lit cr)) (vi-b "$r" (lit cr)) (vi-b "i" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
    fo
    
--
|    fo
|
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 12C
cursor 1 2 bells 0
```

### noai takes it off again

```cu
(vi-case "    foo\n" (list (vi-b ":set ai" (lit cr)) (vi-b ":set noai" (lit cr)) (vi-b "A" (lit cr) "bar" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
    foo
bar
--
|    foo
|bar
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 2L, 12C
cursor 1 2 bells 0
```

## flash

### flash for the bell

```cu
(vi-case "x\n" (list (vi-b ":set fl" (lit cr)) (vi-b "ZX")) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vs/f 1/1 100%
cursor 0 0 bells 0 flashes 1
```

### noflash rings the bell again

```cu
(vi-case "x\n" (list (vi-b ":set fl" (lit cr)) (vi-b ":set nofl" (lit cr)) (vi-b "ZX")) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vs/f 1/1 100%
cursor 0 0 bells 1
```

## ignorecase

### / finds the text in any case

```cu
(vi-case "one\nx FOO\n" (list (vi-b ":set ic" (lit cr)) (vi-b "/foo" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
one
x FOO
--
|one
|x FOO
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vs/f 2/2 100%
cursor 1 2 bells 0
```

### without ic it does not

```cu
(vi-case "one\nx FOO\n" (list (vi-b "/foo" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
one
x FOO
--
|one
|x FOO
|~
|~
|~
|~
|~
|~
|~
status Pattern not found
cursor 0 0 bells 0
```

### ? in any case

```cu
(vi-case "x Foo\ny\n" (list (vi-b ":set ic" (lit cr)) (vi-b "j") (vi-b "?fOO" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x Foo
y
--
|x Foo
|y
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vs/f 1/2 50%
cursor 0 2 bells 0
```

### :s in any case

```cu
(vi-case "Foo foo FOO\n" (list (vi-b ":set ic" (lit cr)) (vi-b ":s/foo/x/g" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 0
x x x
--
|x x x
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vs/f' 1L, 6C
cursor 0 0 bells 0
```

### :/text/ in any case

```cu
(vi-case "a\nb\nFOO\n" (list (vi-b ":set ic" (lit cr)) (vi-b ":/foo/" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
a
b
FOO
--
|a
|b
|FOO
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vs/f 3/3 100%
cursor 2 0 bells 0
```

### past a NUL byte

```cu
(vi-case (vi-raw "a" 0 "b FOO\n") (list (vi-b ":set ic" (lit cr)) (vi-b "/foo" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
a\000b FOO
--
|a^@b FOO
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vs/f 1/1 100%
cursor 0 5 bells 0
```

### :s in any case stays on its line

```cu
(vi-case "x\nFOO\n" (list (vi-b ":set ic" (lit cr)) (vi-b ":s/foo/y/" (lit cr))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
FOO
--
|x
|FOO
|~
|~
|~
|~
|~
|~
|~
status No match
cursor 0 0 bells 0
```

## showmatch

### a closing bracket with its opener

```cu
(vi-case "(x\n" (list (vi-b ":set sm" (lit cr)) (vi-b "A)" (lit esc))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
(x
--
|(x)
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vs/f [Modified] 1/1 100%
cursor 0 2 bells 0
```

### a closing bracket with none

```cu
(vi-case "x\n" (list (vi-b ":set sm" (lit cr)) (vi-b "A)" (lit esc))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x)
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vs/f [Modified] 1/1 100%
cursor 0 1 bells 1
```

### without sm no bell

```cu
(vi-case "x\n" (list (vi-b "A)" (lit esc))) "/tmp/x-cu-vs/f")
```
---
```output
exit 1
x
--
|x)
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vs/f [Modified] 1/1 100%
cursor 0 1 bells 0
```

