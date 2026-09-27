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
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-streams && mkdir -p /tmp/x-cu-streams")) (def feed (fn (_ pieces mark?) (let ((left (list pieces)) (asked (list 0))) (list (fn (_ . how) (if (null? how) (error "asked for the whole input") (do (set-first! asked (+ (first asked) 1)) (if mark? (display "|") ()) (if (null? (first left)) "" (let ((p (first (first left)))) (do (set-first! left (rest (first left))) p)))))) asked)))) (def endless (fn (_ piece) (let ((asked (list 0))) (list (fn (_ . how) (match ((null? how) (error "asked for the whole input")) ((>= (first asked) 100) (error "asked for a hundred pieces")) (#t (do (set-first! asked (+ (first asked) 1)) piece)))) asked)))) (def asked (fn (_ src) (list (first (first (rest src)))))) (def run (fn (_ argv src) (%cu-dispatch (%cu-find-applet (first argv)) (first argv) (rest argv) (first src)))) (def out-of (fn (_ thunk) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((o (file-open-write "/tmp/x-cu-streams/.out")) (e (file-open-write "/tmp/x-cu-streams/.err"))) (do (sys-dup2 o 1) (sys-dup2 e 2) (thunk) (sys-dup2 9 1) (sys-dup2 8 2) (file-close o) (file-close e) (file-read-all "/tmp/x-cu-streams/.out")))))) (def cut-up (fn (_ text n) (let ((go (fn (self i acc) (if (>= i (byte-len text)) (reverse acc) (self (+ i n) (pair (substring text i (if (> (+ i n) (byte-len text)) (byte-len text) (+ i n))) acc)))))) (go 0 ())))) (def same-cut? (fn (_ argv text n) (let ((whole (out-of (fn (_) (cu-run argv text)))) (cut (out-of (fn (_) (run argv (feed (cut-up text n) #f)))))) (if (= (byte-len whole) 0) #f (string=? whole cut))))) (def text (string-concat (list "one two  three\n" "\tlead\ttabs  and  spaces\n" "aaa\naaa\nbbb\n" "carriage\r\nreturn\r\n" "a line long enough to cross a few of the smaller pieces, twice over\n" "\n" "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n" "c,d\nno newline at the end"))) (def enc (out-of (fn (_) (cu-run (list "base64") text)))) (def filters (list (list "cat") (list "cat" "-n") (list "cat" "-b") (list "cat" "-A") (list "cat" "-vn") (list "tr" "a-z" "A-Z") (list "tr" "-s" " ") (list "tr" "-d" "aeiou") (list "cut" "-c" "2-4") (list "cut" "-d" " " "-f" "2") (list "cut" "-s" "-d" "," "-f" "1") (list "fold" "-w" "5") (list "fold" "-s" "-w" "6") (list "nl") (list "nl" "-b" "a") (list "rev") (list "expand" "-t" "4") (list "unexpand" "-a") (list "uniq" "-c") (list "wc") (list "wc" "-L") (list "dos2unix") (list "unix2dos") (list "tee") (list "od" "-c") (list "od" "-An" "-tx1" "-j" "3" "-N" "40") (list "base64") (list "base64" "-w" "10") (list "dd" "bs=3" "skip=2" "count=9" "status=none") (list "dd" "conv=swab" "status=none") (list "dd" "conv=ucase" "status=none"))) (display (list (byte-len text) (length filters))))
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

## yes, which feeds them

yes writes into a named pipe from a forked child, which takes a broken pipe
(SIGPIPE, 13) as a failed write rather than as its end; the parent reads the
other end a buffer at a time, checks that each read is `y` lines, and closes
it after 16 MB, or after 30 seconds if they are slower coming, so a yes that
writes little at a time fails the case rather than holding up the file.  The
child arms the allocator's guard 1,400,000 objects above
the heap it starts from: about half again above what yes holds at its
fullest on the release lang.xon declares, the leavings of 512 writes between
sweeps, and under what it holds with its sweeps turned off over the same
16 MB.

### the pipe, and a reader for it

```cu
(do (def ywant (string-append (let ((go (fn (self s k) (if (= k 0) s (self (string-append s s) (- k 1)))))) (go "y\n" 15)) "y\n")) (def yes-read (fn (_ bound mb) (do (proc-run (list "/bin/sh" "-c" "rm -f /tmp/x-cu-streams/p")) (file-mkfifo "/tmp/x-cu-streams/p" 384) (let ((pid (sys-fork))) (if (= pid 0) (let ((w (file-open-wronly "/tmp/x-cu-streams/p")) (nul (file-open-write "/dev/null"))) (do (sys-dup2 w 1) (sys-dup2 nul 2) (sys-signal 13 cu-sig-ign) (cu-run (list "true") "") (%cu-heap-collect) ((prim-ref (lit alloc) (lit limit!)) (+ (Heap count) bound)) (sys-exit (cu-run (list "yes") "")))) (let ((r (file-open-read "/tmp/x-cu-streams/p")) (buf (%str-make-raw 65536)) (until (+ (date-now-unix) 30))) (let ((go (fn (self k got bad) (if (if (>= got (* mb 1048576)) #t (> (date-now-unix) until)) (list got bad) (let ((n (File read r buf 65536))) (if (<= n 0) (list got bad) (do (if (= (% k 64) 0) (%cu-heap-collect) ()) (self (+ k 1) (+ got n) (if (string=? (substring buf 0 n) (substring ywant (% got 2) (+ (% got 2) n))) bad (+ bad 1)))))))))) (let ((res (go 1 0 0))) (do (file-close r) (list (first res) (first (rest res)) (sys-wait pid))))))))))) (display "made"))
```
---
    made

### 16 MB of `y` lines under the guard, and status 0 once its reader goes

Shown: the bytes read, the reads that were not `y` lines, and yes's status.

```cu
(display (yes-read 1400000 16))
```
---
    (16777216 0 0)

### a write carries 8,192 bytes of lines

The child counts yes's writes while the parent reads 64 KB: eight writes,
and as many again as the pipe holds ahead of its reader, and the one that
fails -- where a write a line would take more than 30,000.  Shown: whether
the 64 KB came, and whether it took fewer than 40 writes.

```cu
(do (def yes-writes (fn (_ bytes) (do (proc-run (list "/bin/sh" "-c" "rm -f /tmp/x-cu-streams/p /tmp/x-cu-streams/n")) (file-mkfifo "/tmp/x-cu-streams/p" 384) (let ((pid (sys-fork))) (if (= pid 0) (let ((w (file-open-wronly "/tmp/x-cu-streams/p")) (nul (file-open-write "/dev/null")) (writes (list 0)) (put file-write)) (do (sys-dup2 w 1) (sys-dup2 nul 2) (sys-signal 13 cu-sig-ign) (set! file-write (fn (_ fd s) (do (set-first! writes (+ (first writes) 1)) (put fd s)))) (cu-run (list "yes") "") (file-write-all "/tmp/x-cu-streams/n" (%cu-int->str (first writes))) (sys-exit 0))) (let ((r (file-open-read "/tmp/x-cu-streams/p")) (buf (%str-make-raw 65536))) (let ((go (fn (self got) (if (>= got bytes) got (let ((n (File read r buf 65536))) (if (<= n 0) got (self (+ got n)))))))) (let ((got (go 0))) (do (file-close r) (sys-wait pid) (list (>= got bytes) (< (%cu-num-prefix (file-read-all "/tmp/x-cu-streams/n")) 40))))))))))) (display (yes-writes 65536)))
```
---
    (#t #t)

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-streams")) (display "clean"))
```
---
    clean
