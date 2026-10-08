# @weight 1

busybox's who, w and users (coreutils/who.c): the utmpx sessions x/sys/host
reports, each a line.  The sessions are this machine's, so the cases check
the shape of what is printed against the records themselves: a line a
session, the columns busybox's `%-15.*s %-15.*s %-7s %-16.16s %.*s` gives,
and the header w and who -H print.  On a machine with no session, who
prints nothing, w its header and users an empty line.  Host reports the
USER_PROCESS sessions, so -a, which busybox has show every utmpx entry with
a user name, adds nothing here.  A `|` marks the end of each line written to
standard output.

## the fixture

### a run of an applet, with its stdout, stderr and status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-who && mkdir -p /tmp/x-cu-who")) (def nf (fn (_ n) (string-append "/tmp/x-cu-who/" n))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (list (file-read-all (nf ".out")) (file-read-all (nf ".err")) st)))))) (def out (fn (_ argv) (first (run argv)))) (def lines (fn (_ s) (filter (fn (_ l) (> (byte-len l) 0)) (%cu-lines s)))) (def trim (fn (_ s) (let ((go (fn (self i) (if (if (> i 0) (= (byte-at s (- i 1)) #\space) #f) (self (- i 1)) i)))) (substring s 0 (go (byte-len s)))))) (def zip (fn (self a b) (if (if (null? a) #t (null? b)) () (pair (list (first a) (first b)) (self (rest a) (rest b)))))) (display "made"))
```
---
    made

## who, w, users

### w prints its header, then a line a session

```cu
(let ((r (run (list "w"))) (n (length (host-users)))) (list (str=? (first (lines (first r))) "USER\t\tTTY\t\tIDLE\tTIME\t\t HOST") (= (length (lines (first r))) (+ n 1)) (first (rest r)) (first (rest (rest r)))))
```
---
    (#t #t "" 0)

### who prints a line a session, and -H the header before them

```cu
(let ((plain (out (list "who"))) (headed (out (list "who" "-H")))) (list (= (length (lines plain)) (length (host-users))) (str=? headed (string-append "USER\t\tTTY\t\tIDLE\tTIME\t\t HOST\n" plain)) (str=? (out (list "who" "-a")) plain)))
```
---
    (#t #t #t)

### each line: the user to column 16, the tty to 32, the idle to 40, the login time to 57, then the host

```cu
(let ((idle-rx (re-compile "^([0-9][0-9]:[0-9][0-9]|old|[?])$"))) (null? (filter (fn (_ r) (not (null? (filter (fn (_ v) (not v)) r)))) (map (fn (_ pr) (let ((l (first pr)) (u (first (rest pr)))) (def d (Date local (Assoc get (lit time) u))) (def two (fn (_ k) (%cu-pad-zero (%cu-int->str (Assoc get k d)) 2))) (list (str=? (trim (substring l 0 15)) (Assoc get (lit user) u)) (= (byte-at l 15) #\space) (str=? (trim (substring l 16 31)) (Assoc get (lit tty) u)) (not (null? (re-search idle-rx (trim (substring l 32 39))))) (str=? (substring l 40 56) (string-concat (list (%cu-nth (- (Assoc get (lit month) d) 1) %cu-date-mon-abbr) (%cu-pad-left (%cu-int->str (Assoc get (lit day) d)) 3) " " (two (lit hour)) ":" (two (lit minute)) ":" (two (lit second)) " "))) (str=? (substring l 57 (byte-len l)) (let ((h (Assoc get (lit host) u))) (if (null? h) "" h)))))) (zip (lines (out (list "who"))) (host-users))))))
```
---
    #t

### users: the names on one line, a space between

```cu
(let ((r (run (list "users")))) (list (str=? (first r) (string-append (%cu-join-with (map (fn (_ u) (Assoc get (lit user) u)) (host-users)) " ") "\n")) (first (rest (rest r)))))
```
---
    (#t 0)

### an operand is busybox's usage, for each of the three

```cu
(map (fn (_ a) (let ((r (run (list a "x")))) (list (first r) (first (rest (rest r))) (if (> (byte-len (first (rest r))) 0) (first (lines (first (rest r)))) "")))) (list "who" "w" "users"))
```
---
    (("" 1 "Usage: who [-aH]") ("" 1 "Usage: w") ("" 1 "Usage: users"))

## cleanup

### the scratch directory goes

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-who")) (display "gone"))
```
---
    gone
