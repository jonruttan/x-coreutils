# @weight 1

busybox's tree (miscutils/tree.c) and time (miscutils/time.c).  Every
expectation is busybox's own output, from a busybox built from its source,
less the banner line its usage text starts with -- but for the times and
counts time measures, which change from run to run, and are checked for
their shape.  A `|` marks the end of each line written to standard output.
The cases run in the fixtures' directory, as busybox's did, so tree's names
are relative.

## the fixtures

### the files, a run of an applet with its standard input, stdout, stderr and status, and the fixtures' directory as the current one

`a` holds files, two directories, a dot file, a name starting with `-`, a
link and a dangling link; `only` holds a dot file and `-a`; `empty` nothing.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-tt && mkdir -p /tmp/x-cu-tt/a/b/c /tmp/x-cu-tt/a/e /tmp/x-cu-tt/only /tmp/x-cu-tt/empty && cd /tmp/x-cu-tt && touch a/f a/b/g a/b/c/h a/.hid a/-x a/e/i only/.h only/-a && ln -s f a/l && ln -s nowhere a/dl")) (def nf (fn (_ n) (string-append "/tmp/x-cu-tt/" n))) (def shown (fn (_ mode) (if (string=? mode "x") (do (proc-run (list "/bin/sh" "-c" "od -An -v -tx1 /tmp/x-cu-tt/.out | tr -d ' \\n' | fold -w 64 > /tmp/x-cu-tt/.hex; [ -s /tmp/x-cu-tt/.hex ] && echo >> /tmp/x-cu-tt/.hex")) (file-read-all (nf ".hex"))) (Str8 replace "\n" "|\n" (Str8 replace "/tmp/x-cu-tt/" "" (file-read-all (nf ".out"))))))) (def run (fn (_ mode argv in) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv in)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (shown mode) "stderr:\n" (Str8 replace "/tmp/x-cu-tt/" "" (file-read-all (nf ".err"))) "status " (%cu-int->str st) "\n")))))))) (def home (Sys getcwd)) (Sys chdir "/tmp/x-cu-tt") (display "made"))
```
---
    made

## tree

### a directory's entries in byte order, the dot ones passed over, a link and where it points, and the count

```cu
(do (run "-" (list "tree" "a") "") (run "-" (list "tree") ""))
```
---
```output
a|
├── -x|
├── b|
│   ├── c|
│   │   └── h|
│   └── g|
├── dl -> nowhere|
├── e|
│   └── i|
├── f|
└── l -> f|
|
3 directories, 7 files|
stderr:
status 0
.|
├── a|
│   ├── -x|
│   ├── b|
│   │   ├── c|
│   │   │   └── h|
│   │   └── g|
│   ├── dl -> nowhere|
│   ├── e|
│   │   └── i|
│   ├── f|
│   └── l -> f|
├── empty|
└── only|
    ├── -a|
|
6 directories, 8 files|
stderr:
status 0
```

### busybox comes back up from a/b to a, so an operand after it is looked for from there

```cu
(run "-" (list "tree" "a/b" "only") "")
```
---
```output
a/b|
├── c|
│   └── h|
└── g|
only [error opening dir]|
|
1 directories, 2 files|
stderr:
status 0
```

### a dot entry sorted last keeps the last one shown from its corner; an empty directory has nothing under it

```cu
(do (run "-" (list "tree" "only") "") (run "-" (list "tree" "empty") ""))
```
---
```output
only|
├── -a|
|
0 directories, 1 files|
stderr:
status 0
empty|
|
0 directories, 0 files|
stderr:
status 0
```

### what will not open as a directory is said, and not counted

```cu
(do (run "-" (list "tree" "nope") "") (run "-" (list "tree" "a/f") "") (run "-" (list "tree" "-x") ""))
```
---
```output
nope [error opening dir]|
|
0 directories, 0 files|
stderr:
status 0
a/f [error opening dir]|
|
0 directories, 0 files|
stderr:
status 0
-x [error opening dir]|
|
0 directories, 0 files|
stderr:
status 0
```

## time

### -f's conversions and escapes; an unknown one is ?C, a trailing % is ? and no newline, a trailing \ is ?\ and the command

```cu
(do (run "-" (list "time" "-f" "%C %x" "false") "") (run "-" (list "time" "-f" "%C|%x|%%|%q|\\t|\\n|\\\\|\\q|%" "true" "a" "b") "") (run "-" (list "time" "-f" "x%" "true") "") (run "-" (list "time" "-f" "y\\" "true") ""))
```
---
```output
stderr:
Command exited with non-zero status 1
false 1
status 1
stderr:
true a b|0|%|?q|	|
|\|?\q|?status 0
stderr:
x?status 0
stderr:
y?\true
status 0
```

### a command that did not exit 0 is said, and the status is its own or its signal's

```cu
(do (run "-" (list "time" "-f" "%x" "sh" "-c" "exit 3") "") (run "-" (list "time" "-f" "%x" "sh" "-c" "kill -9 $$") ""))
```
---
```output
stderr:
Command exited with non-zero status 3
3
status 3
stderr:
Command terminated by signal 9
0
status 9
```

### -o writes to a file, -a appends to it; -- ends the options

```cu
(do (run "-" (list "time" "-o" "out" "-f" "one" "true") "") (run "-" (list "time" "-a" "-o" "out" "-f" "two" "true") "") (run "-" (list "cat" "out") "") (run "-" (list "time" "-f" "%x" "--" "true") ""))
```
---
```output
stderr:
status 0
stderr:
status 0
one|
two|
stderr:
status 0
stderr:
0
status 0
```

### with no command, the usage

```cu
(run "-" (list "time") "")
```
---
```output
stderr:
Usage: time [-vpa] [-o FILE] PROG ARGS

Run PROG, display resource usage when it exits

	-v	Verbose
	-p	POSIX output format
	-f FMT	Custom format
	-o FILE	Write result to FILE
	-a	Append (else overwrite)
status 1
```

### the default format, -p's and -v's: lines of the times in their shapes

```cu
(do (def lines (fn (_ s) (%cu-lines s))) (def starts? (fn (_ s p) (if (>= (byte-len s) (byte-len p)) (string=? (substring s 0 (byte-len p)) p) #f))) (def all? (fn (self f l) (if (null? l) #t (if (f (first l)) (self f (rest l)) #f)))) (def err-of (fn (_ argv) (do (sys-dup2 2 8) (let ((ee (file-open-write (nf ".err")))) (do (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 8 2) (file-close ee) (pair st (lines (file-read-all (nf ".err"))))))))) (def d (err-of (list "time" "true"))) (def p (err-of (list "time" "-p" "true"))) (def v (err-of (list "time" "-v" "true"))) (display (list (first d) (length (rest d)) (all? (fn (_ l) (if (starts? l "real\t") #t (if (starts? l "user\t") #t (starts? l "sys\t")))) (rest d)) (first p) (length (rest p)) (all? (fn (_ l) (if (starts? l "real ") #t (if (starts? l "user ") #t (starts? l "sys ")))) (rest p)) (first v) (length (rest v)) (all? (fn (_ l) (starts? l "\t")) (rest v)) (first (rest v)) (List last (rest v)))))
```
---
    (0 3 #t 0 3 #t 0 23 #t 	Command being timed: "true" 	Exit status: 0)

### back to where the run started

```cu
(do (Sys chdir home) (display "back"))
```
---
    back
