# @weight 2

busybox's ping and ping6 (networking/ping.c), run as root over the
container's loopback.  Each case runs the bundle's ping and busybox's on the
same words and compares what they write and their status, each trip's time
and the round-trip line's figures written as T, the one thing the two runs
cannot share.  192.0.2.1 (TEST-NET-1) is an address nothing answers.

## the comparison

### each applet against busybox's, the times set aside

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (def lx-times "sed -E 's/time=[0-9]+[.][0-9]+ ms/time=T ms/; s|^round-trip min/avg/max = .*|round-trip min/avg/max = T|'")
    (def lx-x (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (def lx-o (file-open-write "/tmp/lx-xo")) (def lx-e (file-open-write "/tmp/lx-xe"))
          (sys-dup2 lx-o 1) (sys-dup2 lx-e 2)
          (def lx-st (cu-run argv ""))
          (sys-dup2 9 1) (sys-dup2 8 2) (file-close lx-o) (file-close lx-e)
          (lx-sh (string-append lx-times " /tmp/lx-xo > /tmp/lx-xn"))
          (string-concat (list (lx-read "/tmp/lx-xn") "stderr:\n" (lx-read "/tmp/lx-xe") "status " (cu-int->str lx-st) "\n")))))
    (def lx-bb (fn (_ argv)
      (do (lx-sh (string-concat (list "/bin/busybox " (Str8 join " " (map lx-q argv)) " > /tmp/lx-bo 2> /tmp/lx-bx; echo $? > /tmp/lx-bs; sed '/^BusyBox v/{N;d;}' /tmp/lx-bx > /tmp/lx-be; " lx-times " /tmp/lx-bo > /tmp/lx-bn")))
          (string-concat (list (lx-read "/tmp/lx-bn") "stderr:\n" (lx-read "/tmp/lx-be") "status " (lx-read "/tmp/lx-bs"))))))
    (def lx-case (fn (_ argv)
      (do (def lx-a (lx-x argv)) (def lx-b (lx-bb argv))
          (display (if (string=? lx-a lx-b) "same\n" (string-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    (display "made"))
```
---
    made

## replies

### a count, an interval, a size and a pattern, quiet, a name

```cu
(do (lx-case (list "ping" "-c" "2" "-i" "0.2" "127.0.0.1"))
    (lx-case (list "ping" "-c" "2" "-i" "0.2" "-s" "100" "-p" "ff" "127.0.0.1"))
    (lx-case (list "ping" "-q" "-c" "2" "-i" "0.2" "127.0.0.1"))
    (lx-case (list "ping" "-c" "1" "localhost"))
    (lx-case (list "ping" "-c" "1" "-t" "1" "127.0.0.1")))
```
---
```output
same
same
same
same
same
```

### data too short for the clock: no time, and no round-trip line

```cu
(do (lx-case (list "ping" "-c" "1" "-s" "0" "127.0.0.1"))
    (lx-case (list "ping" "-c" "1" "-s" "2" "127.0.0.1")))
```
---
```output
same
same
```

### -A sends as each reply comes

```cu
(lx-case (list "ping" "-A" "-c" "3" "127.0.0.1"))
```
---
```output
same
```

### -I names a device, a source address, or neither

```cu
(do (lx-case (list "ping" "-I" "lo" "-c" "1" "127.0.0.1"))
    (lx-case (list "ping" "-I" "127.0.0.1" "-c" "1" "127.0.0.1"))
    (lx-case (list "ping" "-I" "nosuch0" "-c" "1" "127.0.0.1")))
```
---
```output
same
same
same
```

## no replies

### the last of -c waited for -W seconds, and -w's deadline short of -c

```cu
(do (lx-case (list "ping" "-c" "2" "-i" "0.2" "-W" "1" "192.0.2.1"))
    (lx-case (list "ping" "-c" "5" "-w" "1" "-i" "0.4" "192.0.2.1"))
    (lx-case (list "ping" "-w" "1" "-i" "0.4" "127.0.0.1")))
```
---
```output
same
same
same
```

## ping6

### ::1 by ping6 and by ping -6, too short for the clock, and an IPv4 address for either

```cu
(do (lx-case (list "ping6" "-c" "2" "-i" "0.2" "::1"))
    (lx-case (list "ping" "-6" "-c" "1" "::1"))
    (lx-case (list "ping6" "-c" "1" "-s" "0" "::1"))
    (lx-case (list "ping" "-6" "127.0.0.1"))
    (lx-case (list "ping6" "127.0.0.1")))
```
---
```output
same
same
same
same
same
```

## SIGINT

### the statistics, and the status by what came back

```cu
(do (def lx-o (file-open-write "/tmp/lx-io"))
    (def lx-pid (sys-fork))
    (when (= lx-pid 0) (do (sys-dup2 lx-o 1) (sys-exit (cu-run (list "ping" "-i" "0.2" "127.0.0.1") ""))))
    (file-close lx-o)
    (sys-usleep 1100000)
    (sys-kill lx-pid 2)
    (def lx-st (sys-wait lx-pid))
    (lx-sh "busybox ping -i 0.2 127.0.0.1 > /tmp/lx-ib & p=$!; sleep 1.1; kill -INT $p; wait $p; echo $? > /tmp/lx-is")
    (def lx-shape (fn (_ in out) (string-concat (list "sed -E 's/[0-9]+([.][0-9]+)?/N/g' < " in " | uniq > " out))))
    (lx-sh (string-concat (list (lx-shape "/tmp/lx-io" "/tmp/lx-ia") "; " (lx-shape "/tmp/lx-ib" "/tmp/lx-ic"))))
    (display (if (string=? (lx-read "/tmp/lx-ia") (lx-read "/tmp/lx-ic")) "same\n" (string-append (lx-read "/tmp/lx-ia") (lx-read "/tmp/lx-ic"))))
    (display (lx-read "/tmp/lx-ic")) (display lx-st) (display "\n") (display (lx-read "/tmp/lx-is")))
```
---
```output
same
PING N.N (N.N): N data bytes
N bytes from N.N: seq=N ttl=N time=N ms

--- N.N ping statistics ---
N packets transmitted, N packets received, N% packet loss
round-trip min/avg/max = N/N/N ms
0
0
```
