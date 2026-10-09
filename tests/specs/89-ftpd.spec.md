# @weight 2

ftpd as busybox's.  Each case makes the tree /tmp/x-cu-fd/srv with PRE (every
file in it dated 2026-01-02 03:04:05 UTC), runs ftpd ARGS DIR on a connection
accepted from 127.0.0.1 -- in a child, as tcpsvd runs it, with TZ=UTC -- and
sends STEPS over that control connection, one at a time: D:CMD asks EPSV
first, connects to the port it names, sends CMD and keeps what the data
connection carries; W:CMD:TEXT does that sending TEXT (as printf's %b reads
it); S:N waits N seconds; any other step is sent as it is.  Every expectation
is busybox's own output for the same exchange, run by a user who is not root
as the suite is: the control replies, each data connection's bytes between
--- and <EOF>, stderr after log:, and the tree after ===; CR shown as <CR>, a
data port as DPORT or P, a listing's owner and group as USER GROUP and its
total as T, a pid as PID and mkstemp's name as uniq.XXXXXX.  A listing line's
runs of spaces are one: busybox's ls pads its columns to fixed widths, this
bundle's ls to the widest entry.

## the fixture

### a tree, a connection, the steps, and the report

```cu
(do (import x/sys/socket)
  (def fd-dir "/tmp/x-cu-fd/srv")
  (def fd-f (fn (_ n) (string-append "/tmp/x-cu-fd/" n)))
  (def fd-sh (fn (_ script) (proc-run (list "/bin/sh" "-c" script))))
  (def fd-recv (fn (_ fd ms)
    (if (null? (sys-poll (list (pair fd (list (lit in)))) ms)) ()
      (let ((r (Socket recv-run fd 4096))) (if (null? r) "" (substring (first r) 0 (rest r)))))))
  (def fd-ctl "")
  (def fd-drain (fn (self c ms)
    (let ((s (fd-recv c ms)))
      (unless (if (null? s) #t (= (byte-len s) 0))
        (do (set! fd-ctl (string-append fd-ctl s)) (self c ms))))))
  (def fd-epsv-port (fn (_ c)
    (let wait ((n 0))
      (let ((i (%wget-find fd-ctl "(|||")))
        (if (if (null? i) (< n 20) #f)
          (do (fd-drain c 100) (wait (+ n 1)))
          (if (null? i) () (let ((s (substring fd-ctl (+ i 4) (byte-len fd-ctl))))
                             (do (set! fd-ctl (string-append (substring fd-ctl 0 i) "(|=|" s))
                                 (%wget-digits (substring s 0 (%wget-index s #\| 0)))))))))))
  (def fd-data-all (fn (self d acc)
    (let ((s (fd-recv d 2000)))
      (if (if (null? s) #t (= (byte-len s) 0)) acc (self d (string-append acc s))))))
  (def fd-text (fn (_ t)
    (sys-setenv "FD_T" t)
    (fd-sh "printf '%b' \"$FD_T\" > /tmp/x-cu-fd/t")
    (file-read-all (fd-f "t"))))
  (def fd-data-step (fn (_ c s)
    (def body (substring s 2 (byte-len s)))
    (def colon (if (Str8 starts? "W:" s) (%wget-index body #\: 0) ()))
    (def cmd (if (null? colon) body (substring body 0 colon)))
    (def text (if (null? colon) "" (fd-text (substring body (+ colon 1) (byte-len body)))))
    (Socket send c "EPSV\r\n")
    (sys-usleep 300000)
    (let ((port (fd-epsv-port c)))
      (if (null? port) ""
        (let ((d (Socket tcp-connect "127.0.0.1" port)))
          (do (when (> (byte-len text) 0) (Socket send d text))
              (Socket shutdown d)
              (sys-usleep 200000)
              (Socket send c (string-append cmd "\r\n"))
              (let ((got (fd-data-all d "")))
                (do (Socket close d) (sys-usleep 200000) (fd-drain c 100)
                    (string-concat (list "---\n" got "<EOF>\n"))))))))))
  (def fd-step (fn (_ c s)
    (match ((if (Str8 starts? "D:" s) #t (Str8 starts? "W:" s)) (fd-data-step c s))
           ((Str8 starts? "S:" s) (do (sys-usleep (* 1000000 (%wget-digits (substring s 2 (byte-len s))))) (fd-drain c 100) ""))
           (#t (do (Socket send c (string-append s "\r\n")) (sys-usleep 200000) (fd-drain c 100) "")))))
  (def fd-run (fn (_ args pre steps)
    (sys-setenv "FD_PRE" pre) (sys-setenv "FD_ARGS" args)
    (fd-sh "rm -rf /tmp/x-cu-fd; mkdir -p /tmp/x-cu-fd/srv; cd /tmp/x-cu-fd/srv && sh -c \"$FD_PRE\" >/dev/null 2>&1; TZ=UTC find /tmp/x-cu-fd/srv -exec touch -h -t 202601020304.05 {} +; eval \"set -- $FD_ARGS\"; for a; do printf '%s\\n' \"$a\"; done > /tmp/x-cu-fd/argv")
    (def argv (let ((t (file-read-all (fd-f "argv")))) (if (= (byte-len t) 0) () (filter (fn (_ l) (> (byte-len l) 0)) (Str8 split "\n" t)))))
    (def l (Socket tcp-listen-on "127.0.0.1" 0))
    (def port (Socket local-port l))
    (def pid (sys-fork))
    (when (= pid 0)
      (let ((a (Socket accept l)))
        (do (Socket close l) (sys-dup2 a 0) (sys-dup2 a 1) (Socket close a)
            (sys-dup2 (file-open-write (fd-f "log")) 2)
            (sys-setenv "TZ" "UTC") (Sys chdir "/")
            (sys-exit (guard (e (do (file-write 2 (string-append "raised: " (if (Err err? e) (e msg) "?") "\n")) 99))
                        (cu-run (append (list "ftpd") argv (list fd-dir)) ""))))))
    (Socket close l)
    (set! fd-ctl "")
    (def c (Socket tcp-connect "127.0.0.1" port))
    (sys-usleep 300000)
    (fd-drain c 100)
    (def data (string-concat (map (fn (_ s) (fd-step c s)) (Str8 split ";" steps))))
    (sys-usleep 300000) (fd-drain c 100)
    (Socket close c)
    (sys-usleep 300000)
    (sys-kill pid 9) (sys-wait pid)
    (file-write-all (fd-f "ctl") fd-ctl) (file-write-all (fd-f "data") data)
    (fd-sh "cd /tmp/x-cu-fd; norm() { sed -e 's/\\r/<CR>/g' -e 's/(|=|[0-9]*|)/(|||DPORT|)/' -e 's/^\\([-dl][-rwxsStT]\\{9\\} *[0-9]* \\)[^ ]* *[^ ]* */\\1USER GROUP /' -e 's/^total [0-9]*/total T/' -e 's/uniq\\.[A-Za-z0-9]\\{6\\}/uniq.XXXXXX/' -e 's/(127,0,0,1,[0-9]*,[0-9]*)/(127,0,0,1,P,P)/' -e 's/ftpd\\[[0-9]*\\]/ftpd[PID]/' -e '/^[-dl][-rwxsStT]\\{9\\} /s/  */ /g' -e 's|/private/tmp/|/tmp/|g'; }; { norm < ctl; norm < data; echo 'log:'; norm < log; echo '==='; (cd srv && find . | sort | while read f; do if [ -f \"$f\" ]; then echo \"$f: $(cat \"$f\")\"; else echo \"$f/\"; fi; done) | norm; } > report")
    (display (file-read-all (fd-f "report")))))
  (display "made"))
```
---
    made

## the commands

### -A: the simple commands

```cu
(fd-run "-A" "printf hi > a.txt" "SYST;NOOP;TYPE I;STRU F;MODE S;ALLO 5;FEAT;HELP;STAT;FOO;syst;xnoop;QUIT")
```
---
```output
220 Operation successful<CR>
215 UNIX Type: L8<CR>
200 Operation successful<CR>
200 Operation successful<CR>
200 Operation successful<CR>
200 Operation successful<CR>
202 Operation successful<CR>
211-Features:<CR>
 EPSV<CR>
 PASV<CR>
 REST STREAM<CR>
 MDTM<CR>
 SIZE<CR>
211 Ok<CR>
214-Features:<CR>
 EPSV<CR>
 PASV<CR>
 REST STREAM<CR>
 MDTM<CR>
 SIZE<CR>
214 Ok<CR>
211-Server status:<CR>
 TYPE: BINARY<CR>
211 Ok<CR>
500 Unknown command<CR>
215 UNIX Type: L8<CR>
200 Operation successful<CR>
221 Operation successful<CR>
log:
===
./
./a.txt: hi
```

### -A: PWD, CWD, CDUP

```cu
(fd-run "-A" "mkdir -p sub/deeper" "PWD;CWD sub;PWD;XPWD;CWD deeper;CDUP;PWD;CWD nope;CWD;QUIT")
```
---
```output
220 Operation successful<CR>
257 "/tmp/x-cu-fd/srv"<CR>
250 Operation successful<CR>
257 "/tmp/x-cu-fd/srv/sub"<CR>
257 "/tmp/x-cu-fd/srv/sub"<CR>
250 Operation successful<CR>
250 Operation successful<CR>
257 "/tmp/x-cu-fd/srv/sub"<CR>
550 Error<CR>
550 Error<CR>
221 Operation successful<CR>
log:
===
./
./sub/
./sub/deeper/
```

### -A: RETR

```cu
(fd-run "-A" "printf 'hello\\nworld\\n' > a.txt; mkdir sub" "RETR a.txt;D:RETR a.txt;D:RETR nope;D:RETR sub;QUIT")
```
---
```output
220 Operation successful<CR>
425 Use PORT/PASV first<CR>
229 EPSV ok (|||DPORT|)<CR>
150 Opening BINARY connection for a.txt (12 bytes)<CR>
226 Operation successful<CR>
229 EPSV ok (|||DPORT|)<CR>
550 Error<CR>
229 EPSV ok (|||DPORT|)<CR>
550 Error<CR>
221 Operation successful<CR>
---
hello
world
<EOF>
---
<EOF>
---
<EOF>
log:
===
./
./a.txt: hello
world
./sub/
```

### -A: REST then RETR

```cu
(fd-run "-A" "printf abcdefghij > r.txt" "REST 4;D:RETR r.txt;D:RETR r.txt;QUIT")
```
---
```output
220 Operation successful<CR>
350 Operation successful<CR>
229 EPSV ok (|||DPORT|)<CR>
150 Opening BINARY connection for r.txt (10 bytes)<CR>
226 Operation successful<CR>
229 EPSV ok (|||DPORT|)<CR>
150 Opening BINARY connection for r.txt (10 bytes)<CR>
226 Operation successful<CR>
221 Operation successful<CR>
---
efghij<EOF>
---
abcdefghij<EOF>
log:
===
./
./r.txt: abcdefghij
```

### -A: SIZE and MDTM

```cu
(fd-run "-A" "printf hello > a.txt; mkdir sub" "SIZE a.txt;MDTM a.txt;SIZE sub;MDTM nope;SIZE;QUIT")
```
---
```output
220 Operation successful<CR>
213 5<CR>
213 20260102030405<CR>
550 Error<CR>
550 Error<CR>
550 Error<CR>
221 Operation successful<CR>
log:
===
./
./a.txt: hello
./sub/
```

### -A: LIST and NLST

```cu
(fd-run "-A" "printf hello > a.txt; printf bye > b.txt" "LIST;D:LIST;D:NLST;D:LIST a.txt;D:NLST nope;D:LIST -la;QUIT")
```
---
```output
220 Operation successful<CR>
425 Use PORT/PASV first<CR>
229 EPSV ok (|||DPORT|)<CR>
150 Directory listing<CR>
226 Operation successful<CR>
229 EPSV ok (|||DPORT|)<CR>
150 Directory listing<CR>
226 Operation successful<CR>
229 EPSV ok (|||DPORT|)<CR>
150 Directory listing<CR>
226 Operation successful<CR>
229 EPSV ok (|||DPORT|)<CR>
150 Directory listing<CR>
226 Operation successful<CR>
229 EPSV ok (|||DPORT|)<CR>
150 Directory listing<CR>
226 Operation successful<CR>
221 Operation successful<CR>
---
total T<CR>
-rw-r--r-- 1 USER GROUP 5 Jan 2 2026 a.txt<CR>
-rw-r--r-- 1 USER GROUP 3 Jan 2 2026 b.txt<CR>
<EOF>
---
a.txt<CR>
b.txt<CR>
<EOF>
---
-rw-r--r-- 1 USER GROUP 5 Jan 2 2026 a.txt<CR>
<EOF>
---
<EOF>
---
total T<CR>
-rw-r--r-- 1 USER GROUP 5 Jan 2 2026 a.txt<CR>
-rw-r--r-- 1 USER GROUP 3 Jan 2 2026 b.txt<CR>
<EOF>
log:
===
./
./a.txt: hello
./b.txt: bye
```

### -A: STAT of a file

```cu
(fd-run "-A" "printf hello > a.txt" "STAT a.txt;STAT nope;QUIT")
```
---
```output
220 Operation successful<CR>
213-File status:<CR>
-rw-r--r-- 1 USER GROUP 5 Jan 2 2026 a.txt<CR>
213 Operation successful<CR>
213-File status:<CR>
213 Operation successful<CR>
221 Operation successful<CR>
log:
===
./
./a.txt: hello
```

### -A: PASV and PORT

```cu
(fd-run "-A" ":" "PASV;PORT junk;PORT 1,2,3,4,5,999;PORT 1,2,3,4,1,2;QUIT")
```
---
```output
220 Operation successful<CR>
227 PASV ok (127,0,0,1,P,P)<CR>
500 Error<CR>
500 Error<CR>
200 Operation successful<CR>
221 Operation successful<CR>
log:
===
./
```

### -A: upload commands without -w

```cu
(fd-run "-A" "printf hi > a.txt" "STOR x;MKD d;DELE a.txt;RNFR a.txt;APPE a.txt;STOU;RMD d;QUIT")
```
---
```output
220 Operation successful<CR>
500 Unknown command<CR>
500 Unknown command<CR>
500 Unknown command<CR>
500 Unknown command<CR>
500 Unknown command<CR>
500 Unknown command<CR>
500 Unknown command<CR>
221 Operation successful<CR>
log:
===
./
./a.txt: hi
```

### -A -w: STOR, APPE, STOU

```cu
(fd-run "-A -w" ":" "W:STOR up.txt:hello\\n;W:APPE up.txt:more\\n;W:STOU:uniq\\n;D:RETR up.txt;STOR;QUIT")
```
---
```output
220 Operation successful<CR>
229 EPSV ok (|||DPORT|)<CR>
150 Ok to send data<CR>
226 Operation successful<CR>
229 EPSV ok (|||DPORT|)<CR>
150 Ok to send data<CR>
226 Operation successful<CR>
229 EPSV ok (|||DPORT|)<CR>
150 FILE: uniq.XXXXXX<CR>
226 Operation successful<CR>
229 EPSV ok (|||DPORT|)<CR>
150 Opening BINARY connection for up.txt (11 bytes)<CR>
226 Operation successful<CR>
425 Use PORT/PASV first<CR>
221 Operation successful<CR>
---
<EOF>
---
<EOF>
---
<EOF>
---
hello
more
<EOF>
log:
===
./
./uniq.XXXXXX: uniq
./up.txt: hello
more
```

### -A -w: REST then STOR

```cu
(fd-run "-A -w" "printf 0123456789 > r.txt" "REST 3;W:STOR r.txt:XY;QUIT")
```
---
```output
220 Operation successful<CR>
350 Operation successful<CR>
229 EPSV ok (|||DPORT|)<CR>
150 Ok to send data<CR>
226 Operation successful<CR>
221 Operation successful<CR>
---
<EOF>
log:
===
./
./r.txt: 012XY56789
```

### -A -w: MKD, RMD, DELE, RNFR, RNTO

```cu
(fd-run "-A -w" "printf hi > a.txt; printf yo > b.txt; mkdir full; printf x > full/f" "MKD d2;MKD d2;RMD d2;RMD full;RMD nope;DELE a.txt;DELE nope;RNTO c.txt;RNFR b.txt;RNTO c.txt;RNFR nope;RNTO d.txt;QUIT")
```
---
```output
220 Operation successful<CR>
257 Operation successful<CR>
550 Error<CR>
250 Operation successful<CR>
550 Error<CR>
550 Error<CR>
250 Operation successful<CR>
550 Error<CR>
503 Use RNFR first<CR>
350 Operation successful<CR>
250 Operation successful<CR>
350 Operation successful<CR>
550 Error<CR>
221 Operation successful<CR>
log:
===
./
./c.txt: yo
./full/
./full/f: x
```

### login: commands before it

```cu
(fd-run "" ":" "SYST;PASS x;QUIT")
```
---
```output
220 Operation successful<CR>
530 Login with USER+PASS<CR>
530 Login failed<CR>
221 Operation successful<CR>
log:
===
./
```

### login: a wrong password

```cu
(fd-run "" ":" "USER ftpu;PASS wrong;USER nosuch;PASS x;QUIT")
```
---
```output
220 Operation successful<CR>
331 Specify password<CR>
530 Login failed<CR>
331 Specify password<CR>
530 Login failed<CR>
221 Operation successful<CR>
log:
===
./
```

### -v: errors logged

```cu
(fd-run "-A -v" ":" "CWD nope;FOO;NOOP;QUIT")
```
---
```output
220 Operation successful<CR>
550 Error<CR>
500 Unknown command<CR>
200 Operation successful<CR>
221 Operation successful<CR>
log:
ftpd[PID]: 550 Error
===
./
```

### -vv: everything logged

```cu
(fd-run "-A -vv" "printf hi > a.txt" "NOOP;SIZE a.txt;CWD nope;QUIT")
```
---
```output
220 Operation successful<CR>
200 Operation successful<CR>
213 2<CR>
550 Error<CR>
221 Operation successful<CR>
log:
ftpd[PID]: 220 Operation successful
ftpd[PID]: NOOP
ftpd[PID]: 200 Operation successful
ftpd[PID]: SIZE a.txt
ftpd[PID]: 213 2
ftpd[PID]: CWD nope
ftpd[PID]: 550 Error
ftpd[PID]: QUIT
ftpd[PID]: 221 Operation successful
===
./
./a.txt: hi
```

### -t 1: an idle connection timed out

```cu
(fd-run "-A -t 1" ":" "NOOP;S:3")
```
---
```output
220 Operation successful<CR>
200 Operation successful<CR>
421 Timeout<CR>
log:
===
./
```

## what ends a run

Each run below ends before it serves: stdout with a `|` at the end of each
line, then stderr less the banner line busybox's usage text starts with, then
the status.  The suite's stdin is not a socket, as busybox's was not.

### the fixture: a run of an applet, with its stdout, stderr and status

```cu
(do (def nf (fn (_ n) (string-append "/tmp/x-cu-fd/" n))) (def run (fn (_ argv in) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv in)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (Str8 replace "\n" "|\n" (file-read-all (nf ".out"))) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n")))))))) (display "made"))
```
---
    made

### stdin not a socket: the usage

```cu
(run (list "ftpd" "-A" "/tmp") "")
```
---
```output
stderr:
Usage: ftpd [-wvS] [-a USER] [-t SEC] [-T SEC] [DIR]

FTP server. Chroots to DIR, if this fails (run by non-root), cds to it.
It is an inetd service, inetd.conf line:
	21 stream tcp nowait root ftpd ftpd /files/to/serve
Can be run from tcpsvd:
	tcpsvd -vE 0.0.0.0 21 ftpd /files/to/serve

	-w	Allow upload
	-A	No login required, client access occurs under ftpd's UID
	-a USER	Enable 'anonymous' login and map it to USER
	-v	Log errors to stderr. -vv: verbose log
	-S	Log errors to syslog. -SS: verbose log
	-t,-T N	Idle and absolute timeout
status 1
```

### -t: not a number

```cu
(run (list "ftpd" "-t" "x") "")
```
---
```output
stderr:
ftpd: invalid number 'x'
status 1
```
