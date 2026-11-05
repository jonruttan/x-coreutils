# @weight 2

busybox's rdate (util-linux/rdate.c) against a forked server on a port of
its own: it accepts one connection and sends the case's bytes, or holds it
open and sends nothing.  Every expectation is busybox's own output for the
same bytes and arguments.  The report gives stdout, stderr and the status, with the port spelled PORT.

## the fixture

### a server, a run, and its report

```cu
(do (import x/sys/socket)
    (def rd-f (fn (_ n) (string-append "/tmp/x-cu-rd." n)))
    (def rd (fn (_ sent args)
      (do (def l (Socket tcp-listen 0))
          (def port (cu-int->str (Socket local-port l)))
          (def pid (sys-fork))
          (when (= pid 0)
            (do (guard (_ ())
                  (match ((eq? sent (lit closed)) ())
                         ((eq? sent (lit silent)) (do (Socket accept l) (sys-usleep 30000000)))
                         (#t (let ((c (Socket accept l))) (do (File write c (bytes->str sent) (length sent)) (Socket close c))))))
                (sys-exec "/bin/sh" (list "-c" "exit 0"))))
          (when (eq? sent (lit closed)) (do (sys-wait pid) (Socket close l)))
          (def argv (map (fn (_ a) (if (string=? a "H") (string-append "127.0.0.1:" port) a)) args))
          (sys-dup2 1 9) (sys-dup2 2 8)
          (def oo (file-open-write (rd-f "out")))
          (def ee (file-open-write (rd-f "err")))
          (sys-dup2 oo 1) (sys-dup2 ee 2)
          (def st (cu-run (pair "rdate" argv) ""))
          (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
          (unless (eq? sent (lit closed))
            (do (Socket close l) (sys-kill pid 9) (sys-wait pid)))
          (display (Str8 replace (string-append ":" port) ":PORT"
                     (%str-concat (list (file-read-all (rd-f "out")) "stderr:\n"
                                        (file-read-all (rd-f "err")) "status " (cu-int->str st) "\n")))))))
    (display "made"))
```
---
    made

## the time shown

### a time server's answer, ctime's way

1767225600, 2026-01-01 00:00 GMT, as RFC 868 sends it.

```cu
(rd (list 237 0 55 128) (list "-p" "H"))
```
---
```output
Thu Jan  1 00:00:00 2026
stderr:
status 0
```

### -sp shows it too

```cu
(rd (list 237 0 55 128) (list "-sp" "H"))
```
---
```output
Thu Jan  1 00:00:00 2026
stderr:
status 0
```

### thirty-two bits past their end

0 is 1900 in RFC 868's own count, but the time nearest the clock here with
those low 32 bits is in 2036.

```cu
(rd (list 0 0 0 0) (list "-p" "H"))
```
---
```output
Thu Feb  7 06:28:16 2036
stderr:
status 0
```

## the failures

### the clock set by one who may not

The specs run unprivileged: settimeofday refuses, and the run ends before
the time is shown.

```cu
(rd (list 237 0 55 128) (list "H"))
```
---
```output
stderr:
rdate: settimeofday: Operation not permitted
status 1
```

### fewer than four bytes

```cu
(rd (list 237 0) (list "-p" "H"))
```
---
```output
stderr:
rdate: 127.0.0.1:PORT: short read
status 1
```

### no server on the port

```cu
(rd (lit closed) (list "-p" "H"))
```
---
```output
stderr:
rdate: can't connect to remote host (127.0.0.1): Connection refused
status 1
```

### a server that never answers

busybox's alarm ends the run after ten seconds.

```cu
(rd (lit silent) (list "-p" "H"))
```
---
```output
stderr:
rdate: timeout connecting to time server
status 1
```

### no HOST, and an option rdate does not take

```cu
(do (rd (lit closed) (list "-p"))
    (rd (lit closed) (list "-Z" "H")))
```
---
```output
stderr:
Usage: rdate [-s/-p] HOST

Set and print time from HOST using RFC 868

	-s	Only set system time
	-p	Only print time
status 1
stderr:
rdate: unrecognized option: Z
Usage: rdate [-s/-p] HOST

Set and print time from HOST using RFC 868

	-s	Only set system time
	-p	Only print time
status 1
```
