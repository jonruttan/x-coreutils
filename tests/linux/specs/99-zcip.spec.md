# @weight 2
# @timeout-scale 4

busybox's zcip (networking/zcip.c), run as root in a namespace of its own,
zc, which this file's process enters.  A veth pair, zc0 and zc1, joins two
interfaces; a packet socket on zc1 takes every ARP frame that crosses it.
SCRIPT is /tmp/zc.sh, which adds "WORD interface ip" to /tmp/zc-log.  Each
case is a run of commands: the bundle's zcip is run on each, then the log
and the frames zc1 took are written, then the same with busybox's, and
what each writes, its statuses, its log and its frames are compared.  The
addresses are picked from the C library's rand seeded from zc0's hardware
address, so the same frames mean the same picks.

## the comparison

### the applet against busybox's, the script's log and the frames

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (lx-sh "ip2 netns add zc")
    (def lx-ns (in-call (cu-ptr-call (cu-libc-sym "open") "/var/run/netns/zc" 0)))
    (def lx-in (= (in-call (cu-ptr-call (cu-libc-sym "setns") lx-ns 1073741824)) 0))
    (lx-sh (Str8 join "\n" (list
      "[ \"$(readlink /proc/self/ns/net)\" != \"$(readlink /proc/1/ns/net)\" ] || exit 1"
      "ip2 link add zc0 address 02:00:00:00:0a:01 type veth peer name zc1 address 02:00:00:00:0a:02"
      "ip2 link set zc0 up; ip2 link set zc1 up; ip2 link set lo up"
      "printf '#!/bin/sh\\necho \"$1 $interface $ip\" >> /tmp/zc-log\\n' > /tmp/zc.sh"
      "printf '#!/bin/sh\\nexit 3\\n' > /tmp/zc3.sh"
      "chmod +x /tmp/zc.sh /tmp/zc3.sh")))
    (def lx-cap (in-call (cu-ptr-call (cu-libc-sym "socket") 17 3 1544)))
    (def lx-sll (inet-zeros 20))
    (inet-set! lx-sll 0 17 2) (inet-set! lx-sll 2 8 1) (inet-set! lx-sll 3 6 1)
    (inet-set! lx-sll 4 (cu-ptr-call (cu-libc-sym "if_nametoindex") "zc1") 4)
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
    ; WAIT seconds after the runs, for a run gone to the background
    (def lx-run (fn (_ one runs wait)
      (do (lx-drain)
          (lx-sh "rm -f /tmp/zc-log; touch /tmp/zc-log")
          (def lx-out (string-concat (map one runs)))
          (lx-sh (string-append "sleep " wait))
          (string-concat (list lx-out "log:\n" (lx-read "/tmp/zc-log") (lx-drain))))))
    (def lx-case (fn (_ runs wait)
      (do (def lx-a (lx-run lx-x1 runs wait)) (def lx-b (lx-run lx-bb1 runs wait))
          (display (if (string=? lx-a lx-b) "same\n" (string-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    (display (if lx-in (if lx-bound "made" "no capture") "no namespace")))
```
---
    made

## the address

### probed, announced, configured, then -q ends the run

```cu
(lx-case (list (list "zcip" "-f" "-q" "zc0" "/tmp/zc.sh")) "0.2")
```
---
```output
same
```

### -r's address held by zc1: a new one picked from -l's range

```cu
(do (lx-sh "ip2 addr add 10.7.5.5/16 dev zc1")
    (lx-case (list (list "zcip" "-v" "-q" "-l" "10.7.0.0" "-r" "10.7.5.5" "zc0" "/tmp/zc.sh")) "0.2")
    (lx-sh "ip2 addr del 10.7.5.5/16 dev zc1")
    ())
```
---
```output
same
```

### in the background: the caller's run ends at once, the script's log after

```cu
(lx-case (list (list "zcip" "-q" "zc0" "/tmp/zc.sh")) "15")
```
---
```output
same
```

## the refusals

### ranges and addresses not taken, the usage

```cu
(do (lx-case (list (list "zcip" "-f" "-l" "10.7.1.0" "zc0" "/tmp/zc.sh")
                   (list "zcip" "-f" "-l" "nonsense" "zc0" "/tmp/zc.sh")
                   (list "zcip" "-f" "-l" "10.7.0.0" "-r" "169.254.1.1" "zc0" "/tmp/zc.sh")
                   (list "zcip" "-f" "-r" "x" "zc0" "/tmp/zc.sh")) "0")
    (lx-case (list (list "zcip" "zc0") (list "zcip" "-x" "zc0" "/tmp/zc.sh")) "0"))
```
---
```output
same
same
```

### scripts not run and failing, an interface not there

```cu
(lx-case (list (list "zcip" "-f" "zc0" "/nonexistent")
               (list "zcip" "-f" "zc0" "/tmp/zc3.sh")
               (list "zcip" "-f" "nosuch" "/tmp/zc.sh")) "0")
```
---
```output
same
```
