# @weight 2

busybox's traceroute and traceroute6 (networking/traceroute.c), run as root
over namespaces iproute2 builds: the container, a router trr and a host trt,
10.1.0.0/24 and fd01::/64 between the first two, 10.2.0.0/24 and fd02::/64
between the last.  The router has unreachable, prohibit and blackhole routes
to 10.9.1-3.0/24 and fd09:1-3::/32; the container itself unreachable and
prohibit routes to 192.0.2.0/24 and 198.51.100.0/24.  Each case runs the
bundle's applet and busybox's on the same words and compares what they write
and their status, each probe's time written as T.

The router's IPv4 unreachables are rate-limited by its route error tokens,
a second within the second dropped, so each case that draws them first rests
four seconds and the setup draws the first.

## the comparison

### each applet against busybox's, the times set aside

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (def lx-times "sed -E 's/  [0-9]+[.][0-9]{3} ms/  T ms/g'")
    (def lx-x (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (def lx-o (file-open-write "/tmp/lx-xo")) (def lx-e (file-open-write "/tmp/lx-xe"))
          (sys-dup2 lx-o 1) (sys-dup2 lx-e 2)
          (def lx-st (cu-run argv ""))
          (sys-dup2 9 1) (sys-dup2 8 2) (file-close lx-o) (file-close lx-e)
          (lx-sh (string-append lx-times " /tmp/lx-xo > /tmp/lx-xn"))
          (%str-concat (list (lx-read "/tmp/lx-xn") "stderr:\n" (lx-read "/tmp/lx-xe") "status " (cu-int->str lx-st) "\n")))))
    (def lx-bb (fn (_ argv)
      (do (lx-sh (%str-concat (list "/bin/busybox " (Str8 join " " (map lx-q argv)) " > /tmp/lx-bo 2> /tmp/lx-bx; echo $? > /tmp/lx-bs; sed '/^BusyBox v/{N;d;}' /tmp/lx-bx > /tmp/lx-be; " lx-times " /tmp/lx-bo > /tmp/lx-bn")))
          (%str-concat (list (lx-read "/tmp/lx-bn") "stderr:\n" (lx-read "/tmp/lx-be") "status " (lx-read "/tmp/lx-bs"))))))
    (def lx-case (fn (_ argv)
      (do (def lx-a (lx-x argv)) (def lx-b (lx-bb argv))
          (display (if (string=? lx-a lx-b) "same\n" (%str-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    ; a case drawing the router's IPv4 unreachables, each run after a rest
    (def lx-rested (fn (_ argv)
      (do (def lx-a (do (lx-sh "sleep 4") (lx-x argv))) (def lx-b (do (lx-sh "sleep 4") (lx-bb argv)))
          (display (if (string=? lx-a lx-b) "same\n" (%str-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    (lx-sh (Str8 join "\n" (list
            "ip2 netns add trr; ip2 netns add trt"
            "ip2 link add trh0 type veth peer name trr0 netns trr"
            "ip2 -n trr link add trr1 type veth peer name trt0 netns trt"
            "ip2 addr add 10.1.0.1/24 dev trh0; ip2 -6 addr add fd01::1/64 dev trh0 nodad; ip2 link set trh0 up"
            "ip2 -n trr addr add 10.1.0.2/24 dev trr0; ip2 -n trr -6 addr add fd01::2/64 dev trr0 nodad; ip2 -n trr link set trr0 up"
            "ip2 -n trr addr add 10.2.0.1/24 dev trr1; ip2 -n trr -6 addr add fd02::1/64 dev trr1 nodad; ip2 -n trr link set trr1 up"
            "ip2 -n trr link set lo up"
            "ip2 -n trt addr add 10.2.0.2/24 dev trt0; ip2 -n trt -6 addr add fd02::2/64 dev trt0 nodad; ip2 -n trt link set trt0 up; ip2 -n trt link set lo up"
            "ip2 netns exec trr sysctl -qw net.ipv4.ip_forward=1 net.ipv6.conf.all.forwarding=1"
            "ip2 netns exec trr sysctl -qw net.ipv4.icmp_ratelimit=0 net.ipv6.icmp.ratelimit=0"
            "ip2 netns exec trt sysctl -qw net.ipv4.icmp_ratelimit=0 net.ipv6.icmp.ratelimit=0"
            "sysctl -qw net.ipv4.icmp_ratelimit=0 net.ipv6.icmp.ratelimit=0"
            "ip2 -n trt route add default via 10.2.0.1; ip2 -n trt -6 route add default via fd02::1"
            "ip2 route add 10.2.0.0/24 via 10.1.0.2; ip2 -6 route add fd02::/64 via fd01::2"
            "ip2 route add 10.9.0.0/16 via 10.1.0.2; ip2 -6 route add fd09::/16 via fd01::2"
            "ip2 -n trr route add unreachable 10.9.1.0/24; ip2 -n trr route add prohibit 10.9.2.0/24; ip2 -n trr route add blackhole 10.9.3.0/24"
            "ip2 -n trr -6 route add unreachable fd09:1::/32; ip2 -n trr -6 route add prohibit fd09:2::/32; ip2 -n trr -6 route add blackhole fd09:3::/32"
            "ip2 route add unreachable 192.0.2.0/24; ip2 route add prohibit 198.51.100.0/24"
            "printf '10.1.0.2 tr-near\\n10.2.0.2 tr-far\\nfd01::2 tr-near6\\nfd02::2 tr-far6\\n' >> /etc/hosts"
            "busybox traceroute -q 1 -w 1 -m 1 -n 10.9.1.1 > /dev/null 2>&1")))
    (display "made"))
```
---
    made

## the hops

### two hops, by number and by name; UDP and echo requests

```cu
(do (lx-case (list "traceroute" "-n" "10.2.0.2"))
    (lx-case (list "traceroute" "10.2.0.2"))
    (lx-case (list "traceroute" "-I" "-n" "10.2.0.2"))
    (lx-case (list "traceroute" "-I" "10.2.0.2")))
```
---
```output
same
same
same
same
```

### -v: the reply's length and the address it came to

```cu
(do (lx-case (list "traceroute" "-v" "-n" "10.2.0.2"))
    (lx-case (list "traceroute" "-v" "10.2.0.2")))
```
---
```output
same
same
```

### -f, -m, -q, a source, an interface, a length, -l doing nothing

```cu
(do (lx-case (list "traceroute" "-f" "2" "-n" "10.2.0.2"))
    (lx-case (list "traceroute" "-m" "1" "-q" "1" "-n" "10.2.0.2"))
    (lx-case (list "traceroute" "-s" "10.1.0.1" "-n" "10.2.0.2"))
    (lx-case (list "traceroute" "-i" "trh0" "-n" "10.2.0.2"))
    (lx-case (list "traceroute" "-n" "-t" "16" "-p" "40000" "-z" "5" "-F" "10.2.0.2" "100"))
    (lx-case (list "traceroute" "-l" "-n" "-q" "1" "10.2.0.2")))
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

### an interface that is not there is said, and the trace runs on

```cu
(lx-case (list "traceroute" "-i" "nope" "-n" "-q" "1" "10.2.0.2"))
```
---
```output
same
```

## the ends

### host and prohibited unreachables; a blackhole's stars to -m

```cu
(do (lx-rested (list "traceroute" "-n" "-w" "1" "10.9.1.1"))
    (lx-rested (list "traceroute" "-n" "-q" "1" "10.9.2.1"))
    (lx-rested (list "traceroute" "-I" "-n" "-w" "1" "-q" "2" "10.9.1.1"))
    (lx-case (list "traceroute" "-n" "-q" "1" "-w" "1" "-m" "3" "10.9.3.1")))
```
---
```output
same
same
same
same
```

### the connect refused: no route, prohibited, and -r off the link

```cu
(do (lx-case (list "traceroute" "-n" "192.0.2.1"))
    (lx-case (list "traceroute" "-n" "198.51.100.1"))
    (lx-case (list "traceroute" "-r" "-n" "10.2.0.2"))
    (lx-case (list "traceroute" "-t" "300" "-n" "10.2.0.2")))
```
---
```output
same
same
same
same
```

## IPv6

### two hops, by number and by name, -v; -6 and traceroute6 alike

```cu
(do (lx-case (list "traceroute6" "-n" "fd02::2"))
    (lx-case (list "traceroute6" "fd02::2"))
    (lx-case (list "traceroute6" "-v" "-n" "fd02::2"))
    (lx-case (list "traceroute" "-6" "-n" "-q" "1" "fd02::2"))
    (lx-case (list "traceroute" "-n" "-q" "1" "::1")))
```
---
```output
same
same
same
same
same
```

### no route and prohibited; echo requests, whose time-exceeded quotes are not UDP's and go unheard

```cu
(do (lx-case (list "traceroute6" "-n" "-q" "1" "fd09:1::1"))
    (lx-case (list "traceroute6" "-n" "-q" "1" "fd09:2::1"))
    (lx-case (list "traceroute6" "-I" "-n" "-q" "1" "-w" "1" "fd02::2")))
```
---
```output
same
same
same
```

### an IPv4 address is no IPv6 one

```cu
(do (lx-case (list "traceroute6" "127.0.0.1"))
    (lx-case (list "traceroute" "-6" "127.0.0.1")))
```
---
```output
same
same
```
