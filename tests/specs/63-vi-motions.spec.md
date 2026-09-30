# @weight 1

vi's motions, as busybox's vi (editors/vi.c) makes them: words, characters
searched for on the line, lines by number and by place on the screen, the
matching bracket, paragraphs, and scrolling.  Each case types keys at the
editor through `%vi-typed`, in bursts with a pause between two, into a
window 10 rows by 40 columns unless it says otherwise, and shows the exit
status, the file, the rows as drawn, the bottom line, the cursor and the
bells.  A case that ends without :q ends when its keys do, with status 1.

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
    (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-vm && mkdir -p /tmp/x-cu-vm"))
    (if (null? text) () (file-write-all "/tmp/x-cu-vm/f" text))
    (if (null? mode) () (proc-run (list "/bin/chmod" (first mode) "/tmp/x-cu-vm/f")))
    (def st (%vi-typed (list target) bursts rows cols #f))
    (def f (if (file-exists? "/tmp/x-cu-vm/f") (vi-shown (file-read-all "/tmp/x-cu-vm/f")) "no file\n"))
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

## words

### w moves to the start of the next word

```cu
(vi-case "one two three\n" (list (vi-b "w") (vi-b "w")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
one two three
--
|one two three
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 8 bells 0
```

### w stops where a word meets punctuation

```cu
(vi-case "foo.bar(baz) x\n" (list (vi-b "w") (vi-b "w") (vi-b "w") (vi-b "w")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
foo.bar(baz) x
--
|foo.bar(baz) x
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 8 bells 0
```

### 3w

```cu
(vi-case "a b c d e f\n" (list (vi-b "3w")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
a b c d e f
--
|a b c d e f
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 6 bells 0
```

### w crosses to the next line, and stops on an empty one

```cu
(vi-case "one\n\n\ntwo three\n" (list (vi-b "w") (vi-b "w") (vi-b "w")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
one


two three
--
|one
|
|
|two three
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 4/4 100%
cursor 3 4 bells 0
```

### w at the last word stays on the text

```cu
(vi-case "one two\n" (list (vi-b "w") (vi-b "w") (vi-b "w")) "/tmp/x-cu-vm/f")
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
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 6 bells 0
```

### b moves back to the start of a word

```cu
(vi-case "one two three\n" (list (vi-b "$") (vi-b "b") (vi-b "b")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
one two three
--
|one two three
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 4 bells 0
```

### 3b across a line

```cu
(vi-case "one two\nthree four\n" (list (vi-b "j$") (vi-b "3b")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
one two
three four
--
|one two
|three four
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/2 50%
cursor 0 6 bells 0
```

### b at the start of the text stays

```cu
(vi-case "one\n" (list (vi-b "b")) "/tmp/x-cu-vm/f")
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
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 0 bells 0
```

### e moves to the end of a word

```cu
(vi-case "one two three\n" (list (vi-b "e") (vi-b "e") (vi-b "e")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
one two three
--
|one two three
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 12 bells 0
```

### e crosses lines

```cu
(vi-case "one\ntwo\n" (list (vi-b "e") (vi-b "e")) "/tmp/x-cu-vm/f")
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
status - /tmp/x-cu-vm/f 2/2 100%
cursor 1 2 bells 0
```

### e stops at the end of punctuation too

```cu
(vi-case "a..b c\n" (list (vi-b "e") (vi-b "e") (vi-b "e")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
a..b c
--
|a..b c
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 5 bells 0
```

### W moves by blank-delimited words

```cu
(vi-case "a.b c.d e\n" (list (vi-b "W") (vi-b "W")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
a.b c.d e
--
|a.b c.d e
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 8 bells 0
```

### B back by blank-delimited words

```cu
(vi-case "a.b c.d e\n" (list (vi-b "$") (vi-b "B") (vi-b "B")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
a.b c.d e
--
|a.b c.d e
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 0 bells 0
```

### E to the end of blank-delimited words

```cu
(vi-case "a.b c.d e\n" (list (vi-b "E") (vi-b "E")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
a.b c.d e
--
|a.b c.d e
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 6 bells 0
```

## characters on the line

### f, then ; again and , back

```cu
(vi-case "abcabc\n" (list (vi-b "fc") (vi-b ";") (vi-b ",")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
abcabc
--
|abcabc
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 2 bells 0
```

### F searches back, and ; goes on back

```cu
(vi-case "abcabc\n" (list (vi-b "$") (vi-b "Fa") (vi-b ";")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
abcabc
--
|abcabc
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 0 bells 0
```

### t stops before the byte, and ; finds the same one

```cu
(vi-case "a,b,c\n" (list (vi-b "t,") (vi-b ";")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
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
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 0 bells 0
```

### T stops after it

```cu
(vi-case "a,b,c\n" (list (vi-b "$") (vi-b "T,")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
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
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 4 bells 0
```

### 2f. finds the second

```cu
(vi-case "a.b.c.d\n" (list (vi-b "2f.")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
a.b.c.d
--
|a.b.c.d
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 3 bells 0
```

### f with no such byte on the line rings

```cu
(vi-case "abc\nz\n" (list (vi-b "fz")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
abc
z
--
|abc
|z
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/2 50%
cursor 0 0 bells 1
```

### ; before any search does nothing

```cu
(vi-case "abc\n" (list (vi-b ";")) "/tmp/x-cu-vm/f")
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
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 0 bells 0
```

## lines

### G goes to the last line

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b "G")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 26
|line 27
|line 28
|line 29
|line 30
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 30/30 100%
cursor 4 0 bells 0
```

### 5G goes to line 5

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b "G") (vi-b "5G")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 1
|line 2
|line 3
|line 4
|line 5
|line 6
|line 7
|line 8
|line 9
status - /tmp/x-cu-vm/f 5/30 16%
cursor 4 0 bells 0
```

### gg goes to the first line

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b "G") (vi-b "gg")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 1
|line 2
|line 3
|line 4
|line 5
|line 6
|line 7
|line 8
|line 9
status - /tmp/x-cu-vm/f 1/30 3%
cursor 0 0 bells 0
```

### 3gg goes to line 3

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b "G") (vi-b "3gg")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 1
|line 2
|line 3
|line 4
|line 5
|line 6
|line 7
|line 8
|line 9
status - /tmp/x-cu-vm/f 3/30 10%
cursor 2 0 bells 0
```

### g with anything but g is no command

```cu
(vi-case "one\n" (list (vi-b "gq")) "/tmp/x-cu-vm/f")
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
status 'gq' is not implemented
cursor 0 0 bells 0
```

### G lands past the blanks

```cu
(vi-case "one\n   two\n" (list (vi-b "G")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
one
   two
--
|one
|   two
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 2/2 100%
cursor 1 3 bells 0
```

### H goes to the top of the screen

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b ":15" (lit cr)) (vi-b "H")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 11
|line 12
|line 13
|line 14
|line 15
|line 16
|line 17
|line 18
|line 19
status - /tmp/x-cu-vm/f 15/30 50%
cursor 0 0 bells 0
```

### 3H, the third line from the top

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b ":15" (lit cr)) (vi-b "3H")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 11
|line 12
|line 13
|line 14
|line 15
|line 16
|line 17
|line 18
|line 19
status - /tmp/x-cu-vm/f 15/30 50%
cursor 2 0 bells 0
```

### L goes to the bottom of the screen

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b "L")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 1
|line 2
|line 3
|line 4
|line 5
|line 6
|line 7
|line 8
|line 9
status - /tmp/x-cu-vm/f 9/30 30%
cursor 8 0 bells 0
```

### 2L, the second line from the bottom

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b "2L")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 1
|line 2
|line 3
|line 4
|line 5
|line 6
|line 7
|line 8
|line 9
status - /tmp/x-cu-vm/f 8/30 26%
cursor 7 0 bells 0
```

### M goes to the middle of the screen

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b "M")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 1
|line 2
|line 3
|line 4
|line 5
|line 6
|line 7
|line 8
|line 9
status - /tmp/x-cu-vm/f 5/30 16%
cursor 4 0 bells 0
```

### 20H stops at the bottom of the screen

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b "20H")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 1
|line 2
|line 3
|line 4
|line 5
|line 6
|line 7
|line 8
|line 9
status - /tmp/x-cu-vm/f 9/30 30%
cursor 8 0 bells 0
```

### 20L stops at the top

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b "20L")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 1
|line 2
|line 3
|line 4
|line 5
|line 6
|line 7
|line 8
|line 9
status - /tmp/x-cu-vm/f 1/30 3%
cursor 0 0 bells 0
```

### ^ goes to the first non-blank

```cu
(vi-case "   indented\n" (list (vi-b "$") (vi-b "^")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
   indented
--
|   indented
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 3 bells 0
```

### 5| goes to column 5

```cu
(vi-case "abcdefgh\n" (list (vi-b "5|")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
abcdefgh
--
|abcdefgh
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 4 bells 0
```

### | alone goes to the first column

```cu
(vi-case "abcdefgh\n" (list (vi-b "$") (vi-b "|")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
abcdefgh
--
|abcdefgh
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 0 bells 0
```

## brackets and paragraphs

### % from an opening bracket to its match

```cu
(vi-case "(a [b] {c})\n" (list (vi-b "%")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
(a [b] {c})
--
|(a [b] {c})
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 10 bells 0
```

### % on an inner pair

```cu
(vi-case "(a [b] {c})\n" (list (vi-b "f[") (vi-b "%")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
(a [b] {c})
--
|(a [b] {c})
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 5 bells 0
```

### % from a closing bracket back

```cu
(vi-case "(a [b] {c})\n" (list (vi-b "$") (vi-b "%")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
(a [b] {c})
--
|(a [b] {c})
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 0 bells 0
```

### % finds the first bracket after the cursor on the line

```cu
(vi-case "x = f(y)\n" (list (vi-b "%")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
x = f(y)
--
|x = f(y)
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 7 bells 0
```

### % with no bracket on the line rings

```cu
(vi-case "abc\n" (list (vi-b "%")) "/tmp/x-cu-vm/f")
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
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 0 bells 1
```

### % with no match rings

```cu
(vi-case "(abc\n" (list (vi-b "%")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
(abc
--
|(abc
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 0 bells 1
```

### % counts nested pairs of the same kind

```cu
(vi-case "((a) b) c\n" (list (vi-b "%")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
((a) b) c
--
|((a) b) c
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 1/1 100%
cursor 0 6 bells 0
```

### } goes to the next empty line

```cu
(vi-case "a\nb\n\nc\nd\n\n\ne\n" (list (vi-b "}")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
a
b

c
d


e
--
|a
|b
|
|c
|d
|
|
|e
|~
status - /tmp/x-cu-vm/f 3/8 37%
cursor 2 0 bells 0
```

### } twice

```cu
(vi-case "a\nb\n\nc\nd\n\n\ne\n" (list (vi-b "}") (vi-b "}")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
a
b

c
d


e
--
|a
|b
|
|c
|d
|
|
|e
|~
status - /tmp/x-cu-vm/f 6/8 75%
cursor 5 0 bells 0
```

### 2}

```cu
(vi-case "a\nb\n\nc\nd\n\n\ne\n" (list (vi-b "2}")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
a
b

c
d


e
--
|a
|b
|
|c
|d
|
|
|e
|~
status - /tmp/x-cu-vm/f 6/8 75%
cursor 5 0 bells 0
```

### { goes back to an empty line

```cu
(vi-case "a\nb\n\nc\nd\n\n\ne\n" (list (vi-b "G") (vi-b "{")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
a
b

c
d


e
--
|a
|b
|
|c
|d
|
|
|e
|~
status - /tmp/x-cu-vm/f 7/8 87%
cursor 6 0 bells 0
```

### } with no empty line after stays at the end

```cu
(vi-case "a\nb\n" (list (vi-b "}")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
a
b
--
|a
|b
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vm/f 2/2 100%
cursor 1 0 bells 0
```

### } from a run of empty lines passes it first

```cu
(vi-case "a\n\n\n\nb\n\nc\n" (list (vi-b "j") (vi-b "}")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
a



b

c
--
|a
|
|
|
|b
|
|c
|~
|~
status - /tmp/x-cu-vm/f 6/7 85%
cursor 5 0 bells 0
```

## scrolling

### ^F scrolls down a screen

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b (bytes->str (list 6)))) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 9
|line 10
|line 11
|line 12
|line 13
|line 14
|line 15
|line 16
|line 17
status - /tmp/x-cu-vm/f 9/30 30%
cursor 0 0 bells 0
```

### ^B scrolls back up

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b (bytes->str (list 6))) (vi-b (bytes->str (list 6))) (vi-b (bytes->str (list 2)))) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 9
|line 10
|line 11
|line 12
|line 13
|line 14
|line 15
|line 16
|line 17
status - /tmp/x-cu-vm/f 17/30 56%
cursor 8 0 bells 0
```

### ^D scrolls down half a screen

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b (bytes->str (list 4)))) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 5
|line 6
|line 7
|line 8
|line 9
|line 10
|line 11
|line 12
|line 13
status - /tmp/x-cu-vm/f 5/30 16%
cursor 0 0 bells 0
```

### ^U scrolls back half

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b (bytes->str (list 4))) (vi-b (bytes->str (list 4))) (vi-b (bytes->str (list 21)))) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 5
|line 6
|line 7
|line 8
|line 9
|line 10
|line 11
|line 12
|line 13
status - /tmp/x-cu-vm/f 5/30 16%
cursor 4 0 bells 0
```

### ^E scrolls a line, the cursor kept on the screen

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b (bytes->str (list 5))) (vi-b (bytes->str (list 5)))) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 3
|line 4
|line 5
|line 6
|line 7
|line 8
|line 9
|line 10
|line 11
status - /tmp/x-cu-vm/f 3/30 10%
cursor 0 0 bells 0
```

### ^Y scrolls back a line

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b ":20" (lit cr)) (vi-b (bytes->str (list 25)))) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 15
|line 16
|line 17
|line 18
|line 19
|line 20
|line 21
|line 22
|line 23
status - /tmp/x-cu-vm/f 20/30 66%
cursor 5 0 bells 0
```

### Page Down and Page Up

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b (lit esc) "[6~") (vi-b (lit esc) "[6~") (vi-b (lit esc) "[5~")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 9
|line 10
|line 11
|line 12
|line 13
|line 14
|line 15
|line 16
|line 17
status - /tmp/x-cu-vm/f 17/30 56%
cursor 8 0 bells 0
```

### z and Return puts the line at the top

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b ":15" (lit cr)) (vi-b "z" (lit cr))) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 15
|line 16
|line 17
|line 18
|line 19
|line 20
|line 21
|line 22
|line 23
status - /tmp/x-cu-vm/f 15/30 50%
cursor 0 0 bells 0
```

### z. puts it in the middle

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b ":15" (lit cr)) (vi-b "z.")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 11
|line 12
|line 13
|line 14
|line 15
|line 16
|line 17
|line 18
|line 19
status - /tmp/x-cu-vm/f 15/30 50%
cursor 4 0 bells 0
```

### z- puts it at the bottom

```cu
(vi-case "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10\nline 11\nline 12\nline 13\nline 14\nline 15\nline 16\nline 17\nline 18\nline 19\nline 20\nline 21\nline 22\nline 23\nline 24\nline 25\nline 26\nline 27\nline 28\nline 29\nline 30\n" (list (vi-b ":15" (lit cr)) (vi-b "z-")) "/tmp/x-cu-vm/f")
```
---
```output
exit 1
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
line 9
line 10
line 11
line 12
line 13
line 14
line 15
line 16
line 17
line 18
line 19
line 20
line 21
line 22
line 23
line 24
line 25
line 26
line 27
line 28
line 29
line 30
--
|line 7
|line 8
|line 9
|line 10
|line 11
|line 12
|line 13
|line 14
|line 15
status - /tmp/x-cu-vm/f 15/30 50%
cursor 8 0 bells 0
```

