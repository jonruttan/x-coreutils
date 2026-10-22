# @weight 4

telnet as busybox's.  Each case starts a server on a free port of 127.0.0.1
that sends SERVER (as printf's %b reads it) to the client that connects and
then keeps what the client sends until it closes its side; a SERVER of - is
no server.  telnet runs in a child with ENV set (COLUMNS, LINES, USER and
TERM unset first), ARGS split as sh splits them with P the port, and INPUT
on its stdin 1 s after it connects (0.3 s with no server) -- a | in INPUT a
further 0.3 s pause.
Every expectation is busybox's own output for the same case: telnet's
stdout through cat -v, its status, its stderr likewise, and what the server
got, in hex.

## the fixture

### a server, a telnet, and the report

```cu
(do (import x/sys/socket)
  (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-telnet && mkdir -p /tmp/x-cu-telnet"))
  (def tn-f (fn (_ n) (string-append "/tmp/x-cu-telnet/" n)))
  (def tn-lines (fn (_ s)
    (let go ((i 0) (acc ()))
      (let ((nl (wget-index s #\newline i)))
        (if (null? nl) (reverse (if (< i (byte-len s)) (pair (substring s i (byte-len s)) acc) acc))
          (go (+ nl 1) (pair (substring s i nl) acc)))))))
  (def tn-sh (fn (_ script) (proc-run (list "/bin/sh" "-c" script))))
  (def tn-prep (fn (_ args server input port)
    (sys-setenv "TN_ARGS" args) (sys-setenv "TN_SERVER" server) (sys-setenv "TN_IN" input)
    (sys-setenv "TN_PORT" (cu-int->str port))
    (tn-sh (string-concat (list
      "d=/tmp/x-cu-telnet; rm -f $d/p* $d/got $d/out $d/err; printf '%b' \"$TN_SERVER\" > $d/sbytes; "
      "n=0; printf '%s\\n' \"$TN_IN\" | tr '|' '\\n' | while IFS= read -r part; do n=$((n+1)); printf '%b' \"$part\" > $d/p$n; done; "
      "eval \"set -- $(printf ' %s ' \"$TN_ARGS\" | sed \"s/ P / $TN_PORT /g\")\"; for a; do printf '%s\\n' \"$a\"; done > $d/argv")))
    (tn-lines (file-read-all (tn-f "argv")))))
  (def tn-read-run (fn (_ path)
    (let ((fd (File open path (list (lit rdonly)))))
      (let go ((acc ()))
        (let ((r (file-read-run fd 65536)))
          (if (= (rest r) 0) (do (file-close fd) (reverse acc)) (go (pair r acc))))))))
  (def tn-pieces (fn (_)
    (let go ((n 1) (acc ()))
      (let ((f (tn-f (string-append "p" (cu-int->str n)))))
        (if (file-exists? f) (go (+ n 1) (pair (tn-read-run f) acc)) (reverse acc))))))
  (def tn-now (fn (_) (sys-time-ms)))
  (def tn-telnet (fn (_ env argv in-read in-write l)
    (let ((pid (sys-fork)))
      (if (> pid 0) pid
        (do (map sys-unsetenv (list "COLUMNS" "LINES" "USER" "TERM"))
            (map (fn (_ kv) (let ((eq (wget-index kv #\= 0)))
                              (sys-setenv (substring kv 0 eq) (substring kv (+ eq 1) (byte-len kv)))))
                 (filter (fn (_ w) (> (byte-len w) 0)) (Str8 split " " env)))
            (sys-close in-write) (unless (null? l) (Socket close l))
            (sys-dup2 in-read 0) (sys-dup2 in-read 3)
            (sys-dup2 (file-open-write (tn-f "out")) 1) (sys-dup2 (file-open-write (tn-f "err")) 2)
            (sys-exit (cu-run (pair "telnet" argv) "")))))))
  ; the server and stdin's writer in one loop: each piece at its time, what
  ; the client sends kept until it closes its side
  (def tn-serve (fn (_ l in-write)
    (def got (file-open-write (tn-f "got")))
    (def c (if (null? l) ()
             (if (null? (sys-poll (list (pair l (list (lit in)))) 30000)) () (Socket accept l))))
    (unless (null? c)
      (map (fn (_ r) (net-send-run c r)) (tn-read-run (tn-f "sbytes"))))
    (let go ((pieces (tn-pieces)) (at (+ (tn-now) (if (null? c) 300 1000))) (open? (not (null? c))) (writing? #t))
      (def now (tn-now))
      (match
        ((if writing? (>= now at) #f)
          (if (null? pieces)
            (do (sys-close in-write) (go () at open? #f))
            (do (map (fn (_ r) (guard (_ ()) (File write in-write (first r) (rest r)))) (first pieces))
                (go (rest pieces) (+ now 300) open? #t))))
        ((if (not open?) (not writing?) #f) ())
        ((not open?) (do (sys-usleep (* 1000 (- at now))) (go pieces at open? writing?)))
        (#t
          (let ((ready (sys-poll (list (pair c (list (lit in)))) (if writing? (- at now) 5000))))
            (if (null? ready) (if writing? (go pieces at open? writing?) (do (Socket close c) (go pieces at #f #f)))
              (let ((r (guard (_ ()) (Socket recv-run c 4096))))
                (if (null? r) (do (Socket close c) (go pieces at #f writing?))
                  (do (File write got (first r) (rest r)) (go pieces at open? writing?)))))))))
    (file-close got)))
  (def tn (fn (_ env args server input)
    (cu-heap-collect)
    (def l (if (string=? server "-") () (Socket tcp-listen-on "127.0.0.1" 0 5)))
    (def port (if (null? l) (let ((q (Socket tcp-listen 0))) (let ((n (Socket local-port q))) (do (Socket close q) n)))
                (Socket local-port l)))
    (def argv (tn-prep args server input port))
    (def p (sys-pipe))
    (sys-signal 13 1)
    (def pid (tn-telnet env argv (first p) (rest p) l))
    (sys-close (first p))
    (tn-serve l (rest p))
    (unless (null? l) (Socket close l))
    (def st (sys-wait pid))
    (tn-sh (string-concat (list
      "d=/tmp/x-cu-telnet; { LC_ALL=C cat -v $d/out; echo \"[status " (cu-int->str st) "]\"; LC_ALL=C cat -v $d/err; "
      (if (null? l) ""
        "echo '--- server got'; od -An -tx1 -v $d/got | tr -s ' \\n' ' ' | sed 's/^ //; s/ $//'; echo; ")
      "} > $d/report")))
    (display (file-read-all (tn-f "report")))))
  (display "made"))
```
---
    made

## busybox's telnet

### plain text both ways

```cu
(tn "TERM=" "127.0.0.1 P" "hello\\r\\nworld\\n" "abc\\n")
```
---
```output
Connected to 127.0.0.1
hello^M
world
EOF on read from foreign host^M
[status 0]
--- server got
61 62 63 0d 0a
```

### WILL ECHO and WILL SGA: DO ECHO, DO SGA, WILL NAWS

```cu
(tn "TERM=" "127.0.0.1 P" "\\377\\373\\001\\377\\373\\003hi\\r\\n" "x\\n")
```
---
```output
Connected to 127.0.0.1
hi^M
EOF on read from foreign host^M
^M
Entering character mode^M
Escape character is '^]'.^M
[status 0]
--- server got
ff fd 01 ff fd 03 ff fb 1f ff fb 18 78 0d 0a
```

### TERM set: WILL TTYPE too, and DO TTYPE answered

```cu
(tn "TERM=xterm" "127.0.0.1 P" "\\377\\373\\001\\377\\375\\030" "x\\n")
```
---
```output
Connected to 127.0.0.1
EOF on read from foreign host^M
^M
Entering character mode^M
Escape character is '^]'.^M
[status 0]
--- server got
ff fd 01 ff fb 1f ff fb 18 ff fa 18 00 78 74 65 72 6d ff f0 78 0d 0a
```

### DO NAWS: the size, 80x24 off a terminal

```cu
(tn "TERM=" "127.0.0.1 P" "\\377\\373\\003\\377\\375\\037" "x\\n")
```
---
```output
Connected to 127.0.0.1
EOF on read from foreign host^M
[status 0]
--- server got
ff fd 03 ff fb 1f ff fb 18 ff fa 1f 00 50 00 18 ff f0 78 0d 0a
```

### COLUMNS and LINES set the size

```cu
(tn "TERM= COLUMNS=132 LINES=50" "127.0.0.1 P" "\\377\\373\\003\\377\\375\\037" "x\\n")
```
---
```output
Connected to 127.0.0.1
EOF on read from foreign host^M
[status 0]
--- server got
ff fd 03 ff fb 1f ff fb 18 ff fa 1f 00 84 00 32 ff f0 78 0d 0a
```

### -l USER: WILL NEW_ENVIRON, and DO answered

```cu
(tn "TERM=" "-l bob 127.0.0.1 P" "\\377\\373\\003\\377\\375\\047" "x\\n")
```
---
```output
Connected to 127.0.0.1
EOF on read from foreign host^M
[status 0]
--- server got
ff fd 03 ff fb 1f ff fb 18 ff fb 27 ff fa 27 00 00 55 53 45 52 01 62 6f 62 ff f0 78 0d 0a
```

### -a: USER from the environment

```cu
(tn "TERM= USER=carol" "-a 127.0.0.1 P" "\\377\\373\\003\\377\\375\\047" "x\\n")
```
---
```output
Connected to 127.0.0.1
EOF on read from foreign host^M
[status 0]
--- server got
ff fd 03 ff fb 1f ff fb 18 ff fb 27 ff fa 27 00 00 55 53 45 52 01 63 61 72 6f 6c ff f0 78 0d 0a
```

### -a with no USER set

```cu
(tn "TERM= USER=" "-a 127.0.0.1 P" "\\377\\373\\003\\377\\375\\047" "x\\n")
```
---
```output
Connected to 127.0.0.1
EOF on read from foreign host^M
[status 0]
--- server got
ff fd 03 ff fb 1f ff fb 18 ff fb 27 ff fa 27 00 00 55 53 45 52 01 ff f0 78 0d 0a
```

### WILL ECHO then WONT ECHO: back to line mode

```cu
(tn "TERM=" "127.0.0.1 P" "\\377\\373\\001ab\\377\\374\\001cd\\r\\n" "x\\n")
```
---
```output
Connected to 127.0.0.1
abcd^M
EOF on read from foreign host^M
^M
Entering line mode^M
Escape character is '^C'.^M
[status 0]
--- server got
ff fe 01 ff fb 1f ff fb 18 78 0d 0a
```

### IAC IAC is one 0xff; CR NUL is CR

```cu
(tn "TERM=" "127.0.0.1 P" "a\\377\\377b\\r\\000c\\r\\n" "x\\n")
```
---
```output
Connected to 127.0.0.1
aM-^?b^Mc^M
EOF on read from foreign host^M
[status 0]
--- server got
78 0d 0a
```

### a subnegotiation is skipped

```cu
(tn "TERM=" "127.0.0.1 P" "a\\377\\372\\030\\001\\377\\360b\\n" "x\\n")
```
---
```output
Connected to 127.0.0.1
ab
EOF on read from foreign host^M
[status 0]
--- server got
78 0d 0a
```

### an unknown IAC command is skipped

```cu
(tn "TERM=" "127.0.0.1 P" "a\\377\\361b\\n" "x\\n")
```
---
```output
Connected to 127.0.0.1
ab
EOF on read from foreign host^M
[status 0]
--- server got
78 0d 0a
```

### stdin: 0xff doubled, CR and LF each CR LF

```cu
(tn "TERM=" "127.0.0.1 P" "ok\\n" "a\\377b\\rc\\n")
```
---
```output
Connected to 127.0.0.1
ok
EOF on read from foreign host^M
[status 0]
--- server got
61 ff ff 62 0d 0a 63 0d 0a
```

### stdin: ^] then e ends the run

```cu
(tn "TERM=" "127.0.0.1 P" "ok\\n" "ab\\035|e")
```
---
```output
Connected to 127.0.0.1
ok
^M
Console escape. Commands are:^M
l	go to line mode^M
c	go to character mode^M
z	suspend telnet^M
e	exit^M
[status 1]
--- server got

```

### stdin: ^] then c, character mode

```cu
(tn "TERM=" "127.0.0.1 P" "ok\\n" "ab\\035|cxy\\n")
```
---
```output
Connected to 127.0.0.1
ok
^M
Console escape. Commands are:^M
l	go to line mode^M
c	go to character mode^M
z	suspend telnet^M
e	exit^M
EOF on read from foreign host^M
^M
Entering character mode^M
Escape character is '^]'.^M
[status 0]
--- server got
61 62 78 79 0d 0a
```

### stdin: ^] then l, already line mode

```cu
(tn "TERM=" "127.0.0.1 P" "ok\\n" "ab\\035|lxy\\n")
```
---
```output
Connected to 127.0.0.1
ok
^M
Console escape. Commands are:^M
l	go to line mode^M
c	go to character mode^M
z	suspend telnet^M
e	exit^M
continuing...^M
EOF on read from foreign host^M
[status 0]
--- server got
61 62 78 79 0d 0a
```

### stdin: bytes after ^] in the same read dropped

```cu
(tn "TERM=" "127.0.0.1 P" "ok\\n" "ab\\035cd")
```
---
```output
Connected to 127.0.0.1
ok
^M
Console escape. Commands are:^M
l	go to line mode^M
c	go to character mode^M
z	suspend telnet^M
e	exit^M
[status 1]
--- server got

```

### a port by number

```cu
(tn "TERM=" "127.0.0.1 P" "hi\\n" "")
```
---
```output
Connected to 127.0.0.1
hi
EOF on read from foreign host^M
[status 0]
--- server got

```

### no host

```cu
(tn "TERM=" "" "-" "")
```
---
```output
[status 1]
Usage: telnet [-a] [-l USER] HOST [PORT]

Connect to telnet server

	-a	Automatic login with $USER envvar
	-l USER	Automatic login as USER
```

### an extra operand

```cu
(tn "TERM=" "127.0.0.1 P extra" "-" "")
```
---
```output
[status 1]
Usage: telnet [-a] [-l USER] HOST [PORT]

Connect to telnet server

	-a	Automatic login with $USER envvar
	-l USER	Automatic login as USER
```

### a bad port

```cu
(tn "TERM=" "127.0.0.1 nope" "-" "")
```
---
```output
[status 1]
telnet: bad port 'nope'
```

### nothing listening

```cu
(tn "TERM=" "127.0.0.1 P" "-" "")
```
---
```output
[status 1]
telnet: can't connect to remote host (127.0.0.1): Connection refused
```

### an option it does not take

```cu
(tn "TERM=" "-x 127.0.0.1" "-" "")
```
---
```output
[status 1]
telnet: unrecognized option: x
Usage: telnet [-a] [-l USER] HOST [PORT]

Connect to telnet server

	-a	Automatic login with $USER envvar
	-l USER	Automatic login as USER
```
