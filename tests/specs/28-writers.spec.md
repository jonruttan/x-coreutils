# @weight 7

What the tools that write files say when a file will not open: tee,
truncate, dd, sort -o, shuf -o and shred.  Each says it in its own words and
fails; the ones given several files carry on with the rest.  The expected
text and statuses are GNU's for the same files.

## the fixtures

### a directory holding a read-only one, and a reader for both streams

`ro` is a directory nothing can be made in; `locked` is a file no one may
open.

```cu
(do (def w (fn (_ n) (string-append "/tmp/x-cu-wr/" n))) (def mk (fn (_) (proc-run (list "/bin/sh" "-c" "chmod -R u+rwx /tmp/x-cu-wr 2>/dev/null; rm -rf /tmp/x-cu-wr && mkdir -p /tmp/x-cu-wr/ro && cd /tmp/x-cu-wr && printf 'b\\na\\n' > in && printf keep > a && printf keep > b && printf 'secret\\n' > s1 && printf 'secret\\n' > s2 && : > locked && chmod 000 locked && chmod 555 ro")))) (mk) (def run (fn (_ argv input) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (w ".out"))) (ee (file-open-write (w ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def run-st (cu-run argv input)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (file-read-all (w ".out"))) (display (Str8 replace "/tmp/x-cu-wr/" "" (file-read-all (w ".err")))) (display "status ") (display run-st) (newline)))))) (def holds (fn (_ p) (display (string-concat (list p " holds " (Str8 replace "\n" "|" (file-read-all (w p))) "\n"))))) (def there (fn (_ p) (display (string-append p (if (eq? (file-lstat-kind (w p)) (lit none)) " gone\n" " there\n"))))) (def secret? (fn (_ p) (let ((t (file-read-all (w p)))) (display (string-append p (if (if (>= (byte-len t) 6) (string=? (substring t 0 6) "secret") #f) " still secret\n" " overwritten\n")))))) (display "made"))
```
---
    made

## tee and truncate

### tee says a file it cannot open, and still copies to the rest

```cu
(do (mk) (run (list "tee" (w "a") (w "ro/t") (w "b")) "b\na\n") (holds "a") (holds "b"))
```
---
```output
b
a
tee: ro/t: Permission denied
status 1
a holds b|a|
b holds b|a|
```

### truncate says one it cannot open, still cuts the rest, and -c passes a missing one

```cu
(do (mk) (run (list "truncate" "-s" "1" (w "a") (w "ro/t") (w "b")) "") (holds "a") (holds "b") (run (list "truncate" "-c" "-s" "0" (w "nosuch")) "") (there "nosuch"))
```
---
```output
truncate: cannot open 'ro/t' for writing: Permission denied
status 1
a holds k
b holds k
status 0
nosuch gone
```

## dd

### an input it cannot open is said, and nothing is written

```cu
(do (mk) (run (list "dd" (string-append "if=" (w "nosuch")) (string-append "of=" (w "out")) "status=none") "") (there "out"))
```
---
```output
dd: failed to open 'nosuch': No such file or directory
status 1
out gone
```

### so is an output, with no records to count

```cu
(do (mk) (run (list "dd" (string-append "if=" (w "in")) (string-append "of=" (w "ro/d"))) ""))
```
---
```output
dd: failed to open 'ro/d': Permission denied
status 1
```

## sort -o and shuf -o

### sort says an -o file it cannot write, and fails as sort fails

```cu
(do (mk) (run (list "sort" "-o" (w "ro/s") (w "in")) "") (run (list "sort" "-z" "-o" (w "ro/s") (w "in")) ""))
```
---
```output
sort: open failed: ro/s: Permission denied
status 2
sort: open failed: ro/s: Permission denied
status 2
```

### shuf says it too

```cu
(do (mk) (run (list "shuf" "-o" (w "ro/s") (w "in")) "") (run (list "shuf" "-z" "-o" (w "ro/s") (w "in")) ""))
```
---
```output
shuf: ro/s: Permission denied
status 1
shuf: ro/s: Permission denied
status 1
```

## shred

### a file it cannot open is said, and the rest are still overwritten

```cu
(do (mk) (run (list "shred" "-n" "1" (w "ro/nosuch") (w "s1")) "") (secret? "s1") (run (list "shred" "-n" "1" (w "locked")) ""))
```
---
```output
shred: ro/nosuch: failed to open for writing: No such file or directory
status 1
s1 overwritten
shred: locked: failed to open for writing: Permission denied
status 1
```

### every pass writes over the same bytes, so three leave the size one does

```cu
(do (mk) (run (list "shred" "-n" "1" (w "s1")) "") (run (list "shred" (w "s2")) "") (display (if (= (%cu-stat-get (file-stat-full (w "s1")) (lit size)) (%cu-stat-get (file-stat-full (w "s2")) (lit size))) "the same size\n" "a different size\n")))
```
---
```output
status 0
status 0
the same size
```

### -f opens a file the mode denies, and -u removes what it overwrote

```cu
(do (mk) (run (list "shred" "-n" "1" "-f" (w "locked")) "") (run (list "shred" "-n" "1" "-u" (w "s1") (w "s2")) "") (there "s1") (there "s2"))
```
---
```output
status 0
status 0
s1 gone
s2 gone
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "chmod -R u+rwx /tmp/x-cu-wr; rm -rf /tmp/x-cu-wr")) (display "clean"))
```
---
    clean
