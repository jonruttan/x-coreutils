# @weight 1

The applets that take no options.  A first `--` ends the options they do not
have, as getopt ends them, and a second is an operand; the command nohup and
chroot run keeps its own flags; printf and expr take no options at all, so a
format or a word may start with a `-`, and only a first `--` is dropped; true
and false ignore what they are given.  The expected text is GNU's.

## the fixtures

### a file, a variable, and a runner for stdout, stderr and the status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-no && mkdir -p /tmp/x-cu-no && printf 'ab\\ncd\\n' > /tmp/x-cu-no/f")) (sys-setenv "X_CU_NO" "set") (def nf (fn (_ n) (string-append "/tmp/x-cu-no/" n))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (Str8 replace "/tmp/x-cu-no/" "" (string-concat (list (file-read-all (nf ".out")) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n"))))))))) (display "made"))
```
---
    made

## --

### a first -- ends the options of an applet that takes none

```cu
(do (run (list "cksum" "--" (nf "f"))) (run (list "rev" "--" (nf "f"))) (run (list "tac" "--" (nf "f"))) (run (list "dirname" "--" "/a/b")) (run (list "factor" "--" "12")) (run (list "printenv" "--" "X_CU_NO")))
```
---
```output
2425168822 6 f
stderr:
status 0
ba
dc
stderr:
status 0
cd
ab
stderr:
status 0
/a
stderr:
status 0
12: 2 2 3
stderr:
status 0
set
stderr:
status 0
```

### and of one that changes what it is given

```cu
(do (run (list "link" "--" (nf "f") (nf "f2"))) (display (file-exists? (nf "f2"))) (newline) (run (list "unlink" "--" (nf "f2"))) (display (file-exists? (nf "f2"))) (newline))
```
---
```output
stderr:
status 0
#t
stderr:
status 0
#f
```

### a second -- is an operand

```cu
(do (run (list "dirname" "--" "--")) (run (list "tac" "--" "--" (nf "f"))) (run (list "groups" "--" "--")))
```
---
```output
.
stderr:
status 0
cd
ab
stderr:
tac: failed to open '--' for reading: No such file or directory
status 1
stderr:
groups: '--': no such user
status 1
```

### an applet with options reads them, and the --, itself

```cu
(do (run (list "basename" "-s" ".c" "--" "/a/x.c")) (run (list "basename" "-s" ".c" "--" "--")))
```
---
```output
x
stderr:
status 0
--
stderr:
status 0
```

## the command a runner runs

### nohup and chroot hand on the command's flags, and drop a first --

The runners exec, so what each would hand its command is read off the
dispatch, with an applet that answers what it was given.

```cu
(let ((given (fn (_ args thunk) args))) (display (list (%cu-dispatch given "nohup" (list "echo" "-n" "hi") (fn (_) "")) (%cu-dispatch given "nohup" (list "--" "echo" "-n" "hi") (fn (_) "")) (%cu-dispatch given "chroot" (list "/" "ls" "-d" "/") (fn (_) "")))))
```
---
    ((echo -n hi) (echo -n hi) (/ ls -d /))

## no options at all

### printf's format and expr's words may start with a -

```cu
(do (run (list "printf" "-x")) (run (list "expr" "-x")) (run (list "expr" "-5" "+" "1")))
```
---
```output
-xstderr:
status 0
-x
stderr:
status 0
-4
stderr:
status 0
```

### and only a first -- is dropped

```cu
(do (run (list "printf" "--" "-x")) (run (list "printf" "%s-" "--" "x")) (run (list "expr" "--" "-x")))
```
---
```output
-xstderr:
status 0
---x-stderr:
status 0
-x
stderr:
status 0
```

### true and false ignore what they are given

```cu
(do (run (list "true" "-x" "--" "y")) (run (list "false" "-x")))
```
---
```output
stderr:
status 0
stderr:
status 1
```

### cleanup

```cu
(do (sys-unsetenv "X_CU_NO") (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-no")) (display "clean"))
```
---
    clean
