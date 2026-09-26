# @weight 4

The filters put out what they read as they read it: their input comes a
piece at a time, and each piece goes out -- as far as it holds whole lines,
for the tools that work a line at a time -- before the next is asked for.  A
tool that needs only the start of its input asks for no piece past it.  So
an input with no end, the output of yes, costs a filter a piece at a time,
and a reader after it that stops, as head does, stops it too.

Standard input here is a thunk that hands out pieces one at a time and
refuses to answer the whole text.  It counts the pieces it hands out, and
it can put a `|` out each time it is asked for one, which shows where each
piece's output went.  The one with no end hands out a hundred pieces and no
more, so a tool that never stops fails its case rather than running on.

## the fixtures

### a stdin of pieces, one with no end, a run on either, and a run's output kept

The text has words, tabs, runs of blanks, repeated lines, carriage returns,
a line longer than the pieces it is cut into, an empty line, a line of 64
bytes that od shows as a repeated line, and no newline at its end.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-st && mkdir -p /tmp/x-cu-st")) (def feed (fn (_ pieces mark?) (let ((left (list pieces)) (asked (list 0))) (list (fn (_ . how) (if (null? how) (error "asked for the whole input") (do (set-first! asked (+ (first asked) 1)) (if mark? (display "|") ()) (if (null? (first left)) "" (let ((p (first (first left)))) (do (set-first! left (rest (first left))) p)))))) asked)))) (def endless (fn (_ piece) (let ((asked (list 0))) (list (fn (_ . how) (match ((null? how) (error "asked for the whole input")) ((>= (first asked) 100) (error "asked for a hundred pieces")) (#t (do (set-first! asked (+ (first asked) 1)) piece)))) asked)))) (def asked (fn (_ src) (list (first (first (rest src)))))) (def run (fn (_ argv src) (%cu-dispatch (%cu-find-applet (first argv)) (first argv) (rest argv) (first src)))) (def out-of (fn (_ thunk) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((o (file-open-write "/tmp/x-cu-st/.out")) (e (file-open-write "/tmp/x-cu-st/.err"))) (do (sys-dup2 o 1) (sys-dup2 e 2) (thunk) (sys-dup2 9 1) (sys-dup2 8 2) (file-close o) (file-close e) (file-read-all "/tmp/x-cu-st/.out")))))) (def cut-up (fn (_ text n) (let ((go (fn (self i acc) (if (>= i (byte-len text)) (reverse acc) (self (+ i n) (pair (substring text i (if (> (+ i n) (byte-len text)) (byte-len text) (+ i n))) acc)))))) (go 0 ())))) (def same-cut? (fn (_ argv text n) (let ((whole (out-of (fn (_) (cu-run argv text)))) (cut (out-of (fn (_) (run argv (feed (cut-up text n) #f)))))) (if (= (byte-len whole) 0) #f (string=? whole cut))))) (def text (string-concat (list "one two  three\n" "\tlead\ttabs  and  spaces\n" "aaa\naaa\nbbb\n" "carriage\r\nreturn\r\n" "a line long enough to cross a few of the smaller pieces, twice over\n" "\n" "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n" "c,d\nno newline at the end"))) (def enc (out-of (fn (_) (cu-run (list "base64") text)))) (def filters (list (list "cat") (list "cat" "-n") (list "cat" "-b") (list "cat" "-A") (list "cat" "-vn") (list "tr" "a-z" "A-Z") (list "tr" "-s" " ") (list "tr" "-d" "aeiou") (list "cut" "-c" "2-4") (list "cut" "-d" " " "-f" "2") (list "cut" "-s" "-d" "," "-f" "1") (list "fold" "-w" "5") (list "fold" "-s" "-w" "6") (list "nl") (list "nl" "-b" "a") (list "rev") (list "expand" "-t" "4") (list "unexpand" "-a") (list "uniq" "-c") (list "wc") (list "wc" "-L") (list "dos2unix") (list "unix2dos") (list "tee") (list "od" "-c") (list "od" "-An" "-tx1" "-j" "3" "-N" "40") (list "base64") (list "base64" "-w" "10") (list "dd" "bs=3" "skip=2" "count=9" "status=none") (list "dd" "conv=swab" "status=none") (list "dd" "conv=ucase" "status=none"))) (display (list (byte-len text) (length filters))))
```
---
    (228 31)

## a piece at a time

### each piece goes out before the next is asked for

cat and tr take a piece as it comes; rev, cut and nl take the whole lines in
it and hold the rest of a line for the next; uniq writes a run once a
different line ends it; od writes each line of sixteen bytes, and base64
each line it fills.

```cu
(do (run (list "cat") (feed (list "ab\n" "cd\n") #t)) (newline) (run (list "tr" "a-z" "A-Z") (feed (list "ab" "cd") #t)) (newline) (run (list "rev") (feed (list "ab\ncd" "ef\n") #t)) (newline) (run (list "cut" "-c" "1") (feed (list "ab\n" "cd\n") #t)) (newline) (run (list "nl") (feed (list "a\n" "b\n") #t)) (newline) (run (list "uniq") (feed (list "a\na\n" "a\nb\n" "b\n") #t)) (newline) (run (list "od" "-An" "-c") (feed (list "abcdefghijklmnopq" "rs") #t)) (newline) (run (list "base64" "-w" "4") (feed (list "abcd" "ef") #t)) (display ""))
```
---
```output
|ab
|cd
|
|AB|CD|
|ba
|fedc
|
|a
|c
|
|     1	a
|     2	b
|
||a
||b

|   a   b   c   d   e   f   g   h   i   j   k   l   m   n   o   p
||   q   r   s

|YWJj
|ZGVm
|
```

### a tool that needs only the start of its input asks for no piece past it

od -N and dd count= stop reading once they have their bytes, from an input
that never ends; base64 -d stops at the first piece that holds what is not
base64.  Each shows what it put out, then the pieces it asked for.

```cu
(do (let ((src (endless "abc"))) (do (run (list "od" "-An" "-c" "-N" "5") src) (display (asked src)))) (newline) (let ((src (endless "abc"))) (do (run (list "dd" "bs=4" "count=2" "status=none") src) (display (asked src)))) (newline) (let ((src (feed (list "YWJj" "!!!!" "ZGVm") #f))) (do (display (out-of (fn (_) (run (list "base64" "-d") src)))) (display (asked src)))))
```
---
```output
   a   b   c   a   b
(2)
abcabcab(3)
abc(2)
```

## pieces cut anywhere

### what the whole text puts out, cut into pieces of one byte and of seven

Each filter runs on the text twice, whole and cut into pieces, and the two
outputs must agree -- a line split between pieces, a word, a carriage return
before its newline, a byte swab pairs, a line of od's or a step of base64's.
What is shown is the filters whose outputs differed, none.

```cu
(display (list (filter (fn (_ a) (not (same-cut? a text 1))) filters) (filter (fn (_ a) (not (same-cut? a text 7))) filters) (same-cut? (list "base64" "-d") enc 1) (same-cut? (list "base64" "-d") enc 7)))
```
---
    (() () #t #t)

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-st")) (display "clean"))
```
---
    clean
