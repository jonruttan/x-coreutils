# @weight 1

busybox's smemcap (procps/smemcap.c), run as root against busybox's own.
busybox's reads /proc by that name, so it runs chrooted into a directory
holding itself, musl's loader and the tree bound on as /proc, while the
bundle's reads the tree through Host's proc-root; the two archives are
compared byte for byte.  On the kernel's /proc each side's own processes
differ, so the members that hold still are compared: version, and the
first process's directory and cmdline.

## the comparison

### trees, a root for busybox over each, and the two runs

```cu
(do (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (lx-sh (string-append
      "rm -rf /tmp/x-cu-smc && mkdir -p /tmp/x-cu-smc/a/1 /tmp/x-cu-smc/a/300 /tmp/x-cu-smc/a/21 /tmp/x-cu-smc/a/net /tmp/x-cu-smc/b/42 /tmp/x-cu-smc/c/7 /tmp/x-cu-smc/empty && cd /tmp/x-cu-smc && "
      "for d in a b c; do printf 'MemTotal:       16384000 kB\\nMemFree:         1234567 kB\\n' > $d/meminfo && printf 'Linux version 6.6.0 (x@y) #1 SMP\\n' > $d/version; done && "
      "i=0; while [ $i -lt 24 ]; do printf 'Rss:           %5d kB\\n' $i; i=$((i+1)); done > a/1/smaps && "
      "printf 'init\\000--x\\000' > a/1/cmdline && printf '1 (init) S 0 1 1 0 -1 4194560\\n' > a/1/stat && "
      "ln -s 1 a/self && printf 'sh\\000' > a/300/cmdline && printf '300 (sh) S 1 300 300 0 -1 0\\n' > a/300/stat && printf '21 (ksoftirqd/1) S 2 0 0 0 -1 0\\n' > a/21/stat && : > a/net/dev && "
      "i=0; while [ $i -lt 511 ]; do printf a; i=$((i+1)); done > b/42/smaps && printf '\\n' >> b/42/smaps && "
      ": > b/42/cmdline && printf '42 (kthreadd) S 0 0 0 0 -1 2129984\\n' > b/42/stat && "
      "printf '7 (sh) Z 1 7 7 0 -1 4227084\\n' > c/7/stat && chmod 400 a/1/smaps && chown 1:2 a/1/stat && "
      "find a b c -type f -exec touch -t 202601020304.05 {} + && "
      "for d in a b c empty none; do mkdir -p r$d/lib && cp /usr/local/bin/busybox-extra r$d/ && cp /lib/ld-musl-*.so.1 r$d/lib/ && "
      "if [ -d $d ]; then mkdir r$d/proc && mount --bind $d r$d/proc; fi; done"))
    (def lx-nf (fn (_ n) (string-append "/tmp/x-cu-smc/" n)))
    ; ours on ROOT: the archive in the file ours.tar, then stderr and status
    (def lx-ours (fn (_ root)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (lx-nf "ours.tar"))) (ee (file-open-write (lx-nf "ours.err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (Host proc-root root)
                (def st (cu-run (list "smemcap") ""))
                (Host proc-root "/proc")
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (%str-concat (list "stderr:\n" (file-read-all (lx-nf "ours.err")) "status " (cu-int->str st) "\n")))))))
    ; busybox's, chrooted into R or on the kernel's /proc: the archive in bb.tar
    (def lx-bb (fn (_ cmd)
      (do (lx-sh (%str-concat (list cmd " > /tmp/x-cu-smc/bb.tar 2> /tmp/x-cu-smc/bb.raw; echo $? > /tmp/x-cu-smc/bb.st; sed '/^BusyBox v/{N;d;}' /tmp/x-cu-smc/bb.raw > /tmp/x-cu-smc/bb.err")))
          (%str-concat (list "stderr:\n" (file-read-all (lx-nf "bb.err")) "status " (file-read-all (lx-nf "bb.st")))))))
    (def lx-same? (fn (_) (= (lx-sh "cmp -s /tmp/x-cu-smc/ours.tar /tmp/x-cu-smc/bb.tar") 0)))
    ; the tree D both ways, the archives' bytes and the runs' words compared
    (def lx-tree (fn (_ d)
      (do (def lx-a (Str8 replace (lx-nf d) "/proc" (lx-ours (lx-nf d))))
          (def lx-b (lx-bb (%str-concat (list "chroot /tmp/x-cu-smc/r" d " /busybox-extra smemcap"))))
          (display (if (if (string=? lx-a lx-b) (lx-same?) #f) "same\n"
                     (%str-concat (list "ours:\n" lx-a "busybox:\n" lx-b
                                          (if (lx-same?) "" "the archives differ\n"))))))))
    ; what holds still in an archive of the kernel's /proc, F ours.tar or
    ; bb.tar: the members named, their modes and owners, in order; version's
    ; and the first process's cmdline's bytes.  A /proc file's time is when its inode
    ; was made, which may be either run's.
    (def lx-still (fn (_ f)
      (do (lx-sh (%str-concat (list "cd /tmp/x-cu-smc && { busybox tar tvf " f " | awk '$NF ~ /^(meminfo|version|1|1\\/smaps|1\\/cmdline|1\\/stat)$/ { print $1, $2, $NF }'; busybox tar xOf " f " version 1/cmdline | od -c; } > " f ".still")))
          (file-read-all (lx-nf (string-append f ".still"))))))
    (display (if (file-exists? (lx-nf "rnone/busybox-extra")) "made" "fixture incomplete")))
```
---
    made

## trees

### processes in the order listed, a file of two blocks, a cmdline's NULs, a file only its owner reads and one owned by another

```cu
(lx-tree "a")
```
---
    same

### a file of exactly one block and an empty one; a process with only its stat

```cu
(do (lx-tree "b") (lx-tree "c"))
```
---
```output
same
same
```

### a /proc with nothing in it, and none at all

```cu
(do (lx-tree "empty") (lx-tree "none"))
```
---
```output
same
same
```

## the kernel's

### meminfo, version and the first process, each side on /proc

```cu
(do (def lx-a (lx-ours "/proc")) (def lx-b (lx-bb "/usr/local/bin/busybox-extra smemcap"))
    (display (if (string=? lx-a lx-b) "" (%str-concat (list "ours:\n" lx-a "busybox:\n" lx-b))))
    (def lx-sa (lx-still "ours.tar")) (def lx-sb (lx-still "bb.tar"))
    (display (if (if (string=? lx-sa lx-sb) (> (byte-len lx-sa) 0) #f) "same\n" (%str-concat (list "ours:\n" lx-sa "busybox:\n" lx-sb)))))
```
---
    same

## clean up

### the trees

```cu
(do (proc-run (list "/bin/sh" "-c" "for d in a b c empty; do umount /tmp/x-cu-smc/r$d/proc; done; rm -rf /tmp/x-cu-smc")) (display ""))
```
---
```output
```
