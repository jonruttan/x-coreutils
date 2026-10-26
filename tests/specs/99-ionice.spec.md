# @weight 1

busybox's ionice (util-linux/ionice.c) asks the kernel a process's I/O
class and priority through ioprio_get and sets them through ioprio_set.
Darwin has neither call, so here each answers as a kernel without them
does, and the options, the numbers and the command run are tested; the
calls themselves are tested against busybox in the Linux leg.

## the fixture

### a run of ionice with its stdout, stderr and status, and a run in a child of its own

ionice becomes the command it is given, so those runs are in a child, the
parent waiting for it.

```cu
(do (def io-f (fn (_ n) (string-append "/tmp/x-cu-io." n)))
    (def io-aside (fn (_)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (io-f "out"))) (ee (file-open-write (io-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2) (file-close oo) (file-close ee))))))
    (def io-show (fn (_ st)
      (do (sys-dup2 9 1) (sys-dup2 8 2)
          (display (string-concat (list (file-read-all (io-f "out")) "stderr:\n"
                                        (file-read-all (io-f "err")) "status " (cu-int->str st) "\n"))))))
    (def io-run (fn (_ argv) (do (io-aside) (io-show (cu-run argv "")))))
    (def io-forked (fn (_ argv)
      (do (io-aside)
          (def pid (sys-fork))
          (when (= pid 0) (sys-exit (cu-run argv "")))
          (io-show (sys-wait pid)))))
    (display "made"))
```
---
    made

## the options

### an unknown option, the usage

```cu
(io-run (list "ionice" "-z"))
```
---
```output
stderr:
ionice: unrecognized option: z
Usage: ionice [-c 1-3] [-n 0-7] [-t] { -p PID | PROG ARGS }

Change I/O priority and class

	-c N	Class. 1:realtime 2:best-effort 3:idle
	-n N	Priority
	-t	Ignore errors
status 1
```

### numbers as xatoi_positive reads them: -c, -n, -p, the first operand; a class past 3

```cu
(do (io-run (list "ionice" "-c" "x"))
    (io-run (list "ionice" "-n" "-1"))
    (io-run (list "ionice" "-p" "+1"))
    (io-run (list "ionice" "-p" "4294967296"))
    (io-run (list "ionice" "sleep" "1"))
    (io-run (list "ionice" "-c" "4")))
```
---
```output
stderr:
ionice: invalid number 'x'
status 1
stderr:
ionice: invalid number '-1'
status 1
stderr:
ionice: invalid number '+1'
status 1
stderr:
ionice: invalid number '4294967296'
status 1
stderr:
ionice: invalid number 'sleep'
status 1
stderr:
ionice: bad class 4
status 1
```

## the calls

### asked, set, and set with -t, on a platform without them

```cu
(do (io-run (list "ionice"))
    (io-run (list "ionice" "-p" "1"))
    (io-run (list "ionice" "-c" "3"))
    (io-run (list "ionice" "-n" "7" "-p" "1"))
    (io-run (list "ionice" "-t" "-c" "2" "-n" "0")))
```
---
```output
stderr:
ionice: ioprio_get: Function not implemented
status 1
stderr:
ionice: ioprio_get: Function not implemented
status 1
stderr:
ionice: ioprio_set: Function not implemented
status 1
stderr:
ionice: ioprio_set: Function not implemented
status 1
stderr:
status 0
```

## the command

### run in its place with -t, its options its own; one that will not run is 127, one that cannot be run 126

```cu
(do (io-forked (list "ionice" "-t" "-c3" "echo" "-n" "hi"))
    (io-forked (list "ionice" "-c" "3" "echo" "hi"))
    (io-forked (list "ionice" "-tc3" "nope"))
    (io-forked (list "ionice" "-tc3" "/tmp")))
```
---
```output
histderr:
status 0
stderr:
ionice: ioprio_set: Function not implemented
status 1
stderr:
ionice: can't execute 'nope': No such file or directory
status 127
stderr:
ionice: can't execute '/tmp': Permission denied
status 126
```

### the files taken away

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -f /tmp/x-cu-io.out /tmp/x-cu-io.err")) (display "clean"))
```
---
    clean
