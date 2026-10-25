# @weight 1

busybox's tunctl (networking/tunctl.c) reads its options, opens its device
and asks it for an interface, so the options and a device that is not a TUN
device are tested here; Darwin has no /dev/net/tun, and the interfaces are
tested as root in the Linux leg.

## the fixture

### a run of tunctl, what it writes and its status

```cu
(do (def tu-f (fn (_ n) (string-append "/tmp/x-cu-tu." n)))
    (def tu-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (tu-f "out"))) (ee (file-open-write (tu-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (string-concat (list (file-read-all (tu-f "out")) "stderr:\n"
                                              (file-read-all (tu-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the options

### -t with -d, an operand

```cu
(do (tu-show (list "tunctl" "-t" "a" "-d" "b"))
    (tu-show (list "tunctl" "x")))
```
---
```output
stderr:
Usage: tunctl [-f DEVICE] [-t NAME | -d NAME] [-u USER] [-g GRP] [-b]

Create or delete TUN/TAP interfaces

	-f DEV	TUN device (default /dev/net/tun)
	-t NAME	Create iface (default: tapN)
	-d NAME	Delete iface
	-u USER	Set iface owner
	-g GRP	Set iface group
	-b	Brief output
status 1
stderr:
Usage: tunctl [-f DEVICE] [-t NAME | -d NAME] [-u USER] [-g GRP] [-b]

Create or delete TUN/TAP interfaces

	-f DEV	TUN device (default /dev/net/tun)
	-t NAME	Create iface (default: tapN)
	-d NAME	Delete iface
	-u USER	Set iface owner
	-g GRP	Set iface group
	-b	Brief output
status 1
```

## the device

### none at /dev/net/tun, none at -f's, one that is not a TUN device

```cu
(do (tu-show (list "tunctl"))
    (tu-show (list "tunctl" "-d" "tap0"))
    (tu-show (list "tunctl" "-f" "/nonexist" "-t" "a"))
    (tu-show (list "tunctl" "-f" "/dev/null" "-t" "z")))
```
---
```output
stderr:
tunctl: can't open '/dev/net/tun': No such file or directory
status 1
stderr:
tunctl: can't open '/dev/net/tun': No such file or directory
status 1
stderr:
tunctl: can't open '/nonexist': No such file or directory
status 1
stderr:
tunctl: Operation not supported by device
status 1
```
