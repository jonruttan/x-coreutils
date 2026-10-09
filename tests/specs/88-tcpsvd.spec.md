# @weight 2

tcpsvd and udpsvd as busybox's.  Each listener case runs the applet in a child
on a free port of 127.0.0.1, with ARGS split as sh splits them and P the
port, makes one exchange with it -- t: one TCP connection, sent REQ (as
printf's %b reads it) and read to its end; tt: two, the first held open while
the second is made; u: one datagram, and what comes back within a second --
then sends it SIGTERM.  Every expectation is busybox's own output for the same
exchange: === before each reply, the status, then stderr, with the port
shown as LPORT, a peer's as RPORT and a pid as PID.

## the fixture

### a listener, an exchange with it, and the report

```cu
(do (import x/sys/socket)
  (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-ts && mkdir -p /tmp/x-cu-ts"))
  (def ts-f (fn (_ n) (string-append "/tmp/x-cu-ts/" n)))
  (def ts-lines (fn (_ s)
    (let go ((i 0) (acc ()))
      (let ((nl (%wget-index s #\newline i)))
        (if (null? nl) (reverse (if (< i (byte-len s)) (pair (substring s i (byte-len s)) acc) acc))
          (go (+ nl 1) (pair (substring s i nl) acc)))))))
  (def ts-free-port (fn (_)
    (let ((l (Socket tcp-listen 0))) (let ((p (Socket local-port l))) (do (Socket close l) p)))))
  (def ts-prep (fn (_ args port req)
    (sys-setenv "TS_ARGS" args) (sys-setenv "TS_REQ" req) (sys-setenv "TS_PORT" (%cu-int->str port))
    (proc-run (list "/bin/sh" "-c" "eval \"set -- $(printf '%s' \"$TS_ARGS\" | sed \"s/ P / $TS_PORT /\")\"; for a; do printf '%s\\n' \"$a\"; done > /tmp/x-cu-ts/argv; printf '%b' \"$TS_REQ\" > /tmp/x-cu-ts/req"))
    (pair (ts-lines (file-read-all (ts-f "argv"))) (file-read-all (ts-f "req")))))
  (def ts-start (fn (_ app argv)
    (let ((pid (sys-fork)))
      (if (= pid 0)
        (do (sys-dup2 (file-open-write (ts-f "log")) 2)
            (sys-exit (cu-run (pair app argv) "")))
        pid))))
  (def ts-conn (fn (_ port)
    (let try ((n 0)) (let ((fd (guard (_ ()) (Socket tcp-connect "127.0.0.1" port))))
                       (if (if (null? fd) (< n 200) #f) (do (sys-usleep 20000) (try (+ n 1))) fd)))))
  (def ts-recv-all (fn (_ c)
    (let go ((acc "")) (let ((r (Socket recv-run c 4096)))
                         (if (null? r) (do (Socket close c) acc)
                           (go (string-append acc (substring (first r) 0 (rest r)))))))))
  (def ts-send (fn (_ port req)
    (let ((c (ts-conn port)))
      (do (when (> (byte-len req) 0) (Socket send c req)) (Socket shutdown c) c))))
  (def ts-udp (fn (_ port req)
    (sys-usleep 400000)
    (let ((fd (Socket udp-connect "127.0.0.1" port)))
      (do (Socket send fd req)
          (let go ((acc ""))
            (if (null? (sys-poll (list (pair fd (list (lit in)))) 1000)) (do (Socket close fd) acc)
              (let ((r (Socket recv-run fd 4096))) (go (string-append acc (substring (first r) 0 (rest r)))))))))))
  (def ts-exchange (fn (_ kind port req)
    (match ((string=? kind "t") (string-append "===\n" (ts-recv-all (ts-send port req))))
           ((string=? kind "tt")
             (let ((c1 (ts-send port req)))
               (do (sys-usleep 300000)
                   (let ((second (ts-recv-all (ts-send port req))))
                     (do (sys-usleep 1000000)
                         (string-concat (list "===\n" second "===\n" (ts-recv-all c1))))))))
           (#t (string-append "===\n" (ts-udp port req))))))
  (def ts-run (fn (_ app args kind req)
    (def port (ts-free-port))
    (def pr (ts-prep args port req))
    (def pid (ts-start app (first pr)))
    (def out (ts-exchange kind port (rest pr)))
    (sys-usleep 400000)
    (sys-kill pid 15)
    (def st (sys-wait pid))
    (let ((fd (file-open-write (ts-f "raw"))))
      (do (file-write fd (string-concat (list out "[status " (%cu-int->str st) "]\n" (file-read-all (ts-f "log")))))
          (file-close fd)))
    (proc-run (list "/bin/sh" "-c" "sed -E -e \"s/:$TS_PORT([^0-9]|\\$)/:LPORT\\1/g\" -e 's/127\\.0\\.0\\.1:[0-9]+/127.0.0.1:RPORT/g' -e 's/(start|end) [0-9]+/\\1 PID/' -e 's/Address already in use/Address in use/' /tmp/x-cu-ts/raw > /tmp/x-cu-ts/norm"))
    (display (file-read-all (ts-f "norm")))))
  (display "made"))
```
---
    made

## a listener

### the environment

```cu
(ts-run "tcpsvd" "127.0.0.1 P sh -c 'env | grep -E \"^(PROTO|TCP)\" | sort'" "t" "")
```
---
```output
===
PROTO=TCP
TCPLOCALADDR=127.0.0.1:LPORT
TCPREMOTEADDR=127.0.0.1:RPORT
[status 143]
```

### -E: none of it

```cu
(ts-run "tcpsvd" "-E 127.0.0.1 P sh -c 'env | grep -c -E \"^(PROTO|TCP)\"'" "t" "")
```
---
```output
===
0
[status 143]
```

### stdin is the connection

```cu
(ts-run "tcpsvd" "127.0.0.1 P sh -c 'read l; echo \"got $l\"'" "t" "hello\\n")
```
---
```output
===
got hello
[status 143]
```

### -v: listening, start, status, end, the signal

```cu
(ts-run "tcpsvd" "-v 127.0.0.1 P sh -c 'echo hi'" "t" "")
```
---
```output
===
hi
[status 143]
tcpsvd: listening on 127.0.0.1:LPORT, starting
tcpsvd: start PID 127.0.0.1:LPORT-127.0.0.1:RPORT
tcpsvd: status 1/30
tcpsvd: end PID exit 0
tcpsvd: status 0/30
tcpsvd: got signal 15, exit
```

### -v: an exit status

```cu
(ts-run "tcpsvd" "-v -E 127.0.0.1 P sh -c 'exit 3'" "t" "")
```
---
```output
===
[status 143]
tcpsvd: listening on 127.0.0.1:LPORT, starting
tcpsvd: start PID 127.0.0.1:LPORT-127.0.0.1:RPORT
tcpsvd: status 1/30
tcpsvd: end PID exit 3
tcpsvd: status 0/30
tcpsvd: got signal 15, exit
```

### -v: a child killed

```cu
(ts-run "tcpsvd" "-v 127.0.0.1 P sh -c 'kill -9 $$'" "t" "")
```
---
```output
===
[status 143]
tcpsvd: listening on 127.0.0.1:LPORT, starting
tcpsvd: start PID 127.0.0.1:LPORT-127.0.0.1:RPORT
tcpsvd: status 1/30
tcpsvd: end PID signal 9
tcpsvd: status 0/30
tcpsvd: got signal 15, exit
```

### -h -l NAME: the names

```cu
(ts-run "tcpsvd" "-v -h -l myhost 127.0.0.1 P sh -c 'echo $TCPLOCALHOST $TCPREMOTEHOST'" "t" "")
```
---
```output
===
myhost localhost
[status 143]
tcpsvd: listening on 127.0.0.1:LPORT, starting
tcpsvd: start PID 127.0.0.1:LPORT-127.0.0.1:RPORT (myhost-localhost)
tcpsvd: status 1/30
tcpsvd: end PID exit 0
tcpsvd: status 0/30
tcpsvd: got signal 15, exit
```

### -h: the local name looked up too

```cu
(ts-run "tcpsvd" "-h 127.0.0.1 P sh -c 'echo $TCPLOCALHOST $TCPREMOTEHOST'" "t" "")
```
---
```output
===
localhost localhost
[status 143]
```

### -c 1: no status lines

```cu
(ts-run "tcpsvd" "-v -c 1 127.0.0.1 P sh -c 'echo hi'" "t" "")
```
---
```output
===
hi
[status 143]
tcpsvd: listening on 127.0.0.1:LPORT, starting
tcpsvd: start PID 127.0.0.1:LPORT-127.0.0.1:RPORT
tcpsvd: end PID exit 0
tcpsvd: got signal 15, exit
```

### -C 1:MSG: a second connection from the address refused with MSG

```cu
(ts-run "tcpsvd" "-C 1:busy 127.0.0.1 P sh -c 'sleep 0.6; echo slow'" "tt" "")
```
---
```output
===
busy===
slow
[status 143]
```

### -C 1 -v: the concurrency line, the address without its port

```cu
(ts-run "tcpsvd" "-v -C 1 127.0.0.1 P sh -c 'echo $TCPREMOTEADDR $TCPCONCURRENCY'" "t" "")
```
---
```output
===
127.0.0.1 1
[status 143]
tcpsvd: listening on 127.0.0.1:LPORT, starting
tcpsvd: concurrency 127.0.0.1 1/1
tcpsvd: start PID 127.0.0.1:LPORT-127.0.0.1
tcpsvd: status 1/30
tcpsvd: end PID exit 0
tcpsvd: status 0/30
tcpsvd: got signal 15, exit
```

### PROG that cannot run

```cu
(ts-run "tcpsvd" "-v 127.0.0.1 P /nonexistent/prog" "t" "")
```
---
```output
===
[status 143]
tcpsvd: listening on 127.0.0.1:LPORT, starting
tcpsvd: start PID 127.0.0.1:LPORT-127.0.0.1:RPORT
tcpsvd: can't execute '/nonexistent/prog': No such file or directory
tcpsvd: status 1/30
tcpsvd: end PID exit 127
tcpsvd: status 0/30
tcpsvd: got signal 15, exit
```

### host 0: every interface

```cu
(ts-run "tcpsvd" "-v 0 P sh -c 'echo $TCPLOCALADDR'" "t" "")
```
---
```output
===
127.0.0.1:LPORT
[status 143]
tcpsvd: listening on 0.0.0.0:LPORT, starting
tcpsvd: start PID 127.0.0.1:LPORT-127.0.0.1:RPORT
tcpsvd: status 1/30
tcpsvd: end PID exit 0
tcpsvd: status 0/30
tcpsvd: got signal 15, exit
```

### -i -x -t -p accepted

```cu
(ts-run "tcpsvd" "-i d -x c -t 3 -p -l me 127.0.0.1 P sh -c 'echo $TCPLOCALHOST'" "t" "")
```
---
```output
===
me
[status 143]
```

### udpsvd: the environment and the datagram

```cu
(ts-run "udpsvd" "-v 127.0.0.1 P sh -c 'env | grep -E \"^(PROTO|UDP)\" | sort; head -c 3'" "u" "abc")
```
---
```output
===
PROTO=UDP
UDPLOCALADDR=127.0.0.1:LPORT
UDPREMOTEADDR=127.0.0.1:RPORT
abc[status 143]
udpsvd: listening on 127.0.0.1:LPORT, starting
udpsvd: start PID 127.0.0.1:LPORT-127.0.0.1:RPORT
udpsvd: status 1/30
udpsvd: end PID exit 0
udpsvd: status 0/30
udpsvd: got signal 15, exit
```

### udpsvd -E

```cu
(ts-run "udpsvd" "-E 127.0.0.1 P sh -c 'env | grep -c -E \"^(PROTO|UDP)\"; head -c 2'" "u" "xy")
```
---
```output
===
0
xy[status 143]
```

## what ends a run

Each run below ends before it serves: stdout with a `|` at the end of each
line, then stderr less the banner line busybox's usage text starts with, then
the status.  The `-u 0` case binds port 0 -- any free one -- and the suite runs
as a user who is not root, as busybox's own check of this does.

### the fixture: a run of an applet, with its stdout, stderr and status

```cu
(do (def nf (fn (_ n) (string-append "/tmp/x-cu-ts/" n))) (def run (fn (_ argv in) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv in)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (Str8 replace "\n" "|\n" (file-read-all (nf ".out"))) "stderr:\n" (Str8 replace "Address already in use" "Address in use" (file-read-all (nf ".err"))) "status " (%cu-int->str st) "\n")))))))) (display "made"))
```
---
    made

### tcpsvd: fewer than three operands

```cu
(run (list "tcpsvd" "1" "2") "")
```
---
```output
stderr:
Usage: tcpsvd [-hEv] [-c N] [-C N[:MSG]] [-b N] [-u USER] [-l NAME] IP PORT PROG

Create TCP socket, bind to IP:PORT and listen for incoming connections.
Run PROG for each connection.

	IP PORT		IP:PORT to listen on
	PROG ARGS	Program to run
	-u USER[:GRP]	Change to user/group after bind
	-c N		Up to N connections simultaneously (default 30)
	-b N		Allow backlog of approximately N TCP SYNs (default 20)
	-C N[:MSG]	Allow only up to N connections from the same IP:
			new connections from this IP address are closed
			immediately, MSG is written to the peer before close
	-E		Don't set up environment
	-h		Look up peer's hostname
	-l NAME		Local hostname (else look up local hostname in DNS)
	-v		Verbose

Environment if no -E:
PROTO='TCP'
TCPREMOTEADDR='ip:port' ('[ip]:port' for IPv6)
TCPLOCALADDR='ip:port'
TCPORIGDSTADDR='ip:port' of destination before firewall
	Useful for REDIRECTed-to-local connections:
	iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to 8080
TCPCONCURRENCY=num_of_connects_from_this_ip
If -h:
TCPLOCALHOST='hostname' (-l NAME is used if specified)
TCPREMOTEHOST='hostname'
status 1
```

### udpsvd: fewer than three operands

```cu
(run (list "udpsvd" "1" "2") "")
```
---
```output
stderr:
Usage: udpsvd [-hEv] [-c N] [-u USER] [-l NAME] IP PORT PROG

Create UDP socket, bind to IP:PORT and wait for incoming packets.
Run PROG for each packet, redirecting all further packets with same
peer ip:port to it.

	IP PORT		IP:PORT to listen on
	PROG ARGS	Program to run
	-u USER[:GRP]	Change to user/group after bind
	-c N		Up to N connections simultaneously (default 30)
	-E		Don't set up environment
	-h		Look up peer's hostname
	-l NAME		Local hostname (else look up local hostname in DNS)
	-v		Verbose

Environment if no -E:
PROTO='UDP'
UDPREMOTEADDR='ip:port' ('[ip]:port' for IPv6)
UDPLOCALADDR='ip:port'
If -h:
UDPLOCALHOST='hostname' (-l NAME is used if specified)
UDPREMOTEHOST='hostname'
status 1
```

### -c: not a number

```cu
(run (list "tcpsvd" "-c" "x" "127.0.0.1" "7010" "true") "")
```
---
```output
stderr:
tcpsvd: invalid number 'x'
status 1
```

### -b: not a number

```cu
(run (list "tcpsvd" "-b" "9x" "127.0.0.1" "7010" "true") "")
```
---
```output
stderr:
tcpsvd: invalid number '9x'
status 1
```

### -C: N followed by other than :MSG

```cu
(run (list "tcpsvd" "-C" "2x" "127.0.0.1" "7010" "true") "")
```
---
```output
stderr:
Usage: tcpsvd [-hEv] [-c N] [-C N[:MSG]] [-b N] [-u USER] [-l NAME] IP PORT PROG

Create TCP socket, bind to IP:PORT and listen for incoming connections.
Run PROG for each connection.

	IP PORT		IP:PORT to listen on
	PROG ARGS	Program to run
	-u USER[:GRP]	Change to user/group after bind
	-c N		Up to N connections simultaneously (default 30)
	-b N		Allow backlog of approximately N TCP SYNs (default 20)
	-C N[:MSG]	Allow only up to N connections from the same IP:
			new connections from this IP address are closed
			immediately, MSG is written to the peer before close
	-E		Don't set up environment
	-h		Look up peer's hostname
	-l NAME		Local hostname (else look up local hostname in DNS)
	-v		Verbose

Environment if no -E:
PROTO='TCP'
TCPREMOTEADDR='ip:port' ('[ip]:port' for IPv6)
TCPLOCALADDR='ip:port'
TCPORIGDSTADDR='ip:port' of destination before firewall
	Useful for REDIRECTed-to-local connections:
	iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to 8080
TCPCONCURRENCY=num_of_connects_from_this_ip
If -h:
TCPLOCALHOST='hostname' (-l NAME is used if specified)
TCPREMOTEHOST='hostname'
status 1
```

### an address that does not resolve

```cu
(run (list "tcpsvd" "nosuchhost.invalid" "7010" "true") "")
```
---
```output
stderr:
tcpsvd: bad address 'nosuchhost.invalid'
status 1
```

### a port past 65535

```cu
(run (list "tcpsvd" "127.0.0.1" "99999" "true") "")
```
---
```output
stderr:
tcpsvd: bad port '99999'
status 1
```

### a port no service names

```cu
(run (list "tcpsvd" "127.0.0.1" "nosuchservice" "true") "")
```
---
```output
stderr:
tcpsvd: bad port 'nosuchservice'
status 1
```

### udpsvd: a port no service names

```cu
(run (list "udpsvd" "127.0.0.1" "nosuchservice" "true") "")
```
---
```output
stderr:
udpsvd: bad port 'nosuchservice'
status 1
```

### -u: an unknown user

```cu
(run (list "tcpsvd" "-u" "nosuchuser" "127.0.0.1" "7010" "true") "")
```
---
```output
stderr:
tcpsvd: unknown user/group nosuchuser
status 1
```

### -u: a user who is not root cannot take the group

```cu
(run (list "tcpsvd" "-u" "0" "127.0.0.1" "0" "true") "")
```
---
```output
stderr:
tcpsvd: setgid: Operation not permitted
status 1
```

### a port another socket holds

```cu
(let ((l (Socket tcp-listen-on "127.0.0.1" 0)))
  (do (run (list "tcpsvd" "127.0.0.1" (%cu-int->str (Socket local-port l)) "true") "") (Socket close l)))
```
---
```output
stderr:
tcpsvd: bind: Address in use
status 1
```
