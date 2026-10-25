# @weight 2

busybox's nameif (networking/nameif.c), run as root in a namespace of its
own, nin, which this file's process enters, so the renames touch no other
file's interfaces: nia0 (02:00:00:00:06:01) a veth facing nib0
(02:00:00:00:06:02), which is up, and nid0 (02:00:00:00:06:03), a dummy.
Each case builds them anew, runs the bundle's nameif, lists the names, then
builds them anew for busybox's on the same words, and compares what each
writes, its status and the names it leaves.

## the comparison

### the applet against busybox's, the interfaces built anew for each

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (def lx-names "ip2 -o link | sed -E 's/^[0-9]+: ([^:@]+).*/\\1/' | sort | tr '\\n' ' ' > /tmp/lx-nn; echo >> /tmp/lx-nn")
    (def lx-reset (fn (_)
      (lx-sh (Str8 join "\n" (list
              "[ \"$(readlink /proc/self/ns/net)\" != \"$(readlink /proc/1/ns/net)\" ] || exit 1"
              "l=$(ip2 -o link | grep link/loopback | sed -E 's/^[0-9]+: ([^:@]+).*/\\1/'); [ \"$l\" = lo ] || ip2 link set dev \"$l\" name lo"
              "for l in $(ip2 -o link | grep -v link/loopback | sed -E 's/^[0-9]+: ([^:@]+).*/\\1/'); do ip2 link del $l 2>/dev/null; done"
              "ip2 link add nia0 address 02:00:00:00:06:01 type veth peer name nib0 address 02:00:00:00:06:02"
              "ip2 link add nid0 address 02:00:00:00:06:03 type dummy"
              "ip2 link set nib0 up"
              "true")))))
    (def lx-x (fn (_ argv)
      (do (lx-reset)
          (sys-dup2 1 9) (sys-dup2 2 8)
          (def lx-o (file-open-write "/tmp/lx-xo")) (def lx-e (file-open-write "/tmp/lx-xe"))
          (sys-dup2 lx-o 1) (sys-dup2 lx-e 2)
          (def lx-st (cu-run argv ""))
          (sys-dup2 9 1) (sys-dup2 8 2) (file-close lx-o) (file-close lx-e)
          (lx-sh lx-names)
          (string-concat (list (lx-read "/tmp/lx-xo") "stderr:\n" (lx-read "/tmp/lx-xe") "status " (cu-int->str lx-st) "\n"
                               (lx-read "/tmp/lx-nn"))))))
    (def lx-bb (fn (_ argv)
      (do (lx-reset)
          (lx-sh (string-concat (list "/bin/busybox " (Str8 join " " (map lx-q argv)) " > /tmp/lx-bo 2> /tmp/lx-bx; echo $? > /tmp/lx-bs; sed '/^BusyBox v/{N;d;}' /tmp/lx-bx > /tmp/lx-be; " lx-names)))
          (string-concat (list (lx-read "/tmp/lx-bo") "stderr:\n" (lx-read "/tmp/lx-be") "status " (lx-read "/tmp/lx-bs")
                               (lx-read "/tmp/lx-nn"))))))
    (def lx-case (fn (_ argv)
      (do (def lx-a (lx-x argv)) (def lx-b (lx-bb argv))
          (display (if (string=? lx-a lx-b) "same\n" (string-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    (lx-sh "ip2 netns add nin")
    (def lx-ns (in-call (cu-ptr-call (in-c "open") "/var/run/netns/nin" 0)))
    (display (if (= (in-call (cu-ptr-call (in-c "setns") lx-ns 1073741824)) 0) "made" "no namespace")))
```
---
    made

## renames

### by address, by driver and bus, by phyaddr before and after, to its own name

```cu
(do (lx-case (list "nameif" "rn1" "02:00:00:00:06:01"))
    (lx-case (list "nameif" "rn1" "mac=02:00:00:00:06:01"))
    (lx-case (list "nameif" "rn1" "driver=veth bus="))
    (lx-case (list "nameif" "rn2" "driver=dummy"))
    (lx-case (list "nameif" "rn3" "phyaddr=0 driver=veth"))
    (lx-case (list "nameif" "rn3" "driver=veth phyaddr=0"))
    (lx-case (list "nameif" "nid0" "driver=dummy"))
    (lx-case (list "nameif" "rn4" "driver=nothing")))
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

### one that is up, the latest pair first, each entry spent, a name taken

```cu
(do (lx-case (list "nameif" "rn4" "02:00:00:00:06:02"))
    (lx-case (list "nameif" "rn6" "02:0:0:0:6:3" "rn7" "02:00:00:00:06:03"))
    (lx-case (list "nameif" "rn6" "driver=veth" "rn7" "driver=veth"))
    (lx-case (list "nameif" "nib0" "02:00:00:00:06:01")))
```
---
```output
same
same
same
same
```

### addresses as strtoul reads them

```cu
(do (lx-case (list "nameif" "rn5" "0x2:00:00:00:06:03"))
    (lx-case (list "nameif" "rn5" " 2:+0:00:00:06:03"))
    (lx-case (list "nameif" "rn5" ":::::")))
```
---
```output
same
same
same
```

## words and the file

### the usage, selectors that will not parse

```cu
(do (lx-case (list "nameif" "a"))
    (lx-case (list "nameif" "a" "02:00:00:00:06:01" "b"))
    (lx-case (list "nameif" "abcdefghijklmnop" "02:00:00:00:06:01"))
    (lx-case (list "nameif" "a" "zz"))
    (lx-case (list "nameif" "a" "  "))
    (lx-case (list "nameif" "a" "phyaddr=x"))
    (lx-case (list "nameif" "a" "mac=02:00:00:00:06:0g")))
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
```

### /etc/mactab and -c's file, a short line passed over, the words over the file, -s

```cu
(do (lx-case (list "nameif"))
    (lx-case (list "nameif" "-c" "/nonexist"))
    (file-write-all "/tmp/lx-mactab" "# c\nrn8 02:00:00:00:06:03 # x\n\nlonely\n  rn9\tdriver=dummy\n")
    (lx-case (list "nameif" "-c" "/tmp/lx-mactab"))
    (lx-case (list "nameif" "-c" "/tmp/lx-mactab" "rn1" "driver=dummy"))
    (lx-case (list "nameif" "-s" "-c" "/tmp/lx-mactab")))
```
---
```output
same
same
same
same
same
```
