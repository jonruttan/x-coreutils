# @weight 2

busybox's sysctl (procps/sysctl.c) and lsmod (modutils/lsmod.c), run as
root against the kernel itself.  Each case runs the bundle's applet and the
container's busybox on the same words and compares what they write to
standard output and standard error and the status: `same`, or the two
answers when they differ.  The kernel is whatever the container runs on, so
the cases ask nothing whose value changes from one read to the next, and
the writes are to kernel.domainname, which is the container's own.

## the comparison

### each applet against busybox's, by what it writes and its status

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (def lx-x (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (def lx-o (file-open-write "/tmp/lx-xo")) (def lx-e (file-open-write "/tmp/lx-xe"))
          (sys-dup2 lx-o 1) (sys-dup2 lx-e 2)
          (def lx-st (cu-run argv ""))
          (sys-dup2 9 1) (sys-dup2 8 2) (file-close lx-o) (file-close lx-e)
          (string-concat (list (lx-read "/tmp/lx-xo") "stderr:\n" (lx-read "/tmp/lx-xe") "status " (%cu-int->str lx-st) "\n")))))
    (def lx-bb (fn (_ argv)
      (do (lx-sh (string-concat (list "/bin/busybox " (Str8 join " " (map lx-q argv)) " > /tmp/lx-bo 2> /tmp/lx-bx; echo $? > /tmp/lx-bs; sed '/^BusyBox v/{N;d;}' /tmp/lx-bx > /tmp/lx-be")))
          (string-concat (list (lx-read "/tmp/lx-bo") "stderr:\n" (lx-read "/tmp/lx-be") "status " (lx-read "/tmp/lx-bs"))))))
    ; PRE run through the shell before each side
    (def lx-case (fn (_ pre argv)
      (do (lx-sh pre) (def lx-a (lx-x argv)) (lx-sh pre) (def lx-b (lx-bb argv))
          (display (if (string=? lx-a lx-b) "same\n" (string-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    (display "made"))
```
---
    made

## sysctl reads

### a key, by its dots or its slashes; -n leaves the names out

```cu
(do (lx-case ":" (list "sysctl" "kernel.ostype" "kernel.osrelease"))
    (lx-case ":" (list "sysctl" "kernel/ostype"))
    (lx-case ":" (list "sysctl" "-n" "kernel.ostype" "kernel.pid_max")))
```
---
```output
same
same
same
```

### a directory is every key under it, in the kernel's order

```cu
(lx-case ":" (list "sysctl" "fs.mqueue"))
```
---
    same

### -a names every key the kernel has, in its order, and fails to read as many

A key that cannot be read is said with the reason, and the reason is the
C library's words: musl's here, for busybox, and the platform's for the
bundle.  So the keys read are compared by name and the ones not read are
counted.

```cu
(do (def lx-names (fn (_ text) (Str8 join "\n" (map (fn (_ l) (substring l 0 (%dp-find l 0 #\=))) (filter (fn (_ l) (>= (%dp-find l 0 #\=) 0)) (%cu-lines text))))))
    (def lx-errors (fn (_ text) (length (filter (fn (_ l) (Str8 starts? "sysctl: error reading key" l)) (%cu-lines text)))))
    (def lx-xa (lx-x (list "sysctl" "-a")))
    (def lx-ba (lx-bb (list "sysctl" "-a")))
    (display (list (string=? (lx-names lx-xa) (lx-names lx-ba)) (= (lx-errors lx-xa) (lx-errors lx-ba)))))
```
---
    (#t #t)

### an unknown key is said and the status is 1; -e says nothing of it

```cu
(do (lx-case ":" (list "sysctl" "no.such.key" "kernel.ostype"))
    (lx-case ":" (list "sysctl" "-e" "no.such.key")))
```
---
```output
same
same
```

## sysctl writes

### KEY=VALUE writes and says it; -w too; -n says the value alone, -q nothing

```cu
(do (lx-case ":" (list "sysctl" "kernel.domainname=lx-one"))
    (lx-case ":" (list "sysctl" "-w" "kernel.domainname=lx-two"))
    (lx-case ":" (list "sysctl" "-n" "-w" "kernel.domainname=lx-three"))
    (lx-case ":" (list "sysctl" "-q" "kernel.domainname=lx-four"))
    (lx-case "/bin/busybox sysctl -q kernel.domainname=lx-read" (list "sysctl" "kernel.domainname")))
```
---
```output
same
same
same
same
same
```

### -w without a value, an empty name, an unknown key

```cu
(do (lx-case ":" (list "sysctl" "-w" "kernel.domainname"))
    (lx-case ":" (list "sysctl" "=x"))
    (lx-case ":" (list "sysctl" "no.such.key=1")))
```
---
```output
same
same
same
```

### -p sets each KEY = VALUE line of a file, passing over comments

```cu
(do (lx-case "printf '# a comment\\n; another\\n  kernel.domainname = lx-five\\n\\nkernel/domainname=lx-six\\n' > /tmp/lx-sysctl.conf"
             (list "sysctl" "-p" "/tmp/lx-sysctl.conf"))
    (lx-case ":" (list "sysctl" "-p" "/tmp/lx-no-such.conf")))
```
---
```output
same
same
```

## lsmod

### the header, whether the kernel is tainted, and each module; words after it are passed over

```cu
(do (lx-case ":" (list "lsmod")) (lx-case ":" (list "lsmod" "-~")) (lx-case ":" (list "lsmod" "--nope")))
```
---
```output
same
same
same
```
