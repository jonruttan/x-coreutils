# @weight 2

whois as busybox's.  Each case's replies are served in order, one a
connection, by two forked children sharing a count in a file: one on the
case's own port, P in its arguments, and one on port 43, where a
redirect goes.  Each child reads the query line, records it, and answers
the next reply.  Every expectation is busybox's own output for the same
replies and arguments; the report gives stdout, stderr, the status and
the queries the servers saw, with the case's port spelled PORT.

## the fixture

### two servers, a run, and its report

```cu
(do (import x/sys/socket) (def wq-dir "/tmp/x-cu-net.wq") (def wq-line (fn (_ c) (let go ((acc "")) (if (Str8 includes? "\n" acc) acc (let ((r (Socket recv c 1))) (if (null? r) acc (go (string-append acc r)))))))) (def wq-child (fn (_ lfd) (do (guard (_ ()) (let loop () (let ((c (Socket accept lfd))) (do (let ((q (wq-line c)) (fd (file-open-append (string-append wq-dir "/req")))) (do (file-write fd (Str8 replace "\r" "" q)) (file-close fd))) (let ((n (%wget-digits (file-read-all (string-append wq-dir "/cnt"))))) (do (file-write-all (string-append wq-dir "/cnt") (%cu-int->str (+ n 1))) (let ((f (string-concat (list wq-dir "/r" (%cu-int->str n))))) (when (file-exists? f) (Socket send c (file-read-all f)))))) (Socket close c) (loop))))) (sys-exec "/bin/sh" (list "-c" "exit 0"))))) (def wq (fn (_ name resps args) (do (proc-run (list "/bin/sh" "-c" (string-concat (list "rm -rf " wq-dir " && mkdir -p " wq-dir)))) (file-write-all (string-append wq-dir "/cnt") "0") (file-write-all (string-append wq-dir "/req") "") (let put ((rs resps) (i 0)) (unless (null? rs) (do (file-write-all (string-concat (list wq-dir "/r" (%cu-int->str i))) (first rs)) (put (rest rs) (+ i 1))))) (def l1 (Socket tcp-listen 0)) (def port (%cu-int->str (Socket local-port l1))) (def l2 (Socket tcp-listen 43)) (def p1 (sys-fork)) (when (= p1 0) (wq-child l1)) (def p2 (sys-fork)) (when (= p2 0) (wq-child l2)) (Socket close l1) (Socket close l2) (def argv (map (fn (_ a) (if (string=? a "P") port a)) args)) (sys-dup2 1 9) (sys-dup2 2 8) (def oo (file-open-write (string-append wq-dir "/out"))) (def ee (file-open-write (string-append wq-dir "/err"))) (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (guard (e (do (file-write 2 (string-append "raised: " (if (Err err? e) (e msg) (if (string? e) e "?")))) -1)) (cu-run (pair "whois" argv) ""))) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (sys-kill p1 9) (sys-wait p1) (sys-kill p2 9) (sys-wait p2) (display (Str8 replace (string-append " " port) " PORT" (Str8 replace (string-append ":" port) ":PORT" (string-concat (list (file-read-all (string-append wq-dir "/out")) "stderr:\n" (file-read-all (string-append wq-dir "/err")) "status " (%cu-int->str st) "\nqueries:\n" (file-read-all (string-append wq-dir "/req")))))))))) (display "made"))
```
---
    made

## busybox's behaviour

### found

```cu
(wq "found" (list "Domain Name: EXAMPLE.TEST\r\nRegistrar: X\r\n") (list "-h" "127.0.0.1" "-p" "P" "example.test"))
```
---
```output
[Querying 127.0.0.1:PORT 'example.test']
[127.0.0.1]
Domain Name: EXAMPLE.TEST
Registrar: X
stderr:
status 0
queries:
example.test
```

### lowercase

```cu
(wq "lowercase" (list "DOMAIN:  ex.test\nnote\n") (list "-h" "127.0.0.1" "-p" "P" "ex.test"))
```
---
```output
[Querying 127.0.0.1:PORT 'ex.test']
[127.0.0.1]
DOMAIN:  ex.test
note
stderr:
status 0
queries:
ex.test
```

### retry

```cu
(wq "retry" (list "No match\r\n" "Domain Name: EX.TEST\r\n") (list "-h" "127.0.0.1" "-p" "P" "ex.test"))
```
---
```output
[Querying 127.0.0.1:PORT 'ex.test']
[Querying 127.0.0.1:PORT 'domain ex.test']
[127.0.0.1]
Domain Name: EX.TEST
stderr:
status 0
queries:
ex.test
domain ex.test
```

### never

```cu
(wq "never" (list "nothing\r\n" "still nothing\r\n") (list "-h" "127.0.0.1" "-p" "P" "ex.test"))
```
---
```output
[Querying 127.0.0.1:PORT 'ex.test']
[Querying 127.0.0.1:PORT 'domain ex.test']
[127.0.0.1]
still nothing
stderr:
status 0
queries:
ex.test
domain ex.test
```

### self

```cu
(wq "self" (list "Domain Name: A\r\nWhois Server: 127.0.0.1\r\n") (list "-h" "127.0.0.1" "-p" "P" "a.test"))
```
---
```output
[Querying 127.0.0.1:PORT 'a.test']
[127.0.0.1]
Domain Name: A
Whois Server: 127.0.0.1
stderr:
status 0
queries:
a.test
```

### redirect

```cu
(wq "redirect" (list "Domain Name: A\r\n   whois server:   localhost  \r\nmore\r\n" "Domain Name: A\r\nFrom: second\r\n") (list "-h" "127.0.0.1" "-p" "P" "a.test"))
```
---
```output
[Querying 127.0.0.1:PORT 'a.test']
[Redirected to localhost]
[Querying localhost:43 'a.test']
[localhost]
Domain Name: A
From: second
stderr:
status 0
queries:
a.test
a.test
```

### redirect-i

```cu
(wq "redirect-i" (list "Domain Name: A\r\nwhois: localhost\r\n" "Domain Name: A\r\nFrom: second\r\n") (list "-i" "-h" "127.0.0.1" "-p" "P" "a.test"))
```
---
```output
[Querying 127.0.0.1:PORT 'a.test']
[127.0.0.1]
Domain Name: A
whois: localhost
[Redirected to localhost]
[Querying localhost:43 'a.test']
[localhost]
Domain Name: A
From: second
stderr:
status 0
queries:
a.test
a.test
```

### two

```cu
(wq "two" (list "Domain Name: A\r\n" "Domain Name: B\r\n") (list "-h" "127.0.0.1" "-p" "P" "a.test" "b.test"))
```
---
```output
[Querying 127.0.0.1:PORT 'a.test']
[127.0.0.1]
Domain Name: A
[Querying 127.0.0.1:PORT 'b.test']
[127.0.0.1]
Domain Name: B
stderr:
status 0
queries:
a.test
b.test
```

### crmid

```cu
(wq "crmid" (list "Domain Name: A\r\nline\rcut here\r\nlast\r\n") (list "-h" "127.0.0.1" "-p" "P" "a.test"))
```
---
```output
[Querying 127.0.0.1:PORT 'a.test']
[127.0.0.1]
Domain Name: A
line
last
stderr:
status 0
queries:
a.test
```

### empty

```cu
(wq "empty" (list "" "") (list "-h" "127.0.0.1" "-p" "P" "a.test"))
```
---
```output
[Querying 127.0.0.1:PORT 'a.test']
[Querying 127.0.0.1:PORT 'domain a.test']
[127.0.0.1]
stderr:
status 0
queries:
a.test
domain a.test
```

### refused

```cu
(wq "refused" (list) (list "-h" "127.0.0.1" "-p" "9" "a.test"))
```
---
```output
[Querying 127.0.0.1:9 'a.test']
stderr:
whois: can't connect to remote host (127.0.0.1): Connection refused
status 1
queries:
```

### badaddr

```cu
(wq "badaddr" (list) (list "-h" "no.such.host.invalid" "a.test"))
```
---
```output
[Querying no.such.host.invalid:43 'a.test']
stderr:
whois: bad address 'no.such.host.invalid'
status 1
queries:
```

### noargs

```cu
(wq "noargs" (list) (list))
```
---
```output
stderr:
Usage: whois [-i] [-h SERVER] [-p PORT] NAME...

Query WHOIS info about NAME

	-i	Show redirect results too
	-h,-p	Server to query
status 1
queries:
```

### badport

```cu
(wq "badport" (list) (list "-p" "x" "a.test"))
```
---
```output
stderr:
whois: invalid number 'x'
status 1
queries:
```

### longline

```cu
(wq "longline" (list "Domain Name: A\r\naaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\r\nend\r\n") (list "-h" "127.0.0.1" "-p" "P" "a.test"))
```
---
```output
[Querying 127.0.0.1:PORT 'a.test']
[127.0.0.1]
Domain Name: A
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
end
stderr:
status 0
queries:
a.test
```
