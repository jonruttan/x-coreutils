# @weight 2

busybox's fallocate (util-linux/fallocate.c) against busybox-extra's.
Each case starts FILE afresh, from the same bytes, for each side, runs
the applet on the same words and compares what it writes, its status, and
FILE after: its size and the blocks it holds, from stat.  `same`, or the
two answers when they differ.

## the comparison

### the applet against busybox's, by what it writes, its status and FILE

```cu
(do (def fa-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def fa-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def fa-file "/tmp/fa-file")
    ; FILE afresh: gone where SEED is nil, else holding SEED
    (def fa-seed! (fn (_ seed)
      (do (fa-sh "rm -f /tmp/fa-file")
          (when (not (null? seed))
            (let ((f (file-open-write fa-file))) (do (file-write f seed) (file-close f)))))))
    (def fa-after (fn (_)
      (do (fa-sh "if [ -e /tmp/fa-file ]; then stat -c '%s %b' /tmp/fa-file; else echo none; fi > /tmp/fa-st")
          (file-read-all "/tmp/fa-st"))))
    (def fa-x (fn (_ argv)
      (do (def pid (sys-fork))
          (when (= pid 0)
            (let ((o (file-open-write "/tmp/fa-xo")) (e (file-open-write "/tmp/fa-xe")))
              (do (sys-dup2 o 1) (sys-dup2 e 2) (sys-exit (cu-run argv "")))))
          (def st (sys-wait pid))
          (%str-concat (list (file-read-all "/tmp/fa-xo") "stderr:\n" (file-read-all "/tmp/fa-xe")
                             "status " (cu-int->str st) "\n" (fa-after))))))
    (def fa-bb (fn (_ argv)
      (do (fa-sh (%str-concat (list "/usr/local/bin/busybox-extra " (Str8 join " " (map fa-q argv))
                                    " < /dev/null > /tmp/fa-bo 2> /tmp/fa-bx; echo $? > /tmp/fa-bs; sed '/^BusyBox v/{N;d;}' /tmp/fa-bx > /tmp/fa-be")))
          (%str-concat (list (file-read-all "/tmp/fa-bo") "stderr:\n" (file-read-all "/tmp/fa-be")
                             "status " (file-read-all "/tmp/fa-bs") (fa-after))))))
    ; ARGV on each side, FILE seeded with SEED before each
    (def fa-case (fn (_ seed argv)
      (do (fa-seed! seed) (def a (fa-x argv))
          (fa-seed! seed) (def b (fa-bb argv))
          (display (if (string=? a b) "same\n" (%str-concat (list "ours:\n" a "busybox:\n" b)))))))
    (display "made"))
```
---
    made

## the space

### a new FILE, -o past its end, a range inside it

```cu
(do (fa-case () (list "fallocate" "-l" "100" fa-file))
    (fa-case () (list "fallocate" "-l" "1M" fa-file))
    (fa-case "abc" (list "fallocate" "-o" "10" "-l" "5" fa-file))
    (fa-case "0123456789" (list "fallocate" "-o" "2" "-l" "3" fa-file))
    (fa-case "abc" (list "fallocate" "-o" "1KiB" "-l" "64k" fa-file)))
```
---
```output
same
same
same
same
same
```

## the refusals

### the usage, numbers it will not read, and the call's own errors

```cu
(do (fa-case () (list "fallocate" fa-file))
    (fa-case () (list "fallocate" "-l" "1"))
    (fa-case () (list "fallocate" "-l" "1" fa-file "b"))
    (fa-case () (list "fallocate" "-l" "1kB" fa-file))
    (fa-case () (list "fallocate" "-l" "+1" fa-file))
    (fa-case () (list "fallocate" "-o" "x" "-l" "1" fa-file))
    (fa-case () (list "fallocate" "-l" "18446744073709551616" fa-file))
    (fa-case () (list "fallocate" "-l" "18014398509481984k" fa-file))
    (fa-case () (list "fallocate" "-l" "0" fa-file))
    (fa-case () (list "fallocate" "-l" "9223372036854775808" fa-file))
    (fa-case () (list "fallocate" "-l" "1" "/tmp")))
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
same
```

## the clean-up

```cu
(do (fa-sh "rm -f /tmp/fa-file /tmp/fa-xo /tmp/fa-xe /tmp/fa-bo /tmp/fa-bx /tmp/fa-be /tmp/fa-bs /tmp/fa-st")
    (display "gone"))
```
---
    gone
