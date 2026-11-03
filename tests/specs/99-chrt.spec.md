# @weight 1

busybox's chrt (util-linux/chrt.c) reads its options and numbers, then asks
the kernel for a process's policy and priority, or sets them.  Darwin has the
priority ranges alone, 15 to 47 whatever the policy, and no call for a
process's policy, so here the ranges are shown, the numbers are refused as
busybox refuses them, and the calls fail as ENOSYS; the policies are tested
as root in the Linux leg.

## the fixture

### a run of chrt, what it writes and its status

```cu
(do (def ch-f (fn (_ n) (string-append "/tmp/x-cu-ch." n)))
    (def ch-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (ch-f "out"))) (ee (file-open-write (ch-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (ch-f "out")) "stderr:\n"
                                              (file-read-all (ch-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the options

### none, two policies, a PRIO with no PROG

```cu
(do (ch-show (list "chrt"))
    (ch-show (list "chrt" "-r" "-f" "1" "true"))
    (ch-show (list "chrt" "5")))
```
---
```output
stderr:
Usage: chrt -m | -p [PRIO] PID | [-rfobi] PRIO PROG ARGS

Change scheduling priority and class for a process

	-m	Show min/max priorities
	-p	Operate on PID
	-r	Set SCHED_RR class
	-f	Set SCHED_FIFO class
	-o	Set SCHED_OTHER class
	-b	Set SCHED_BATCH class
	-i	Set SCHED_IDLE class
status 1
stderr:
Usage: chrt -m | -p [PRIO] PID | [-rfobi] PRIO PROG ARGS

Change scheduling priority and class for a process

	-m	Show min/max priorities
	-p	Operate on PID
	-r	Set SCHED_RR class
	-f	Set SCHED_FIFO class
	-o	Set SCHED_OTHER class
	-b	Set SCHED_BATCH class
	-i	Set SCHED_IDLE class
status 1
stderr:
Usage: chrt -m | -p [PRIO] PID | [-rfobi] PRIO PROG ARGS

Change scheduling priority and class for a process

	-m	Show min/max priorities
	-p	Operate on PID
	-r	Set SCHED_RR class
	-f	Set SCHED_FIFO class
	-o	Set SCHED_OTHER class
	-b	Set SCHED_BATCH class
	-i	Set SCHED_IDLE class
status 1
```

## the ranges

### -m, whatever follows it

```cu
(do (ch-show (list "chrt" "-m"))
    (ch-show (list "chrt" "-m" "-f" "x")))
```
---
```output
SCHED_OTHER min/max priority	: 15/47
SCHED_FIFO min/max priority	: 15/47
SCHED_RR min/max priority	: 15/47
SCHED_BATCH min/max priority	: 15/47
SCHED_IDLE min/max priority	: 15/47
stderr:
status 0
SCHED_OTHER min/max priority	: 15/47
SCHED_FIFO min/max priority	: 15/47
SCHED_RR min/max priority	: 15/47
SCHED_BATCH min/max priority	: 15/47
SCHED_IDLE min/max priority	: 15/47
stderr:
status 0
```

## the numbers

### a PID: none, past the range, signed, spaced, trailing

```cu
(do (ch-show (list "chrt" "-p" "0"))
    (ch-show (list "chrt" "-p" "2147483648"))
    (ch-show (list "chrt" "-p" "18446744073709551616"))
    (ch-show (list "chrt" "-p" "+5"))
    (ch-show (list "chrt" "-p" " 5"))
    (ch-show (list "chrt" "-p" "5x")))
```
---
```output
stderr:
chrt: number 0 is not in 1..2147483647 range
status 1
stderr:
chrt: number 2147483648 is not in 1..2147483647 range
status 1
stderr:
chrt: invalid number '18446744073709551616'
status 1
stderr:
chrt: invalid number '+5'
status 1
stderr:
chrt: invalid number ' 5'
status 1
stderr:
chrt: invalid number '5x'
status 1
```

### a PRIO: past the range, in hex and octal, a bare 0x

```cu
(do (ch-show (list "chrt" "50" "true"))
    (ch-show (list "chrt" "0x30" "true"))
    (ch-show (list "chrt" "060" "true"))
    (ch-show (list "chrt" "0x" "true")))
```
---
```output
stderr:
chrt: number 50 is not in 15..47 range
status 1
stderr:
chrt: number 0x30 is not in 15..47 range
status 1
stderr:
chrt: number 060 is not in 15..47 range
status 1
stderr:
chrt: invalid number '0x'
status 1
```

## the calls

### a policy got, a policy set, each ENOSYS

```cu
(do (ch-show (list "chrt" "-p" "1"))
    (ch-show (list "chrt" "-p" "20" "1"))
    (ch-show (list "chrt" "-o" "20" "true"))
    (ch-show (list "chrt" "0x14" "true")))
```
---
```output
stderr:
chrt: can't get pid 1's policy: Function not implemented
status 1
stderr:
chrt: can't get pid 1's policy: Function not implemented
status 1
stderr:
chrt: can't set pid 0's policy: Function not implemented
status 1
stderr:
chrt: can't set pid 0's policy: Function not implemented
status 1
```
