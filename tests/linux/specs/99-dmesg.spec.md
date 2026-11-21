# @weight 2

busybox's dmesg (util-linux/dmesg.c), run as root against the kernel's
ring.  Each case runs the bundle's applet and busybox-extra's on the same
words and compares what they write and their status: `same`, or the two
answers when they differ.  The ring can take a line from the kernel
between two reads, so a case reads busybox's answer before and after its
own, and reads again, to three times, until the two agree.

## the comparison

### the applet against busybox's, by what it writes and its status

```cu
(do (def dm-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def dm-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def dm-x (fn (_ argv)
      (do (def dm-pid (sys-fork))
          (when (= dm-pid 0)
            (let ((o (file-open-write "/tmp/dm-xo")) (e (file-open-write "/tmp/dm-xe")))
              (do (sys-dup2 o 1) (sys-dup2 e 2) (sys-exit (cu-run argv "")))))
          (def dm-st (sys-wait dm-pid))
          (%str-concat (list (file-read-all "/tmp/dm-xo") "stderr:\n" (file-read-all "/tmp/dm-xe")
                             "status " (cu-int->str dm-st) "\n")))))
    (def dm-bb (fn (_ argv)
      (do (dm-sh (%str-concat (list "/usr/local/bin/busybox-extra " (Str8 join " " (map dm-q argv))
                                    " > /tmp/dm-bo 2> /tmp/dm-bx; echo $? > /tmp/dm-bs; sed '/^BusyBox v/{N;d;}' /tmp/dm-bx > /tmp/dm-be")))
          (%str-concat (list (file-read-all "/tmp/dm-bo") "stderr:\n" (file-read-all "/tmp/dm-be")
                             "status " (file-read-all "/tmp/dm-bs"))))))
    (def dm-show (fn (_ a b) (display (if (string=? a b) "same\n" (%str-concat (list "ours:\n" a "busybox:\n" b))))))
    ; ARGV on each side, busybox's read on both sides of ours until they agree
    (def dm-case (fn (_ argv)
      (let go ((tries 3))
        (do (def b1 (dm-bb argv)) (def a (dm-x argv)) (def b2 (dm-bb argv))
            (if (if (string=? b1 b2) #t (= tries 1)) (dm-show a b1) (go (- tries 1)))))))
    ; LINES written to the kernel's ring
    (def dm-kmsg (fn (_ lines)
      (map (fn (_ l) (dm-sh (string-append "printf '%s\\n' " (string-append (dm-q l) " > /dev/kmsg")))) lines)))
    (dm-kmsg (list "<6>x-cu dmesg: info" "<3>x-cu dmesg: <b> not a priority" "x-cu dmesg: none"))
    (display "made"))
```
---
    made

## reading the ring

### the lines, their <PRI> taken out; -r leaves them in

```cu
(do (dm-case (list "dmesg"))
    (dm-case (list "dmesg" "-r")))
```
---
```output
same
same
```

### -s SIZE: the last SIZE bytes, 16 KB at the least

```cu
(do (dm-case (list "dmesg" "-s" "20000"))
    (dm-case (list "dmesg" "-r" "-s" "100")))
```
---
```output
same
same
```

### -c: the ring printed, then cleared

```cu
(do (def dm-clear (fn (_) (dm-sh "/usr/local/bin/busybox-extra dmesg -c > /dev/null")))
    ; S with the kernel's [seconds] at each line's start taken out
    (def dm-unstamp (fn (_ s)
      (do (let ((f (file-open-write "/tmp/dm-s"))) (do (file-write f s) (file-close f)))
          (dm-sh "sed 's/^\\[ *[0-9]*\\.[0-9]*\\] //' /tmp/dm-s > /tmp/dm-u")
          (file-read-all "/tmp/dm-u"))))
    (dm-clear)
    (dm-kmsg (list "<6>x-cu dmesg: before -c"))
    (def a (dm-unstamp (dm-x (list "dmesg" "-c"))))
    (def a-after (dm-x (list "dmesg")))
    (dm-clear)
    (dm-kmsg (list "<6>x-cu dmesg: before -c"))
    (def b (dm-unstamp (dm-bb (list "dmesg" "-c"))))
    (def b-after (dm-bb (list "dmesg")))
    (dm-show a b)
    (dm-show a-after b-after))
```
---
```output
same
same
```

## the options

### -n LEVEL: the console's level, and nothing printed

```cu
(do (dm-sh "cut -f1 /proc/sys/kernel/printk | tr -d '\\n' > /tmp/dm-was")
    (def was (file-read-all "/tmp/dm-was"))
    (def a (dm-x (list "dmesg" "-n" "5")))
    (dm-sh "cut -f1 /proc/sys/kernel/printk > /tmp/dm-now")
    (def a-now (file-read-all "/tmp/dm-now"))
    (dm-sh (string-append "echo " (string-append was " > /proc/sys/kernel/printk")))
    (def b (dm-bb (list "dmesg" "-n" "5")))
    (dm-sh "cut -f1 /proc/sys/kernel/printk > /tmp/dm-now")
    (def b-now (file-read-all "/tmp/dm-now"))
    (dm-sh (string-append "echo " (string-append was " > /proc/sys/kernel/printk")))
    (dm-show (string-append a a-now) (string-append b b-now)))
```
---
    same

### the refusals: an unknown option, and numbers out of their range

```cu
(do (dm-case (list "dmesg" "-x"))
    (dm-case (list "dmesg" "-s" "x"))
    (dm-case (list "dmesg" "-s" "2147483648"))
    (dm-case (list "dmesg" "-n" "-1"))
    (dm-case (list "dmesg" "-n" "99")))
```
---
```output
same
same
same
same
same
```
