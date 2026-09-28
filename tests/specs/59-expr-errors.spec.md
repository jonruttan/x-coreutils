# @weight 1

An expression expr cannot parse is said as GNU's expr says it, with status 2,
and so is a division by zero.  An argument left over past the whole
expression is unexpected; an operand missing at the end is wanted after the
last argument; a group not closed at the end expects `)` after the last
argument, and one closed by something else expects `)` instead of it; and a
`)` where an operand belongs is unexpected.  The expected text is GNU's, less
the line GNU adds to point at --help.

## the fixtures

### a runner for stdout, stderr and the status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-ex && mkdir -p /tmp/x-cu-ex")) (def nf (fn (_ n) (string-append "/tmp/x-cu-ex/" n))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (file-read-all (nf ".out")) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n")))))))) (display "made"))
```
---
    made

## syntax errors

### an argument left over, and an operand missing at the end

```cu
(do (run (list "expr" "1" "+" "2" "3")) (run (list "expr" "1" "2")) (run (list "expr" "a" ":" "b" "c")) (run (list "expr" "1" "+")) (run (list "expr" "length")) (run (list "expr" "substr" "abc")))
```
---
```output
stderr:
expr: syntax error: unexpected argument '3'
status 2
stderr:
expr: syntax error: unexpected argument '2'
status 2
stderr:
expr: syntax error: unexpected argument 'c'
status 2
stderr:
expr: syntax error: missing argument after '+'
status 2
stderr:
expr: syntax error: missing argument after 'length'
status 2
stderr:
expr: syntax error: missing argument after 'abc'
status 2
```

### groups: not closed at the end, closed by something else, a close with nothing open

```cu
(do (run (list "expr" "(" "1" "+" "2")) (run (list "expr" "(" "1" "2")) (run (list "expr" "(" "(" "1" ")")) (run (list "expr" ")")) (run (list "expr" "1" "+" ")")) (run (list "expr" "(" "1" "+" "2" ")" "*" "3")))
```
---
```output
stderr:
expr: syntax error: expecting ')' after '2'
status 2
stderr:
expr: syntax error: expecting ')' instead of '2'
status 2
stderr:
expr: syntax error: expecting ')' after ')'
status 2
stderr:
expr: syntax error: unexpected ')'
status 2
stderr:
expr: syntax error: unexpected ')'
status 2
9
stderr:
status 0
```

## division by zero

### by / and by %

```cu
(do (run (list "expr" "1" "/" "0")) (run (list "expr" "7" "%" "0")))
```
---
```output
stderr:
expr: division by zero
status 2
stderr:
expr: division by zero
status 2
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-ex")) (display "clean"))
```
---
    clean
