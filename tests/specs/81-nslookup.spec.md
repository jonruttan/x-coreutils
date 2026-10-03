# @weight 2

nslookup as busybox's.  Each case's server is a forked child on an
ephemeral port, -port=P in the arguments, answering every query with
its id and question and the case's row for the query's type: the
answer count, the authoritative bit, the rcode, and the answer records
in hex.  A type with no row is answered NOTIMP, as busybox's dnsd
answers it.  The report gives stdout, stderr and the status, the port
spelled PORT and a query's time 0.

The cases dnsd can serve -- an A, a reverse lookup, a name it does not
know, -debug, no server, and the refusals -- expect busybox's own output
against dnsd; the other record types expect what busybox's parse_reply
prints for them, from its formats.

## the fixture

### a responder, a run, and its report

```cu
(do (import x/sys/socket) (def nsd "/tmp/x-cu-net.ns") (def ns-hex (fn (_ h) (let go ((i (- (byte-len h) 2)) (acc ())) (if (< i 0) acc (go (- i 2) (pair (+ (* 16 (%ns-hex (byte-at h i))) (%ns-hex (byte-at h (+ i 1)))) acc)))))) (def ns-vec (fn (_ bs) (vec-build (length bs) (let ((l bs)) (fn (_ i) (let ((b (first l))) (do (set! l (rest l)) b))))))) (def ns-qtype (fn (_ q) (let ((v (ns-vec q))) (let ((name (%ns-name v (length q) 12))) (if (null? name) 0 (%ns-u16 v (+ 12 (rest name)))))))) (def ns-row (fn (self rows t) (if (null? rows) (list 0 0 4 "") (if (= (first (first rows)) t) (rest (first rows)) (self (rest rows) t))))) (def ns-reply (fn (_ q row) (append (list (first q) (first (rest q)) (+ 129 (* 4 (first (rest row)))) (+ 128 (first (rest (rest row)))) 0 1 0 (first row) 0 0 0 0) (append (%ns-drop 12 q) (ns-hex (first (rest (rest (rest row))))))))) (def ns-serve (fn (_ fd rows) (do (guard (_ ()) (let loop () (let ((got (Socket recv-from-run fd 512))) (let ((q (%ns-bytes (first (first got)) 0 (rest (first got))))) (let ((reply (ns-reply q (ns-row rows (ns-qtype q))))) (do (Socket send-to-run fd (pair (bytes->str reply) (length reply)) (first (rest got)) (rest (rest got))) (loop))))))) (sys-exec "/bin/sh" (list "-c" "exit 0"))))) (def ns-tidy (fn (_ s) (let ((i (%wget-find s " completed in "))) (if (null? i) s (let ((j (%wget-index s #\m (+ i 14)))) (string-concat (list (substring s 0 (+ i 14)) "0" (substring s j (byte-len s))))))))) (def ns-case (fn (_ args rows) (do (proc-run (list "/bin/sh" "-c" (string-concat (list "rm -rf " nsd " && mkdir -p " nsd)))) (def fd (Socket udp-bind 0)) (def port (%cu-int->str (Socket local-port fd))) (def pid (if (null? rows) -1 (sys-fork))) (when (= pid 0) (ns-serve fd rows)) (Socket close fd) (sys-dup2 1 9) (sys-dup2 2 8) (def oo (file-open-write (string-append nsd "/out"))) (def ee (file-open-write (string-append nsd "/err"))) (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (guard (e (do (file-write 2 (string-append "raised: " (if (Err err? e) (e msg) "?"))) -1)) (cu-run (pair "nslookup" (map (fn (_ a) (Str8 replace "=P" (string-append "=" port) a)) args)) ""))) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (when (> pid 0) (do (sys-kill pid 9) (sys-wait pid))) (display (ns-tidy (Str8 replace (string-append ":" port) ":PORT" (string-concat (list (file-read-all (string-append nsd "/out")) "stderr:\n" (file-read-all (string-append nsd "/err")) "status " (%cu-int->str st) "\n")))))))) (display "made"))
```
---
    made

## against a dnsd: busybox's own output

### with no -type, an A and an AAAA query; the server knows the A only

```cu
(ns-case (list "-port=P" "host.test" "127.0.0.1") (list (list 1 1 1 0 "c00c000100010000012c00040a010203")))
```
---
```output
Server:		127.0.0.1
Address:	127.0.0.1:PORT

Name:	host.test
Address: 10.1.2.3

** server can't find host.test: NOTIMP

stderr:
status 1
```

### -type=a asks for the A alone

```cu
(ns-case (list "-port=P" "-type=a" "host.test" "127.0.0.1") (list (list 1 1 1 0 "c00c000100010000012c00040a010203")))
```
---
```output
Server:		127.0.0.1
Address:	127.0.0.1:PORT

Name:	host.test
Address: 10.1.2.3

stderr:
status 0
```

### an address is a reverse lookup

```cu
(ns-case (list "-port=P" "10.1.2.3" "127.0.0.1") (list (list 12 1 1 0 "c00c000c00010000012c000b04686f7374047465737400")))
```
---
```output
Server:		127.0.0.1
Address:	127.0.0.1:PORT

3.2.1.10.in-addr.arpa	name = host.test

stderr:
status 0
```

### a name the server does not know

```cu
(ns-case (list "-port=P" "nope.test" "127.0.0.1") (list (list 1 0 1 3 "")))
```
---
```output
Server:		127.0.0.1
Address:	127.0.0.1:PORT

** server can't find nope.test: NXDOMAIN

** server can't find nope.test: NOTIMP

stderr:
status 1
```

### -debug says the answer is authoritative, and when the query completed

```cu
(ns-case (list "-port=P" "-debug" "-type=a" "host.test" "127.0.0.1") (list (list 1 1 1 0 "c00c000100010000012c00040a010203")))
```
---
```output
Server:		127.0.0.1
Address:	127.0.0.1:PORT

Query #0 completed in 0ms:
authoritative answer:
Name:	host.test
Address: 10.1.2.3

stderr:
status 0
```

### no server listening

```cu
(ns-case (list "-port=P" "-timeout=1" "-retry=1" "host.test" "127.0.0.1") ())
```
---
```output
;; connection timed out; no servers could be reached

stderr:
nslookup: write to '127.0.0.1': Connection refused
status 1
```

### no operand, an unknown type, an unknown option, an operand too many

```cu
(do (ns-case () ()) (ns-case (list "-type=bogus" "host.test" "127.0.0.1") ()) (ns-case (list "-zap" "host.test" "127.0.0.1") ()) (ns-case (list "host.test" "127.0.0.1" "extra") ()))
```
---
```output
stderr:
Usage: nslookup [-type=QUERY_TYPE] [-debug] HOST [DNS_SERVER]

Query DNS about HOST

QUERY_TYPE: soa,ns,a,aaaa,cname,mx,txt,ptr,srv,any
status 1
stderr:
nslookup: invalid query type "bogus"
status 1
stderr:
Usage: nslookup [-type=QUERY_TYPE] [-debug] HOST [DNS_SERVER]

Query DNS about HOST

QUERY_TYPE: soa,ns,a,aaaa,cname,mx,txt,ptr,srv,any
status 1
stderr:
Usage: nslookup [-type=QUERY_TYPE] [-debug] HOST [DNS_SERVER]

Query DNS about HOST

QUERY_TYPE: soa,ns,a,aaaa,cname,mx,txt,ptr,srv,any
status 1
```

## the other record types: busybox's formats

### mx: preference and exchanger

```cu
(ns-case (list "-port=P" "-type=mx" "host.test" "127.0.0.1") (list (list 15 1 1 0 "c00c000f00010000012c000d000a046d61696c047465737400")))
```
---
```output
Server:		127.0.0.1
Address:	127.0.0.1:PORT

host.test	mail exchanger = 10 mail.test

stderr:
status 0
```

### txt: the first string, quoted

```cu
(ns-case (list "-port=P" "-type=txt" "host.test" "127.0.0.1") (list (list 16 1 1 0 "c00c001000010000012c000c0b68656c6c6f20776f726c64")))
```
---
```output
Server:		127.0.0.1
Address:	127.0.0.1:PORT

host.test	text = "hello world"

stderr:
status 0
```

### ns

```cu
(ns-case (list "-port=P" "-type=ns" "host.test" "127.0.0.1") (list (list 2 1 1 0 "c00c000200010000012c000a036e7331047465737400")))
```
---
```output
Server:		127.0.0.1
Address:	127.0.0.1:PORT

host.test	nameserver = ns1.test

stderr:
status 0
```

### cname

```cu
(ns-case (list "-port=P" "-type=cname" "host.test" "127.0.0.1") (list (list 5 1 1 0 "c00c000500010000012c000c05616c696173047465737400")))
```
---
```output
Server:		127.0.0.1
Address:	127.0.0.1:PORT

host.test	canonical name = alias.test

stderr:
status 0
```

### srv: priority, weight, port and target

```cu
(ns-case (list "-port=P" "-type=srv" "host.test" "127.0.0.1") (list (list 33 1 1 0 "c00c002100010000012c0010000a00141f9003737276047465737400")))
```
---
```output
Server:		127.0.0.1
Address:	127.0.0.1:PORT

host.test	service = 10 20 8080 srv.test

stderr:
status 0
```

### soa: its seven fields

```cu
(ns-case (list "-port=P" "-type=soa" "host.test" "127.0.0.1") (list (list 6 1 1 0 "c00c000600010000012c002a036e73310474657374000561646d696e0474657374000000000100000e100000038400093a800000012c")))
```
---
```output
Server:		127.0.0.1
Address:	127.0.0.1:PORT

host.test
	origin = ns1.test
	mail addr = admin.test
	serial = 1
	refresh = 3600
	retry = 900
	expire = 604800
	minimum = 300

stderr:
status 0
```

### aaaa: the longest run of zero groups as ::

```cu
(ns-case (list "-port=P" "-type=aaaa" "host.test" "127.0.0.1") (list (list 28 1 1 0 "c00c001c00010000012c001020010db8000000000000000000000001")))
```
---
```output
Server:		127.0.0.1
Address:	127.0.0.1:PORT

Name:	host.test
Address: 2001:db8::1

stderr:
status 0
```

### two answers, not authoritative

```cu
(ns-case (list "-port=P" "-type=a" "host.test" "127.0.0.1") (list (list 1 2 0 0 "c00c000100010000012c00040a010203c00c000100010000012c00040a010204")))
```
---
```output
Server:		127.0.0.1
Address:	127.0.0.1:PORT

Non-authoritative answer:
Name:	host.test
Address: 10.1.2.3
Name:	host.test
Address: 10.1.2.4

stderr:
status 0
```

### SERVFAIL is asked again twice, then reported

```cu
(ns-case (list "-port=P" "-type=a" "host.test" "127.0.0.1") (list (list 1 0 1 2 "")))
```
---
```output
Server:		127.0.0.1
Address:	127.0.0.1:PORT

** server can't find host.test: SERVFAIL

stderr:
status 1
```

### an authoritative answer with no records

```cu
(ns-case (list "-port=P" "-type=a" "host.test" "127.0.0.1") (list (list 1 0 1 0 "")))
```
---
```output
Server:		127.0.0.1
Address:	127.0.0.1:PORT


stderr:
status 0
```
