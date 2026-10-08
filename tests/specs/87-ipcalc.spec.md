# @weight 1

ipcalc as busybox's.  Every expectation is busybox's own output for the same
arguments, from a busybox built from its source: stdout with a `|` at the end
of each line, then stderr less the banner line busybox's usage text starts
with, then the status.

## the fixture

### a run of an applet, with its stdout, stderr and status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-ipcalc && mkdir -p /tmp/x-cu-ipcalc")) (def nf (fn (_ n) (string-append "/tmp/x-cu-ipcalc/" n))) (def run (fn (_ argv in) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv in)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (Str8 replace "\n" "|\n" (file-read-all (nf ".out"))) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n")))))))) (display "made"))
```
---
    made

## ipcalc

### class A's netmask

```cu
(run (list "ipcalc" "-m" "10.1.2.3") "")
```
---
```output
NETMASK=255.0.0.0|
stderr:
status 0
```

### class B's netmask

```cu
(run (list "ipcalc" "-m" "172.16.5.4") "")
```
---
```output
NETMASK=255.255.0.0|
stderr:
status 0
```

### class C's netmask

```cu
(run (list "ipcalc" "-m" "192.168.1.1") "")
```
---
```output
NETMASK=255.255.255.0|
stderr:
status 0
```

### an address past class C takes C's netmask

```cu
(run (list "ipcalc" "-m" "224.0.0.1") "")
```
---
```output
NETMASK=255.255.255.0|
stderr:
status 0
```

### every line for an address with a prefix

```cu
(run (list "ipcalc" "-bnmp" "192.168.1.77/26") "")
```
---
```output
NETMASK=255.255.255.192|
BROADCAST=192.168.1.127|
NETWORK=192.168.1.64|
PREFIX=26|
stderr:
status 0
```

### a netmask given

```cu
(run (list "ipcalc" "-bn" "10.0.0.5" "255.255.255.0") "")
```
---
```output
BROADCAST=10.0.0.255|
NETWORK=10.0.0.0|
stderr:
status 0
```

### the prefix of a netmask

```cu
(run (list "ipcalc" "-p" "10.0.0.5" "255.255.240.0") "")
```
---
```output
PREFIX=20|
stderr:
status 0
```

### the prefix of a netmask that is not one run of bits

```cu
(run (list "ipcalc" "-p" "10.0.0.5" "255.0.255.0") "")
```
---
```output
PREFIX=16|
stderr:
status 0
```

### prefix 0

```cu
(run (list "ipcalc" "-bnp" "10.1.2.3/0") "")
```
---
```output
BROADCAST=255.255.255.255|
NETWORK=0.0.0.0|
PREFIX=0|
stderr:
status 0
```

### prefix 32

```cu
(run (list "ipcalc" "-bnp" "10.1.2.3/32") "")
```
---
```output
BROADCAST=10.1.2.3|
NETWORK=10.1.2.3|
PREFIX=32|
stderr:
status 0
```

### two parts: the last fills three bytes

```cu
(run (list "ipcalc" "-bn" "10.1") "")
```
---
```output
BROADCAST=10.255.255.255|
NETWORK=10.0.0.0|
stderr:
status 0
```

### hex and octal parts

```cu
(run (list "ipcalc" "-bn" "0x0a.010.1.2") "")
```
---
```output
BROADCAST=10.255.255.255|
NETWORK=10.0.0.0|
stderr:
status 0
```

### three parts: the last fills two bytes

```cu
(run (list "ipcalc" "-bn" "10.1.2") "")
```
---
```output
BROADCAST=10.255.255.255|
NETWORK=10.0.0.0|
stderr:
status 0
```

### the long options

```cu
(run (list "ipcalc" "--broadcast" "--network" "--netmask" "--prefix" "10.9.8.7/12") "")
```
---
```output
NETMASK=255.240.0.0|
BROADCAST=10.15.255.255|
NETWORK=10.0.0.0|
PREFIX=12|
stderr:
status 0
```

### a slash with nothing after it

```cu
(run (list "ipcalc" "-m" "1.2.3.4/") "")
```
---
```output
NETMASK=255.0.0.0|
stderr:
status 0
```

### a part past 255

```cu
(run (list "ipcalc" "-m" "300.1.2.3") "")
```
---
```output
stderr:
ipcalc: bad IP address: 300.1.2.3
status 1
```

### a prefix past 32

```cu
(run (list "ipcalc" "-m" "1.2.3.4/33") "")
```
---
```output
stderr:
ipcalc: number 33 is not in 0..32 range
status 1
```

### a prefix that is not a number

```cu
(run (list "ipcalc" "-m" "1.2.3.4/x") "")
```
---
```output
stderr:
ipcalc: invalid number 'x'
status 1
```

### a prefix and a netmask

```cu
(run (list "ipcalc" "-b" "1.2.3.4/24" "255.0.0.0") "")
```
---
```output
stderr:
ipcalc: use prefix or netmask, not both
status 1
```

### a netmask that is not an address

```cu
(run (list "ipcalc" "-b" "1.2.3.4" "255.0.0.300") "")
```
---
```output
stderr:
ipcalc: bad netmask: 255.0.0.300
status 1
```

### an octal part with an 8 in it

```cu
(run (list "ipcalc" "-m" "08.1.2.3") "")
```
---
```output
stderr:
ipcalc: bad IP address: 08.1.2.3
status 1
```

### five parts

```cu
(run (list "ipcalc" "-m" "1.2.3.4.5") "")
```
---
```output
stderr:
ipcalc: bad IP address: 1.2.3.4.5
status 1
```

### -s keeps the error to the status

```cu
(run (list "ipcalc" "-s" "-m" "300.1.2.3") "")
```
---
```output
stderr:
status 1
```

### -s does not keep the usage text

```cu
(run (list "ipcalc" "-s" "1.2.3.4") "")
```
---
```output
stderr:
Usage: ipcalc [-bnmphs] ADDRESS[/PREFIX] [NETMASK]

Calculate and display network settings from IP address

	-b	Broadcast address
	-n	Network address
	-m	Default netmask for IP
	-p	Prefix for IP/NETMASK
	-h	Resolved host name
	-s	No error messages
status 1
```

### no option to say what to show

```cu
(run (list "ipcalc" "1.2.3.4") "")
```
---
```output
stderr:
Usage: ipcalc [-bnmphs] ADDRESS[/PREFIX] [NETMASK]

Calculate and display network settings from IP address

	-b	Broadcast address
	-n	Network address
	-m	Default netmask for IP
	-p	Prefix for IP/NETMASK
	-h	Resolved host name
	-s	No error messages
status 1
```

### -m with a netmask too

```cu
(run (list "ipcalc" "-m" "1.2.3.4" "255.0.0.0") "")
```
---
```output
stderr:
Usage: ipcalc [-bnmphs] ADDRESS[/PREFIX] [NETMASK]

Calculate and display network settings from IP address

	-b	Broadcast address
	-n	Network address
	-m	Default netmask for IP
	-p	Prefix for IP/NETMASK
	-h	Resolved host name
	-s	No error messages
status 1
```

### no address

```cu
(run (list "ipcalc" "-b") "")
```
---
```output
stderr:
Usage: ipcalc [-bnmphs] ADDRESS[/PREFIX] [NETMASK]

Calculate and display network settings from IP address

	-b	Broadcast address
	-n	Network address
	-m	Default netmask for IP
	-p	Prefix for IP/NETMASK
	-h	Resolved host name
	-s	No error messages
status 1
```

### three operands

```cu
(run (list "ipcalc" "-b" "1" "2" "3") "")
```
---
```output
stderr:
Usage: ipcalc [-bnmphs] ADDRESS[/PREFIX] [NETMASK]

Calculate and display network settings from IP address

	-b	Broadcast address
	-n	Network address
	-m	Default netmask for IP
	-p	Prefix for IP/NETMASK
	-h	Resolved host name
	-s	No error messages
status 1
```

### -h: the loopback's name

```cu
(run (list "ipcalc" "-h" "127.0.0.1") "")
```
---
```output
HOSTNAME=localhost|
stderr:
status 0
```
