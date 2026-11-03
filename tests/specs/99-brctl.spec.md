# @weight 1

busybox's brctl (networking/brctl.c) shows its usage with no command, and
otherwise works from /sys/class/net, which Darwin has not, so every other
run ends there, a command it does not know among them; the bridges are
tested as root in the Linux leg.

## the fixture

### a run of brctl, what it writes and its status

```cu
(do (def br-f (fn (_ n) (string-append "/tmp/x-cu-br." n)))
    (def br-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (br-f "out"))) (ee (file-open-write (br-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (br-f "out")) "stderr:\n"
                                              (file-read-all (br-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the usage

### no command

```cu
(br-show (list "brctl"))
```
---
```output
stderr:
Usage: brctl COMMAND [BRIDGE [ARGS]]

Manage ethernet bridges
Commands:
	show [BRIDGE]...	Show bridges
	addbr BRIDGE		Create BRIDGE
	delbr BRIDGE		Delete BRIDGE
	addif BRIDGE IFACE	Add IFACE to BRIDGE
	delif BRIDGE IFACE	Delete IFACE from BRIDGE
	showmacs BRIDGE			List MAC addresses
	showstp	BRIDGE			Show STP info
	stp BRIDGE 1/yes/on|0/no/off	Set STP on/off
	setageing BRIDGE SECONDS	Set ageing time
	setfd BRIDGE SECONDS		Set bridge forward delay
	sethello BRIDGE SECONDS		Set hello time
	setmaxage BRIDGE SECONDS	Set max message age
	setbridgeprio BRIDGE PRIO	Set bridge priority
	setportprio BRIDGE IFACE PRIO	Set port priority
	setpathcost BRIDGE IFACE COST	Set path cost
status 1
```

## /sys/class/net

### not there: a command, one not known, one short of its words

```cu
(do (br-show (list "brctl" "show"))
    (br-show (list "brctl" "frob"))
    (br-show (list "brctl" "addbr")))
```
---
```output
stderr:
brctl: can't change directory to '/sys/class/net': No such file or directory
status 1
stderr:
brctl: can't change directory to '/sys/class/net': No such file or directory
status 1
stderr:
brctl: can't change directory to '/sys/class/net': No such file or directory
status 1
```
