# @weight 2

busybox's vconfig (networking/vconfig.c), run as root in a namespace of its
own, vcn, which this file's process enters, so its VLANs and its name type
touch no other file's: vca0 (02:00:00:00:07:01) is a dummy to put them on.
Each case is a run of commands: it builds vca0 anew with the name type
DEV_PLUS_VID_NO_PAD, runs the bundle's vconfig on each, lists the VLANs
with their ids, flags and maps, then does the same with busybox's, and
compares what each writes, its statuses and the VLANs it leaves.

## the comparison

### the applet against busybox's, vca0 built anew for each

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (def lx-vlans "ip2 -d -o link | sed -nE 's/^[0-9]+: ([^:@]+)[^ ]*: .*(vlan protocol .*) numtxqueues.*/\\1 \\2/p' > /tmp/lx-vl")
    (def lx-reset (fn (_)
      (lx-sh (Str8 join "\n" (list
              "[ \"$(readlink /proc/self/ns/net)\" != \"$(readlink /proc/1/ns/net)\" ] || exit 1"
              "for l in $(ip2 -o link | grep -v link/loopback | sed -E 's/^[0-9]+: ([^:@]+).*/\\1/'); do ip2 link del $l 2>/dev/null; done"
              "ip2 link add vca0 address 02:00:00:00:07:01 type dummy"
              "/bin/busybox vconfig set_name_type DEV_PLUS_VID_NO_PAD"
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
          (lx-sh lx-vlans)
          (string-append lx-out (lx-read "/tmp/lx-vl")))))
    (def lx-case (fn (_ runs)
      (do (def lx-a (lx-run lx-x1 runs)) (def lx-b (lx-run lx-bb1 runs))
          (display (if (string=? lx-a lx-b) "same\n" (string-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    (lx-sh "ip2 netns add vcn")
    (def lx-ns (in-call (cu-ptr-call (in-c "open") "/var/run/netns/vcn" 0)))
    (display (if (= (in-call (cu-ptr-call (in-c "setns") lx-ns 1073741824)) 0) "made" "no namespace")))
```
---
    made

## add and rem

### a VLAN made, made twice, at the ends of the ids, on no interface, removed

```cu
(do (lx-case (list (list "vconfig" "add" "vca0" "5")))
    (lx-case (list (list "vconfig" "add" "vca0" "5") (list "vconfig" "add" "vca0" "5")))
    (lx-case (list (list "vconfig" "add" "vca0" "0") (list "vconfig" "add" "vca0" "4095")))
    (lx-case (list (list "vconfig" "add" "vca0" "4096") (list "vconfig" "add" "vca0" "-1") (list "vconfig" "add" "vca0" "x")))
    (lx-case (list (list "vconfig" "add" "nosuch" "3") (list "vconfig" "rem" "nosuch")))
    (lx-case (list (list "vconfig" "add" "vca0" "5") (list "vconfig" "rem" "vca0.5")))
    (lx-case (list (list "vconfig" "ADD" "vca0" "6") (list "vconfig" "Rem" "vca0.6"))))
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

## set_flag and the maps

### the flag cleared and set, its QoS, the maps both ways, their numbers

```cu
(do (lx-case (list (list "vconfig" "add" "vca0" "5") (list "vconfig" "set_flag" "vca0.5" "0" "0")))
    (lx-case (list (list "vconfig" "add" "vca0" "5") (list "vconfig" "set_flag" "vca0.5" "0" "3")))
    (lx-case (list (list "vconfig" "add" "vca0" "5") (list "vconfig" "set_flag" "vca0.5" "0" "3") (list "vconfig" "set_flag" "vca0.5" "1" "1")))
    (lx-case (list (list "vconfig" "add" "vca0" "5") (list "vconfig" "set_flag" "vca0.5" "2" "0") (list "vconfig" "set_flag" "vca0.5" "1" "8")))
    (lx-case (list (list "vconfig" "add" "vca0" "5") (list "vconfig" "set_egress_map" "vca0.5" "4" "6") (list "vconfig" "set_ingress_map" "vca0.5" "2" "5")))
    (lx-case (list (list "vconfig" "add" "vca0" "5") (list "vconfig" "set_egress_map" "vca0.5" "4294967295" "7") (list "vconfig" "set_egress_map" "vca0.5" "4294967296" "0")))
    (lx-case (list (list "vconfig" "set_egress_map" "nosuch" "1" "1") (list "vconfig" "set_ingress_map" "nosuch" "1" "1") (list "vconfig" "set_flag" "nosuch" "1" "0"))))
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

## set_name_type

### each name type, then a VLAN named by it; one not known

```cu
(do (lx-case (list (list "vconfig" "set_name_type" "VLAN_PLUS_VID") (list "vconfig" "add" "vca0" "7")))
    (lx-case (list (list "vconfig" "set_name_type" "vlan_plus_vid_no_pad") (list "vconfig" "add" "vca0" "7")))
    (lx-case (list (list "vconfig" "set_name_type" "DEV_PLUS_VID") (list "vconfig" "add" "vca0" "7")))
    (lx-case (list (list "vconfig" "set_name_type" "DEV_PLUS_VID_NO_PAD") (list "vconfig" "add" "vca0" "7")))
    (lx-case (list (list "vconfig" "set_name_type" "VLAN_PLUS") (list "vconfig" "set_name_type" "VLAN_PLUS_VID" "x"))))
```
---
```output
same
same
same
same
same
```

## the usage

### no command, one not known, a count not the command's

```cu
(lx-case (list (list "vconfig") (list "vconfig" "frob") (list "vconfig" "add" "vca0") (list "vconfig" "rem")
               (list "vconfig" "set_flag" "vca0" "1")))
```
---
```output
same
```
