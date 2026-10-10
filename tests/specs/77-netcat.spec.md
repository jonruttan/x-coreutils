# @weight 2

netcat as busybox's: nc under its other name, its messages and usage text
named netcat (busybox-all, as the plain build has no netcat).  Each case runs
netcat in a forked child, its standard input a file holding the case's input,
its standard output and error captured; the peer is a second child.  A client
case's peer listens on the case's port, P in its arguments, sends its reply
a fifth of a second after the connection, shuts its write side and records
what arrives; a listen case's peer connects to that port, sends "hi\n",
shuts its write side and records the answer.  Every expectation is busybox's
own output for the same peer and arguments; the report gives stdout, stderr,
the status and what the peer received, the port spelled PORT.

## the fixture

### a peer, an nc, and the report

```cu
(do (import x/sys/socket) (def nd "/tmp/x-cu-net.nc") (def nd-took 0) (def nd-f (fn (_ n) (string-append nd n))) (def nd-drain (fn (_ c) (let ((fd (file-open-write (nd-f "/peer")))) (do (let go () (let ((r (file-read-run c 4096))) (unless (= (rest r) 0) (do (file-write-run fd r) (go))))) (file-close fd))))) (def nd-exit (fn (_) (sys-exec "/bin/sh" (list "-c" "exit 0")))) (def nd-server (fn (_ lfd reply) (do (guard (_ ()) (let ((c (Socket accept lfd))) (do (sys-usleep (if (string=? reply "HOLD") 4000000 200000)) (unless (if (string=? reply "") #t (string=? reply "HOLD")) (Socket send c reply)) (Socket shutdown c) (nd-drain c) (Socket close c)))) (nd-exit)))) (def nd-client (fn (_ port) (do (guard (_ ()) (do (sys-usleep 300000) (let ((c (Socket tcp-connect "127.0.0.1" port))) (do (Socket send c "hi\n") (Socket shutdown c) (nd-drain c) (Socket close c))))) (nd-exit)))) (def nd-nc (fn (_ argv input) (do (if (pair? input) (let ((fd (file-open-write (nd-f "/in")))) (do (file-write-run fd input) (file-close fd))) (file-write-all (nd-f "/in") input)) (def pid (sys-fork)) (when (= pid 0) (do (sys-dup2 (file-open-read (nd-f "/in")) 0) (sys-dup2 (file-open-write (nd-f "/out")) 1) (sys-dup2 (file-open-write (nd-f "/err")) 2) (sys-exit (guard (_ 99) (cu-run (pair "netcat" argv) ""))))) (sys-wait pid)))) (def nc-case (fn (_ name mode reply input args) (do (proc-run (list "/bin/sh" "-c" (string-concat (list "rm -rf " nd " && mkdir -p " nd " && : > " nd "/peer")))) (def lfd (Socket tcp-listen 0)) (def port (Socket local-port lfd)) (def ps (%cu-int->str port)) (def peer (match ((string=? mode "client") (let ((p (sys-fork))) (do (when (= p 0) (nd-server lfd reply)) p))) ((string=? mode "listen") (do (Socket close lfd) (let ((p (sys-fork))) (do (when (= p 0) (nd-client port)) p)))) (#t (do (Socket close lfd) 0)))) (when (string=? mode "client") (Socket close lfd)) (def t0 (date-now-unix)) (def st (nd-nc (map (fn (_ a) (if (string=? a "P") ps a)) args) input)) (set! nd-took (- (date-now-unix) t0)) (when (> peer 0) (let ((dog (sys-fork))) (do (when (= dog 0) (do (sys-sleep 5) (sys-kill peer 9) (nd-exit))) (sys-wait peer) (sys-kill dog 9) (sys-wait dog)))) (display (Str8 replace ps "PORT" (string-concat (list (file-read-all (nd-f "/out")) (if (file-exists? (nd-f "/hex")) (string-concat (map (fn (_ l) (string-append "hex " (string-append l "\n"))) (filter (fn (_ l) (> (byte-len l) 0)) (Str8 split "\n" (file-read-all (nd-f "/hex")))))) "") "stderr:\n" (file-read-all (nd-f "/err")) "status " (%cu-int->str st) "\npeer:\n" (file-read-all (nd-f "/peer"))))))))) (display "made"))
```
---
    made

## busybox's behaviour

### c_basic

```cu
(nc-case "c_basic" "client" "yo\n" "hi\n" (list "127.0.0.1" "P"))
```
---
```output
yo
stderr:
status 0
peer:
hi
```

### c_verbose

```cu
(nc-case "c_verbose" "client" "yo\n" "hi\n" (list "-v" "127.0.0.1" "P"))
```
---
```output
yo
stderr:
127.0.0.1 (127.0.0.1:PORT) open
status 0
peer:
hi
```

### c_refused_vv

```cu
(nc-case "c_refused_vv" "none" "" "hi\n" (list "-vv" "127.0.0.1" "P"))
```
---
```output
stderr:
netcat: 127.0.0.1 (127.0.0.1:PORT): Connection refused
sent 0, rcvd 0
status 1
peer:
```

### c_zero_open

```cu
(nc-case "c_zero_open" "client" "" "" (list "-z" "-v" "127.0.0.1" "P"))
```
---
```output
stderr:
127.0.0.1 (127.0.0.1:PORT) open
status 0
peer:
```

### c_noargs

```cu
(nc-case "c_noargs" "none" "" "" (list))
```
---
```output
stderr:
Usage: netcat [OPTIONS] HOST PORT  - connect
nc [OPTIONS] -l -p PORT [HOST] [PORT]  - listen

	-e PROG	Run PROG after connect (must be last)
	-l	Listen mode, for inbound connects
	-lk	With -e, provides persistent server
	-p PORT	Local port
	-s ADDR	Local address
	-w SEC	Timeout for connects and final net reads
	-i SEC	Delay interval for lines sent
	-n	Don't do DNS resolution
	-u	UDP mode
	-b	Allow broadcasts
	-v	Verbose
	-o FILE	Hex dump traffic
	-z	Zero-I/O mode (scanning)
status 1
peer:
```

### c_onearg

```cu
(nc-case "c_onearg" "none" "" "" (list "127.0.0.1"))
```
---
```output
stderr:
status 1
peer:
```

### c_badport

```cu
(nc-case "c_badport" "none" "" "" (list "127.0.0.1" "nope"))
```
---
```output
stderr:
netcat: bad port 'nope'
status 1
peer:
```

### c_badhost

```cu
(nc-case "c_badhost" "none" "" "" (list "no.such.host.invalid" "80"))
```
---
```output
stderr:
netcat: bad address 'no.such.host.invalid'
status 1
peer:
```

### l_basic

```cu
(nc-case "l_basic" "listen" "" "yo\n" (list "-l" "-p" "P"))
```
---
```output
hi
stderr:
status 0
peer:
yo
```

