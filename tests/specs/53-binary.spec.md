# @weight 2

Bytes that a NUL is among, through the tools that pass them on: cat, tee,
head, tail, wc and tr read each piece of their input by its count, NULs and
all, and write it by its count.  A string's own length stops at its first
NUL, so a piece is a run -- its bytes and how many there are -- and only the
tools that work on lines take a piece as text.

The files are 40,000 random bytes, and 16,384 bytes of `a` with a NUL and a
line after them, so that the second piece of the second starts with a NUL.
A case compares what an applet wrote with what the system's own tool writes
for the same bytes, with cmp.  From a pipe, the pieces come from a thunk
that reads the file a piece at a time and refuses to answer the whole text.

## the fixtures

### the files, a run of an applet into a file, and a pipe of a file's pieces

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-bin && mkdir -p /tmp/x-cu-bin && cd /tmp/x-cu-bin && head -c 40000 /dev/urandom > rnd && head -c 16384 /dev/zero | tr '\\000' a > edge && printf '\\000after\\n' >> edge")) (def bp (fn (_ n) (string-append "/tmp/x-cu-bin/" n))) (def into (fn (_ out argv src) (do (sys-dup2 1 9) (let ((o (file-open-write (bp out)))) (do (sys-dup2 o 1) (if (null? src) (cu-run argv "") (%cu-dispatch (%cu-find-applet (first argv)) (first argv) (rest argv) src)) (sys-dup2 9 1) (file-close o)))))) (def sys (fn (_ out cmd) (proc-run (list "/bin/sh" "-c" (string-concat (list "cd /tmp/x-cu-bin && " cmd " > " out)))))) (def same (fn (_ a b) (= 0 (proc-run (list "/usr/bin/cmp" "-s" (bp a) (bp b)))))) (def pipe-of (fn (_ name) (let ((src (%cu-file-pieces (bp name)))) (fn (_ . how) (if (null? how) (error "asked for the whole input") (src)))))) (display (list (%cu-stat-get (file-stat-full (bp "rnd")) (lit size)) (%cu-stat-get (file-stat-full (bp "edge")) (lit size)))))
```
---
    (40000 16391)

## a file's bytes

### cat puts every byte out, of random bytes and of a second piece that starts with a NUL

```cu
(do (into "c1" (list "cat" (bp "rnd")) ()) (into "c2" (list "cat" (bp "edge")) ()) (display (list (same "c1" "rnd") (same "c2" "edge"))))
```
---
    (#t #t)

### head and tail take their bytes and lines as the system's tools do

The first and last 20,000 bytes and 40 lines, and from the 40th line and the
20,000th byte on.

```cu
(do (into "h1" (list "head" "-c" "20000" (bp "rnd")) ()) (sys "g1" "head -c 20000 rnd") (into "h2" (list "head" "-n" "40" (bp "rnd")) ()) (sys "g2" "head -n 40 rnd") (into "t1" (list "tail" "-c" "20000" (bp "rnd")) ()) (sys "u1" "tail -c 20000 rnd") (into "t2" (list "tail" "-n" "40" (bp "rnd")) ()) (sys "u2" "tail -n 40 rnd") (into "t3" (list "tail" "-n" "+40" (bp "rnd")) ()) (sys "u3" "tail -n +40 rnd") (into "t4" (list "tail" "-c" "+20000" (bp "rnd")) ()) (sys "u4" "tail -c +20000 rnd") (display (list (same "h1" "g1") (same "h2" "g2") (same "t1" "u1") (same "t2" "u2") (same "t3" "u3") (same "t4" "u4"))))
```
---
    (#t #t #t #t #t #t)

## a pipe's bytes

### cat, head, tail and tee, a piece at a time

tail keeps the pieces that hold the last lines or bytes; tee writes each
piece to its file as well.

```cu
(do (into "p1" (list "cat") (pipe-of "rnd")) (into "p2" (list "head" "-c" "20000") (pipe-of "rnd")) (into "p3" (list "tail" "-n" "40") (pipe-of "rnd")) (into "p4" (list "tail" "-c" "20000") (pipe-of "rnd")) (into "p5" (list "tee" (bp "p6")) (pipe-of "rnd")) (display (list (same "p1" "rnd") (same "p2" "g1") (same "p3" "u2") (same "p4" "u1") (same "p5" "rnd") (same "p6" "rnd"))))
```
---
    (#t #t #t #t #t #t)

### wc counts every byte and the newlines among them; cat -v shows a NUL, and tr reads one

```cu
(do (into "w1" (list "wc" "-c" (bp "rnd")) ()) (into "w2" (list "wc" "-l" (bp "rnd")) ()) (sys "w3" "wc -l < rnd") (display (list (%cu-num-prefix (file-read-all (bp "w1"))) (= (%cu-num-prefix (file-read-all (bp "w2"))) (%cu-num-prefix (file-read-all (bp "w3")))))) (newline) (%cu-dispatch %cu-cat "cat" (list "-v") (let ((given (list #f))) (fn (_ . how) (if (first given) "" (do (set-first! given #t) (%cu-run-bytes (list 97 0 98 10) 4)))))) (%cu-dispatch %cu-tr "tr" (list "\\000" "x") (let ((given (list #f))) (fn (_ . how) (if (first given) "" (do (set-first! given #t) (%cu-run-bytes (list 97 0 98 10) 4)))))) (display ""))
```
---
```output
(40000 #t)
a^@b
axb
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-bin")) (display "clean"))
```
---
    clean
