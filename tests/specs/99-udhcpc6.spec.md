# @weight 1

busybox's udhcpc6 (networking/udhcp/d6_dhcpc.c) reads its options before
it asks for the interface, so their refusals are tested here; the leases,
the packets and the script's events are tested as root in the Linux leg,
against busybox's own.

## the fixture

### a run of udhcpc6, what it writes and its status

```cu
(do (def u6-f (fn (_ n) (string-append "/tmp/x-cu-u6." n)))
    (def u6-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (u6-f "out"))) (ee (file-open-write (u6-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (u6-f "out")) "stderr:\n"
                                              (file-read-all (u6-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the options

### -B, which the usage lists and udhcpc6 does not read

```cu
(u6-show (list "udhcpc6" "-B"))
```
---
```output
stderr:
udhcpc6: unrecognized option: B
Usage: udhcpc6 [-fbqvR] [-t N] [-T SEC] [-A SEC|-n] [-i IFACE] [-s PROG]
	[-p PIDFILE] [-ldo] [-r IPv6] [-x OPT:VAL]... [-O OPT]...

	-i IFACE	Interface to use (default eth0)
	-p FILE		Create pidfile
	-s PROG		Run PROG at DHCP events (default /usr/share/udhcpc/default6.script)
	-B		Request broadcast replies
	-t N		Send up to N discover packets
	-T SEC		Pause between packets (default 3)
	-A SEC		Wait if lease is not obtained (default 20)
	-b		Background if lease is not obtained
	-n		Exit if lease is not obtained
	-q		Exit after obtaining lease
	-R		Release IP on exit
	-f		Run in foreground
	-S		Log to syslog too
	-l		Send 'information request' instead of 'solicit'
			(used for servers which do not assign IPv6 addresses)
	-r IPv6		Request this address ('no' to not request any IP)
	-d		Request prefix
	-o		Don't request any options (unless -O is given)
	-O OPT		Request option OPT from server (cumulative)
	-x OPT:VAL	Include option OPT in sent packets (cumulative)
			Examples of string, numeric, and hex byte opts:
			-x hostname:bbox - option 12
			-x lease:3600 - option 51 (lease time)
			-x 0x3d:0100BEEFC0FFEE - option 61 (client id)
			-x 14:'"dumpfile"' - option 14 (shell-quoted)
	-v		Verbose
Signals:
	USR1	Renew lease
	USR2	Release lease
status 1
```

### numbers that are not, and an address that is not IPv6

-T, -t and -A take a count of seconds or packets, at most 2147483647; -r
is read by inet_pton for IPv6.

```cu
(do (u6-show (list "udhcpc6" "-T" "x"))
    (u6-show (list "udhcpc6" "-t" "-1"))
    (u6-show (list "udhcpc6" "-A" "3000000000"))
    (u6-show (list "udhcpc6" "-r" "1.2.3.4")))
```
---
```output
stderr:
udhcpc6: invalid number 'x'
status 1
stderr:
udhcpc6: invalid number '-1'
status 1
stderr:
udhcpc6: number 3000000000 is not in 0..2147483647 range
status 1
stderr:
udhcpc6: bad IPv6 address '1.2.3.4'
status 1
```

### options named that DHCPv6 does not know, and hex that is not

A code above 254 is read as a name; the names are DHCPv6's.

```cu
(do (u6-show (list "udhcpc6" "-O" "foo"))
    (u6-show (list "udhcpc6" "-O" "255"))
    (u6-show (list "udhcpc6" "-x" "hostname:box"))
    (u6-show (list "udhcpc6" "-x" "0x10:zz")))
```
---
```output
stderr:
udhcpc6: unknown option 'foo', known options: dns search fqdn tz timezone bootfile_url bootfile_param pxeconffile pxepathprefix
status 1
stderr:
udhcpc6: unknown option '255', known options: dns search fqdn tz timezone bootfile_url bootfile_param pxeconffile pxepathprefix
status 1
stderr:
udhcpc6: unknown option 'hostname', known options: dns search fqdn tz timezone bootfile_url bootfile_param pxeconffile pxepathprefix
status 1
stderr:
udhcpc6: malformed hex string 'zz'
status 1
```
