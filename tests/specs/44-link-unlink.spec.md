# @weight 1

link and unlink are link(2) and unlink(2) and no more.  Too few operands or too
many are refused before anything is made or removed; a call that fails is
reported with its errno's text; unlink names the path itself, so it removes a
link that leads nowhere.  The expected text is GNU's, less the line GNU adds
after a refusal to point at --help, which no applet here has.

## the fixtures

### two files, a directory, a link that leads nowhere, and a runner

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-ln && mkdir -p /tmp/x-cu-ln/dir && echo hi > /tmp/x-cu-ln/f && echo ho > /tmp/x-cu-ln/g && ln -s nowhere /tmp/x-cu-ln/dangle")) (def nf (fn (_ n) (string-append "/tmp/x-cu-ln/" n))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (Str8 replace "/tmp/x-cu-ln/" "" (string-concat (list (file-read-all (nf ".out")) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n"))))))))) (display "made"))
```
---
    made

## the operands

### too few are refused

```cu
(do (run (list "link")) (run (list "link" (nf "f"))) (run (list "unlink")))
```
---
```output
stderr:
link: missing operand
status 1
stderr:
link: missing operand after 'f'
status 1
stderr:
unlink: missing operand
status 1
```

### too many are refused, and nothing is made or removed

```cu
(do (run (list "link" (nf "f") (nf "f2") (nf "f3"))) (display (list (file-exists? (nf "f2")) (file-exists? (nf "f3")))) (newline) (run (list "unlink" (nf "f") (nf "g"))) (display (list (file-exists? (nf "f")) (file-exists? (nf "g")))) (newline))
```
---
```output
stderr:
link: extra operand 'f3'
status 1
(#f #f)
stderr:
unlink: extra operand 'g'
status 1
(#t #t)
```

## the calls

### a link that cannot be made says why

```cu
(do (run (list "link" (nf "nope") (nf "new"))) (run (list "link" (nf "f") (nf "g"))) (run (list "link" (nf "dir") (nf "dir2"))) (run (list "link" (nf "f") (nf "nodir/x"))))
```
---
```output
stderr:
link: cannot create link 'new' to 'nope': No such file or directory
status 1
stderr:
link: cannot create link 'g' to 'f': File exists
status 1
stderr:
link: cannot create link 'dir2' to 'dir': Operation not permitted
status 1
stderr:
link: cannot create link 'nodir/x' to 'f': No such file or directory
status 1
```

### a name that cannot be removed says why

```cu
(do (run (list "unlink" (nf "nope"))) (run (list "unlink" "")))
```
---
```output
stderr:
unlink: cannot unlink 'nope': No such file or directory
status 1
stderr:
unlink: cannot unlink '': No such file or directory
status 1
```

### a link is made, and a link that leads nowhere is removed

```cu
(do (run (list "link" (nf "f") (nf "f2"))) (display (file-read-all (nf "f2"))) (run (list "unlink" (nf "dangle"))) (display (file-lstat-kind (nf "dangle"))) (newline))
```
---
```output
stderr:
status 0
hi
stderr:
status 0
none
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-ln")) (display "clean"))
```
---
    clean
