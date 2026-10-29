# @weight 1

busybox's udhcpd (networking/udhcp/dhcpd.c) reads its options, then its
configuration, before it opens a socket, so those are tested here, each
run ended before the interface is asked for; the leases, the replies and
the lease file are tested as root in the Linux leg, against busybox's own.

## the fixture

### a run of udhcpd in the foreground, what it writes and its status

```cu
(do (def ud-f (fn (_ n) (string-append "/tmp/x-cu-ud." n)))
    (def ud-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (ud-f "out"))) (ee (file-open-write (ud-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (ud-f "out")) "stderr:\n"
                                              (file-read-all (ud-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (def ud-conf (fn (_ text) (do (file-write-all (ud-f "conf") text) (ud-f "conf"))))
    (display "made"))
```
---
    made

## the options

### one not known, a MSEC that is not a number, an ADDR that is not one

```cu
(do (ud-show (list "udhcpd" "-x"))
    (ud-show (list "udhcpd" "-f" "-a" "2s" (ud-conf "start 10.0.0.2\nend 10.0.0.1\n")))
    (ud-show (list "udhcpd" "-f" "-I" "10.0.0.1:x" (ud-conf "start 10.0.0.2\nend 10.0.0.1\n"))))
```
---
```output
stderr:
udhcpd: unrecognized option: x
Usage: udhcpd [-fS] [-I ADDR] [-a MSEC] [CONFFILE]

DHCP server

	-f	Run in foreground
	-S	Log to syslog too
	-I ADDR	Local address
	-a MSEC	Timeout for ARP ping (default 2000)
Signals:
	USR1	Update lease file
status 1
stderr:
udhcpd: invalid number '2s'
status 1
stderr:
udhcpd: bad port 'x'
status 1
```

## the configuration

### a line short of a value, values that are not read, a range backwards

Each keyword not named keeps its default; a line that cannot be read says
so and puts the keyword back to its default, then the range is checked.

```cu
(do (ud-show (list "udhcpd" "-f"
               (ud-conf (%str-concat (list
                 "# a comment\n"
                 "start\n"
                 "max_leases 12x\n"
                 "opt dns 1.2.3.4 \\\n  5.6.7.8\n"
                 "static_lease 00:11:22:33:44 10.0.0.9\n"
                 "nosuchkeyword 1\n"
                 "START 10.0.0.30\n"
                 "end 10.0.0.29\n"))))) ())
```
---
```output
stderr:
udhcpd: bad line 2: 1 tokens found, 2 needed
udhcpd: can't parse line 3 in /tmp/x-cu-ud.conf
udhcpd: can't parse line 6 in /tmp/x-cu-ud.conf
udhcpd: bad start/end IP range in /tmp/x-cu-ud.conf
status 1
```

### an option not known ends the run

```cu
(ud-show (list "udhcpd" "-f" (ud-conf "option nosuchopt 1\n")))
```
---
```output
stderr:
udhcpd: unknown option 'nosuchopt', known options: subnet timezone router dns lprsrv hostname bootsize domain swapsrv rootpath ipttl mtu broadcast routes nisdomain nissrv ntpsrv wins lease serverid message vendor tftp bootfile tzstr tzdbstr search sipsrv staticroutes vlanid vlanpriority pxeconffile pxepathprefix reboottime ip6rd msstaticroutes wpad
status 1
```
