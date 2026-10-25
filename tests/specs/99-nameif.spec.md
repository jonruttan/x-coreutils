# @weight 1

busybox's nameif (networking/nameif.c) reads every entry it is given before
it opens /proc/net/dev, so the selectors and the file are tested here and
the end of each run is the file it cannot open; the renames are tested as
root in the Linux leg.

## the fixture

### a run of nameif, what it writes and its status

```cu
(do (def ni-f (fn (_ n) (string-append "/tmp/x-cu-ni." n)))
    (def ni-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (ni-f "out"))) (ee (file-open-write (ni-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (string-concat (list (file-read-all (ni-f "out")) "stderr:\n"
                                              (file-read-all (ni-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the operands

### an odd count is the usage

```cu
(do (ni-show (list "nameif" "a"))
    (ni-show (list "nameif" "a" "02:00:00:00:06:01" "b")))
```
---
```output
stderr:
Usage: nameif [-s] [-c FILE] [IFNAME SELECTOR]...

Rename network interface while it in the down state.
The device matched by SELECTOR is renamed to IFNAME.
SELECTOR can be a combination of:
	driver=STRING
	bus=STRING
	phy_address=NUM
	[mac=]XX:XX:XX:XX:XX:XX

	-c FILE	Configuration file (default: /etc/mactab)
	-s	Log to syslog
status 1
stderr:
Usage: nameif [-s] [-c FILE] [IFNAME SELECTOR]...

Rename network interface while it in the down state.
The device matched by SELECTOR is renamed to IFNAME.
SELECTOR can be a combination of:
	driver=STRING
	bus=STRING
	phy_address=NUM
	[mac=]XX:XX:XX:XX:XX:XX

	-c FILE	Configuration file (default: /etc/mactab)
	-s	Log to syslog
status 1
```

### a selector that will not parse, a name too long, none at all

```cu
(do (ni-show (list "nameif" "abcdefghijklmnop" "02:00:00:00:06:01"))
    (ni-show (list "nameif" "a" "zz"))
    (ni-show (list "nameif" "a" ""))
    (ni-show (list "nameif" "a" "  "))
    (ni-show (list "nameif" "a" "phyaddr=x"))
    (ni-show (list "nameif" "a" "mac=02:00:00:00:06:0g"))
    (ni-show (list "nameif" "a" "02:00:00:00:06")))
```
---
```output
stderr:
nameif: interface name 'abcdefghijklmnop' too long
status 1
stderr:
nameif: can't parse zz
status 1
stderr:
nameif: no selectors found for a
status 1
stderr:
nameif: no selectors found for a
status 1
stderr:
nameif: invalid number 'x'
status 1
stderr:
nameif: can't parse mac=02:00:00:00:06:0g
status 1
stderr:
nameif: can't parse 02:00:00:00:06
status 1
```

### addresses as strtoul reads them, each word its own

```cu
(do (ni-show (list "nameif" "a" "0x2:00:00:00:06:03"))
    (ni-show (list "nameif" "a" " 2:+0:00:00:06:03"))
    (ni-show (list "nameif" "a" ":::::"))
    (ni-show (list "nameif" "a" "2:0:0:0:6:100"))
    (ni-show (list "nameif" "a" "driver=veth bus= phyaddr=0 mac=02:00:00:00:06:03")))
```
---
```output
stderr:
nameif: can't open '/proc/net/dev': No such file or directory
status 1
stderr:
nameif: can't open '/proc/net/dev': No such file or directory
status 1
stderr:
nameif: can't open '/proc/net/dev': No such file or directory
status 1
stderr:
nameif: can't parse 2:0:0:0:6:100
status 1
stderr:
nameif: can't open '/proc/net/dev': No such file or directory
status 1
```

## the file

### none is said and passed over; a line short of its selector the same

```cu
(do (ni-show (list "nameif"))
    (ni-show (list "nameif" "-c" "/tmp/x-cu-ni.none"))
    (file-write-all (ni-f "tab") "# c\nrn8 02:00:00:00:06:03 # x\n\nlonely\n  rn9\tdriver=dummy\n")
    (ni-show (list "nameif" "-c" (ni-f "tab")))
    (file-write-all (ni-f "tab") "a zz\n")
    (ni-show (list "nameif" "-c" (ni-f "tab")))
    (ni-show (list "nameif" "-s" "-c" (ni-f "tab") "a" "driver=x")))
```
---
```output
stderr:
nameif: /etc/mactab: No such file or directory
nameif: can't open '/proc/net/dev': No such file or directory
status 1
stderr:
nameif: /tmp/x-cu-ni.none: No such file or directory
nameif: can't open '/proc/net/dev': No such file or directory
status 1
stderr:
nameif: bad line 4: 1 tokens found, 2 needed
nameif: can't open '/proc/net/dev': No such file or directory
status 1
stderr:
nameif: can't parse zz
status 1
stderr:
nameif: can't open '/proc/net/dev': No such file or directory
status 1
```
