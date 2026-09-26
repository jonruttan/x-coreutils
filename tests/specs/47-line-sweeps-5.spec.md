# @weight 4

What the line tools hold at their fullest: the passes sort makes besides its
merge, and the loops that take a cheap step, each run on its own.

Every step of a loop leaves an environment, and nothing is collected unless a
tool asks, so a tool that walked its input without sweeping held everything
it had ever made: at thousands of objects a line, a few thousand lines
exhausted the machine.  The loops that walk an input sweep as they go, and a
tool that made its whole output before writing any puts it out a line at a
time instead, since joining it into one string costs thousands of objects a
line where no sweep reaches.

Each run is made in a forked child, with the allocator's guard armed a bound
above the heap the child starts from: a run whose live heap ever grows past
it is stopped, and the child's status says so.  That is the peak, which is
what exhausts a machine -- a count taken after a run would miss a loop whose
leavings a later sweep clears.  Each bound sits about half again above what
the tool holds at its fullest here, and several times under what it held
unswept: a sweep taken out of any of its loops puts it over.

A cheap step -- a comparison, a copy, a line written -- leaves little, so a
loop of them sweeps less often, and shows what it holds only over thousands of
steps.  Those loops run here on their own, since through a tool most of the
time would go to the tool's other work: the merge, on two lists of 20,000
lines under a comparison that costs nothing, deeper than a merge recursing a
line at a time could go before its child died of it; the line and field
printers on 4,000 lines; the -z reader on 2,000 fields; and shuf's range and
its copies into a vector and out, on 4,000 items.

## the fixtures

### inputs, and a run under the guard

The keyed files hold a distinct number on each line, in order, built a
hundred at a time: 1,000 lines for -u and 2,000 for -c.  The -z file holds the
2,000 numbers, each ended by a NUL.  The lists to merge are one digit a line,
all ones and all zeros; the items are the numbers 1 to 4,000, and the vector
holds them.

```cu
(do (def limit! (prim-ref (lit alloc) (lit limit!))) (def kv (fn (self n from acc) (if (= n 0) (string-concat acc) (self (- n 1) from (pair (%cu-int->str (+ from n)) (pair " alpha\n" acc)))))) (def kblocks (fn (self k acc) (if (= k 0) (string-concat acc) (self (- k 1) (pair (kv 100 (+ 10000 (* 100 (- k 1))) ()) acc))))) (def k2 (kblocks 20 ())) (file-write-all "/tmp/x-cu-ls5-k" (kblocks 10 ())) (file-write-all "/tmp/x-cu-ls5-c" k2) (def put-z (fn (self fd ls i) (if (null? ls) () (do (%cu-sweep-at i %cu-sweep-steps) (file-write-field fd (first ls) 0) (self fd (rest ls) (+ i 1)))))) (let ((fd (file-open-write "/tmp/x-cu-ls5-z"))) (do (put-z fd (%cu-lines k2) 0) (file-close fd))) (def same (fn (self s k acc) (if (= k 0) acc (self s (- k 1) (pair s acc))))) (def ones (same "1" 20000 ())) (def zeros (same "0" 20000 ())) (def cheap< (fn (_ a b) (< (byte-at a 0) (byte-at b 0)))) (def items (%cu-shuf-range "1-4000")) (def v (%cu-list->vec items 4000)) (def under? (fn (_ argv input bound) (= 0 (let ((pid (sys-fork))) (if (= pid 0) (do (let ((nul (file-open-write "/dev/null"))) (do (sys-dup2 nul 1) (sys-dup2 nul 2))) (cu-run argv "2\n1\n") (%cu-heap-collect) (limit! (+ (Heap count) bound)) (cu-run argv input) (sys-exit 0)) (sys-wait pid)))))) (def under-th? (fn (_ th bound) (= 0 (let ((pid (sys-fork))) (if (= pid 0) (do (let ((nul (file-open-write "/dev/null"))) (do (sys-dup2 nul 1) (sys-dup2 nul 2))) (%cu-heap-collect) (limit! (+ (Heap count) bound)) (th) (sys-exit 0)) (sys-wait pid)))))) (display "made"))
```
---
    made

## sort's other passes

### sort -u on 1,000 lines in order, and -c on 2,000

```cu
(display (list (under? (list "sort" "-u" "/tmp/x-cu-ls5-k") "" 6300000) (under? (list "sort" "-c" "/tmp/x-cu-ls5-c") "" 8100000)))
```
---
    (#t #t)

## the loops on their own

### the merge of two lists of 20,000 lines

```cu
(display (list (under-th? (fn (_) (%cu-merge ones zeros cheap< ())) 1200000)))
```
---
    (#t)

### the line printer and the field printer, on 4,000 lines

```cu
(display (list (under-th? (fn (_) (%cu-print-lines-to (file-open-write "/dev/null") items)) 2400000) (under-th? (fn (_) (%cu-print-fields-to (file-open-write "/dev/null") items 0)) 3500000)))
```
---
    (#t #t)

### the -z reader, on 2,000 fields

```cu
(display (list (under-th? (fn (_) (%cu-fd-fields (file-open-read "/tmp/x-cu-ls5-z") 0 "")) 1100000)))
```
---
    (#t)

### shuf's range, and its copies into a vector and out, on 4,000 items

```cu
(display (list (under-th? (fn (_) (%cu-shuf-range "1-4000")) 2600000) (under-th? (fn (_) (%cu-list->vec items 4000)) 900000) (under-th? (fn (_) (%cu-vec->list v 4000)) 2000000)))
```
---
    (#t #t #t)

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -f /tmp/x-cu-ls5-k /tmp/x-cu-ls5-c /tmp/x-cu-ls5-z")) (display "clean"))
```
---
    clean
