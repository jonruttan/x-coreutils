# @weight 1

busybox's klogd (sysklogd/klogd.c) reads its options before it opens the
kernel's ring, so the refusals are tested here; what it sends on is tested
as root in the Linux leg, against busybox's own.

## the fixture

### a run of klogd, what it writes and its status

```cu
(do (def kl-f (fn (_ n) (string-append "/tmp/x-cu-kl." n)))
    (def kl-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (kl-f "out"))) (ee (file-open-write (kl-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (kl-f "out")) "stderr:\n"
                                              (file-read-all (kl-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the options

### an option klogd does not take

```cu
(kl-show (list "klogd" "-x"))
```
---
```output
stderr:
klogd: unrecognized option: x
Usage: klogd [-c N] [-n]

Log kernel messages to syslog

	-c N	Print to console messages more urgent than prio N (1-8)
	-n	Run in foreground
status 1
```

### -c N: from 1 to 8, in decimal

```cu
(do (kl-show (list "klogd" "-n" "-c" "x"))
    (kl-show (list "klogd" "-n" "-c" "9"))
    (kl-show (list "klogd" "-n" "-c" "0"))
    (kl-show (list "klogd" "-n" "-c" "3x")))
```
---
```output
stderr:
klogd: invalid number 'x'
status 1
stderr:
klogd: number 9 is not in 1..8 range
status 1
stderr:
klogd: number 0 is not in 1..8 range
status 1
stderr:
klogd: invalid number '3x'
status 1
```
