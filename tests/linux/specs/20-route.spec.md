# @weight 2

busybox's route (networking/route.c), run as root against the container's
own network namespace.  Each case runs the bundle's route and busybox's on
the same words, PRE through the shell before each, and compares what they
write and their status: `same`, or both answers.  A route a case adds is
one on the container's own interfaces, and the case after it takes it away.

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
          (%str-concat (list (lx-read "/tmp/lx-xo") "stderr:\n" (lx-read "/tmp/lx-xe") "status " (cu-int->str lx-st) "\n")))))
    (def lx-bb (fn (_ argv)
      (do (lx-sh (%str-concat (list "/bin/busybox " (Str8 join " " (map lx-q argv)) " > /tmp/lx-bo 2> /tmp/lx-bx; echo $? > /tmp/lx-bs; sed '/^BusyBox v/{N;d;}' /tmp/lx-bx > /tmp/lx-be")))
          (%str-concat (list (lx-read "/tmp/lx-bo") "stderr:\n" (lx-read "/tmp/lx-be") "status " (lx-read "/tmp/lx-bs"))))))
    ; PRE run through the shell before each side
    (def lx-case (fn (_ pre argv)
      (do (lx-sh pre) (def lx-a (lx-x argv)) (lx-sh pre) (def lx-b (lx-bb argv))
          (display (if (string=? lx-a lx-b) "same\n" (%str-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    ; as lx-case, with what POST says after each side's run compared too: the
    ; kernel's own account of what the run changed
    (def lx-case-after (fn (_ pre argv post)
      (do (lx-sh pre) (def lx-a (lx-x argv)) (lx-sh (%str-concat (list "{ " post "; } > /tmp/lx-post 2>&1"))) (def lx-pa (lx-read "/tmp/lx-post"))
          (lx-sh pre) (def lx-b (lx-bb argv)) (lx-sh (%str-concat (list "{ " post "; } > /tmp/lx-post 2>&1"))) (def lx-pb (lx-read "/tmp/lx-post"))
          (display (if (if (string=? lx-a lx-b) (string=? lx-pa lx-pb) #f) "same\n"
                     (%str-concat (list "ours:\n" lx-a lx-pa "busybox:\n" lx-b lx-pb)))))))
    (display "made"))
```
---
    made

## showing

### the IPv4 table, by name and by number, and -e's columns

```cu
(do (lx-case ":" (list "route"))
    (lx-case ":" (list "route" "-n"))
    (lx-case ":" (list "route" "-n" "-e"))
    (lx-case ":" (list "route" "-A" "inet" "-n")))
```
---
```output
same
same
same
same
```

### the IPv6 table

```cu
(lx-case ":" (list "route" "-A" "inet6"))
```
---
    same

### a family that is neither, and a verb that is no verb, are its usage

```cu
(do (lx-case ":" (list "route" "-A" "ipx"))
    (lx-case ":" (list "route" "move" "10.9.9.0"))
    (lx-case ":" (list "route" "add")))
```
---
```output
same
same
same
```

## adding and deleting

### a network by prefix, a host, a gateway, a metric; each added, shown, and deleted

```cu
(do (def lx-undo "ip route del 10.9.9.0/24 2>/dev/null; ip route del 10.9.8.7 2>/dev/null; ip route del 10.9.7.0/24 2>/dev/null; true")
    (lx-case-after lx-undo (list "route" "add" "-net" "10.9.9.0/24" "dev" "lo") "ip route show 10.9.9.0/24")
    (lx-case ":" (list "route" "-n"))
    (lx-case-after lx-undo (list "route" "add" "-host" "10.9.8.7" "lo") "ip route show 10.9.8.7")
    (lx-case-after lx-undo (list "route" "add" "-net" "10.9.7.0" "netmask" "255.255.255.0" "metric" "5" "dev" "lo") "ip route show 10.9.7.0/24")
    (lx-case "ip route replace 10.9.9.0/24 dev lo" (list "route" "del" "-net" "10.9.9.0/24" "dev" "lo"))
    (lx-sh lx-undo) (display ""))
```
---
```output
same
same
same
same
same
```

### what the kernel refuses: a route that is there, one that is not, a device that is not

```cu
(do (lx-case "ip route replace 10.9.9.0/24 dev lo" (list "route" "add" "-net" "10.9.9.0/24" "dev" "lo"))
    (lx-case "ip route del 10.9.9.0/24 2>/dev/null; true" (list "route" "del" "-net" "10.9.9.0/24" "dev" "lo"))
    (lx-case ":" (list "route" "add" "-net" "10.9.6.0/24" "dev" "nosuch0"))
    (lx-sh "ip route del 10.9.9.0/24 2>/dev/null; true") (display ""))
```
---
```output
same
same
same
```

### what route refuses itself: a mask and a host, a bogus mask, a mask and an address, a gateway that is a network

```cu
(do (lx-case ":" (list "route" "add" "-host" "10.9.9.1" "netmask" "255.255.255.0" "lo"))
    (lx-case ":" (list "route" "add" "-net" "10.9.9.0" "netmask" "255.0.255.0" "lo"))
    (lx-case ":" (list "route" "add" "-net" "10.9.9.1" "netmask" "255.255.255.0" "lo"))
    (lx-case ":" (list "route" "add" "-net" "10.9.9.0/24" "gw" "default"))
    (lx-case ":" (list "route" "add" "-net" "10.9.9.0/33" "lo"))
    (lx-case ":" (list "route" "add" "-net" "10.9.9.0/24" "mss" "10" "lo"))
    (lx-case ":" (list "route" "add" "-net" "no.such.name.invalid" "lo")))
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
```

### a reject route goes on lo

```cu
(do (lx-case "ip route del unreachable 10.9.5.0/24 2>/dev/null; ip route del 10.9.5.0/24 2>/dev/null; true" (list "route" "add" "-net" "10.9.5.0/24" "reject"))
    (lx-case ":" (list "route" "-n"))
    (lx-sh "ip route del unreachable 10.9.5.0/24 2>/dev/null; ip route del 10.9.5.0/24 2>/dev/null; true") (display ""))
```
---
```output
same
same
```

### IPv6: a route added on lo and deleted

```cu
(do (def lx-undo6 "ip -6 route del fd00:9::/64 2>/dev/null; true")
    (lx-case lx-undo6 (list "route" "-A" "inet6" "add" "fd00:9::/64" "dev" "lo"))
    (lx-case "ip -6 route del fd00:9::/64 2>/dev/null; ip -6 route add fd00:9::/64 dev lo metric 1" (list "route" "-A" "inet6" "del" "fd00:9::/64" "dev" "lo"))
    (lx-sh lx-undo6) (display ""))
```
---
```output
same
same
```
