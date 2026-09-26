# @weight 2

What the line tools hold at their fullest: the tools that hold every line
before they put any out, and comm, which walks two files together.

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
the tool holds at its fullest on the release lang.xon declares, and under
what it holds unswept: a sweep taken out of any of its loops puts it over.

comm also runs on two files of 4,000 short lines, where each line costs little
to split and the walk is most of what a line leaves.

## the fixtures

### inputs, and a run under the guard

The lines are a number and two words, the numbers out of order and
repeating.  The keyed file holds a distinct number on each line, and the
short file one digit a line, built a hundred at a time.

```cu
(do (def limit! (prim-ref (lit alloc) (lit limit!))) (def mk (fn (self n acc) (if (= n 0) (string-concat acc) (self (- n 1) (pair (%cu-int->str (% (* n 7919) 1000)) (pair " alpha beta\tx\n" acc)))))) (def short (fn (self n acc) (if (= n 0) (string-concat acc) (self (- n 1) (pair (%cu-int->str (% n 10)) (pair "\n" acc)))))) (def block (short 100 ())) (def rep (fn (self n acc) (if (= n 0) (string-concat acc) (self (- n 1) (pair block acc))))) (def kv (fn (self n from acc) (if (= n 0) (string-concat acc) (self (- n 1) from (pair (%cu-int->str (+ from n)) (pair " alpha\n" acc)))))) (def in400 (mk 400 ())) (def in800 (mk 800 ())) (file-write-all "/tmp/x-cu-ls3-k" (kv 400 1000 ())) (file-write-all "/tmp/x-cu-ls3-s" (rep 40 ())) (def under? (fn (_ argv input bound) (= 0 (let ((pid (sys-fork))) (if (= pid 0) (do (let ((nul (file-open-write "/dev/null"))) (do (sys-dup2 nul 1) (sys-dup2 nul 2))) (cu-run argv "2\n1\n") (%cu-heap-collect) (limit! (+ (Heap count) bound)) (cu-run argv input) (sys-exit 0)) (sys-wait pid)))))) (display "made"))
```
---
    made

## every line held

### sort and shuf hold the lines, and put them out a line at a time

```cu
(display (list (under? (list "sort") in400 3600000) (under? (list "shuf") in800 4100000)))
```
---
    (#t #t)

## two files walked together

### comm, on 400 keyed lines and on 4,000 short ones

```cu
(display (list (under? (list "comm" "/tmp/x-cu-ls3-k" "/tmp/x-cu-ls3-k") "" 3000000) (under? (list "comm" "/tmp/x-cu-ls3-s" "/tmp/x-cu-ls3-s") "" 10200000)))
```
---
    (#t #t)

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -f /tmp/x-cu-ls3-k /tmp/x-cu-ls3-s")) (display "clean"))
```
---
    clean
