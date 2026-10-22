# @weight 2

busybox's arp (networking/arp.c), run as root against the container's own
ARP cache.  Each case runs the bundle's arp and busybox's on the same words,
PRE through the shell before each, and compares what they write and their
status, and where it says so what /proc/net/arp holds after.  The entries
are on 10.77.0.0/24, an address the setup puts on eth0, their names in
/etc/hosts so a name is found without asking a server; each case takes
away what it adds.

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

### the subnet the entries are on

```cu
(do (lx-sh "ip addr add 10.77.0.1/24 dev eth0 2>/dev/null; ip neigh flush dev eth0 to 10.77.0.0/24 >/dev/null 2>&1; printf '10.77.0.5 lx-five\\n10.77.0.6 lx-six\\n' >> /etc/hosts; true")
    (def lx-clear "arp -d 10.77.0.5 >/dev/null 2>&1; arp -d 10.77.0.6 >/dev/null 2>&1; arp -d 10.77.0.7 >/dev/null 2>&1; ip neigh flush dev eth0 to 10.77.0.0/24 >/dev/null 2>&1; true")
    (display "set"))
```
---
    set

## showing

### the cache, by name and by number, a host's entry, a device's, a hardware type's, and none of them

```cu
(do (lx-sh "arp -s 10.77.0.5 02:00:00:00:00:05; arp -s 10.77.0.6 02:00:00:00:00:06 pub")
    (def lx-quiet "ip neigh flush dev eth0 >/dev/null 2>&1; true")
    (lx-case lx-quiet (list "arp" "10.77.0.5"))
    (lx-case lx-quiet (list "arp" "-a" "-n"))
    (lx-case lx-quiet (list "arp" "-n" "10.77.0.5"))
    (lx-case lx-quiet (list "arp" "-n" "-i" "eth0"))
    (lx-case lx-quiet (list "arp" "-n" "-H" "ether"))
    (lx-case lx-quiet (list "arp" "-n" "-i" "nosuch0"))
    (lx-case lx-quiet (list "arp" "-n" "10.77.0.99"))
    (lx-sh lx-clear) (display ""))
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

## setting and deleting

### -s sets an entry, permanent unless temp, published with pub, with a netmask; the cache after says so

The cache after leaves out the gateway's entry, which the gateway's own
traffic can add between the two sides.

```cu
(do (lx-case-after lx-clear (list "arp" "-s" "10.77.0.5" "02:00:00:00:00:05") "grep -v \"^$(ip route | awk '/^default/ {print $3}') \" /proc/net/arp")
    (lx-case-after lx-clear (list "arp" "-s" "10.77.0.5" "2:0:0:0:0:a" "temp") "grep -v \"^$(ip route | awk '/^default/ {print $3}') \" /proc/net/arp")
    (lx-case-after lx-clear (list "arp" "-i" "eth0" "-s" "10.77.0.5" "02-00" "pub") "grep -v \"^$(ip route | awk '/^default/ {print $3}') \" /proc/net/arp")
    (lx-case-after lx-clear (list "arp" "-s" "10.77.0.5" "02:00:00:00:00:05" "netmask" "255.255.255.255" "pub" "dev" "eth0") "grep -v \"^$(ip route | awk '/^default/ {print $3}') \" /proc/net/arp")
    (lx-case-after lx-clear (list "arp" "-Ds" "10.77.0.6" "eth0" "pub") "grep -v \"^$(ip route | awk '/^default/ {print $3}') \" /proc/net/arp")
    (lx-case-after lx-clear (list "arp" "-s" "10.77.0.5" "02:00:00:00:00:05" "dontpub" "auto" "trail") "grep -v \"^$(ip route | awk '/^default/ {print $3}') \" /proc/net/arp")
    (lx-sh lx-clear) (display ""))
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

### -d deletes it, the published one too; an entry not there is said, status 255

```cu
(do (lx-case-after (string-append lx-clear "; arp -s 10.77.0.5 02:00:00:00:00:05") (list "arp" "-d" "10.77.0.5") "cat /proc/net/arp")
    (lx-case-after (string-append lx-clear "; arp -s 10.77.0.6 02:00:00:00:00:06 pub") (list "arp" "-d" "10.77.0.6" "pub") "cat /proc/net/arp")
    (lx-case lx-clear (list "arp" "-d" "10.77.0.7"))
    (lx-case lx-clear (list "arp" "-d" "10.77.0.7" "priv"))
    (lx-sh lx-clear) (display ""))
```
---
```output
same
same
same
same
```

### what arp refuses: a hardware address that is not one, none, no host, a device that is not, a word it does not know

```cu
(do (lx-case lx-clear (list "arp" "-s" "10.77.0.5" "zz:00"))
    (lx-case lx-clear (list "arp" "-s" "10.77.0.5"))
    (lx-case lx-clear (list "arp" "-s"))
    (lx-case lx-clear (list "arp" "-d"))
    (lx-case lx-clear (list "arp" "-Ds" "10.77.0.6" "nosuch0"))
    (lx-case lx-clear (list "arp" "-s" "10.77.0.5" "02:00:00:00:00:05" "sideways"))
    (lx-case lx-clear (list "arp" "-s" "10.77.0.5" "02:00:00:00:00:05" "dev"))
    (lx-case lx-clear (list "arp" "-d" "no.such.name.invalid")))
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
```

### families and hardware types: inet only, a type with ARP only

```cu
(do (lx-case ":" (list "arp" "-A" "inet6"))
    (lx-case ":" (list "arp" "-p" "ipx"))
    (lx-case ":" (list "arp" "-H" "loop"))
    (lx-case ":" (list "arp" "-H" "token"))
    (lx-case "ip neigh flush dev eth0 >/dev/null 2>&1; true" (list "arp" "-A" "inet" "-n")))
```
---
```output
same
same
same
same
same
```

### the setup taken away

```cu
(do (lx-sh (string-append lx-clear "; ip addr del 10.77.0.1/24 dev eth0 2>/dev/null; true")) (display "clear"))
```
---
    clear
