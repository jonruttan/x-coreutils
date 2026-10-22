# @weight 4

telnetd as busybox's.  Each case writes ISSUE (as printf's %b reads it) to
/tmp/x-cu-telnetd/issue and SCRIPT to /tmp/x-cu-telnetd/s, which the login
-- a wrapper that runs sh on it -- runs; in ARGS, P is a free port of
127.0.0.1, @I the issue file and @S the login.  telnetd runs in a child; a
client connects, sends INPUT (as printf's %b reads it) 0.5 s later -- a | in
INPUT a further 0.5 s pause -- waits 1.5 s, closes its side and reads to the
end.  ARGS of the form inetd:nowait:ARGS hand telnetd an accepted connection
on its stdin and stdout, as inetd hands a nowait service one; inetd:wait:ARGS
the listening socket.  ARGS starting with ! run telnetd that way alone.  Every
expectation is busybox's own output for the same case: what the client got
through LC_ALL=C cat -v, then telnetd's stderr; for !, its status, stdout and
stderr.  The terminal's name is shown as PTS.

## the fixture

### a telnetd, a client, and the report

```cu
(do (import x/sys/socket)
  (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-telnetd && mkdir -p /tmp/x-cu-telnetd"))
  (def td-f (fn (_ n) (string-append "/tmp/x-cu-telnetd/" n)))
  (def td-lines (fn (_ s)
    (let go ((i 0) (acc ()))
      (let ((nl (%wget-index s #\newline i)))
        (if (null? nl) (reverse (if (< i (byte-len s)) (pair (substring s i (byte-len s)) acc) acc))
          (go (+ nl 1) (pair (substring s i nl) acc)))))))
  (def td-sh (fn (_ script) (proc-run (list "/bin/sh" "-c" script))))
  (def td-runs (fn (_ path)
    (let ((fd (File open path (list (lit rdonly)))))
      (let go ((acc ()))
        (let ((r (file-read-run fd 65536)))
          (if (= (rest r) 0) (do (file-close fd) (reverse acc)) (go (pair r acc))))))))
  (def td-prep (fn (_ args issue script input port)
    (sys-setenv "TD_ARGS" args) (sys-setenv "TD_ISSUE" issue) (sys-setenv "TD_S" script)
    (sys-setenv "TD_IN" input) (sys-setenv "TD_PORT" (cu-int->str port))
    (td-sh (string-concat (list
      "d=/tmp/x-cu-telnetd; rm -f $d/p* $d/got $d/out $d/err $d/argv; "
      "printf '%b' \"$TD_ISSUE\" > $d/issue; printf '%b' \"$TD_S\" > $d/s; "
      "printf '#!/bin/sh\\nexec sh %s/s\\n' $d > $d/login; chmod +x $d/login; "
      "n=0; printf '%s\\n' \"$TD_IN\" | tr '|' '\\n' | while IFS= read -r part; do n=$((n+1)); printf '%b' \"$part\" > $d/p$n; done; "
      "a=${TD_ARGS#!}; a=${a#inetd:*:}; "
      "eval \"set -- $(printf ' %s ' \"$a\" | sed -e \"s/ P / $TD_PORT /g\" -e \"s# @I # $d/issue #g\" -e \"s# @S # $d/login #g\")\"; "
      "for x; do printf '%s\\n' \"$x\"; done > $d/argv")))
    (td-lines (file-read-all (td-f "argv")))))
  (def td-pieces (fn (_)
    (let go ((n 1) (acc ()))
      (let ((f (td-f (string-append "p" (cu-int->str n)))))
        (if (file-exists? f) (go (+ n 1) (pair (td-runs f) acc)) (reverse acc))))))
  ; telnetd in a child; MODE plain, nowait (an accepted connection on 0 and
  ; 1) or wait (the listener on 0)
  (def td-start (fn (_ mode argv l)
    (let ((pid (sys-fork)))
      (if (> pid 0) pid
        (do (sys-dup2 (file-open-write (td-f "err")) 2)
            (match ((string=? mode "nowait") (let ((c (Socket accept l))) (do (sys-dup2 c 0) (sys-dup2 c 1) (Socket close c) (Socket close l))))
                   ((string=? mode "wait") (do (sys-dup2 l 0) (Socket close l)))
                   (#t (unless (null? l) (Socket close l))))
            (sys-exit (cu-run (pair "telnetd" argv) "")))))))
  (def td-conn (fn (_ port)
    (let try ((n 0)) (let ((fd (guard (_ ()) (Socket tcp-connect "127.0.0.1" port))))
                       (if (if (null? fd) (< n 150) #f) (do (sys-usleep 20000) (try (+ n 1))) fd)))))
  (def td-client (fn (_ port)
    (def got (file-open-write (td-f "got")))
    (def c (td-conn port))
    (unless (null? c)
      (do (sys-usleep 500000)
          (map (fn (_ piece) (do (map (fn (_ r) (guard (_ ()) (net-send-run c r))) piece) (sys-usleep 500000))) (td-pieces))
          (let go ((until (+ (sys-time-ms) 8000)) (shut? #f) (shut-at (+ (sys-time-ms) 1000)))
            (def now (sys-time-ms))
            (when (< now until)
              (let ((shut2? (if shut? #t (if (>= now shut-at) (do (guard (_ ()) (Socket shutdown c)) #t) #f))))
                (let ((ready (sys-poll (list (pair c (list (lit in)))) 100)))
                  (if (null? ready) (go until shut2? shut-at)
                    (let ((r (guard (_ ()) (Socket recv-run c 4096))))
                      (unless (null? r) (do (File write got (first r) (rest r)) (go until shut2? shut-at)))))))))
          (Socket close c)))
    (file-close got)))
  (def td (fn (_ args issue script input)
    (cu-heap-collect)
    (def bang? (Str8 starts? "!" args))
    (def mode (match ((Str8 starts? "inetd:nowait:" args) "nowait") ((Str8 starts? "inetd:wait:" args) "wait") (#t "plain")))
    (def l (if (if bang? #f (not (string=? mode "plain"))) (Socket tcp-listen-on "127.0.0.1" 0 5) ()))
    (def port (if (null? l) (let ((q (Socket tcp-listen 0))) (let ((n (Socket local-port q))) (do (Socket close q) n)))
                (Socket local-port l)))
    (def argv (td-prep args issue script input port))
    (sys-signal 13 1)
    (if bang?
      (let ((pid (sys-fork)))
        (do (when (= pid 0)
              (do (sys-dup2 (File open "/dev/null" (list (lit rdonly))) 0) (sys-dup2 (File open "/dev/null" (list (lit rdonly))) 3)
                  (sys-dup2 (file-open-write (td-f "out")) 1) (sys-dup2 (file-open-write (td-f "err")) 2)
                  (sys-exit (cu-run (pair "telnetd" argv) ""))))
            (def st (sys-wait pid))
            (td-sh (string-concat (list "d=/tmp/x-cu-telnetd; { echo \"[status " (cu-int->str st) "]\"; cat $d/out; cat $d/err; } > $d/report")))))
      (let ((pid (td-start mode argv l)))
        (do (unless (null? l) (Socket close l))
            (td-client port)
            (sys-usleep 300000)
            (sys-kill pid 15)
            (sys-wait pid)
            (td-sh "d=/tmp/x-cu-telnetd; { LC_ALL=C cat -v $d/got | sed -E 's#/dev/(pts/|ttys)[0-9]+#PTS#g'; echo; cat $d/err; } > $d/report"))))
    (display (file-read-all (td-f "report")))))
  (display "made"))
```
---
    made

## busybox's telnetd

### the opening IACs, the issue file, the login's output

```cu
(td "-F -p P -f @I -l @S" "Welcome\\n" "echo hello" "")
```
---
```output
M-^?M-{^AM-^?M-{^CM-^?M-}^_Welcome^M
^Mhello^M

```

### the issue file's \\l and an unknown escape

```cu
(td "-F -p P -f @I -l @S" "tty \\\\l x\\\\q\\n" "echo ok" "")
```
---
```output
M-^?M-{^AM-^?M-{^CM-^?M-}^_tty PTS xq^M
^Mok^M

```

### no issue file

```cu
(td "-F -p P -f /nonexistent -l @S" "" "echo ok" "")
```
---
```output
M-^?M-{^AM-^?M-{^CM-^?M-}^_ok^M

```

### input to the login: CR LF is CR, the pty echoes

```cu
(td "-F -p P -f /nonexistent -l @S" "" "read l; echo \"got $l\"" "abc\\r\\n")
```
---
```output
M-^?M-{^AM-^?M-{^CM-^?M-}^_abc^M
got abc^M

```

### CR NUL is CR

```cu
(td "-F -p P -f /nonexistent -l @S" "" "read l; echo \"got $l\"" "abc\\r\\000")
```
---
```output
M-^?M-{^AM-^?M-{^CM-^?M-}^_abc^M
got abc^M

```

### IAC IAC is one 0xff

```cu
(td "-F -p P -f /nonexistent -l @S" "" "read l; printf '%s\\\\n' \"$l\" | LC_ALL=C cat -v" "a\\377\\377b\\r\\n")
```
---
```output
M-^?M-{^AM-^?M-{^CM-^?M-}^_aM-^?M-^?b^M
aM-^?b^M

```

### negotiation and two-byte commands are dropped

```cu
(td "-F -p P -f /nonexistent -l @S" "" "read l; echo \"got $l\"" "\\377\\375\\001\\377\\373\\037\\377\\361ab\\r\\n")
```
---
```output
M-^?M-{^AM-^?M-{^CM-^?M-}^_ab^M
got ab^M

```

### AYT is answered IAC NOP

```cu
(td "-F -p P -f /nonexistent -l @S" "" "sleep 1; echo done" "\\377\\366")
```
---
```output
M-^?M-{^AM-^?M-{^CM-^?M-}^_M-^?M-qdone^M

```

### NAWS sets the window size

```cu
(td "-F -p P -f /nonexistent -l @S" "" "read l; stty size" "\\377\\372\\037\\000\\144\\000\\050\\377\\360x\\r\\n")
```
---
```output
M-^?M-{^AM-^?M-{^CM-^?M-}^_x^M
40 100^M

```

### a 0xff from the login goes out doubled

```cu
(td "-F -p P -f /nonexistent -l @S" "" "printf 'a\\\\377b\\\\n'" "")
```
---
```output
M-^?M-{^AM-^?M-{^CM-^?M-}^_aM-^?M-^?b^M

```

### -K: the connection ends with the login

```cu
(td "-F -K -p P -f /nonexistent -l @S" "" "(sleep 1; echo late) & echo early" "")
```
---
```output
M-^?M-{^AM-^?M-{^CM-^?M-}^_early^M

```

### without -K: it ends when the pty is let go

```cu
(td "-F -p P -f /nonexistent -l @S" "" "(sleep 1; echo late) & echo early" "")
```
---
```output
M-^?M-{^AM-^?M-{^CM-^?M-}^_early^M

```

### a login that cannot run

```cu
(td "-F -p P -f /nonexistent -l /nonexistent/login" "" "" "")
```
---
```output
M-^?M-{^AM-^?M-{^CM-^?M-}^_
```

### -i and -w together

```cu
(td "!-i -w 5" "" "" "")
```
---
```output
[status 1]
Usage: telnetd [OPTIONS]

Handle incoming telnet connections

	-l LOGIN	Exec LOGIN on connect (default /bin/login)
	-f ISSUE_FILE	Display ISSUE_FILE instead of /etc/issue.net
	-K		Close connection as soon as login exits
			(normally wait until all programs close slave pty)
	-p PORT		Port to listen on. Default 23
	-b ADDR[:PORT]	Address to bind to
	-F		Run in foreground
	-i		Inetd mode
	-w SEC		Inetd 'wait' mode, linger time SEC
		inetd.conf line: 23 stream tcp wait root telnetd telnetd -w10
	-S		Log to syslog (implied by -i or without -F and -w)
	-v		Verbose
```

### a bad port

```cu
(td "!-F -p nope" "" "" "")
```
---
```output
[status 1]
telnetd: invalid number 'nope'
```

### an option it does not take

```cu
(td "!-x" "" "" "")
```
---
```output
[status 1]
telnetd: unrecognized option: x
Usage: telnetd [OPTIONS]

Handle incoming telnet connections

	-l LOGIN	Exec LOGIN on connect (default /bin/login)
	-f ISSUE_FILE	Display ISSUE_FILE instead of /etc/issue.net
	-K		Close connection as soon as login exits
			(normally wait until all programs close slave pty)
	-p PORT		Port to listen on. Default 23
	-b ADDR[:PORT]	Address to bind to
	-F		Run in foreground
	-i		Inetd mode
	-w SEC		Inetd 'wait' mode, linger time SEC
		inetd.conf line: 23 stream tcp wait root telnetd telnetd -w10
	-S		Log to syslog (implied by -i or without -F and -w)
	-v		Verbose
```

### -i: one session on inetd's socket

```cu
(td "inetd:nowait:-i -f /nonexistent -l @S" "" "read l; echo \"got $l\"" "hi\\r\\n")
```
---
```output
M-^?M-{^AM-^?M-{^CM-^?M-}^_hi^M
got hi^M

```

### -w: a wait service, then the linger

```cu
(td "inetd:wait:-w 1 -f /nonexistent -l @S" "" "echo served" "")
```
---
```output
M-^?M-{^AM-^?M-{^CM-^?M-}^_served^M

```
