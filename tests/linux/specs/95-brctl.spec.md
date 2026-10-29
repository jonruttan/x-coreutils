# @weight 2

busybox's brctl (networking/brctl.c), run as root in a network namespace
of its own, brn, which this file's process enters, with a mount namespace
of its own over a sysfs mounted afresh, so /sys/class/net lists brn's
interfaces and the bridges touch no other file's.  bd0 (02:00:00:00:08:01)
and bd1 (02:00:00:00:08:02) are dummies to join to them.  Each case is a
run of commands: it takes away every interface but the loopback and builds
bd0 and bd1 anew, runs the bundle's brctl on each, reads the settings each
bridge and port is left with from /sys, then does the same with busybox's,
and compares what each writes, its statuses and the settings left, the
timers that run on their own written as T.

## the comparison

### the applet against busybox's, the interfaces built anew for each

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (def lx-times "sed -E 's/(timer[\t ]+) *[0-9]+[.][0-9]{2}/\\1T/g'")
    (def lx-state (Str8 join "; " (list
            "cd /sys/class/net"
            "for b in */bridge; do b=${b%/bridge}; [ -d $b/bridge ] || continue; printf '%s' $b; for f in forward_delay hello_time max_age ageing_time stp_state priority; do printf ' %s=%s' $f $(cat $b/bridge/$f); done; echo; for p in $b/brif/*; do [ -e $p ] || continue; p=${p##*/}; echo \"  $p $(cat $p/brport/path_cost) $(cat $p/brport/priority)\"; done; done > /tmp/lx-st")))
    (def lx-reset (fn (_)
      (lx-sh (Str8 join "\n" (list
              "[ \"$(readlink /proc/self/ns/net)\" != \"$(readlink /proc/1/ns/net)\" ] || exit 1"
              "for l in $(ip2 -o link | grep -v link/loopback | sed -E 's/^[0-9]+: ([^:@]+).*/\\1/'); do ip2 link del $l 2>/dev/null; done"
              "ip2 link add bd0 address 02:00:00:00:08:01 type dummy"
              "ip2 link add bd1 address 02:00:00:00:08:02 type dummy"
              "true")))))
    (def lx-x1 (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (def lx-o (file-open-write "/tmp/lx-xo")) (def lx-e (file-open-write "/tmp/lx-xe"))
          (sys-dup2 lx-o 1) (sys-dup2 lx-e 2)
          (def lx-st (cu-run argv ""))
          (sys-dup2 9 1) (sys-dup2 8 2) (file-close lx-o) (file-close lx-e)
          (lx-sh (string-append lx-times " /tmp/lx-xo > /tmp/lx-xn"))
          (%str-concat (list (lx-read "/tmp/lx-xn") "stderr:\n" (lx-read "/tmp/lx-xe") "status " (cu-int->str lx-st) "\n")))))
    (def lx-bb1 (fn (_ argv)
      (do (lx-sh (%str-concat (list "/bin/busybox " (Str8 join " " (map lx-q argv)) " > /tmp/lx-bo 2> /tmp/lx-bx; echo $? > /tmp/lx-bs; sed '/^BusyBox v/{N;d;}' /tmp/lx-bx > /tmp/lx-be; " lx-times " /tmp/lx-bo > /tmp/lx-bn")))
          (%str-concat (list (lx-read "/tmp/lx-bn") "stderr:\n" (lx-read "/tmp/lx-be") "status " (lx-read "/tmp/lx-bs"))))))
    (def lx-run (fn (_ one runs)
      (do (lx-reset)
          (def lx-out (%str-concat (map one runs)))
          (lx-sh lx-state)
          (string-append lx-out (lx-read "/tmp/lx-st")))))
    (def lx-case (fn (_ runs)
      (do (def lx-a (lx-run lx-x1 runs)) (def lx-b (lx-run lx-bb1 runs))
          (display (if (string=? lx-a lx-b) "same\n" (%str-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    (lx-sh "ip2 netns add brn")
    (def lx-ns (in-call (cu-ptr-call (cu-libc-sym "open") "/var/run/netns/brn" 0)))
    (def lx-in (= (in-call (cu-ptr-call (cu-libc-sym "setns") lx-ns 1073741824)) 0))
    (def lx-mnt (if lx-in (= (in-call (cu-ptr-call (cu-libc-sym "unshare") 131072)) 0) #f))
    (when lx-mnt (in-call (cu-ptr-call (cu-libc-sym "mount") "none" "/" 0 278528 0)))
    (def lx-sys (if lx-mnt (= (in-call (cu-ptr-call (cu-libc-sym "mount") "sysfs" "/sys" "sysfs" 0 0)) 0) #f))
    (display (if lx-sys "made" "no namespace")))
```
---
    made

## bridges and their interfaces

### made, made twice, words past the bridge, joined, shown, taken out, removed

```cu
(do (lx-case (list (list "brctl" "addbr" "br0") (list "brctl" "addbr" "br0") (list "brctl" "addbr" "br1" "x" "y") (list "brctl" "show")))
    (lx-case (list (list "brctl" "addbr" "br0") (list "brctl" "addif" "br0" "bd0") (list "brctl" "addif" "br0" "bd1")
                   (list "brctl" "show") (list "brctl" "show" "br0")))
    (lx-case (list (list "brctl" "addbr" "br0") (list "brctl" "addif" "br0" "bd0") (list "brctl" "addif" "br0" "bd1")
                   (list "brctl" "delif" "br0" "bd1") (list "brctl" "delif" "br0" "bd1") (list "brctl" "show")))
    (lx-case (list (list "brctl" "addbr" "br0") (list "brctl" "delbr" "br0") (list "brctl" "delbr" "br0") (list "brctl" "show")))
    (lx-case (list (list "brctl" "addbr" "abcdefghijklmnopq") (list "brctl" "show") (list "brctl" "delbr" "abcdefghijklmnopq"))))
```
---
```output
same
same
same
same
same
```

### shown: none, several named, one that is no bridge, an interface not there

```cu
(do (lx-case (list (list "brctl" "show")))
    (lx-case (list (list "brctl" "addbr" "br0") (list "brctl" "addbr" "br1") (list "brctl" "show" "br0" "nosuch" "br1")
                   (list "brctl" "show" "bd0") (list "brctl" "show" "nosuch")))
    (lx-case (list (list "brctl" "addbr" "br0") (list "brctl" "addif" "br0" "nosuch") (list "brctl" "addif" "nosuch" "bd0")
                   (list "brctl" "delif" "br0" "bd0"))))
```
---
```output
same
same
same
```

## settings

### stp, the times as strtod reads them, the priorities and costs

```cu
(do (lx-case (list (list "brctl" "addbr" "br0") (list "brctl" "stp" "br0" "on") (list "brctl" "stp" "br0" "maybe")
                   (list "brctl" "addbr" "br1") (list "brctl" "stp" "br1" "yes") (list "brctl" "stp" "br1" "0")))
    (lx-case (list (list "brctl" "addbr" "br0") (list "brctl" "setageing" "br0" "2.3") (list "brctl" "setfd" "br0" "4.56")
                   (list "brctl" "sethello" "br0" "1e0") (list "brctl" "setmaxage" "br0" "0x10")))
    (lx-case (list (list "brctl" "addbr" "br0") (list "brctl" "setageing" "br0" "x") (list "brctl" "setageing" "br0" "-1")
                   (list "brctl" "setageing" "br0" " 7abc") (list "brctl" "setfd" "br0" "1") (list "brctl" "setfd" "br0" "inf")
                   (list "brctl" "setageing" "br0" "infinity") (list "brctl" "setageing" "br0" ".")))
    (lx-case (list (list "brctl" "addbr" "br0") (list "brctl" "addif" "br0" "bd0") (list "brctl" "addif" "br0" "bd1")
                   (list "brctl" "setbridgeprio" "br0" "100") (list "brctl" "setbridgeprio" "br0" "x")
                   (list "brctl" "setpathcost" "br0" "bd0" "50") (list "brctl" "setportprio" "nosuch" "bd1" "3")
                   (list "brctl" "setpathcost" "br0" "nosuch" "5") (list "brctl" "setpathcost" "br0" "bd0" "-2")))
    (lx-case (list (list "brctl" "setageing" "nosuch" "5") (list "brctl" "stp" "nosuch" "on"))))
```
---
```output
same
same
same
same
same
```

## showmacs and showstp

### a bridge's addresses and STP, its ports', none for a bridge not there

```cu
(do (lx-case (list (list "brctl" "addbr" "br0") (list "brctl" "showmacs" "br0") (list "brctl" "showstp" "br0")))
    (lx-case (list (list "brctl" "addbr" "br0") (list "brctl" "addif" "br0" "bd0") (list "brctl" "addif" "br0" "bd1")
                   (list "brctl" "setportprio" "br0" "bd1" "3") (list "brctl" "setbridgeprio" "br0" "100")
                   (list "brctl" "showmacs" "br0") (list "brctl" "showstp" "br0")))
    (lx-case (list (list "brctl" "showmacs" "nosuch") (list "brctl" "showstp" "nosuch") (list "brctl" "showstp" "bd0"))))
```
---
```output
same
same
same
```

## the usage

### none, a command not known, too few words

```cu
(lx-case (list (list "brctl") (list "brctl" "frob") (list "brctl" "addbr") (list "brctl" "addif" "br0")
               (list "brctl" "stp" "br0") (list "brctl" "setpathcost" "br0" "bd0") (list "brctl" "showmacs")))
```
---
```output
same
```
