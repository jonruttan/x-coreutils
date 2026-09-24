# @weight 2

What the line tools allocate as their input grows.  The sweeps that clear it
as a tool goes (47-line-sweeps) are turned off here, so a count is what a
tool allocates rather than what it keeps: the input's length times whatever
a line costs, which is what the sweeps have to clear, and the time a tool
takes.  An option read costs thousands of objects, so a tool reads its
options once per run, never once per line or per comparison.  Each case
asks whether a tool stays under a bound set well above what it costs and
well below what it cost when it read its options per line, or padded a
number a space at a time: the bounds catch a return to that, not a single
stray read.

Each count is the (Heap count) growth over a warm run, with the tool's
output sent to /dev/null.  The per-line cases take the difference between
1000 lines and 100, so what a tool costs once per run drops out.

## the fixtures

### inputs of distinct lines, a counter, and the sweeps turned off

The lines are the numbers from N down to 1, one to a line.

```cu
(do (set-first! %cu-sweeps-cell #f) (def mkn (fn (self n acc) (if (= n 0) acc (self (- n 1) (string-append acc (string-append (%cu-int->str n) "\n")))))) (def in100 (mkn 100 "")) (def in1000 (mkn 1000 "")) (def cost (fn (_ argv input) (do (sys-dup2 1 9) (let ((nul (file-open-write "/dev/null"))) (do (sys-dup2 nul 1) (cu-run argv "2\n1\n") (def h0 (Heap count)) (cu-run argv input) (def h1 (Heap count)) (sys-dup2 9 1) (file-close nul) (- h1 h0)))))) (def per-900 (fn (_ argv) (- (cost argv in1000) (cost argv in100)))) (display "made"))
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

### nl, which numbers each line, costs under 22,000

The number is padded to its column, so this bounds the padding and the
digits as well as the option reads.

```cu
(display (< (per-900 (list "nl")) (* 900 22000)))
```
---
    #t

### and uniq -c, which pads a count before each, under 22,000

```cu
(display (< (per-900 (list "uniq" "-c")) (* 900 22000)))
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

## after

### the sweeps turned back on, for what runs next

```cu
(do (set-first! %cu-sweeps-cell #t) (display "on"))
```
---
    on
