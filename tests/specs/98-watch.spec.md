# @weight 1

busybox's watch (procps/watch.c).  Every expectation but the one marked is
busybox's own output for the same command line, run in Alpine with its
clock's time written as the epoch: each run here is a child that stops
after its first screens, so a period read wrongly cannot leave the suite
waiting, its clock rebound to 0 (TZ is UTC0 in the suite), its standard
error a file, so the width is $COLUMNS's or 80.  An escape is shown as `^[`
and a `|` marks the end of each line written to standard output.

## the fixture

### a run of watch in a child, stopped after ROUNDS screens: its stdout, stderr, status and first wait

```cu
(do (def watch-set! (fn (_ name v) (eval (list (lit set!) name (list (lit lit) v)) (module cu/watch)))) (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-watch && mkdir -p /tmp/x-cu-watch")) (def nf (fn (_ n) (string-append "/tmp/x-cu-watch/" n))) (def rounds (fn (_ n cols argv) (let ((pid (sys-fork))) (if (= pid 0) (do (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2))) (if (null? cols) (sys-unsetenv "COLUMNS") (sys-setenv "COLUMNS" cols)) (file-write-all (nf ".us") "") (def left (list n)) (eval (lit (set! %watch-now (fn (_) 0))) (module cu/watch)) (watch-set! (lit %watch-wait) (fn (_ us) (do (if (= (byte-len (file-read-all (nf ".us"))) 0) (file-write-all (nf ".us") (cu-int->str us)) ()) (set-first! left (- (first left) 1)) (if (= (first left) 0) (sys-exit 0) ())))) (sys-exit (cu-run argv ""))) (let ((st (sys-wait pid))) (list (file-read-all (nf ".out")) (file-read-all (nf ".err")) st (file-read-all (nf ".us")))))))) (def mark (fn (_ s) (bytes->str ((fn (self i acc) (if (< i 0) acc (self (- i 1) (match ((= (byte-at s i) 10) (pair 124 (pair 10 acc))) ((= (byte-at s i) 27) (pair 94 (pair 91 acc))) (#t (pair (byte-at s i) acc)))))) (- (byte-len s) 1) ())))) (def show (fn (_ r) (do (display (mark (first r))) (newline) (rest r)))) (def first-line (fn (_ s) ((fn (self i) (if (if (< i (byte-len s)) (not (= (byte-at s i) 10)) #f) (self (+ i 1)) (substring s 0 i))) 0))) (display "made"))
```
---
    made

## screens

### the header, an empty line and the command's output, each screen after home and clear; -n 0.25 shows as 0.2

```cu
(show (rounds 2 "80" (list "watch" "-n" "0.25" "echo" "hi" "there")))
```
---
```output
^[[H^[[JEvery 0.2s: echo hi there                                   1970-01-01 00:00:00|
|
hi there|
^[[H^[[JEvery 0.2s: echo hi there                                   1970-01-01 00:00:00|
|
hi there|

("" 0 "250000")
```

### no -n: every 2 seconds, and no COLUMNS: 80 wide

```cu
(show (rounds 2 () (list "watch" "echo" "hi")))
```
---
```output
^[[H^[[JEvery 2.0s: echo hi                                         1970-01-01 00:00:00|
|
hi|
^[[H^[[JEvery 2.0s: echo hi                                         1970-01-01 00:00:00|
|
hi|

("" 0 "2000000")
```

### -t: no header; the command's output as it is, a missing newline missing

```cu
(show (rounds 2 "80" (list "watch" "-t" "printf" "x")))
```
---
```output
^[[H^[[Jx^[[H^[[Jx
("" 0 "2000000")
```

### the words are joined for sh -c, which splits them again; -x runs them as they are

```cu
(list (show (rounds 2 "80" (list "watch" "-n" "0.2" "-t" "echo" "a   b"))) (show (rounds 2 "80" (list "watch" "-n" "0.2" "-t" "-x" "echo" "a   b"))))
```
---
```output
^[[H^[[Ja b|
^[[H^[[Ja b|

^[[H^[[Ja   b|
^[[H^[[Ja   b|

(("" 0 "200000") ("" 0 "200000"))
```

### -x and a command that will not run: nothing said, and the screens go on

```cu
(show (rounds 2 "80" (list "watch" "-n" "0.2" "-x" "nope-cmd" "a")))
```
---
```output
^[[H^[[JEvery 0.2s: nope-cmd a                                      1970-01-01 00:00:00|
|
^[[H^[[JEvery 0.2s: nope-cmd a                                      1970-01-01 00:00:00|
|

("" 0 "200000")
```

### sh's command that is not found: the screens go on

```cu
(let ((r (rounds 2 "80" (list "watch" "-n" "0.2" "-t" "nope-cmd")))) (list (mark (first r)) (> (byte-len (first (rest r))) 0) (first (rest (rest r)))))
```
---
    ("^[[H^[[J^[[H^[[J" #t 0)

### SIGINT is ignored while sh runs the command, as system() ignores it; under -x it ends watch

```cu
(list (show (rounds 2 "80" (list "watch" "-n" "0.2" "-t" "kill -INT $PPID; echo after"))) (let ((r (rounds 2 "80" (list "watch" "-n" "0.2" "-t" "-x" "sh" "-c" "kill -INT $PPID; echo after")))) (list (mark (first r)) (= (first (rest (rest r))) 0))))
```
---
```output
^[[H^[[Jafter|
^[[H^[[Jafter|

(("" 0 "200000") ("^[[H^[[Jafter|\n" #f))
```

### -d is taken and does nothing; -- ends the options, and so does the command's first word

```cu
(list (show (rounds 1 "80" (list "watch" "-d" "-n" "0.2" "echo" "d"))) (show (rounds 1 "80" (list "watch" "-n" "0.2" "--" "echo" "hi"))) (show (rounds 1 "80" (list "watch" "-n" "0.2" "echo" "-t"))))
```
---
```output
^[[H^[[JEvery 0.2s: echo d                                          1970-01-01 00:00:00|
|
d|

^[[H^[[JEvery 0.2s: echo hi                                         1970-01-01 00:00:00|
|
hi|

^[[H^[[JEvery 0.2s: echo -t                                         1970-01-01 00:00:00|
|
-t|

(("" 0 "200000") ("" 0 "200000") ("" 0 "200000"))
```

## the width

### past 20 columns the header is cut to one less than the width, the time at its end; a command too long is cut

```cu
(map (fn (_ cols) (first-line (let ((s (first (rounds 1 cols (list "watch" "-n" "0.2" "echo" "0123456789abcdefghij"))))) (substring s 6 (byte-len s))))) (list "30" "21" "22" "40"))
```
---
    ("Every 0.2s1970-01-01 00:00:00" "E1970-01-01 00:00:00" "Ev1970-01-01 00:00:00" "Every 0.2s: echo 0121970-01-01 00:00:00")

### 20 columns and under: the whole header, the command padded to the width

```cu
(map (fn (_ cols) (first-line (let ((s (first (rounds 1 cols (list "watch" "-n" "0.2" "echo" "hi"))))) (substring s 6 (byte-len s))))) (list "10" "20" "2"))
```
---
    ("Every 0.2s: echo hi   " "Every 0.2s: echo hi             " "Every 0.2s: echo hi")

### COLUMNS read as atoi reads it; under 2, past 29999, empty or no number: 80

```cu
(map (fn (_ cols) (byte-len (first-line (let ((s (first (rounds 1 cols (list "watch" "-n" "0.2" "echo" "hi"))))) (substring s 6 (byte-len s)))))) (list "1" "30000" "29999" " 40x" "" "-5" "abc"))
```
---
    (79 79 29998 39 79 79 79)

## the period

### seconds with a fraction, an s, m, h or d after them, printed as %.1f prints the double

```cu
(map (fn (_ p) (let ((r (rounds 1 "40" (list "watch" "-n" p "true")))) (list (substring (first-line (first r)) 6 20) (first (rest (rest (rest r))))))) (list "1m" "0.25" "0.35" "0.45" "0.05" "0.15" "0.95" "1.5m" ".5" "5." "0" "00007" "1s" "1h" "1d" "2.5h"))
```
---
    (("Every 60.0s: t" "60000000") ("Every 0.2s: tr" "250000") ("Every 0.3s: tr" "350000") ("Every 0.5s: tr" "450000") ("Every 0.1s: tr" "50000") ("Every 0.1s: tr" "150000") ("Every 0.9s: tr" "950000") ("Every 90.0s: t" "90000000") ("Every 0.5s: tr" "500000") ("Every 5.0s: tr" "5000000") ("Every 0.0s: tr" "0") ("Every 7.0s: tr" "7000000") ("Every 1.0s: tr" "1000000") ("Every 3600.0s:" "3600000000") ("Every 86400.0s" "86400000000") ("Every 9000.0s:" "9000000000"))

### no number: xatoul_sfx's message, naming what it read -- after a dot, a 1 and the rest

```cu
(map (fn (_ p) (let ((r (rounds 1 "80" (list "watch" "-n" p "echo")))) (list (first (rest r)) (first (rest (rest r)))))) (list "abc" "-1" "+1" "1.x" "1.5mm" "99999999999999999999" "1x.5" "12x.5" "1 " " 1" "1ms"))
```
---
    (("watch: invalid number 'abc'\n" 1) ("watch: invalid number '-1'\n" 1) ("watch: invalid number '+1'\n" 1) ("watch: invalid number '1x'\n" 1) ("watch: invalid number '1mm'\n" 1) ("watch: invalid number '99999999999999999999'\n" 1) ("watch: invalid number '1x.5'\n" 1) ("watch: invalid number '1x.5'\n" 1) ("watch: invalid number '1 '\n" 1) ("watch: invalid number ' 1'\n" 1) ("watch: invalid number '1ms'\n" 1))

### HERE, NOT BUSYBOX: a period is at most 2^53 microseconds, 285 years; past it no number, where busybox's takes up to 2^64 - 1 seconds

```cu
(list (let ((r (rounds 1 "80" (list "watch" "-n" "9007199254" "true")))) (list (substring (first-line (first r)) 6 25) (first (rest (rest (rest r)))))) (map (fn (_ p) (first (rest (rounds 1 "80" (list "watch" "-n" p "true"))))) (list "9007199255" "150119987.6m" "99999999999999999999.5")))
```
---
    (("Every 9007199254.0s" "9007199254000000") ("watch: invalid number '9007199255'\n" "watch: invalid number '150119987.6m'\n" "watch: invalid number '99999999999999999999.5'\n"))

### a number strtod reads only part of, a dot first or no digits: the usage

```cu
(map (fn (_ p) (let ((r (rounds 1 "80" (list "watch" "-n" p "echo")))) (list (first-line (first (rest r))) (first (rest (rest r)))))) (list "." "1..5" "-1.5" "x.5" "1.2.3"))
```
---
    (("Usage: watch [-n SEC] [-tx] PROG ARGS" 1) ("Usage: watch [-n SEC] [-tx] PROG ARGS" 1) ("Usage: watch [-n SEC] [-tx] PROG ARGS" 1) ("Usage: watch [-n SEC] [-tx] PROG ARGS" 1) ("Usage: watch [-n SEC] [-tx] PROG ARGS" 1))

## no command

### no PROG: the usage, before the period is read

```cu
(map (fn (_ argv) (let ((r (rounds 1 "80" argv))) (list (first r) (first-line (first (rest r))) (first (rest (rest r)))))) (list (list "watch") (list "watch" "-n" "abc") (list "watch" "-n" "1" "-tx")))
```
---
    (("" "Usage: watch [-n SEC] [-tx] PROG ARGS" 1) ("" "Usage: watch [-n SEC] [-tx] PROG ARGS" 1) ("" "Usage: watch [-n SEC] [-tx] PROG ARGS" 1))

### an option that takes -n's place is its value

```cu
(let ((r (rounds 1 "80" (list "watch" "-n" "-t" "echo")))) (list (first (rest r)) (first (rest (rest r)))))
```
---
    ("watch: invalid number '-t'\n" 1)

## memory

### 64 screens hold no more than 16 screens' garbage, collected every 16th: under 2.8M live objects (16 hold 1.85M; 64 unswept, 6.4M)

```cu
(let ((pid (sys-fork))) (if (= pid 0) (do (let ((nul (file-open-write "/dev/null"))) (do (sys-dup2 nul 1) (sys-dup2 nul 2))) (sys-setenv "COLUMNS" "80") (def n (list 0)) (watch-set! (lit %watch-wait) (fn (_ us) (do (set-first! n (+ (first n) 1)) (if (= (first n) 64) (sys-exit 0) ())))) (cu-heap-collect) ((prim-ref (lit alloc) (lit limit!)) (+ (Heap count) 2800000)) (cu-run (list "watch" "-n" "0" "true") "") (sys-exit 3)) (sys-wait pid)))
```
---
    0
