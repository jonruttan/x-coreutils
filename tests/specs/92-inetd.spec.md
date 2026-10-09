# @weight 4

inetd as busybox's.  Each case writes CONF (as printf's %b reads it) to
/tmp/x-cu-in/conf and SCRIPT to /tmp/x-cu-in/s, runs inetd in a child with
ARGS split as sh splits them -- in CONF, CONF2 and ARGS, @P is a free port of
127.0.0.1, @Q that port + 50, @U the user the spec runs as and @C the config's
path -- and makes one exchange with it.  t: one TCP connection, sent REQ and
read to its end; t2: two in turn; tl: the length of the reply; tN: its first N
bytes; t6: one connection to ::1; u: one datagram, and what comes back within
a second; ul: its length; h: CONF2 written over the config, SIGHUP, then t
with hi; w: two seconds' wait; n: none.  Then it sends SIGTERM.  The services
table names echo, discard, chargen, daytime, time and myserv as @P, for TCP
and UDP alike.  Every expectation is busybox's own output for the same case,
run as an unprivileged user: === before each reply, the status, then
stderr, and what the case's SCRIPT left in /tmp/x-cu-in/got -- the port
shown as LPORT, @Q's as QPORT.

## the fixture

### a config, an inetd, an exchange with it, and the report

```cu
(do (import x/sys/socket)
  (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-in && mkdir -p /tmp/x-cu-in"))
  (def in-f (fn (_ n) (string-append "/tmp/x-cu-in/" n)))
  (def in-lines (fn (_ s)
    (let go ((i 0) (acc ()))
      (let ((nl (%wget-index s #\newline i)))
        (if (null? nl) (reverse (if (< i (byte-len s)) (pair (substring s i (byte-len s)) acc) acc))
          (go (+ nl 1) (pair (substring s i nl) acc)))))))
  (def in-free-port (fn (_)
    (let ((l (Socket tcp-listen 0))) (let ((p (Socket local-port l))) (do (Socket close l) p)))))
  (def in-prep (fn (_ args conf script req port)
    (sys-setenv "IN_ARGS" args) (sys-setenv "IN_CONF" conf) (sys-setenv "IN_SCRIPT" script)
    (sys-setenv "IN_REQ" req) (sys-setenv "IN_PORT" (%cu-int->str port))
    (proc-run (list "/bin/sh" "-c" (string-concat (list
      "d=/tmp/x-cu-in; p=$IN_PORT; u=$(id -un); rm -f $d/got $d/log; "
      "sub() { sed -e \"s/@P/$p/g\" -e \"s/@Q/$((p+50))/g\" -e \"s/@U/$u/g\" -e \"s#@C#$d/conf#g\"; }; "
      "for s in echo discard chargen daytime time myserv; do printf '%s %s/tcp\\n%s %s/udp\\n' $s $p $s $p; done > $d/services; "
      "printf '%b' \"$IN_CONF\" | sub > $d/conf; printf '%b' \"$IN_SCRIPT\" > $d/s; "
      "printf '%b' \"$IN_REQ\" > $d/req; printf '%b' \"$IN_REQ\" | sub > $d/conf2; "
      "eval \"set -- $(printf '%s' \"$IN_ARGS\" | sub)\"; for a; do printf '%s\\n' \"$a\"; done > $d/argv"))))
    (in-lines (file-read-all (in-f "argv")))))
  (def in-start (fn (_ argv)
    (let ((pid (sys-fork)))
      (if (= pid 0)
        (do (sys-dup2 (file-open-write (in-f "log")) 2)
            (sys-exit (cu-run (pair "inetd" argv) "")))
        pid))))
  (def in-conn (fn (_ port)
    (let try ((n 0)) (let ((fd (guard (_ ()) (Socket tcp-connect "127.0.0.1" port))))
                       (if (if (null? fd) (< n 25) #f) (do (sys-usleep 20000) (try (+ n 1))) fd)))))
  (def in-conn6 (fn (_ port)
    (def fd (Sys %sign-fold (%cu-ptr-call (%in-c "socket") (%in-af (lit inet6)) 1 0)))
    (def a (%in-zeroed 16))
    (%cu-ptr-call (%in-c "inet_pton") (%in-af (lit inet6)) "::1" (%cu-str->ptr a))
    (def sa (first (%in-sockaddr6 a port)))
    (if (< (Sys %sign-fold (%cu-ptr-call (%in-c "connect") fd (%cu-str->ptr sa) 28)) 0) (do (sys-close fd) ()) fd)))
  (def in-recv (fn (_ c limit)
    (let go ((acc ""))
      (let ((r (if (if (null? limit) #f (>= (byte-len acc) limit)) () (guard (_ ()) (Socket recv-run c 4096)))))
        (if (null? r) (do (Socket close c) (if (null? limit) acc (substring acc 0 (if (< (byte-len acc) limit) (byte-len acc) limit))))
          (go (string-append acc (substring (first r) 0 (rest r)))))))))
  (def in-tcp (fn (_ c req limit)
    (if (null? c) ""
      (do (when (> (byte-len req) 0) (Socket send c req)) (Socket shutdown c) (in-recv c limit)))))
  (def in-udp (fn (_ port req)
    (let ((fd (Socket udp-connect "127.0.0.1" port)))
      (do (Socket send fd req)
          (let go ((acc ""))
            (if (null? (sys-poll (list (pair fd (list (lit in)))) 1000)) (do (Socket close fd) acc)
              (let ((r (guard (_ ()) (Socket recv-run fd 4096))))
                (if (null? r) (do (Socket close fd) acc) (go (string-append acc (substring (first r) 0 (rest r))))))))))))
  (def in-digits? (fn (_ s) (if (> (byte-len s) 1) (not (null? (%wget-digits (substring s 1 (byte-len s))))) #f)))
  (def in-exchange (fn (_ kind port pid req)
    (match ((string=? kind "t") (string-append "===\n" (in-tcp (in-conn port) req ())))
           ((string=? kind "t2") (string-concat (list "===\n" (in-tcp (in-conn port) req ()) "===\n" (in-tcp (in-conn port) req ()))))
           ((string=? kind "tl") (string-concat (list "===\n" (%cu-int->str (byte-len (in-tcp (in-conn port) req ()))) "\n")))
           ((string=? kind "t6") (string-append "===\n" (in-tcp (in-conn6 port) req ())))
           ((in-digits? kind) (string-concat (list "===\n" (in-tcp (in-conn port) req (%wget-digits (substring kind 1 (byte-len kind)))) "\n")))
           ((string=? kind "u") (string-append "===\n" (in-udp port req)))
           ((string=? kind "ul") (string-concat (list "===\n" (%cu-int->str (byte-len (in-udp port req))) "\n")))
           ((string=? kind "h")
             (do (file-write-all (in-f "conf") (file-read-all (in-f "conf2")))
                 (sys-kill pid 1) (sys-usleep 400000)
                 (string-append "===\n" (in-tcp (in-conn port) "hi\n" ()))))
           ((string=? kind "w") (do (sys-usleep 2000000) ""))
           (#t ""))))
  (def in-run (fn (_ args conf script kind req)
    (def port (in-free-port))
    (def argv (in-prep args conf script req port))
    (set! %in-services-file (in-f "services"))
    (def pid (in-start argv))
    (sys-usleep 400000)
    (def out (in-exchange kind port pid (file-read-all (in-f "req"))))
    (sys-usleep 400000)
    (sys-kill pid 15)
    (def st (sys-wait pid))
    (def got (if (file-exists? (in-f "got")) (string-concat (list "--- got\n" (file-read-all (in-f "got")) "\n")) ""))
    (let ((fd (file-open-write (in-f "raw"))))
      (do (file-write fd (string-concat (list out "[status " (%cu-int->str st) "]\n" (file-read-all (in-f "log")) got)))
          (file-close fd)))
    (proc-run (list "/bin/sh" "-c" "q=$((IN_PORT+50)); sed -E -e \"s/(^|[^0-9])$IN_PORT([^0-9]|\\$)/\\1LPORT\\2/g\" -e \"s/(^|[^0-9])$q([^0-9]|\\$)/\\1QPORT\\2/g\" -e 's/Address already in use/Address in use/' /tmp/x-cu-in/raw > /tmp/x-cu-in/norm"))
    (display (file-read-all (in-f "norm")))))
  (display "made"))
```
---
    made

## busybox's inetd

### no config file named

```cu
(in-run "" "" "" "n" "")
```
---
```output
[status 1]
inetd: non-root must specify config file
```

### an option it does not take

```cu
(in-run "-x" "" "" "n" "")
```
---
```output
[status 1]
inetd: unrecognized option: x
Usage: inetd [-fe] [-q N] [-R N] [CONFFILE]

Listen for network connections and launch programs

	-f	Run in foreground
	-e	Log to stderr
	-q N	Socket listen queue (default 128)
	-R N	Pause services after N connects/min
		(default 0 - disabled)
	Default CONFFILE is /etc/inetd.conf
```

### a config file that cannot be read

```cu
(in-run "-f -e /nonexistent" "" "" "n" "")
```
---
```output
[status 0]
inetd: /nonexistent: No such file or directory
```

### echo, stream

```cu
(in-run "-f -e @C" "echo stream tcp nowait @U internal\\n" "" "t" "hello\\n")
```
---
```output
===
hello
[status 0]
```

### echo, datagram

```cu
(in-run "-f -e @C" "echo dgram udp wait @U internal\\n" "" "u" "abc")
```
---
```output
===
abc[status 0]
```

### discard, stream

```cu
(in-run "-f -e @C" "discard stream tcp nowait @U internal\\n" "" "t" "zzz\\n")
```
---
```output
===
[status 0]
```

### discard, datagram

```cu
(in-run "-f -e @C" "discard dgram udp wait @U internal\\n" "" "u" "zzz")
```
---
```output
===
[status 0]
```

### chargen, stream: its first two lines

```cu
(in-run "-f -e @C" "chargen stream tcp nowait @U internal\\n" "" "t148" "")
```
---
```output
===
 !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefg
!"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefgh

[status 0]
```

### chargen, datagram: one line

```cu
(in-run "-f -e @C" "chargen dgram udp wait @U internal\\n" "" "u" "x")
```
---
```output
===
 !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefg
[status 0]
```

### daytime, stream: 24 characters and CRLF

```cu
(in-run "-f -e @C" "daytime stream tcp nowait @U internal\\n" "" "tl" "")
```
---
```output
===
26
[status 0]
```

### daytime, datagram

```cu
(in-run "-f -e @C" "daytime dgram udp wait @U internal\\n" "" "ul" "x")
```
---
```output
===
26
[status 0]
```

### time, stream: four bytes

```cu
(in-run "-f -e @C" "time stream tcp nowait @U internal\\n" "" "tl" "")
```
---
```output
===
4
[status 0]
```

### time, datagram

```cu
(in-run "-f -e @C" "time dgram udp wait @U internal\\n" "" "ul" "x")
```
---
```output
===
4
[status 0]
```

### a program, its stdin the connection

```cu
(in-run "-f -e @C" "@P stream tcp nowait @U /bin/sh sh /tmp/x-cu-in/s\\n" "read l; echo \"got $l\"" "t" "hello\\n")
```
---
```output
===
got hello
[status 0]
```

### a nowait program's stderr is the connection too

```cu
(in-run "-f -e @C" "@P stream tcp nowait @U /bin/sh sh /tmp/x-cu-in/s\\n" "echo out; echo err >&2" "t" "")
```
---
```output
===
out
err
[status 0]
```

### a program named by its service

```cu
(in-run "-f -e @C" "myserv stream tcp nowait @U /bin/sh sh /tmp/x-cu-in/s\\n" "echo served" "t" "")
```
---
```output
===
served
[status 0]
```

### a program with no arguments

```cu
(in-run "-f -e @C" "@P stream tcp nowait @U /bin/echo\\n" "" "t" "")
```
---
```output
===

[status 0]
```

### the arguments

```cu
(in-run "-f -e @C" "@P stream tcp nowait @U /bin/echo echo a  b\\tc\\n" "" "t" "")
```
---
```output
===
a b c
[status 0]
```

### a datagram program, nowait: connected to its sender

```cu
(in-run "-f -e @C" "@P dgram udp nowait @U /bin/sh sh /tmp/x-cu-in/s\\n" "dd bs=64 count=1 2>/dev/null" "u" "ping")
```
---
```output
===
ping[status 0]
```

### a wait program's exit status

```cu
(in-run "-f -e @C" "@P dgram udp wait @U /bin/sh sh /tmp/x-cu-in/s\\n" "dd bs=64 count=1 of=/tmp/x-cu-in/got 2>/dev/null; exit 3" "u" "data")
```
---
```output
===
[status 0]
inetd: /bin/sh: exit status 3
--- got
data
```

### a wait program killed

```cu
(in-run "-f -e @C" "@P dgram udp wait @U /bin/sh sh /tmp/x-cu-in/s\\n" "dd bs=64 count=1 of=/tmp/x-cu-in/got 2>/dev/null; kill -9 $$" "u" "data")
```
---
```output
===
[status 0]
inetd: /bin/sh: exit signal 9
--- got
data
```

### a wait program served again once it ends

```cu
(in-run "-f -e @C" "@P dgram udp wait @U /bin/sh sh /tmp/x-cu-in/s\\n" "dd bs=64 count=1 2>/dev/null >> /tmp/x-cu-in/got" "u" "one")
```
---
```output
===
[status 0]
--- got
one
```

### a program that cannot run

```cu
(in-run "-f -e @C" "@P stream tcp nowait @U /nonexistent/prog\\n" "" "t" "")
```
---
```output
===
inetd: can't execute '/nonexistent/prog': No such file or directory
[status 0]
```

### no such user

```cu
(in-run "-f -e @C" "@P stream tcp nowait nosuchuser /bin/echo echo hi\\n" "" "t" "")
```
---
```output
===
[status 0]
inetd: nosuchuser: no such user
```

### no such group

```cu
(in-run "-f -e @C" "@P stream tcp nowait @U:nosuchgrp /bin/echo echo hi\\n" "" "t" "")
```
---
```output
===
[status 0]
inetd: nosuchgrp: no such group
```

### no such group, the dot form

```cu
(in-run "-f -e @C" "@P stream tcp nowait @U.nosuchgrp /bin/echo echo hi\\n" "" "t" "")
```
---
```output
===
[status 0]
inetd: nosuchgrp: no such group
```

### another user's service

```cu
(in-run "-f -e @C" "@P stream tcp nowait root /bin/echo echo hi\\n" "" "t" "")
```
---
```output
===
[status 0]
inetd: non-root must run services as himself
```

### parse errors, each line named

```cu
(in-run "-f -e @C" "a b c\\necho stream udp nowait @U internal\\n@P stream tcp maybe @U /bin/echo\\n@P stream sctp nowait @U /bin/echo\\n@P dgram tcp wait @U /bin/echo\\n@P stream tcp nowait.x @U /bin/echo\\n@Q stream tcp nowait @U /bin/echo echo ok\\n" "" "n" "")
```
---
```output
[status 0]
inetd: parse error on line 1, line is ignored
inetd: parse error on line 2, line is ignored
inetd: parse error on line 3, line is ignored
inetd: parse error on line 4, line is ignored
inetd: parse error on line 5, line is ignored
inetd: parse error on line 6, line is ignored
```

### an unknown internal service

```cu
(in-run "-f -e @C" "foo stream tcp nowait @U internal\\necho stream tcp wait @U internal\\n@P stream tcp nowait @U /bin/echo echo ok\\n" "" "t" "")
```
---
```output
===
ok
[status 0]
inetd: unknown internal service foo
inetd: parse error on line 1, line is ignored
inetd: parse error on line 2, line is ignored
```

### an unknown service

```cu
(in-run "-f -e @C" "nosuchsvc stream tcp nowait @U /bin/echo echo hi\\n" "" "n" "")
```
---
```output
[status 0]
inetd: nosuchsvc/tcp: unknown service
```

### an unknown host

```cu
(in-run "-f -e @C" "nohost.invalid:@P stream tcp nowait @U /bin/echo echo hi\\n" "" "w" "")
```
---
```output
[status 0]
inetd: bad address 'nohost.invalid'
inetd: LPORT/tcp: unknown host 'nohost.invalid'
```

### a default host line

```cu
(in-run "-f -e @C" "127.0.0.1:\\n@P stream tcp nowait @U /bin/echo echo hi\\n" "" "t" "")
```
---
```output
===
hi
[status 0]
```

### a host list: the second address in use

```cu
(in-run "-f -e @C" "127.0.0.1,127.0.0.1:@P stream tcp nowait @U /bin/echo echo hi\\n" "" "t" "")
```
---
```output
===
hi
[status 0]
```

### two services on one port

```cu
(in-run "-f -e @C" "@P stream tcp nowait @U /bin/echo echo one\\n@P stream tcp nowait @U /bin/echo echo two\\n" "" "t" "")
```
---
```output
===
two
[status 0]
```

### comments, blank lines, a comment after the fields

```cu
(in-run "-f -e @C" "# a comment\\n\\n   \\n@P stream tcp nowait @U /bin/echo echo hi # trailing\\n" "" "t" "")
```
---
```output
===
hi
[status 0]
```

### a tab between the fields

```cu
(in-run "-f -e @C" "@P\\tstream\\ttcp\\tnowait\\t@U\\t/bin/echo\\techo\\thi\\n" "" "t" "")
```
---
```output
===
hi
[status 0]
```

### nowait.1: the second connection pauses it

```cu
(in-run "-f -e @C" "@P stream tcp nowait.1 @U /bin/echo echo hi\\n" "" "t2" "")
```
---
```output
===
hi
===
[status 0]
inetd: LPORT/tcp: too many connections, pausing
```

### -R 1: the same

```cu
(in-run "-f -e -R 1 @C" "@P stream tcp nowait @U /bin/echo echo hi\\n" "" "t2" "")
```
---
```output
===
hi
===
[status 0]
inetd: LPORT/tcp: too many connections, pausing
```

### nowait.0: no limit

```cu
(in-run "-f -e -R 1 @C" "@P stream tcp nowait.0 @U /bin/echo echo hi\\n" "" "t2" "")
```
---
```output
===
hi
===
hi
[status 0]
```

### -q accepted

```cu
(in-run "-f -e -q 5 @C" "@P stream tcp nowait @U /bin/echo echo hi\\n" "" "t" "")
```
---
```output
===
hi
[status 0]
```

### SIGHUP: the config read again

```cu
(in-run "-f -e @C" "@P stream tcp nowait @U /bin/echo echo before\\n" "" "h" "@P stream tcp nowait @U /bin/echo echo after\\n")
```
---
```output
===
after
[status 0]
```

### SIGHUP: a service dropped

```cu
(in-run "-f -e @C" "@P stream tcp nowait @U /bin/echo echo before\\n" "" "h" "@Q stream tcp nowait @U /bin/echo echo other\\n")
```
---
```output
===
[status 0]
```

### tcp6

```cu
(in-run "-f -e @C" "@P stream tcp6 nowait @U /bin/echo echo six\\n" "" "t6" "")
```
---
```output
===
six
[status 0]
```

### tcp6, an IPv4 client

```cu
(in-run "-f -e @C" "@P stream tcp6 nowait @U /bin/echo echo six\\n" "" "t" "")
```
---
```output
===
six
[status 0]
```

### without -e: nothing on stderr

```cu
(in-run "-f @C" "nosuchsvc stream tcp nowait @U /bin/echo echo hi\\n" "" "n" "")
```
---
```output
[status 0]
```
