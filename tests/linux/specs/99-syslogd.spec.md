# @weight 2
# @timeout-scale 3

busybox's syslogd (sysklogd/syslogd.c), run as root.  Each case starts the
bundle's syslogd with the case's arguments in a child, sends it datagrams
on /dev/log, ends it with SIGTERM and shows what it wrote, its status and
the files the case names; then the same with busybox-extra's.  The stamps
syslogd makes are written STAMP -- a message's own, Feb 29 12:34:56, is
kept -- and the started line names no version.

## the comparison

### the applet against busybox's, the files a case names

```cu
(do (def sl-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def sl-bytes (fn (_ l) (bytes->str (map (fn (_ c) (if (number? c) c (byte-at c 0))) l))))
    ; DATAGRAMS to /dev/log, in order
    (def sl-send (fn (_ datagrams)
      (do (def fd (Socket unix-dgram-connect "/dev/log"))
          (map (fn (_ d) (cu-ptr-call (cu-libc-sym "send") fd (cu-str->ptr d) (byte-len d) 0)) datagrams)
          (Socket close fd))))
    (def sl-start (fn (_ side args)
      (do (def pid (sys-fork))
          (when (= pid 0)
            (guard (e (sys-exit 99))
              (let ((ee (file-open-write "/tmp/sl-err")))
                (do (sys-dup2 ee 1) (sys-dup2 ee 2)
                    (if (string=? side "ours")
                      (sys-exit (cu-run (pair "syslogd" args) ""))
                      (do (sys-exec "/usr/local/bin/busybox-extra" (pair "syslogd" args))
                          (sys-exit 98)))))))
          (sl-sh "sleep 0.5")
          pid)))
    (def sl-norm (fn (_ path)
      (if (not (file-exists? path)) "(none)\n"
        (do (sl-sh (%str-concat (list "sed -e '/^Feb 29 12:34:56 /!s/^[A-Z][a-z][a-z] [ 0-9][0-9] [0-9:]\\{8\\}/STAMP/'"
                                        " -e 's/syslogd started: .*/syslogd started/' " path " > /tmp/sl-norm")))
            (file-read-all "/tmp/sl-norm")))))
    ; a side's run: the datagrams sent, then STEP, then SIGTERM
    (def sl-side (fn (_ side args datagrams step files)
      (do (sl-sh "rm -f /tmp/sl-* /var/run/syslogd.pid")
          (def pid (sl-start side args))
          (sl-send datagrams)
          (sl-sh "sleep 0.3")
          (def seen (step))
          (if (List any? (fn (_ a) (string=? a "-n")) args) (sys-kill pid 15)
            (sl-sh "kill $(cat /var/run/syslogd.pid)"))
          (def st (sys-wait pid))
          (sl-sh "sleep 0.3")
          (%str-concat (list seen "out:\n" (sl-norm "/tmp/sl-err") "status " (cu-int->str st) "\n"
                               "pidfile " (if (file-exists? "/var/run/syslogd.pid") "left" "gone") "\n"
                               (%str-concat (map (fn (_ f) (%str-concat (list f ":\n" (sl-norm f)))) files)))))))
    (def sl-case (fn (_ args datagrams step files)
      (do (def a (sl-side "ours" args datagrams step files))
          (def b (sl-side "bb" args datagrams step files))
          (display (if (string=? a b) "same\n" (%str-concat (list "ours:\n" a "busybox:\n" b)))))))
    (def sl-none (fn (_) ""))
    (def sl-rep (fn (_ s n) (if (= n 0) "" (string-append s (sl-rep s (- n 1))))))
    (display "made"))
```
---
    made

## a message's parts

### the priority read, the stamp kept or made, controls escaped, NULs split

A priority past 1023, or one that is not a number, is user.notice; a
facility with no name is written <PRI>; a newline is a space, a control
^X but tab; the newlines and NULs at a datagram's end go.

```cu
(sl-case (list "-n" "-O" "/tmp/sl-log")
  (list "<13>hello" "<14>Feb 29 12:34:56 tag: own stamp" "no priority" "<191>local7 debug"
        "<1000>big facility" "<1024>too big" "<abc>x" "<12x>y" "<>z" "<9999999999>w"
        (sl-bytes (list "t" "w" "o" 0 "<" "1" "1" ">" "p" "a" "r" "t"))
        (sl-bytes (list "c" 1 27 9 "t" 10 "n" 127 200))
        (sl-bytes (list "e" "n" "d" 10 0 0))
        (sl-bytes (list 0)) "")
  sl-none (list "/tmp/sl-log"))
```
---
```output
same
```

### -S, the short line; -t, the message's own stamp dropped

```cu
(do (sl-case (list "-n" "-S" "-O" "/tmp/sl-log") (list "<13>short" "<14>Feb 29 12:34:56 own") sl-none (list "/tmp/sl-log"))
    (sl-case (list "-n" "-t" "-O" "/tmp/sl-log") (list "<13>Feb 29 12:34:56 dropped") sl-none (list "/tmp/sl-log")))
```
---
```output
same
same
```

### -l, the more urgent only; -D, a repeat dropped

```cu
(do (sl-case (list "-n" "-l" "4" "-O" "/tmp/sl-log")
      (list "<0>emerg" "<3>err" "<4>warning" "<7>debug" "<35>auth err") sl-none (list "/tmp/sl-log"))
    (sl-case (list "-n" "-D" "-O" "/tmp/sl-log")
      (list "<13>again" "<13>again" "<13>again\n" "<13>other" "<13>again") sl-none (list "/tmp/sl-log")))
```
---
```output
same
same
```

### -O -, standard output

```cu
(sl-case (list "-n" "-O" "-") (list "<13>to stdout") sl-none ())
```
---
```output
same
```

## the config

### the rules: lists, =, !, none, *, and the file -O names shared

```cu
(do (file-write-all "/tmp/sl.conf"
      (%str-concat (list "# rules\n"
                         "kern,mail.info /tmp/sl-a\n"
                         "*.=err /tmp/sl-b\n"
                         "user.!notice\t/tmp/sl-c\n"
                         "*.*;auth.none;mark.* /tmp/sl-d   # all\n"
                         "local0.* /tmp/sl-log\n")))
    (sl-case (list "-n" "-f" "/tmp/sl.conf" "-O" "/tmp/sl-log")
      (list "<0>kern emerg" "<6>kern info" "<7>kern debug" "<19>mail err" "<11>user err"
            "<13>user notice" "<14>user info" "<36>auth warning" "<134>local0 info" "<157>local3 notice")
      sl-none (list "/tmp/sl-a" "/tmp/sl-b" "/tmp/sl-c" "/tmp/sl-d" "/tmp/sl-log")))
```
---
```output
same
```

## the files

### rotation: past -s KB the file moves to .0, .0 to .1, with -b 2

```cu
(sl-case (list "-n" "-s" "1" "-b" "2" "-O" "/tmp/sl-log")
  (map (fn (_ i) (string-append "<13>" (sl-rep "r" 200))) (List range 0 14))
  sl-none (list "/tmp/sl-log" "/tmp/sl-log.0" "/tmp/sl-log.1" "/tmp/sl-log.2"))
```
---
```output
same
```

### -b 0: the full file purged

```cu
(sl-case (list "-n" "-s" "1" "-b" "0" "-O" "/tmp/sl-log")
  (map (fn (_ i) (string-append "<13>" (sl-rep "p" 200))) (List range 0 7))
  sl-none (list "/tmp/sl-log" "/tmp/sl-log.0"))
```
---
```output
same
```

## the other ends

### -C, the shared buffer, as busybox's logread reads it

```cu
(sl-case (list "-n" "-C" "-O" "/tmp/sl-log") (list "<13>buffered one" "<11>buffered two")
  (fn (_) (do (sl-sh "/usr/local/bin/busybox-extra logread > /tmp/sl-read 2>&1")
              (string-append "logread:\n" (sl-norm "/tmp/sl-read"))))
  (list "/tmp/sl-log"))
```
---
```output
same
```

### -C 4 KB, the ring around its end

```cu
(sl-case (list "-n" "-C4" "-O" "/tmp/sl-log")
  (map (fn (_ i) (string-append "<13>" (sl-rep (cu-int->str (% i 10)) 150))) (List range 0 30))
  (fn (_) (do (sl-sh "/usr/local/bin/busybox-extra logread > /tmp/sl-read 2>&1")
              (string-append "logread:\n" (sl-norm "/tmp/sl-read"))))
  ())
```
---
```output
same
```

### -R, each datagram sent on with a newline; with -L kept here too

```cu
(do (def sl-udp (fn (_)
      (do (def fd (net-udp-bind 5514))
          (def pid (sys-fork))
          (when (= pid 0)
            (guard (_ (sys-exit 0))
              (let go ()
                (let ((r (Socket recv-run fd 1024)))
                  (do (let ((f (file-open-append "/tmp/sl-udp")))
                        (do (file-write f (%str-concat (list "[" (substring (first r) 0 (rest r)) "]\n"))) (file-close f)))
                      (go))))))
          (sys-close fd)
          pid)))
    (def sl-remote (fn (_ args)
      (do (def u (sl-udp))
          (sl-case args (list "<13>far" "<14>away\n")
            (fn (_) (do (sl-sh "sleep 0.2") (string-append "udp:\n" (sl-norm "/tmp/sl-udp"))))
            (list "/tmp/sl-log"))
          (sys-kill u 9) (sys-wait u) ())))
    (sl-remote (list "-n" "-R" "127.0.0.1:5514" "-O" "/tmp/sl-log"))
    (sl-remote (list "-n" "-R" "127.0.0.1:5514" "-L" "-O" "/tmp/sl-log")))
```
---
```output
same
same
```

## the daemon

### without -n, in the background, its pid in /var/run/syslogd.pid

```cu
(sl-case (list "-O" "/tmp/sl-log") (list "<13>from the background") sl-none (list "/tmp/sl-log"))
```
---
```output
same
```
