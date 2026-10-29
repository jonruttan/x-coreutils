# @weight 2

busybox's netstat (networking/netstat.c), run as root against the
container's own sockets.  Each case runs the bundle's netstat and busybox's
on the same words and compares what they write and their status.  The
setup makes the sockets: TCP listeners on 7704 and on 127.0.0.1:80 (a port
/etc/services names), a UDP one on 7703, a connection held open on 7701,
syslogd's unix socket, and a listening one socat holds.

## the comparison

### each applet against busybox's, by what it writes and its status

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (def lx-x (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (def lx-o (file-open-write "/tmp/lx-xo")) (def lx-e (file-open-write "/tmp/lx-xe"))
          (sys-dup2 lx-o 1) (sys-dup2 lx-e 2)
          (def lx-st (cu-run argv ""))
          (sys-dup2 9 1) (sys-dup2 8 2) (file-close lx-o) (file-close lx-e)
          (%str-concat (list (lx-read "/tmp/lx-xo") "stderr:\n" (lx-read "/tmp/lx-xe") "status " (cu-int->str lx-st) "\n")))))
    (def lx-bb (fn (_ argv)
      (do (lx-sh (%str-concat (list "/bin/busybox " (Str8 join " " (map lx-q argv)) " > /tmp/lx-bo 2> /tmp/lx-bx; echo $? > /tmp/lx-bs; sed '/^BusyBox v/{N;d;}' /tmp/lx-bx > /tmp/lx-be")))
          (%str-concat (list (lx-read "/tmp/lx-bo") "stderr:\n" (lx-read "/tmp/lx-be") "status " (lx-read "/tmp/lx-bs"))))))
    ; PRE run through the shell before each side
    (def lx-case (fn (_ pre argv)
      (do (lx-sh pre) (def lx-a (lx-x argv)) (lx-sh pre) (def lx-b (lx-bb argv))
          (display (if (string=? lx-a lx-b) "same\n" (%str-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    ; as lx-case, with what POST says after each side's run compared too: the
    ; kernel's own account of what the run changed
    (def lx-case-after (fn (_ pre argv post)
      (do (lx-sh pre) (def lx-a (lx-x argv)) (lx-sh (%str-concat (list "{ " post "; } > /tmp/lx-post 2>&1"))) (def lx-pa (lx-read "/tmp/lx-post"))
          (lx-sh pre) (def lx-b (lx-bb argv)) (lx-sh (%str-concat (list "{ " post "; } > /tmp/lx-post 2>&1"))) (def lx-pb (lx-read "/tmp/lx-post"))
          (display (if (if (string=? lx-a lx-b) (string=? lx-pa lx-pb) #f) "same\n"
                     (%str-concat (list "ours:\n" lx-a lx-pa "busybox:\n" lx-b lx-pb)))))))
    (display "made"))
```
---
    made

### the sockets

```cu
(do (lx-sh "(sleep 9999 | nc -l -p 7701 >/dev/null 2>&1 &); (nc -lk -p 7704 >/dev/null 2>&1 &); (nc -lk -s 127.0.0.1 -p 80 >/dev/null 2>&1 &); (nc -u -l -p 7703 >/dev/null 2>&1 &); (syslogd -n -O /tmp/lx-log >/dev/null 2>&1 &); (socat UNIX-LISTEN:/tmp/lx-listen.sock,fork /dev/null >/dev/null 2>&1 &); sleep 1; (sleep 9999 | nc 127.0.0.1 7701 >/dev/null 2>&1 &); sleep 1")
    (display "up"))
```
---
    up

## the sockets

### connected sockets by default, listening ones with -l, both with -a

```cu
(do (lx-case ":" (list "netstat" "-n"))
    (lx-case ":" (list "netstat" "-l" "-n"))
    (lx-case ":" (list "netstat" "-a" "-n")))
```
---
```output
same
same
same
```

### one kind or another: -t, -u, -w, -x, and two of them

```cu
(do (lx-case ":" (list "netstat" "-a" "-n" "-t"))
    (lx-case ":" (list "netstat" "-a" "-n" "-u"))
    (lx-case ":" (list "netstat" "-a" "-n" "-w"))
    (lx-case ":" (list "netstat" "-a" "-x"))
    (lx-case ":" (list "netstat" "-l" "-n" "-t" "-u")))
```
---
```output
same
same
same
same
same
```

### names and services, -W's wide columns, and -p's processes

```cu
(do (lx-case ":" (list "netstat" "-a" "-t"))
    (lx-case ":" (list "netstat" "-a" "-n" "-W"))
    (lx-case ":" (list "netstat" "-a" "-n" "-p"))
    (lx-case ":" (list "netstat" "-l" "-x" "-p")))
```
---
```output
same
same
same
same
```

## the routing table

### -r is route's table in netstat's columns, -e in route's

```cu
(do (lx-case ":" (list "netstat" "-r" "-n"))
    (lx-case ":" (list "netstat" "-r" "-n" "-e"))
    (lx-case ":" (list "netstat" "-r")))
```
---
```output
same
same
same
```

### the sockets taken away

```cu
(do (lx-sh "pkill -f 'nc -l' ; pkill -f 'sleep 9999'; pkill syslogd; pkill socat; true") (display "down"))
```
---
    down
