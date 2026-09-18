# @weight 1

What sync says when it cannot do what it is asked: a file it cannot open, -d
with no file, and -d with -f.  The expected text and statuses are GNU
sync's for the same files.

## the fixtures

### a directory of files, one unreadable and one write-only

```cu
(do (def sh (fn (_ n) (string-append "/tmp/x-cu-sync/" n))) (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-sync && mkdir -p /tmp/x-cu-sync/dir && cd /tmp/x-cu-sync && printf x > f && printf y > g && : > locked && printf w > w && chmod 000 locked && chmod 200 w")) (def sy (fn (_ argv) (do (sys-dup2 2 8) (let ((ee (file-open-write (sh ".err")))) (do (sys-dup2 ee 2) (def sy-st (cu-run (pair "sync" argv) "")) (sys-dup2 8 2) (file-close ee) (display (Str8 replace "/tmp/x-cu-sync/" "" (file-read-all (sh ".err")))) (display "status ") (display sy-st) (newline)))))) (display "made"))
```
---
    made

## files

### a file that is not there is said, and the others are still synced

```cu
(sy (list (sh "f") (sh "nope") (sh "g")))
```
---
```output
sync: error opening 'nope': No such file or directory
status 1
```

### so is one it may not open

```cu
(sy (list (sh "locked")))
```
---
```output
sync: error opening 'locked': Permission denied
status 1
```

### one it may only write is opened to write, and a directory is opened too

```cu
(do (sy (list (sh "w"))) (sy (list "-d" (sh "w"))) (sy (list (sh "dir"))))
```
---
```output
status 0
status 0
status 0
```

## -d and -f

### -d needs a file, and does not go with -f

```cu
(do (sy (list "-d")) (sy (list "-d" "-f" (sh "f"))) (sy (list "-d" (sh "f"))))
```
---
```output
sync: --data needs at least one argument
status 1
sync: cannot specify both --data and --file-system
status 1
status 0
```

### -f opens nothing: with no syncfs, sync syncs everything and opens no file

```cu
(sy (list "-f" (sh "nope")))
```
---
```output
status 0
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "chmod 644 /tmp/x-cu-sync/locked /tmp/x-cu-sync/w; rm -rf /tmp/x-cu-sync")) (display "clean"))
```
---
    clean
