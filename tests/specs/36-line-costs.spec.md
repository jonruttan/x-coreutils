# @weight 2

What the line tools allocate as their input grows.  Nothing is collected
while an applet runs, so the input's length multiplies whatever a line
costs: at tens of thousands of objects a line, a few thousand lines exhaust
the machine.  An option read costs thousands of objects, so a tool reads its
options once per run, never once per line or per comparison.  Each case
asks whether a tool stays under a bound set well above what it costs and
well below what it cost when it read its options per line: the bounds catch
a return to that, not a single stray read.

Each count is the (Heap count) growth over a warm run, with the tool's
output sent to /dev/null.  The per-line cases take the difference between
1000 lines and 100, so what a tool costs once per run drops out.

## the fixtures

### inputs of distinct lines, and a counter

The lines are the numbers from N down to 1, one to a line.

```cu
(do (def mkn (fn (self n acc) (if (= n 0) acc (self (- n 1) (string-append acc (string-append (%cu-int->str n) "\n")))))) (def in100 (mkn 100 "")) (def in1000 (mkn 1000 "")) (def cost (fn (_ argv input) (do (sys-dup2 1 9) (let ((nul (file-open-write "/dev/null"))) (do (sys-dup2 nul 1) (cu-run argv "2\n1\n") (def h0 (Heap count)) (cu-run argv input) (def h1 (Heap count)) (sys-dup2 9 1) (file-close nul) (- h1 h0)))))) (def per-900 (fn (_ argv) (- (cost argv in1000) (cost argv in100)))) (display "made"))
```
---
    made

## per line

### uniq costs under 15,000 objects a line

```cu
(display (< (per-900 (list "uniq")) (* 900 15000)))
```
---
    #t

## per sort

### sort orders 100 lines in under 10,000,000 objects

```cu
(display (< (cost (list "sort") in100) 10000000))
```
---
    #t

### and under 20,000,000 by number

```cu
(display (< (cost (list "sort" "-n") in100) 20000000))
```
---
    #t
