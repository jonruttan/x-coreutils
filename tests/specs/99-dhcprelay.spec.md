# @weight 1

busybox's dhcprelay (networking/udhcp/dhcprelay.c) reads its words before
it opens a socket, so those are tested here; the relaying is tested as
root in the Linux leg, against busybox's own.

## the fixture

### a run of dhcprelay, what it writes and its status

```cu
(do (def dr-f (fn (_ n) (string-append "/tmp/x-cu-dr." n)))
    (def dr-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (dr-f "out"))) (ee (file-open-write (dr-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (dr-f "out")) "stderr:\n"
                                              (file-read-all (dr-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the words

### too few, --help, and a server address that is not one

```cu
(do (dr-show (list "dhcprelay"))
    (dr-show (list "dhcprelay" "eth1"))
    (dr-show (list "dhcprelay" "--help"))
    (dr-show (list "dhcprelay" "eth1" "eth0" "10.0.x.1")))
```
---
```output
stderr:
Usage: dhcprelay CLIENT_IFACE[,CLIENT_IFACE2]... SERVER_IFACE [SERVER_IP]

Relay DHCP requests between clients and server.
Without SERVER_IP, requests are broadcast on SERVER_IFACE.
status 1
stderr:
Usage: dhcprelay CLIENT_IFACE[,CLIENT_IFACE2]... SERVER_IFACE [SERVER_IP]

Relay DHCP requests between clients and server.
Without SERVER_IP, requests are broadcast on SERVER_IFACE.
status 1
Usage: dhcprelay CLIENT_IFACE[,CLIENT_IFACE2]... SERVER_IFACE [SERVER_IP]

Relay DHCP requests between clients and server.
Without SERVER_IP, requests are broadcast on SERVER_IFACE.
stderr:
status 0
stderr:
dhcprelay: bad server IP: Invalid argument
status 1
```
