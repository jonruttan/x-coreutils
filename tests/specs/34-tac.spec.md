# @weight 1

tac reverses each file on its own, record by record: a record ends with its
newline, and a last one without a newline is put out as it is, so it runs
into the record after it.  The expected text and statuses are GNU tac's for
the same files.

Each case shows what tac wrote, then a `|` where it ended -- so a record
with no newline shows as the one before the `|` -- then what it said on
stderr and its status.

## the fixtures

### files with and without a last newline, and a reader for both streams

`a` holds `1` and `2` and `b` holds `3` and `4`, a line each.  `nonl` holds
`1` and then `2` with no newline after it; `mid` is `x`, an empty line, and
`y` with no newline; `dd` is a directory.

```cu
(do (def th (fn (_ n) (string-append "/tmp/x-cu-tac/" n))) (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-tac && mkdir -p /tmp/x-cu-tac/dd && cd /tmp/x-cu-tac && printf '1\\n2\\n' > a && printf '3\\n4\\n' > b && printf '1\\n2' > nonl && printf 'x\\n\\ny' > mid")) (def tc (fn (_ argv input) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (th ".out"))) (ee (file-open-write (th ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def tc-st (cu-run (pair "tac" argv) input)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (file-read-all (th ".out"))) (display "|\n") (display (Str8 replace "/tmp/x-cu-tac/" "" (file-read-all (th ".err")))) (display "status ") (display tc-st) (newline)))))) (display "made"))
```
---
    made

## each file on its own

### two files are each reversed, in the order given

```cu
(tc (list (th "a") (th "b")) "")
```
---
```output
2
1
4
3
|
status 0
```

### standard input is reversed on its own, in its place

```cu
(tc (list (th "a") "-" (th "b")) "5\n6\n")
```
---
```output
2
1
6
5
4
3
|
status 0
```

### a file that will not open or read is said, and the others are still reversed

```cu
(do (tc (list (th "a") (th "nosuch") (th "b")) "") (tc (list (th "a") (th "dd") (th "b")) ""))
```
---
```output
2
1
4
3
|
tac: failed to open 'nosuch' for reading: No such file or directory
status 1
2
1
4
3
|
tac: dd: read error: Is a directory
status 1
```

## a record without a newline

### a last record without a newline runs into the next

```cu
(do (tc (list (th "nonl") (th "b")) "") (tc (list (th "a") (th "nonl")) ""))
```
---
```output
21
4
3
|
status 0
2
1
21
|
status 0
```

### nothing is added to it when it comes last

```cu
(tc () "a")
```
---
```output
a|
status 0
```

### an empty line is a record of its own

`x`, the empty line, then `y`: reversed, `y` runs into the empty line's
newline.

```cu
(tc (list (th "mid")) "")
```
---
```output
y
x
|
status 0
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-tac")) (display "clean"))
```
---
    clean
