# @weight 1

busybox's taskset (util-linux/taskset.c), run as root against busybox's
own.  Each case is a run of commands, each made twice: once with the
bundle's taskset in a child of this file's process, so a PROG can take its
place, and once with busybox's.  Each side starts a sleep of its own, PID
in a command, so a mask set on one side is not the other's to read; each
writes `pid PID's` for the sleep's pid, and the two sides' output and
statuses are compared.

## the comparison

### the applet against busybox's, a sleep of its own on each side

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (def lx-x1 (fn (_ argv)
      (do (def lx-kid (sys-fork))
          (when (= lx-kid 0)
            (do (sys-dup2 (file-open-write "/tmp/lx-tk-xo") 1) (sys-dup2 (file-open-write "/tmp/lx-tk-xe") 2)
                (sys-exit (cu-run argv ""))))
          (def lx-st (sys-wait lx-kid))
          (%str-concat (list (lx-read "/tmp/lx-tk-xo") "stderr:\n" (lx-read "/tmp/lx-tk-xe") "status " (cu-int->str lx-st) "\n")))))
    (def lx-bb1 (fn (_ argv)
      (do (lx-sh (%str-concat (list "/usr/local/bin/busybox-extra " (Str8 join " " (map lx-q argv)) " > /tmp/lx-tk-bo 2> /tmp/lx-tk-bx; echo $? > /tmp/lx-tk-bs; sed '/^BusyBox v/{N;d;}' /tmp/lx-tk-bx > /tmp/lx-tk-be")))
          (%str-concat (list (lx-read "/tmp/lx-tk-bo") "stderr:\n" (lx-read "/tmp/lx-tk-be") "status " (lx-read "/tmp/lx-tk-bs"))))))
    (def lx-run (fn (_ one runs)
      (do (def lx-sleep (sys-fork))
          (when (= lx-sleep 0) (sys-exec "/bin/sleep" (list "999")))
          (def lx-pid (cu-int->str lx-sleep))
          (def lx-out (%str-concat (map (fn (_ argv) (one (map (fn (_ w) (if (string=? w "PID") lx-pid w)) argv))) runs)))
          (sys-kill lx-sleep 9) (sys-wait lx-sleep)
          (Str8 replace (%str-concat (list "pid " lx-pid "'s")) "pid PID's" lx-out))))
    (def lx-case (fn (_ runs)
      (do (def lx-a (lx-run lx-x1 runs)) (def lx-b (lx-run lx-bb1 runs))
          (display (if (string=? lx-a lx-b) "same\n" (%str-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    (display "made"))
```
---
    made

## the words

### none, a mask with no PROG, -p alone, options it does not take

```cu
(do (lx-case (list (list "taskset")))
    (lx-case (list (list "taskset" "ff")))
    (lx-case (list (list "taskset" "-p")))
    (lx-case (list (list "taskset" "-x" "ff" "true")))
    (lx-case (list (list "taskset" "-p" "-1" "PID"))))
```
---
```output
same
same
same
same
same
```

### PIDs: 0, no number, past an int, no process

```cu
(do (lx-case (list (list "taskset" "-p" "0")))
    (lx-case (list (list "taskset" "-p" "ff" "12x")))
    (lx-case (list (list "taskset" "-p" "2147483648")))
    (lx-case (list (list "taskset" "-p" "2147483647")))
    (lx-case (list (list "taskset" "-p" "1" "4194303"))))
```
---
```output
same
same
same
same
same
```

## shown and set

### the mask and the list, each thread's, CPU 0 then every CPU

```cu
(do (lx-case (list (list "taskset" "-p" "PID") (list "taskset" "-pc" "PID")))
    (lx-case (list (list "taskset" "-ap" "PID") (list "taskset" "-a" "-p" "-c" "PID")))
    (lx-case (list (list "taskset" "-p" "1" "PID") (list "taskset" "-p" "PID")
                   (list "taskset" "-p" "ffffffff" "PID") (list "taskset" "-pc" "PID"))))
```
---
```output
same
same
same
```

### masks: a 0x, upper case, bits past the buffer, no CPU online, none at all

```cu
(do (lx-case (list (list "taskset" "-p" "0x2" "PID") (list "taskset" "-p" "0XA" "PID")))
    (lx-case (list (list "taskset" "-p" "123000000000000000000000000000000003" "PID")))
    (lx-case (list (list "taskset" "-p" "f000000000000000" "PID")))
    (lx-case (list (list "taskset" "-p" "0x" "PID") (list "taskset" "-p" "" "PID")))
    (lx-case (list (list "taskset" "-ap" "1" "PID" "ignored"))))
```
---
```output
same
same
same
same
same
```

### lists: runs, strides, past the CPUs, beyond the buffer

```cu
(do (lx-case (list (list "taskset" "-pc" "0,2-3" "PID") (list "taskset" "-p" "PID")))
    (lx-case (list (list "taskset" "-pc" "0-5:2" "PID") (list "taskset" "-pc" "1-1000:3" "PID")))
    (lx-case (list (list "taskset" "-pc" "0-4000" "PID") (list "taskset" "-pc" "4000" "PID"))))
```
---
```output
same
same
same
```

### masks and lists it will not read

```cu
(do (lx-case (list (list "taskset" "-p" "0xfg" "PID") (list "taskset" "-p" "x1" "PID")))
    (lx-case (map (fn (_ l) (list "taskset" "-pc" l "PID"))
                  (list "" "a" " 1" "1 " "1-" "3-1" "0-7:0" "0-7:" "1,,2" "1,"
                        "0x1" "+1" "1-2:1073741825" "1-2:1073741824" "4294967295"
                        "4294967294" "4294967294-4294967295" "99999999999"))))
```
---
```output
same
same
```

## PROG

### the affinity it runs with, its options its own, none to run, one not to run

```cu
(do (lx-case (list (list "taskset" "1" "grep" "Cpus_allowed" "/proc/self/status")))
    (lx-case (list (list "taskset" "-c" "1-2" "grep" "-e" "Cpus_allowed_list" "/proc/self/status")))
    (lx-case (list (list "taskset" "ff" "/nonexist/prog")))
    (lx-case (list (list "taskset" "ff" "/etc/passwd")))
    (lx-case (list (list "taskset" "-c" "4000" "true"))))
```
---
```output
same
same
same
same
same
```
