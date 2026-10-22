# @weight 15
# @timeout-scale 4

ssl_client against `openssl s_server -www` on a free port of 127.0.0.1, its
certificate made for the run: s_server answers a GET with a page about the
session, which names the protocol it agreed.  Each case runs ssl_client in
a child with ARGS (P the server's port) and INPUT (as printf's %b reads it)
as standard input; with -s FD the child opens the connection itself and FD
is that socket, and as -s ends the run at standard input's end, a request
there is fed through a pipe held open three seconds past it, for the reply
to come back first.  The report is the reply's first line, whether the page
names TLSv1.3, the status and stderr.  The refusals and the messages are
busybox's own; busybox's ssl_client speaks TLS 1.2 and this one TLS 1.3, so
the exchanges are checked against the server, not against busybox.  The
weight and timeout are the TLS engines' build, which a session pays once.

## the fixture

### a server, an ssl_client, and the report

```cu
(do (import x/sys/socket)
  (def sc-f (fn (_ n) (string-append "/tmp/x-cu-ssl/" n)))
  (def sc-sh (fn (_ script) (proc-run (list "/bin/sh" "-c" script))))
  (def sc-lines (fn (_ s)
    (let go ((i 0) (acc ()))
      (let ((nl (%wget-index s #\newline i)))
        (if (null? nl) (reverse (if (< i (byte-len s)) (pair (substring s i (byte-len s)) acc) acc))
          (go (+ nl 1) (pair (substring s i nl) acc)))))))
  (def sc-port (let ((l (Socket tcp-listen 0))) (let ((p (Socket local-port l))) (do (Socket close l) p))))
  (sys-setenv "SC_PORT" (cu-int->str sc-port))
  (sc-sh (string-concat (list
    "d=/tmp/x-cu-ssl; rm -rf $d; mkdir -p $d && cd $d"
    " && openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 1 -subj /CN=localhost >/dev/null 2>&1"
    " && { openssl s_server -quiet -www -tls1_3 -accept $SC_PORT -cert cert.pem -key key.pem >/dev/null 2>&1 & echo $! > pid; } && sleep 1")))
  (def sc (fn (_ args input socket?)
    (cu-heap-collect)
    (sys-setenv "SC_ARGS" args) (sys-setenv "SC_IN" input)
    (sc-sh "d=/tmp/x-cu-ssl; printf '%b' \"$SC_IN\" > $d/in; eval \"set -- $(printf ' %s ' \"$SC_ARGS\" | sed \"s/ P / $SC_PORT /g; s/:P /:$SC_PORT /g\")\"; for a; do printf '%s\\n' \"$a\"; done > $d/argv")
    (def argv (sc-lines (file-read-all (sc-f "argv"))))
    (def pid (sys-fork))
    (when (= pid 0)
      (do (if (if socket? (> (byte-len input) 0) #f)
            (let ((p (sys-pipe)))
              (do (when (= (sys-fork) 0)
                    (do (sys-dup2 (rest p) 1) (sys-close (first p))
                        (%in-exec "/bin/sh" (list "/bin/sh" "-c" "cat /tmp/x-cu-ssl/in; sleep 3"))
                        (sys-exit 1)))
                  (sys-close (rest p))
                  (sys-dup2 (first p) 0)))
            (sys-dup2 (file-open-read (sc-f "in")) 0))
          (sys-dup2 (file-open-write (sc-f "out")) 1)
          (sys-dup2 (file-open-write (sc-f "err")) 2)
          (def full (if socket? (append (list "-s" (cu-int->str (net-connect "127.0.0.1" sc-port))) argv) argv))
          (sys-exit (guard (e (do (file-write 2 "uncaught\n") 99)) (cu-run (pair "ssl_client" full) "")))))
    (def st (sys-wait pid))
    (sc-sh (string-concat (list
      "d=/tmp/x-cu-ssl; { if [ -s $d/out ]; then head -1 $d/out | tr -d '\\r'; grep -q TLSv1.3 $d/out && echo 'the page names TLSv1.3'; fi;"
      " echo \"[status " (cu-int->str st) "]\"; cat $d/err; } > $d/report")))
    (display (file-read-all (sc-f "report")))))
  (display "made"))
```
---
    made

## talking to the server

### HOST:PORT: the request on standard input, the page on standard output

```cu
(sc "127.0.0.1:P" "GET / HTTP/1.0\r\n\r\n" #f)
```
---
```output
HTTP/1.0 200 ok
the page names TLSv1.3
[status 0]
```

### -n names the server

```cu
(sc "-n localhost 127.0.0.1:P" "GET / HTTP/1.0\r\n\r\n" #f)
```
---
```output
HTTP/1.0 200 ok
the page names TLSv1.3
[status 0]
```

### -e PROG ARGS: the session over pipes to a program that carries it

```cu
(sc "-e nc 127.0.0.1 P" "GET / HTTP/1.0\r\n\r\n" #f)
```
---
```output
HTTP/1.0 200 ok
the page names TLSv1.3
[status 0]
```

### -s FD: a connection already open

```cu
(sc "" "GET / HTTP/1.0\r\n\r\n" #t)
```
---
```output
HTTP/1.0 200 ok
the page names TLSv1.3
[status 0]
```

### -s ends when standard input does

With nothing to send, s_server waits for a request it never gets; -s ends
the run at standard input's end rather than waiting for the server.

```cu
(sc "" "" #t)
```
---
```output
[status 0]
```

## what it refuses

### a port nothing listens on

```cu
(sc "127.0.0.1:1" "" #f)
```
---
```output
[status 1]
ssl_client: can't connect to remote host (127.0.0.1): Connection refused
```

### -s takes a number

```cu
(sc "-s x" "" #f)
```
---
```output
[status 1]
ssl_client: invalid number 'x'
```

### no HOST, or two; -e without PROG; -e with -s; -s with a HOST; -r without -s: the usage, status 1

```cu
(display (list (cu-run (list "ssl_client") "") (cu-run (list "ssl_client" "a" "b") "") (cu-run (list "ssl_client" "-e") "")
               (cu-run (list "ssl_client" "-e" "-s" "3" "prog") "") (cu-run (list "ssl_client" "-s" "3" "host") "")
               (cu-run (list "ssl_client" "-r" "3") "")))
```
---
```output
(1 1 1 1 1 1)
```

### the end: the server stopped

```cu
(do (sc-sh "kill $(cat /tmp/x-cu-ssl/pid) 2>/dev/null; rm -rf /tmp/x-cu-ssl") (display "stopped"))
```
---
    stopped
