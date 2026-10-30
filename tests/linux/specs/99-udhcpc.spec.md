# @weight 2
# @timeout-scale 10

busybox's udhcpc (networking/udhcp/dhcpc.c), run as root.  A veth pair
joins two namespaces: uc0, 10.11.0.1/24, in uc, where the server runs,
and uc1 in ucc, which this file's process enters and where each client
runs.  Each case runs the bundle's udhcpc and then busybox-extra's, each
time against a fresh server: busybox-extra's udhcpd, the bundle's, or a
scripted one that answers each request with the packets the case gives
it.  The script the client runs logs each event with the variables it
was given, and configures uc1 as a real script would, so a renew goes out
through the kernel.  A packet socket on uc1 takes every IPv4 and ARP
frame either side sends; a frame's IP id and sums, the transaction ID and
the seconds are written as x.  The frames, what the client wrote, its
status and the script's log are compared.

## the comparison

### the client against busybox's, over three servers

```cu
(do (def lc-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (ud-logging! "spec" 0 #f #f)
    (lc-sh (Str8 join "\n" (list
      "ip2 netns add uc; ip2 netns add ucc"
      "ip2 link add uc0 netns uc address 02:00:00:00:0d:01 type veth peer name uc1 netns ucc address 02:00:00:00:0d:02"
      "ip2 -n uc addr add 10.11.0.1/24 dev uc0"
      "ip2 -n uc link set uc0 up; ip2 -n uc link set lo up; ip2 -n ucc link set uc1 up; ip2 -n ucc link set lo up"
      "cat > /tmp/uc-script.sh <<'EOF'"
      "#!/bin/sh"
      "{ echo \"event $1\"; env | grep '^[a-z][a-z0-9_]*=' | grep -v '^container=' | sort; } >> /tmp/uc-script.log"
      "case $1 in"
      "bound|renew) ip2 addr flush dev uc1; ip2 addr add \"$ip/${mask:-24}\" dev uc1 ;;"
      "deconfig) ip2 addr flush dev uc1 ;;"
      "esac"
      "EOF"
      "chmod +x /tmp/uc-script.sh")))
    (def lc-ns (fn (_ name) (in-call (cu-ptr-call (cu-libc-sym "open") (string-append "/var/run/netns/" name) 0))))
    (def lc-srv-ns (lc-ns "uc"))
    (def lc-in (= (in-call (cu-ptr-call (cu-libc-sym "setns") (lc-ns "ucc") 1073741824)) 0))
    (def lc-if1 (cu-ptr-call (cu-libc-sym "if_nametoindex") "uc1"))
    (def lc-cap (in-call (cu-ptr-call (cu-libc-sym "socket") 17 3 768)))
    (def lc-sll (inet-zeros 20))
    (inet-set! lc-sll 0 17 2) (inet-set! lc-sll 2 0 1) (inet-set! lc-sll 3 3 1)
    (inet-set! lc-sll 4 lc-if1 4)
    (def lc-bound (= (in-call (cu-ptr-call (cu-libc-sym "bind") lc-cap (cu-str->ptr lc-sll) 20)) 0))
    (def lc-buf (inet-zeros 2048))
    (def lc-b (fn (_ k) (& (byte-at lc-buf k) 255)))
    ; an IPv4 frame's id, sums, transaction ID and seconds are written as x
    (def lc-masked (list 18 19 24 25 40 41 46 47 48 49 50 51))
    (def lc-frame (fn (_ n)
      (def udp? (if (= (lc-b 12) 8) (if (= (lc-b 13) 0) (= (lc-b 23) 17) #f) #f))
      (%str-concat (list "frame "
        (Str8 join " " (map (fn (_ k) (if (if udp? (List find (fn (_ m) (= m k)) lc-masked) #f) "x" (ud-hex2 (lc-b k))))
                            (List range 0 n)))
        "\n"))))
    (def lc-drain (fn (_)
      (let go ((acc ""))
        (let ((r (in-call (cu-ptr-call (cu-libc-sym "recv") lc-cap (cu-str->ptr lc-buf) 2048 64))))
          (match ((< r 0) acc)
                 ((if (= (lc-b 12) 8) (if (= (lc-b 13) 0) #t (= (lc-b 13) 6)) #f)
                  (go (let ((a (string-append acc (lc-frame r)))) (do (Heap collect) a))))
                 (#t (go acc)))))))
    (def lc-ip (fn (_ s) (ud-str2nip s)))
    (def lc-o (fn (_ code bytes) (pair code (pair (length bytes) bytes))))
    (def lc-s (fn (_ s) (ud-str-bytes s)))
    ; a reply of TYPE to REQ offering YIADDR, with OPTIONS
    (def lc-reply (fn (_ req type yiaddr options)
      (do (def p (ud-packet type))
          (ud-put! p ud-xid (ud-bytes req ud-xid 4))
          (ud-put! p ud-chaddr (ud-bytes req ud-chaddr 16))
          (ud-be32! p ud-yiaddr (lc-ip yiaddr))
          (map (fn (_ o) (ud-add-option! p o)) options)
          p)))
    ; the scripted server: each request read on uc0 is answered by the next
    ; of ANSWERS, a function of the request giving the packets to send
    (def lc-scripted (fn (_ answers)
      (do (cu-ptr-call (cu-libc-sym "setns") lc-srv-ns 1073741824)
          (def if0 (cu-ptr-call (cu-libc-sym "if_nametoindex") "uc0"))
          (def udp (in-call (cu-ptr-call (cu-libc-sym "socket") 2 2 17)))
          (cu-ptr-call (cu-libc-sym "bind") udp (cu-str->ptr (ud-sin 0 67)) 16)
          (def s (in-call (cu-ptr-call (cu-libc-sym "socket") 17 2 8)))
          (def sll (inet-zeros 20))
          (inet-set! sll 0 17 2) (inet-set! sll 2 8 1) (inet-set! sll 4 if0 4)
          (cu-ptr-call (cu-libc-sym "bind") s (cu-str->ptr sll) 20)
          (def b (inet-zeros 2048))
          (let go ((as answers))
            (unless (null? as)
              (let ((n (in-call (cu-ptr-call (cu-libc-sym "recv") s (cu-str->ptr b) 2048 0))))
                (if (if (>= n 28) (if (= (& (byte-at b 9) 255) 17) (= (pn-be16 (cu-str->ptr b) 22) 67) #f) #f)
                  (let ((req (ud-zeros 628)))
                    (do (cu-ptr-call (cu-libc-sym "memcpy") (cu-str->ptr req) (+ (td-ptr->int (cu-str->ptr b)) 28) (- n 28))
                        (map (fn (_ p) (ud-send-raw p (lc-ip "10.11.0.1") 67 4294967295 68 (list 255 255 255 255 255 255) if0))
                             ((first as) req))
                        (go (rest as))))
                  (go as)))))
          (let forever () (do (sys-usleep 1000000) (forever))))))
    (def lc-conf (fn (_ extra)
      (%str-concat (list "interface uc0\nstart 10.11.0.20\nend 10.11.0.30\nlease_file /tmp/uc-leases\n"
                           "pidfile /tmp/uc-srv.pid\n"
                           "option subnet 255.255.255.0\noption router 10.11.0.1\noption dns 10.11.0.1 10.11.0.2\n"
                           "option domain example.org\noption lease 1000\noption broadcast 10.11.0.255\n"
                           "option search example.org other.org\noption staticroutes 10.0.0.0/8 10.11.0.1\n"
                           "option timezone -3600\noption mtu 1400\n" extra))))
    ; SERVER: (bb EXTRA), (ours EXTRA) or (scripted ANSWERS)
    (def lc-server (fn (_ server)
      (do (def pid (sys-fork))
          (when (= pid 0)
            (guard (e (sys-exit 99))
              (let ((ee (file-open-write "/tmp/uc-srv-err")))
                (do (sys-dup2 ee 1) (sys-dup2 ee 2)
                    (match ((eq? (first server) (lit scripted)) (do (lc-scripted (first (rest server))) (sys-exit 0)))
                           (#t (do (file-write-all "/tmp/uc.conf" (lc-conf (first (rest server))))
                                   (cu-ptr-call (cu-libc-sym "setns") lc-srv-ns 1073741824)
                                   (if (eq? (first server) (lit ours))
                                     (sys-exit (cu-run (list "udhcpd" "-f" "-a" "300" "/tmp/uc.conf") ""))
                                     (do (sys-exec "/usr/local/bin/busybox-extra" (list "udhcpd" "-f" "-a" "300" "/tmp/uc.conf"))
                                         (sys-exit 98))))))))))
          ; a udhcpd is up when it holds port 67 in its namespace; ours takes
          ; longer than busybox's to get there
          (lc-sh (if (eq? (first server) (lit scripted)) "sleep 1"
                   "i=0; until ip2 netns exec uc grep -q ':0043 ' /proc/net/udp || [ $i -ge 100 ]; do sleep 0.1; i=$((i+1)); done"))
          pid)))
    (def lc-client (fn (_ side args)
      (do (def pid (sys-fork))
          (when (= pid 0)
            (guard (e (sys-exit 99))
              (let ((ee (file-open-write "/tmp/uc-err")))
                (do (sys-dup2 ee 1) (sys-dup2 ee 2)
                    (if (string=? side "ours")
                      (sys-exit (cu-run (pair "udhcpc" args) ""))
                      (do (sys-exec "/usr/local/bin/busybox-extra" (pair "udhcpc" args)) (sys-exit 98)))))))
          pid)))
    (def lc-wait (fn (_ secs) (fn (_ pid) (lc-sh (string-append "sleep " secs)))))
    (def lc-kill (fn (_ sig) (fn (_ pid) (do (sys-kill pid sig) (lc-sh "sleep 1")))))
    ; a client gone to the background: its pidfile names it; SIGTERM ends it
    (def lc-background (fn (_)
      (if (not (do (lc-sh "sleep 0.5") (file-exists? "/tmp/uc.pid"))) ""
        ; one try in the background, ended by its leasefail, before the kill
        (let ((n (do (lc-sh "i=0; while [ $(grep -c '^event leasefail' /tmp/uc-script.log) -lt 2 ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done")
                     (ud-strtou (first (ud-strtok (file-read-all "/tmp/uc.pid") 0 "\n")) 10))))
          (do (def alive (= (in-call (cu-ptr-call (cu-libc-sym "kill") (first n) 0)) 0))
              (sys-kill (first n) 15)
              (lc-sh "sleep 1")
              (%str-concat (list "background " (if alive "running" "gone") ", pidfile "
                                 (if (file-exists? "/tmp/uc.pid") "left" "removed") "\n")))))))
    (def lc-side (fn (_ side server args steps)
      (do (lc-sh "rm -f /tmp/uc-leases /tmp/uc-err /tmp/uc.pid; : > /tmp/uc-script.log; ip2 -n ucc addr flush dev uc1; ip2 -n uc neigh flush dev uc0; ip2 -n ucc neigh flush dev uc1")
          (lc-drain)
          (Heap collect)
          (def srv (lc-server server))
          (def pid (lc-client side (append (list "-i" "uc1" "-s" "/tmp/uc-script.sh" "-T" "1") args)))
          (map (fn (_ s) (s pid)) steps)
          (def st (sys-wait pid))
          (def bg (lc-background))
          (sys-kill srv 9)
          (sys-wait srv)
          (lc-sh "sed 's/^udhcpc: started, v.*/udhcpc: started/; s/xid [0-9a-f]* (our is [0-9a-f]*)/xid x (our is x)/; /waiting [0-9]* seconds/d' /tmp/uc-err > /tmp/uc-err2")
          (%str-concat (list (lc-drain) "stderr:\n" (file-read-all "/tmp/uc-err2") "status " (cu-int->str st) "\n"
                               bg "script:\n" (file-read-all "/tmp/uc-script.log"))))))
    (def lc-case (fn (_ servers args steps)
      (map (fn (_ server)
             (let ((a (lc-side "ours" server args steps)) (b (lc-side "bb" server args steps)))
               (display (if (string=? a b) "same\n" (%str-concat (list "ours:\n" a "busybox:\n" b))))))
           servers)
      ()))
    (def lc-real (list (list (lit bb) "") (list (lit ours) "")))
    (display (if lc-in (if lc-bound "made" "no capture") "no namespace")))
```
---
    made

## a lease

### DISCOVER, OFFER, REQUEST, ACK, and the script's bound

The DISCOVER asks for -r's address and broadcast replies; -x's client ID
stands in for the MAC; -O adds to the codes asked for.

```cu
(lc-case lc-real
  (list "-f" "-q" "-B" "-r" "10.11.0.25" "-V" "vend" "-O" "42" "-O" "staticroutes"
        "-x" "hostname:box" "-x" "0x3d:0100beef" "-F" "box.example")
  ())
```
---
```output
same
same
```

### SIGUSR1 renews through the kernel, SIGUSR2 releases, -R at SIGTERM

```cu
(lc-case lc-real
  (list "-f" "-R" "-o" "-C" "-O" "1" "-O" "3" "-V" "")
  (list (lc-wait "3") (lc-kill 10) (lc-wait "1") (lc-kill 12) (lc-kill 10) (lc-wait "2") (lc-kill 15)))
```
---
```output
same
same
```

### an offered address someone holds: the ARP probe, DECLINE, the next

```cu
(do (lc-sh "ip2 -n uc addr add 10.11.0.20/24 dev uc0")
    (lc-case lc-real (list "-f" "-q" "-a500" "-A" "1" "-V" "v") ())
    (lc-sh "ip2 -n uc addr del 10.11.0.20/24 dev uc0")
    ())
```
---
```output
same
same
```

## no lease

### -n ends the run; -b goes to the background

```cu
(do (lc-case (list (list (lit scripted) ())) (list "-f" "-n" "-t" "2" "-V" "v") ())
    (lc-case (list (list (lit scripted) ())) (list "-b" "-t" "1" "-A" "1" "-p" "/tmp/uc.pid" "-V" "v")
      ()))
```
---
```output
same
same
```

## what the client is sent

### packets for others, NAKs, then a lease and its variables

Packets with another's transaction ID or MAC, without a type, and an ACK
before any OFFER are passed over; an OFFER with no server ID is taken as
0.0.0.0's; a NAK from another server is passed over, one from it starts
over.  The ACK carries one option of each type, an option given twice,
a name with a pointer in it, and the file and sname fields lent to
options; the NAK carries them as fields.

```cu
(def lc-ack-options
  (list (lc-o 1 (list 255 255 255 0)) (lc-o 3 (list 10 11 0 1 10 11 0 2 7 7))
        (lc-o 6 (list 1 1 1 1)) (lc-o 6 (list 2 2 2 2))
        (lc-o 12 (lc-s "-box")) (lc-o 15 (lc-s "a!")) (lc-o 40 (lc-s "x y"))
        (lc-o 2 (list 255 255 241 240)) (lc-o 26 (list 5 220)) (lc-o 23 (list 64))
        (lc-o 121 (list 24 10 11 1 10 11 0 1 0 10 11 0 1)) (lc-o 249 (list 33 1 2 3 4))
        (lc-o 119 (append (list 7) (lc-s "example") (list 3) (lc-s "org") (list 0 5) (lc-s "other") (list 192 8)))
        (lc-o 120 (list 1 10 11 0 7 10 11 0 8))
        (lc-o 212 (list 16 48 32 1 13 184 0 0 0 0 0 0 0 0 0 0 0 0 10 11 0 9))
        (lc-o 224 (list 1 2 255)) (lc-o 60 (list 97 98 0 99 100)) (lc-o 56 (lc-s "hello"))
        (lc-o 52 (list 3)) (lc-o 54 (list 10 11 0 1))))
(def lc-weird
  (list
    (fn (_ req)
      (list (let ((p (lc-reply req ud-offer "10.11.0.40" ()))) (do (ud-set! p ud-xid (+ 1 (ud-byte p ud-xid))) p))
            (let ((p (lc-reply req ud-offer "10.11.0.40" ()))) (do (ud-set! p (+ ud-chaddr 5) 9) p))
            (let ((p (lc-reply req ud-offer "10.11.0.40" ()))) (do (ud-set! p ud-options 255) p))
            (lc-reply req ud-ack "10.11.0.40" (list (lc-o 54 (list 10 11 0 1))))
            (lc-reply req ud-offer "10.11.0.40" ())))
    (fn (_ req)
      (list (lc-reply req ud-nak "0.0.0.0" (list (lc-o 54 (list 10 11 0 9))))
            (let ((p (lc-reply req ud-nak "0.0.0.0" ())))
              (do (ud-be32! p ud-siaddr (lc-ip "10.11.0.5")) (ud-be32! p ud-giaddr (lc-ip "10.11.0.6"))
                  (ud-put! p ud-sname (lc-s "srv")) (ud-put! p ud-file (lc-s "/boot/x"))
                  p))))
    (fn (_ req) (list (lc-reply req ud-offer "10.11.0.41" (list (lc-o 54 (list 10 11 0 1))))))
    (fn (_ req)
      (list (let ((p (lc-reply req ud-ack "10.11.0.41" lc-ack-options)))
              (do (ud-put! p ud-file (append (lc-o 66 (lc-s "tftp.example")) (list 255)))
                  (ud-put! p ud-sname (append (lc-o 67 (lc-s "boot.img")) (list 255)))
                  p))))))
(lc-case (list (list (lit scripted) lc-weird)) (list "-f" "-q" "-v" "-V" "v" "-t" "5") ())
```
---
```output
same
```

### no answer to the renew: the rebind, the lease lost, a lease again

```cu
(def lc-offer (fn (_ ip) (fn (_ req) (list (lc-reply req ud-offer ip (list (lc-o 54 (list 10 11 0 1)) (lc-o 51 (list 0 0 0 40))))))))
(def lc-ack (fn (_ ip) (fn (_ req) (list (lc-reply req ud-ack ip (list (lc-o 54 (list 10 11 0 1)) (lc-o 51 (list 0 0 0 40)) (lc-o 1 (list 255 255 255 0))))))))
(def lc-none (fn (_ req) ()))
(lc-case (list (list (lit scripted) (list (lc-offer "10.11.0.42") (lc-ack "10.11.0.42") lc-none lc-none lc-none lc-none
                                         (lc-offer "10.11.0.43") (lc-ack "10.11.0.43"))))
  (list "-f" "-v" "-V" "v")
  (list (lc-wait "2") (lc-kill 10) (lc-wait "7") (lc-kill 15)))
```
---
```output
same
```
