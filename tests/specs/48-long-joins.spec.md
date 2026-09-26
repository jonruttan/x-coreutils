# @weight 5

Joining strings.  string-concat hands its list to the platform's concat,
which loops over it, so a list of any length joins; a piece that is not a
string is a type error rather than a read of whatever it points at.

cat's renderings join the most -- a piece for every byte -- so they run here
on a long text: every byte but the newline, on each of eighty lines, 20,400
bytes.  The lengths and the slices are GNU cat's.  The text goes to the
renderer in pieces of 4,096 bytes, and the renderer sweeps as it goes,
counting its bytes across pieces, so what a rendering holds is bounded by
the bytes between sweeps: a run is made in a forked child with the
allocator's guard armed a bound above the heap it starts from, as in
47-line-sweeps, and the bound sits about half again above what cat holds.

## string-concat

### twenty thousand pieces

```cu
(display (byte-len (string-concat (let ((go (fn (self k acc) (if (= k 0) acc (self (- k 1) (pair "abcdefgh" acc)))))) (go 20000 ())))))
```
---
    160000

### a piece that is not a string

```cu
(display (guard (e (list (Err tag e) (e msg))) (string-concat (list "a" 5 "b"))))
```
---
    (type string-concat: not a string)

## cat's renderings of 20,400 bytes

### the text, and a run with its output kept

```cu
(do (def limit! (prim-ref (lit alloc) (lit limit!))) (def line (bytes->str (append (let ((go (fn (self b acc) (if (= b 0) acc (self (- b 1) (if (= b 10) acc (pair b acc))))))) (go 255 ())) (list 10)))) (def all80 (string-concat (let ((go (fn (self k acc) (if (= k 0) acc (self (- k 1) (pair line acc)))))) (go 80 ())))) (def out-of (fn (_ argv) (do (let ((pid (sys-fork))) (if (= pid 0) (do (let ((fd (file-open-write "/tmp/x-cu-lj-out"))) (do (sys-dup2 fd 1) (%cu-heap-collect) (limit! (+ (Heap count) 60000000)) (cu-run argv all80))) (sys-exit 0)) (sys-wait pid))) (file-read-all "/tmp/x-cu-lj-out")))) (def under? (fn (_ argv input bound) (= 0 (let ((pid (sys-fork))) (if (= pid 0) (do (let ((nul (file-open-write "/dev/null"))) (do (sys-dup2 nul 1) (sys-dup2 nul 2))) (cu-run argv "2\n1\n") (%cu-heap-collect) (limit! (+ (Heap count) bound)) (cu-run argv input) (sys-exit 0)) (sys-wait pid)))))) (display (byte-len all80)))
```
---
    20400

### the length of each of -v, -A, -e, -t and -vn

```cu
(do (def outs (map (fn (_ o) (out-of (list "cat" o))) (list "-v" "-A" "-e" "-t" "-vn"))) (display (map byte-len outs)))
```
---
    (45920 46080 46000 46000 46480)

### the first 64 bytes of -A's, and the 64 before its last newline

```cu
(display (let ((a (first (rest outs)))) (string-append (substring a 0 64) "\n" (substring a (- (byte-len a) 65) (- (byte-len a) 1)))))
```
---
```output
^A^B^C^D^E^F^G^H^I^K^L^M^N^O^P^Q^R^S^T^U^V^W^X^Y^Z^[^\^]^^^_ !"#
-kM-lM-mM-nM-oM-pM-qM-rM-sM-tM-uM-vM-wM-xM-yM-zM-{M-|M-}M-~M-^?$
```

### the pieces the text is rendered in

```cu
(display (map byte-len (%cat-number all80 (%cu-opts "cat" (list "-v")))))
```
---
    (4096 4096 4096 4096 4016)

### what -A, -v and -vn hold at their fullest

```cu
(display (list (under? (list "cat" "-A") all80 5000000) (under? (list "cat" "-v") all80 5000000) (under? (list "cat" "-vn") all80 5000000)))
```
---
    (#t #t #t)

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -f /tmp/x-cu-lj-out")) (display "clean"))
```
---
    clean
