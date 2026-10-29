# @weight 1

busybox's ping and ping6 (networking/ping.c, FEATURE_FANCY_PING), as far as
a run without root reaches: the usage, the options' numbers, the address,
and the raw socket refused.  The replies are tested as root in the Linux
leg.  Every expectation is busybox 1.36.1's in alpine.  A `|` marks the end
of each line written to standard output.

## the fixture

### a run of ping, what it writes and its status

```cu
(do (def pn-f (fn (_ n) (string-append "/tmp/x-cu-pn." n)))
    (def pn-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (pn-f "out"))) (ee (file-open-write (pn-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (Str8 replace "\n" "|\n" (file-read-all (pn-f "out"))) "stderr:\n"
                                              (file-read-all (pn-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the usage

### no host, and two, are the usage

```cu
(do (pn-show (list "ping")) (pn-show (list "ping" "a" "b")))
```
---
```output
stderr:
Usage: ping [OPTIONS] HOST

Send ICMP ECHO_REQUESTs to HOST

	-4,-6		Force IP or IPv6 name resolution
	-c CNT		Send only CNT pings
	-s SIZE		Send SIZE data bytes in packets (default 56)
	-i SECS		Interval
	-A		Ping as soon as reply is received
	-t TTL		Set TTL
	-I IFACE/IP	Source interface or IP address
	-W SEC		Seconds to wait for the first response (default 10)
			(after all -c CNT packets are sent)
	-w SEC		Seconds until ping exits (default:infinite)
			(can exit earlier with -c CNT)
	-q		Quiet, only display output at start/finish
	-p HEXBYTE	Payload pattern
status 1
stderr:
Usage: ping [OPTIONS] HOST

Send ICMP ECHO_REQUESTs to HOST

	-4,-6		Force IP or IPv6 name resolution
	-c CNT		Send only CNT pings
	-s SIZE		Send SIZE data bytes in packets (default 56)
	-i SECS		Interval
	-A		Ping as soon as reply is received
	-t TTL		Set TTL
	-I IFACE/IP	Source interface or IP address
	-W SEC		Seconds to wait for the first response (default 10)
			(after all -c CNT packets are sent)
	-w SEC		Seconds until ping exits (default:infinite)
			(can exit earlier with -c CNT)
	-q		Quiet, only display output at start/finish
	-p HEXBYTE	Payload pattern
status 1
```

### ping6's leaves out -4,-6 and -t

```cu
(pn-show (list "ping6"))
```
---
```output
stderr:
Usage: ping6 [OPTIONS] HOST

Send ICMP ECHO_REQUESTs to HOST

	-c CNT		Send only CNT pings
	-s SIZE		Send SIZE data bytes in packets (default 56)
	-i SECS		Interval
	-A		Ping as soon as reply is received
	-I IFACE/IP	Source interface or IP address
	-W SEC		Seconds to wait for the first response (default 10)
			(after all -c CNT packets are sent)
	-w SEC		Seconds until ping exits (default:infinite)
			(can exit earlier with -c CNT)
	-q		Quiet, only display output at start/finish
	-p HEXBYTE	Payload pattern
status 1
```

## the numbers

### -c past INT_MAX is out of range, past UINT_MAX no number; -s to 65535, -p a hex byte

```cu
(do (pn-show (list "ping" "-c" "x" "1.2.3.4"))
    (pn-show (list "ping" "-c" "3000000000" "h"))
    (pn-show (list "ping" "-c" "99999999999" "1.2.3.4"))
    (pn-show (list "ping" "-c" "+5" "h"))
    (pn-show (list "ping" "-s" "70000" "h"))
    (pn-show (list "ping" "-s" "99999999999" "h"))
    (pn-show (list "ping" "-p" "zz" "h"))
    (pn-show (list "ping" "-p" "100" "h"))
    (pn-show (list "ping" "-p" "0x" "h")))
```
---
```output
stderr:
ping: invalid number 'x'
status 1
stderr:
ping: number 3000000000 is not in 0..2147483647 range
status 1
stderr:
ping: invalid number '99999999999'
status 1
stderr:
ping: invalid number '+5'
status 1
stderr:
ping: number 70000 is not in 0..65535 range
status 1
stderr:
ping: invalid number '99999999999'
status 1
stderr:
ping: invalid number 'zz'
status 1
stderr:
ping: number 100 is not in 0..255 range
status 1
stderr:
ping: invalid number '0x'
status 1
```

### -i: a suffix after a fraction is read after a 1, a bad fraction is the usage

```cu
(do (pn-show (list "ping" "-i" "x" "h"))
    (pn-show (list "ping" "-i" "1.x" "h"))
    (pn-show (list "ping" "-i" "1.5x" "h"))
    (pn-show (list "ping" "-i" "2m5" "h"))
    (pn-show (list "ping" "-i" "1.2.3" "h"))
    (pn-show (list "ping" "-i" "." "h")))
```
---
```output
stderr:
ping: invalid number 'x'
status 1
stderr:
ping: invalid number '1x'
status 1
stderr:
ping: invalid number '1x'
status 1
stderr:
ping: invalid number '2m5'
status 1
stderr:
Usage: ping [OPTIONS] HOST

Send ICMP ECHO_REQUESTs to HOST

	-4,-6		Force IP or IPv6 name resolution
	-c CNT		Send only CNT pings
	-s SIZE		Send SIZE data bytes in packets (default 56)
	-i SECS		Interval
	-A		Ping as soon as reply is received
	-t TTL		Set TTL
	-I IFACE/IP	Source interface or IP address
	-W SEC		Seconds to wait for the first response (default 10)
			(after all -c CNT packets are sent)
	-w SEC		Seconds until ping exits (default:infinite)
			(can exit earlier with -c CNT)
	-q		Quiet, only display output at start/finish
	-p HEXBYTE	Payload pattern
status 1
stderr:
Usage: ping [OPTIONS] HOST

Send ICMP ECHO_REQUESTs to HOST

	-4,-6		Force IP or IPv6 name resolution
	-c CNT		Send only CNT pings
	-s SIZE		Send SIZE data bytes in packets (default 56)
	-i SECS		Interval
	-A		Ping as soon as reply is received
	-t TTL		Set TTL
	-I IFACE/IP	Source interface or IP address
	-W SEC		Seconds to wait for the first response (default 10)
			(after all -c CNT packets are sent)
	-w SEC		Seconds until ping exits (default:infinite)
			(can exit earlier with -c CNT)
	-q		Quiet, only display output at start/finish
	-p HEXBYTE	Payload pattern
status 1
```

## the address

### a name with no address, a bad port, an unclosed bracket, and an IPv6 address for -4

```cu
(do (pn-show (list "ping" "nosuch.invalid"))
    (pn-show (list "ping" "1.2.3.4:99999"))
    (pn-show (list "ping" "[::1"))
    (pn-show (list "ping" "-4" "::1"))
    (pn-show (list "ping" "-I" "1.2.3" "nosuch.invalid")))
```
---
```output
stderr:
ping: bad address 'nosuch.invalid'
status 1
stderr:
ping: bad port '99999'
status 1
stderr:
ping: bad address '[::1'
status 1
stderr:
ping: bad address '::1'
status 1
stderr:
ping: bad address 'nosuch.invalid'
status 1
```

## the socket

### without root the raw socket is refused, after the PING line

```cu
(do (pn-show (list "ping" "-c" "1" "127.0.0.1"))
    (pn-show (list "ping" "-s" "8" "[127.0.0.1]:7"))
    (pn-show (list "ping6" "::1")))
```
---
```output
PING 127.0.0.1 (127.0.0.1): 56 data bytes|
stderr:
ping: permission denied (are you root?)
status 1
PING [127.0.0.1]:7 (127.0.0.1): 8 data bytes|
stderr:
ping: permission denied (are you root?)
status 1
PING ::1 (::1): 56 data bytes|
stderr:
ping6: permission denied (are you root?)
status 1
```
