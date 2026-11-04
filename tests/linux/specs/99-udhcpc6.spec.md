# @weight 2
# @timeout-scale 10

busybox's udhcpc6 (networking/udhcp/d6_dhcpc.c), run as root.  A veth
pair joins two namespaces, duplicate address detection and router
solicitations off in both: u60 in u6, where the server runs, and u61 in
u6c, which this file's process enters and where each client runs.  Each
case runs the bundle's udhcpc6 and then busybox-extra's, each time
against a fresh scripted server that answers each request with the
packets the case gives it, from u60's link-local address to the
request's sender.  The script the client runs logs each event with the
variables it was given, and gives u61 the address leased, so a renew
goes out through the kernel.  A packet socket on u61 takes every DHCPv6
frame either side sends; a frame's flow label, UDP sum, transaction ID,
elapsed time and IAIDs are written as x.  The frames, what the client
wrote, its status and the script's log are compared.

## the comparison

### the client against busybox's, over a scripted server

```cu
(do (def l6-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (ud-logging! "spec" 0 #f #f)
    (l6-sh (Str8 join "\n" (list
      "ip2 netns add u6; ip2 netns add u6c"
      "for n in u6 u6c; do ip2 netns exec $n sh -c 'echo 0 > /proc/sys/net/ipv6/conf/default/accept_dad; echo 0 > /proc/sys/net/ipv6/conf/default/router_solicitations'; done"
      "ip2 link add u60 netns u6 address 02:00:00:00:0e:01 type veth peer name u61 netns u6c address 02:00:00:00:0e:02"
      "ip2 -n u6 link set u60 up; ip2 -n u6 link set lo up; ip2 -n u6c link set u61 up; ip2 -n u6c link set lo up"
      "cat > /tmp/u6-script.sh <<'EOF'"
      "#!/bin/sh"
      "{ echo \"event $1\"; env | grep '^[a-z][a-z0-9_]*=' | grep -v '^container=' | sort; } >> /tmp/u6-script.log"
      "case $1 in"
      "bound|renew) ip2 -6 addr flush dev u61 scope global; [ -z \"$ipv6\" ] || ip2 -6 addr add \"$ipv6/128\" dev u61 nodad ;;"
      "deconfig) ip2 -6 addr flush dev u61 scope global ;;"
      "esac"
      "EOF"
      "chmod +x /tmp/u6-script.sh")))
    (def l6-ns (fn (_ name) (in-call (cu-ptr-call (cu-libc-sym "open") (string-append "/var/run/netns/" name) 0))))
    (def l6-srv-ns (l6-ns "u6"))
    (def l6-in (= (in-call (cu-ptr-call (cu-libc-sym "setns") (l6-ns "u6c") 1073741824)) 0))
    (def l6-if1 (cu-ptr-call (cu-libc-sym "if_nametoindex") "u61"))
    (def l6-cap (in-call (cu-ptr-call (cu-libc-sym "socket") 17 3 768)))
    (def l6-sll (inet-zeros 20))
    (inet-set! l6-sll 0 17 2) (inet-set! l6-sll 2 0 1) (inet-set! l6-sll 3 3 1)
    (inet-set! l6-sll 4 l6-if1 4)
    (def l6-bound (= (in-call (cu-ptr-call (cu-libc-sym "bind") l6-cap (cu-str->ptr l6-sll) 20)) 0))
    (def l6-buf (inet-zeros 2048))
    (def l6-b (fn (_ k) (& (byte-at l6-buf k) 255)))
    (def l6-be16 (fn (_ k) (+ (* (l6-b k) 256) (l6-b (+ k 1)))))
    ; an IPv6 frame of UDP to 546 or 547
    (def l6-dhcp? (fn (_ n)
      (if (>= n 66)
        (if (if (= (l6-b 12) 134) (if (= (l6-b 13) 221) (= (l6-b 20) 17) #f) #f)
          (if (= (l6-be16 56) 546) #t (= (l6-be16 56) 547))
          #f)
        #f)))
    ; the flow label, the UDP sum, the transaction ID, then each option's:
    ; ELAPSED_TIME's data, IA_NA's and IA_PD's IAID
    (def l6-masks (fn (_ n)
      (let go ((i 66) (acc (list 15 16 17 60 61 63 64 65)))
        (if (> (+ i 4) n) acc
          (let ((code (l6-be16 i)) (len (l6-be16 (+ i 2))))
            (go (+ i 4 len)
                (match ((= code 8) (append (List range (+ i 4) (+ i 4 len)) acc))
                       ((if (= code 3) #t (= code 25)) (append (List range (+ i 4) (+ i 8)) acc))
                       (#t acc))))))))
    (def l6-frame (fn (_ n)
      (let ((m (l6-masks n)))
        (%str-concat (list "frame "
          (Str8 join " " (map (fn (_ k) (if (List find (fn (_ x) (= x k)) m) "x" (ud-hex2 (l6-b k)))) (List range 0 n)))
          "\n")))))
    (def l6-drain (fn (_)
      (let go ((acc ""))
        (let ((r (in-call (cu-ptr-call (cu-libc-sym "recv") l6-cap (cu-str->ptr l6-buf) 2048 64))))
          (match ((< r 0) acc)
                 ((l6-dhcp? r) (go (let ((a (string-append acc (l6-frame r)))) (do (Heap collect) a))))
                 (#t (go acc)))))))
    ; the options' bytes
    (def l6-o (fn (_ code data) (append (list (>> code 8) (& code 255) (>> (length data) 8) (& (length data) 255)) data)))
    (def l6-s (fn (_ s) (ud-str-bytes s)))
    (def l6-u32 (fn (_ n) (list (& (>> n 24) 255) (& (>> n 16) 255) (& (>> n 8) 255) (& n 255))))
    (def l6-pton (fn (_ s) (let ((b (inet-zeros 16))) (do (cu-ptr-call (cu-libc-sym "inet_pton") 10 s (cu-str->ptr b)) (ud-bytes b 0 16)))))
    (def l6-names (fn (_ labels) (append (List fold (fn (_ acc l) (append acc (pair (byte-len l) (l6-s l)))) () labels) (list 0))))
    ; the data of the option CODE among the options L, or nil
    (def l6-find (fn (_ l code)
      (let go ((l l))
        (if (< (length l) 4) ()
          (let ((len (+ (* (cu-nth 2 l) 256) (cu-nth 3 l))))
            (if (= (+ (* (first l) 256) (cu-nth 1 l)) code) (List take len (List drop 4 l))
              (go (List drop (+ 4 len) l))))))))
    (def l6-iaid (fn (_ req code) (let ((d (l6-find (List drop 4 req) code))) (if (null? d) (list 0 0 0 0) (List take 4 d)))))
    (def l6-sid (l6-o 2 (list 0 3 0 1 2 0 0 0 14 1)))
    (def l6-na (fn (_ req addr lease)
      (l6-o 3 (append (l6-iaid req 3) (l6-u32 10) (l6-u32 20) (l6-o 5 (append (l6-pton addr) (l6-u32 30) (l6-u32 lease)))))))
    (def l6-pd (fn (_ req pfx plen lease)
      (l6-o 25 (append (l6-iaid req 25) (l6-u32 10) (l6-u32 20) (l6-o 26 (append (l6-u32 30) (l6-u32 lease) (list plen) (l6-pton pfx)))))))
    ; an answer: a packet of TYPE with REQ's transaction ID, OPTIONS a
    ; function of REQ
    (def l6-answer (fn (_ type options) (fn (_ req) (list (append (pair type (List take 3 (rest req))) (List fold append () (options req)))))))
    (def l6-none (fn (_ req) ()))
    (def l6-srv-ll (l6-pton "fe80::ff:fe00:e01"))
    ; P from u60's link-local address to DST at u61's MAC
    (def l6-send (fn (_ fd if0 p dst)
      (do (def size (length p))
          (def b (inet-zeros (+ 48 size)))
          (def sll (inet-zeros 20))
          (inet-set! sll 0 17 2) (ud-be16! sll 2 34525) (inet-set! sll 4 if0 4) (ud-set! sll 11 6)
          (ud-put! sll 12 (list 2 0 0 0 14 2))
          (ud-set! b 0 96) (ud-be16! b 4 (+ 8 size)) (ud-put! b 8 l6-srv-ll) (ud-put! b 24 dst)
          (ud-be16! b 40 547) (ud-be16! b 42 546) (ud-be16! b 44 (+ 8 size)) (ud-put! b 48 p)
          (ud-set! b 7 17)
          (let ((sum (ud-cksum b 4 (+ 48 size)))) (ud-be16! b 46 (if (= sum 0) 65535 sum)))
          (ud-set! b 7 64) (ud-set! b 6 17)
          (cu-ptr-call (cu-libc-sym "sendto") fd (cu-str->ptr b) (+ 48 size) 0 (cu-str->ptr sll) 20))))
    ; the scripted server: each request read on u60 is answered by the next
    ; of ANSWERS, a function of the request giving the packets to send; a
    ; copy of the request read within half a second of the answer is passed
    ; over, as the udhcpc spec's is.  LAST is (XID TYPE MS) of the request
    ; last answered
    (def l6-scripted (fn (_ answers)
      (do (cu-ptr-call (cu-libc-sym "setns") l6-srv-ns 1073741824)
          (def if0 (cu-ptr-call (cu-libc-sym "if_nametoindex") "u60"))
          (def s (in-call (cu-ptr-call (cu-libc-sym "socket") 17 2 56710)))
          (def sll (inet-zeros 20))
          (inet-set! sll 0 17 2) (ud-be16! sll 2 34525) (inet-set! sll 4 if0 4)
          (cu-ptr-call (cu-libc-sym "bind") s (cu-str->ptr sll) 20)
          (def b (inet-zeros 2048))
          (let go ((as answers) (last (list -1 -1 0)))
            (unless (null? as)
              (let ((n (in-call (cu-ptr-call (cu-libc-sym "recv") s (cu-str->ptr b) 2048 0))))
                (if (if (>= n 52) (if (= (& (byte-at b 6) 255) 17) (= (pn-be16 (cu-str->ptr b) 42) 547) #f) #f)
                  (do (def req (ud-bytes b 48 (- (pn-be16 (cu-str->ptr b) 4) 8)))
                      (def src (ud-bytes b 8 16))
                      (def rx (ud-bytes-be (List take 3 (rest req))))
                      (def rt (first req))
                      (if (if (= rx (first last)) (if (= rt (cu-nth 1 last)) (< (- (ud-ms) (cu-nth 2 last)) 500) #f) #f)
                        (go as last)
                        (do (map (fn (_ p) (l6-send s if0 p src)) ((first as) req))
                            (go (rest as) (list rx rt (ud-ms))))))
                  (go as last)))))
          (let forever () (do (sys-usleep 1000000) (forever))))))
    (def l6-server (fn (_ answers)
      (do (def pid (sys-fork))
          (when (= pid 0)
            (guard (e (do (display e) (sys-exit 99)))
              (let ((ee (file-open-write "/tmp/u6-srv-err")))
                (do (sys-dup2 ee 1) (sys-dup2 ee 2) (l6-scripted answers) (sys-exit 0)))))
          (l6-sh "sleep 1")
          pid)))
    (def l6-client (fn (_ side args)
      (do (def pid (sys-fork))
          (when (= pid 0)
            (guard (e (sys-exit 99))
              (let ((ee (file-open-write "/tmp/u6-err")))
                (do (sys-dup2 ee 1) (sys-dup2 ee 2)
                    (if (string=? side "ours")
                      (sys-exit (cu-run (pair "udhcpc6" args) ""))
                      (do (sys-exec "/usr/local/bin/busybox-extra" (pair "udhcpc6" args)) (sys-exit 98)))))))
          pid)))
    (def l6-wait (fn (_ secs) (fn (_ pid) (l6-sh (string-append "sleep " secs)))))
    (def l6-kill (fn (_ sig) (fn (_ pid) (do (sys-kill pid sig) (l6-sh "sleep 1")))))
    ; a client gone to the background: its pidfile names it; SIGTERM ends it
    (def l6-background (fn (_)
      (if (not (do (l6-sh "sleep 0.5") (file-exists? "/tmp/u6.pid"))) ""
        ; one try in the background, ended by its leasefail, before the kill
        (let ((n (do (l6-sh "i=0; while [ $(grep -c '^event leasefail' /tmp/u6-script.log) -lt 2 ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done")
                     (ud-strtou (first (ud-strtok (file-read-all "/tmp/u6.pid") 0 "\n")) 10))))
          (do (def alive (= (in-call (cu-ptr-call (cu-libc-sym "kill") (first n) 0)) 0))
              (sys-kill (first n) 15)
              (l6-sh "sleep 1")
              (%str-concat (list "background " (if alive "running" "gone") ", pidfile "
                                 (if (file-exists? "/tmp/u6.pid") "left" "removed") "\n")))))))
    (def l6-side (fn (_ side answers args steps)
      (do (l6-sh "rm -f /tmp/u6-err /tmp/u6-srv-err /tmp/u6.pid; : > /tmp/u6-script.log; ip2 -n u6c -6 addr flush dev u61 scope global")
          (l6-drain)
          (Heap collect)
          (def srv (l6-server answers))
          (def pid (l6-client side (append (list "-i" "u61" "-s" "/tmp/u6-script.sh" "-T" "1") args)))
          (map (fn (_ s) (s pid)) steps)
          ; a client still running after a minute is killed, so a run that
          ; went wrong fails in its own case
          (l6-sh (%str-concat (list "p=" (cu-int->str pid) "; i=0; while [ -e /proc/$p ] && ! grep -q ') Z' /proc/$p/stat"
                                    " && [ $i -lt 600 ]; do sleep 0.1; i=$((i+1)); done; [ $i -lt 600 ] || kill -9 $p")))
          (def st (sys-wait pid))
          (def bg (l6-background))
          (sys-kill srv 9)
          (sys-wait srv)
          ; the raw socket reads every IPv6 frame on u61, the client's own
          ; and the kernel's among them, as they come
          (l6-sh (%str-concat (list "sed 's/^udhcpc6: started, v.*/udhcpc6: started/; s/xid [0-9a-f]* (our is [0-9a-f]*)/xid x (our is x)/;"
                                    " /waiting [0-9]* seconds/d; /unrelated\\/bogus packet, ignoring/d' /tmp/u6-err > /tmp/u6-err2")))
          ; a client in the background tries again a second after its second
          ; leasefail, so a late kill sees a third SOLICIT; two are compared
          (def fr (l6-drain))
          (when (not (string=? bg ""))
            (do (file-write-all "/tmp/u6-frames" fr)
                (l6-sh "head -n 2 /tmp/u6-frames > /tmp/u6-frames2")
                (set! fr (file-read-all "/tmp/u6-frames2"))))
          (%str-concat (list fr "stderr:\n" (file-read-all "/tmp/u6-err2") "status " (cu-int->str st) "\n"
                               bg "script:\n" (file-read-all "/tmp/u6-script.log")
                               "server:\n" (if (file-exists? "/tmp/u6-srv-err") (file-read-all "/tmp/u6-srv-err") ""))))))
    ; same, then the events the script saw, so a run with no lease on
    ; either side does not pass as one with a lease
    (def l6-case (fn (_ answers args steps)
      (let ((a (l6-side "ours" answers args steps)) (b (l6-side "bb" answers args steps)))
        (display (if (string=? a b)
                   (do (l6-sh "grep '^event' /tmp/u6-script.log | cut -d' ' -f2 | tr '\\n' ' ' | sed 's/ $//' > /tmp/u6-events")
                       (%str-concat (list "same: " (file-read-all "/tmp/u6-events") "\n")))
                   (%str-concat (list "ours:\n" a "busybox:\n" b)))))))
    (display (if l6-in (if l6-bound "made" "no capture") "no namespace")))
```
---
    made

## a lease

### SOLICIT, ADVERTISE, REQUEST, REPLY, and the script's bound

The SOLICIT asks for -r's address and, with -d, a prefix; -O adds to the
codes asked for; -x's options go after the FQDN asked for, a second
search name raising the first's code by its length, as busybox's does.
The REPLY carries an option of each kind the script is given, and one it
is not.

```cu
(def l6-full (fn (_ req)
  (list l6-sid (l6-na req "2001:db8::20" 100) (l6-pd req "2001:db8:1::" 48 200)
        (l6-o 23 (append (l6-pton "2001:db8::53") (l6-pton "2001:db8::54")))
        (l6-o 24 (append (l6-names (list "example" "org")) (l6-names (list "other" "org"))))
        (l6-o 39 (pair 0 (l6-names (list "host" "example" "org"))))
        (l6-o 41 (l6-s "EST5EDT")) (l6-o 42 (l6-s "America/Toronto"))
        (l6-o 59 (l6-s "tftp://boot/x")) (l6-o 60 (l6-s "arg")) (l6-o 209 (l6-s "pxe.cfg"))
        (l6-o 210 (l6-s "/pxe/")) (l6-o 99 (list 1 2 3)))))
(l6-case (list (l6-answer 2 l6-full) (l6-answer 7 l6-full))
  (list "-f" "-q" "-d" "-r" "2001:db8::5" "-O" "tz" "-O" "42"
        "-x" "fqdn:box.example" "-x" "0x10:abcd" "-x" "search:a.org,b.org")
  ())
```
---
```output
same: deconfig bound
```

### SIGUSR1 renews through the kernel, SIGUSR2 releases, -R at SIGTERM

```cu
(def l6-short (fn (_ req) (list l6-sid (l6-na req "2001:db8::21" 40))))
(l6-case (list (l6-answer 2 l6-short) (l6-answer 7 l6-short) (l6-answer 7 l6-short))
  (list "-f" "-R" "-o" "-O" "23")
  (list (l6-wait "3") (l6-kill 10) (l6-wait "2") (l6-kill 12) (l6-kill 15)))
```
---
```output
same: deconfig bound renew deconfig deconfig
```

### -l asks for information alone, and holds it a day

```cu
(l6-case (list (l6-answer 7 (fn (_ req) (list l6-sid (l6-o 23 (l6-pton "2001:db8::53"))))))
  (list "-f" "-q" "-l")
  ())
```
---
```output
same: deconfig renew
```

## no lease

### -n ends the run; -b goes to the background; an interface not there

```cu
(do (l6-case () (list "-f" "-n" "-t" "2") ())
    (l6-case () (list "-b" "-t" "1" "-A" "1" "-p" "/tmp/u6.pid") ())
    (l6-sh "rm -f /tmp/u6-err")
    (def l6-gone (fn (_ side)
      (let ((pid (l6-client side (list "-i" "u6none" "-f"))))
        (let ((st (sys-wait pid)))
          (string-append (file-read-all "/tmp/u6-err") (cu-int->str st))))))
    (let ((a (l6-gone "ours")) (b (l6-gone "bb")))
      (display (if (string=? a b) "same\n" (%str-concat (list "ours:\n" a "\nbusybox:\n" b "\n"))))))
```
---
```output
same: deconfig leasefail
same: deconfig leasefail leasefail
same
```

## what the client is sent

### another's transaction ID, a NAK, then a REPLY with no ADVERTISE

A REPLY to the SOLICIT is a lease at once, the script's event a renew;
the NAK's status code is printed from the third byte of its message.

```cu
(def l6-ok (fn (_ addr) (fn (_ req) (list l6-sid (l6-na req addr 50)))))
(l6-case
  (list (fn (_ req)
          (list (append (list 2 0 0 0) l6-sid) (first ((l6-answer 2 (l6-ok "2001:db8::30")) req))))
        (l6-answer 7 (fn (_ req) (list l6-sid (l6-o 13 (append (list 0 2) (l6-s "NoAddrsAvail"))))))
        (l6-answer 7 (l6-ok "2001:db8::31")))
  (list "-f" "-q" "-v" "-t" "3")
  ())
```
---
```output
same: deconfig nak renew
```

### an ADVERTISE with no server ID, a REPLY with no IA_NA

Each is passed over after the listening has stopped, so the client
hears nothing more until it starts over.

```cu
(def l6-adv (l6-answer 2 (l6-ok "2001:db8::40")))
(l6-case
  (list (l6-answer 2 (fn (_ req) (list (l6-na req "2001:db8::40" 50)))) l6-none
        l6-adv (l6-answer 7 (fn (_ req) (list l6-sid))) l6-none
        l6-adv (l6-answer 7 (l6-ok "2001:db8::41")))
  (list "-f" "-q" "-t" "2" "-A" "1")
  ())
```
---
```output
same: deconfig leasefail leasefail bound
```

### no answer to the renew: the rebind, the lease lost, a lease again

```cu
(l6-case
  (list (l6-answer 2 (l6-ok "2001:db8::42")) (l6-answer 7 (fn (_ req) (list l6-sid (l6-na req "2001:db8::42" 40))))
        l6-none l6-none l6-none l6-none
        (l6-answer 2 (l6-ok "2001:db8::43")) (l6-answer 7 (l6-ok "2001:db8::43")))
  (list "-f" "-v")
  (list (l6-wait "2") (l6-kill 10) (l6-wait "8") (l6-kill 15)))
```
---
```output
same: deconfig bound deconfig bound
```
