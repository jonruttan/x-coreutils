# @weight 1

busybox's dmesg (util-linux/dmesg.c) reads its options before it asks the
kernel's ring, so the refusals are tested here; what it prints and clears
is tested as root in the Linux leg, against busybox's own.

## the fixture

### a run of dmesg, what it writes and its status

```cu
(do (def dm-f (fn (_ n) (string-append "/tmp/x-cu-dm." n)))
    (def dm-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (dm-f "out"))) (ee (file-open-write (dm-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (dm-f "out")) "stderr:\n"
                                              (file-read-all (dm-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the options

### an option dmesg does not take

```cu
(dm-show (list "dmesg" "-x"))
```
---
```output
stderr:
dmesg: unrecognized option: x
Usage: dmesg [-cr] [-n LEVEL] [-s SIZE]

Print or control the kernel ring buffer

	-c		Clear ring buffer after printing
	-n LEVEL	Set console logging level
	-s SIZE		Buffer size
	-r		Print raw message buffer
status 1
```

### -s and -n: from 0 to 2147483647, in decimal

```cu
(do (dm-show (list "dmesg" "-s" "x"))
    (dm-show (list "dmesg" "-s" "3x"))
    (dm-show (list "dmesg" "-s" "2147483648"))
    (dm-show (list "dmesg" "-n" "-1")))
```
---
```output
stderr:
dmesg: invalid number 'x'
status 1
stderr:
dmesg: invalid number '3x'
status 1
stderr:
dmesg: number 2147483648 is not in 0..2147483647 range
status 1
stderr:
dmesg: invalid number '-1'
status 1
```
