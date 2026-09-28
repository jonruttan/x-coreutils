# @weight 1

Applets that take any number of operands take every one, as GNU's do:
dirname puts out the directory part of each, printenv the value of each name
that is set -- status 1 where any is not -- and sleep sleeps as long as its
intervals come to between them.  An interval carries a fraction and a unit
of s, m, h or d, and one that is not an interval is said and nothing is
slept.  The expected output is GNU's.

## dirname

### the directory part of each: trailing slashes, repeated slashes, the root, no slash, empty

```cu
(do (cu-run (list "dirname" "a/b" "//a" "/" "a/" "a///b//" "." "../x" "" "/usr/lib/") "") (display ""))
```
---
```output
a
/
/
.
a
.
..
.
/usr
```

## printenv

### each name that is set, and status 1 for the one that is not

```cu
(do (sys-setenv "X_CU_EO_A" "one") (sys-setenv "X_CU_EO_B" "two") (let ((st (cu-run (list "printenv" "X_CU_EO_A" "X_CU_EO_NOPE" "X_CU_EO_B") ""))) (do (sys-unsetenv "X_CU_EO_A") (sys-unsetenv "X_CU_EO_B") (display st))))
```
---
```output
one
two
1
```

## sleep

### an interval in microseconds: whole, fraction, both, a unit; and what is not one

```cu
(display (list (map %cu-sleep-us (list "2" "0.5" ".25" "5." "1.5m" "2h" "1d" "3s" "0.0000019")) (map %cu-sleep-us (list "1x" "" "." "1.2.3" "m" "-1" "1 "))))
```
---
    ((2000000 500000 250000 5000000 90000000 7200000000 86400000000 3000000 1) (() () () () () () ()))

### every interval that is not one is said, and nothing is slept; two that are, summed

```cu
(do (sys-dup2 2 8) (let ((e (file-open-write "/tmp/x-cu-eo-err"))) (do (sys-dup2 e 2) (display (cu-run (list "sleep" "1x" "0.1" "2y") "")) (sys-dup2 8 2) (file-close e))) (newline) (display (file-read-all "/tmp/x-cu-eo-err")) (display (cu-run (list "sleep" "0.05" "0.05") "")) (file-unlink "/tmp/x-cu-eo-err"))
```
---
```output
1
sleep: invalid time interval '1x'
sleep: invalid time interval '2y'
0
```
