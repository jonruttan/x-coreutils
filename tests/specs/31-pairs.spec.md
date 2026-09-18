# @weight 2

What the tools that need all their files say when one will not read: comm,
join, paste, cmp, diff and xargs -a.  They print nothing they cannot print
whole -- but for paste, which pastes a directory as an empty column -- and
cmp and diff fail as they do for trouble, with 2.  Most open every file
before they read any, so a file that is not there is said before a
directory that will not read; comm reads each in turn.  The expected text
and statuses are GNU's for comm, join and paste, and BSD's for cmp and
diff, which have no GNU build here; xargs -a has neither, and says it as
the other readers do.

## the fixtures

### two files, a directory, and a reader for both streams

`a` holds `a` and `b` holds `b`, a line each; `dd` is a directory.  A tab
shows as `^I`.

```cu
(do (def ph (fn (_ n) (string-append "/tmp/x-cu-pr/" n))) (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-pr && mkdir -p /tmp/x-cu-pr/dd && cd /tmp/x-cu-pr && printf 'a\\n' > a && printf 'b\\n' > b")) (def seen (fn (_ s) (Str8 replace "\t" "^I" (Str8 replace "/tmp/x-cu-pr/" "" s)))) (def pr (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (ph ".out"))) (ee (file-open-write (ph ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def pr-st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (seen (file-read-all (ph ".out")))) (display (seen (file-read-all (ph ".err")))) (display "status ") (display pr-st) (newline)))))) (display "made"))
```
---
    made

## comm and join

### comm prints nothing without its two files, and reads the first before it opens the second

```cu
(do (pr (list "comm" (ph "a") (ph "nosuch"))) (pr (list "comm" (ph "a") (ph "dd"))) (pr (list "comm" (ph "dd") (ph "nosuch"))))
```
---
```output
comm: nosuch: No such file or directory
status 1
comm: dd: Is a directory
status 1
comm: dd: Is a directory
status 1
```

### join opens both before it reads either, and names no file for a read that fails

```cu
(do (pr (list "join" (ph "a") (ph "nosuch"))) (pr (list "join" (ph "a") (ph "dd"))) (pr (list "join" (ph "dd") (ph "nosuch"))))
```
---
```output
join: nosuch: No such file or directory
status 1
join: read error: Is a directory
status 1
join: nosuch: No such file or directory
status 1
```

## paste

### a file that will not open stops it before anything is pasted

```cu
(do (pr (list "paste" (ph "a") (ph "nosuch1") (ph "nosuch2"))) (pr (list "paste" (ph "dd") (ph "nosuch"))))
```
---
```output
paste: nosuch1: No such file or directory
status 1
paste: nosuch: No such file or directory
status 1
```

### a directory is pasted as an empty column, and said

```cu
(pr (list "paste" (ph "a") (ph "dd") (ph "b")))
```
---
```output
a^I^Ib
paste: dd: Is a directory
status 1
```

## cmp and diff

### cmp says the first file it cannot read, and fails with 2 -- silently under -s

```cu
(do (pr (list "cmp" (ph "a") (ph "nosuch"))) (pr (list "cmp" (ph "a") (ph "dd"))) (pr (list "cmp" (ph "dd") (ph "nosuch"))) (pr (list "cmp" "-s" (ph "a") (ph "nosuch"))))
```
---
```output
cmp: nosuch: No such file or directory
status 2
cmp: dd: Is a directory
status 2
cmp: nosuch: No such file or directory
status 2
status 2
```

### diff says it too, and a directory against a file names the file inside it

```cu
(do (pr (list "diff" (ph "a") (ph "nosuch"))) (pr (list "diff" (ph "nosuch1") (ph "nosuch2"))) (pr (list "diff" (ph "a") (ph "dd"))) (pr (list "diff" "-q" (ph "a") (ph "nosuch"))))
```
---
```output
diff: nosuch: No such file or directory
status 2
diff: nosuch1: No such file or directory
status 2
diff: dd/a: No such file or directory
status 2
diff: nosuch: No such file or directory
status 2
```

## xargs -a

### a file xargs cannot read is said, and nothing is run

```cu
(do (pr (list "xargs" "-a" (ph "nosuch") "echo" "ran")) (pr (list "xargs" "-a" (ph "dd") "echo" "ran")))
```
---
```output
xargs: nosuch: No such file or directory
status 1
xargs: dd: Is a directory
status 1
```

## the -z readers

### reading a file as NUL-ended fields, each says it as it does without -z

```cu
(do (pr (list "sort" "-z" (ph "a") (ph "nosuch"))) (pr (list "sort" "-z" (ph "dd") (ph "a"))) (pr (list "shuf" "-z" (ph "nosuch"))) (pr (list "shuf" "-z" (ph "dd"))) (pr (list "xargs" "-0" "-a" (ph "nosuch") "echo" "ran")))
```
---
```output
sort: cannot read: nosuch: No such file or directory
status 2
sort: read failed: dd: Is a directory
status 2
shuf: nosuch: No such file or directory
status 1
shuf: read error: Is a directory
status 1
xargs: nosuch: No such file or directory
status 1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-pr")) (display "clean"))
```
---
    clean
