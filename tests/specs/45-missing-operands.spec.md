# @weight 1

An applet given too few operands says so before it takes one: the first of an
empty list is a crash, not an error anything can catch.  In GNU's words, none
at all is `missing operand`, and some is `missing operand after 'LAST'`; tr
says why it wants a second set, split with no file reads its input, and
timeout's refusal is its status alone.  The expected text is GNU's, less the
line GNU adds after a refusal to point at --help, which no applet here has.
cmp, diff and uuencode have no GNU build here: BSD's refuse with a usage line,
cmp and diff with 2 and uuencode with 1, and so do these, naming their own
options.

## the fixtures

### a runner for stdout, stderr and the status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-mo && mkdir -p /tmp/x-cu-mo")) (def nf (fn (_ n) (string-append "/tmp/x-cu-mo/" n))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (file-read-all (nf ".out")) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n")))))))) (display "made"))
```
---
    made

## missing operand

### none at all

```cu
(do (run (list "comm")) (run (list "join")) (run (list "basename")) (run (list "dirname")) (run (list "seq")) (run (list "sleep")))
```
---
```output
stderr:
comm: missing operand
status 1
stderr:
join: missing operand
status 1
stderr:
basename: missing operand
status 1
stderr:
dirname: missing operand
status 1
stderr:
seq: missing operand
status 1
stderr:
sleep: missing operand
status 1
```

### one where two are wanted names it

```cu
(do (run (list "comm" "a")) (run (list "join" "a")) (run (list "chmod")) (run (list "chmod" "644")) (run (list "chown" "root")) (run (list "chgrp")) (run (list "chgrp" "wheel")))
```
---
```output
stderr:
comm: missing operand after 'a'
status 1
stderr:
join: missing operand after 'a'
status 1
stderr:
chmod: missing operand
status 1
stderr:
chmod: missing operand after '644'
status 1
stderr:
chown: missing operand after 'root'
status 1
stderr:
chgrp: missing operand
status 1
stderr:
chgrp: missing operand after 'wheel'
status 1
```

## tr

### one set where two are wanted, and why

```cu
(do (run (list "tr")) (run (list "tr" "a")) (run (list "tr" "-ds" "a")) (run (list "tr" "-d")))
```
---
```output
stderr:
tr: missing operand
status 1
stderr:
tr: missing operand after 'a'
Two strings must be given when translating.
status 1
stderr:
tr: missing operand after 'a'
Two strings must be given when both deleting and squeezing repeats.
status 1
stderr:
tr: missing operand
status 1
```

### deleting or squeezing alone wants one

```cu
(do (run (list "tr" "-d" "a")) (run (list "tr" "-s" "a")))
```
---
```output
stderr:
status 0
stderr:
status 0
```

## the others

### split with no file reads its input, and empty input makes no piece

```cu
(do (run (list "split")) (display (file-exists? "xaa")) (newline) (if (file-exists? "xaa") (file-unlink "xaa") ()))
```
---
```output
stderr:
status 0
#f
```

### timeout refuses with its status alone

```cu
(do (run (list "timeout")) (run (list "timeout" "5")))
```
---
```output
stderr:
status 125
stderr:
status 125
```

### cmp, diff and uuencode refuse with a usage line

```cu
(do (run (list "cmp")) (run (list "cmp" "a")) (run (list "diff" "a")) (run (list "uuencode")))
```
---
```output
stderr:
cmp: usage: cmp [-ls] [-n N] FILE1 FILE2
status 2
stderr:
cmp: usage: cmp [-ls] [-n N] FILE1 FILE2
status 2
stderr:
diff: usage: diff [-ibwBqsadTtrN] [-U N] [-L LABEL] [-S FILE] FILE1 FILE2
status 2
stderr:
uuencode: usage: uuencode [-m] [FILE] NAME
status 1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-mo")) (display "clean"))
```
---
    clean
