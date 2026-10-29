# @weight 2
# @timeout-scale 6

busybox's udhcpd (networking/udhcp/dhcpd.c), run as root.  A veth pair
joins two namespaces: ud0, 10.9.0.1/24, in ud, where each server runs, and
ud1 in udc, which this file's process enters.  Each case writes
/tmp/ud.conf, starts the bundle's udhcpd -f -v -a 300 on it in a child
that enters ud, sends DHCP packets from ud1 a second apart, then ends the
server with SIGTERM; then the same with busybox-extra's.  A packet socket
on ud1 takes every IPv4 and ARP frame ud0 sends -- the ARP probes, the
replies, a relay's packet -- and the frames, what the server wrote, its
status, its lease file and the notify script's log are compared.  The
lease file names its side, so a case can start a server on what the last
run of that side left; its times are written as tens of seconds.

## the comparison

### the applet against busybox's, the frames, the lease file

```cu
(do (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (ud-logging! "spec" 0 #f #f)
    (lx-sh (Str8 join "\n" (list
      "ip2 netns add ud; ip2 netns add udc"
      "ip2 link add ud0 netns ud address 02:00:00:00:0b:01 type veth peer name ud1 netns udc address 02:00:00:00:0b:02"
      "ip2 -n ud addr add 10.9.0.1/24 dev ud0"
      "ip2 -n ud link set ud0 up; ip2 -n ud link set lo up; ip2 -n udc link set ud1 up; ip2 -n udc link set lo up"
      "printf '#!/bin/sh\\necho \"notify ${1%%.*}\" >> /tmp/ud-notify.log\\n' > /tmp/ud-notify.sh"
      "chmod +x /tmp/ud-notify.sh")))
    (def lx-ns (fn (_ name) (in-call (cu-ptr-call (in-c "open") (string-append "/var/run/netns/" name) 0))))
    (def lx-srv-ns (lx-ns "ud"))
    (def lx-in (= (in-call (cu-ptr-call (in-c "setns") (lx-ns "udc") 1073741824)) 0))
    (def lx-if1 (cu-ptr-call (in-c "if_nametoindex") "ud1"))
    (def lx-cap (in-call (cu-ptr-call (in-c "socket") 17 3 768)))
    (def lx-sll (inet-zeros 20))
    (inet-set! lx-sll 0 17 2) (inet-set! lx-sll 2 0 1) (inet-set! lx-sll 3 3 1)
    (inet-set! lx-sll 4 lx-if1 4)
    (def lx-bound (= (in-call (cu-ptr-call (in-c "bind") lx-cap (cu-str->ptr lx-sll) 20)) 0))
    (def lx-buf (inet-zeros 2048))
    (def lx-b (fn (_ k) (& (byte-at lx-buf k) 255)))
    ; ud0's frames, IPv4 and ARP; an IPv4 frame's id and header sum are
    ; the kernel's own, so they are written as x
    (def lx-frame (fn (_ n)
      (def ip? (if (= (lx-b 12) 8) (= (lx-b 13) 0) #f))
      (string-concat (list "frame "
        (Str8 join " " (map (fn (_ k) (if (if ip? (if (>= k 18) (if (< k 20) #t (if (>= k 24) (< k 26) #f)) #f) #f) "x"
                                       (ud-hex2 (lx-b k))))
                            (List range 0 n)))
        "\n"))))
    (def lx-drain (fn (_)
      (let go ((acc ""))
        (let ((r (in-call (cu-ptr-call (in-c "recv") lx-cap (cu-str->ptr lx-buf) 2048 64))))
          (match ((< r 0) acc)
                 ((if (= (lx-b 6) 2) (= (lx-b 11) 2) #f) (go acc))
                 ((if (= (lx-b 12) 8) (if (= (lx-b 13) 0) #t (= (lx-b 13) 6)) #f)
                  (go (string-append acc (lx-frame r))))
                 (#t (go acc)))))))
    ; a request: TYPE from MAC, XID, the raw OPTIONS, ciaddr, flags, giaddr
    (def lx-pkt (fn (_ type mac xid opts ciaddr flags giaddr)
      (do (def p (ud-packet type))
          (ud-be32! p ud-xid xid)
          (ud-put! p ud-chaddr mac)
          (ud-be32! p ud-ciaddr ciaddr)
          (ud-set! p ud-flags flags)
          (ud-be32! p ud-giaddr giaddr)
          (map (fn (_ o) (ud-add-option! p o)) opts)
          p)))
    (def lx-step (fn (_ p)
      (fn (_) (do (ud-send-raw p 0 68 4294967295 67 (list 255 255 255 255 255 255) lx-if1)
                  (lx-sh "sleep 1")
                  (lx-drain)))))
    (def lx-conf (fn (_ side extra)
      (string-concat (list "interface ud0\nstart 10.9.0.20\nend 10.9.0.30\n"
                           "lease_file /tmp/ud-leases." side "\npidfile /tmp/ud.pid\n"
                           "notify_file /tmp/ud-notify.sh\n" extra))))
    (def lx-start (fn (_ side)
      (do (def pid (sys-fork))
          (when (= pid 0)
            (guard (e (sys-exit 99))
              (let ((ee (file-open-write "/tmp/ud-err")))
                (do (sys-dup2 ee 1) (sys-dup2 ee 2)
                    (cu-ptr-call (in-c "setns") lx-srv-ns 1073741824)
                    (if (string=? side "ours")
                      (sys-exit (cu-run (list "udhcpd" "-f" "-v" "-a" "300" "/tmp/ud.conf") ""))
                      (do (sys-exec "/usr/local/bin/busybox-extra" (list "udhcpd" "-f" "-v" "-a" "300" "/tmp/ud.conf"))
                          (sys-exit 98)))))))
          (lx-sh "sleep 1")
          pid)))
    ; the records: address, MAC, name, the seconds left in tens
    (def lx-leases (fn (_ path)
      (let ((fd (file-open-read path)))
        (if (< fd 0) "none\n"
          (let ((b (ud-zeros 4096)))
            (do (def n (File read fd b 4096))
                (file-close fd)
                (let go ((at 8) (acc ""))
                  (if (> (+ at 36) n) acc
                    (go (+ at 36)
                        (string-concat (list acc (ud-dotted (ud-be32 b (+ at 4))) " "
                          (Str8 join ":" (map ud-hex2 (ud-bytes b (+ at 8) 6))) " '"
                          (list->string (map integer->char
                                             (let cut ((l (ud-bytes b (+ at 14) 20)) (k ()))
                                               (if (if (null? l) #t (= (first l) 0)) (reverse k) (cut (rest l) (pair (first l) k))))))
                          "' ~" (cu-int->str (pn-div (+ (ud-be32 b at) 5) 10)) "\n")))))))))))
    (def lx-side (fn (_ side extra steps fresh)
      (do (when fresh (lx-sh (string-append "rm -f /tmp/ud-leases." side)))
          (lx-sh "rm -f /tmp/ud.pid /tmp/ud-err; : > /tmp/ud-notify.log; ip2 -n ud neigh flush dev ud0; ip2 -n udc neigh flush dev ud1")
          (file-write-all "/tmp/ud.conf" (lx-conf side extra))
          (lx-drain)
          (def pid (lx-start side))
          (def frames (string-concat (map (fn (_ s) (s)) steps)))
          (sys-kill pid 15)
          (def st (sys-wait pid))
          (lx-sh "sed 's/^udhcpd: started, v.*/udhcpd: started/; s/ud-leases[.][a-z]*/ud-leases/g' /tmp/ud-err > /tmp/ud-err2")
          (string-concat (list frames "stderr:\n" (file-read-all "/tmp/ud-err2") "status " (cu-int->str st) "\n"
                               "pidfile " (if (file-exists? "/tmp/ud.pid") "left" "gone") "\n"
                               "leases:\n" (lx-leases (string-append "/tmp/ud-leases." side))
                               "notify:\n" (file-read-all "/tmp/ud-notify.log"))))))
    (def lx-case (fn (_ extra steps fresh)
      (do (def lx-a (lx-side "ours" extra steps fresh)) (def lx-b2 (lx-side "bb" extra steps fresh))
          (display (if (string=? lx-a lx-b2) "same\n" (string-concat (list "ours:\n" lx-a "busybox:\n" lx-b2)))))))
    (def lx-mac (list 2 0 0 0 12 1))
    (def lx-opts "option subnet 255.255.255.0\nopt router 10.9.0.1\noption dns 10.9.0.1 10.9.0.2\noption domain example.org\noption lease 1000\n")
    (display (if lx-in (if lx-bound "made" "no capture") "no namespace")))
```
---
    made

## a lease

### DISCOVER, OFFER, REQUEST, ACK, and the lease written

The first address in the range is probed over ARP and offered; the
client's name goes into the lease, cleaned of what a name cannot hold.

```cu
(lx-case lx-opts
  (list (lx-step (lx-pkt ud-discover lx-mac 305419896 (list (list 12 6 45 98 111 120 33 121)) 0 128 0))
        (lx-step (lx-pkt ud-request lx-mac 305419896
                   (list (list 50 4 10 9 0 20) (list 54 4 10 9 0 1) (list 12 6 45 98 111 120 33 121)) 0 128 0)))
  #t)
```
---
```output
same
```

### the lease read back at the start; its client asks again

```cu
(lx-case lx-opts
  (list (lx-step (lx-pkt ud-discover lx-mac 305419897 () 0 0 0))
        (lx-step (lx-pkt ud-request lx-mac 305419897 () 168362004 0 0)))
  #f)
```
---
```output
same
```

### the address asked for, where it is free; another client's NAKed

```cu
(lx-case lx-opts
  (list (lx-step (lx-pkt ud-discover (list 2 0 0 0 12 2) 7 (list (list 50 4 10 9 0 27)) 0 128 0))
        (lx-step (lx-pkt ud-request (list 2 0 0 0 12 3) 8 (list (list 50 4 10 9 0 27) (list 54 4 10 9 0 1)) 0 128 0))
        (lx-step (lx-pkt ud-request (list 2 0 0 0 12 3) 9 (list (list 50 4 10 9 0 28)) 0 128 0))
        (lx-step (lx-pkt ud-request (list 2 0 0 0 12 3) 10 () 168362012 0 0)))
  #t)
```
---
```output
same
```

## the ways a lease ends

### RELEASE, then DECLINE of another

```cu
(lx-case lx-opts
  (list (lx-step (lx-pkt ud-discover lx-mac 1 () 0 128 0))
        (lx-step (lx-pkt ud-request lx-mac 2 (list (list 50 4 10 9 0 20) (list 54 4 10 9 0 1)) 0 128 0))
        (lx-step (lx-pkt ud-release lx-mac 3 (list (list 54 4 10 9 0 1)) 168362004 0 0))
        (lx-step (lx-pkt ud-discover (list 2 0 0 0 12 4) 4 () 0 128 0))
        (lx-step (lx-pkt ud-decline (list 2 0 0 0 12 4) 5 (list (list 50 4 10 9 0 21) (list 54 4 10 9 0 1)) 0 0 0)))
  #t)
```
---
```output
same
```

## a static lease, a conflict, a relay

### a static lease and its host name; another server's ID ignored

```cu
(lx-case (string-append lx-opts "static_lease 02:00:00:00:0c:05 10.9.0.25 statichost\nstatic_lease 2:0:0:0:c:6 10.9.0.26\n")
  (list (lx-step (lx-pkt ud-discover (list 2 0 0 0 12 5) 11 () 0 128 0))
        (lx-step (lx-pkt ud-request (list 2 0 0 0 12 5) 12 (list (list 50 4 10 9 0 25) (list 54 4 10 9 0 1)) 0 128 0))
        (lx-step (lx-pkt ud-discover (list 2 0 0 0 12 6) 13 (list (list 54 4 10 9 0 99)) 0 128 0)))
  #t)
```
---
```output
same
```

### an address someone holds is reserved for conflict_time, the next offered

```cu
(do (lx-sh "ip2 -n udc addr add 10.9.0.20/24 dev ud1")
    (lx-case (string-append lx-opts "conflict_time 500\n")
      (list (lx-step (lx-pkt ud-discover lx-mac 14 () 0 128 0)))
      #t)
    (lx-sh "ip2 -n udc addr del 10.9.0.20/24 dev ud1")
    ())
```
---
```output
same
```

### through a relay, INFORM unicast to ciaddr

```cu
(do (lx-sh "ip2 -n udc addr add 10.9.0.2/24 dev ud1")
    (lx-case (string-append lx-opts "sname srv\nboot_file /boot/x\nsiaddr 10.9.0.3\n")
      (list (lx-step (lx-pkt ud-discover lx-mac 15 () 0 0 168361986))
            (lx-step (lx-pkt ud-inform (list 2 0 0 0 12 7) 16 () 168362024 0 0)))
      #t)
    (lx-sh "ip2 -n udc addr del 10.9.0.2/24 dev ud1")
    ())
```
---
```output
same
```

## what is refused

### packets that are not requests, no MAC length, no type

```cu
(lx-case lx-opts
  (list (lx-step (let ((p (lx-pkt ud-discover lx-mac 17 () 0 0 0))) (do (ud-set! p ud-op 2) p)))
        (lx-step (let ((p (lx-pkt ud-discover lx-mac 18 () 0 0 0))) (do (ud-set! p ud-hlen 8) p)))
        (lx-step (let ((p (lx-pkt ud-discover lx-mac 19 () 0 0 0))) (do (ud-set! p 242 9) p))))
  #t)
```
---
```output
same
```

### the configuration's refusals, the usage

```cu
(do (lx-case (string-append "start\nmax_leases 12x\noption nosuch 1\n") () #t)
    (lx-case "end 10.9.0.10\n" () #t)
    (lx-case "interface nosuch\n" () #t))
```
---
```output
same
same
same
```
