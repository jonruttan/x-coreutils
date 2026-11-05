# @weight 1

busybox's killall5 (procps/kill.c), against busybox's own.  killall5
signals every process outside its session, so the runs here are made in a
PID namespace of their own, over a /proc mounted afresh, where the
container's other processes are out of its reach.  The namespace's first
process runs each side in turn: before each run it starts two sleeps,
each in a session of its own, and after it, reads the state each sleep
was left in -- Z for one the signal ended, T for one it stopped -- then
ends and reaps them.  A and B in a case's words are those sleeps' pids.
The first process, and the shell busybox runs under, are in the session
killall5 spares.

## the comparison

### the namespace, then each case on both sides

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-f (fn (_ n) (string-append "/tmp/lx-k5/" n)))
    (def lx-read (fn (_ n) (file-read-all (lx-f n))))
    (def lx-runs
      (list (list "killall5")
            (list "killall5" "-o" "B")
            (list "killall5" "-STOP" "-oA")
            (list "killall5" "-s" "KILL" "-o" "A" "-o" "B")
            (list "killall5" "-o" "A" "junk")
            (list "killall5" "-o" "x")))
    (def lx-x1 (fn (_ k argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (def lx-o (file-open-write (lx-f (string-append "xo" k)))) (def lx-e (file-open-write (lx-f (string-append "xe" k))))
          (sys-dup2 lx-o 1) (sys-dup2 lx-e 2)
          (def lx-st (cu-run argv ""))
          (sys-dup2 9 1) (sys-dup2 8 2) (file-close lx-o) (file-close lx-e)
          (lx-sh (%str-concat (list "echo " (cu-int->str lx-st) " > " (lx-f (string-append "xs" k))))))))
    (def lx-bb1 (fn (_ k argv)
      (lx-sh (%str-concat (list "/usr/local/bin/busybox-extra " (Str8 join " " (map lx-q argv))
                                  " > " (lx-f (string-append "bo" k)) " 2> " (lx-f "bx") "; echo $? > " (lx-f (string-append "bs" k))
                                  "; sed '/^BusyBox v/{N;d;}' " (lx-f "bx") " > " (lx-f (string-append "be" k)))))))
    ; a sleep in a session of its own
    (def lx-sleeper (fn (_)
      (let ((p (sys-fork)))
        (do (when (= p 0)
              (do (in-call (cu-ptr-call (cu-libc-sym "setsid")))
                  (sys-exec "/bin/sleep" (list "999"))))
            p))))
    ; one side's run of ARGV, its sleeps' states after it
    (def lx-side-run (fn (_ s k argv)
      (do (def lx-a (lx-sleeper)) (def lx-b (lx-sleeper))
          (lx-sh "sleep 0.3")
          (def lx-w (map (fn (_ w) (match ((string=? w "A") (cu-int->str lx-a))
                                          ((string=? w "B") (cu-int->str lx-b))
                                          ((string=? w "-oA") (string-append "-o" (cu-int->str lx-a)))
                                          (#t w)))
                         argv))
          (if (string=? s "x") (lx-x1 k lx-w) (lx-bb1 k lx-w))
          (lx-sh "sleep 0.3")
          (def lx-st (fn (_ p) (%str-concat (list "$(cut -d' ' -f3 /proc/" (cu-int->str p) "/stat)"))))
          (lx-sh (%str-concat (list "echo A " (lx-st lx-a) " B " (lx-st lx-b) " > " (lx-f (%str-concat (list s "p" k))))))
          (sys-kill lx-a 9) (sys-kill lx-b 9) (sys-wait lx-a) (sys-wait lx-b))))
    ; the namespace's first process: each case, ours then busybox's
    (def lx-first (fn (_)
      (do (in-call (cu-ptr-call (cu-libc-sym "mount") "proc" "/proc" "proc" 0 0))
          (def lx-k (fn (self i rs)
            (unless (null? rs)
              (do (lx-side-run "x" (cu-int->str i) (first rs))
                  (lx-side-run "b" (cu-int->str i) (first rs))
                  (self (+ i 1) (rest rs))))))
          (lx-k 0 lx-runs))))
    (lx-sh "rm -rf /tmp/lx-k5; mkdir /tmp/lx-k5")
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
    (def lx-side (fn (_ s k)
      (%str-concat (list (lx-read (%str-concat (list s "o" k))) "stderr:\n" (lx-read (%str-concat (list s "e" k)))
                         "status " (lx-read (%str-concat (list s "s" k))) (lx-read (%str-concat (list s "p" k)))))))
    (def lx-case (fn (_ k)
      (let ((a (lx-side "x" k)) (b (lx-side "b" k)))
        (display (if (string=? a b) (string-append "same: " (lx-read (string-append "xp" k)))
                   (%str-concat (list "ours:\n" a "busybox:\n" b)))))))
    (display (if (= lx-made 0) "made" (string-append "not made: " (cu-int->str lx-made)))))
```
---
    made

## the runs

### TERM to both, one spared, STOP to the other, every one spared, a word that is no -o, a PID that is no number

```cu
(do (lx-case "0") (lx-case "1") (lx-case "2") (lx-case "3") (lx-case "4") (lx-case "5"))
```
---
```output
same: A Z B Z
same: A Z B S
same: A S B T
same: A S B S
same: A S B S
same: A S B S
```

## cleanup

### the scratch directory goes

```cu
(do (lx-sh "rm -rf /tmp/lx-k5") (display ""))
```
---
```output
```
