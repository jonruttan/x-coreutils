# @weight 1

vi's searches and colon commands, as busybox's vi (editors/vi.c) makes
them: / ? n N, addresses (. $ 'x /text/ ?text? % , ; + -), and :d :y :l
:s :w :r :e :f :n :prev :rew :=.  A search is for text, not a regular
expression, as busybox's is with its regex search off.  Each case types
keys at the editor through `%vi-typed`, in bursts with a pause between two,
into a window 10 rows by 40 columns unless it says otherwise, and shows the
exit status, the file, the rows as drawn, the bottom line, the cursor and
the bells.  A case that ends without :wq ends when its keys do, with status
1.

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
    (if (if (= b 10) #t (if (< 31 b) (< b 127) #f))
      (bytes->str (list b))
      (bytes->str (list 92 (%vi+ 48 (%vi/ b 64)) (%vi+ 48 (%vi% (%vi/ b 8) 8)) (%vi+ 48 (%vi% b 8)))))))
(def vi-shown
  (fn (_ s)
    (string-concat
      (List map (fn (_ i) (vi-byte (& (byte-at s i) 255))) (List range 0 (byte-len s))))))
(def vi-trim
  (fn (self s)
    (if (if (< 0 (byte-len s)) (= (byte-at s (- (byte-len s) 1)) 32) #f)
      (self (substring s 0 (- (byte-len s) 1)))
      s)))
(def vi-bells-in
  (fn (self s i n)
    (if (< i (byte-len s)) (self s (+ i 1) (if (= (byte-at s i) 7) (+ n 1) n)) n)))
(def vi-bells
  (fn (self ds n)
    (if (null? ds) n (self (rest ds) (vi-bells-in (first ds) 0 n)))))
(def vi-case
  (fn (_ text bursts target . mode)
    (apply vi-case-in (List append (list 10 40 text bursts target) mode))))
(def vi-case-in
  (fn (_ rows cols text bursts target . mode)
    (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-vx && mkdir -p /tmp/x-cu-vx"))
    (if (null? text) () (file-write-all "/tmp/x-cu-vx/f" text))
    (if (null? mode) () (proc-run (list "/bin/chmod" (first mode) "/tmp/x-cu-vx/f")))
    (def st (%vi-typed (list target) bursts rows cols #f))
    (def f (if (file-exists? "/tmp/x-cu-vx/f") (vi-shown (file-read-all "/tmp/x-cu-vx/f")) "no file\n"))
    (display
      (string-concat
        (list "exit " (%cu-int->str st) "\n"
              (if (if (< 0 (byte-len f)) (= (byte-at f (- (byte-len f) 1)) 10) #t) f
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

## searching

### / finds the next place the text is

```cu
(vi-case "one two three\ntwo\nthree two\n" (list (vi-b "/two" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
one two three
two
three two
--
|one two three
|two
|three two
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vx/f 1/3 33%
cursor 0 4 bells 0
```

### n finds the next after it

```cu
(vi-case "one two three\ntwo\nthree two\n" (list (vi-b "/two" (lit cr)) (vi-b "n")) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
one two three
two
three two
--
|one two three
|two
|three two
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vx/f 2/3 66%
cursor 1 0 bells 0
```

### 2/ finds the second

```cu
(vi-case "a a a a\n" (list (vi-b "2/a" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
a a a a
--
|a a a a
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vx/f 1/1 100%
cursor 0 4 bells 0
```

### / past the last goes round to the top

```cu
(vi-case "one two three\ntwo\nthree two\n" (list (vi-b "G") (vi-b "/one" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
one two three
two
three two
--
|one two three
|two
|three two
|~
|~
|~
|~
|~
|~
status search hit BOTTOM, continuing at TOP
cursor 0 0 bells 0
```

### / for text that is not there

```cu
(vi-case "one two three\ntwo\nthree two\n" (list (vi-b "/zz" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
one two three
two
three two
--
|one two three
|two
|three two
|~
|~
|~
|~
|~
|~
status Pattern not found
cursor 0 0 bells 0
```

### ? finds the last place before the cursor

```cu
(vi-case "one two three\ntwo\nthree two\n" (list (vi-b "G") (vi-b "?one" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
one two three
two
three two
--
|one two three
|two
|three two
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vx/f 1/3 33%
cursor 0 0 bells 0
```

### N searches the other way

```cu
(vi-case "one two three\ntwo\nthree two\n" (list (vi-b "/two" (lit cr)) (vi-b "n") (vi-b "N")) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
one two three
two
three two
--
|one two three
|two
|three two
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vx/f 1/3 33%
cursor 0 4 bells 0
```

### ? before the first goes round to the bottom

```cu
(vi-case "one two three\ntwo\nthree two\n" (list (vi-b "?three" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
one two three
two
three two
--
|one two three
|two
|three two
|~
|~
|~
|~
|~
|~
status search hit TOP, continuing at BOTTOM
cursor 2 0 bells 0
```

### n before any search

```cu
(vi-case "one two three\ntwo\nthree two\n" (list (vi-b "n")) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
one two three
two
three two
--
|one two three
|two
|three two
|~
|~
|~
|~
|~
|~
status No previous search
cursor 0 0 bells 0
```

### / alone searches for the last text again

```cu
(vi-case "one two three\ntwo\nthree two\n" (list (vi-b "/two" (lit cr)) (vi-b "/" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
one two three
two
three two
--
|one two three
|two
|three two
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vx/f 2/3 66%
cursor 1 0 bells 0
```

### ? alone searches for it the other way

```cu
(vi-case "one two three\ntwo\nthree two\n" (list (vi-b "/two" (lit cr)) (vi-b "n") (vi-b "?" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
one two three
two
three two
--
|one two three
|two
|three two
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vx/f 1/3 33%
cursor 0 4 bells 0
```

### / backspaced away searches for nothing

```cu
(vi-case "one two three\ntwo\nthree two\n" (list (vi-b "/" (lit bs))) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
one two three
two
three two
--
|one two three
|two
|three two
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vx/f 1/3 33%
cursor 0 0 bells 0
```

### d/ deletes up to the text found

```cu
(vi-case "one two three\n" (list (vi-b "d/thr" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 0
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
status '/tmp/x-cu-vx/f' 1L, 6C
cursor 0 0 bells 0
```

### ? does not find text that the cursor is on

```cu
(vi-case "ab ab\n" (list (vi-b "$") (vi-b "?ab" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
ab ab
--
|ab ab
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vx/f 1/1 100%
cursor 0 0 bells 0
```

### ? does not find text that ends by the cursor

```cu
(vi-case "ab abx\n" (list (vi-b "$") (vi-b "?ab" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
ab abx
--
|ab abx
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vx/f 1/1 100%
cursor 0 0 bells 0
```

## addresses

### :$ is the last line

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":$" (lit cr))) "/tmp/x-cu-vx/f")
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
status - /tmp/x-cu-vx/f 5/5 100%
cursor 4 0 bells 0
```

### :.+2 is two lines on

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":.+2" (lit cr))) "/tmp/x-cu-vx/f")
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
status - /tmp/x-cu-vx/f 3/5 60%
cursor 2 0 bells 0
```

### :-2 is two lines back

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b "G") (vi-b ":-2" (lit cr))) "/tmp/x-cu-vx/f")
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
status - /tmp/x-cu-vx/f 3/5 60%
cursor 2 0 bells 0
```

### :2+1 and :4-2

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":2+1" (lit cr)) (vi-b "x") (vi-b ":4-2" (lit cr)) (vi-b "x") (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 0
one
wo
hree
four
five
--
|one
|wo
|hree
|four
|five
|~
|~
|~
|~
status '/tmp/x-cu-vx/f' 5L, 22C
cursor 1 0 bells 0
```

### :'a is the line of mark a

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b "jjma") (vi-b "gg") (vi-b ":'a" (lit cr))) "/tmp/x-cu-vx/f")
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
status - /tmp/x-cu-vx/f 3/5 60%
cursor 2 0 bells 0
```

### :'z with no mark z

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":'z" (lit cr))) "/tmp/x-cu-vx/f")
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
status Mark not set
cursor 0 0 bells 0
```

### :/text/ is the next line holding it

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":/four/" (lit cr))) "/tmp/x-cu-vx/f")
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
status - /tmp/x-cu-vx/f 4/5 80%
cursor 3 0 bells 0
```

### :?text? the last before

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b "G") (vi-b ":?two?" (lit cr))) "/tmp/x-cu-vx/f")
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
status - /tmp/x-cu-vx/f 2/5 40%
cursor 1 0 bells 0
```

### :?text? the nearest before, not the next after

```cu
(vi-case "two\none\ntwo\nthree\nfour\ntwo\n" (list (vi-b "4G") (vi-b ":?two?" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
two
one
two
three
four
two
--
|two
|one
|two
|three
|four
|two
|~
|~
|~
status - /tmp/x-cu-vx/f 3/6 50%
cursor 2 0 bells 0
```

### :/text/ that is nowhere

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":/zz/" (lit cr))) "/tmp/x-cu-vx/f")
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
status Pattern not found
cursor 0 0 bells 0
```

### :2,4 goes to the second address

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":2,4" (lit cr))) "/tmp/x-cu-vx/f")
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
status - /tmp/x-cu-vx/f 4/5 80%
cursor 3 0 bells 0
```

### := says the current line

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b "j") (vi-b ":=" (lit cr))) "/tmp/x-cu-vx/f")
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
status 2
cursor 1 0 bells 0
```

### :$= says the last line's number

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":$=" (lit cr))) "/tmp/x-cu-vx/f")
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
status 5
cursor 0 0 bells 0
```

### :9 past the last line

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":9d" (lit cr))) "/tmp/x-cu-vx/f")
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
status Invalid range
cursor 0 0 bells 0
```

### :3,2 backwards

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":3,2d" (lit cr))) "/tmp/x-cu-vx/f")
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
status Invalid range
cursor 0 0 bells 0
```

## delete, yank, list

### :d deletes the current line

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b "j") (vi-b ":d" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 0
one
three
four
five
--
|one
|three
|four
|five
|~
|~
|~
|~
|~
status '/tmp/x-cu-vx/f' 4L, 20C
cursor 1 0 bells 0
```

### :2,4d deletes lines 2 to 4

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":2,4d" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 0
one
five
--
|one
|five
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vx/f' 2L, 9C
cursor 1 0 bells 0
```

### :%d deletes every line

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":%d" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 0

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
status '/tmp/x-cu-vx/f' 1L, 1C
cursor 0 0 bells 0
```

### :2;+1d reads the second address from the first

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":2;+1d" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
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
status '/tmp/x-cu-vx/f' 3L, 14C
cursor 1 0 bells 0
```

### :1,2y yanks two lines, and p puts them

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":1,2y" (lit cr)) (vi-b "G") (vi-b "p") (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 0
one
two
three
four
five
one
two
--
|one
|two
|three
|four
|five
|one
|two
|~
|~
status '/tmp/x-cu-vx/f' 7L, 32C
cursor 5 0 bells 0
```

### :y says what it yanked

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":2,3y" (lit cr))) "/tmp/x-cu-vx/f")
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
status Yank 2 lines (10 chars) into [D]
cursor 0 0 bells 0
```

### :y into a named register

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b "\"a:y" (lit cr))) "/tmp/x-cu-vx/f")
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
status Yank 1 lines (4 chars) into [a]
cursor 0 0 bells 0
```

### :l spells the line out

```cu
(vi-case (string-append "a\tb" (bytes->str (list 1)) "c\n") (list (vi-b ":l" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
a\011b\001c
--
|a       b^Ac
|~
|~
|~
|~
|~
|~
|~
|~
status a^Ib^Ac$
cursor 0 0 bells 0
```

### :l of a range shows its first line

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":2,3l" (lit cr))) "/tmp/x-cu-vx/f")
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
status two$
cursor 0 0 bells 0
```

## substitute

### :s replaces the first on the line

```cu
(vi-case "one two one\n" (list (vi-b ":s/one/1/" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 0
1 two one
--
|1 two one
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vx/f' 1L, 10C
cursor 0 0 bells 0
```

### :s of one says nothing

```cu
(vi-case "one two\n" (list (vi-b ":s/one/1/" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
one two
--
|1 two
|~
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vx/f [Modified] 1/1 100%
cursor 0 0 bells 0
```

### :s with g replaces each

```cu
(vi-case "one two one\n" (list (vi-b ":s/one/1/g" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 0
1 two 1
--
|1 two 1
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vx/f' 1L, 8C
cursor 0 0 bells 0
```

### :1,2s over two lines

```cu
(vi-case "a\na\na\n" (list (vi-b ":1,2s/a/b/" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
a
a
a
--
|b
|b
|a
|~
|~
|~
|~
|~
|~
status 2 substitutions on 2 lines
cursor 1 0 bells 0
```

### :%s with g over every line

```cu
(vi-case "aa\naa\n" (list (vi-b ":%s/a/b/g" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 0
bb
bb
--
|bb
|bb
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vx/f' 2L, 6C
cursor 1 0 bells 0
```

### :s with no match

```cu
(vi-case "one\n" (list (vi-b ":s/zz/y/" (lit cr))) "/tmp/x-cu-vx/f")
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
status No match
cursor 0 0 bells 0
```

### :s with no text uses the last search

```cu
(vi-case "one two\n" (list (vi-b "/two" (lit cr)) (vi-b ":s//2/" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 0
one 2
--
|one 2
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vx/f' 1L, 6C
cursor 0 0 bells 0
```

### :s with no text and no search

```cu
(vi-case "one\n" (list (vi-b ":s//x/" (lit cr))) "/tmp/x-cu-vx/f")
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
status No previous search
cursor 0 0 bells 0
```

### :s with nothing to put back deletes

```cu
(vi-case "one two\n" (list (vi-b ":s/two//" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
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
status '/tmp/x-cu-vx/f' 1L, 5C
cursor 0 0 bells 0
```

### :s with another delimiter

```cu
(vi-case "a/b\n" (list (vi-b ":s,/,+," (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 0
a+b
--
|a+b
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vx/f' 1L, 4C
cursor 0 0 bells 0
```

### :s with one delimiter

```cu
(vi-case "one\n" (list (vi-b ":s/one" (lit cr))) "/tmp/x-cu-vx/f")
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
status :s expression missing delimiters
cursor 0 0 bells 0
```

### :s with a space before the pattern

```cu
(vi-case "one\n" (list (vi-b ":s /one/1/" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 0
1
--
|1
|~
|~
|~
|~
|~
|~
|~
|~
status '/tmp/x-cu-vx/f' 1L, 2C
cursor 0 0 bells 0
```

### :s sets the search n goes on with

```cu
(vi-case "one two\none\n" (list (vi-b ":s/one/1/" (lit cr)) (vi-b "n")) "/tmp/x-cu-vx/f")
```
---
```output
exit 1
one two
one
--
|1 two
|one
|~
|~
|~
|~
|~
|~
|~
status - /tmp/x-cu-vx/f [Modified] 2/2 100%
cursor 1 0 bells 0
```

### :2s on one addressed line

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":2s/o/0/" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 0
one
tw0
three
four
five
--
|one
|tw0
|three
|four
|five
|~
|~
|~
|~
status '/tmp/x-cu-vx/f' 5L, 24C
cursor 1 0 bells 0
```

## files

### :2,3w writes a range to a new file

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":2,3w /tmp/x-cu-vx/g" (lit cr))) "/tmp/x-cu-vx/f")
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
status '/tmp/x-cu-vx/g' 2L, 10C
cursor 0 0 bells 0
```

### :w to a file that is there

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":w /tmp/x-cu-vx/g" (lit cr)) (vi-b ":w /tmp/x-cu-vx/g" (lit cr))) "/tmp/x-cu-vx/f")
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
status File exists (:w! overrides)
cursor 0 0 bells 0
```

### :1w of a changed text leaves it changed

```cu
(vi-case-in 10 50 "one\ntwo\nthree\nfour\nfive\n" (list (vi-b "x") (vi-b ":1w! /tmp/x-cu-vx/g" (lit cr)) (vi-b ":q" (lit cr))) "/tmp/x-cu-vx/f")
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
|ne
|two
|three
|four
|five
|~
|~
|~
|~
status No write since last change (:q! overrides)
cursor 0 0 bells 0
```

### :r % reads the file after the current line

```cu
(vi-case "one\ntwo\n" (list (vi-b ":r %" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 0
one
one
two
two
--
|one
|one
|two
|two
|~
|~
|~
|~
|~
status '/tmp/x-cu-vx/f' 4L, 16C
cursor 1 0 bells 0
```

### :0r reads before the first line

```cu
(vi-case "one\ntwo\n" (list (vi-b ":0r %" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 0
one
two
one
two
--
|one
|two
|one
|two
|~
|~
|~
|~
|~
status '/tmp/x-cu-vx/f' 4L, 16C
cursor 0 0 bells 0
```

### :$r reads after the last line

```cu
(vi-case "one\ntwo\n" (list (vi-b ":$r %" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
```
---
```output
exit 0
one
two
one
two
--
|one
|two
|one
|two
|~
|~
|~
|~
|~
status '/tmp/x-cu-vx/f' 4L, 16C
cursor 2 0 bells 0
```

### :r of a file that is not there

```cu
(vi-case-in 10 50 "one\n" (list (vi-b ":r /tmp/x-cu-vx/zz" (lit cr))) "/tmp/x-cu-vx/f")
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
status '/tmp/x-cu-vx/zz' No such file or directory
cursor 0 0 bells 0
```

### :e of a changed text refuses

```cu
(vi-case-in 10 50 "one\n" (list (vi-b "x") (vi-b ":e" (lit cr))) "/tmp/x-cu-vx/f")
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
status No write since last change (:e! overrides)
cursor 0 0 bells 0
```

### :e! reads the file again

```cu
(vi-case "one\n" (list (vi-b "x") (vi-b ":e!" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
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
status '/tmp/x-cu-vx/f' 1L, 4C
cursor 0 0 bells 0
```

### :e another file, then :e # back

```cu
(vi-case "one\n" (list (vi-b ":w /tmp/x-cu-vx/g" (lit cr)) (vi-b ":e /tmp/x-cu-vx/g" (lit cr)) (vi-b ":e #" (lit cr))) "/tmp/x-cu-vx/f")
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
status '/tmp/x-cu-vx/f' 1L, 4C
cursor 0 0 bells 0
```

### :e of a file that is not there

```cu
(vi-case "one\n" (list (vi-b ":e /tmp/x-cu-vx/new" (lit cr))) "/tmp/x-cu-vx/f")
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
status '/tmp/x-cu-vx/new' [New file] 1L, 1C
cursor 0 0 bells 0
```

### :e # with no other file

```cu
(vi-case "one\n" (list (vi-b ":e #" (lit cr))) "/tmp/x-cu-vx/f")
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
status No previous filename
cursor 0 0 bells 0
```

### :f names the file anew, and :w writes there

```cu
(vi-case "one\n" (list (vi-b ":f /tmp/x-cu-vx/g" (lit cr)) (vi-b ":w" (lit cr)) (vi-b ":f" (lit cr))) "/tmp/x-cu-vx/f")
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
status - /tmp/x-cu-vx/g 1/1 100%
cursor 0 0 bells 0
```

### :2f takes no address

```cu
(vi-case "one\ntwo\nthree\nfour\nfive\n" (list (vi-b ":2f" (lit cr))) "/tmp/x-cu-vx/f")
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
status No address allowed on this command
cursor 0 0 bells 0
```

### :n with no more files

```cu
(vi-case "one\n" (list (vi-b ":n" (lit cr))) "/tmp/x-cu-vx/f")
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
status No more files to edit
cursor 0 0 bells 0
```

### :prev with none before

```cu
(vi-case "one\n" (list (vi-b ":prev" (lit cr))) "/tmp/x-cu-vx/f")
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
status No previous files to edit
cursor 0 0 bells 0
```

### :rew starts the first file again

```cu
(vi-case "one\n" (list (vi-b "x") (vi-b ":rew!" (lit cr)) (vi-b ":wq" (lit cr))) "/tmp/x-cu-vx/f")
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
status '/tmp/x-cu-vx/f' 1L, 4C
cursor 0 0 bells 0
```

### a command is read to nine bytes

```cu
(vi-case "one\n" (list (vi-b ":writexyzab" (lit cr))) "/tmp/x-cu-vx/f")
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
status 'writexyza' is not implemented
cursor 0 0 bells 0
```

