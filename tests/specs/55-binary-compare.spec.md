# @weight 2

Files that a NUL is among, through the tools that compare them: cmp reads
its two inputs a piece at a time, together, and compares them a byte at a
time by count; diff finds a file binary where its first piece holds a NUL,
as the system's diff does, and then only says whether the two differ.  The
expected output is what busybox's cmp and the system's diff put out for the
same files.

The files are the 256 byte values in order, 128 times over, so that every
piece starts with a NUL: `b1`; `b2`, the same but for a `Z` at offset 20,000,
where `b1` holds a space; and `b3`, the first 20,000 bytes of `b1`.  From a
pipe, the pieces come from a thunk that reads a file a piece at a time, or
hands out the runs it was given, and refuses to answer the whole text.

## the fixtures

### the files, the directories, and a run of an applet with its stdout and stderr

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-bincmp && mkdir -p /tmp/x-cu-bincmp/d1 /tmp/x-cu-bincmp/d2")) (def bp (fn (_ n) (string-append "/tmp/x-cu-bincmp/" n))) (def run2 (fn (_ argv src) (let ((o (file-open-write (bp ".out")))) (do (sys-dup2 1 9) (sys-dup2 2 8) (sys-dup2 o 1) (sys-dup2 o 2) (let ((st (if (null? src) (cu-run argv "") (%cu-dispatch (%cu-find-applet (first argv)) (first argv) (rest argv) src)))) (do (sys-dup2 9 1) (sys-dup2 8 2) (file-close o) (display (string-append (file-read-all (bp ".out")) (string-append "status " (%cu-int->str st)))) (newline))))))) (def pipe-of (fn (_ name) (let ((src (%cu-file-pieces (bp name)))) (fn (_ . how) (if (null? how) (error "asked for the whole input") (src)))))) (def runs-of (fn (_ rs) (let ((left (list rs))) (fn (_ . how) (if (null? how) (error "asked for the whole input") (if (null? (first left)) (pair "" 0) (let ((r (first (first left)))) (do (set-first! left (rest (first left))) r)))))))) (def upto (fn (self i acc) (if (< i 0) acc (self (- i 1) (pair i acc))))) (def all (upto 255 ())) (def put-times (fn (_ fd bs k) (let ((r (%cu-run-bytes bs (length bs)))) (let ((go (fn (self j) (if (= j 0) () (do (file-write-run fd r) (self (- j 1))))))) (go k))))) (def make (fn (_ n parts) (let ((fd (file-open-write (bp n)))) (do (let ((go (fn (self ps) (if (null? ps) () (do (put-times fd (first (first ps)) (rest (first ps))) (self (rest ps))))))) (go parts)) (file-close fd))))) (def head32 (upto 31 ())) (def tail223 (let ((go (fn (self i acc) (if (< i 33) acc (self (- i 1) (pair i acc)))))) (go 255 ()))) (make "b1" (list (pair all 128))) (make "b2" (list (pair all 78) (pair (append head32 (pair 90 tail223)) 1) (pair all 49))) (make "b3" (list (pair all 78) (pair head32 1))) (make "small" (list (pair (list 0 1 2 3 5) 1))) (file-write-all (bp "t1") "a\n") (proc-run (list "/bin/sh" "-c" "cd /tmp/x-cu-bincmp && cp b1 d1/x && cp b2 d2/x && cp b1 d1/only && printf 'a\\n' > d1/t && : > d2/t")) (display (map (fn (_ n) (%cu-stat-get (file-stat-full (bp n)) (lit size))) (list "b1" "b2" "b3" "small"))))
```
---
    (32768 32768 20000 5)

## cmp

### the first difference and its line, every difference, silence, and a bound

```cu
(do (run2 (list "cmp" (bp "b1") (bp "b2")) ()) (run2 (list "cmp" "-l" (bp "b1") (bp "b2")) ()) (run2 (list "cmp" "-s" (bp "b1") (bp "b2")) ()) (run2 (list "cmp" (bp "b1") (bp "b1")) ()) (run2 (list "cmp" "-n" "20000" (bp "b1") (bp "b2")) ()))
```
---
```output
/tmp/x-cu-bincmp/b1 /tmp/x-cu-bincmp/b2 differ: byte 20001, line 80
status 1
20001  40 132
status 1
status 1
status 0
status 0
```

### the input that ends first is said, the first or the second, with and without -l

```cu
(do (run2 (list "cmp" (bp "b3") (bp "b1")) ()) (run2 (list "cmp" (bp "b1") (bp "b3")) ()) (run2 (list "cmp" "-l" (bp "b3") (bp "b2")) ()))
```
---
```output
cmp: EOF on /tmp/x-cu-bincmp/b3
status 1
cmp: EOF on /tmp/x-cu-bincmp/b3
status 1
cmp: EOF on /tmp/x-cu-bincmp/b3
status 1
```

### from a pipe a piece at a time, and pieces that do not line up with the file's

The runs 0 1 2 and 3 4 against a file of 0 1 2 3 5, as the first input and
as the second.

```cu
(do (run2 (list "cmp" "-l" "-" (bp "b2")) (pipe-of "b1")) (run2 (list "cmp" "-" (bp "b1")) (pipe-of "b1")) (run2 (list "cmp" "-l" "-" (bp "small")) (runs-of (list (%cu-run-bytes (list 0 1 2) 3) (%cu-run-bytes (list 3 4) 2)))) (run2 (list "cmp" "-l" (bp "small") "-") (runs-of (list (%cu-run-bytes (list 0 1 2) 3) (%cu-run-bytes (list 3 4) 2)))))
```
---
```output
20001  40 132
status 1
status 0
5   4   5
status 1
5   5   4
status 1
```

## diff

### binary files are only said to differ, or to be the same

```cu
(do (run2 (list "diff" (bp "b1") (bp "b2")) ()) (run2 (list "diff" (bp "b1") (bp "b1")) ()) (run2 (list "diff" "-q" (bp "b1") (bp "b2")) ()) (run2 (list "diff" "-s" (bp "b1") (bp "b1")) ()) (run2 (list "diff" (bp "t1") (bp "b1")) ()))
```
---
```output
Binary files /tmp/x-cu-bincmp/b1 and /tmp/x-cu-bincmp/b2 differ
status 1
status 0
Files /tmp/x-cu-bincmp/b1 and /tmp/x-cu-bincmp/b2 differ
status 1
Files /tmp/x-cu-bincmp/b1 and /tmp/x-cu-bincmp/b1 are identical
status 0
Binary files /tmp/x-cu-bincmp/t1 and /tmp/x-cu-bincmp/b1 differ
status 1
```

### in a directory walk, a binary pair is its own line, and -N reads a missing one as empty

The text pair only takes a line away: the spec runner strips a `> ` it
finds at the head of a line of captured output.

```cu
(do (run2 (list "diff" "-r" (bp "d1") (bp "d2")) ()) (run2 (list "diff" "-rN" (bp "d1") (bp "d2")) ()))
```
---
```output
Only in /tmp/x-cu-bincmp/d1: only
diff -r /tmp/x-cu-bincmp/d1/t /tmp/x-cu-bincmp/d2/t
1d0
< a
Binary files /tmp/x-cu-bincmp/d1/x and /tmp/x-cu-bincmp/d2/x differ
status 1
Binary files /tmp/x-cu-bincmp/d1/only and /tmp/x-cu-bincmp/d2/only differ
diff -rN /tmp/x-cu-bincmp/d1/t /tmp/x-cu-bincmp/d2/t
1d0
< a
Binary files /tmp/x-cu-bincmp/d1/x and /tmp/x-cu-bincmp/d2/x differ
status 1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-bincmp")) (display "clean"))
```
---
    clean
