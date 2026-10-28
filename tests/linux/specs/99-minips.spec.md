# @weight 1

busybox's minips (klibc-utils/minips.c: ps's main under another name),
against busybox's own.  The table is the whole container's, and other
files' processes come and go in it, so the runs here are made in a PID
namespace of their own, over a /proc mounted afresh: its first process, a
child of this file's, starts two sleeps, one niced, and leaves a third
child a zombie, then runs the bundle's minips and busybox's on the same
words.  The rows compared are those processes' -- busybox's own shell and
itself are not in the bundle's table -- with the header, the output's
other lines and the statuses.  The first process's state and times move
while it runs, so its row is compared on the columns that hold still, its
command line not among them: under qemu (an x86 image on an arm64 host) a
process reading its own /proc entry is shown its program's words alone,
while busybox reading it sees qemu's too.

## the comparison

### the namespace, its processes, then each run on both sides

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-f (fn (_ n) (string-append "/tmp/lx-mp/" n)))
    (def lx-read (fn (_ n) (file-read-all (lx-f n))))
    (def lx-runs
      (list (list "minips" "-o" "pid,ppid,pgid,sid,user,group,ruser,rgroup,nice,tty,comm")
            (list "minips")
            (list "minips" "-o" "pid,stat,vsz,rss,time,comm=CMD,args=")
            (list "minips" "-o" "pid,bogus")))
    (def lx-x1 (fn (_ k argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (def lx-o (file-open-write (lx-f (string-append "xo" k)))) (def lx-e (file-open-write (lx-f (string-append "xe" k))))
          (sys-dup2 lx-o 1) (sys-dup2 lx-e 2)
          (def lx-st (cu-run argv ""))
          (sys-dup2 9 1) (sys-dup2 8 2) (file-close lx-o) (file-close lx-e)
          (lx-sh (string-concat (list "echo " (cu-int->str lx-st) " > " (lx-f (string-append "xs" k))))))))
    (def lx-bb1 (fn (_ k argv)
      (lx-sh (string-concat (list "/usr/local/bin/busybox-extra " (Str8 join " " (map lx-q argv))
                                  " > " (lx-f (string-append "bo" k)) " 2> " (lx-f "bx") "; echo $? > " (lx-f (string-append "bs" k))
                                  "; sed '/^BusyBox v/{N;d;}' " (lx-f "bx") " > " (lx-f (string-append "be" k)))))))
    ; the namespace's first process: its children, then both sides' runs
    (def lx-first (fn (_)
      (do (in-call (cu-ptr-call (cu-libc-sym "mount") "proc" "/proc" "proc" 0 0))
          (def lx-a (sys-fork))
          (when (= lx-a 0) (sys-exec "/bin/sleep" (list "999")))
          (def lx-b (sys-fork))
          (when (= lx-b 0) (sys-exec "/bin/nice" (list "-n" "7" "/bin/sleep" "998")))
          (def lx-z (sys-fork))
          (when (= lx-z 0) (sys-exit 0))
          (lx-sh "sleep 0.5")
          (lx-sh (string-concat (list "echo " (Str8 join " " (map cu-int->str (list 1 lx-a lx-b lx-z))) " > " (lx-f "pids"))))
          (def lx-k (fn (self i rs)
            (unless (null? rs)
              (do (lx-x1 (cu-int->str i) (first rs)) (lx-bb1 (cu-int->str i) (first rs)) (self (+ i 1) (rest rs))))))
          (lx-k 0 lx-runs)
          (sys-kill lx-a 9) (sys-kill lx-b 9))))
    (lx-sh "rm -rf /tmp/lx-mp; mkdir /tmp/lx-mp")
    (def lx-kid (sys-fork))
    (when (= lx-kid 0)
      (guard (e (sys-exit 9))
        (do (sys-exit
              (if (= (in-call (cu-ptr-call (cu-libc-sym "unshare") 537001984)) 0)
                (do (in-call (cu-ptr-call (cu-libc-sym "mount") "none" "/" 0 278528 0))
                    (def lx-one (sys-fork))
                    (when (= lx-one 0) (guard (e (sys-exit 9)) (do (lx-first) (sys-exit 0))))
                    (sys-wait lx-one))
                8)))))
    (def lx-made (sys-wait lx-kid))
    (def lx-pids (Str8 split " " (Str8 trim (lx-read "pids"))))
    ; the header, the namespace's processes' rows, the first process's only
    ; on the first run's columns, and every other line
    (def lx-row-pid (fn (_ l) (let ((w (Str8 trim (if (< (byte-len l) 5) l (substring l 0 5)))))
                                (if (List any? (fn (_ p) (string=? p w)) (list "" "PID")) () w))))
    (def lx-keep (fn (_ k out)
      (filter (fn (_ l)
                (let ((p (lx-row-pid l)))
                  (match ((null? p) #t)
                         ((string=? p "1") (string=? k "0"))
                         (#t (List any? (fn (_ q) (string=? q p)) lx-pids)))))
              (Str8 split "\n" out))))
    (def lx-side (fn (_ s k)
      (string-concat (list (Str8 join "\n" (lx-keep k (lx-read (string-concat (list s "o" k)))))
                           "stderr:\n" (lx-read (string-concat (list s "e" k))) "status " (lx-read (string-concat (list s "s" k)))))))
    (def lx-case (fn (_ k)
      (let ((a (lx-side "x" k)) (b (lx-side "b" k)))
        (display (if (string=? a b) "same\n" (string-concat (list "ours:\n" a "busybox:\n" b)))))))
    (display (if (= lx-made 0) "made\n" (string-append "not made: " (cu-int->str lx-made))))
    (display (cu-int->str (length lx-pids))))
```
---
```output
made
4
```

## the runs

### the columns that hold still, the default ones, sizes and states, a bad column

```cu
(do (lx-case "0") (lx-case "1") (lx-case "2") (lx-case "3"))
```
---
```output
same
same
same
same
```

## cleanup

### the scratch directory goes

```cu
(do (lx-sh "rm -rf /tmp/lx-mp") (display ""))
```
---
```output
```
