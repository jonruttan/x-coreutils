# @weight 1

busybox's udhcpc (networking/udhcp/dhcpc.c) reads its options before it
asks for the interface, so their refusals are tested here; the leases,
the packets and the script's events are tested as root in the Linux leg,
against busybox's own.

## the fixture

### a run of udhcpc, what it writes and its status

```cu
(do (def uc-f (fn (_ n) (string-append "/tmp/x-cu-uc." n)))
    (def uc-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (uc-f "out"))) (ee (file-open-write (uc-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (uc-f "out")) "stderr:\n"
                                              (file-read-all (uc-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the options

### one not known, and the usage

```cu
(uc-show (list "udhcpc" "-Z"))
```
---
```output
stderr:
udhcpc: unrecognized option: Z
Usage: udhcpc [-fbqvRB] [-a[MSEC]] [-t N] [-T SEC] [-A SEC|-n]
	[-i IFACE] [-s PROG] [-p PIDFILE]
	[-oC] [-r IP] [-V VENDOR] [-F NAME] [-x OPT:VAL]... [-O OPT]...

	-i IFACE	Interface to use (default eth0)
	-s PROG		Run PROG at DHCP events (default /usr/share/udhcpc/default.script)
	-p FILE		Create pidfile
	-B		Request broadcast replies
	-t N		Send up to N discover packets (default 3)
	-T SEC		Pause between packets (default 3)
	-A SEC		Wait if lease is not obtained (default 20)
	-b		Background if lease is not obtained
	-n		Exit if lease is not obtained
	-q		Exit after obtaining lease
	-R		Release IP on exit
	-f		Run in foreground
	-S		Log to syslog too
	-a[MSEC]	Validate offered address with ARP ping
	-r IP		Request this IP address
	-o		Don't request any options (unless -O is given)
	-O OPT		Request option OPT from server (cumulative)
	-x OPT:VAL	Include option OPT in sent packets (cumulative)
			Examples of string, numeric, and hex byte opts:
			-x hostname:bbox - option 12
			-x lease:3600 - option 51 (lease time)
			-x 0x3d:0100BEEFC0FFEE - option 61 (client id)
			-x 14:'"dumpfile"' - option 14 (shell-quoted)
	-F NAME		Ask server to update DNS mapping for NAME
	-V VENDOR	Vendor identifier (default 'udhcp VERSION')
	-C		Don't send MAC as client identifier
	-v		Verbose
Signals:
	USR1	Renew lease
	USR2	Release lease
status 1
```

### numbers that are not, an address that is not one

-T, -t and -A take a count of seconds or packets; -a's MSEC is attached,
or follows --arping=; -r's address is read by inet_aton, and is the usage
where it is not one.

```cu
(do (uc-show (list "udhcpc" "-f" "-T" "2s"))
    (uc-show (list "udhcpc" "-f" "--retries" "-1"))
    (uc-show (list "udhcpc" "-f" "-A" "x"))
    (uc-show (list "udhcpc" "-f" "-t" "2147483648"))
    (uc-show (list "udhcpc" "-fa2s"))
    (uc-show (list "udhcpc" "-f" "--arping=1e3"))
    (uc-show (list "udhcpc" "-f" "-r" "10.0.0.256")))
```
---
```output
stderr:
udhcpc: invalid number '2s'
status 1
stderr:
udhcpc: invalid number '-1'
status 1
stderr:
udhcpc: invalid number 'x'
status 1
stderr:
udhcpc: number 2147483648 is not in 0..2147483647 range
status 1
stderr:
udhcpc: invalid number '2s'
status 1
stderr:
udhcpc: invalid number '1e3'
status 1
stderr:
Usage: udhcpc [-fbqvRB] [-a[MSEC]] [-t N] [-T SEC] [-A SEC|-n]
	[-i IFACE] [-s PROG] [-p PIDFILE]
	[-oC] [-r IP] [-V VENDOR] [-F NAME] [-x OPT:VAL]... [-O OPT]...

	-i IFACE	Interface to use (default eth0)
	-s PROG		Run PROG at DHCP events (default /usr/share/udhcpc/default.script)
	-p FILE		Create pidfile
	-B		Request broadcast replies
	-t N		Send up to N discover packets (default 3)
	-T SEC		Pause between packets (default 3)
	-A SEC		Wait if lease is not obtained (default 20)
	-b		Background if lease is not obtained
	-n		Exit if lease is not obtained
	-q		Exit after obtaining lease
	-R		Release IP on exit
	-f		Run in foreground
	-S		Log to syslog too
	-a[MSEC]	Validate offered address with ARP ping
	-r IP		Request this IP address
	-o		Don't request any options (unless -O is given)
	-O OPT		Request option OPT from server (cumulative)
	-x OPT:VAL	Include option OPT in sent packets (cumulative)
			Examples of string, numeric, and hex byte opts:
			-x hostname:bbox - option 12
			-x lease:3600 - option 51 (lease time)
			-x 0x3d:0100BEEFC0FFEE - option 61 (client id)
			-x 14:'"dumpfile"' - option 14 (shell-quoted)
	-F NAME		Ask server to update DNS mapping for NAME
	-V VENDOR	Vendor identifier (default 'udhcp VERSION')
	-C		Don't send MAC as client identifier
	-v		Verbose
Signals:
	USR1	Renew lease
	USR2	Release lease
status 1
```

### an option asked for by a name not known

```cu
(uc-show (list "udhcpc" "-f" "-O" "router" "-O" "121" "-O" "nosuch"))
```
---
```output
stderr:
udhcpc: unknown option 'nosuch', known options: subnet timezone router dns lprsrv hostname bootsize domain swapsrv rootpath ipttl mtu broadcast routes nisdomain nissrv ntpsrv wins lease serverid message vendor tftp bootfile tzstr tzdbstr search sipsrv staticroutes vlanid vlanpriority pxeconffile pxepathprefix reboottime ip6rd msstaticroutes wpad
status 1
```
