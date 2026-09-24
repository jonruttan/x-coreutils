# @weight 2

What the byte-stream tools hold at their fullest: the tools that walk their
input a byte at a time -- wc, sum, cksum, tr -- and od, which walks it a line
of sixteen bytes at a time.

Every step of a loop leaves an environment, and nothing is collected unless a
tool asks, so a tool that walked its input without sweeping held everything
it had ever made: at hundreds to thousands of objects a byte, an input of a
few hundred kilobytes took gigabytes.  The walks sweep as they go -- every
2,048 bytes, or every 512 where a byte costs a few thousand objects -- and tr
puts its output out in runs of 4,096 bytes rather than holding it whole.

Each run is made in a forked child, with the allocator's guard armed a bound
above the heap it starts from, as in 47-line-sweeps: a run whose live heap
ever grows past it is stopped, and the child's status says so.  Each bound
sits about half again above what the tool holds at its fullest here, and
several times under what an unswept walk leaves over the same input: the
walks whose bytes cost the least run on 15,997 bytes, the dearer ones on
3,995.  tr's runs are counted in a child that counts the writes it makes.

## the fixtures

### inputs, and a run under the guard

The lines are a number and two words: 941 of them are 15,997 bytes, 470 are
7,990, and 235 are 3,995.

```cu
(do (def limit! (prim-ref (lit alloc) (lit limit!))) (def mk (fn (self n acc) (if (= n 0) (string-concat acc) (self (- n 1) (pair (%cu-int->str (+ 100 (% (* n 7919) 900))) (pair " alpha beta\tx\n" acc)))))) (def in16k (mk 941 ())) (def in8k (mk 470 ())) (def in4k (mk 235 ())) (def under? (fn (_ argv input bound) (= 0 (let ((pid (sys-fork))) (if (= pid 0) (do (let ((nul (file-open-write "/dev/null"))) (do (sys-dup2 nul 1) (sys-dup2 nul 2))) (cu-run argv "2\n1\n") (%cu-heap-collect) (limit! (+ (Heap count) bound)) (cu-run argv input) (sys-exit 0)) (sys-wait pid)))))) (display (list (byte-len in16k) (byte-len in8k) (byte-len in4k))))
```
---
    (15997 7990 3995)

## a byte at a time

### wc, sum and sum -s on 15,997 bytes

```cu
(display (list (under? (list "wc") in16k 3200000) (under? (list "sum") in16k 3200000) (under? (list "sum" "-s") in16k 2300000)))
```
---
    (#t #t #t)

### cksum and tr on 3,995 bytes

```cu
(display (list (under? (list "cksum") in4k 2400000) (under? (list "tr" "a-z" "A-Z") in4k 4400000)))
```
---
    (#t #t)

### the writes tr makes of 7,990 bytes: a run of 4,096, and the rest

```cu
(display (let ((pid (sys-fork))) (if (= pid 0) (let ((runs (list 0)) (put file-write-run)) (do (let ((nul (file-open-write "/dev/null"))) (do (sys-dup2 nul 1) (sys-dup2 nul 2))) (set! file-write-run (fn (_ fd r) (do (set-first! runs (+ (first runs) 1)) (put fd r)))) (cu-run (list "tr" "a-z" "A-Z") in8k) (sys-exit (first runs)))) (sys-wait pid))))
```
---
    2

## a line of sixteen bytes at a time

### od -An -tx1 on 3,995 bytes

```cu
(display (list (under? (list "od" "-An" "-tx1") in4k 4200000)))
```
---
    (#t)
