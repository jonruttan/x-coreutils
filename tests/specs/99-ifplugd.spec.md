# @weight 1

busybox's ifplugd (networking/ifplugd.c) reads its options, its pidfile and
-m before it reads the interface, so their refusals are tested here; the
links, the scripts and the signals are tested as root in the Linux leg,
against busybox's own.

## the fixture

### a run of ifplugd, what it writes and its status

```cu
(do (def pd-f (fn (_ n) (string-append "/tmp/x-cu-pd." n)))
    (def pd-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (pd-f "out"))) (ee (file-open-write (pd-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (pd-f "out")) "stderr:\n"
                                              (file-read-all (pd-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the options

### an option ifplugd does not take

```cu
(pd-show (list "ifplugd" "-Z"))
```
---
```output
stderr:
ifplugd: unrecognized option: Z
Usage: ifplugd [OPTIONS]

Network interface plug detection daemon

	-n		Run in foreground
	-s		Don't log to syslog
	-i IFACE	Interface
	-f/-F		Treat link detection error as link down/link up
			(otherwise exit on error)
	-a		Don't up interface at each link probe
	-M		Monitor creation/destruction of interface
			(otherwise it must exist)
	-A		Don't up newly appeared interface
	-r PROG		Script to run
	-x ARG		Extra argument for script
	-I		Don't exit on nonzero exit code from script
	-p		Don't run "up" script on startup
	-q		Don't run "down" script on exit
	-l		Always run script on startup
	-t SECS		Poll time in seconds
	-u SECS		Delay before running script after link up
	-d SECS		Delay after link down
	-m MODE		API mode (mii, priv, ethtool, wlan, iff, auto)
	-k		Kill running daemon
status 1
```

### numbers that are not

-t, -u and -d take seconds, at most 2147483647; they are read before the
interface names the messages.

```cu
(do (pd-show (list "ifplugd" "-t" "x"))
    (pd-show (list "ifplugd" "-u" "-1"))
    (pd-show (list "ifplugd" "-d" "3000000000")))
```
---
```output
stderr:
ifplugd: invalid number 'x'
status 1
stderr:
ifplugd: invalid number '-1'
status 1
stderr:
ifplugd: number 3000000000 is not in 0..2147483647 range
status 1
```

### a mode that is none of mii, priv, ethtool, wlan, iff and auto

Only the first letter is read.

```cu
(pd-show (list "ifplugd" "-n" "-i" "x-cu-none" "-m" "zz"))
```
---
```output
stderr:
ifplugd(x-cu-none): unknown API mode 'zz'
status 1
```

### -k, with no daemon running on the interface

```cu
(pd-show (list "ifplugd" "-k" "-i" "x-cu-none"))
```
---
```output
stderr:
status 0
```
