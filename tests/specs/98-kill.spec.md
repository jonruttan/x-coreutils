# @weight 1

busybox's kill (procps/kill.c) and the signal names it shares with pkill
(libbb/u_signal_names.c).  Every expectation is busybox's own, run in
alpine; the numbers that differ between kernels are checked against this
one.  A pid that no process has is 2147483647; the runs that signal a live
process signal children this spec starts, or send signal 0, which only asks.
A `|` marks the end of each line written to standard output.

## the fixture

### a run of an applet, with its stdout, stderr and status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-kill && mkdir -p /tmp/x-cu-kill")) (def nf (fn (_ n) (string-append "/tmp/x-cu-kill/" n))) (def capture (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (list (file-read-all (nf ".out")) (file-read-all (nf ".err")) st)))))) (def run (fn (_ argv) (let ((r (capture argv))) (display (%str-concat (list (Str8 replace "\n" "|\n" (first r)) "stderr:\n" (first (rest r)) "status " (cu-int->str (first (rest (rest r)))) "\n")))))) (def kill (fn (_ . words) (run (pair "kill" words)))) (def same (fn (_ a b) (if (null? a) (null? b) (if (null? b) #f (= a b))))) (def child (fn (_) (let ((kid (sys-fork))) (if (= kid 0) (do (sys-exec "/bin/sleep" (list "30.4343")) (sys-exit 127)) kid)))) (display "made"))
```
---
    made

## whom to kill

### no pid at all, after a signal or --, is refused

```cu
(do (kill) (kill "-9") (kill "-s" "9") (kill "--"))
```
---
```output
stderr:
kill: you need to specify whom to kill
status 1
stderr:
kill: you need to specify whom to kill
status 1
stderr:
kill: you need to specify whom to kill
status 1
stderr:
kill: you need to specify whom to kill
status 1
```

## kill -l

### a number names its signal by its low 7 bits, EXIT for 0, itself for none

```cu
(do (kill "-l" "9") (kill "-l" "9" "15") (kill "-l" "137") (kill "-l" "200") (kill "-l" "0") (kill "-l" "64") (kill "-l" "09") (kill "-l" "4294967295"))
```
---
```output
KILL|
stderr:
status 0
KILL|
TERM|
stderr:
status 0
KILL|
stderr:
status 0
72|
stderr:
status 0
EXIT|
stderr:
status 0
64|
stderr:
status 0
KILL|
stderr:
status 0
127|
stderr:
status 0
```

### a name answers its number: any case, with or without SIG, EXIT, IOT

```cu
(do (kill "-l" "KILL") (kill "-l" "kill") (kill "-l" "SIGKILL") (kill "-l" "sigterm") (kill "-l" "EXIT") (kill "-l" "IOT"))
```
---
```output
9|
stderr:
status 0
9|
stderr:
status 0
9|
stderr:
status 0
15|
stderr:
status 0
0|
stderr:
status 0
6|
stderr:
status 0
```

### the first word that is neither ends the list, with 1

```cu
(do (kill "-l" "+9") (kill "-l" "nope") (kill "-l" "9" "nope" "15") (kill "-l" "9x") (kill "-l" "4294967296") (kill "-l" "") (kill "-l" " 9") (kill "-l" "-9") (kill "-l" "9" "--") (kill "-l" "--help"))
```
---
```output
stderr:
kill: unknown signal '+9'
status 1
stderr:
kill: unknown signal 'nope'
status 1
KILL|
stderr:
kill: unknown signal 'nope'
status 1
stderr:
kill: unknown signal '9x'
status 1
stderr:
kill: unknown signal '4294967296'
status 1
stderr:
kill: unknown signal ''
status 1
stderr:
kill: unknown signal ' 9'
status 1
stderr:
kill: unknown signal '-9'
status 1
KILL|
stderr:
kill: unknown signal '--'
status 1
stderr:
kill: unknown signal '--help'
status 1
```

### alone, it lists the kernel's signals, then libc's RTMIN and RTMAX where it has them

```cu
(let ((r (capture (list "kill" "-l"))) (rt (pg-rt)) (line (fn (_ n name) (%str-concat (list (cu-pad-left (cu-int->str n) 2) ") " name "\n"))))) (list (str=? (first r) (%str-concat (append (map (fn (_ e) (line (rest e) (first e))) (sys-signals)) (if (null? rt) () (list (line (first rt) "RTMIN") (line (rest rt) "RTMAX")))))) (str=? (first r) (first (capture (list "pkill" "-l")))) (first (rest r)) (first (rest (rest r))) (= (length (sys-signals)) 31) (if (null? rt) os-darwin? (if (< (first rt) (rest rt)) (= (rest rt) 64) #f))))
```
---
    (#t #t "" 0 #t #t)

### the names each kernel numbers its own way

```cu
(map (fn (_ e) (same (pg-signum (first e)) (if os-darwin? (first (rest e)) (first (rest (rest e)))))) (list (list "USR1" 30 10) (list "USR2" 31 12) (list "CHLD" 20 17) (list "STOP" 17 19) (list "SYS" 12 31) (list "BUS" 10 7) (list "IO" 23 29) (list "io" 23 29) (list "SIGIO" 23 29) (list "POLL" () 29) (list "PWR" () 30) (list "STKFLT" () 16) (list "EMT" 7 ()) (list "INFO" 29 ())))
```
---
    (#t #t #t #t #t #t #t #t #t #t #t #t #t #t)

### a number is a signal below NSIG: 65 where libc has real-time signals, 32 where it has none

```cu
(let ((rt (pg-rt))) (list (= (pg-nsig) (if os-darwin? 32 65)) (same (pg-signum "31") 31) (same (pg-signum "64") (if os-darwin? () 64)) (pg-signum "65") (pg-signum "99") (pg-signum "9x") (pg-signum "9 ") (pg-signum "9,") (pg-signum "+9") (pg-signum "")))
```
---
    (#t #t #t () () () 9 9 () ())

### RTMIN+N and RTMAX-N stay inside libc's range; where libc has none, no name reads

```cu
(let ((rt (pg-rt)) (none (fn (_ s) (null? (pg-signum s))))) (if (null? rt) (map none (list "RTMIN" "RTMAX" "RTMIN+1" "sigrtmin+1" "RTMAX-2" "RTMAX-0" "RTMIN+0" "RTMIN-1" "RTMINX")) (list (same (pg-signum "RTMIN") (first rt)) (same (pg-signum "sigrtmin+1") (+ (first rt) 1)) (same (pg-signum "RTMAX-2") (- (rest rt) 2)) (same (pg-signum "RTMAX-0") (rest rt)) (same (pg-signum (string-append "RTMIN+" (cu-int->str (- (rest rt) (first rt))))) (rest rt)) (none (string-append "RTMIN+" (cu-int->str (+ (- (rest rt) (first rt)) 1)))) (none "RTMAX-40") (none "RTMIN-1") (none "RTMINX"))))
```
---
    (#t #t #t #t #t #t #t #t #t)

## the signal

### a signal busybox has no name or number for is refused, before any pid

```cu
(do (kill "-nope" "1") (kill "-SIGNOPE" "1") (kill "-q" "1") (kill "-s") (kill "-") (kill "-s" "--" "1") (kill "-L" "1") (kill "-ll") (kill "-65" "1"))
```
---
```output
stderr:
kill: bad signal name 'nope'
status 1
stderr:
kill: bad signal name 'SIGNOPE'
status 1
stderr:
kill: bad signal name 'q'
status 1
stderr:
kill: bad signal name 's'
status 1
stderr:
kill: bad signal name ''
status 1
stderr:
kill: bad signal name '--'
status 1
stderr:
kill: bad signal name 'L'
status 1
stderr:
kill: bad signal name 'll'
status 1
stderr:
kill: bad signal name '65'
status 1
```

## the pids

### a pid no process has is said with the reason, and counted

```cu
(do (kill "-0" "2147483647") (kill "2147483647") (kill "-s" "KILL" "2147483647") (kill "-9 " "2147483647") (kill "-9," "2147483647") (kill "-0" "2147483647" "2147483646"))
```
---
```output
stderr:
kill: can't kill pid 2147483647: No such process
status 1
stderr:
kill: can't kill pid 2147483647: No such process
status 1
stderr:
kill: can't kill pid 2147483647: No such process
status 1
stderr:
kill: can't kill pid 2147483647: No such process
status 1
stderr:
kill: can't kill pid 2147483647: No such process
status 1
stderr:
kill: can't kill pid 2147483647: No such process
kill: can't kill pid 2147483646: No such process
status 2
```

### a word that is not an int is said from where it went wrong

```cu
(do (kill "abc") (kill "-0" "abc") (kill "-0" "2147483648") (kill "-0" "-2147483649") (kill "-0" "0x10") (kill "-0" "+12") (kill "-0" "12a") (kill "-0" "12,") (kill "-0" "-") (kill "-0" "--" "2147483647") (kill "-0" "--help"))
```
---
```output
stderr:
kill: invalid number 'abc'
status 1
stderr:
kill: invalid number 'abc'
status 1
stderr:
kill: invalid number '2147483648'
status 1
stderr:
kill: invalid number '-2147483649'
status 1
stderr:
kill: invalid number '0x10'
status 1
stderr:
kill: invalid number '+12'
status 1
stderr:
kill: invalid number '12a'
status 1
stderr:
kill: invalid number '12,'
status 1
stderr:
kill: invalid number '-'
status 1
stderr:
kill: invalid number '--'
kill: can't kill pid 2147483647: No such process
status 2
stderr:
kill: invalid number '--help'
status 1
```

### one word holds pids a blank apart, as the shell's kill hands them over

```cu
(do (kill "-0" "") (kill "-0" " 2147483647") (kill "-0" "2147483647 2147483646") (kill "-0" "2147483647 ") (kill "-0" "2147483647 x") (kill "-0" "2147483647  2147483646") (kill "-0" "  2147483647") (kill "-0" "0 0"))
```
---
```output
stderr:
status 0
stderr:
kill: can't kill pid 2147483647: No such process
status 1
stderr:
kill: can't kill pid 2147483647: No such process
kill: can't kill pid 2147483646: No such process
status 2
stderr:
kill: can't kill pid 2147483647: No such process
kill: invalid number ''
status 2
stderr:
kill: can't kill pid 2147483647: No such process
kill: invalid number 'x'
status 2
stderr:
kill: can't kill pid 2147483647: No such process
kill: invalid number ' 2147483646'
status 2
stderr:
kill: invalid number ' 2147483647'
status 1
stderr:
status 0
```

## this machine

### TERM by default, -SIG, -s SIG and -- signal this spec's children; -0 only asks

```cu
(let ((a (child)) (b (child)) (c (child)) (d (child))) (def as (fn (_ pid) (cu-int->str pid))) (def r0 (capture (list "kill" "-0" (as a)))) (def r1 (capture (list "kill" "--" (as a)))) (def r2 (capture (list "kill" "-INT" (as b)))) (def r3 (capture (list "kill" "-s" "hup" (%str-concat (list (as c) " " (as d)))))) (list r0 (sys-wait a) r1 (sys-wait b) r2 (sys-wait c) (sys-wait d) r3))
```
---
    (("" "" 0) 143 ("" "" 0) 130 ("" "" 0) 129 129 ("" "" 0))

## cleanup

### the scratch directory goes

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-kill")) (display "gone"))
```
---
    gone
