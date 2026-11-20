# @weight 2
# @timeout-scale 3

busybox's logread (sysklogd/logread.c), run as root.  busybox-extra's
syslogd -C writes the shared buffer; the bundle's logread and busybox's
read the same one, so what each writes is compared as it stands.

## the comparison

### the applet against busybox's, on the same buffer

```cu
(do (def lr-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lr-send (fn (_ datagrams)
      (do (def fd (Socket unix-dgram-connect "/dev/log"))
          (map (fn (_ d) (cu-ptr-call (cu-libc-sym "send") fd (cu-str->ptr d) (byte-len d) 0)) datagrams)
          (Socket close fd)
          (lr-sh "sleep 0.3"))))
    ; busybox's syslogd with ARGS, in the foreground, its pid
    (def lr-syslogd (fn (_ args)
      (do (lr-sh "rm -f /tmp/lr-* /dev/log; ipcrm -M 0x414e4547 -S 0x414e4547 2>/dev/null")
          (def pid (sys-fork))
          (when (= pid 0)
            (do (sys-exec "/usr/local/bin/busybox-extra" (append (list "syslogd" "-n" "-O" "/tmp/lr-log") args))
                (sys-exit 98)))
          (lr-sh "sleep 0.5")
          pid)))
    (def lr-stop (fn (_ pid) (do (sys-kill pid 15) (sys-wait pid) (lr-sh "sleep 0.2") ())))
    ; SIDE's logread with ARGS, its output and errors to OUT, in a child
    (def lr-start (fn (_ side args out)
      (do (def pid (sys-fork))
          (when (= pid 0)
            (guard (e (sys-exit 99))
              (let ((f (file-open-write out)))
                (do (sys-dup2 f 1) (sys-dup2 f 2)
                    (if (string=? side "ours")
                      (sys-exit (cu-run (pair "logread" args) ""))
                      (do (sys-exec "/usr/local/bin/busybox-extra" (pair "logread" args))
                          (sys-exit 98)))))))
          pid)))
    (def lr-show (fn (_ path) (if (file-exists? path) (file-read-all path) "(none)\n")))
    ; both with ARGS, to their end
    (def lr-once (fn (_ args)
      (do (def a (sys-wait (lr-start "ours" args "/tmp/lr-ours")))
          (def b (sys-wait (lr-start "bb" args "/tmp/lr-bb")))
          (%str-concat (list "status " (cu-int->str a) "\n" (lr-show "/tmp/lr-ours")
                             "status " (cu-int->str b) "\n" (lr-show "/tmp/lr-bb"))))))
    (def lr-same (fn (_ args)
      (do (def a (sys-wait (lr-start "ours" args "/tmp/lr-ours")))
          (def b (sys-wait (lr-start "bb" args "/tmp/lr-bb")))
          (def oa (lr-show "/tmp/lr-ours"))
          (def ob (lr-show "/tmp/lr-bb"))
          (display (if (if (= a b) (string=? oa ob) #f) "same\n"
                     (%str-concat (list "ours: " (cu-int->str a) "\n" oa "busybox: " (cu-int->str b) "\n" ob)))))))
    ; both following with ARGS while DATAGRAMS are sent, then SIGTERM
    (def lr-follow (fn (_ args datagrams)
      (do (def a (lr-start "ours" args "/tmp/lr-ours"))
          (def b (lr-start "bb" args "/tmp/lr-bb"))
          (lr-sh "sleep 0.5")
          (lr-send datagrams)
          (lr-sh "sleep 2.5")
          (sys-kill a 15) (sys-kill b 15)
          (def sa (sys-wait a))
          (def sb (sys-wait b))
          (def oa (lr-show "/tmp/lr-ours"))
          (def ob (lr-show "/tmp/lr-bb"))
          (display (if (if (= sa sb) (string=? oa ob) #f) "same\n"
                     (%str-concat (list "ours: " (cu-int->str sa) "\n" oa "busybox: " (cu-int->str sb) "\n" ob)))))))
    (def lr-rep (fn (_ s n) (if (= n 0) "" (string-append s (lr-rep s (- n 1))))))
    (display "made"))
```
---
    made

## no buffer

### no syslogd -C: the buffer not found

```cu
(do (lr-sh "ipcrm -M 0x414e4547 -S 0x414e4547 2>/dev/null")
    (display (lr-once ())))
```
---
```output
status 1
logread: can't find syslogd buffer: No such file or directory
status 1
logread: can't find syslogd buffer: No such file or directory
```

## once

### the messages, oldest first, an operand ignored

```cu
(do (def s (lr-syslogd (list "-C")))
    (lr-send (list "<13>one" "<11>two" "<14>three"))
    (lr-same ())
    (lr-same (list "extra"))
    (lr-stop s))
```
---
```output
same
same
```

### -C 4 KB, past its end: the message the tail cut dropped

```cu
(do (def s (lr-syslogd (list "-C4")))
    (lr-send (map (fn (_ i) (string-append "<13>" (lr-rep (cu-int->str (% i 10)) 150))) (List range 0 30)))
    (lr-same ())
    (lr-stop s))
```
---
```output
same
```

## following

### -F: the buffer, then what comes

```cu
(do (def s (lr-syslogd (list "-C")))
    (lr-send (list "<13>before"))
    (lr-follow (list "-F") (list "<13>after one" "<13>after two"))
    (lr-stop s))
```
---
```output
same
```

### -f: only what comes

```cu
(do (def s (lr-syslogd (list "-C")))
    (lr-send (list "<13>before"))
    (lr-follow (list "-f") (list "<13>after"))
    (lr-stop s))
```
---
```output
same
```
