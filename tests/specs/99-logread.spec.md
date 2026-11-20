# @weight 1

busybox's logread (sysklogd/logread.c): its options, and the refusal where
no syslogd -C has made the shared buffer.  What it reads from the buffer is
tested as root in the Linux leg, against busybox's own.

## the fixture

### a run of logread, what it writes and its status

```cu
(do (def lr-f (fn (_ n) (string-append "/tmp/x-cu-lr." n)))
    (def lr-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (lr-f "out"))) (ee (file-open-write (lr-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (lr-f "out")) "stderr:\n"
                                              (file-read-all (lr-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the options

### an option logread does not take

```cu
(lr-show (list "logread" "-x"))
```
---
```output
stderr:
logread: unrecognized option: x
Usage: logread [-fF]

Show messages in syslogd's circular buffer

	-f	Output data as log grows
	-F	Same as -f, but dump buffer first
status 1
```

## no buffer

### no syslogd -C has run

```cu
(lr-show (list "logread"))
```
---
```output
stderr:
logread: can't find syslogd buffer: No such file or directory
status 1
```
