# @weight 2

pscan as busybox 1.36.1's, scanning this host only.  Each case runs pscan
with ARGS in a child, after two TCP listeners are opened at 31811 and 31813
where the case asks for them, so that a scan of 31810 to 31814 finds those
two open and the rest closed; the range sits below the ephemeral ports of
Linux and Darwin.  The service names come from the host's /etc/services
through getservbyport, as busybox's do.  Every expectation is busybox's own
output for the same case, in alpine 3.20: stdout, the status, then stderr.

## the fixture

### listeners, a pscan, and the report

```cu
(do (import x/sys/socket)
  (def ps (fn (_ args listen?)
    (cu-heap-collect)
    (def ls (if listen?
              (list (Socket tcp-listen-on "127.0.0.1" 31811) (Socket tcp-listen-on "127.0.0.1" 31813))
              ()))
    (def pid (sys-fork))
    (when (= pid 0)
      (do (let ((o (file-open-write "/tmp/x-cu-pscan.so"))) (do (sys-dup2 o 1) (sys-close o)))
          (let ((e (file-open-write "/tmp/x-cu-pscan.se"))) (do (sys-dup2 e 2) (sys-close e)))
          (sys-exit (guard (e (do (file-write 2 "uncaught\n") 99)) (cu-run (pair "pscan" args) "")))))
    (def st (sys-wait pid))
    (List for-each (fn (_ l) (Socket close l)) ls)
    (display (%str-concat (list (file-read-all "/tmp/x-cu-pscan.so") "[status " (cu-int->str st) "]\n"
                                  (file-read-all "/tmp/x-cu-pscan.se"))))))
  (display "made"))
```
---
    made

## scans

### two open ports in a range, the opens only

```cu
(ps (list "-p" "31810" "-P" "31814" "127.0.0.1") #t)
```
---
```output
Scanning 127.0.0.1 ports 31810 to 31814
 Port	Proto	State	Service
31811	tcp	open	unknown
31813	tcp	open	unknown
3 closed, 2 open, 0 timed out (or blocked) ports
[status 0]
```

### every port of a range, closed and open

```cu
(ps (list "-c" "-b" "-p" "31810" "-P" "31814" "127.0.0.1") #t)
```
---
```output
Scanning 127.0.0.1 ports 31810 to 31814
 Port	Proto	State	Service
31810	tcp	closed	unknown
31811	tcp	open	unknown
31812	tcp	closed	unknown
31813	tcp	open	unknown
31814	tcp	closed	unknown
3 closed, 2 open, 0 timed out (or blocked) ports
[status 0]
```

### a closed port with no service

```cu
(ps (list "-c" "-p" "31810" "-P" "31810" "127.0.0.1") #f)
```
---
```output
Scanning 127.0.0.1 ports 31810 to 31810
 Port	Proto	State	Service
31810	tcp	closed	unknown
1 closed, 0 open, 0 timed out (or blocked) ports
[status 0]
```

### low ports, named from the services file

```cu
(ps (list "-c" "-p" "7" "-P" "9" "127.0.0.1") #f)
```
---
```output
Scanning 127.0.0.1 ports 7 to 9
 Port	Proto	State	Service
    7	tcp	closed	echo
    8	tcp	closed	unknown
    9	tcp	closed	discard
3 closed, 0 open, 0 timed out (or blocked) ports
[status 0]
```

### an IPv6 address

```cu
(ps (list "-c" "-p" "31810" "-P" "31811" "::1") #f)
```
---
```output
Scanning ::1 ports 31810 to 31811
 Port	Proto	State	Service
31810	tcp	closed	unknown
31811	tcp	closed	unknown
2 closed, 0 open, 0 timed out (or blocked) ports
[status 0]
```

### a name

```cu
(ps (list "-c" "-p" "31810" "-P" "31810" "localhost") #f)
```
---
```output
Scanning localhost ports 31810 to 31810
 Port	Proto	State	Service
31810	tcp	closed	unknown
1 closed, 0 open, 0 timed out (or blocked) ports
[status 0]
```

### a host with a port, the port ignored

```cu
(ps (list "-c" "-p" "31810" "-P" "31810" "127.0.0.1:80") #f)
```
---
```output
Scanning 127.0.0.1:80 ports 31810 to 31810
 Port	Proto	State	Service
31810	tcp	closed	unknown
1 closed, 0 open, 0 timed out (or blocked) ports
[status 0]
```

## refusals

### a min port below one

```cu
(ps (list "-p" "0" "127.0.0.1") #f)
```
---
```output
[status 1]
pscan: number 0 is not in 1..1024 range
```

### a max port above the ceiling

```cu
(ps (list "-P" "70000" "127.0.0.1") #f)
```
---
```output
[status 1]
pscan: number 70000 is not in 1..65535 range
```

### a min above the max

```cu
(ps (list "-p" "2000" "-P" "1000" "127.0.0.1") #f)
```
---
```output
[status 1]
pscan: number 2000 is not in 1..1000 range
```

### a min that is not a number

```cu
(ps (list "-p" "x" "127.0.0.1") #f)
```
---
```output
[status 1]
pscan: invalid number 'x'
```

### a min with a sign

```cu
(ps (list "-p" "+5" "127.0.0.1") #f)
```
---
```output
[status 1]
pscan: invalid number '+5'
```

### a timeout of zero

```cu
(ps (list "-t" "0" "127.0.0.1") #f)
```
---
```output
[status 1]
pscan: number 0 is not in 1..536870 range
```

### an rtt past the ceiling

```cu
(ps (list "-T" "536871" "127.0.0.1") #f)
```
---
```output
[status 1]
pscan: number 536871 is not in 1..536870 range
```

### the rtt read before the timeout

```cu
(ps (list "-t" "99" "-T" "536871" "127.0.0.1") #f)
```
---
```output
[status 1]
pscan: number 536871 is not in 1..536870 range
```

### a min above a thirty-two-bit unsigned

```cu
(ps (list "-p" "4294967296" "127.0.0.1") #f)
```
---
```output
[status 1]
pscan: invalid number '4294967296'
```

### a host that will not resolve

```cu
(ps (list "-p" "5" "-P" "5" "nosuchhost.invalid") #f)
```
---
```output
[status 1]
pscan: bad address 'nosuchhost.invalid'
```

### an unclosed IPv6 bracket

```cu
(ps (list "-p" "5" "-P" "5" "[::1") #f)
```
---
```output
[status 1]
pscan: bad address '[::1'
```

### no host

```cu
(ps (list ) #f)
```
---
```output
[status 1]
Usage: pscan [-cb] [-p MIN_PORT] [-P MAX_PORT] [-t TIMEOUT] [-T MIN_RTT] HOST

Scan HOST, print all open ports

	-c	Show closed ports too
	-b	Show blocked ports too
	-p PORT	Scan from this port (default 1)
	-P PORT	Scan up to this port (default 1024)
	-t MS	Timeout (default 5000 ms)
	-T MS	Minimum rtt (default 5 ms)
```

### two hosts

```cu
(ps (list "a" "b") #f)
```
---
```output
[status 1]
Usage: pscan [-cb] [-p MIN_PORT] [-P MAX_PORT] [-t TIMEOUT] [-T MIN_RTT] HOST

Scan HOST, print all open ports

	-c	Show closed ports too
	-b	Show blocked ports too
	-p PORT	Scan from this port (default 1)
	-P PORT	Scan up to this port (default 1024)
	-t MS	Timeout (default 5000 ms)
	-T MS	Minimum rtt (default 5 ms)
```
