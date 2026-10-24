# @weight 1

busybox's fuser (procps/fuser.c), over the files record x/sys/host reports
for each process.  The matching is checked on a fixture /proc: the Linux
reader pointed at a tree this spec writes, whose links point at files under
the scratch directory, so the devices and inodes are this machine's own.  The
run at the end signals a process this spec starts.  A `|` marks the end of
each line written to standard output.

## the fixtures

### a /proc of five processes, and a run of an applet with the reader pointed at it

100 works in a/ and holds a/held open; 200 holds b/other and a socket bound
to port 8080 over IPv4; 300 maps a/lib; 400 holds a socket bound to port 80
over IPv6; 500 is chrooted into b/.  The maps line carries a/lib's device as
this platform numbers it, two hex digits a part at least, as the kernel prints
it.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-fu && mkdir -p /tmp/x-cu-fu/proc/net /tmp/x-cu-fu/a /tmp/x-cu-fu/b && cd /tmp/x-cu-fu && : > a/held && : > a/lib && : > b/other && cd proc && printf 'cpu  1 0 1 1 0 0 0 0 0 0\\nbtime 1790000000\\n' > stat && mk() { mkdir $1 $1/fd && printf '%s (%s) S 1 %s %s 0 -1 0 0 0 0 0 1 1 0 0 20 0 1 0 100 4096 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\\n' $1 $2 $1 $1 > $1/stat && : > $1/maps; } && mk 100 sh && mk 200 nc && mk 300 app && mk 400 httpd && mk 500 jail && ln -s /tmp/x-cu-fu/a 100/cwd && ln -s /tmp/x-cu-fu/a/held 100/fd/3 && ln -s /tmp/x-cu-fu/b/other 200/fd/0 && ln -s 'socket:[7001]' 200/fd/4 && ln -s 'socket:[7002]' 400/fd/5 && ln -s /tmp/x-cu-fu/b 500/root && printf '  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\\n   0: 0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 7001 1 0000000000000000 100 0 0 10 0\\n' > net/tcp && printf '  sl  local_address                         remote_address                        st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\\n   0: 00000000000000000000000000000000:0050 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 7002 1 0000000000000000 100 0 0 10 0\\n' > net/tcp6")) (def nf (fn (_ n) (string-append "/tmp/x-cu-fu/" n))) (def lib (file-stat-full (nf "a/lib"))) (def hex (fn (_ n) (let ((h (Str8 downcase (cu-hexs n)))) (if (< (byte-len h) 2) (string-append "0" h) h)))) (file-write-all (nf "proc/300/maps") (string-concat (list "55d0a000-55d0b000 r-xp 00000000 " (hex (cu-dev-major (cu-stat-get lib (lit dev)))) ":" (hex (cu-dev-minor (cu-stat-get lib (lit dev)))) " " (cu-int->str (cu-stat-get lib (lit ino))) "    /tmp/x-cu-fu/a/lib\n7f0000000000-7f0000001000 rw-p 00000000 00:00 0 \n"))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (Str8 replace "\n" "|\n" (file-read-all (nf ".out"))) "stderr:\n" (file-read-all (nf ".err")) "status " (cu-int->str st) "\n")))))))) (def kernel (Host %backend)) (def fixed (fn (_ argv) (do (Host source (lit linux)) (Host proc-root (nf "proc")) (run argv) (Host source kernel) (Host proc-root "/proc") ()))) (display (if (file-exists? (nf "proc/500/root")) "made" "fixture incomplete")))
```
---
    made

## files

### a file held open, a working directory, a root and a mapped file are each found

```cu
(do (fixed (list "fuser" "/tmp/x-cu-fu/a/held")) (fixed (list "fuser" "/tmp/x-cu-fu/a")) (fixed (list "fuser" "/tmp/x-cu-fu/b")) (fixed (list "fuser" "/tmp/x-cu-fu/a/lib")))
```
---
```output
100 |
stderr:
status 0
100 |
stderr:
status 0
500 |
stderr:
status 0
300 |
stderr:
status 0
```

### several operands, in pid order; -m finds every process with anything on the file's device

```cu
(do (fixed (list "fuser" "/tmp/x-cu-fu/b/other" "/tmp/x-cu-fu/a/held")) (fixed (list "fuser" "-m" "/tmp/x-cu-fu/a/held")))
```
---
```output
100 200 |
stderr:
status 0
100 200 300 500 |
stderr:
status 0
```

### -s prints nothing and still answers 0; a file nothing holds answers 1

```cu
(do (fixed (list "fuser" "-s" "/tmp/x-cu-fu/a/held")) (fixed (list "fuser" "/tmp/x-cu-fu/proc/stat")))
```
---
```output
stderr:
status 0
stderr:
status 1
```

### a file that will not stat ends the run before any is matched, as does a PORT/PROTO with no such protocol

```cu
(do (fixed (list "fuser" "/tmp/x-cu-fu/a/held" "/tmp/x-cu-fu/nosuch")) (fixed (list "fuser" "80/xyz")))
```
---
```output
stderr:
fuser: can't stat '/tmp/x-cu-fu/nosuch': No such file or directory
status 1
stderr:
fuser: can't stat '80/xyz': No such file or directory
status 1
```

## ports

### PORT/PROTO finds the socket bound to it; tcp names IPv4 and tcp6 IPv6, as busybox reads one /proc/net table

```cu
(do (fixed (list "fuser" "8080/tcp")) (fixed (list "fuser" "80/tcp6")) (fixed (list "fuser" "80/tcp")) (fixed (list "fuser" "8080/tcp6")))
```
---
```output
200 |
stderr:
status 0
400 |
stderr:
status 0
stderr:
status 1
stderr:
status 1
```

### -4 passes over IPv6 and -6 over IPv4; a protocol is read to four bytes

```cu
(do (fixed (list "fuser" "-4" "80/tcp6")) (fixed (list "fuser" "-6" "8080/tcp")) (fixed (list "fuser" "-6" "80/tcp6")) (fixed (list "fuser" "80/tcp6x")))
```
---
```output
stderr:
status 1
stderr:
status 1
400 |
stderr:
status 0
400 |
stderr:
status 0
```

## -SIGNAL

### the first -SIGNAL before a -- is set aside wherever it stands; a second reaches getopt

```cu
(do (fixed (list "fuser" "-s" "-HUP" "/tmp/x-cu-fu/a/held")) (fixed (list "fuser" "/tmp/x-cu-fu/a/held" "-9")) (fixed (list "fuser" "--" "-HUP")))
```
---
```output
stderr:
status 0
100 |
stderr:
status 0
stderr:
fuser: can't stat '-HUP': No such file or directory
status 1
```

## this machine

### -k signals a process this spec started that holds a file, with the signal asked for

```cu
(do (def kid (sys-fork)) (if (= kid 0) (do (sys-exec "/bin/sh" (list "-c" "exec /bin/sleep 600.4243 < /tmp/x-cu-fu/b/other")) (sys-exit 127)) ()) (def exec-wait (fn (self n) (if (if (> n 0) (not (str=? (host-exe kid) "/bin/sleep")) #f) (do (sys-usleep 20000) (self (- n 1))) ()))) (exec-wait 250) (sys-dup2 1 9) (def oo (file-open-write (nf ".out"))) (sys-dup2 oo 1) (def st (cu-run (list "fuser" "-k" "-INT" "/tmp/x-cu-fu/b/other") "")) (sys-dup2 9 1) (file-close oo) (def out (file-read-all (nf ".out"))) (sys-kill kid 9) (def w (sys-wait kid)) (list (Str8 includes? (string-append (cu-int->str kid) " ") out) st w))
```
---
    (#t 0 130)

## cleanup

### the scratch directory goes

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-fu")) (display "gone"))
```
---
    gone
