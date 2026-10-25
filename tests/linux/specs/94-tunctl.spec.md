# @weight 2

busybox's tunctl (networking/tunctl.c), run as root in a namespace of its
own, tun, which this file's process enters, so its interfaces touch no
other file's.  Each case is a run of commands: it takes away every
interface but the loopback, runs the bundle's tunctl on each, lists the
TUN/TAP interfaces with their type, persistence, owner and group, then
does the same with busybox's, and compares what each writes, its statuses
and the interfaces it leaves.

## the comparison

### the applet against busybox's, the interfaces taken away for each

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (def lx-tuns "ip2 -d -o link | sed -nE 's/^[0-9]+: ([^:@]+)[^ ]*: .*(tun type .*) numtxqueues.*/\\1 \\2/p' > /tmp/lx-tl")
    (def lx-reset (fn (_)
      (lx-sh (Str8 join "\n" (list
              "[ \"$(readlink /proc/self/ns/net)\" != \"$(readlink /proc/1/ns/net)\" ] || exit 1"
              "for l in $(ip2 -o link | grep -v link/loopback | sed -E 's/^[0-9]+: ([^:@]+).*/\\1/'); do ip2 link del $l 2>/dev/null; done"
              "true")))))
    (def lx-x1 (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (def lx-o (file-open-write "/tmp/lx-xo")) (def lx-e (file-open-write "/tmp/lx-xe"))
          (sys-dup2 lx-o 1) (sys-dup2 lx-e 2)
          (def lx-st (cu-run argv ""))
          (sys-dup2 9 1) (sys-dup2 8 2) (file-close lx-o) (file-close lx-e)
          (string-concat (list (lx-read "/tmp/lx-xo") "stderr:\n" (lx-read "/tmp/lx-xe") "status " (cu-int->str lx-st) "\n")))))
    (def lx-bb1 (fn (_ argv)
      (do (lx-sh (string-concat (list "/bin/busybox " (Str8 join " " (map lx-q argv)) " > /tmp/lx-bo 2> /tmp/lx-bx; echo $? > /tmp/lx-bs; sed '/^BusyBox v/{N;d;}' /tmp/lx-bx > /tmp/lx-be")))
          (string-concat (list (lx-read "/tmp/lx-bo") "stderr:\n" (lx-read "/tmp/lx-be") "status " (lx-read "/tmp/lx-bs"))))))
    (def lx-run (fn (_ one runs)
      (do (lx-reset)
          (def lx-out (string-concat (map one runs)))
          (lx-sh lx-tuns)
          (string-append lx-out (lx-read "/tmp/lx-tl")))))
    (def lx-case (fn (_ runs)
      (do (def lx-a (lx-run lx-x1 runs)) (def lx-b (lx-run lx-bb1 runs))
          (display (if (string=? lx-a lx-b) "same\n" (string-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    (lx-sh "ip2 netns add tun")
    (def lx-ns (in-call (cu-ptr-call (in-c "open") "/var/run/netns/tun" 0)))
    (display (if (= (in-call (cu-ptr-call (in-c "setns") lx-ns 1073741824)) 0) "made" "no namespace")))
```
---
    made

## made and taken back

### the kernel's name, brief, a name of its own, made twice, taken back, none to take

```cu
(do (lx-case (list (list "tunctl") (list "tunctl")))
    (lx-case (list (list "tunctl" "-b")))
    (lx-case (list (list "tunctl" "-t" "tq1") (list "tunctl" "-t" "tq1")))
    (lx-case (list (list "tunctl" "-t" "tq1") (list "tunctl" "-d" "tq1")))
    (lx-case (list (list "tunctl" "-d" "nosuch"))))
```
---
```output
same
same
same
same
same
```

### names: too long, a number of the kernel's, brief before and after

```cu
(do (lx-case (list (list "tunctl" "-t" "abcdefghijklmnopqrs")))
    (lx-case (list (list "tunctl" "-t" "tq%d") (list "tunctl" "-t" "tq%d")))
    (lx-case (list (list "tunctl" "-t" "tun%d" "-b") (list "tunctl" "-b" "-t" "tq7"))))
```
---
```output
same
same
same
```

## owners

### a user, a group alone, both, numbers, names not known

```cu
(do (lx-case (list (list "tunctl" "-t" "tq2" "-u" "nobody")))
    (lx-case (list (list "tunctl" "-t" "tq3" "-g" "wheel")))
    (lx-case (list (list "tunctl" "-t" "tq4" "-u" "nobody" "-g" "wheel")))
    (lx-case (list (list "tunctl" "-t" "tq5" "-u" "65534") (list "tunctl" "-t" "tq5" "-g" "5")))
    (lx-case (list (list "tunctl" "-t" "tq6" "-g" "nosuchgrp") (list "tunctl" "-t" "tq6" "-u" "nosuchusr")
                   (list "tunctl" "-t" "tq6" "-u" "nosuchusr" "-g" "nosuchgrp"))))
```
---
```output
same
same
same
same
same
```

## refusals

### the device not there, not a TUN device; the usage

```cu
(do (lx-case (list (list "tunctl" "-f" "/nonexist") (list "tunctl" "-f" "/dev/null" "-t" "z")))
    (lx-case (list (list "tunctl" "-t" "a" "-d" "b") (list "tunctl" "x"))))
```
---
```output
same
same
```
