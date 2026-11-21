# @weight 1

busybox's setarch, linux32 and linux64 (util-linux/setarch.c) read their
names and options before they set a personality, so the refusals are
tested here; what a program runs under is tested as root in the Linux
leg, against busybox's own.

## the fixture

### a run of an applet, what it writes and its status

```cu
(do (def sa-f (fn (_ n) (string-append "/tmp/x-cu-sa." n)))
    (def sa-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (sa-f "out"))) (ee (file-open-write (sa-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (sa-f "out")) "stderr:\n"
                                              (file-read-all (sa-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the names

### setarch without a personality shows its usage

```cu
(do (sa-show (list "setarch"))
    (sa-show (list "setarch" "-R" "linux32" "true")))
```
---
```output
stderr:
Usage: setarch PERSONALITY [-R] PROG ARGS

PERSONALITY may be:
	linux32	Set 32bit uname emulation
	linux64	Set 64bit uname emulation

	-R	Disable address space randomization
status 1
stderr:
Usage: setarch PERSONALITY [-R] PROG ARGS

PERSONALITY may be:
	linux32	Set 32bit uname emulation
	linux64	Set 64bit uname emulation

	-R	Disable address space randomization
status 1
```

### a "linux" word that names no personality: no applet, so no usage

```cu
(do (sa-show (list "setarch" "linux" "true"))
    (sa-show (list "setarch" "linuxq" "true")))
```
---
```output
stderr:
status 1
stderr:
status 1
```

### an option linux32 does not take: no help text

```cu
(sa-show (list "linux32" "-x"))
```
---
```output
stderr:
linux32: unrecognized option: x
No help available
status 1
```
