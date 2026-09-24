# @weight 2

What the line tools hold at their fullest: join, which walks two files
together and makes each line it puts out from both.

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

join is walked three ways, since two of its loops sweep: over keys that match,
over keys that never do, and over one key on every line, which pairs each line
with every other.

## the fixtures

### inputs, and a run under the guard

The keyed files hold a distinct number on each line, one from 1001 and one
from 2001, and the last one number on all twenty of its lines.

```cu
(do (def limit! (prim-ref (lit alloc) (lit limit!))) (def kv (fn (self n from acc) (if (= n 0) (string-concat acc) (self (- n 1) from (pair (%cu-int->str (+ from n)) (pair " alpha\n" acc)))))) (def same (fn (self n acc) (if (= n 0) (string-concat acc) (self (- n 1) (pair "7 alpha\n" acc))))) (file-write-all "/tmp/x-cu-ls4-k" (kv 400 1000 ())) (file-write-all "/tmp/x-cu-ls4-d" (kv 400 2000 ())) (file-write-all "/tmp/x-cu-ls4-r" (same 20 ())) (def under? (fn (_ argv input bound) (= 0 (let ((pid (sys-fork))) (if (= pid 0) (do (let ((nul (file-open-write "/dev/null"))) (do (sys-dup2 nul 1) (sys-dup2 nul 2))) (cu-run argv "2\n1\n") (%cu-heap-collect) (limit! (+ (Heap count) bound)) (cu-run argv input) (sys-exit 0)) (sys-wait pid)))))) (display "made"))
```
---
    made

## two files walked together

### join over keys that match, that never do, and that are all one

```cu
(display (list (under? (list "join" "/tmp/x-cu-ls4-k" "/tmp/x-cu-ls4-k") "" 9000000) (under? (list "join" "/tmp/x-cu-ls4-k" "/tmp/x-cu-ls4-d") "" 3500000) (under? (list "join" "/tmp/x-cu-ls4-r" "/tmp/x-cu-ls4-r") "" 10000000)))
```
---
    (#t #t #t)

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -f /tmp/x-cu-ls4-k /tmp/x-cu-ls4-d /tmp/x-cu-ls4-r")) (display "clean"))
```
---
    clean
