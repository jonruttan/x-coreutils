# @weight 2

Bytes that a NUL is among, through the tools that cut them up or encode them
for mail: split reads its input a piece at a time and writes each file by
count, and uuencode and uudecode read and write by count, so a NUL goes
through like any other byte.

The file is the 256 byte values in order, 128 times over, so that every
piece starts with a NUL, and it holds 128 lines.  A case compares what came
out with the file, or with what the system's uuencode writes for it, with
cmp.  From a pipe, the pieces come from a thunk that reads the file a piece
at a time and refuses to answer the whole text.

## the fixtures

### the file, a run of an applet with its stdout and stderr, and the sizes of split's files

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-binsp && mkdir -p /tmp/x-cu-binsp")) (def bp (fn (_ n) (string-append "/tmp/x-cu-binsp/" n))) (def run2 (fn (_ argv src) (let ((o (file-open-write (bp ".out")))) (do (sys-dup2 1 9) (sys-dup2 2 8) (sys-dup2 o 1) (sys-dup2 o 2) (let ((st (if (null? src) (cu-run argv "") (%cu-dispatch (%cu-find-applet (first argv)) (first argv) (rest argv) src)))) (do (sys-dup2 9 1) (sys-dup2 8 2) (file-close o) (display (string-append (file-read-all (bp ".out")) (string-append "status " (%cu-int->str st)))) (newline))))))) (def into (fn (_ out argv src) (do (sys-dup2 1 9) (let ((o (file-open-write (bp out)))) (do (sys-dup2 o 1) (if (null? src) (cu-run argv "") (%cu-dispatch (%cu-find-applet (first argv)) (first argv) (rest argv) src)) (sys-dup2 9 1) (file-close o)))))) (def sys (fn (_ cmd) (proc-run (list "/bin/sh" "-c" (string-append "cd /tmp/x-cu-binsp && " cmd))))) (def same (fn (_ a b) (= 0 (proc-run (list "/usr/bin/cmp" "-s" (bp a) (bp b)))))) (def size (fn (_ n) (%cu-stat-get (file-stat-full (bp n)) (lit size)))) (def pipe-of (fn (_ name) (let ((src (%cu-file-pieces (bp name)))) (fn (_ . how) (if (null? how) (error "asked for the whole input") (src)))))) (def upto (fn (self i acc) (if (< i 0) acc (self (- i 1) (pair i acc))))) (def fd (file-open-write (bp "pat"))) (def r (%cu-run-bytes (upto 255 ()) 256)) (let ((go (fn (self k) (if (= k 0) (file-close fd) (do (file-write-run fd r) (self (- k 1))))))) (go 128)) (def sizes (fn (_ stem names) (map (fn (_ n) (size (string-append stem n))) names))) (display (size "pat")))
```
---
    32768

## split

### by bytes and by lines, from the file, and by bytes from a pipe

The files join back into the file with cat.  Their sizes are GNU split's:
each line ends at the newline 10 bytes into a block of 256, and the last
has no newline.

```cu
(do (cu-run (list "split" "-b" "10000" (bp "pat") (bp "b")) "") (sys "cat baa bab bac bad > b-all") (display (list (sizes "b" (list "aa" "ab" "ac" "ad")) (file-exists? (bp "bae")) (same "b-all" "pat"))) (newline) (cu-run (list "split" "-l" "50" (bp "pat") (bp "l")) "") (sys "cat laa lab lac > l-all") (display (list (sizes "l" (list "aa" "ab" "ac")) (file-exists? (bp "lad")) (same "l-all" "pat"))) (newline) (%cu-dispatch %cu-split "split" (list "-b" "5000" "-" (bp "p")) (pipe-of "pat")) (sys "cat paa pab pac pad pae paf pag > p-all") (display (list (sizes "p" (list "aa" "ab" "ac" "ad" "ae" "af" "ag")) (same "p-all" "pat"))))
```
---
```output
((10000 10000 10000 2768) #f #t)
((12555 12800 7413) #f #t)
((5000 5000 5000 5000 5000 5000 2768) #t)
```

### from standard input as the command line hands it over, which moves off fd 3 once

The command line's standard input waits on fd 3 until an applet reads it,
and split's files take fd 3 once it is free -- every other one, since the
next is made before the last is closed.  Files of 7,000 bytes leave the
third open on fd 3 at the end of the first piece.  A forked child puts the
file on fd 3 and runs split through cu-main, which exits with split's status.

```cu
(do (display (let ((pid (sys-fork))) (if (= pid 0) (let ((fd (file-open-read (bp "pat")))) (do (if (= fd 3) () (do (sys-dup2 fd 3) (sys-close fd))) (cu-main (list "x" "split" "-b" "7000" "-" (bp "c"))))) (sys-wait pid)))) (newline) (sys "cat caa cab cac cad cae > c-all") (display (list (sizes "c" (list "aa" "ab" "ac" "ad" "ae")) (same "c-all" "pat"))))
```
---
```output
0
((7000 7000 7000 7000 4768) #t)
```

### past the last suffix, and a size of 0, as GNU's split says them

Thirty-three files of 1,000 bytes are wanted and one letter spells 26.

```cu
(do (run2 (list "split" "-a" "1" "-b" "1000" (bp "pat") (bp "a")) ()) (display (list (file-exists? (bp "az")) (size "az"))) (newline) (run2 (list "split" "-b" "0" (bp "pat") (bp "z")) ()))
```
---
```output
split: output file suffixes exhausted
status 1
(#t 1000)
split: invalid number of bytes: '0'
status 1
```

## uuencode and uudecode

### both encodings as the system's uuencode writes them, from the file and from a pipe

The begin line names the file's permissions: a copy of the file with mode 750
as well.

```cu
(do (into "u1" (list "uuencode" (bp "pat") "name") ()) (sys "/usr/bin/uuencode pat name > u1s") (into "u2" (list "uuencode" "-m" "name") (pipe-of "pat")) (sys "/usr/bin/uuencode -m pat name > u2s") (sys "cp pat p750 && chmod 750 p750") (into "u3" (list "uuencode" (bp "p750") "name") ()) (sys "/usr/bin/uuencode p750 name > u3s") (display (list (same "u1" "u1s") (same "u2" "u2s") (same "u3" "u3s"))))
```
---
    (#t #t #t)

### decoded, both come back as they were, to a file and to stdout

```cu
(do (cu-run (list "uudecode" "-o" (bp "d1") (bp "u1s")) "") (cu-run (list "uudecode" "-o" (bp "d2") (bp "u2s")) "") (into "d3" (list "uudecode" (bp "u1s")) ()) (display (list (same "d1" "pat") (same "d2" "pat") (same "d3" "pat"))))
```
---
    (#t #t #t)

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-binsp")) (display "clean"))
```
---
    clean
