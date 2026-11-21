# @weight 2
# @timeout-scale 3

busybox's klogd (sysklogd/klogd.c), run as root.  A forked reader holds
/dev/log and keeps each datagram.  Each side's klogd starts and reads the
ring's unread lines, which are dropped; then the lines a case writes to
/dev/kmsg are read and sent on, and SIGTERM ends it.  What it sent, its
status and its pidfile are compared with busybox-extra's.  Stamps are
written STAMP and the kernel's [seconds] as [T]; the started line names
no version.

## the comparison

### the applet against busybox's, the datagrams it sends

```cu
(do (def kl-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    ; the datagrams on /dev/log, each a line of /tmp/kl-dg
    (def kl-reader (fn (_)
      (do (kl-sh "rm -f /dev/log /tmp/kl-dg")
          (def fd (Socket unix-dgram-bind "/dev/log"))
          (def pid (sys-fork))
          (when (= pid 0)
            (guard (_ (sys-exit 0))
              (let go ()
                (let ((r (Socket recv-run fd 2048)))
                  (do (let ((f (file-open-append "/tmp/kl-dg")))
                        (do (file-write f (string-append (substring (first r) 0 (rest r)) "\n")) (file-close f)))
                      (go))))))
          (sys-close fd)
          pid)))
    (def kl-start (fn (_ side args)
      (do (def pid (sys-fork))
          (when (= pid 0)
            (guard (e (sys-exit 99))
              (let ((ee (file-open-write "/tmp/kl-err")))
                (do (sys-dup2 ee 1) (sys-dup2 ee 2)
                    (if (string=? side "ours")
                      (sys-exit (cu-run (pair "klogd" args) ""))
                      (do (sys-exec "/usr/local/bin/busybox-extra" (pair "klogd" args))
                          (sys-exit 98)))))))
          pid)))
    (def kl-norm (fn (_ path)
      (if (not (file-exists? path)) "(none)\n"
        (do (kl-sh (%str-concat (list "sed -e 's/^\\(<[0-9]*>\\)[A-Z][a-z][a-z] [ 0-9][0-9] [0-9:]\\{8\\} /\\1STAMP /'"
                                        " -e 's/\\[ *[0-9]*\\.[0-9]*\\] /[T] /'"
                                        " -e 's/klogd started: .*/klogd started/' " path " > /tmp/kl-norm")))
            (file-read-all "/tmp/kl-norm")))))
    ; a side's run: started, the backlog read and dropped, LINES written to
    ; /dev/kmsg, then SIGTERM -- to the child with -n, else by the pidfile
    (def kl-side (fn (_ side args lines step)
      (do (kl-sh "rm -f /tmp/kl-err /var/run/klogd.pid")
          (def r (kl-reader))
          (def pid (kl-start side args))
          (kl-drain 60)
          (kl-sh "grep 'klogd started' /tmp/kl-dg > /tmp/kl-started; rm -f /tmp/kl-dg")
          (map (fn (_ l) (kl-sh (string-append "printf '%s\\n' '" (string-append l "' > /dev/kmsg")))) lines)
          (kl-sh "sleep 1")
          (def seen (step))
          (if (List any? (fn (_ a) (string=? a "-n")) args) (sys-kill pid 15)
            (kl-sh "kill $(cat /var/run/klogd.pid)"))
          (def st (sys-wait pid))
          (kl-sh "sleep 0.3")
          (sys-kill r 9) (sys-wait r)
          (%str-concat (list (kl-norm "/tmp/kl-started") (kl-norm "/tmp/kl-dg") seen
                             "err:\n" (kl-norm "/tmp/kl-err") "status " (cu-int->str st) "\n"
                             "pidfile " (if (file-exists? "/var/run/klogd.pid") "left" "gone") "\n")))))
    (def kl-case (fn (_ args lines step)
      (do (def a (kl-side "ours" args lines step))
          (def b (kl-side "bb" args lines step))
          (display (if (string=? a b) "same\n" (%str-concat (list "ours:\n" a "busybox:\n" b)))))))
    ; the ring read to its end, then a moment for the sends, or N tries of a fifth of a second
    (def kl-drain (fn (_ n)
      (do (kl-sh "sleep 0.5")
          (if (if (> n 0) (> (in-call (cu-ptr-call (cu-libc-sym "klogctl") 9 (cu-int->ptr 0) 0)) 0) #f)
            (do (kl-sh "sleep 0.2") (kl-drain (- n 1)))
            (kl-sh "sleep 0.5")))))
    (def kl-out (fn (_ cmd) (do (kl-sh (string-append cmd " > /tmp/kl-out")) (file-read-all "/tmp/kl-out"))))
    (def kl-none (fn (_) ""))
    (def kl-rep (fn (_ s n) (if (= n 0) "" (string-append s (kl-rep s (- n 1))))))
    (display "made"))
```
---
    made

## the lines

### priorities read, a line with none, the kernel's facility kept

```cu
(kl-case (list "-n")
  (list "<6>info line" "<3>error line" "no priority" "<14>user info" "<0>emergency" "<6>100% sure")
  kl-none)
```
---
```output
same
```

### many lines, past one read's 1024 bytes

```cu
(kl-case (list "-n")
  (map (fn (_ i) (string-append "<6>" (kl-rep (cu-int->str (% i 10)) 200))) (List range 0 12))
  kl-none)
```
---
```output
same
```

## the options

### -c N: the console's level while it runs

```cu
(do (def kl-was (kl-out "cut -f1 /proc/sys/kernel/printk | tr -d '\\n'"))
    (kl-case (list "-n" "-c" "3") (list "<6>with -c")
      (fn (_) (string-append "printk " (kl-out "cut -f1 /proc/sys/kernel/printk"))))
    (kl-sh (string-append "echo " (string-append kl-was " > /proc/sys/kernel/printk")))
    ())
```
---
```output
same
```

### without -n, in the background, its pid in /var/run/klogd.pid

```cu
(kl-case () (list "<6>from the background") kl-none)
```
---
```output
same
```
