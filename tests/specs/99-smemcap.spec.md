# @weight 1

busybox's smemcap (procps/smemcap.c) over /proc trees made here: Host's
proc-root points the applet at each.  The archive is listed and read back
through the bundle's tar, the owner shown as U/G (the files are this
user's); its header fields are shown as bytes, a NUL as a dot.  The Linux
leg compares the bytes with busybox's own, on a tree and on the kernel's
/proc.

## the fixture

### three trees, an empty one, a run of smemcap, its archive listed

```cu
(do (proc-run (list "/bin/sh" "-c" (string-append
      "rm -rf /tmp/x-cu-smc && mkdir -p /tmp/x-cu-smc/a/1 /tmp/x-cu-smc/a/net /tmp/x-cu-smc/b/42 /tmp/x-cu-smc/c/7 /tmp/x-cu-smc/empty && cd /tmp/x-cu-smc && "
      "for d in a b c; do printf 'MemTotal:       16384000 kB\\nMemFree:         1234567 kB\\n' > $d/meminfo && printf 'Linux version 6.6.0 (x@y) #1 SMP\\n' > $d/version; done && "
      "i=0; while [ $i -lt 24 ]; do printf 'Rss:           %5d kB\\n' $i; i=$((i+1)); done > a/1/smaps && "
      "printf 'init\\000--x\\000' > a/1/cmdline && printf '1 (init) S 0 1 1 0 -1 4194560\\n' > a/1/stat && "
      "ln -s 1 a/self && : > a/net/dev && "
      "i=0; while [ $i -lt 511 ]; do printf a; i=$((i+1)); done > b/42/smaps && printf '\\n' >> b/42/smaps && "
      ": > b/42/cmdline && printf '42 (kthreadd) S 0 0 0 0 -1 2129984\\n' > b/42/stat && "
      "printf '7 (sh) Z 1 7 7 0 -1 4227084\\n' > c/7/stat && "
      "find a b c -type f -exec touch -t 202601020304.05 {} +")))
    (def nf (fn (_ n) (string-append "/tmp/x-cu-smc/" n)))
    ; the trees' owner and group, as tar lists them (a new file takes its
    ; directory's group on Darwin)
    (def ids (let ((st (file-stat-full (nf "a/meminfo"))))
               (%str-concat (list (cu-int->str (cu-stat-get st (lit uid))) "/" (cu-int->str (cu-stat-get st (lit gid)))))))
    ; ARGV's run with stdout in the file OUT, its stderr and status shown;
    ; ROOT the /proc it reads
    (def cap (fn (_ root argv out)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (nf out))) (ee (file-open-write (nf ".err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (Host proc-root root)
                (def st (cu-run argv ""))
                (Host proc-root "/proc")
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (%str-concat (list "stderr:\n" (file-read-all (nf ".err")) "status " (cu-int->str st) "\n")))))))
    (def fsize (fn (_ p) (cu-stat-get (file-stat-full p) (lit size))))
    (def show (fn (_ root argv) (do (display (cap root argv "out")) ())))
    ; the archive's listing, and its size in bytes
    (def tv (fn (_)
      (do (def r (cap "/proc" (list "tar" "tvf" (nf "out")) ".tv"))
          (display (%str-concat (list (Str8 replace ids "U/G" (file-read-all (nf ".tv"))) r
                                        "bytes " (cu-int->str (fsize (nf "out"))) "\n")))
          ())))
    ; the member NAME's bytes against the tree's file PATH
    (def same (fn (_ name path)
      (do (cap "/proc" (list "tar" "xOf" (nf "out") name) ".x")
          (display (if (= (proc-run (list "/usr/bin/cmp" "-s" (nf ".x") (nf path))) 0) "same\n" "differ\n"))
          ())))
    ; LEN bytes of the archive from OFF, a NUL as a dot; a digit as d in the
    ; sum, which counts the owner's digits
    (def field (fn (_ off len)
      (do (def s (file-read-all (nf "out")))
          (display (string-append (bytes->str (map (fn (_ i) (let ((b (byte-at s i)))
                                                                (match ((= b 0) #\.)
                                                                       ((if (= off 148) (>= b #\0) #f) #\d)
                                                                       (#t b))))
                                                   (List range off (+ off len))))
                                  "\n"))
          ())))
    (display (if (file-exists? (nf "c/7/stat")) "made" "fixture incomplete")))
```
---
    made

## the archive

### meminfo and version first, then a process's directory and its three files

```cu
(do (show (nf "a") (list "smemcap")) (tv))
```
---
```output
stderr:
status 0
-rw-r--r-- U/G        56 2026-01-02 03:04:05 meminfo
-rw-r--r-- U/G        33 2026-01-02 03:04:05 version
dr-xr-xr-x 0/0         0 1970-01-01 00:00:00 1
-rw-r--r-- U/G       576 2026-01-02 03:04:05 1/smaps
-rw-r--r-- U/G         9 2026-01-02 03:04:05 1/cmdline
-rw-r--r-- U/G        30 2026-01-02 03:04:05 1/stat
stderr:
status 0
bytes 6144
```

### each member's bytes, a cmdline's NULs too

```cu
(do (same "meminfo" "a/meminfo") (same "version" "a/version") (same "1/smaps" "a/1/smaps")
    (same "1/cmdline" "a/1/cmdline") (same "1/stat" "a/1/stat"))
```
---
```output
same
same
same
same
same
```

### a file's header: mode, size and time in octal with no padding, GNU's magic, the sum in six digits

```cu
(do (field 0 12) (field 100 8) (field 124 12) (field 136 12) (field 156 1) (field 257 8)
    (field 148 7))
```
---
```output
meminfo.....
644.....
70..........
15125632645.
0
ustar  .
dddddd.
```

### a directory's header: 555, owner 0, no size, time 0

```cu
(field (* 4 512) 2) (field (+ (* 4 512) 100) 24) (field (+ (* 4 512) 124) 24) (field (+ (* 4 512) 156) 1)
```
---
```output
1.
555.....0.......0.......
0...........0...........
5
```

## the sizes

### a file of exactly one block, and an empty cmdline

```cu
(do (show (nf "b") (list "smemcap")) (tv) (same "42/smaps" "b/42/smaps"))
```
---
```output
stderr:
status 0
-rw-r--r-- U/G        56 2026-01-02 03:04:05 meminfo
-rw-r--r-- U/G        33 2026-01-02 03:04:05 version
dr-xr-xr-x 0/0         0 1970-01-01 00:00:00 42
-rw-r--r-- U/G       512 2026-01-02 03:04:05 42/smaps
-rw-r--r-- U/G         0 2026-01-02 03:04:05 42/cmdline
-rw-r--r-- U/G        35 2026-01-02 03:04:05 42/stat
stderr:
status 0
bytes 5120
same
```

## what is left out

### a process's files that are not there, and words given

```cu
(do (show (nf "c") (list "smemcap" "-x" "words")) (tv))
```
---
```output
stderr:
status 0
-rw-r--r-- U/G        56 2026-01-02 03:04:05 meminfo
-rw-r--r-- U/G        33 2026-01-02 03:04:05 version
dr-xr-xr-x 0/0         0 1970-01-01 00:00:00 7
-rw-r--r-- U/G        28 2026-01-02 03:04:05 7/stat
stderr:
status 0
bytes 3584
```

### a /proc with nothing in it, and none at all

```cu
(do (show (nf "empty") (list "smemcap")) (display (cu-int->str (fsize (nf "out"))))
    (show (nf "none") (list "smemcap")) (display (cu-int->str (fsize (nf "out")))))
```
---
```output
stderr:
status 0
0stderr:
smemcap: can't change directory to '/tmp/x-cu-smc/none': No such file or directory
status 1
0
```

## clean up

### the trees

```cu
(do (proc-run (list "/bin/rm" "-rf" "/tmp/x-cu-smc")) (display ""))
```
---
```output
```
