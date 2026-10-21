# @weight 2

busybox's ip route and iproute (networking/libiproute/iproute.c), run as
root against routes made for it on a dummy interface, lx0, with eth0 down
so no route outside the cases changes.  Each case runs the bundle's
applet and busybox's on the same words, PRE through the shell before each
to set the routes as the case needs them, and compares what they write,
their status, and where it says so what `ip route` lists after.

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

### the routes

```cu
(do (def lx-reset "ip link del lx0 2>/dev/null; ip link add lx0 address 02:00:00:00:00:01 type dummy; sysctl -qw net.ipv6.conf.lx0.accept_dad=0; ip link set lx0 up; ip addr add 10.66.0.1/24 dev lx0; ip addr add fd00:66::1/64 dev lx0; for t in blackhole unreachable prohibit; do ip route del $t 10.78.0.0/16 2>/dev/null; done; ip route flush table 100 2>/dev/null; ip route flush table 1000 2>/dev/null; for i in 1 2 3 4 5 6 7 8 9 10; do ip -6 route show table all | grep -q ff00:: && break; sleep 0.2; done; true")
    (def lx-routes "ip route show table all")
    (def lx-more (string-append lx-reset "; ip route add 10.77.0.0/16 via 10.66.0.254; ip route add 10.79.0.0/16 dev lx0 metric 7 proto static; ip route add default via 10.66.0.254 table 100; ip route add blackhole 10.78.0.0/16; ip route add fd00:77::/64 via fd00:66::fe"))
    (lx-sh "ip link set eth0 down")
    (lx-sh lx-more)
    (display "made"))
```
---
    made

## showing

### the tables, each family, and the verbs' spellings

```cu
(do (lx-case lx-more (list "ip" "route"))
    (lx-case lx-more (list "ip" "r"))
    (lx-case lx-more (list "ip" "ro" "show"))
    (lx-case lx-more (list "ip" "route" "list" "table" "all"))
    (lx-case lx-more (list "ip" "route" "show" "table" "main"))
    (lx-case lx-more (list "ip" "route" "show" "table" "local"))
    (lx-case lx-more (list "ip" "route" "show" "table" "100"))
    (lx-case lx-more (list "ip" "route" "show" "table" "cache"))
    (lx-case lx-more (list "ip" "route" "show" "cache"))
    (lx-case lx-more (list "ip" "-6" "route"))
    (lx-case lx-more (list "ip" "-6" "route" "show" "table" "all"))
    (lx-case lx-more (list "ip" "-4" "route" "show" "table" "all"))
    (lx-case lx-more (list "ip" "-o" "route"))
    (lx-case lx-more (list "iproute"))
    (lx-case lx-more (list "iproute" "list")))
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
```

### the selectors: dev, to and from, scope, proto, via, iif

```cu
(do (lx-case lx-more (list "ip" "route" "show" "dev" "lx0"))
    (lx-case lx-more (list "ip" "route" "show" "oif" "lx0"))
    (lx-case lx-more (list "ip" "route" "show" "10.66.0.0/24"))
    (lx-case lx-more (list "ip" "route" "show" "to" "root" "10.0.0.0/8"))
    (lx-case lx-more (list "ip" "route" "show" "to" "match" "10.77.5.5"))
    (lx-case lx-more (list "ip" "route" "show" "to" "exact" "10.77.0.0/16"))
    (lx-case lx-more (list "ip" "route" "show" "match" "10.79.1.1"))
    (lx-case lx-more (list "ip" "route" "show" "root" "10.77.0.0/16"))
    (lx-case lx-more (list "ip" "route" "show" "default"))
    (lx-case lx-more (list "ip" "route" "show" "table" "all" "default"))
    (lx-case lx-more (list "ip" "route" "show" "from" "0.0.0.0/0"))
    (lx-case lx-more (list "ip" "route" "show" "scope" "link"))
    (lx-case lx-more (list "ip" "route" "show" "table" "all" "scope" "host"))
    (lx-case lx-more (list "ip" "route" "show" "scope" "all"))
    (lx-case lx-more (list "ip" "route" "show" "proto" "static"))
    (lx-case lx-more (list "ip" "route" "show" "proto" "all"))
    (lx-case lx-more (list "ip" "route" "show" "via" "10.66.0.254"))
    (lx-case lx-more (list "ip" "route" "show" "via" "10.66.0.0/24"))
    (lx-case lx-more (list "ip" "route" "show" "iif" "lx0"))
    (lx-case lx-more (list "ip" "-6" "route" "show" "fd00::/16")))
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
same
```

### rt_protos and rt_tables names

```cu
(do (lx-sh "mkdir -p /etc/iproute2; printf '100\\tlxtab\\n' > /etc/iproute2/rt_tables; printf '42 lxproto\\n' > /etc/iproute2/rt_protos")
    (lx-case lx-more (list "ip" "route" "show" "table" "all"))
    (lx-case lx-more (list "ip" "route" "show" "table" "lxtab"))
    (lx-case-after lx-more (list "ip" "route" "add" "10.80.0.0/16" "dev" "lx0" "proto" "lxproto" "table" "lxtab") "ip route show table all; ip route show proto lxproto table all")
    (lx-sh "rm -rf /etc/iproute2") (display ""))
```
---
```output
same
same
same
```

### what the listing refuses

```cu
(do (lx-case lx-more (list "ip" "route" "show" "scope" "bogus"))
    (lx-case lx-more (list "ip" "route" "show" "proto" "bogus"))
    (lx-case lx-more (list "ip" "route" "show" "table" "bogus"))
    (lx-case lx-more (list "ip" "route" "show" "dev" "nosuch0"))
    (lx-case lx-more (list "ip" "route" "show" "dev"))
    (lx-case lx-more (list "ip" "route" "show" "to" "10.0.0.0/99"))
    (lx-case lx-more (list "ip" "-0" "route" "show" "10.0.0.0/8"))
    (lx-case lx-more (list "ip" "route" "zap"))
    (lx-case lx-more (list "ip" "route" "c")))
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

## changing

### added: each kind of route and each of its words

```cu
(do (lx-case-after lx-reset (list "ip" "route" "add" "10.77.0.0/16" "via" "10.66.0.254") lx-routes)
    (lx-case-after lx-reset (list "ip" "r" "a" "10.77.0.0/16" "dev" "lx0") lx-routes)
    (lx-case-after lx-reset (list "ip" "route" "add" "default" "via" "10.66.0.254" "table" "100") lx-routes)
    (lx-case-after lx-reset (list "ip" "route" "add" "10.77.0.0/16" "dev" "lx0" "metric" "5" "proto" "static") lx-routes)
    (lx-case-after lx-reset (list "ip" "route" "add" "blackhole" "10.78.0.0/16") lx-routes)
    (lx-case-after lx-reset (list "ip" "route" "add" "unreachable" "10.78.0.0/16") lx-routes)
    (lx-case-after lx-reset (list "ip" "route" "add" "prohibit" "10.78.0.0/16") lx-routes)
    (lx-case-after lx-reset (list "ip" "route" "add" "local" "10.66.9.9" "dev" "lx0") lx-routes)
    (lx-case-after lx-reset (list "ip" "route" "add" "to" "unicast" "10.77.0.0/16" "dev" "lx0") lx-routes)
    (lx-case-after lx-reset (list "ip" "route" "add" "10.77.0.0/16" "via" "10.66.0.254" "mtu" "lock" "1400" "advmss" "1300") "ip route show table all; cat /proc/net/route")
    (lx-case-after lx-reset (list "ip" "route" "add" "10.77.0.0/16" "dev" "lx0" "src" "10.66.0.1" "scope" "link") lx-routes)
    (lx-case-after lx-reset (list "ip" "route" "add" "10.77.0.0/16" "dev" "lx0" "table" "1000") lx-routes)
    (lx-case-after lx-reset (list "ip" "route" "add" "10.77.0.0/16" "via" "10.99.0.1" "dev" "lx0" "onlink") lx-routes)
    (lx-case-after lx-reset (list "ip" "route" "add" "10.77.1.1" "dev" "lx0" "scope" "host") lx-routes)
    (lx-case-after lx-reset (list "ip" "route" "add" "fd00:77::/64" "via" "fd00:66::fe") "ip -6 route show table all")
    (lx-case-after lx-reset (list "ip" "-6" "route" "add" "fd00:77::/64" "dev" "lx0" "metric" "9") "ip -6 route show table all")
    (lx-case-after lx-reset (list "iproute" "add" "10.77.0.0/16" "dev" "lx0") lx-routes))
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

### append, prepend, replace, change, test and delete

```cu
(do (lx-case-after lx-more (list "ip" "route" "append" "10.77.0.0/16" "dev" "lx0" "metric" "3") lx-routes)
    (lx-case-after lx-more (list "ip" "route" "prepend" "10.77.0.0/16" "via" "10.66.0.253") lx-routes)
    (lx-case-after lx-more (list "ip" "route" "replace" "10.77.0.0/16" "via" "10.66.0.253") lx-routes)
    (lx-case-after lx-reset (list "ip" "route" "replace" "10.77.0.0/16" "dev" "lx0") lx-routes)
    (lx-case-after lx-more (list "ip" "route" "change" "10.77.0.0/16" "via" "10.66.0.252") lx-routes)
    (lx-case-after lx-more (list "ip" "route" "chg" "10.88.0.0/16" "via" "10.66.0.252") lx-routes)
    (lx-case-after lx-more (list "ip" "route" "test" "10.77.0.0/16" "via" "10.66.0.254") lx-routes)
    (lx-case-after lx-more (list "ip" "route" "delete" "10.77.0.0/16") lx-routes)
    (lx-case-after lx-more (list "ip" "route" "del" "10.79.0.0/16" "dev" "lx0" "metric" "7") lx-routes)
    (lx-case-after lx-more (list "ip" "route" "del" "blackhole" "10.78.0.0/16") lx-routes)
    (lx-case-after lx-more (list "ip" "route" "del" "default" "table" "100") lx-routes)
    (lx-case-after lx-more (list "ip" "route" "d" "10.99.0.0/16") lx-routes)
    (lx-case-after lx-more (list "ip" "route" "add" "10.77.0.0/16" "via" "10.66.0.254") lx-routes))
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

### what a route refuses

```cu
(do (lx-case lx-reset (list "ip" "route" "add"))
    (lx-case lx-reset (list "ip" "route" "add" "10.77.0.0/16" "10.78.0.0/16" "dev" "lx0"))
    (lx-case lx-reset (list "ip" "route" "add" "10.77.0.0/99" "dev" "lx0"))
    (lx-case lx-reset (list "ip" "route" "add" "10.77.0.0/16" "via" "foo"))
    (lx-case lx-reset (list "ip" "route" "add" "10.77.0.0/16" "dev" "lx0" "scope" "bogus"))
    (lx-case lx-reset (list "ip" "route" "add" "10.77.0.0/16" "dev" "lx0" "proto" "bogus"))
    (lx-case lx-reset (list "ip" "route" "add" "10.77.0.0/16" "dev" "lx0" "table" "bogus"))
    (lx-case lx-reset (list "ip" "route" "add" "10.77.0.0/16" "dev" "lx0" "mtu" "x"))
    (lx-case lx-reset (list "ip" "route" "add" "10.77.0.0/16" "dev" "lx0" "metric" "-1"))
    (lx-case lx-reset (list "ip" "route" "add" "10.77.0.0/16" "dev" "nosuch0"))
    (lx-case lx-reset (list "ip" "route" "add" "10.77.0.0/16" "via" "10.99.0.1"))
    (lx-case lx-reset (list "ip" "route" "add" "blackhole"))
    (lx-case lx-reset (list "ip" "route" "add" "10.77.0.0/16" "dev"))
    (lx-case lx-reset (list "ip" "route" "add" "10.77.0.0/16" "via" "fd00::1" "dev" "lx0"))
    (lx-case lx-reset (list "ip" "route" "del" "10.99.0.0/16")))
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
```

### flushed: by device, table, prefix and family, and the cache

```cu
(do (lx-case-after lx-more (list "ip" "route" "flush" "dev" "lx0") lx-routes)
    (lx-case-after lx-more (list "ip" "route" "flush" "table" "100") lx-routes)
    (lx-case-after lx-more (list "ip" "route" "flush" "root" "10.77.0.0/16") lx-routes)
    (lx-case-after lx-more (list "ip" "route" "flush" "proto" "static") lx-routes)
    (lx-case-after lx-more (list "ip" "-6" "route" "flush" "dev" "lx0") "ip -6 route show table all")
    (lx-case-after lx-more (list "ip" "route" "flush" "cache") lx-routes)
    (lx-case-after lx-more (list "ip" "-6" "route" "flush" "cache") lx-routes)
    (lx-case lx-more (list "ip" "route" "flush"))
    (lx-case lx-more (list "ip" "route" "flush" "dev" "nosuch0")))
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

### get: the route the kernel takes, from a source, through a device, connected

```cu
(do (lx-case lx-more (list "ip" "route" "get" "10.66.0.9"))
    (lx-case lx-more (list "ip" "route" "get" "10.77.1.1"))
    (lx-case lx-more (list "ip" "route" "get" "to" "10.79.1.1"))
    (lx-case lx-more (list "ip" "route" "get" "10.78.1.1"))
    (lx-case lx-more (list "ip" "route" "get" "8.8.8.8"))
    (lx-case lx-more (list "ip" "route" "get" "10.66.0.9" "from" "10.66.0.1"))
    (lx-case lx-more (list "ip" "route" "get" "10.66.0.9" "oif" "lx0"))
    (lx-case lx-more (list "ip" "route" "get" "10.66.0.9" "connected"))
    (lx-case lx-more (list "ip" "route" "get" "10.77.1.1" "connected"))
    (lx-case lx-more (list "ip" "route" "get" "10.66.0.9" "notify"))
    (lx-case lx-more (list "ip" "route" "get" "fd00:66::9"))
    (lx-case lx-more (list "ip" "route" "get" "127.0.0.1"))
    (lx-case lx-more (list "ip" "route" "get"))
    (lx-case lx-more (list "ip" "route" "get" "default"))
    (lx-case lx-more (list "ip" "route" "get" "10.66.0.9" "iif" "nosuch0")))
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
```

### the routes taken away

```cu
(do (lx-sh "ip link del lx0; for t in blackhole unreachable prohibit; do ip route del $t 10.78.0.0/16 2>/dev/null; done; ip route flush table 100 2>/dev/null; ip route flush table 1000 2>/dev/null; ip link set eth0 up; true") (display "gone"))
```
---
    gone
