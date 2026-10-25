# @weight 2

busybox's arping (networking/arping.c), run as root over veth pairs
iproute2 builds: aph0 (10.3.0.1, 02:00:00:00:03:01) facing apr0 (10.3.0.2,
02:00:00:00:03:02) in the namespace apn; aph1, a pair left down; and apd0,
a dummy, which has no ARP.  Each case runs the bundle's arping and
busybox's on the same words and compares what they write and their
status, each reply's time written as T.

## the comparison

### the applet against busybox's, the times set aside

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (def lx-times "sed -E 's/ [0-9]+[.][0-9]{3}ms$/ Tms/'")
    (def lx-x (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (def lx-o (file-open-write "/tmp/lx-xo")) (def lx-e (file-open-write "/tmp/lx-xe"))
          (sys-dup2 lx-o 1) (sys-dup2 lx-e 2)
          (def lx-st (cu-run argv ""))
          (sys-dup2 9 1) (sys-dup2 8 2) (file-close lx-o) (file-close lx-e)
          (lx-sh (string-append lx-times " /tmp/lx-xo > /tmp/lx-xn"))
          (string-concat (list (lx-read "/tmp/lx-xn") "stderr:\n" (lx-read "/tmp/lx-xe") "status " (cu-int->str lx-st) "\n")))))
    (def lx-bb (fn (_ argv)
      (do (lx-sh (string-concat (list "/bin/busybox " (Str8 join " " (map lx-q argv)) " > /tmp/lx-bo 2> /tmp/lx-bx; echo $? > /tmp/lx-bs; sed '/^BusyBox v/{N;d;}' /tmp/lx-bx > /tmp/lx-be; " lx-times " /tmp/lx-bo > /tmp/lx-bn")))
          (string-concat (list (lx-read "/tmp/lx-bn") "stderr:\n" (lx-read "/tmp/lx-be") "status " (lx-read "/tmp/lx-bs"))))))
    (def lx-case (fn (_ argv)
      (do (def lx-a (lx-x argv)) (def lx-b (lx-bb argv))
          (display (if (string=? lx-a lx-b) "same\n" (string-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    (lx-sh (Str8 join "\n" (list
            "ip2 netns add apn"
            "ip2 link add aph0 address 02:00:00:00:03:01 type veth peer name apr0 address 02:00:00:00:03:02 netns apn"
            "ip2 addr add 10.3.0.1/24 dev aph0; ip2 link set aph0 up"
            "ip2 -n apn addr add 10.3.0.2/24 dev apr0; ip2 -n apn link set apr0 up; ip2 -n apn link set lo up"
            "ip2 link add aph1 address 02:00:00:00:04:01 type veth peer name apr1 address 02:00:00:00:04:02 netns apn"
            "ip2 link add apd0 type dummy; ip2 link set apd0 up"
            "ip link set lo up"
            "true")))
    (display "made"))
```
---
    made

## replies

### a count, the first reply, quiet, broadcasts throughout, a source

```cu
(do (lx-case (list "arping" "-c" "2" "-I" "aph0" "10.3.0.2"))
    (lx-case (list "arping" "-f" "-I" "aph0" "10.3.0.2"))
    (lx-case (list "arping" "-q" "-c" "1" "-I" "aph0" "10.3.0.2"))
    (lx-case (list "arping" "-b" "-c" "2" "-I" "aph0" "10.3.0.2"))
    (lx-case (list "arping" "-s" "10.3.0.1" "-c" "1" "-I" "aph0" "10.3.0.2")))
```
---
```output
same
same
same
same
same
```

### none: a count, a deadline, a count of 0

```cu
(do (lx-case (list "arping" "-c" "1" "-I" "aph0" "10.3.0.9"))
    (lx-case (list "arping" "-w" "1" "-I" "aph0" "10.3.0.9"))
    (lx-case (list "arping" "-c" "0" "-I" "aph0" "10.3.0.2")))
```
---
```output
same
same
same
```

### -D finds a duplicate or none; -U and -A announce our own address

```cu
(do (lx-case (list "arping" "-D" "-c" "2" "-I" "aph0" "10.3.0.2"))
    (lx-case (list "arping" "-D" "-c" "1" "-I" "aph0" "10.3.0.9"))
    (lx-case (list "arping" "-U" "-c" "1" "-I" "aph0" "10.3.0.1"))
    (lx-case (list "arping" "-A" "-c" "2" "-I" "aph0" "10.3.0.1")))
```
---
```output
same
same
same
same
```

## the errors

### the usage, the numbers, the address, the source

```cu
(do (lx-case (list "arping"))
    (lx-case (list "arping" "a" "b"))
    (lx-case (list "arping" "-c" "x" "-I" "aph0" "10.3.0.2"))
    (lx-case (list "arping" "-w" "2000" "-I" "aph0" "10.3.0.2"))
    (lx-case (list "arping" "-I" "aph0" "nosuch.invalid"))
    (lx-case (list "arping" "-s" "bogus" "-I" "aph0" "10.3.0.2"))
    (lx-case (list "arping" "-s" "10.3.0.7" "-c" "1" "-I" "aph0" "10.3.0.2"))
    (lx-case (list "arping" "-U" "-c" "1" "-I" "aph0" "10.3.0.2")))
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
```

### interfaces: none such, the loopback and a dummy with no ARP, -D's 0 for them, one down

```cu
(do (lx-case (list "arping" "-I" "nope" "10.3.0.2"))
    (lx-case (list "arping" "-I" "lo" "10.3.0.2"))
    (lx-case (list "arping" "-D" "-I" "lo" "10.3.0.2"))
    (lx-case (list "arping" "-I" "apd0" "10.3.0.2"))
    (lx-case (list "arping" "-I" "aph1" "10.3.0.2")))
```
---
```output
same
same
same
same
same
```
