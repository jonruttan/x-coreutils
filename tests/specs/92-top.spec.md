# @weight 1

busybox's top (procps/top.c).  Its numbers are checked against busybox's own
formatting -- smart_ulltoa5, fmt_100percent_8, the %RSS and %CPU
multiply-and-shift, the PID PPID USER squeeze -- as a program built from
busybox's source prints them for the same inputs.  The batch screen and the
memory view are then checked on this machine for their shape, since what
they show changes from run to run.  A `|` marks the end of each line written
to standard output.

## the fixture

### a run of an applet, with its stdout, stderr and status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-top && mkdir -p /tmp/x-cu-top")) (def nf (fn (_ n) (string-append "/tmp/x-cu-top/" n))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (list (file-read-all (nf ".out")) (file-read-all (nf ".err")) st)))))) (def lines (fn (_ s) (filter (fn (_ l) (> (byte-len l) 0)) (%cu-lines s)))) (display "made"))
```
---
    made

## busybox's numbers

### sizes in five characters, as smart_ulltoa5 writes kilobytes

```cu
(map %top-five (list 0 7 99999 100000 102400 999999 1048576 9437184 104857600 1073741824))
```
---
    ("    0" "    7" "99999" "97.6m" " 100m" " 976m" "1024m" "9216m" " 100g" "1024g")

### a CPU line's shares, as fmt_100percent_8 writes them

```cu
(map (fn (_ p) (%top-percent (first p) (first (rest p)))) (list (list 0 1) (list 5 1000) (list 123 1000) (list 999 1000) (list 1000 1000) (list 1 3) (list 250 400)))
```
---
    ("  0.0% " "  0.5% " " 12.3% " " 99.9% " "  100% " " 33.3% " " 62.5% ")

### %RSS and %CPU in tenths: MemTotal, a row's kilobytes, busy and total ticks, the processes' ticks and the row's

```cu
(map (fn (_ r) (let ((s (%top-scales-of (first r) (%cu-nth 2 r) (%cu-nth 3 r) (%cu-nth 4 r)))) (let ((sh (%top-shares (%cu-nth 1 r) (%cu-nth 5 r) s))) (list (first sh) (rest sh))))) (list (list 16384000 2048 400 1200 300 150) (list 16384000 819200 400 1200 300 0) (list 2048 4096 50 100 10 10) (list 7864320 123456 1 12 0 0) (list 16384000 2048 70000 70000 300 299)))
```
---
    ((0 125) (50 0) (2000 100) (15 0) (0 3))

### a process's ticks since the last scan, none when they fall -- a zombie's times, which Darwin does not give -- and their total

```cu
(do (set! %top-hist (list (pair 7 31) (pair 8 10) (pair 9 0))) (def rs (%top-stats! (list (list 7 1 0 0 501 "Z  " "z" () 0) (list 8 1 0 25 501 "R  " "r" () 0) (list 9 1 0 100 501 "R  " "b" () 0)))) (set! %top-hist ()) (list (map (fn (_ e) (%cu-nth 8 e)) rs) %top-total-pcpu))
```
---
    ((0 15 100) 115)

### PID PPID USER in twenty characters, a wide pid squeezing the spaces first

```cu
(list (%top-ppu 1 0 "root") (%top-ppu 4242 300 "averyverylongname") (%top-ppu 123456 1 "jon") (%top-ppu 1234567 1 "longusername") (%top-ppu 1234567 7654321 "u"))
```
---
    ("    1     0 root    " " 4242   300 averyver" "123456    1 jon     " "1234567   1 longuser" "1234567 7654321 u   ")

### the load line: the kernel's rounding of each average, then the run queue and last pid where they are kept

```cu
(list (%top-load-line (list 1065 1188 1208) (list (pair (lit running) 2) (pair (lit total) 1234) (pair (lit last-pid) 56789)))
      (%top-load-line (list 0 2048 4095) (list (pair (lit running) ()) (pair (lit total) ()) (pair (lit last-pid) ()))))
```
---
    ("Load average: 0.52 0.58 0.59 2/1234 56789" "Load average: 0.00 1.00 2.00")

### -d's durations: seconds with a fraction, and an s, m, h or d after them

```cu
(map %top-duration-ms (list "1" "0.5" "1.25s" "2m" "1h" "x" "" "1.5x"))
```
---
    (1000 500 1250 120000 3600000 () () ())

## the applet

### a bad delay or count is named, and 1

```cu
(list (run (list "top" "-b" "-d" "x")) (run (list "top" "-b" "-n" "x")))
```
---
    (("" "top: invalid number 'x'\n" 1) ("" "top: invalid number 'x'\n" 1))

### -bn1: the memory, CPU and load lines, the header, then a row a process (any of the first three that misses the pattern shown), ending in a newline

```cu
(let ((r (run (list "top" "-bn1")))) (def ls (lines (first r))) (def row-rx (re-compile "^ *[0-9]+ +[0-9]+ [^ ]+ +[A-Z ][A-Z<N ][A-Z<N ]  .....[ 0-9][ 0-9][ 0-9]\\.[0-9+]....[ 0-9][ 0-9][ 0-9]\\.[0-9] ")) (list (first (rest (rest r))) (first (rest r)) (str=? (substring (first r) (- (byte-len (first r)) 1) (byte-len (first r))) "\n") (not (null? (re-search (re-compile "^Mem: [0-9]+K used, [0-9]+K free, [0-9]+K shrd, [0-9]+K buff, [0-9]+K cached$") (first ls)))) (not (null? (re-search (re-compile "^CPU:( [ 0-9][0-9]\\.[0-9]% |  100% )usr") (first (rest ls))))) (not (null? (re-search (re-compile "^Load average: [0-9]+\\.[0-9][0-9] [0-9]+\\.[0-9][0-9] [0-9]+\\.[0-9][0-9]") (%cu-nth 2 ls)))) (%cu-nth 3 ls) (< 1 (length (%top-drop ls 4))) (filter (fn (_ l) (null? (re-search row-rx l))) (%top-take (%top-drop ls 4) 3))))
```
---
    (0 "" #t #t #t #t "  PID  PPID USER     STAT   RSS %RSS CPU %CPU COMMAND" #t ())

### busybox's dashless arguments: `top bn1` is `top -bn1`

```cu
(let ((r (run (list "top" "bn1")))) (list (first (rest (rest r))) (str=? (substring (first r) 0 5) "Mem: ")))
```
---
    (0 #t)

### -m: the memory view, its sort column marked, then a row a process

```cu
(let ((r (run (list "top" "-bmn1")))) (def ls (lines (first r))) (list (first (rest (rest r))) (not (null? (re-search (re-compile "^Mem total:[0-9]+ anon:[0-9]+ map:[0-9]+ free:[0-9]+$") (first ls)))) (not (null? (re-search (re-compile "^Swap total:[0-9]+ free:[0-9]+$") (%cu-nth 2 ls)))) (%cu-nth 3 ls) (< 0 (length (%top-drop ls 4)))))
```
---
    (0 #t #t "  PID^^^VSZ^VSZRW   RSS (SHR) DIRTY (SHR) STACK COMMAND" #t)

## cleanup

### the scratch directory goes

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-top")) (display "gone"))
```
---
    gone
