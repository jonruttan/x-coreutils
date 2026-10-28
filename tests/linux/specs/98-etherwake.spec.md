# @weight 2

busybox's ether-wake (networking/ether-wake.c), run as root in a namespace
of its own, wol, which this file's process enters.  A veth pair, ew0 and
ew1, joins two addresses; a packet socket on ew1 takes every frame of type
0x0842 that reaches it.  Each case is a run of commands: the bundle's
ether-wake is run on each, then the frames ew1 took are written in hex,
then the same with busybox's, and what each writes, its statuses and its
frames are compared.

## the comparison

### the applet against busybox's, the frames each sends

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (lx-sh "ip2 netns add wol")
    (def lx-ns (in-call (cu-ptr-call (cu-libc-sym "open") "/var/run/netns/wol" 0)))
    (def lx-in (= (in-call (cu-ptr-call (cu-libc-sym "setns") lx-ns 1073741824)) 0))
    (lx-sh (Str8 join "\n" (list
      "[ \"$(readlink /proc/self/ns/net)\" != \"$(readlink /proc/1/ns/net)\" ] || exit 1"
      "ip2 link add ew0 address 02:00:00:00:09:01 type veth peer name ew1 address 02:00:00:00:09:02"
      "ip2 link add ewd address 02:00:00:00:09:03 type dummy"
      "ip2 link set ew0 up; ip2 link set ew1 up; ip2 link set lo up")))
    (def lx-cap (in-call (cu-ptr-call (cu-libc-sym "socket") 17 3 16904)))
    (def lx-sll (inet-zeros 20))
    (inet-set! lx-sll 0 17 2) (inet-set! lx-sll 2 8 1) (inet-set! lx-sll 3 66 1)
    (inet-set! lx-sll 4 (cu-ptr-call (cu-libc-sym "if_nametoindex") "ew1") 4)
    (def lx-bound (= (in-call (cu-ptr-call (cu-libc-sym "bind") lx-cap (cu-str->ptr lx-sll) 20)) 0))
    (def lx-buf (inet-zeros 2048))
    (def lx-hex (fn (_ n)
      (Str8 join " " (map (fn (_ k) (let ((b (& (byte-at lx-buf k) 255)))
                                      (string-append (substring "0123456789abcdef" (>> b 4) (+ (>> b 4) 1))
                                                     (substring "0123456789abcdef" (& b 15) (+ (& b 15) 1)))))
                          (List range 0 n)))))
    (def lx-drain (fn (_)
      (let go ((acc ""))
        (let ((r (in-call (cu-ptr-call (cu-libc-sym "recv") lx-cap (cu-str->ptr lx-buf) 2048 64))))
          (if (< r 0) acc (go (string-concat (list acc "frame " (lx-hex r) "\n"))))))))
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
      (do (lx-drain)
          (def lx-out (string-concat (map one runs)))
          (lx-sh "sleep 0.2")
          (string-append lx-out (lx-drain)))))
    (def lx-case (fn (_ runs)
      (do (def lx-a (lx-run lx-x1 runs)) (def lx-b (lx-run lx-bb1 runs))
          (display (if (string=? lx-a lx-b) "same\n" (string-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    (display (if lx-in (if lx-bound "made" "no capture") "no namespace")))
```
---
    made

## the packet

### to MAC, broadcast, MAC written short and in capitals

```cu
(do (lx-case (list (list "ether-wake" "-i" "ew0" "02:00:00:00:09:02")))
    (lx-case (list (list "ether-wake" "-b" "-i" "ew0" "02:00:00:00:09:02")))
    (lx-case (list (list "ether-wake" "-i" "ew0" "2:0:0:0:9:2") (list "ether-wake" "-i" "ew0" "AA:bb:Cc:0:1:ff"))))
```
---
```output
same
same
same
```

### a password: four, five and six hex bytes, a dotted quad, one not read

```cu
(do (lx-case (list (list "ether-wake" "-i" "ew0" "-p" "01:02:03:04" "02:00:00:00:09:02")))
    (lx-case (list (list "ether-wake" "-i" "ew0" "-p" "a:b:c:d:e" "02:00:00:00:09:02")
                   (list "ether-wake" "-i" "ew0" "-p" "aa:bb:cc:dd:ee:ff" "02:00:00:00:09:02")))
    (lx-case (list (list "ether-wake" "-i" "ew0" "-p" "192.168.300.4" "02:00:00:00:09:02")
                   (list "ether-wake" "-i" "ew0" "-p" "-1.2.3.4" "02:00:00:00:09:02")))
    (lx-case (list (list "ether-wake" "-i" "ew0" "-p" "ff:ff" "02:00:00:00:09:02")
                   (list "ether-wake" "-i" "ew0" "-p" "1.2.3" "02:00:00:00:09:02")
                   (list "ether-wake" "-b" "-i" "ew0" "-p" "" "02:00:00:00:09:02"))))
```
---
```output
same
same
same
same
```

## the refusals

### MACs not read, the usage

```cu
(do (lx-case (list (list "ether-wake" "-i" "ew0" "02:00:00:00:09") (list "ether-wake" "-i" "ew0" "02:00:00:00:09:02:")
                   (list "ether-wake" "-i" "ew0" "100:0:0:0:0:1") (list "ether-wake" "-i" "ew0" "nosuchhost")))
    (lx-case (list (list "ether-wake") (list "ether-wake" "a" "b") (list "ether-wake" "-x" "02:00:00:00:09:02"))))
```
---
```output
same
same
```

### interfaces: not there, the default not there, down, the loopback

```cu
(do (lx-case (list (list "ether-wake" "-i" "nosuch" "02:00:00:00:09:02") (list "ether-wake" "02:00:00:00:09:02")))
    (lx-case (list (list "ether-wake" "-i" "ewd" "02:00:00:00:09:02") (list "ether-wake" "-i" "lo" "02:00:00:00:09:02"))))
```
---
```output
same
same
```
