# @weight 2

busybox's ip neigh, ip rule and ip tunnel, and the ipneigh, iprule and
iptunnel applets (networking/libiproute: ipneigh.c, iprule.c and
iptunnel.c), run as root against a dummy interface, lx0, with eth0 down.
Neighbour entries are made fresh before each side, so their ages read 0;
rules and tunnels are made in PRE and judged by what each side writes, its
status, and what `ip rule` or `ip tunnel` says after.

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
          (string-concat (list (lx-read "/tmp/lx-xo") "stderr:\n" (lx-read "/tmp/lx-xe") "status " (cu-int->str lx-st) "\n")))))
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

### the interface

```cu
(do (def lx-base "ip link set eth0 down; ip link del lx0 2>/dev/null; ip link add lx0 address 02:00:00:00:00:01 type dummy; sysctl -qw net.ipv6.conf.lx0.accept_dad=0; ip link set lx0 up; ip addr add 10.66.0.1/24 dev lx0")
    (def lx-neigh (string-append lx-base "; arp -i lx0 -s 10.66.0.5 02:00:00:00:00:05; arp -i lx0 -s 10.66.0.6 02:00:00:00:00:06 temp; arp -i lx0 -s 10.66.0.7 02:00:00:00:00:07 pub; true"))
    (def lx-rules "for p in 500 501 502 503 504 505 506 507 508; do ip rule del pref $p 2>/dev/null; done; true")
    (def lx-rmore (string-append lx-rules "; ip rule add from 10.66.0.0/24 lookup 100 pref 500; ip rule add to 10.77.0.0/16 tos 0x10 fwmark 0x5/0xff pref 501 lookup main; ip rule add iif lx0 prohibit pref 502; ip rule add from 10.66.9.0/24 realms 3/4 pref 503 table 200; ip rule add fwmark 0/0xff pref 508 lookup main"))
    (def lx-tunnels "for t in lxt1 lxt2 lxt3; do ip tunnel del $t 2>/dev/null; done; true")
    (def lx-tmore (string-append lx-tunnels "; ip tunnel add lxt1 mode sit remote 10.1.1.1 local 10.66.0.1 ttl 64; ip tunnel add lxt2 mode gre remote 10.1.1.2 key 7 csum seq; ip tunnel add lxt3 mode ipip remote 10.1.1.3 dev lx0 tos inherit nopmtudisc"))
    (lx-sh lx-base)
    (display "made"))
```
---
    made

## neighbours

### the neighbours compared in either order

The kernel dumps a neighbour table in its hash order, which differs
between two tables made the same way, so each side's lines are sorted
before they are compared.

```cu
(do (def lx-sorted (fn (_ s) (Str8 join "\n" (List sort (fn (_ a b) (Str8 <? a b)) (Str8 split "\n" s)))))
    (def lx-case-sorted (fn (_ pre argv post)
      (do (lx-sh pre) (def lx-a (lx-x argv)) (lx-sh (string-concat (list "{ " post "; } > /tmp/lx-post 2>&1"))) (def lx-pa (lx-read "/tmp/lx-post"))
          (lx-sh pre) (def lx-b (lx-bb argv)) (lx-sh (string-concat (list "{ " post "; } > /tmp/lx-post 2>&1"))) (def lx-pb (lx-read "/tmp/lx-post"))
          (display (if (if (string=? (lx-sorted lx-a) (lx-sorted lx-b)) (string=? (lx-sorted lx-pa) (lx-sorted lx-pb)) #f) "same\n"
                     (string-concat (list "ours:\n" lx-a lx-pa "busybox:\n" lx-b lx-pb)))))))
    (display "made"))
```
---
    made

### shown: each state, a device, a prefix, a family

```cu
(do (lx-case-sorted lx-neigh (list "ip" "neigh") ":")
    (lx-case-sorted lx-neigh (list "ip" "n" "show") ":")
    (lx-case-sorted lx-neigh (list "ip" "neigh" "show" "dev" "lx0") ":")
    (lx-case-sorted lx-neigh (list "ip" "neigh" "show" "nud" "all") ":")
    (lx-case-sorted lx-neigh (list "ip" "neigh" "show" "nud" "permanent") ":")
    (lx-case-sorted lx-neigh (list "ip" "neigh" "show" "nud" "noarp") ":")
    (lx-case-sorted lx-neigh (list "ip" "neigh" "show" "nud" "none") ":")
    (lx-case-sorted lx-neigh (list "ip" "neigh" "show" "nud" "reach" "nud" "perm") ":")
    (lx-case-sorted lx-neigh (list "ip" "neigh" "show" "to" "10.66.0.6") ":")
    (lx-case-sorted lx-neigh (list "ip" "neigh" "show" "10.66.0.0/30") ":")
    (lx-case-sorted lx-neigh (list "ip" "-6" "neigh") ":")
    (lx-case-sorted lx-neigh (list "ip" "-6" "neigh" "show" "nud" "all") ":")
    (lx-case-sorted lx-neigh (list "ip" "-4" "neigh" "show" "nud" "all") ":")
    (lx-case-sorted lx-neigh (list "ip" "-o" "neigh") ":")
    (lx-case-sorted lx-neigh (list "ipneigh") ":")
    (lx-case-sorted lx-neigh (list "ipneigh" "show" "dev" "lo") ":"))
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

### flushed, and what neigh refuses

```cu
(do (lx-case-sorted lx-neigh (list "ip" "neigh" "flush" "dev" "lx0") "ip neigh show nud all")
    (lx-case-sorted lx-neigh (list "ip" "neigh" "flush" "dev" "lx0" "nud" "all") "ip neigh show nud all")
    (lx-case-sorted lx-neigh (list "ip" "neigh" "flush" "dev" "lx0" "nud" "permanent") "ip neigh show nud all")
    (lx-case-sorted lx-neigh (list "ip" "neigh" "flush" "to" "10.66.0.6" "nud" "all") "ip neigh show nud all")
    (lx-case-sorted lx-neigh (list "ip" "-6" "neigh" "flush" "dev" "lx0" "nud" "all") "ip -6 neigh show nud all")
    (lx-case-sorted lx-neigh (list "ip" "neigh" "flush") ":")
    (lx-case-sorted lx-neigh (list "ip" "neigh" "show" "nud" "bogus") ":")
    (lx-case-sorted lx-neigh (list "ip" "neigh" "show" "nud" "n") ":")
    (lx-case-sorted lx-neigh (list "ip" "neigh" "show" "dev" "nosuch0") ":")
    (lx-case-sorted lx-neigh (list "ip" "neigh" "show" "dev") ":")
    (lx-case-sorted lx-neigh (list "ip" "neigh" "zap") ":")
    (lx-case-sorted lx-neigh (list "ip" "-0" "neigh" "show" "10.0.0.0/8") ":"))
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
```

## rules

### listed, added and deleted

```cu
(do (lx-case lx-rmore (list "ip" "rule"))
    (lx-case lx-rmore (list "ip" "ru" "list"))
    (lx-case lx-rmore (list "ip" "-6" "rule"))
    (lx-case lx-rmore (list "iprule" "show"))
    (lx-case lx-rmore (list "ip" "rule" "show" "x"))
    (lx-case-after lx-rules (list "ip" "rule" "add" "from" "10.66.0.0/24" "lookup" "100" "pref" "500") "ip rule")
    (lx-case-after lx-rules (list "ip" "rule" "add" "to" "10.77.0.0/16" "tos" "10" "pref" "501") "ip rule")
    (lx-case-after lx-rules (list "ip" "rule" "add" "fwmark" "5" "pref" "502" "table" "main") "ip rule")
    (lx-case-after lx-rules (list "ip" "rule" "add" "fwmark" "0x5/0xff" "pref" "503" "table" "1000") "ip rule")
    (lx-case-after lx-rules (list "ip" "rule" "add" "fwmark" "0/0xff" "pref" "508" "table" "main") "ip rule")
    (lx-case-after lx-rules (list "ip" "rule" "add" "dev" "lx0" "unreachable" "pref" "504") "ip rule")
    (lx-case-after lx-rules (list "ip" "rule" "add" "iif" "lx0" "type" "blackhole" "pref" "505") "ip rule")
    (lx-case-after lx-rules (list "ip" "rule" "add" "from" "10.66.9.0/24" "realms" "3/4" "pref" "506") "ip rule")
    (lx-case-after lx-rules (list "ip" "rule" "add" "from" "10.66.9.0/24" "suppress_prefixlength" "0" "pref" "507") "ip rule")
    (lx-case-after lx-rmore (list "ip" "rule" "del" "pref" "500") "ip rule")
    (lx-case-after lx-rmore (list "ip" "rule" "delete" "from" "10.66.0.0/24" "lookup" "100") "ip rule")
    (lx-case-after lx-rmore (list "iprule" "add" "from" "10.66.0.0/24" "lookup" "100" "pref" "500") "ip rule"))
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

### what a rule refuses

```cu
(do (lx-case lx-rules (list "ip" "rule" "add" "bogus"))
    (lx-case lx-rules (list "ip" "rule" "add" "t" "1"))
    (lx-case lx-rules (list "ip" "rule" "add" "from" "10.66.0.0/99"))
    (lx-case lx-rules (list "ip" "rule" "add" "pref" "x"))
    (lx-case lx-rules (list "ip" "rule" "add" "tos" "bogus"))
    (lx-case lx-rules (list "ip" "rule" "add" "lookup" "bogus"))
    (lx-case lx-rules (list "ip" "rule" "add" "realms" "a/b"))
    (lx-case lx-rules (list "ip" "rule" "add" "fwmark" "5/x"))
    (lx-case lx-rules (list "ip" "rule" "add" "nat" "foo"))
    (lx-case lx-rules (list "ip" "rule" "add" "type" "bogus"))
    (lx-case lx-rules (list "ip" "rule" "add" "help"))
    (lx-case lx-rules (list "ip" "rule" "del" "pref" "999"))
    (lx-case lx-rules (list "ip" "rule" "zap")))
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

## tunnels

### shown: all of them, one by name, one by mode

/proc/net/dev, which the listing walks, gives the tunnels in the hash order
of their indexes, which differ between two sets made alike, so the lines are
compared sorted.

```cu
(do (lx-case-sorted lx-tmore (list "ip" "tunnel") ":")
    (lx-case-sorted lx-tmore (list "ip" "tunnel" "show") ":")
    (lx-case-sorted lx-tmore (list "ip" "tun" "list" "lxt2") ":")
    (lx-case-sorted lx-tmore (list "ip" "tunnel" "show" "mode" "sit") ":")
    (lx-case-sorted lx-tmore (list "ip" "tunnel" "show" "name" "lxt1") ":")
    (lx-case-sorted lx-tmore (list "ip" "tunnel" "show" "sit0") ":")
    (lx-case-sorted lx-tmore (list "ip" "tunnel" "show" "remote" "10.1.1.2") ":")
    (lx-case-sorted lx-tmore (list "ip" "-o" "tunnel" "show" "lxt2") ":")
    (lx-case-sorted lx-tmore (list "iptunnel") ":")
    (lx-case-sorted lx-tmore (list "ip" "tunnel" "show" "mode" "gre" "nosuch0") ":"))
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

### added, changed and deleted

```cu
(do (lx-case-after lx-tunnels (list "ip" "tunnel" "add" "lxt1" "mode" "sit" "remote" "10.1.1.1" "local" "10.66.0.1") "ip tunnel show")
    (lx-case-after lx-tunnels (list "ip" "tunnel" "add" "lxt2" "mode" "gre" "remote" "10.1.1.2" "ikey" "5" "okey" "6" "icsum" "oseq") "ip tunnel show")
    (lx-case-after lx-tunnels (list "ip" "tunnel" "add" "lxt2" "mode" "gre" "remote" "10.1.1.2" "key" "1.2.3.4") "ip tunnel show")
    (lx-case-after lx-tunnels (list "ip" "tunnel" "add" "lxt3" "mode" "ipip" "remote" "10.1.1.3" "ttl" "32" "tos" "0x10" "dev" "lx0") "ip tunnel show")
    (lx-case-after lx-tunnels (list "ip" "tunnel" "add" "name" "lxt1" "mode" "sit" "remote" "any" "local" "any" "ttl" "inherit") "ip tunnel show")
    (lx-case-after lx-tunnels (list "ip" "tunnel" "add" "lxt2" "mode" "gre" "remote" "239.1.1.1" "local" "10.66.0.1") "ip tunnel show")
    (lx-case-after lx-tmore (list "ip" "tunnel" "change" "lxt1" "mode" "sit" "remote" "10.1.1.9") "ip tunnel show")
    (lx-case-after lx-tmore (list "ip" "tunnel" "change" "lxt2" "ttl" "20") "ip tunnel show")
    (lx-case-after lx-tmore (list "ip" "tunnel" "del" "lxt1") "ip tunnel show")
    (lx-case-after lx-tmore (list "ip" "tunnel" "delete" "lxt2" "mode" "gre") "ip tunnel show")
    (lx-case-after lx-tunnels (list "iptunnel" "add" "lxt1" "mode" "sit" "remote" "10.1.1.1") "ip tunnel show"))
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

### what a tunnel refuses

```cu
(do (lx-case lx-tunnels (list "ip" "tunnel" "add" "lxt1"))
    (lx-case lx-tunnels (list "ip" "tunnel" "add" "lxt1" "mode" "bogus"))
    (lx-case lx-tunnels (list "ip" "tunnel" "add" "lxt1" "mode" "sit" "mode" "gre"))
    (lx-case lx-tunnels (list "ip" "tunnel" "add" "lxt1" "mode" "sit" "key" "5"))
    (lx-case lx-tunnels (list "ip" "tunnel" "add" "lxt1" "mode" "sit" "remote" "foo"))
    (lx-case lx-tunnels (list "ip" "tunnel" "add" "lxt1" "mode" "sit" "ttl" "300"))
    (lx-case lx-tunnels (list "ip" "tunnel" "add" "lxt1" "mode" "sit" "ttl" "20" "nopmtudisc"))
    (lx-case lx-tunnels (list "ip" "tunnel" "add" "lxt1" "mode" "sit" "tos" "bogus"))
    (lx-case lx-tunnels (list "ip" "tunnel" "add" "lxt1" "mode" "gre" "remote" "239.1.1.1"))
    (lx-case lx-tunnels (list "ip" "tunnel" "add" "lxt1" "lxt2" "mode" "sit"))
    (lx-case lx-tunnels (list "ip" "tunnel" "add" "lxt1" "mode" "sit" "dev" "nosuch0"))
    (lx-case lx-tunnels (list "ip" "tunnel" "change" "nosuch0" "mode" "sit"))
    (lx-case lx-tunnels (list "ip" "tunnel" "del" "nosuch0"))
    (lx-case lx-tunnels (list "ip" "tunnel" "show" "nosuch0" "mode" "sit"))
    (lx-case lx-tmore (list "ip" "tunnel" "add" "lxt1" "mode" "sit"))
    (lx-case lx-tunnels (list "ip" "tunnel" "zap")))
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

### taken away

```cu
(do (lx-sh (string-append lx-tunnels "; " lx-rules "; ip link del lx0; ip link set eth0 up; true")) (display "gone"))
```
---
    gone
