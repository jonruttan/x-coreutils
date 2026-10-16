# @weight 2

busybox's ifconfig (networking/ifconfig.c, networking/interface.c), run as
root against the container's own interfaces.  Each case runs the bundle's
ifconfig and busybox's on the same words, PRE through the shell before
each, and compares what they write and their status, and where it says so
what `ip addr` says of the interface after.  The interfaces are made for
it -- a dummy, lx0, and a veth pair -- and eth0 is down while they run, so
nothing counts traffic under the cases.

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
    ; as lx-case, with what POST says after each side's run compared too: the
    ; kernel's own account of what the run changed
    (def lx-case-after (fn (_ pre argv post)
      (do (lx-sh pre) (def lx-a (lx-x argv)) (lx-sh (string-concat (list "{ " post "; } > /tmp/lx-post 2>&1"))) (def lx-pa (lx-read "/tmp/lx-post"))
          (lx-sh pre) (def lx-b (lx-bb argv)) (lx-sh (string-concat (list "{ " post "; } > /tmp/lx-post 2>&1"))) (def lx-pb (lx-read "/tmp/lx-post"))
          (display (if (if (string=? lx-a lx-b) (string=? lx-pa lx-pb) #f) "same\n"
                     (string-concat (list "ours:\n" lx-a lx-pa "busybox:\n" lx-b lx-pb)))))))
    (display "made"))
```
---
    made

### the interfaces

```cu
(do (lx-sh "ip link add lx0 type dummy; ip link add lxa type veth peer name lxb; ip link set eth0 down; true")
    (def lx-reset "ip link set lx0 down; ip addr flush dev lx0; ip link set lx0 mtu 1500 txqueuelen 1000 -promisc arp on multicast on allmulti off address 02:00:00:00:00:01 2>/dev/null; ip link set lx0 promisc off; ip link set lx0 allmulti off; true")
    (def lx-show "ip addr show lx0")
    (lx-sh lx-reset)
    (display "made"))
```
---
    made

## showing

### the interfaces that are up, all of them with -a, one by name, one that is not there, a word that is no interface

```cu
(do (lx-case ":" (list "ifconfig"))
    (lx-case ":" (list "ifconfig" "-a"))
    (lx-case ":" (list "ifconfig" "lx0"))
    (lx-case ":" (list "ifconfig" "lxa"))
    (lx-case ":" (list "ifconfig" "lo"))
    (lx-case ":" (list "ifconfig" "nosuch0"))
    (lx-case ":" (list "ifconfig" "-~")))
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

### an interface with addresses, an alias among them, and its flags

```cu
(do (lx-sh "ip link set lx0 up; ip addr add 10.66.0.1/24 broadcast 10.66.0.255 dev lx0; ip addr add 10.66.1.1/24 dev lx0 label lx0:1; ip addr add fd00:66::1/64 dev lx0 nodad; ip link set lx0 promisc on")
    (lx-case ":" (list "ifconfig" "lx0"))
    (lx-case ":" (list "ifconfig" "-a"))
    (lx-case ":" (list "ifconfig" "lx0:1"))
    (lx-sh lx-reset) (display ""))
```
---
```output
same
same
same
```

## setting

### an address brings it up; netmask, broadcast and dstaddr; and the words inet and default

```cu
(do (lx-case-after lx-reset (list "ifconfig" "lx0" "10.66.0.1") lx-show)
    (lx-case-after lx-reset (list "ifconfig" "lx0" "10.66.0.1" "netmask" "255.255.255.0" "broadcast" "10.66.0.255") lx-show)
    (lx-case-after lx-reset (list "ifconfig" "lx0" "inet" "10.66.0.2" "netmask" "255.255.0.0") lx-show)
    (lx-case-after lx-reset (list "ifconfig" "lx0" "10.66.0.1" "-broadcast") lx-show)
    (lx-case-after lx-reset (list "ifconfig" "lx0" "10.66.0.1" "dstaddr" "10.66.0.9") lx-show)
    (lx-case-after lx-reset (list "ifconfig" "lx0" "default") lx-show))
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

### the flags, each set and cleared

```cu
(do (lx-case-after lx-reset (list "ifconfig" "lx0" "up") lx-show)
    (lx-case-after (string-append lx-reset "; ip link set lx0 up") (list "ifconfig" "lx0" "down") lx-show)
    (lx-case-after lx-reset (list "ifconfig" "lx0" "promisc" "allmulti" "-multicast") lx-show)
    (lx-case-after lx-reset (list "ifconfig" "lx0" "-arp" "trailers") lx-show)
    (lx-case-after lx-reset (list "ifconfig" "lx0" "dynamic" "-dynamic") lx-show))
```
---
```output
same
same
same
same
same
```

### mtu, txqueuelen, metric, a hardware address, and IPv6 added and deleted

```cu
(do (lx-case-after lx-reset (list "ifconfig" "lx0" "mtu" "1400" "txqueuelen" "50") (string-append lx-show "; ip -d link show lx0"))
    (lx-case-after lx-reset (list "ifconfig" "lx0" "metric" "2") lx-show)
    (lx-case-after lx-reset (list "ifconfig" "lx0" "hw" "ether" "02:00:00:00:00:07") lx-show)
    (lx-case-after lx-reset (list "ifconfig" "lx0" "add" "fd00:66::5/64") lx-show)
    (lx-case-after (string-append lx-reset "; ip addr add fd00:66::5/64 dev lx0 nodad") (list "ifconfig" "lx0" "del" "fd00:66::5/64") lx-show)
    (lx-case-after lx-reset (list "ifconfig" "lx0" "mtu" "0x400") lx-show))
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

### what ifconfig refuses: a flag that takes no -, a second netmask, no argument, a bad address, a bad hardware address, a hardware class it does not know, a prefix on IPv4, and what the kernel refuses

```cu
(do (lx-case lx-reset (list "ifconfig" "lx0" "-up"))
    (lx-case lx-reset (list "ifconfig" "lx0" "10.66.0.1" "netmask" "255.0.0.0" "netmask" "255.255.0.0"))
    (lx-case lx-reset (list "ifconfig" "lx0" "mtu"))
    (lx-case lx-reset (list "ifconfig" "lx0" "300.1.2.3"))
    (lx-case lx-reset (list "ifconfig" "lx0" "hw" "ether" "zz"))
    (lx-case lx-reset (list "ifconfig" "lx0" "hw" "token" "02:00"))
    (lx-case lx-reset (list "ifconfig" "lx0" "10.66.0.1/24"))
    (lx-case lx-reset (list "ifconfig" "lx0" "mem_start" "0x1000"))
    (lx-case lx-reset (list "ifconfig" "nosuch0" "up"))
    (lx-case lx-reset (list "ifconfig" "lx0" "pointopoint")))
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

### the interfaces taken away

```cu
(do (lx-sh "ip link del lx0; ip link del lxa; ip link set eth0 up; true") (display "gone"))
```
---
    gone
