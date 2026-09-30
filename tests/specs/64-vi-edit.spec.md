# @weight 1

vi's operators, registers and marks, as busybox's vi (editors/vi.c) makes
them: d c y < > over a motion, p P, named registers, the marks m and ',
and r R J ~ D C s U.  Each case types keys at the editor through
`%vi-typed`, in bursts with a pause between two, into a window 10 rows by 40
columns, and shows the exit status, the file, the rows as drawn, the bottom
line, the cursor and the bells.  A case that ends without :wq ends when its
keys do, with status 1.

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
(def vi-shown
  (fn (_ s)
    (string-concat
      (List map (fn (_ i) (vi-byte (& (byte-at s i) 255))) (List range 0 (byte-len s))))))
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
(def vi-case
  (fn (_ text bursts target . mode)
    (apply vi-case-in (List append (list 10 40 text bursts target) mode))))
(def vi-case-in
  (fn (_ rows cols text bursts target . mode)
    (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-ve && mkdir -p /tmp/x-cu-ve"))
    (if (null? text) () (file-write-all "/tmp/x-cu-ve/f" text))
    (if (null? mode) () (proc-run (list "/bin/chmod" (first mode) "/tmp/x-cu-ve/f")))
    (def st (%vi-typed (list target) bursts rows cols #f))
    (def f (if (file-exists? "/tmp/x-cu-ve/f") (vi-shown (file-read-all "/tmp/x-cu-ve/f")) "no file\n"))
    (display
      (string-concat
        (list "exit " (%cu-int->str st) "\n"
              (if (if (< 0 (byte-len f)) (= (byte-at f (- (byte-len f) 1)) #\newline) #t) f
                (string-append f " (no newline)\n"))
              "--\n"
              (string-concat (List map (fn (_ r) (string-append "|" (vi-trim r) "\n")) %vi-screen))
              "status " (vi-trim %vi-bottom) "\n"
              "cursor " (%cu-int->str %vi-crow) " " (%cu-int->str %vi-ccol)
              " bells " (%cu-int->str (vi-bells %vi-drawn 0)) "\n")))))
(display "made")
```
---
    made

## d with a motion

### dw deletes to the next word

```cu
(vi-case "one two three\n" (list (vi-b "dw") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
two three
--
|two three
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 10C
cursor 0 0 bells 0
```

### d3w

```cu
(vi-case "a b c d e\n" (list (vi-b "d3w") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
d e
--
|d e
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 4C
cursor 0 0 bells 0
```

### dw on the last word keeps the newline

```cu
(vi-case "one two\nthree\n" (list (vi-b "w") (vi-b "dw") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one 
three
--
|one
|three
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 2L, 11C
cursor 0 3 bells 0
```

### de deletes to the end of the word

```cu
(vi-case "one two\n" (list (vi-b "de") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
 two
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
status '/tmp/x-cu-ve/f' 1L, 5C
cursor 0 0 bells 0
```

### db deletes back to the start of the word

```cu
(vi-case "one two\n" (list (vi-b "$") (vi-b "db") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one o
--
|one o
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 6C
cursor 0 4 bells 0
```

### dW and dE by blank-delimited words

```cu
(vi-case "a.b c.d e.f\n" (list (vi-b "dW") (vi-b "dE") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
 e.f
--
| e.f
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 5C
cursor 0 0 bells 0
```

### d$ to the end of the line

```cu
(vi-case "one two three\n" (list (vi-b "w") (vi-b "d$") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
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
status '/tmp/x-cu-ve/f' 1L, 5C
cursor 0 3 bells 0
```

### d0 to the start of the line

```cu
(vi-case "one two three\n" (list (vi-b "$") (vi-b "d0") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
e
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
status '/tmp/x-cu-ve/f' 1L, 2C
cursor 0 0 bells 0
```

### d^ to the first non-blank

```cu
(vi-case "  one two\n" (list (vi-b "$") (vi-b "d^") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
  o
--
|  o
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 4C
cursor 0 2 bells 0
```

### df, deletes through the comma

```cu
(vi-case "a,b,c\n" (list (vi-b "df,") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
b,c
--
|b,c
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 4C
cursor 0 0 bells 0
```

### dt, stops before it

```cu
(vi-case "a,b,c\n" (list (vi-b "dt,") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
a,b,c
--
|a,b,c
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 6C
cursor 0 0 bells 1
```

### dFa deletes back to it, the cursor left out

```cu
(vi-case "abcabc\n" (list (vi-b "$") (vi-b "dFa") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
abcc
--
|abcc
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 5C
cursor 0 3 bells 0
```

### d% deletes the bracketed text

```cu
(vi-case "(a b) c\n" (list (vi-b "d%") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
 c
--
| c
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 3C
cursor 0 0 bells 0
```

### dG deletes to the end of the text

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b "jdG") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
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
status '/tmp/x-cu-ve/f' 1L, 4C
cursor 0 0 bells 0
```

### dgg deletes to the start

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b "jjdgg") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
four
five
--
|four
|five
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 2L, 10C
cursor 0 0 bells 0
```

### dj deletes this line and the next

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b "jdj") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one
four
five
--
|one
|four
|five
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 3L, 14C
cursor 1 0 bells 0
```

### dk deletes this line and the one before

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b "jjdk") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one
four
five
--
|one
|four
|five
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 3L, 14C
cursor 1 0 bells 0
```

### dL deletes to the bottom of the screen

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b "jdL") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
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
status '/tmp/x-cu-ve/f' 1L, 4C
cursor 0 0 bells 0
```

### d} deletes to the paragraph's end

```cu
(vi-case "a\nb\n\nc\n" (list (vi-b "d}") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0

c
--
|
|c
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 2L, 3C
cursor 0 0 bells 0
```

### dl, d and a space, dh

```cu
(vi-case "abcdef\n" (list (vi-b "dl") (vi-b "d ") (vi-b "$") (vi-b "dh") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
cdf
--
|cdf
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 4C
cursor 0 2 bells 0
```

### d2j

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b "d2j") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
four
five
--
|four
|five
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 2L, 10C
cursor 0 0 bells 0
```

### d with no motion rings

```cu
(vi-case "one\n" (list (vi-b "dq")) "/tmp/x-cu-ve/f")
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
status - /tmp/x-cu-ve/f 1/1 100%
cursor 0 0 bells 1
```

### d then Escape rings nothing

```cu
(vi-case "one\n" (list (vi-b "d") (vi-b (lit esc))) "/tmp/x-cu-ve/f")
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
status - /tmp/x-cu-ve/f 1/1 100%
cursor 0 0 bells 0
```

### dj on the last line rings twice

```cu
(vi-case "one\ntwo\n" (list (vi-b "jdj")) "/tmp/x-cu-ve/f")
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
status - /tmp/x-cu-ve/f 2/2 100%
cursor 1 0 bells 2
```

## yank and put

### yy then p puts the line below

```cu
(vi-case "one\ntwo\n" (list (vi-b "yy") (vi-b "p") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one
one
two
--
|one
|one
|two
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 3L, 12C
cursor 1 0 bells 0
```

### yy then P puts it above

```cu
(vi-case "one\ntwo\n" (list (vi-b "j") (vi-b "yy") (vi-b "P") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one
two
two
--
|one
|two
|two
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 3L, 12C
cursor 1 0 bells 0
```

### yy says what it yanked

```cu
(vi-case "one\ntwo\n" (list (vi-b "2yy")) "/tmp/x-cu-ve/f")
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
status Yank 2 lines (8 chars) from [D]
cursor 0 0 bells 0
```

### yy leaves the cursor where it was

```cu
(vi-case "one two\nthree\n" (list (vi-b "w") (vi-b "yy")) "/tmp/x-cu-ve/f")
```
---
```output
exit 1
one two
three
--
|one two
|three
|~
|~
|~
|~
|~
|~
|~
status Yank 1 lines (8 chars) from [D]
cursor 0 4 bells 0
```

### yw then p puts the word after the cursor

```cu
(vi-case "one two\n" (list (vi-b "yw") (vi-b "$") (vi-b "p") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one twoone 
--
|one twoone
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 12C
cursor 0 10 bells 0
```

### Y yanks the line

```cu
(vi-case "one\ntwo\n" (list (vi-b "Y") (vi-b "j") (vi-b "p") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one
two
one
--
|one
|two
|one
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 3L, 12C
cursor 2 0 bells 0
```

### 3p puts three copies

```cu
(vi-case "ab\n" (list (vi-b "yl") (vi-b "3p") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
aaaab
--
|aaaab
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 6C
cursor 0 3 bells 0
```

### p of lines after the last line

```cu
(vi-case "one\ntwo\n" (list (vi-b "yy") (vi-b "j") (vi-b "p") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one
two
one
--
|one
|two
|one
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 3L, 12C
cursor 2 0 bells 0
```

### p with nothing yanked

```cu
(vi-case "one\n" (list (vi-b "p")) "/tmp/x-cu-ve/f")
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
status Nothing in register D
cursor 0 0 bells 0
```

### dd then p moves a line down

```cu
(vi-case "one\ntwo\nthree\n" (list (vi-b "dd") (vi-b "p") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
two
one
three
--
|two
|one
|three
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 3L, 14C
cursor 1 0 bells 0
```

### x then p swaps two bytes

```cu
(vi-case "ab\n" (list (vi-b "x") (vi-b "p") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
ba
--
|ba
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 3C
cursor 0 1 bells 0
```

## registers

### "ayy keeps a line in register a

```cu
(vi-case "one\ntwo\n" (list (vi-b "\"ayy") (vi-b "j") (vi-b "\"ap") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one
two
one
--
|one
|two
|one
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 3L, 12C
cursor 2 0 bells 0
```

### a register survives a dd into the default

```cu
(vi-case "one\ntwo\nthree\n" (list (vi-b "\"ayy") (vi-b "jdd") (vi-b "\"aP") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one
one
three
--
|one
|one
|three
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 3L, 14C
cursor 1 0 bells 0
```

### "A names the same register as "a

```cu
(vi-case "one\ntwo\n" (list (vi-b "\"Ayy") (vi-b "j") (vi-b "\"ap") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one
two
one
--
|one
|two
|one
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 3L, 12C
cursor 2 0 bells 0
```

### "1 is no register

```cu
(vi-case "one\n" (list (vi-b "\"1")) "/tmp/x-cu-ve/f")
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
status - /tmp/x-cu-ve/f 1/1 100%
cursor 0 0 bells 1
```

### the status names the register

```cu
(vi-case "one\n" (list (vi-b "\"byy")) "/tmp/x-cu-ve/f")
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
status Yank 1 lines (4 chars) from [b]
cursor 0 0 bells 0
```

### a register never written is empty

```cu
(vi-case "one\n" (list (vi-b "\"zp")) "/tmp/x-cu-ve/f")
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
status Nothing in register z
cursor 0 0 bells 0
```

## change

### cw changes a word

```cu
(vi-case "one two\n" (list (vi-b "cwxyz") (vi-b (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
xyz two
--
|xyz two
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 8C
cursor 0 2 bells 0
```

### cw on a word before spaces keeps them

```cu
(vi-case "one   two\n" (list (vi-b "cwX") (vi-b (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
X   two
--
|X   two
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 8C
cursor 0 0 bells 0
```

### cc changes a line

```cu
(vi-case "one\ntwo\nthree\n" (list (vi-b "jccnew") (vi-b (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one
new
three
--
|one
|new
|three
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 3L, 14C
cursor 1 2 bells 0
```

### cc on the last line

```cu
(vi-case "one\ntwo\n" (list (vi-b "jccnew") (vi-b (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one
new
--
|one
|new
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 2L, 8C
cursor 1 2 bells 0
```

### C changes to the end of the line

```cu
(vi-case "one two three\n" (list (vi-b "wCend") (vi-b (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one end
--
|one end
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 8C
cursor 0 6 bells 0
```

### s changes a byte

```cu
(vi-case "abc\n" (list (vi-b "sX") (vi-b (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
Xbc
--
|Xbc
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 4C
cursor 0 0 bells 0
```

### 3s changes three

```cu
(vi-case "abcdef\n" (list (vi-b "3sX") (vi-b (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
Xdef
--
|Xdef
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 5C
cursor 0 0 bells 0
```

### D deletes to the end of the line

```cu
(vi-case "one two\nthree\n" (list (vi-b "w") (vi-b "D") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one 
three
--
|one
|three
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 2L, 11C
cursor 0 3 bells 0
```

## replace, join, case

### r replaces a byte

```cu
(vi-case "abc\n" (list (vi-b "rX") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
Xbc
--
|Xbc
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 4C
cursor 0 0 bells 0
```

### 3r replaces three

```cu
(vi-case "abcdef\n" (list (vi-b "3rX") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
XXXdef
--
|XXXdef
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 7C
cursor 0 2 bells 0
```

### 3r with two bytes left rings

```cu
(vi-case "abc\n" (list (vi-b "l") (vi-b "3rX") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
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
status '/tmp/x-cu-ve/f' 1L, 4C
cursor 0 1 bells 1
```

### r and Return splits the line

```cu
(vi-case "abcd\n" (list (vi-b "l") (vi-b "r" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
a
cd
--
|a
|cd
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 2L, 5C
cursor 1 0 bells 0
```

### r and Escape does nothing

```cu
(vi-case "abc\n" (list (vi-b "r" (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
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
status '/tmp/x-cu-ve/f' 1L, 4C
cursor 0 0 bells 0
```

### R overtypes

```cu
(vi-case "abcdef\n" (list (vi-b "RXY") (vi-b (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
XYcdef
--
|XYcdef
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 7C
cursor 0 1 bells 0
```

### R past the line's end adds

```cu
(vi-case "ab\n" (list (vi-b "RWXYZ") (vi-b (lit esc)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
WXYZ
--
|WXYZ
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 5C
cursor 0 3 bells 0
```

### J joins with a space

```cu
(vi-case "one\n   two\nthree\n" (list (vi-b "J") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one two
three
--
|one two
|three
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 2L, 14C
cursor 0 4 bells 0
```

### 3J joins three times

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b "3J") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one two three four
five
--
|one two three four
|five
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 2L, 24C
cursor 0 14 bells 0
```

### J on the last line does nothing

```cu
(vi-case "one\ntwo\n" (list (vi-b "jJ") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
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
status '/tmp/x-cu-ve/f' 2L, 8C
cursor 1 2 bells 0
```

### ~ flips case and moves on

```cu
(vi-case "aBc1d\n" (list (vi-b "~~~~") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
AbC1d
--
|AbC1d
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 6C
cursor 0 4 bells 0
```

### 5~

```cu
(vi-case "hello world\n" (list (vi-b "5~") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
HELLO world
--
|HELLO world
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 12C
cursor 0 5 bells 0
```

## shifting

### >> puts a tab before the line

```cu
(vi-case "one\ntwo\n" (list (vi-b ">>") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
\011one
two
--
|        one
|two
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 2L, 9C
cursor 0 8 bells 0
```

### 3>> shifts three lines, an empty one left alone

```cu
(vi-case "one\n\nthree\nfour\n" (list (vi-b "3>>") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
\011one

\011three
four
--
|        one
|
|        three
|four
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 4L, 18C
cursor 0 8 bells 0
```

### >j shifts two lines

```cu
(vi-case "one\ntwo\nthree\n" (list (vi-b ">j") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
\011one
\011two
three
--
|        one
|        two
|three
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 3L, 16C
cursor 0 8 bells 0
```

### << takes a tab

```cu
(vi-case "\t\tone\n" (list (vi-b "<<") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
\011one
--
|        one
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 5C
cursor 0 8 bells 0
```

### << takes up to eight spaces

```cu
(vi-case "          one\n" (list (vi-b "<<") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
  one
--
|  one
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 1L, 6C
cursor 0 2 bells 0
```

### << takes the spaces there are

```cu
(vi-case "   one\n" (list (vi-b "<<") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
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
status '/tmp/x-cu-ve/f' 1L, 4C
cursor 0 0 bells 0
```

## marks and U

### ma, then 'a goes back to its line

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b "jjma") (vi-b "gg") (vi-b "'a") (vi-b "x") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
one
two
hree
four
five
--
|one
|two
|hree
|four
|five
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 5L, 23C
cursor 2 0 bells 0
```

### '' goes back where a jump started

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b "jj") (vi-b "G") (vi-b "''") (vi-b "x") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
ne
two
three
four
five
--
|ne
|two
|three
|four
|five
|~
|~
|~
|~
status '/tmp/x-cu-ve/f' 5L, 23C
cursor 0 0 bells 0
```

### '' after :3 and G goes back to line 3

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":3" (lit cr)) (vi-b "G") (vi-b "''")) "/tmp/x-cu-ve/f")
```
---
```output
exit 1
one
two
three
four
five
--
|one
|two
|three
|four
|five
|~
|~
|~
|~
status - /tmp/x-cu-ve/f 3/5 60%
cursor 2 0 bells 0
```

### 'z with no mark z rings

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b "'z")) "/tmp/x-cu-ve/f")
```
---
```output
exit 1
one
two
three
four
five
--
|one
|two
|three
|four
|five
|~
|~
|~
|~
status - /tmp/x-cu-ve/f 1/5 20%
cursor 0 0 bells 1
```

### m1 is no mark

```cu
(vi-case "one\n" (list (vi-b "m1")) "/tmp/x-cu-ve/f")
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
status - /tmp/x-cu-ve/f 1/1 100%
cursor 0 0 bells 1
```

### U puts the line back as it was

```cu
(vi-case "one two\n" (list (vi-b "xxx") (vi-b "U") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
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
status '/tmp/x-cu-ve/f' 1L, 8C
cursor 0 0 bells 0
```

### U says what it put back

```cu
(vi-case "one two\n" (list (vi-b "xx") (vi-b "U")) "/tmp/x-cu-ve/f")
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
status Undo 1 lines (8 chars) from [D]
cursor 0 0 bells 0
```

### U after leaving the line puts back the line as it was when it came back

```cu
(vi-case "one\ntwo\n" (list (vi-b "x") (vi-b "j") (vi-b "k") (vi-b "x") (vi-b "U") (vi-b ":wq" (lit cr))) "/tmp/x-cu-ve/f")
```
---
```output
exit 0
ne
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
status '/tmp/x-cu-ve/f' 2L, 7C
cursor 0 0 bells 0
```

