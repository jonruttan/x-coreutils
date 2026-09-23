# @weight 1

An applet given more operands than it takes refuses before it acts on any: in
GNU's words, `extra operand 'X'`, X the first past the last it takes.  tr says
why a delete takes one set, tty refuses with 2, mktemp says `too many
templates`, and pwd only says it ignores them.  basename takes a second
operand as a suffix, or with -s as many names as are given.  The expected text
is GNU's, less the line GNU adds after a refusal to point at --help, which no
applet here has.  cmp, diff and uuencode have no GNU build here: BSD's refuse
a count they do not take with a usage line, cmp and diff with 2 and uuencode
with 1, and so do these.  BSD's cmp reads a third and fourth operand as byte
offsets to skip; this one reads none, so it refuses them rather than compare
from the start.

## the fixtures

### three files, and a runner for stdout, stderr and the status

The working directory shows as `CWD`.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-eo && mkdir -p /tmp/x-cu-eo && cd /tmp/x-cu-eo && echo a > a && echo b > b && echo c > c && echo x > a.c")) (def nf (fn (_ n) (string-append "/tmp/x-cu-eo/" n))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (Str8 replace (sys-getcwd) "CWD" (Str8 replace "/tmp/x-cu-eo/" "" (string-concat (list (file-read-all (nf ".out")) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n")))))))))) (display "made"))
```
---
    made

## extra operand

### the first past the last is named, and nothing is done

```cu
(do (run (list "comm" (nf "a") (nf "b") (nf "c"))) (run (list "join" (nf "a") (nf "b") (nf "c"))) (run (list "seq" "1" "2" "3" "4" "5")) (run (list "split" (nf "a") (nf "p") (nf "c"))) (display (file-exists? (nf "paa"))) (newline) (run (list "date" "a" "b")) (run (list "base64" (nf "a") (nf "b"))) (run (list "shuf" (nf "a") (nf "b"))))
```
---
```output
stderr:
comm: extra operand 'c'
status 1
stderr:
join: extra operand 'c'
status 1
stderr:
seq: extra operand '4'
status 1
stderr:
split: extra operand 'c'
status 1
#f
stderr:
date: extra operand 'b'
status 1
stderr:
base64: extra operand 'b'
status 1
stderr:
shuf: extra operand 'b'
status 1
```

### an applet that takes none

```cu
(do (run (list "whoami" "x")) (run (list "logname" "x")) (run (list "uname" "x")) (run (list "arch" "x")) (run (list "nproc" "x")) (run (list "tty" "x")))
```
---
```output
stderr:
whoami: extra operand 'x'
status 1
stderr:
logname: extra operand 'x'
status 1
stderr:
uname: extra operand 'x'
status 1
stderr:
arch: extra operand 'x'
status 1
stderr:
nproc: extra operand 'x'
status 1
stderr:
tty: extra operand 'x'
status 2
```

## tr

### the first set past the last is named, and a delete given two says it takes one

```cu
(do (run (list "tr" "a" "b" "c")) (run (list "tr" "-d" "a" "b")) (run (list "tr" "-d" "a" "b" "c")) (run (list "tr" "-s" "a" "b" "c")) (run (list "tr" "-ds" "a" "b" "c")))
```
---
```output
stderr:
tr: extra operand 'c'
status 1
stderr:
tr: extra operand 'b'
Only one string may be given when deleting without squeezing repeats.
status 1
stderr:
tr: extra operand 'b'
status 1
stderr:
tr: extra operand 'c'
status 1
stderr:
tr: extra operand 'c'
status 1
```

## the others

### basename takes a suffix second, or with -s every name

```cu
(do (run (list "basename" "a" "b" "c")) (run (list "basename" "/x/a.c" ".c")) (run (list "basename" "-s" ".c" "/x/a.c" "b.c" "c")))
```
---
```output
stderr:
basename: extra operand 'c'
status 1
a
stderr:
status 0
a
b
c
stderr:
status 0
```

### shuf -e shuffles every word given, and -i takes none

The shuffled order is chance's, so the lines are counted.

```cu
(do (run (list "shuf" "-i" "1-3" "x")) (cu-run (list "shuf" "-e" "a" "b" "c" "-o" (nf "sh")) "") (display (length (%cu-lines (file-read-all (nf "sh"))))) (newline))
```
---
```output
stderr:
shuf: extra operand 'x'
status 1
3
```

### pwd says it ignores them, and mktemp takes one template

```cu
(do (run (list "pwd" "x")) (run (list "mktemp" (nf "tXXXXXX") (nf "uXXXXXX"))))
```
---
```output
CWD
stderr:
pwd: ignoring non-option arguments
status 0
stderr:
mktemp: too many templates
status 1
```

### cmp, diff and uuencode refuse with a usage line

```cu
(do (run (list "cmp" (nf "a") (nf "b") "1" "2" "3")) (run (list "diff" (nf "a") (nf "b") (nf "c"))) (run (list "uuencode" (nf "a") "n" (nf "c"))))
```
---
```output
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

### cmp refuses the offsets it does not read

```cu
(do (run (list "cmp" (nf "a") (nf "b") "1")) (run (list "cmp" (nf "a") (nf "b") "1" "1")))
```
---
```output
stderr:
cmp: usage: cmp [-ls] [-n N] FILE1 FILE2
status 2
stderr:
cmp: usage: cmp [-ls] [-n N] FILE1 FILE2
status 2
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-eo")) (display "clean"))
```
---
    clean
