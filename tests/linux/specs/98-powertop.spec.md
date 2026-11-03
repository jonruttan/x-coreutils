# @weight 2
# @timeout-scale 3

busybox's powertop (procps/powertop.c), run as root against busybox's own.
Each side is fed the same keys: the bundle's powertop in a child of this
file's process, busybox's through the shell, and their output, stderr and
statuses are compared.  First on this kernel's /proc, which has no
timer_stats since Linux 4.11 and no ACPI power files, the wakeups counted
written N.  Then over tests/fixtures/powertop, on a tmpfs mounted on /proc
in a mount namespace of a child's own: tests/linux/powertop-proc.sh fills
it, plays timer_stats as the kernel kept it when asked, and presses each
key after the next sample is in place.  The keys come two seconds apart,
which is what the file's time goes on.

## the comparison

### each side on the same stdin, and on the fixture /proc made afresh

```cu
(do (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (def lx-text (fn (_ o e st) (%str-concat (list (lx-read o) "stderr:\n" (lx-read e) "status " st "\n"))))
    ; the wakeups counted, which this kernel's interrupts make differ, as N
    (def lx-n (fn (self s)
      (def k (Str8 index-of "seconds: " s))
      (if (null? k) s
        (let ((d ((fn (self i) (if (if (< i (byte-len s)) (if (>= (byte-at s i) 48) (<= (byte-at s i) 57) #f) #f) (self (+ i 1)) i)) (+ k 9))))
          (%str-concat (list (substring s 0 (+ k 9)) "N" (self (substring s d (byte-len s)))))))))
    ; ours in a child, stdin IN, ENV before it runs, KILL ms later a SIGTERM when not 0
    (def lx-x1 (fn (_ in env kill)
      (do (def lx-kid (sys-fork))
          (when (= lx-kid 0)
            (guard (e (sys-exit 99))
              (do (sys-dup2 (file-open-read in) 0) (set-first! cu-stdin-moved #t)
                  (sys-dup2 (file-open-write "/tmp/lx-ptop-xo") 1) (sys-dup2 (file-open-write "/tmp/lx-ptop-xe") 2)
                  (if (null? env) () (sys-setenv "LINES" env))
                  (sys-exit (cu-run (list "powertop") "")))))
          (when (> kill 0) (do (sys-usleep (* kill 1000)) (sys-kill lx-kid 15)))
          (lx-text "/tmp/lx-ptop-xo" "/tmp/lx-ptop-xe" (cu-int->str (sys-wait lx-kid))))))
    (def lx-bb1 (fn (_ in env kill)
      (do (lx-sh (%str-concat (list (if (null? env) "" (string-append "LINES=" env))
                                      " /usr/local/bin/busybox-extra powertop < " in " > /tmp/lx-ptop-bo 2> /tmp/lx-ptop-be"
                                      (if (> kill 0)
                                        (%str-concat (list " & p=$!; sleep " (cu-int->str (/ kill 1000)) "; kill $p; wait $p"))
                                        "")
                                      "; echo $? > /tmp/lx-ptop-bs")))
          (lx-text "/tmp/lx-ptop-bo" "/tmp/lx-ptop-be" (Str8 trim (lx-read "/tmp/lx-ptop-bs"))))))
    (def lx-same (fn (_ a b)
      (display (if (string=? a b) "same\n" (%str-concat (list "ours:\n" a "busybox:\n" b))))))
    ; on this kernel's /proc, stdin the bytes BYTES (printf's), KILL as lx-x1's
    (def lx-live (fn (_ bytes kill)
      (do (lx-sh (%str-concat (list "printf '" bytes "' > /tmp/lx-ptop-key")))
          (def lx-in (if (> kill 0) "/tmp/lx-ptop-in" "/tmp/lx-ptop-key"))
          (def lx-hold (fn (_) (lx-sh "rm -f /tmp/lx-ptop-in && mkfifo /tmp/lx-ptop-in && { sleep 30 > /tmp/lx-ptop-in 2> /dev/null & echo $! > /tmp/lx-ptop-hold; }")))
          (when (> kill 0) (lx-hold))
          (def lx-a (lx-n (lx-x1 lx-in () kill)))
          (when (> kill 0) (do (lx-sh "kill $(cat /tmp/lx-ptop-hold)") (lx-hold)))
          (def lx-b (lx-n (lx-bb1 lx-in () kill)))
          (when (> kill 0) (lx-sh "kill $(cat /tmp/lx-ptop-hold)"))
          (lx-same lx-a lx-b))))
    ; the fixture /proc ARGS builds, in a child's own mount namespace; LINES
    ; ENV, or nil
    (def lx-end "for p in $(cat /tmp/lx-ptop-pids); do kill -STOP $p; pkill -9 -P $p; kill -9 $p; done 2> /dev/null")
    (def lx-fx (fn (_ args env)
      (do (def lx-kid (sys-fork))
          (when (= lx-kid 0)
            (guard (e (sys-exit 99))
              (do (in-call (cu-ptr-call (cu-libc-sym "unshare") 131072))
                  (cu-ptr-call (cu-libc-sym "mount") "none" "/" 0 278528 0)
                  (lx-sh (string-append "sh tests/linux/powertop-proc.sh " args))
                  (file-write-all "/tmp/lx-ptop-a" (lx-x1 "/tmp/lx-ptop-in" env 0))
                  (lx-sh lx-end)
                  (lx-sh (string-append "sh tests/linux/powertop-proc.sh " args))
                  (file-write-all "/tmp/lx-ptop-b" (lx-bb1 "/tmp/lx-ptop-in" env 0))
                  (lx-sh lx-end)
                  (sys-exit 0))))
          (sys-wait lx-kid)
          (lx-same (lx-read "/tmp/lx-ptop-a") (lx-read "/tmp/lx-ptop-b")))))
    (display "made"))
```
---
    made

## this kernel's /proc

### the end of input, q, Q, a NUL (the interrupt key of no terminal), a key then the end

```cu
(do (lx-live "" 0)
    (lx-live "q" 0)
    (lx-live "Q" 0)
    (lx-live "\\0" 0)
    (lx-live "x" 0))
```
---
```output
same
same
same
same
same
```

### a SIGTERM while it waits: status 1, and what stdio held for stdout lost

```cu
(lx-live "" 3000)
```
---
```output
same
```

## the fixture /proc

### two samples, the kernel keeping timer_stats: C-states, timers and interrupts

```cu
(lx-fx "small fifo yes 2" ())
```
---
```output
same
```

### timer_stats a file the writes land in, a directory no write opens

```cu
(do (lx-fx "small file yes 2" ())
    (lx-fx "small dir yes 1" ()))
```
---
```output
same
same
```

### no power files; a terminal of 14 lines, 2 of them causes

```cu
(do (lx-fx "small file no 1" ())
    (lx-fx "small fifo yes 1" "14"))
```
---
```output
same
same
```

### 45 sources, past the 40 kept, in thousands, 60 lines

```cu
(lx-fx "big file no 2" "60")
```
---
```output
same
```

### no interrupts, no stat

```cu
(do (lx-fx "none file yes 0" ())
    (lx-fx "nostat file yes 0" ()))
```
---
```output
same
same
```
