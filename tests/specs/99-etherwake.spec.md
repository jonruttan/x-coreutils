# @weight 1

busybox's ether-wake (networking/ether-wake.c) reads its options and its
password before it opens its packet socket, so those are tested here, and
the socket Darwin refuses; the packets are tested as root in the Linux
leg.

## the fixture

### a run of ether-wake, what it writes and its status

```cu
(do (def ew-f (fn (_ n) (string-append "/tmp/x-cu-ew." n)))
    (def ew-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (ew-f "out"))) (ee (file-open-write (ew-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (ew-f "out")) "stderr:\n"
                                              (file-read-all (ew-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the usage

### no MAC, two, an option not known

```cu
(do (ew-show (list "ether-wake"))
    (ew-show (list "ether-wake" "02:00:00:00:00:01" "02:00:00:00:00:02"))
    (ew-show (list "ether-wake" "-x" "02:00:00:00:00:01")))
```
---
```output
stderr:
Usage: ether-wake [-b] [-i IFACE] [-p aa:bb:cc:dd[:ee:ff]/a.b.c.d] MAC

Send a magic packet to wake up sleeping machines.
MAC must be a station address (00:11:22:33:44:55) or
a hostname with a known 'ethers' entry.

	-b		Broadcast the packet
	-i IFACE	Interface to use (default eth0)
	-p PASSWORD	Append four or six byte PASSWORD to the packet
status 1
stderr:
Usage: ether-wake [-b] [-i IFACE] [-p aa:bb:cc:dd[:ee:ff]/a.b.c.d] MAC

Send a magic packet to wake up sleeping machines.
MAC must be a station address (00:11:22:33:44:55) or
a hostname with a known 'ethers' entry.

	-b		Broadcast the packet
	-i IFACE	Interface to use (default eth0)
	-p PASSWORD	Append four or six byte PASSWORD to the packet
status 1
stderr:
ether-wake: unrecognized option: x
Usage: ether-wake [-b] [-i IFACE] [-p aa:bb:cc:dd[:ee:ff]/a.b.c.d] MAC

Send a magic packet to wake up sleeping machines.
MAC must be a station address (00:11:22:33:44:55) or
a hostname with a known 'ethers' entry.

	-b		Broadcast the packet
	-i IFACE	Interface to use (default eth0)
	-p PASSWORD	Append four or six byte PASSWORD to the packet
status 1
```

## the socket

### refused, a password not read said first

```cu
(do (ew-show (list "ether-wake" "02:00:00:00:00:01"))
    (ew-show (list "ether-wake" "-b" "-i" "en0" "-p" "1.2" "02:00:00:00:00:01")))
```
---
```output
stderr:
ether-wake: socket(AF_PACKET,3,0): Address family not supported by protocol family
status 1
stderr:
ether-wake: can't read Wake-On-LAN pass
ether-wake: socket(AF_PACKET,3,0): Address family not supported by protocol family
status 1
```
