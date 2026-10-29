# @weight 1

busybox's zcip (networking/zcip.c) takes exactly two operands, then opens
its packet socket before it reads -l and -r or runs the script, so the
usage is tested here, and the socket Darwin refuses; the probes, the
announcements and the script runs are tested as root in the Linux leg.

## the fixture

### a run of zcip, what it writes and its status

```cu
(do (def zc-f (fn (_ n) (string-append "/tmp/x-cu-zc." n)))
    (def zc-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (zc-f "out"))) (ee (file-open-write (zc-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (zc-f "out")) "stderr:\n"
                                              (file-read-all (zc-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the usage

### one operand, three, an option not known

```cu
(do (zc-show (list "zcip" "eth0"))
    (zc-show (list "zcip" "-f" "eth0" "/bin/true" "x"))
    (zc-show (list "zcip" "-x" "eth0" "/bin/true")))
```
---
```output
stderr:
Usage: zcip [OPTIONS] IFACE SCRIPT

Manage a ZeroConf IPv4 link-local address

	-f		Run in foreground
	-q		Quit after obtaining address
	-r 169.254.x.x	Request this address first
	-l x.x.0.0	Use this range instead of 169.254
	-v		Verbose

$LOGGING=none		Suppress logging
$LOGGING=syslog 	Log to syslog

With no -q, runs continuously monitoring for ARP conflicts,
exits only on I/O errors (link down etc)
status 1
stderr:
Usage: zcip [OPTIONS] IFACE SCRIPT

Manage a ZeroConf IPv4 link-local address

	-f		Run in foreground
	-q		Quit after obtaining address
	-r 169.254.x.x	Request this address first
	-l x.x.0.0	Use this range instead of 169.254
	-v		Verbose

$LOGGING=none		Suppress logging
$LOGGING=syslog 	Log to syslog

With no -q, runs continuously monitoring for ARP conflicts,
exits only on I/O errors (link down etc)
status 1
stderr:
zcip: unrecognized option: x
Usage: zcip [OPTIONS] IFACE SCRIPT

Manage a ZeroConf IPv4 link-local address

	-f		Run in foreground
	-q		Quit after obtaining address
	-r 169.254.x.x	Request this address first
	-l x.x.0.0	Use this range instead of 169.254
	-v		Verbose

$LOGGING=none		Suppress logging
$LOGGING=syslog 	Log to syslog

With no -q, runs continuously monitoring for ARP conflicts,
exits only on I/O errors (link down etc)
status 1
```

## the socket

### refused before -l is read or the script is run

```cu
(do (zc-show (list "zcip" "-f" "eth0" "/bin/true"))
    (zc-show (list "zcip" "-f" "-l" "10.0.0.1" "eth0" "/nonexistent")))
```
---
```output
stderr:
zcip: socket(AF_PACKET,10,1544): Address family not supported by protocol family
status 1
stderr:
zcip: socket(AF_PACKET,10,1544): Address family not supported by protocol family
status 1
```
