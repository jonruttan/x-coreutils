# @weight 2
# @timeout-scale 10

busybox's dhcprelay (networking/udhcp/dhcprelay.c), run as root.  Three
namespaces: drr, which this file's process enters and where each relay
runs; drs, the server's; and drc, the clients'.  Veth pairs join dr0,
10.12.0.2/24, to drs0, 10.12.0.1/24; dr1, 10.13.0.1/24, to drc1,
10.13.0.50/24; and dr2, with no address, to drc2.  Each case runs the
bundle's dhcprelay and then busybox-extra's on the same words.  A client's
packets are sent raw from drc, as a client with no address sends them; the
server's go out through a UDP socket on port 67 in drs.  What reaches the
server's socket and the clients' -- the sender, the bytes -- what the
relay wrote and whether it still runs are compared.

## the comparison

### the relay against busybox's

```cu
(do (def lr-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (ud-logging! "spec" 0 #f #f)
    (lr-sh (Str8 join "\n" (list
      "ip2 netns add drr; ip2 netns add drs; ip2 netns add drc"
      "ip2 link add dr0 netns drr address 02:00:00:00:0e:01 type veth peer name drs0 netns drs address 02:00:00:00:0e:02"
      "ip2 link add dr1 netns drr address 02:00:00:00:0e:11 type veth peer name drc1 netns drc address 02:00:00:00:0e:12"
      "ip2 link add dr2 netns drr address 02:00:00:00:0e:21 type veth peer name drc2 netns drc address 02:00:00:00:0e:22"
      "ip2 -n drr addr add 10.12.0.2/24 dev dr0; ip2 -n drs addr add 10.12.0.1/24 dev drs0"
      "ip2 -n drr addr add 10.13.0.1/24 dev dr1; ip2 -n drc addr add 10.13.0.50/24 dev drc1"
      "for l in dr0 dr1 dr2 lo; do ip2 -n drr link set $l up; done"
      "ip2 -n drs link set drs0 up; ip2 -n drs link set lo up"
      "for l in drc1 drc2 lo; do ip2 -n drc link set $l up; done")))
    (def lr-ns (fn (_ name) (in-call (cu-ptr-call (cu-libc-sym "open") (string-append "/var/run/netns/" name) 0))))
    (def lr-nss (list (lr-ns "drr") (lr-ns "drs") (lr-ns "drc")))
    (def lr-enter (fn (_ i) (= (in-call (cu-ptr-call (cu-libc-sym "setns") (cu-nth i lr-nss) 1073741824)) 0)))
    ; a UDP socket on PORT, broadcasts let in, bound to DEV, in namespace I
    (def lr-udp (fn (_ i dev port)
      (do (lr-enter i)
          (def s (in-call (cu-ptr-call (cu-libc-sym "socket") 2 2 17)))
          (pn-setopt s pn-sol-socket 2 1)
          (pn-setopt s pn-sol-socket 6 1)
          (def name (inet-zeros 16))
          (cu-ptr-call (cu-libc-sym "memcpy") (cu-str->ptr name) dev (byte-len dev))
          (cu-ptr-call (cu-libc-sym "setsockopt") s pn-sol-socket 25 (cu-str->ptr name) 16)
          (cu-ptr-call (cu-libc-sym "bind") s (cu-str->ptr (ud-sin 0 port)) 16)
          s)))
    (def lr-srv (lr-udp 1 "drs0" 67))
    (def lr-c1 (lr-udp 2 "drc1" 68))
    (def lr-c2 (lr-udp 2 "drc2" 68))
    (def lr-ifs (list (cu-ptr-call (cu-libc-sym "if_nametoindex") "drc1")
                      (cu-ptr-call (cu-libc-sym "if_nametoindex") "drc2")))
    (def lr-in (lr-enter 0))
    (def lr-ip (fn (_ s) (ud-str2nip s)))
    (def lr-pkt (fn (_ type xid)
      (let ((p (ud-packet type)))
        (do (ud-be32! p ud-xid xid) (ud-put! p ud-chaddr (list 2 0 0 0 14 18)) p))))
    ; a client's packet, sent raw from SRC on drc1 or drc2
    (def lr-client (fn (_ which p src)
      (do (lr-enter 2)
          (ud-send-raw p (lr-ip src) 68 4294967295 67 (list 255 255 255 255 255 255) (cu-nth (- which 1) lr-ifs))
          (lr-enter 0))))
    ; the server's packet, its first 300 bytes, to the relay's port 67
    (def lr-server (fn (_ p)
      (cu-ptr-call (cu-libc-sym "sendto") lr-srv (cu-str->ptr p) 300 0 (cu-str->ptr (ud-sin (lr-ip "10.12.0.2") 67)) 16)))
    (def lr-buf (inet-zeros 1024))
    (def lr-flush (fn (_ s)
      (let go () (when (>= (in-call (cu-ptr-call (cu-libc-sym "recv") s (cu-str->ptr lr-buf) 1024 64)) 0) (go)))))
    ; what reaches S within a second, its sender and its bytes
    (def lr-recv (fn (_ label s)
      (if (null? (Sys poll (list (pair s (list (lit in)))) 1000)) (string-append label " nothing\n")
        (let ((from (inet-zeros 16)) (len (inet-zeros 4)))
          (do (inet-set! len 0 16 4)
              (def n (in-call (cu-ptr-call (cu-libc-sym "recvfrom") s (cu-str->ptr lr-buf) 1024 0
                                (cu-str->ptr from) (cu-str->ptr len))))
              (%str-concat (list label " from " (ud-dotted (ud-be32 from 4)) ":" (cu-int->str (pn-be16 (cu-str->ptr from) 2))
                                 ", " (cu-int->str n) " bytes, giaddr " (ud-dotted (ud-be32 lr-buf ud-giaddr)) "\n"
                                 (Str8 join " " (map ud-hex2 (ud-bytes lr-buf 0 n))) "\n")))))))
    (def lr-relay (fn (_ side args)
      (do (def pid (sys-fork))
          (when (= pid 0)
            (guard (e (sys-exit 99))
              (let ((ee (file-open-write "/tmp/dr-err")))
                (do (sys-dup2 ee 1) (sys-dup2 ee 2)
                    (if (string=? side "ours")
                      (sys-exit (cu-run (pair "dhcprelay" args) ""))
                      (do (sys-exec "/usr/local/bin/busybox-extra" (pair "dhcprelay" args)) (sys-exit 98)))))))
          pid)))
    ; with no STEPS the relay's run ends of itself; else it is up when its
    ; SOCKETS hold port 67, the steps are taken, and SIGTERM ends it
    (def lr-side (fn (_ side args sockets steps)
      (do (lr-sh "rm -f /tmp/dr-err")
          (map lr-flush (list lr-srv lr-c1 lr-c2))
          (Heap collect)
          (def pid (lr-relay side args))
          (if (null? steps)
            (let ((st (sys-wait pid)))
              (%str-concat (list "stderr:\n" (file-read-all "/tmp/dr-err") "status " (cu-int->str st) "\n")))
            (do (lr-sh (%str-concat (list "i=0; until [ $(grep -c ':0043 ' /proc/net/udp) -ge " (cu-int->str sockets)
                                            " ] || [ $i -ge 100 ]; do sleep 0.1; i=$((i+1)); done")))
                (def out (%str-concat (map (fn (_ s) (let ((r (s))) (do (Heap collect) r))) steps)))
                (def alive (= (in-call (cu-ptr-call (cu-libc-sym "kill") pid 0)) 0))
                (sys-kill pid 15)
                (sys-wait pid)
                (%str-concat (list out "relay " (if alive "running" "gone") "\nstderr:\n" (file-read-all "/tmp/dr-err"))))))))
    (def lr-case (fn (_ args sockets steps)
      (let ((a (lr-side "ours" args sockets steps)) (b (lr-side "bb" args sockets steps)))
        (display (if (string=? a b) "same\n" (%str-concat (list "ours:\n" a "busybox:\n" b)))))))
    (display (if lr-in "made" "no namespace")))
```
---
    made

## relaying

### to the broadcast address, the replies back by xid

A client on dr1 is answered at the broadcast address, its xid then
forgotten; dr2, given as an alias, has no address, so its requests carry
the server interface's and a giaddr already set is written over.  A
client that has an address is answered at it.  DECLINE, RELEASE and
INFORM go to the server; an OFFER from a client, a packet with no message
type or with an op that is neither, a REQUEST from the server, a reply
with an xid no client sent, and one with bad magic go nowhere.

```cu
(lr-case (list "dr1,dr2:7" "dr0") 3
  (list (fn (_) (do (lr-client 1 (lr-pkt ud-discover 17) "0.0.0.0") (lr-recv "server" lr-srv)))
        (fn (_) (do (lr-server (lr-pkt ud-offer 17)) (lr-recv "client 1" lr-c1)))
        (fn (_) (do (lr-server (lr-pkt ud-offer 17)) (lr-recv "client 1" lr-c1)))
        (fn (_) (do (lr-client 2 (let ((p (lr-pkt ud-request 34))) (do (ud-be32! p ud-giaddr (lr-ip "1.2.3.4")) p)) "0.0.0.0")
                    (lr-recv "server" lr-srv)))
        (fn (_) (do (lr-server (lr-pkt ud-ack 34)) (lr-recv "client 2" lr-c2)))
        (fn (_) (do (lr-client 1 (lr-pkt ud-request 51) "10.13.0.50") (lr-recv "server" lr-srv)))
        (fn (_) (do (lr-server (lr-pkt ud-ack 51)) (lr-recv "client 1" lr-c1)))
        (fn (_) (do (lr-client 1 (lr-pkt ud-decline 68) "0.0.0.0") (lr-recv "server" lr-srv)))
        (fn (_) (do (lr-server (lr-pkt ud-request 68)) (lr-recv "client 1" lr-c1)))
        (fn (_) (do (lr-server (lr-pkt ud-nak 68)) (lr-recv "client 1" lr-c1)))
        (fn (_) (do (lr-client 1 (lr-pkt ud-release 85) "10.13.0.50") (lr-recv "server" lr-srv)))
        (fn (_) (do (lr-client 1 (lr-pkt ud-inform 102) "10.13.0.50") (lr-recv "server" lr-srv)))
        (fn (_) (do (lr-client 1 (lr-pkt ud-offer 119) "0.0.0.0") (lr-recv "server" lr-srv)))
        (fn (_) (do (lr-client 1 (let ((p (lr-pkt ud-discover 136))) (do (ud-set! p ud-options 255) p)) "0.0.0.0")
                    (lr-recv "server" lr-srv)))
        (fn (_) (do (lr-client 1 (let ((p (lr-pkt ud-discover 153))) (do (ud-set! p ud-op 3) p)) "0.0.0.0")
                    (lr-recv "server" lr-srv)))
        (fn (_) (do (lr-server (lr-pkt ud-ack 999)) (lr-recv "client 1" lr-c1)))
        (fn (_) (do (lr-client 1 (lr-pkt ud-discover 170) "0.0.0.0") (lr-recv "server" lr-srv)))
        (fn (_) (do (lr-server (let ((p (lr-pkt ud-offer 170))) (do (ud-be32! p 236 0) p))) (lr-recv "client 1" lr-c1)))))
```
---
```output
same
```

### to SERVER_IP

```cu
(lr-case (list "dr1" "dr0" "10.12.0.1") 2
  (list (fn (_) (do (lr-client 1 (lr-pkt ud-discover 187) "0.0.0.0") (lr-recv "server" lr-srv)))
        (fn (_) (do (lr-server (lr-pkt ud-offer 187)) (lr-recv "client 1" lr-c1)))))
```
---
```output
same
```

## the refusals

### an interface not there, a server address that is not one, a server interface with no address

```cu
(do (lr-case (list "nosuch" "dr0") 0 ())
    (lr-case (list "dr1" "dr0" "10.0.x.1") 0 ())
    (lr-case (list "dr1" "dr2") 0 ()))
```
---
```output
same
same
same
```
