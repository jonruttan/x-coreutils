# @weight 2

Bytes that a NUL is among, through the tools that read them to show,
encode or convert them: od, base64, dd, dos2unix and unix2dos read each
piece of their input by its count, NULs and all, and what they carry from one
piece to the next -- od's part of a line, base64's bytes of a step, the byte
swab holds for its pair -- is a run too.

The files are 40,001 random bytes, and the 256 byte values in order, 128
times over, so that every piece of the second starts with a NUL.  A case
compares what an applet wrote with what the system's own tool writes for the
same bytes, with cmp, where the system's tool writes what GNU's does: its
base64 and its dd do, its od does not, and it has no dos2unix.  For those
the case holds what GNU's od and dos2unix put out, or a file built from the
byte values.  From a pipe, the pieces come from a thunk that reads the file a
piece at a time and refuses to answer the whole text.

## the fixtures

### the files, what dos2unix and unix2dos make of the second, and the helpers

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-bin2 && mkdir -p /tmp/x-cu-bin2 && head -c 40001 /dev/urandom > /tmp/x-cu-bin2/rnd")) (def bp (fn (_ n) (string-append "/tmp/x-cu-bin2/" n))) (def into (fn (_ out argv src) (do (sys-dup2 1 9) (let ((o (file-open-write (bp out)))) (do (sys-dup2 o 1) (if (null? src) (cu-run argv "") (%cu-dispatch (%cu-find-applet (first argv)) (first argv) (rest argv) src)) (sys-dup2 9 1) (file-close o)))))) (def sys (fn (_ out cmd) (proc-run (list "/bin/sh" "-c" (string-concat (list "cd /tmp/x-cu-bin2 && " cmd " > " out)))))) (def same (fn (_ a b) (= 0 (proc-run (list "/usr/bin/cmp" "-s" (bp a) (bp b)))))) (def size (fn (_ n) (%cu-stat-get (file-stat-full (bp n)) (lit size)))) (def pipe-of (fn (_ name) (let ((src (%cu-file-pieces (bp name)))) (fn (_ . how) (if (null? how) (error "asked for the whole input") (src)))))) (def runs-of (fn (_ rs) (let ((left (list rs))) (fn (_ . how) (if (null? how) (error "asked for the whole input") (if (null? (first left)) (pair "" 0) (let ((r (first (first left)))) (do (set-first! left (rest (first left))) r)))))))) (def bytes-of (fn (_ n) (let ((fd (file-open-read (bp n)))) (let ((r (file-read-run fd 64))) (do (file-close fd) (let ((go (fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (+ 0 (byte-at (first r) i)) acc)))))) (go (- (rest r) 1) ()))))))) (def upto (fn (self i acc) (if (< i 0) acc (self (- i 1) (pair i acc))))) (def times (fn (_ n bs k) (let ((fd (file-open-write (bp n))) (r (%cu-run-bytes bs (length bs)))) (let ((go (fn (self j) (if (= j 0) (file-close fd) (do (file-write-run fd r) (self (- j 1))))))) (go k))))) (def crlf (fn (self bs) (match ((null? bs) ()) ((= (first bs) 13) (self (rest bs))) ((= (first bs) 10) (pair 13 (pair 10 (self (rest bs))))) (#t (pair (first bs) (self (rest bs))))))) (def all (upto 255 ())) (times "pat" all 128) (times "d2u" (filter (fn (_ b) (not (= b 13))) all) 128) (times "u2d" (crlf all) 128) (display (list (size "rnd") (size "pat") (size "d2u") (size "u2d"))))
```
---
    (40001 32768 32640 32768)

## od

### the lines about the start of the second piece, a NUL, in hex, as characters and as words

```cu
(do (into "o1" (list "od" "-An" "-tx1" "-j" "16376" "-N" "32" (bp "pat")) ()) (into "o2" (list "od" "-c" "-j" "16380" "-N" "16" (bp "pat")) ()) (into "o3" (list "od" "-tx2" "-j" "16382" "-N" "6" (bp "pat")) ()) (display (string-concat (list (file-read-all (bp "o1")) (file-read-all (bp "o2")) (file-read-all (bp "o3"))))))
```
---
```output
 f8 f9 fa fb fc fd fe ff 00 01 02 03 04 05 06 07
 08 09 0a 0b 0c 0d 0e 0f 10 11 12 13 14 15 16 17
0037774 374 375 376 377  \0 001 002 003 004 005 006  \a  \b  \t  \n  \v
0040014
0037776 fffe 0100 0302
0040004
```

### all of it, from the file in hex and from a pipe as characters, by cksum

```cu
(do (into "o4" (list "od" "-An" "-tx1" (bp "pat")) ()) (into "o5" (list "od" "-c") (pipe-of "pat")) (sys "o4s" "cksum < o4") (sys "o5s" "cksum < o5") (display (string-append (file-read-all (bp "o4s")) (file-read-all (bp "o5s")))))
```
---
```output
2002313976 100352
3294058245 147464
```

## base64

### random bytes encoded, wrapped from the file and unwrapped from a pipe, as the system's base64 encodes them

```cu
(do (into "b1" (list "base64" (bp "rnd")) ()) (sys "b1s" "/usr/bin/base64 -b 76 -i rnd") (into "b2" (list "base64" "-w" "0") (pipe-of "rnd")) (sys "b2s" "/usr/bin/base64 -i rnd | tr -d '\\n'") (display (list (same "b1" "b1s") (same "b2" "b2s"))))
```
---
    (#t #t)

### the bytes a piece leaves for the next step, NULs among them

Three pieces: a NUL; a NUL and `A`; a NUL.

```cu
(do (into "b4" (list "base64") (runs-of (list (%cu-run-bytes (list 0) 1) (%cu-run-bytes (list 0 65) 2) (%cu-run-bytes (list 0) 1)))) (display (file-read-all (bp "b4"))))
```
---
    AABBAA==

### decoded, they come back as they were; a NUL in the input is not base64

What comes before the NUL is put out, and the status is 1.

```cu
(do (into "b3" (list "base64" "-d" (bp "b1s")) ()) (display (list (same "b3" "rnd"))) (newline) (display (%cu-dispatch %cu-base64 "base64" (list "-d") (runs-of (list (%cu-run-bytes (list 81 85 74 68 0 82 69 86 71) 9))))))
```
---
```output
(#t)
ABC1
```

## dd

### blocks, skip and count, swab and ucase, as the system's dd copies them, and from a pipe

The random bytes are an odd number, so swab ends on a byte with no pair.
ucase raises a to z and nothing else, as the system's dd does in the C
locale; in a UTF-8 one it raises bytes past 127 as well, as Latin-1.

```cu
(do (def inf (string-append "if=" (bp "rnd"))) (into "d1" (list "dd" inf "status=none") ()) (into "d2" (list "dd" inf "bs=1000" "skip=3" "count=20" "status=none") ()) (sys "d2s" "/bin/dd if=rnd bs=1000 skip=3 count=20 2>/dev/null") (into "d3" (list "dd" inf "conv=swab" "status=none") ()) (sys "d3s" "/bin/dd if=rnd conv=swab 2>/dev/null") (into "d4" (list "dd" inf "conv=ucase" "status=none") ()) (sys "d4s" "LC_ALL=C /bin/dd if=rnd conv=ucase 2>/dev/null") (into "d5" (list "dd" "bs=512" "status=none") (pipe-of "rnd")) (cu-run (list "dd" inf (string-append "of=" (bp "d6")) "status=none") "") (display (list (same "d1" "rnd") (same "d2" "d2s") (same "d3" "d3s") (same "d4" "d4s") (same "d5" "rnd") (same "d6" "rnd"))))
```
---
    (#t #t #t #t #t #t)

### swab holds a piece's odd byte, a NUL among them, for its pair in the next

Two pieces of three bytes: 0 1 2, then 3 4 5.

```cu
(do (into "d7" (list "dd" "conv=swab" "status=none") (runs-of (list (%cu-run-bytes (list 0 1 2) 3) (%cu-run-bytes (list 3 4 5) 3)))) (display (bytes-of "d7")))
```
---
    (1 0 3 2 5 4)

## dos2unix and unix2dos

### every carriage return out, or one before each newline, from a pipe and in place

```cu
(do (into "u1" (list "dos2unix") (pipe-of "pat")) (into "u2" (list "unix2dos") (pipe-of "pat")) (proc-run (list "/bin/sh" "-c" "cd /tmp/x-cu-bin2 && cp pat u3 && cp pat u4")) (cu-run (list "dos2unix" (bp "u3")) "") (cu-run (list "unix2dos" (bp "u4")) "") (display (list (same "u1" "d2u") (same "u2" "u2d") (same "u3" "d2u") (same "u4" "u2d"))))
```
---
    (#t #t #t #t)

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-bin2")) (display "clean"))
```
---
    clean
