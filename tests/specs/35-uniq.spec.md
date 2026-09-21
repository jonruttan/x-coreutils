# @weight 1

`uniq [IN [OUT]]`: the first operand is what uniq reads and the second is
where it writes, `-` for either being standard input or output.  A third
operand is refused before anything opens.  IN is opened before OUT, so an
IN that will not open leaves OUT uncreated; OUT is truncated before IN is
read, so the same file for both comes out empty.  The expected text and
statuses are GNU uniq's for the same files, less the line GNU adds after a
refused operand pointing at its `--help`, which x has no counterpart for.

Each case shows what uniq wrote to stdout and stderr and its status, then
each file it names: its bytes between brackets, or `none` when it is not
there.

## the fixtures

### an input with a run in it, and a reader for both streams and the files

`in` is `a`, `a`, `b`; `same` is a copy of it; `old` holds a line of its
own; `dd` is a directory.

```cu
(do (def kh (fn (_ n) (string-append "/tmp/x-cu-uq/" n))) (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-uq && mkdir -p /tmp/x-cu-uq/dd && cd /tmp/x-cu-uq && printf 'a\\na\\nb\\n' > in && cp in same && printf 'old old old old\\n' > old")) (def uq-show (fn (self names) (if (null? names) () (do (display (first names)) (display ": ") (display (if (file-exists? (kh (first names))) (string-append "[" (string-append (file-read-all (kh (first names))) "]")) "none")) (newline) (self (rest names)))))) (def uq (fn (_ argv input names) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (kh ".out"))) (ee (file-open-write (kh ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def uq-st (cu-run (pair "uniq" argv) input)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (file-read-all (kh ".out"))) (display (Str8 replace "/tmp/x-cu-uq/" "" (file-read-all (kh ".err")))) (display "status ") (display uq-st) (newline) (uq-show names)))))) (display "made"))
```
---
    made

## where it writes

### the second operand is where the output goes

```cu
(uq (list (kh "in") (kh "o1")) "" (list "o1"))
```
---
```output
status 0
o1: [a
b
]
```

### - is standard input as the first, and standard output as the second

```cu
(do (uq (list "-" (kh "o2")) "a\na\nb\n" (list "o2")) (uq (list (kh "in") "-") "" ()))
```
---
```output
status 0
o2: [a
b
]
a
b
status 0
```

### an output that is there is truncated first

```cu
(uq (list (kh "in") (kh "old")) "" (list "old"))
```
---
```output
status 0
old: [a
b
]
```

### the same file as both comes out empty

```cu
(uq (list (kh "same") (kh "same")) "" (list "same"))
```
---
```output
status 0
same: []
```

### the flags shape what the output holds, and -- ends them

```cu
(do (uq (list "-d" (kh "in") (kh "o3")) "" (list "o3")) (uq (list "-u" "--" (kh "in") (kh "o4")) "" (list "o4")))
```
---
```output
status 0
o3: [a
]
status 0
o4: [b
]
```

## what it refuses

### a third operand is refused, and nothing is opened

The operand named is the third, however many follow it.

```cu
(do (uq (list (kh "in") (kh "o5") (kh "extra")) "" (list "o5")) (uq (list (kh "in") (kh "o6") (kh "c") (kh "d")) "" (list "o6")))
```
---
```output
uniq: extra operand 'extra'
status 1
o5: none
uniq: extra operand 'c'
status 1
o6: none
```

### an input that will not open leaves the output uncreated

```cu
(uq (list (kh "nosuch") (kh "o7")) "" (list "o7"))
```
---
```output
uniq: nosuch: No such file or directory
status 1
o7: none
```

### an input that opens and will not read leaves it created, and empty

```cu
(uq (list (kh "dd") (kh "o8")) "" (list "o8"))
```
---
```output
uniq: error reading 'dd': Is a directory
status 1
o8: []
```

### an output that will not open is said

```cu
(do (uq (list (kh "in") (kh "nodir/x")) "" ()) (uq (list (kh "in") (kh "dd")) "" ()))
```
---
```output
uniq: nodir/x: No such file or directory
status 1
uniq: dd: Is a directory
status 1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-uq")) (display "clean"))
```
---
    clean
