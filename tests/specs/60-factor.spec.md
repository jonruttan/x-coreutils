# @weight 1

factor reads each operand, or each word of its input, as GNU's factor does:
blanks and a `+` may lead the digits, and anything else -- a sign, a letter,
nothing at all -- is not a positive integer, said on stderr while the rest are
still factored, with status 1.  -h writes a repeated factor once, with its
exponent.  The expected text is GNU's.

## the fixtures

### a runner for stdout, stderr and the status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-fa && mkdir -p /tmp/x-cu-fa")) (def nf (fn (_ n) (string-append "/tmp/x-cu-fa/" n))) (def run (fn (_ argv in) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv in)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (file-read-all (nf ".out")) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n")))))))) (display "made"))
```
---
    made

## numbers

### what is not one is said and the rest are factored; what may lead one

```cu
(do (run (list "factor" "12" "abc" "5") "") (run (list "factor" "--" "-3" "3x") "") (run (list "factor" "+7" " 8" "0" "1") ""))
```
---
```output
12: 2 2 3
5: 5
stderr:
factor: 'abc' is not a valid positive integer
status 1
stderr:
factor: '-3' is not a valid positive integer
factor: '3x' is not a valid positive integer
status 1
7: 7
8: 2 2 2
0:
1:
stderr:
status 0
```

### the words of standard input, and -h's exponents

```cu
(do (run (list "factor") "6 x\n9\n") (run (list "factor" "-h" "12" "8" "7" "1" "360") ""))
```
---
```output
6: 2 3
9: 3 3
stderr:
factor: 'x' is not a valid positive integer
status 1
12: 2^2 3
8: 2^3
7: 7
1:
360: 2^3 3^2 5
stderr:
status 0
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-fa")) (display "clean"))
```
---
    clean
