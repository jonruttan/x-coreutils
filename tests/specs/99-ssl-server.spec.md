# @weight 15
# @timeout-scale 4

ssl_server on a connection accepted from a free port of 127.0.0.1, with
`openssl s_client -quiet -tls1_3` as the client.  Each case runs
ssl_server in a child whose standard input and output are the accepted
socket, as tcpsvd hands it one, with ARGS after `-f`'s PEM file; s_client
sends "hello" and prints what comes back.  The PEM files hold a key and its
self-signed certificate, made for the run: RSA, Ed25519, and the RSA key
alone.  The report is what the client printed, then ssl_server's status
and stderr.  The refusals and the messages are busybox's own; busybox's
ssl_server speaks TLS 1.2 with an RSA key and this one TLS 1.3, so the
exchanges are checked against s_client, not against busybox.  The weight
and timeout are the TLS engines' build, which a session pays once.

## the fixture

### keys and certificates, a server, a client, and the report

```cu
(do (import x/sys/socket)
  (def ss-sh (fn (_ script) (proc-run (list "/bin/sh" "-c" script))))
  (ss-sh (string-concat (list
    "d=/tmp/x-cu-ssls; rm -rf $d; mkdir -p $d && cd $d"
    " && openssl req -x509 -newkey rsa:2048 -nodes -keyout rsa.key -out rsa.crt -days 1 -subj /CN=localhost >/dev/null 2>&1"
    " && cat rsa.key rsa.crt > rsa.pem"
    " && openssl req -x509 -newkey ed25519 -nodes -keyout ed.key -out ed.crt -days 1 -subj /CN=localhost >/dev/null 2>&1"
    " && cat ed.key ed.crt > ed.pem")))
  (def ss (fn (_ args)
    (%cu-heap-collect)
    (def l (Socket tcp-listen-on "127.0.0.1" 0))
    (def port (Socket local-port l))
    (def pid (sys-fork))
    (when (= pid 0)
      (do (def fd (Socket accept l))
          ; nothing left on descriptor 3: an applet takes it for the launcher's standard input
          (Socket close l)
          (sys-dup2 fd 0) (sys-dup2 fd 1) (sys-close fd)
          (let ((e (file-open-write "/tmp/x-cu-ssls/err"))) (do (sys-dup2 e 2) (sys-close e)))
          (sys-exit (guard (e (do (file-write 2 "uncaught\n") 99)) (cu-run (pair "ssl_server" args) "")))))
    (Socket close l)
    (sys-setenv "SS_PORT" (%cu-int->str port))
    (ss-sh "cd /tmp/x-cu-ssls && printf 'hello\\n' | openssl s_client -quiet -tls1_3 -connect 127.0.0.1:$SS_PORT > out 2>/dev/null")
    (def st (sys-wait pid))
    (ss-sh (string-concat (list
      "cd /tmp/x-cu-ssls && { cat out; echo \"[status " (%cu-int->str st) "]\"; cat err; } > report")))
    (display (file-read-all "/tmp/x-cu-ssls/report"))))
  (display "made"))
```
---
    made

## serving

### an RSA key: the client's line to PROG, PROG's reply to the client

```cu
(ss (list "-f" "/tmp/x-cu-ssls/rsa.pem" "sh" "-c" "read l; echo \"got $l\""))
```
---
```output
got hello
[status 0]
```

### an Ed25519 key

```cu
(ss (list "-f" "/tmp/x-cu-ssls/ed.pem" "sh" "-c" "read l; echo \"got $l\""))
```
---
```output
got hello
[status 0]
```

### PROG's output ends the session, whatever the client sends

```cu
(ss (list "-f" "/tmp/x-cu-ssls/rsa.pem" "echo" "Hello world"))
```
---
```output
Hello world
[status 0]
```

## what it refuses

### a PROG that cannot run: its child says so, and the session ends

```cu
(ss (list "-f" "/tmp/x-cu-ssls/rsa.pem" "/nonexistent/prog"))
```
---
```output
[status 0]
ssl_server: can't execute '/nonexistent/prog': No such file or directory
```

### a PEM file with no certificate

```cu
(ss (list "-f" "/tmp/x-cu-ssls/rsa.key" "cat"))
```
---
```output
[status 1]
ssl_server: Tls13: the PEM text holds no certificate
```

### a PEM file that is not there

```cu
(ss (list "-f" "/tmp/x-cu-ssls/nope.pem" "cat"))
```
---
```output
[status 1]
ssl_server: can't read '/tmp/x-cu-ssls/nope.pem': No such file or directory
```

### no -f, no PROG, -f without its file: the usage, status 1

```cu
(display (list (cu-run (list "ssl_server") "") (cu-run (list "ssl_server" "cat") "")
               (cu-run (list "ssl_server" "-f" "x") "") (cu-run (list "ssl_server" "-f") "")
               (cu-run (list "ssl_server" "-v" "-f" "x") "")))
```
---
```output
(1 1 1 1 1)
```

## the end

### the files removed

```cu
(do (ss-sh "rm -rf /tmp/x-cu-ssls") (display "removed"))
```
---
    removed
