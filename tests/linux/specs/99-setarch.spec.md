# @weight 2

busybox's setarch, linux32 and linux64 (util-linux/setarch.c), run as root.
Each case runs the bundle's applet and busybox-extra's on the same words,
the program's standard input from a file, and compares what they write and
their status: `same`, or the two answers when they differ.  What a program
runs under is read from /proc/self/personality and uname -m.

## the comparison

### the applet against busybox's, by what it writes and its status

```cu
(do (def sa-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def sa-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def sa-put (fn (_ path s) (let ((f (file-open-write path))) (do (file-write f s) (file-close f)))))
    (def sa-x (fn (_ argv)
      (do (def pid (sys-fork))
          (when (= pid 0)
            (let ((i (file-open-read "/tmp/sa-in")) (o (file-open-write "/tmp/sa-xo")) (e (file-open-write "/tmp/sa-xe")))
              (do (sys-dup2 i 3) (sys-dup2 i 0) (sys-dup2 o 1) (sys-dup2 e 2) (sys-exit (cu-run argv "")))))
          (def st (sys-wait pid))
          (%str-concat (list (file-read-all "/tmp/sa-xo") "stderr:\n" (file-read-all "/tmp/sa-xe")
                             "status " (cu-int->str st) "\n")))))
    (def sa-bb (fn (_ argv)
      (do (sa-sh (%str-concat (list "/usr/local/bin/busybox-extra " (Str8 join " " (map sa-q argv))
                                    " < /tmp/sa-in > /tmp/sa-bo 2> /tmp/sa-bx; echo $? > /tmp/sa-bs; sed '/^BusyBox v/{N;d;}' /tmp/sa-bx > /tmp/sa-be")))
          (%str-concat (list (file-read-all "/tmp/sa-bo") "stderr:\n" (file-read-all "/tmp/sa-be")
                             "status " (file-read-all "/tmp/sa-bs"))))))
    ; ARGV on each side, IN its standard input
    (def sa-case (fn (_ in argv)
      (do (sa-put "/tmp/sa-in" in)
          (def a (sa-x argv)) (def b (sa-bb argv))
          (display (if (string=? a b) "same\n" (%str-concat (list "ours:\n" a "busybox:\n" b)))))))
    (display "made"))
```
---
    made

## the personality a program runs under

### linux32 and linux64, -R adding ADDR_NO_RANDOMIZE

```cu
(do (sa-case "" (list "linux32" "cat" "/proc/self/personality"))
    (sa-case "" (list "linux32" "-R" "cat" "/proc/self/personality"))
    (sa-case "" (list "linux64" "cat" "/proc/self/personality"))
    (sa-case "" (list "linux64" "-R" "cat" "/proc/self/personality"))
    (sa-case "" (list "linux32" "uname" "-m"))
    (sa-case "" (list "linux64" "uname" "-m")))
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

### setarch by a first word that starts "linux"

```cu
(do (sa-case "" (list "setarch" "linux32" "-R" "cat" "/proc/self/personality"))
    (sa-case "" (list "setarch" "linux64" "cat" "/proc/self/personality"))
    (sa-case "" (list "setarch" "linux32x" "cat" "/proc/self/personality")))
```
---
```output
same
same
same
```

### no program: /bin/sh, reading standard input

```cu
(sa-case "cat /proc/self/personality\n" (list "linux32" "-R"))
```
---
    same

## the refusals

### usage, a name no applet has, an unknown option, a program not run

```cu
(do (sa-case "" (list "setarch"))
    (sa-case "" (list "setarch" "linuxq" "true"))
    (sa-case "" (list "linux32" "-x"))
    (sa-case "" (list "linux64" "/nonexistent/prog"))
    (sa-case "" (list "linux32" "/etc")))
```
---
```output
same
same
same
same
same
```
