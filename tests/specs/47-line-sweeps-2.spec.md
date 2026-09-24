# @weight 2

What the line tools hold at their fullest: the tools that make each line as
they put it out.

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

paste -s and rev also run on 8,000 short lines, where each line costs little
to split or to make, and putting it out is most of what a line leaves.

## the fixtures

### inputs, and a run under the guard

The lines are a number and two words, the numbers out of order and
repeating; the short lines are one digit each, built a hundred at a time.

```cu
(do (def limit! (prim-ref (lit alloc) (lit limit!))) (def mk (fn (self n acc) (if (= n 0) (string-concat acc) (self (- n 1) (pair (%cu-int->str (% (* n 7919) 1000)) (pair " alpha beta\tx\n" acc)))))) (def short (fn (self n acc) (if (= n 0) (string-concat acc) (self (- n 1) (pair (%cu-int->str (% n 10)) (pair "\n" acc)))))) (def block (short 100 ())) (def rep (fn (self n acc) (if (= n 0) (string-concat acc) (self (- n 1) (pair block acc))))) (def in800 (mk 800 ())) (def short8000 (rep 80 ())) (def under? (fn (_ argv input bound) (= 0 (let ((pid (sys-fork))) (if (= pid 0) (do (let ((nul (file-open-write "/dev/null"))) (do (sys-dup2 nul 1) (sys-dup2 nul 2))) (cu-run argv "2\n1\n") (%cu-heap-collect) (limit! (+ (Heap count) bound)) (cu-run argv input) (sys-exit 0)) (sys-wait pid)))))) (display "made"))
```
---
    made

## a line made at a time

### each line made as it is put out, on 800 lines

```cu
(display (list (under? (list "cut" "-d" " " "-f" "2") in800 5500000) (under? (list "rev") in800 3000000) (under? (list "fold" "-w" "20") in800 5500000) (under? (list "expand") in800 6000000) (under? (list "paste" "-" "-") in800 7000000) (under? (list "paste" "-s" "-") in800 3000000)))
```
---
    (#t #t #t #t #t #t)

### and paste -s and rev on 8,000 short lines

```cu
(display (list (under? (list "paste" "-s" "-") short8000 5500000) (under? (list "rev") short8000 5500000)))
```
---
    (#t #t)
