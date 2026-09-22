# @weight 1

printf repeats its format while a pass reads arguments and some are left.  A
pass that reads none would read none on the next, so what is left is named,
once, starting with the first of it, and printf still succeeds.  A \c ends the
output before anything is named.  The expected text is GNU's.

## the fixtures

### a runner for stdout, stderr and the status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-pfx && mkdir -p /tmp/x-cu-pfx")) (def nf (fn (_ n) (string-append "/tmp/x-cu-pfx/" n))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (file-read-all (nf ".out")) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n")))))))) (display "made"))
```
---
    made

## arguments a pass does not read

### the first of them is named, and printf succeeds

```cu
(do (run (list "printf" "x" "a")) (run (list "printf" "x\\n" "a" "b" "c")))
```
---
```output
xstderr:
printf: warning: ignoring excess arguments, starting with 'a'
status 0
x
stderr:
printf: warning: ignoring excess arguments, starting with 'a'
status 0
```

### %% reads none, nor does an empty format, and an empty argument is named

```cu
(do (run (list "printf" "%%" "a")) (run (list "printf" "" "a")) (run (list "printf" "x" "")))
```
---
```output
%stderr:
printf: warning: ignoring excess arguments, starting with 'a'
status 0
stderr:
printf: warning: ignoring excess arguments, starting with 'a'
status 0
xstderr:
printf: warning: ignoring excess arguments, starting with ''
status 0
```

## arguments that are read

### a format that reads them reads them all, and names none

```cu
(do (run (list "printf" "%s\\n" "a" "b")) (run (list "printf" "%s %s\\n" "a" "b" "c")))
```
---
```output
a
b
stderr:
status 0
a b
c 
stderr:
status 0
```

### a \c ends the output before any are named

```cu
(do (run (list "printf" "a\\c" "x")) (run (list "printf" "%b" "a\\cb" "x")) (run (list "printf" "%s\\c" "a" "b")))
```
---
```output
astderr:
status 0
astderr:
status 0
astderr:
status 0
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-pfx")) (display "clean"))
```
---
    clean
