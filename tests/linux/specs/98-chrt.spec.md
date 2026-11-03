# @weight 1

busybox's chrt (util-linux/chrt.c), run as root.  Each case runs the
bundle's chrt in a child of its own, since chrt becomes PROG, then busybox's
on the same words, and compares what each writes and its status.  @PID in a
word is a sleeping process made for the case: its policy is put back to
SCHED_OTHER before each side runs, and shown after, so a policy set is
compared too.  A PROG shows the policy it was started with.

## the comparison

### the applet against busybox's, the sleeper reset for each

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (lx-sh "sleep 99999 > /dev/null 2>&1 & echo $! > /tmp/lx-pid")
    (def lx-pid (Str8 replace "\n" "" (lx-read "/tmp/lx-pid")))
    (def lx-words (fn (_ argv) (map (fn (_ w) (Str8 replace "@PID" lx-pid w)) argv)))
    (def lx-reset (fn (_) (lx-sh (string-append "/usr/local/bin/busybox-extra chrt -o -p 0 " lx-pid " > /dev/null"))))
    (def lx-after (fn (_) (do (lx-sh (string-append "/usr/local/bin/busybox-extra chrt -p " lx-pid " > /tmp/lx-af")) (lx-read "/tmp/lx-af"))))
    (def lx-x1 (fn (_ argv)
      (do (lx-reset)
          (def lx-o (file-open-write "/tmp/lx-xo")) (def lx-e (file-open-write "/tmp/lx-xe"))
          (def lx-child (sys-fork))
          (when (= lx-child 0)
            (do (sys-dup2 lx-o 1) (sys-dup2 lx-e 2) (sys-exit (cu-run (lx-words argv) ""))))
          (file-close lx-o) (file-close lx-e)
          (def lx-st (sys-wait lx-child))
          (%str-concat (list (lx-read "/tmp/lx-xo") "stderr:\n" (lx-read "/tmp/lx-xe") "status " (cu-int->str lx-st) "\n" (lx-after))))))
    (def lx-bb1 (fn (_ argv)
      (do (lx-reset)
          (lx-sh (%str-concat (list "/usr/local/bin/busybox-extra " (Str8 join " " (map lx-q (lx-words argv))) " > /tmp/lx-bo 2> /tmp/lx-bx; echo $? > /tmp/lx-bs; sed '/^BusyBox v/{N;d;}' /tmp/lx-bx > /tmp/lx-be")))
          (%str-concat (list (lx-read "/tmp/lx-bo") "stderr:\n" (lx-read "/tmp/lx-be") "status " (lx-read "/tmp/lx-bs") (lx-after))))))
    (def lx-case (fn (_ argv)
      (do (def lx-a (lx-x1 argv)) (def lx-b (lx-bb1 argv))
          (display (if (string=? lx-a lx-b) "same\n" (%str-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    (display (if (> (byte-len lx-pid) 0) "made" "no sleeper")))
```
---
    made

## the options

### none, two policies, a PRIO alone, -p alone, an unknown option

```cu
(do (lx-case (list "chrt"))
    (lx-case (list "chrt" "-o" "-i" "0" "true"))
    (lx-case (list "chrt" "5"))
    (lx-case (list "chrt" "-p"))
    (lx-case (list "chrt" "-z" "1" "true")))
```
---
```output
same
same
same
same
same
```

### -m, and -m before the rest

```cu
(do (lx-case (list "chrt" "-m"))
    (lx-case (list "chrt" "-m" "-f" "x")))
```
---
```output
same
same
```

## a process

### shown: the sleeper, one that is not there, numbers refused

```cu
(do (lx-case (list "chrt" "-p" "@PID"))
    (lx-case (list "chrt" "-p" "999999"))
    (lx-case (list "chrt" "-p" "0"))
    (lx-case (list "chrt" "-p" "2147483648"))
    (lx-case (list "chrt" "-p" "+1"))
    (lx-case (list "chrt" "-p" "1x")))
```
---
```output
same
same
same
same
same
same
```

### set: each policy, PRIO in hex and octal, out of each range

```cu
(do (lx-case (list "chrt" "-p" "10" "@PID"))
    (lx-case (list "chrt" "-f" "-p" "50" "@PID"))
    (lx-case (list "chrt" "-r" "-p" "0x63" "@PID"))
    (lx-case (list "chrt" "-f" "-p" "017" "@PID"))
    (lx-case (list "chrt" "-o" "-p" "0" "@PID"))
    (lx-case (list "chrt" "-b" "-p" "0" "@PID"))
    (lx-case (list "chrt" "-i" "-p" "0" "@PID"))
    (lx-case (list "chrt" "-r" "-p" "100" "@PID"))
    (lx-case (list "chrt" "-o" "-p" "1" "@PID"))
    (lx-case (list "chrt" "-p" "5" "999999")))
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
same
same
```

## a PROG

### run under each policy, not found, not runnable, its status

```cu
(do (lx-case (list "chrt" "7" "sh" "-c" "/usr/local/bin/busybox-extra chrt -p $$ | sed s/$$/P/"))
    (lx-case (list "chrt" "-f" "3" "sh" "-c" "/usr/local/bin/busybox-extra chrt -p $$ | sed s/$$/P/"))
    (lx-case (list "chrt" "-b" "0" "sh" "-c" "/usr/local/bin/busybox-extra chrt -p $$ | sed s/$$/P/"))
    (lx-case (list "chrt" "-o" "0" "nosuchprog"))
    (lx-case (list "chrt" "-o" "0" "/etc"))
    (lx-case (list "chrt" "-o" "0" "sh" "-c" "exit 3")))
```
---
```output
same
same
same
same
same
same
```
