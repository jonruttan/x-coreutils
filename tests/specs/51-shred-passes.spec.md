# @weight 2

shred's passes are the system's random bytes, read from /dev/urandom a buffer
of up to 64K at a time, and each buffer is fresh, as GNU shred's stream is: no
buffer repeats within a pass, a pass is not zeros, and two files shredded
together are not the same.  The bytes are compared by the system's dd and
cmp, since a string's observable bytes end at its first NUL.

A random pass reads and writes through File's read and write resolved once,
and it and the zeros pass sweep every 512 buffers, so a pass holds what a few
buffers leave rather than one draw for every three bytes.  Each run is made
in a forked child with the allocator's guard armed a bound above the heap it
starts from, as in 47-line-sweeps, and a child that raises leaves with status
3: shred -n 1 over 200,000 bytes, and 128 MB of random bytes and of zeros
written to /dev/null, 2,048 buffers each.  Each bound sits about half again
above what the run holds at its fullest on the release lang.xon declares, and
under what it holds with its sweeps taken out, or, for the random pass,
File's methods looked up on every call.

## the fixtures

### a scratch directory, a file of x's, dd and cmp, and runs under the guard

```cu
(do (def limit! (prim-ref (lit alloc) (lit limit!))) (def w (fn (_ n) (string-append "/tmp/x-cu-sh/" n))) (def sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" (string-append "cd /tmp/x-cu-sh && " cmd))))) (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-sh && mkdir -p /tmp/x-cu-sh")) (def fill (fn (_ n k) (sh (string-concat (list "head -c " (%cu-int->str k) " /dev/zero | tr '\\000' x > " n))))) (def block (fn (_ n i o) (sh (string-concat (list "dd if=" n " of=" o " bs=65536 skip=" (%cu-int->str i) " count=1 2>/dev/null"))))) (def bytes-same? (fn (_ a b) (= 0 (sh (string-concat (list "cmp -s " a " " b)))))) (def nul (file-open-write "/dev/null")) (def under? (fn (_ argv input bound) (= 0 (let ((pid (sys-fork))) (if (= pid 0) (do (let ((nul (file-open-write "/dev/null"))) (do (sys-dup2 nul 1) (sys-dup2 nul 2))) (cu-run argv "2\n1\n") (%cu-heap-collect) (limit! (+ (Heap count) bound)) (cu-run argv input) (sys-exit 0)) (sys-wait pid)))))) (def under-th? (fn (_ th bound) (= 0 (let ((pid (sys-fork))) (if (= pid 0) (guard (_ (sys-exit 3)) (do (th) (%cu-heap-collect) (limit! (+ (Heap count) bound)) (th) (sys-exit 0))) (sys-wait pid)))))) (display "made"))
```
---
    made

## the bytes

### no buffer repeats within a pass: 200,000 bytes, three whole buffers

```cu
(do (fill "f" 200000) (cu-run (list "shred" "-n" "1" (w "f")) "") (block "f" 0 "b0") (block "f" 1 "b1") (block "f" 2 "b2") (display (list (bytes-same? "b0" "b1") (bytes-same? "b1" "b2") (bytes-same? "b0" "b2"))))
```
---
    (#f #f #f)

### a pass is not zeros, and two files shredded together are not the same

```cu
(do (fill "a" 7) (fill "b" 7) (cu-run (list "shred" "-n" "1" (w "a") (w "b")) "") (sh "head -c 4096 /dev/zero > z") (display (list (bytes-same? "a" "z") (bytes-same? "b" "z") (bytes-same? "a" "b"))))
```
---
    (#f #f #f)

## as they go

### shred -n 1 over 200,000 bytes, and 128 MB of random bytes and of zeros to /dev/null

```cu
(do (fill "g" 200000) (display (list (under? (list "shred" "-n" "1" (w "g")) "" 500000) (under-th? (fn (_) (file-write-random nul 134217728)) 1800000) (under-th? (fn (_) (file-write-nuls nul 134217728)) 1800000))))
```
---
    (#t #t #t)

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-sh")) (display "clean"))
```
---
    clean
