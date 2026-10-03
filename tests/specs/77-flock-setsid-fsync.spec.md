# @weight 1

busybox's fsync (coreutils/sync.c), flock (util-linux/flock.c), setsid
(util-linux/setsid.c), ttysize (miscutils/ttysize.c), nologin
(util-linux/nologin) and pipe_progress (debianutils/pipe_progress.c).  The
expectations are busybox's own output, from a busybox built from its source,
less the banner line its usage text starts with.  A `|` marks the end of each
line written to standard output.

## the fixtures

### a file, a directory, a run of an applet with its stdout, stderr and status, and a run in a child of its own

setsid replaces the process that runs it, so its runs are in a child, the
parent waiting for it.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-ss && mkdir -p /tmp/x-cu-ss/d && touch /tmp/x-cu-ss/f")) (def nf (fn (_ n) (string-append "/tmp/x-cu-ss/" n))) (def show (fn (_ st) (display (Str8 replace "/tmp/x-cu-ss/" "" (string-concat (list (Str8 replace "\n" "|\n" (file-read-all (nf ".out"))) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n")))))) (def aside (fn (_) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (file-close oo) (file-close ee)))))) (def back (fn (_) (do (sys-dup2 9 1) (sys-dup2 8 2)))) (def run (fn (_ argv in) (do (aside) (def st (cu-run argv in)) (back) (show st)))) (def forked (fn (_ argv) (do (aside) (def pid (sys-fork)) (if (= pid 0) (sys-exit (cu-run argv "")) ()) (def st (sys-wait pid)) (back) (show st)))) (display "made"))
```
---
    made

## fsync

### each file flushed, -d its data alone; a file that will not open is said; with none, the usage

```cu
(do (run (list "fsync" (nf "f")) "") (run (list "fsync" "-d" (nf "f") (nf "d")) "") (run (list "fsync" (nf "nope") (nf "f")) "") (run (list "fsync") ""))
```
---
```output
stderr:
status 0
stderr:
status 0
stderr:
fsync: can't open 'nope': No such file or directory
status 1
stderr:
Usage: fsync [-d] FILE...

Write all buffered blocks in FILEs to disk

	-d	Avoid syncing metadata
status 1
```

## flock

### a file locked while a command runs; -c runs one through the shell, and takes one argument; a directory is locked too

```cu
(do (run (list "flock" (nf "f") "echo" "hi") "") (run (list "flock" (nf "f") "-c" "echo hi there") "") (run (list "flock" (nf "f") "-c" "echo a" "b") "") (run (list "flock" (nf "d") "true") ""))
```
---
```output
hi|
stderr:
status 0
hi there|
stderr:
status 0
stderr:
flock: -c takes only one argument
status 1
stderr:
status 0
```

### -s, -n and the long names; the command's status, 128 and a signal's number, or 255 where it will not run

```cu
(do (run (list "flock" "-s" (nf "f") "true") "") (run (list "flock" "-n" "-x" (nf "f") "true") "") (run (list "flock" "--shared" (nf "f") "true") "") (run (list "flock" (nf "f") "sh" "-c" "exit 7") "") (run (list "flock" (nf "f") "sh" "-c" "kill -9 $$") "") (run (list "flock" (nf "f") "nope") ""))
```
---
```output
stderr:
status 0
stderr:
status 0
stderr:
status 0
stderr:
status 7
stderr:
status 137
stderr:
flock: nope: No such file or directory
status 255
```

### a file that will not open, a descriptor that is not a number or not open, and no operand

```cu
(do (run (list "flock" (nf "nope/x") "true") "") (run (list "flock" "x") "") (run (list "flock" "99") "") (run (list "flock") ""))
```
---
```output
stderr:
flock: can't open 'nope/x': No such file or directory
status 1
stderr:
flock: invalid number 'x'
status 1
stderr:
flock: : Bad file descriptor
status 1
stderr:
Usage: flock [-sxun] FD | { FILE [-c] PROG ARGS }

[Un]lock file descriptor, or lock FILE, run PROG

	-s	Shared lock
	-x	Exclusive lock (default)
	-u	Unlock FD
	-n	Fail rather than wait
status 1
```

### a file locked elsewhere: -n fails with 1 and no word; a descriptor is locked and unlocked by its number

```cu
(do (%ss-resolve!) (def held (File open (nf "f") (lit rdonly))) (%cu-ptr-call %ss-c-flock held 2) (run (list "flock" "-n" (nf "f") "true") "") (%cu-ptr-call %ss-c-flock held 8) (run (list "flock" "-n" (nf "f") "true") "") (run (list "flock" (%cu-int->str held)) "") (run (list "flock" "-u" (%cu-int->str held)) "") (file-close held) (display ""))
```
---
```output
stderr:
status 1
stderr:
status 0
stderr:
status 0
stderr:
status 0
```

## setsid

### a command in a new session; one that will not run is 127; with none, the usage

```cu
(do (forked (list "setsid" "echo" "hi")) (forked (list "setsid" "-c" "true")) (forked (list "setsid" "nope")) (run (list "setsid") ""))
```
---
```output
hi|
stderr:
status 0
stderr:
status 0
stderr:
setsid: can't execute 'nope': No such file or directory
status 127
stderr:
Usage: setsid [-c] PROG ARGS

Run PROG in a new session. PROG will have no controlling terminal
and will not be affected by keyboard signals (^C etc).

	-c	Set controlling terminal to stdin
status 1
```

## ttysize, nologin, pipe_progress

### off a terminal, 80 by 24; operands starting w or h choose, the rest print nothing

```cu
(do (run (list "ttysize") "") (run (list "ttysize" "w" "h" "x") "") (run (list "ttysize" "h") ""))
```
---
```output
80 24|
stderr:
status 0
80 24|
stderr:
status 0
24|
stderr:
status 0
```

### nologin's line, after five seconds, and 1; pipe_progress copies its input, a newline on stderr at the end

```cu
(do (run (list "nologin") "") (run (list "pipe_progress") "abc"))
```
---
```output
This account is not available|
stderr:
status 1
abcstderr:

status 0
```
