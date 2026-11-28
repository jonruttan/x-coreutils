# @weight 2

busybox's fstrim (util-linux/fstrim.c) against busybox-extra's, as root.
A trim is compared on a fresh file system for each side: an ext2 image
made by busybox's mke2fs, on a loop device, mounted at /tmp/ft-mnt.
Each case compares what the applet writes and its status: `same`, or the
two answers when they differ.

## the comparison

### the applet against busybox's, each on its own fresh file system

```cu
(do (def ft-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def ft-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def ft-bb "/usr/local/bin/busybox-extra")
    ; a fresh 8 MB ext2 at /tmp/ft-mnt: 0 once it is mounted
    (def ft-fresh! (fn (_)
      (ft-sh (%str-concat (list "(umount /tmp/ft-mnt 2>/dev/null; for d in $(" ft-bb " losetup -a 2>/dev/null | grep /tmp/ft-img | cut -d: -f1); do " ft-bb " losetup -d $d; done; "
                                "rm -f /tmp/ft-img && mkdir -p /tmp/ft-mnt && dd if=/dev/zero of=/tmp/ft-img bs=1M count=8 2>/dev/null && "
                                "dev=$(" ft-bb " losetup -f) && " ft-bb " losetup $dev /tmp/ft-img && " ft-bb " mke2fs -q $dev >/dev/null && mount $dev /tmp/ft-mnt) > /tmp/ft-log 2>&1")))))
    (def ft-gone! (fn (_)
      (ft-sh (%str-concat (list "umount /tmp/ft-mnt 2>/dev/null; for d in $(" ft-bb " losetup -a 2>/dev/null | grep /tmp/ft-img | cut -d: -f1); do " ft-bb " losetup -d $d; done; rm -f /tmp/ft-img")))))
    (def ft-x (fn (_ argv)
      (do (def pid (sys-fork))
          (when (= pid 0)
            (let ((o (file-open-write "/tmp/ft-xo")) (e (file-open-write "/tmp/ft-xe")))
              (do (sys-dup2 o 1) (sys-dup2 e 2) (sys-exit (cu-run argv "")))))
          (def st (sys-wait pid))
          (%str-concat (list (file-read-all "/tmp/ft-xo") "stderr:\n" (file-read-all "/tmp/ft-xe")
                             "status " (cu-int->str st) "\n")))))
    (def ft-b (fn (_ argv)
      (do (ft-sh (%str-concat (list ft-bb " " (Str8 join " " (map ft-q argv))
                                    " < /dev/null > /tmp/ft-bo 2> /tmp/ft-bx; echo $? > /tmp/ft-bs; sed '/^BusyBox v/{N;d;}' /tmp/ft-bx > /tmp/ft-be")))
          (%str-concat (list (file-read-all "/tmp/ft-bo") "stderr:\n" (file-read-all "/tmp/ft-be")
                             "status " (file-read-all "/tmp/ft-bs"))))))
    ; ARGV on each side, each after a fresh file system where FRESH
    (def ft-case (fn (_ fresh argv)
      (do (when fresh (ft-fresh!)) (def a (ft-x argv))
          (when fresh (ft-fresh!)) (def b (ft-b argv))
          (display (if (string=? a b) "same\n" (%str-concat (list "ours:\n" a "busybox:\n" b)))))))
    (display (if (= (ft-fresh!) 0) "made" (string-append "no loop file system: " (Str8 replace "\n" " | " (file-read-all "/tmp/ft-log")))))
    ())
```
---
    made

## the trim

### the whole file system, a range of it, a minimum extent, the long names

```cu
(do (ft-case #t (list "fstrim" "-v" "/tmp/ft-mnt"))
    (ft-case #t (list "fstrim" "/tmp/ft-mnt"))
    (ft-case #t (list "fstrim" "-v" "-o" "1M" "-l" "4M" "/tmp/ft-mnt"))
    (ft-case #t (list "fstrim" "-v" "-m" "64k" "/tmp/ft-mnt"))
    (ft-case #t (list "fstrim" "--verbose" "--offset=2M" "--length" "2M" "--min" "4k" "/tmp/ft-mnt"))
    (ft-gone!)
    ())
```
---
```output
same
same
same
same
same
```

## the refusals

### the usage, numbers it will not read, and the call's own errors

```cu
(do (ft-case #f (list "fstrim"))
    (ft-case #f (list "fstrim" "/" "/tmp"))
    (ft-case #f (list "fstrim" "/" "-v"))
    (ft-case #f (list "fstrim" "-o" "x" "/"))
    (ft-case #f (list "fstrim" "-l" "1kB" "/"))
    (ft-case #f (list "fstrim" "-m" "18014398509481984k" "/"))
    (ft-case #f (list "fstrim" "-v" "/nonexistent"))
    (ft-case #f (list "fstrim" "-v" "/proc")))
```
---
```output
same
same
same
same
same
same
same
same
```

## the clean-up

```cu
(do (ft-gone!)
    (ft-sh "rm -rf /tmp/ft-mnt /tmp/ft-xo /tmp/ft-xe /tmp/ft-bo /tmp/ft-bx /tmp/ft-be /tmp/ft-bs")
    (display "gone"))
```
---
    gone
