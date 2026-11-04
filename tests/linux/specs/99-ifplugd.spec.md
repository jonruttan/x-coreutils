# @weight 2
# @timeout-scale 10

busybox's ifplugd (networking/ifplugd.c), run as root.  A veth pair, pd0
and pd1, lies in the namespace pd, which this file's process enters; each
case runs the bundle's ifplugd on pd0 and then busybox-extra's, while the
case's steps change pd1 (pd0's link follows its peer), make and remove
interfaces, and signal the run.  The script logs each run with its words
and IFPLUGD_PREVIOUS and IFPLUGD_CURRENT, and fails where a file
/tmp/pd-fail-ACTION is there.  What the run wrote, less its banner line,
its status and the script's log are compared.

## the comparison

### ours against busybox's, as pd1 comes and goes

```cu
(do (def pd-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (pd-sh (Str8 join "\n" (list
      "ip2 netns add pd"
      "ip2 link add pd0 netns pd type veth peer name pd1 netns pd"
      "cat > /tmp/pd-script.sh <<'EOF'"
      "#!/bin/sh"
      "echo \"$# $* previous=$IFPLUGD_PREVIOUS current=$IFPLUGD_CURRENT\" >> /tmp/pd-script.log"
      "[ ! -e /tmp/pd-fail-$2 ] || exit 3"
      "EOF"
      "chmod +x /tmp/pd-script.sh")))
    (def pd-in (= (in-call (cu-ptr-call (cu-libc-sym "setns")
                    (in-call (cu-ptr-call (cu-libc-sym "open") "/var/run/netns/pd" 0)) 1073741824)) 0))
    (def pd-run (fn (_ side args)
      (do (def pid (sys-fork))
          (when (= pid 0)
            (guard (e (do (display e) (display "\n") (sys-exit 99)))
              (let ((ee (file-open-write "/tmp/pd-err")))
                (do (sys-dup2 ee 1) (sys-dup2 ee 2)
                    (if (string=? side "ours")
                      (sys-exit (cu-run (pair "ifplugd" args) ""))
                      (do (sys-exec "/usr/local/bin/busybox-extra" (pair "ifplugd" args)) (sys-exit 98)))))))
          pid)))
    ; a step: a shell command, or (SIGNAL) for the run
    (def pd-step (fn (_ pid s)
      (if (pair? s) (do (sys-kill pid (first s)) (pd-sh "sleep 1")) (pd-sh s))))
    (def pd-side (fn (_ side args steps)
      (do (pd-sh "rm -f /tmp/pd-err /tmp/pd-fail-* /var/run/ifplugd.*.pid; : > /tmp/pd-script.log; ip2 link set pd0 down; ip2 link set pd1 down")
          (Heap collect)
          (def pid (pd-run side args))
          (pd-sh "sleep 1.5")
          (map (fn (_ s) (pd-step pid s)) steps)
          ; a run still going ten seconds after the steps is killed
          (pd-sh (%str-concat (list "p=" (cu-int->str pid) "; i=0; while [ -e /proc/$p ] && ! grep -q ') Z' /proc/$p/stat"
                                    " && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done; [ $i -lt 100 ] || kill -9 $p")))
          (def st (Sys wait pid))
          (pd-sh "sed '/: started: /d' /tmp/pd-err > /tmp/pd-err2")
          (%str-concat (list "stderr:\n" (file-read-all "/tmp/pd-err2")
                             "status " (cu-int->str st) "\n"
                             "script:\n" (file-read-all "/tmp/pd-script.log"))))))
    (def pd-case (fn (_ args steps)
      (let ((a (pd-side "ours" args steps)) (b (pd-side "bb" args steps)))
        (display (if (string=? a b) (string-append a "busybox: same\n")
                   (%str-concat (list "ours:\n" a "busybox:\n" b)))))))
    (def pd-args (list "-n" "-s" "-i" "pd0" "-r" "/tmp/pd-script.sh" "-u" "0" "-d" "0"))
    (display (if pd-in "made" "no namespace")))
```
---
    made

## the link

### down at the start, up, down, then SIGTERM

pd0 is brought up; its link is down until pd1 is up.  The ethtool ioctl
answers first.  A change that holds runs the script at once with -u 0
and -d 0; a link down at SIGTERM runs nothing more.

```cu
(pd-case pd-args (list "ip2 link set pd1 up; sleep 2" "ip2 link set pd1 down; sleep 2" (list 15)))
```
---
```output
stderr:
ifplugd(pd0): upping interface
ifplugd(pd0): using SIOCETHTOOL detection mode
ifplugd(pd0): link is down
ifplugd(pd0): link is up
ifplugd(pd0): executing '/tmp/pd-script.sh pd0 up'
ifplugd(pd0): exit code: 0
ifplugd(pd0): link is down
ifplugd(pd0): executing '/tmp/pd-script.sh pd0 down'
ifplugd(pd0): exit code: 0
ifplugd(pd0): exiting
status 1
script:
2 pd0 up previous=down current=up
2 pd0 down previous=up current=down
busybox: same
```

### up, then SIGTERM, with -x

A link up at SIGTERM runs "down" before the end; -x adds its word to each run.

```cu
(pd-case (append pd-args (list "-x" "extra")) (list "ip2 link set pd1 up; sleep 2" (list 15)))
```
---
```output
stderr:
ifplugd(pd0): upping interface
ifplugd(pd0): using SIOCETHTOOL detection mode
ifplugd(pd0): link is down
ifplugd(pd0): link is up
ifplugd(pd0): executing '/tmp/pd-script.sh pd0 up'
ifplugd(pd0): exit code: 0
ifplugd(pd0): executing '/tmp/pd-script.sh pd0 down'
ifplugd(pd0): exit code: 0
ifplugd(pd0): exiting
status 1
script:
3 pd0 up extra previous=down current=up
3 pd0 down extra previous=down current=up
busybox: same
```

### -p and -q: no script at the start or the end

```cu
(pd-case (append pd-args (list "-p" "-q")) (list "ip2 link set pd1 up; sleep 0.5" "sleep 1" (list 15)))
```
---
```output
stderr:
ifplugd(pd0): upping interface
ifplugd(pd0): using SIOCETHTOOL detection mode
ifplugd(pd0): link is down
ifplugd(pd0): link is up
ifplugd(pd0): executing '/tmp/pd-script.sh pd0 up'
ifplugd(pd0): exit code: 0
ifplugd(pd0): exiting
status 1
script:
2 pd0 up previous=down current=up
busybox: same
```

### -l: the script at the start whatever the link

```cu
(pd-case (append pd-args (list "-l")) (list "sleep 1" (list 15)))
```
---
```output
stderr:
ifplugd(pd0): upping interface
ifplugd(pd0): using SIOCETHTOOL detection mode
ifplugd(pd0): link is down
ifplugd(pd0): executing '/tmp/pd-script.sh pd0 down'
ifplugd(pd0): exit code: 0
ifplugd(pd0): exiting
status 1
script:
2 pd0 down previous=error current=down
busybox: same
```

### SIGQUIT ends the run with no script; SIGHUP does not end it

```cu
(pd-case pd-args (list "ip2 link set pd1 up; sleep 0.5" (list 1) "sleep 1" (list 3)))
```
---
```output
stderr:
ifplugd(pd0): upping interface
ifplugd(pd0): using SIOCETHTOOL detection mode
ifplugd(pd0): link is down
ifplugd(pd0): link is up
ifplugd(pd0): executing '/tmp/pd-script.sh pd0 up'
ifplugd(pd0): exit code: 0
ifplugd(pd0): exiting
status 1
script:
2 pd0 up previous=down current=up
busybox: same
```

### a link that comes back within -d runs nothing

```cu
(pd-case (list "-n" "-s" "-i" "pd0" "-r" "/tmp/pd-script.sh" "-u" "0" "-d" "3")
         (list "ip2 link set pd1 up; sleep 2" "ip2 link set pd1 down; sleep 1.2" "ip2 link set pd1 up; sleep 4" (list 15)))
```
---
```output
stderr:
ifplugd(pd0): upping interface
ifplugd(pd0): using SIOCETHTOOL detection mode
ifplugd(pd0): link is down
ifplugd(pd0): link is up
ifplugd(pd0): executing '/tmp/pd-script.sh pd0 up'
ifplugd(pd0): exit code: 0
ifplugd(pd0): link is down
ifplugd(pd0): link is up
ifplugd(pd0): executing '/tmp/pd-script.sh pd0 down'
ifplugd(pd0): exit code: 0
ifplugd(pd0): exiting
status 1
script:
2 pd0 up previous=down current=up
2 pd0 down previous=down current=up
busybox: same
```

## the script

### a script that fails ends the run; -I goes on

```cu
(do (pd-case pd-args (list ": > /tmp/pd-fail-up; ip2 link set pd1 up; sleep 2" (list 15)))
    (pd-case (append pd-args (list "-I")) (list ": > /tmp/pd-fail-up; ip2 link set pd1 up; sleep 2" (list 15))))
```
---
```output
stderr:
ifplugd(pd0): upping interface
ifplugd(pd0): using SIOCETHTOOL detection mode
ifplugd(pd0): link is down
ifplugd(pd0): link is up
ifplugd(pd0): executing '/tmp/pd-script.sh pd0 up'
ifplugd(pd0): exit code: 3
ifplugd(pd0): exiting
status 1
script:
2 pd0 up previous=down current=up
busybox: same
stderr:
ifplugd(pd0): upping interface
ifplugd(pd0): using SIOCETHTOOL detection mode
ifplugd(pd0): link is down
ifplugd(pd0): link is up
ifplugd(pd0): executing '/tmp/pd-script.sh pd0 up'
ifplugd(pd0): exit code: 3
ifplugd(pd0): executing '/tmp/pd-script.sh pd0 down'
ifplugd(pd0): exit code: 0
ifplugd(pd0): exiting
status 1
script:
2 pd0 up previous=down current=up
2 pd0 down previous=down current=up
busybox: same
```

### a script that cannot be run

```cu
(pd-case (list "-n" "-s" "-i" "pd0" "-r" "/tmp/pd-none.sh") (list "ip2 link set pd1 up; sleep 2" (list 15)))
```
---
```output
stderr:
ifplugd(pd0): upping interface
ifplugd(pd0): using SIOCETHTOOL detection mode
ifplugd(pd0): link is down
ifplugd(pd0): link is up
ifplugd(pd0): executing '/tmp/pd-none.sh pd0 up'
ifplugd(pd0): exit code: 255
ifplugd(pd0): exiting
status 1
script:
busybox: same
```

## the methods

### -m iff with -a and -A: the interface left down until it is brought up

IFF_RUNNING is never set on an interface down, so its link reads down.

```cu
(pd-case (append pd-args (list "-m" "iff" "-a" "-A"))
         (list "ip2 link set pd1 up; sleep 2" "ip2 link set pd0 up; sleep 2" (list 15)))
```
---
```output
stderr:
ifplugd(pd0): link is down
ifplugd(pd0): link is up
ifplugd(pd0): executing '/tmp/pd-script.sh pd0 up'
ifplugd(pd0): exit code: 0
ifplugd(pd0): executing '/tmp/pd-script.sh pd0 down'
ifplugd(pd0): exit code: 0
ifplugd(pd0): exiting
status 1
script:
2 pd0 up previous=down current=up
2 pd0 down previous=down current=up
busybox: same
```

### -m mii, which a veth does not answer; -f reads that as down, -F as up

```cu
(do (pd-case (append pd-args (list "-m" "mii")) (list "sleep 1"))
    (pd-case (append pd-args (list "-m" "mii" "-f")) (list "sleep 1" (list 15)))
    (pd-case (append pd-args (list "-m" "priv" "-F")) (list "sleep 1" (list 15))))
```
---
```output
stderr:
ifplugd(pd0): upping interface
ifplugd(pd0): SIOCGMIIPHY failed: Not supported
ifplugd(pd0): exiting
status 1
script:
busybox: same
stderr:
ifplugd(pd0): upping interface
ifplugd(pd0): SIOCGMIIPHY failed: Not supported
ifplugd(pd0): link is down
ifplugd(pd0): SIOCGMIIPHY failed: Not supported
ifplugd(pd0): SIOCGMIIPHY failed: Not supported
ifplugd(pd0): exiting
status 1
script:
busybox: same
stderr:
ifplugd(pd0): upping interface
ifplugd(pd0): SIOCDEVPRIVATE failed: Not supported
ifplugd(pd0): link is up
ifplugd(pd0): executing '/tmp/pd-script.sh pd0 up'
ifplugd(pd0): exit code: 0
ifplugd(pd0): SIOCDEVPRIVATE failed: Not supported
ifplugd(pd0): SIOCDEVPRIVATE failed: Not supported
ifplugd(pd0): executing '/tmp/pd-script.sh pd0 down'
ifplugd(pd0): exit code: 0
ifplugd(pd0): exiting
status 1
script:
2 pd0 up previous=error current=up
2 pd0 down previous=error current=up
busybox: same
```

## the interface

### an interface that is not there

```cu
(do (pd-case (list "-n" "-s" "-i" "pd9" "-r" "/tmp/pd-script.sh") (list "sleep 1"))
    (pd-case (list "-n" "-s" "-i" "pd9" "-r" "/tmp/pd-script.sh" "-m" "iff") (list "sleep 1")))
```
---
```output
stderr:
ifplugd(pd9): getting interface flags failed: No such device
ifplugd(pd9): exiting
status 1
script:
busybox: same
stderr:
ifplugd(pd9): getting interface flags failed: No such device
ifplugd(pd9): exiting
status 1
script:
busybox: same
```

### -M: waiting for the interface, then following it as it comes and goes

With -a the interface is upped only as it appears, so it and its peer can
be taken down before it is removed: a removal while the peer is up
wakes the poll with the peer's closing, and the ioctls race netlink.

```cu
(pd-case (list "-n" "-s" "-M" "-a" "-i" "pd2" "-r" "/tmp/pd-script.sh" "-u" "0" "-d" "0")
         (list "ip2 link add pd2 type veth peer name pd3; sleep 2" "ip2 link set pd3 up; sleep 2" "ip2 link set pd2 down; ip2 link set pd3 down; sleep 2"
               "ip2 link del pd2; sleep 2"
               (list 15)))
```
---
```output
stderr:
ifplugd(pd2): interface doesn't exist, waiting
ifplugd(pd2): interface appeared
ifplugd(pd2): upping interface
ifplugd(pd2): using SIOCETHTOOL detection mode
ifplugd(pd2): link is up
ifplugd(pd2): executing '/tmp/pd-script.sh pd2 up'
ifplugd(pd2): exit code: 0
ifplugd(pd2): link is down
ifplugd(pd2): executing '/tmp/pd-script.sh pd2 down'
ifplugd(pd2): exit code: 0
ifplugd(pd2): interface disappeared
ifplugd(pd2): exiting
status 1
script:
2 pd2 up previous=down current=up
2 pd2 down previous=up current=down
busybox: same
```

## the daemon

### in the background, its pidfile, a second refused, then -k

The run that goes to the background ends at 0; the pidfile names the
daemon, a second run on the interface is refused, and -k sends the
daemon SIGINT, which runs "down" for a link up.

```cu
(def pd-daemon (fn (_ side)
  (do (pd-sh "rm -f /tmp/pd-err /var/run/ifplugd.*.pid; : > /tmp/pd-script.log; ip2 link set pd0 down; ip2 link set pd1 up")
      (Heap collect)
      (def first-run (Sys wait (pd-run side (list "-s" "-i" "pd0" "-r" "/tmp/pd-script.sh"))))
      (pd-sh "sleep 2")
      (def pidfile (if (file-exists? "/var/run/ifplugd.pd0.pid") "pidfile written" "no pidfile"))
      (def second (Sys wait (pd-run side (list "-n" "-i" "pd0" "-r" "/tmp/pd-script.sh"))))
      (def second-err (file-read-all "/tmp/pd-err"))
      (def kill-run (Sys wait (pd-run side (list "-k" "-i" "pd0"))))
      (pd-sh "sleep 2")
      (%str-concat (list "first status " (cu-int->str first-run) "\n" pidfile "\n"
                         "second status " (cu-int->str second) "\n" second-err
                         "-k status " (cu-int->str kill-run) "\n"
                         (if (file-exists? "/var/run/ifplugd.pd0.pid") "pidfile left\n" "pidfile removed\n")
                         "script:\n" (file-read-all "/tmp/pd-script.log"))))))
(let ((a (pd-daemon "ours")) (b (pd-daemon "bb")))
  (display (if (string=? a b) (string-append a "busybox: same\n") (%str-concat (list "ours:\n" a "busybox:\n" b)))))
```
---
```output
first status 0
pidfile written
second status 1
ifplugd(pd0): daemon already running
-k status 0
pidfile removed
script:
2 pd0 up previous=error current=up
2 pd0 down previous=error current=up
busybox: same
```

### the namespace removed

```cu
(do (pd-sh "ip2 netns del pd; rm -f /tmp/pd-*") (display "removed"))
```
---
    removed
