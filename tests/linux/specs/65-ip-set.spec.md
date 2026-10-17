# @weight 2

busybox's ip verbs that change the kernel's state (networking/libiproute:
ipaddr_modify, the flush of ipaddr_list_or_flush, iplink's do_set and
do_add_or_delete), run as root against interfaces made for it.  Each case
runs the bundle's applet and busybox's on the same words, PRE through the
shell before each to set the interfaces as the case needs them, and
compares what they write, their status, and what `ip` says of the
interfaces after.

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
(do (lx-sh "ip link set eth0 down; ip link add lx0 type dummy; sysctl -qw net.ipv6.conf.lx0.accept_dad=0; ip link add lxr type vrf table 10; true")
    (def lx-reset "ip link del lxv 2>/dev/null; ip link del lx0.7 2>/dev/null; ip link del lx0.8 2>/dev/null; ip link set lx9 name lx0 2>/dev/null; ip link set lx0 nomaster; ip link set lx0 down; ip addr flush dev lx0; ip link set lx0 mtu 1500 qlen 1000 arp on multicast on promisc off address 02:00:00:00:00:01; true")
    (def lx-show "ip addr show dev lx0")
    (def lx-links "ip link show")
    ; a link made anew has the next index and, unless the case gives one, a random
    ; address; eth0's peer, outside the container, may hold the same index
    (def lx-made "ip link show | sed -e 's/^[0-9]*: /N: /' -e 's/^N: eth0@[^:]*:/N: eth0@PEER:/' -e '/link\\/ether 02:00:00:/!s/link\\/ether [0-9a-f:]*/link\\/ether MAC/'")
    (lx-sh lx-reset)
    (display "made"))
```
---
    made

## addresses

### added: each way of giving one

```cu
(do (lx-case-after lx-reset (list "ip" "addr" "add" "10.66.0.1/24" "dev" "lx0") lx-show)
    (lx-case-after lx-reset (list "ip" "a" "add" "10.66.0.1/24" "brd" "+" "dev" "lx0") lx-show)
    (lx-case-after lx-reset (list "ip" "a" "add" "10.66.0.1/24" "broadcast" "-" "dev" "lx0") lx-show)
    (lx-case-after lx-reset (list "ip" "a" "add" "10.66.0.1/24" "broadcast" "10.66.0.200" "dev" "lx0") lx-show)
    (lx-case-after lx-reset (list "ip" "a" "add" "10.66.0.1/31" "brd" "+" "dev" "lx0") lx-show)
    (lx-case-after lx-reset (list "ip" "a" "add" "10.66.0.1" "peer" "10.66.0.2/32" "dev" "lx0") lx-show)
    (lx-case-after lx-reset (list "ip" "a" "add" "10.66.0.1" "remote" "10.66.8.0/24" "brd" "+" "dev" "lx0") lx-show)
    (lx-case-after lx-reset (list "ip" "a" "add" "local" "10.66.0.1/24" "dev" "lx0" "label" "lx0:3") lx-show)
    (lx-case-after lx-reset (list "ip" "a" "add" "10.66.0.1/24" "dev" "lx0" "scope" "link") lx-show)
    (lx-case-after lx-reset (list "ip" "a" "add" "10.66.0.1/24" "dev" "lx0" "scope" "50") lx-show)
    (lx-case-after lx-reset (list "ip" "a" "add" "127.6.6.6/8" "dev" "lx0") lx-show)
    (lx-case-after lx-reset (list "ip" "a" "add" "10.66.0.1/255.255.0.0" "dev" "lx0") lx-show)
    (lx-case-after lx-reset (list "ip" "a" "add" "fd00:66::1/64" "dev" "lx0") lx-show)
    (lx-case-after lx-reset (list "ip" "-6" "a" "add" "fd00:66::1/64" "dev" "lx0" "noprefixroute") lx-show)
    (lx-case-after lx-reset (list "ip" "a" "add" "10.66.0.1/24" "dev" "lx0" "valid_lft" "forever" "preferred_lft" "forever") lx-show)
    (lx-case-after lx-reset (list "ip" "a" "add" "10.66.0.1/24" "dev" "lx0" "anycast" "10.66.0.9") lx-show)
    (lx-case-after lx-reset (list "ipaddr" "add" "10.66.0.1/24" "dev" "lx0") lx-show))
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
same
same
same
same
same
same
```

### changed, replaced, deleted, and added twice

```cu
(do (def lx-one (string-append lx-reset "; ip addr add 10.66.0.1/24 dev lx0"))
    (lx-case-after lx-one (list "ip" "a" "add" "10.66.0.1/24" "dev" "lx0") lx-show)
    (lx-case-after lx-one (list "ip" "a" "change" "10.66.0.1/24" "dev" "lx0" "label" "lx0:9") lx-show)
    (lx-case-after lx-one (list "ip" "a" "chg" "10.66.0.1/24" "dev" "lx0" "brd" "+") lx-show)
    (lx-case-after lx-one (list "ip" "a" "replace" "10.66.0.1/24" "dev" "lx0" "scope" "link") lx-show)
    (lx-case-after lx-reset (list "ip" "a" "replace" "10.66.0.5/24" "dev" "lx0") lx-show)
    (lx-case-after lx-one (list "ip" "a" "delete" "10.66.0.1/24" "dev" "lx0") lx-show)
    (lx-case-after lx-one (list "ip" "a" "del" "10.66.0.1" "dev" "lx0") lx-show)
    (lx-case-after lx-one (list "ip" "a" "d" "10.66.0.7/24" "dev" "lx0") lx-show)
    (lx-case-after lx-reset (list "ip" "a" "change" "10.66.0.5/24" "dev" "lx0") lx-show))
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
```

### what add refuses

```cu
(do (lx-case lx-reset (list "ip" "a" "add"))
    (lx-case lx-reset (list "ip" "a" "add" "10.66.0.1/24"))
    (lx-case lx-reset (list "ip" "a" "add" "10.66.0.1/24" "dev" "lx0" "label" "foo"))
    (lx-case lx-reset (list "ip" "a" "add" "10.66.0.1/24" "dev" "lx0" "valid_lft" "0"))
    (lx-case lx-reset (list "ip" "a" "add" "10.66.0.1/24" "dev" "lx0" "valid_lft" "5" "preferred_lft" "9"))
    (lx-case lx-reset (list "ip" "a" "add" "10.66.0.1/24" "dev" "lx0" "valid_lft" "5" "valid_lft" "6"))
    (lx-case lx-reset (list "ip" "a" "add" "10.66.0.1/24" "dev" "lx0" "valid_lft" "x"))
    (lx-case lx-reset (list "ip" "a" "add" "10.66.0.1/24" "dev" "lx0" "preferred_lft"))
    (lx-case lx-reset (list "ip" "a" "add" "fd00::1/64" "dev" "lx0" "brd" "+"))
    (lx-case lx-reset (list "ip" "a" "add" "10.66.0.1/24" "10.66.0.2/24" "dev" "lx0"))
    (lx-case lx-reset (list "ip" "a" "add" "10.66.0.1" "peer" "10.66.0.2" "peer" "10.66.0.3" "dev" "lx0"))
    (lx-case lx-reset (list "ip" "a" "add" "10.66.0.1/24" "brd" "+" "brd" "-" "dev" "lx0"))
    (lx-case lx-reset (list "ip" "a" "add" "10.66.0.1/24" "brd" "fd00::1" "dev" "lx0"))
    (lx-case lx-reset (list "ip" "a" "add" "10.66.0.1/24" "brd" "foo" "dev" "lx0"))
    (lx-case lx-reset (list "ip" "a" "add" "10.66.0.1/24" "dev" "lx0" "scope" "bogus"))
    (lx-case lx-reset (list "ip" "a" "add" "10.66.0.1/99" "dev" "lx0"))
    (lx-case lx-reset (list "ip" "a" "add" "10.66.0.1/24" "dev" "nosuch0"))
    (lx-case lx-reset (list "ip" "-0" "a" "add" "10.66.0.1/24" "dev" "lx0"))
    (lx-case lx-reset (list "ip" "-6" "a" "add" "10.66.0.1/24" "dev" "lx0")))
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
same
same
same
same
same
same
same
same
```

### flushed: by device, prefix, label, scope and family

```cu
(do (def lx-many (string-append lx-reset "; ip addr add 10.66.0.1/24 dev lx0; ip addr add 10.66.0.2/24 dev lx0; ip addr add 10.66.1.1/24 dev lx0 label lx0:1; ip addr add 10.66.2.1/24 dev lx0 scope link; ip addr add fd00:66::1/64 dev lx0"))
    (lx-case-after lx-many (list "ip" "a" "flush" "dev" "lx0") lx-show)
    (lx-case-after lx-many (list "ip" "a" "flush" "lx0" "to" "10.66.1.0/24") lx-show)
    (lx-case-after lx-many (list "ip" "a" "flush" "label" "lx0:*") lx-show)
    (lx-case-after lx-many (list "ip" "a" "flush" "dev" "lx0" "scope" "link") lx-show)
    (lx-case-after lx-many (list "ip" "-4" "a" "flush" "dev" "lx0") lx-show)
    (lx-case-after lx-many (list "ip" "-6" "a" "flush" "dev" "lx0") lx-show)
    (lx-case-after lx-many (list "ip" "a" "flush" "to" "10.66.0.2") lx-show)
    (lx-case-after lx-many (list "ip" "a" "flush" "dev" "lx0" "to" "10.99.0.0/16") lx-show)
    (lx-case lx-many (list "ip" "a" "flush"))
    (lx-case lx-many (list "ip" "-0" "a" "flush" "dev" "lx0"))
    (lx-case lx-many (list "ip" "a" "flush" "dev" "nosuch0")))
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

## links

### set: flags, mtu, qlen, address, name and master

```cu
(do (lx-case-after lx-reset (list "ip" "link" "set" "lx0" "up") lx-links)
    (lx-case-after (string-append lx-reset "; ip link set lx0 up") (list "ip" "link" "set" "dev" "lx0" "down") lx-links)
    (lx-case-after lx-reset (list "ip" "link" "set" "lx0" "mtu" "1400" "qlen" "50") lx-links)
    (lx-case-after lx-reset (list "ip" "link" "set" "lx0" "mtu" "0x400") lx-links)
    (lx-case-after lx-reset (list "ip" "link" "set" "lx0" "arp" "off" "multicast" "off" "promisc" "on") lx-links)
    (lx-case-after lx-reset (list "ip" "link" "set" "lx0" "address" "02:00:00:00:00:07") lx-links)
    (lx-case-after lx-reset (list "ip" "l" "s" "lx0" "addr" "2:0:0:0:0:a" "up") lx-links)
    (lx-case-after lx-reset (list "ip" "link" "set" "lx0" "name" "lx9") lx-links)
    (lx-case-after lx-reset (list "ip" "link" "set" "lx0" "name" "lx0" "up") lx-links)
    (lx-case-after lx-reset (list "ip" "link" "set" "lx0" "master" "lxr") lx-links)
    (lx-case-after (string-append lx-reset "; ip link set lx0 master lxr") (list "ip" "link" "set" "lx0" "nomaster") lx-links)
    (lx-case-after lx-reset (list "ip" "link" "set" "lx0" "netns" "1") lx-links)
    (lx-case-after lx-reset (list "iplink" "set" "lx0" "up") lx-links)
    (lx-case-after lx-reset (list "ip" "link" "set" "d") lx-links))
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
same
same
same
```

### what set refuses

```cu
(do (lx-case lx-reset (list "ip" "link" "set"))
    (lx-case lx-reset (list "ip" "link" "set" "lx0" "bogus"))
    (lx-case lx-reset (list "ip" "link" "set" "lx0" "mtu"))
    (lx-case lx-reset (list "ip" "link" "set" "lx0" "mtu" "x"))
    (lx-case lx-reset (list "ip" "link" "set" "lx0" "mtu" "1400" "mtu" "1300"))
    (lx-case lx-reset (list "ip" "link" "set" "lx0" "qlen" "-1"))
    (lx-case lx-reset (list "ip" "link" "set" "lx0" "arp" "maybe"))
    (lx-case lx-reset (list "ip" "link" "set" "lx0" "promisc" "yes"))
    (lx-case lx-reset (list "ip" "link" "set" "lx0" "address" "02:zz"))
    (lx-case lx-reset (list "ip" "link" "set" "lx0" "address" "02:00:00"))
    (lx-case lx-reset (list "ip" "link" "set" "lx0" "address" "1.2.3.4"))
    (lx-case lx-reset (list "ip" "link" "set" "lx0" "address" "1.2.3.x"))
    (lx-case lx-reset (list "ip" "link" "set" "lx0" "mtu" "10"))
    (lx-case lx-reset (list "ip" "link" "set" "lx0" "master" "nosuch0"))
    (lx-case lx-reset (list "ip" "link" "set" "nosuch0" "up"))
    (lx-case lx-reset (list "ip" "link" "set" "lx0" "netns" "x")))
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
same
same
same
same
same
```

### add and delete: a dummy, a vlan with its options, a vrf, and their names

```cu
(do (lx-case-after lx-reset (list "ip" "link" "add" "lxv" "type" "dummy") lx-made)
    (lx-case-after lx-reset (list "ip" "link" "add" "name" "lxv" "address" "02:00:00:00:00:09" "type" "dummy") lx-made)
    (lx-case-after lx-reset (list "ip" "link" "add" "link" "lx0" "name" "lx0.7" "type" "vlan" "id" "7") lx-made)
    (lx-case-after lx-reset (list "ip" "link" "add" "link" "lx0" "lx0.7" "type" "vlan" "id" "7" "protocol" "802.1AD" "reorder_hdr" "off" "gvrp" "on") (string-append lx-made "; head -1 /proc/net/vlan/lx0.7"))
    ; a second vlan of one id and protocol on a link is refused, of the other protocol made
    (lx-case-after (string-append lx-reset "; ip link add link lx0 name lx0.8 type vlan id 7 protocol 802.1ad") (list "ip" "link" "add" "link" "lx0" "lx0.7" "type" "vlan" "id" "7" "protocol" "802.1ad") lx-made)
    (lx-case-after (string-append lx-reset "; ip link add link lx0 name lx0.8 type vlan id 7 protocol 802.1ad") (list "ip" "link" "add" "link" "lx0" "lx0.7" "type" "vlan" "id" "7" "protocol" "802.1q") lx-made)
    (lx-case-after lx-reset (list "ip" "link" "add" "lxv" "type" "vrf" "table" "20") lx-made)
    (lx-case-after (string-append lx-reset "; ip link add lxv type dummy") (list "ip" "link" "delete" "lxv") lx-made)
    (lx-case-after (string-append lx-reset "; ip link add lxv type dummy") (list "ip" "link" "del" "dev" "lxv") lx-made)
    (lx-case-after (string-append lx-reset "; ip link add lxv type dummy") (list "ip" "link" "add" "lxv" "type" "dummy") lx-made))
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

### what add and delete refuse

```cu
(do (lx-case lx-reset (list "ip" "link" "add" "lx1" "type" "vlan" "id" "5"))
    (lx-case lx-reset (list "ip" "link" "add" "link" "lx0" "name" "lx0.7" "type" "vlan" "id" "x"))
    (lx-case lx-reset (list "ip" "link" "add" "link" "lx0" "name" "lx0.7" "type" "vlan" "protocol" "FOO"))
    (lx-case lx-reset (list "ip" "link" "add" "link" "lx0" "name" "lx0.7" "type" "vlan" "bogus" "1"))
    (lx-case lx-reset (list "ip" "link" "add" "link" "lx0" "name" "lx0.7" "type" "vlan" "reorder_hdr" "maybe"))
    (lx-case lx-reset (list "ip" "link" "add" "link" "lx0" "name" "aaaaaaaaaaaaaaaaaa" "type" "vlan" "id" "3"))
    (lx-case lx-reset (list "ip" "link" "add" "link" "nosuch0" "name" "lx0.7" "type" "vlan" "id" "3"))
    (lx-case lx-reset (list "ip" "link" "add" "lxv" "address" "02:zz" "type" "dummy"))
    (lx-case lx-reset (list "ip" "link" "add" "lxv" "type" "vrf" "tablex" "5"))
    (lx-case lx-reset (list "ip" "link" "add" "lxv" "type" "nosuchkind"))
    (lx-case lx-reset (list "ip" "link" "add" "dev" "lxv" "dev" "lxw" "type" "dummy"))
    (lx-case lx-reset (list "ip" "link" "delete"))
    (lx-case lx-reset (list "ip" "link" "delete" "nosuch0")))
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
same
same
```

### the interfaces taken away

```cu
(do (lx-sh (string-append lx-reset "; ip link del lx0; ip link del lxr; ip link set eth0 up; true")) (display "gone"))
```
---
    gone
