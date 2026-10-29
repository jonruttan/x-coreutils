# @weight 1

busybox's traceroute and traceroute6 (networking/traceroute.c), as far as a
run without root reaches: the usage, the options' numbers in the order
busybox reads them, the address, and the raw socket refused.  The hops are
tested as root in the Linux leg.  Every expectation is busybox 1.36.1's in
alpine.  A `|` marks the end of each line written to standard output.

## the fixture

### a run of traceroute, what it writes and its status

```cu
(do (def tr-f (fn (_ n) (string-append "/tmp/x-cu-tr." n)))
    (def tr-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (tr-f "out"))) (ee (file-open-write (tr-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (Str8 replace "\n" "|\n" (file-read-all (tr-f "out"))) "stderr:\n"
                                              (file-read-all (tr-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the usage

### no host is the usage; traceroute6's leaves out -4,-6, -F and -l

```cu
(do (tr-show (list "traceroute")) (tr-show (list "traceroute6")))
```
---
```output
stderr:
Usage: traceroute [-46IFlnrv] [-f 1ST_TTL] [-m MAXTTL] [-q PROBES] [-p PORT]
	[-t TOS] [-w WAIT_SEC] [-s SRC_IP] [-i IFACE]
	[-z PAUSE_MSEC] HOST [BYTES]

Trace the route to HOST

	-4,-6	Force IP or IPv6 name resolution
	-F	Set don't fragment bit
	-I	Use ICMP ECHO instead of UDP datagrams
	-l	Display TTL value of the returned packet
	-n	Print numeric addresses
	-r	Bypass routing tables, send directly to HOST
	-v	Verbose
	-f N	First number of hops (default 1)
	-m N	Max number of hops
	-q N	Number of probes per hop (default 3)
	-p N	Base UDP port number used in probes
		(default 33434)
	-s IP	Source address
	-i IFACE Source interface
	-t N	Type-of-service in probe packets (default 0)
	-w SEC	Wait for a response (default 3)
	-z MSEC	Wait before each send
status 1
stderr:
Usage: traceroute6 [-Inrv] [-f 1ST_TTL] [-m MAXTTL] [-q PROBES] [-p PORT]
	[-t TOS] [-w WAIT_SEC] [-s SRC_IP] [-i IFACE]
	[-z PAUSE_MSEC] HOST [BYTES]

Trace the route to HOST

	-I	Use ICMP ECHO instead of UDP datagrams
	-n	Print numeric addresses
	-r	Bypass routing tables, send directly to HOST
	-v	Verbose
	-f N	First number of hops (default 1)
	-m N	Max number of hops
	-q N	Number of probes per hop (default 3)
	-p N	Base UDP port number used in probes
		(default 33434)
	-s IP	Source address
	-i IFACE Source interface
	-t N	Type-of-service in probe packets (default 0)
	-w SEC	Wait for a response (default 3)
	-z MSEC	Wait before each send
status 1
```

## the numbers

### -m, -p, -q, -w, -z, then -f up to -m

```cu
(do (tr-show (list "traceroute" "-m" "0" "h"))
    (tr-show (list "traceroute" "-m" "256" "h"))
    (tr-show (list "traceroute" "-p" "65536" "h"))
    (tr-show (list "traceroute" "-q" "0" "h"))
    (tr-show (list "traceroute" "-q" "x" "h"))
    (tr-show (list "traceroute" "-q" "2147483648" "h"))
    (tr-show (list "traceroute" "-w" "0" "h"))
    (tr-show (list "traceroute" "-w" "86401" "h"))
    (tr-show (list "traceroute" "-z" "3600001" "h"))
    (tr-show (list "traceroute" "-f" "0" "h"))
    (tr-show (list "traceroute" "-f" "31" "h"))
    (tr-show (list "traceroute" "-m" "5" "-f" "6" "h"))
    (tr-show (list "traceroute" "-f" "3" "-m" "2" "-q" "0" "h")))
```
---
```output
stderr:
traceroute: number 0 is not in 1..255 range
status 1
stderr:
traceroute: number 256 is not in 1..255 range
status 1
stderr:
traceroute: number 65536 is not in 0..65535 range
status 1
stderr:
traceroute: number 0 is not in 1..2147483647 range
status 1
stderr:
traceroute: invalid number 'x'
status 1
stderr:
traceroute: number 2147483648 is not in 1..2147483647 range
status 1
stderr:
traceroute: number 0 is not in 1..86400 range
status 1
stderr:
traceroute: number 86401 is not in 1..86400 range
status 1
stderr:
traceroute: number 3600001 is not in 0..3600000 range
status 1
stderr:
traceroute: number 0 is not in 1..30 range
status 1
stderr:
traceroute: number 31 is not in 1..30 range
status 1
stderr:
traceroute: number 6 is not in 1..5 range
status 1
stderr:
traceroute: number 0 is not in 1..2147483647 range
status 1
```

### the packet length: from the header's own to 32768, read after the address

```cu
(do (tr-show (list "traceroute" "127.0.0.1" "45"))
    (tr-show (list "traceroute" "127.0.0.1" "32769"))
    (tr-show (list "traceroute" "127.0.0.1" "x"))
    (tr-show (list "traceroute6" "::1" "71"))
    (tr-show (list "traceroute" "nosuch.invalid" "x")))
```
---
```output
stderr:
traceroute: number 45 is not in 46..32768 range
status 1
stderr:
traceroute: number 32769 is not in 46..32768 range
status 1
stderr:
traceroute: invalid number 'x'
status 1
stderr:
traceroute6: number 71 is not in 72..32768 range
status 1
stderr:
traceroute: bad address 'nosuch.invalid'
status 1
```

## the address and the socket

### a name with no address, -4 with an IPv6 one; without root the raw socket is refused

```cu
(do (tr-show (list "traceroute" "nosuch.invalid"))
    (tr-show (list "traceroute" "-4" "::1"))
    (tr-show (list "traceroute" "127.0.0.1"))
    (tr-show (list "traceroute" "-I" "-n" "127.0.0.1"))
    (tr-show (list "traceroute6" "::1")))
```
---
```output
stderr:
traceroute: bad address 'nosuch.invalid'
status 1
stderr:
traceroute: bad address '::1'
status 1
stderr:
traceroute: socket(AF_INET,3,1): Operation not permitted
status 1
stderr:
traceroute: socket(AF_INET,3,1): Operation not permitted
status 1
stderr:
traceroute6: socket(AF_INET6,3,58): Operation not permitted
status 1
```
