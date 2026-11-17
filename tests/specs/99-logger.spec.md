# @weight 1

busybox's logger (sysklogd/logger.c) refuses an option it does not take and
a -p name the C library does not hold before anything reaches the system
log, so those are tested here; what it sends is tested as root in the Linux
leg, against busybox's own.

## the fixture

### a run of logger, what it writes and its status

```cu
(do (def lg-f (fn (_ n) (string-append "/tmp/x-cu-lg." n)))
    (def lg-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (lg-f "out"))) (ee (file-open-write (lg-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (lg-f "out")) "stderr:\n"
                                              (file-read-all (lg-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the refusals

### an option logger does not take

```cu
(lg-show (list "logger" "-Z" "x"))
```
---
```output
stderr:
logger: unrecognized option: Z
Usage: logger [-s] [-t TAG] [-p PRIO] [MESSAGE]

Write MESSAGE (or stdin) to syslog

	-s	Log to stderr as well as the system log
	-t TAG	Log using the specified tag (defaults to user name)
	-p PRIO	Priority (number or FACILITY.LEVEL pair)
status 1
```

### a facility, and a level, the C library does not name

The facility is named alone; a level is named with its facility.

```cu
(do (lg-show (list "logger" "-p" "bogus.info" "x"))
    (lg-show (list "logger" "-p" "user.bogus" "x"))
    (lg-show (list "logger" "-p" "bogus" "x")))
```
---
```output
stderr:
logger: unknown facility name: bogus
status 1
stderr:
logger: unknown priority name: user.bogus
status 1
stderr:
logger: unknown priority name: bogus
status 1
```
