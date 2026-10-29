# @weight 1

busybox's ionice (util-linux/ionice.c), run as root.  A sleeping process
is the one each case asks about and sets: before each side runs, busybox
puts it back to no class, and after, busybox asks its class and priority,
so a case compares what each side writes, its statuses and what it left
the process.  ionice becomes the command it is given, so the bundle's
runs are each in a child of their own.

## the comparison

### the applet against busybox's, the sleeper put back for each

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (lx-sh "sleep 9999 > /dev/null 2>&1 & echo $! > /tmp/lx-io-pid")
    (def lx-pid (Str8 replace "\n" "" (lx-read "/tmp/lx-io-pid")))
    (def lx-words (fn (_ argv) (map (fn (_ w) (Str8 replace "PID" lx-pid w)) argv)))
    (def lx-x1 (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (def lx-o (file-open-write "/tmp/lx-xo")) (def lx-e (file-open-write "/tmp/lx-xe"))
          (sys-dup2 lx-o 1) (sys-dup2 lx-e 2) (file-close lx-o) (file-close lx-e)
          (def lx-child (sys-fork))
          (when (= lx-child 0) (sys-exit (cu-run (lx-words argv) "")))
          (def lx-st (sys-wait lx-child))
          (sys-dup2 9 1) (sys-dup2 8 2)
          (%str-concat (list (lx-read "/tmp/lx-xo") "stderr:\n" (lx-read "/tmp/lx-xe") "status " (cu-int->str lx-st) "\n")))))
    (def lx-bb1 (fn (_ argv)
      (do (lx-sh (%str-concat (list "/bin/busybox " (Str8 join " " (map lx-q (lx-words argv))) " > /tmp/lx-bo 2> /tmp/lx-bx; echo $? > /tmp/lx-bs; sed '/^BusyBox v/{N;d;}' /tmp/lx-bx > /tmp/lx-be")))
          (%str-concat (list (lx-read "/tmp/lx-bo") "stderr:\n" (lx-read "/tmp/lx-be") "status " (lx-read "/tmp/lx-bs"))))))
    (def lx-run (fn (_ one runs)
      (do (lx-sh (string-append "/bin/busybox ionice -c 0 -p " lx-pid))
          (def lx-out (%str-concat (map one runs)))
          (lx-sh (%str-concat (list "/bin/busybox ionice -p " lx-pid " > /tmp/lx-il 2>&1")))
          (%str-concat (list lx-out "left: " (lx-read "/tmp/lx-il"))))))
    (def lx-case (fn (_ runs)
      (do (def lx-a (lx-run lx-x1 runs)) (def lx-b (lx-run lx-bb1 runs))
          (display (if (string=? lx-a lx-b) "same\n" (%str-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    (display "made"))
```
---
    made

## asked

### by -p, by the first operand, -p before an operand, no such process, its own

```cu
(do (lx-case (list (list "ionice" "-p" "PID")))
    (lx-case (list (list "ionice" "PID" "x")))
    (lx-case (list (list "ionice" "-p" "PID" "1")))
    (lx-case (list (list "ionice" "-p" "999999") (list "ionice" "999999")))
    (lx-case (list (list "ionice"))))
```
---
```output
same
same
same
same
same
```

## set

### each class, each priority's ends, a class alone, a priority alone

```cu
(do (lx-case (list (list "ionice" "-c" "1" "-n" "0" "-p" "PID") (list "ionice" "-p" "PID")))
    (lx-case (list (list "ionice" "-c2" "-n7" "-pPID") (list "ionice" "-p" "PID")))
    (lx-case (list (list "ionice" "-c" "3" "-p" "PID") (list "ionice" "-p" "PID")))
    (lx-case (list (list "ionice" "-c" "2" "-p" "PID")))
    (lx-case (list (list "ionice" "-n" "4" "-p" "PID")))
    (lx-case (list (list "ionice" "-c" "0" "-n" "3" "-p" "PID"))))
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

### refused: a priority past 7, a class past 3, no such process; -t ignores the kernel's refusal

```cu
(do (lx-case (list (list "ionice" "-c" "2" "-n" "8" "-p" "PID")))
    (lx-case (list (list "ionice" "-c" "2" "-n" "8200" "-p" "PID")))
    (lx-case (list (list "ionice" "-c" "4" "-p" "PID")))
    (lx-case (list (list "ionice" "-c" "2" "-p" "999999")))
    (lx-case (list (list "ionice" "-t" "-c" "2" "-n" "8" "-p" "PID") (list "ionice" "-t" "-c" "2" "-p" "999999"))))
```
---
```output
same
same
same
same
same
```

## the command

### run with the class it was given, -p's process set as well; one that will not run, one that cannot

```cu
(do (lx-case (list (list "ionice" "-c" "3" "/bin/busybox" "ionice")))
    (lx-case (list (list "ionice" "-c" "2" "-n" "6" "sh" "-c" "echo $# \"$0\"; /bin/busybox ionice" "a")))
    (lx-case (list (list "ionice" "-c" "1" "-n" "2" "-p" "PID" "/bin/busybox" "ionice")))
    (lx-case (list (list "ionice" "-c" "2" "nope") (list "ionice" "-c" "2" "/tmp"))))
```
---
```output
same
same
same
same
```

## the options

### numbers that are not, an unknown option

```cu
(do (lx-case (list (list "ionice" "-c" "x") (list "ionice" "-n" "-1") (list "ionice" "-p" "+1")
                   (list "ionice" "-p" "4294967296") (list "ionice" "sleep")))
    (lx-case (list (list "ionice" "-z"))))
```
---
```output
same
same
```

### the sleeper taken away

```cu
(do (lx-sh (string-append "kill " lx-pid)) (display "clean"))
```
---
    clean
