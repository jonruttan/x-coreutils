# @weight 1

busybox's syslogd (sysklogd/syslogd.c) reads its options and its config
before it binds /dev/log, and refuses what it cannot read there, so those
refusals are tested here; what it logs is tested as root in the Linux leg,
against busybox's own.

## the fixture

### a run of syslogd, what it writes and its status

```cu
(do (def sl-f (fn (_ n) (string-append "/tmp/x-cu-sl." n)))
    (def sl-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (sl-f "out"))) (ee (file-open-write (sl-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (sl-f "out")) "stderr:\n"
                                              (file-read-all (sl-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (def sl-conf (fn (_ text) (do (file-write-all (sl-f "conf") text) (sl-f "conf"))))
    (display "made"))
```
---
    made

## the options

### an option syslogd does not take

```cu
(sl-show (list "syslogd" "-Z"))
```
---
```output
stderr:
syslogd: unrecognized option: Z
Usage: syslogd [OPTIONS]

System logging utility

	-n		Run in foreground
	-R HOST[:PORT]	Log to HOST:PORT (default PORT:514)
	-L		Log locally and via network (default is network only if -R)
	-C[size_kb]	Log to shared mem buffer (use logread to read it)
	-K		Log to kernel printk buffer (use dmesg to read it)
	-O FILE		Log to FILE (default: /var/log/messages, stdout if -)
	-s SIZE		Max size (KB) before rotation (default 200KB, 0=off)
	-b N		N rotated logs to keep (default 1, max 99, 0=purge)
	-l N		Log only messages more urgent than prio N (1-8)
	-S		Smaller output
	-t		Strip client-generated timestamps
	-D		Drop duplicates
	-f FILE		Use FILE as config (default:/etc/syslog.conf)
status 1
```

### an operand, and -C's size as a word of its own, which is one

```cu
(do (sl-show (list "syslogd" "-n" "x"))
    (sl-show (list "syslogd" "-n" "-C" "3")))
```
---
```output
stderr:
Usage: syslogd [OPTIONS]

System logging utility

	-n		Run in foreground
	-R HOST[:PORT]	Log to HOST:PORT (default PORT:514)
	-L		Log locally and via network (default is network only if -R)
	-C[size_kb]	Log to shared mem buffer (use logread to read it)
	-K		Log to kernel printk buffer (use dmesg to read it)
	-O FILE		Log to FILE (default: /var/log/messages, stdout if -)
	-s SIZE		Max size (KB) before rotation (default 200KB, 0=off)
	-b N		N rotated logs to keep (default 1, max 99, 0=purge)
	-l N		Log only messages more urgent than prio N (1-8)
	-S		Smaller output
	-t		Strip client-generated timestamps
	-D		Drop duplicates
	-f FILE		Use FILE as config (default:/etc/syslog.conf)
status 1
stderr:
Usage: syslogd [OPTIONS]

System logging utility

	-n		Run in foreground
	-R HOST[:PORT]	Log to HOST:PORT (default PORT:514)
	-L		Log locally and via network (default is network only if -R)
	-C[size_kb]	Log to shared mem buffer (use logread to read it)
	-K		Log to kernel printk buffer (use dmesg to read it)
	-O FILE		Log to FILE (default: /var/log/messages, stdout if -)
	-s SIZE		Max size (KB) before rotation (default 200KB, 0=off)
	-b N		N rotated logs to keep (default 1, max 99, 0=purge)
	-l N		Log only messages more urgent than prio N (1-8)
	-S		Smaller output
	-t		Strip client-generated timestamps
	-D		Drop duplicates
	-f FILE		Use FILE as config (default:/etc/syslog.conf)
status 1
```

### the numbers, out of range and not numbers

A sign, a trailing letter and a value past 2^32-1 are not numbers; -C's
size is attached.

```cu
(do (map (fn (_ a) (sl-show (pair "syslogd" (pair "-n" a))))
         (list (list "-l" "9") (list "-l" "0") (list "-l" "x") (list "-l" "1x") (list "-l" "-1")
               (list "-l" "+1") (list "-l" "99999999999") (list "-C3") (list "-Cx") (list "-s" "x")
               (list "-b" "100") (list "-s" "2097152")))
    ())
```
---
```output
stderr:
syslogd: number 9 is not in 1..8 range
status 1
stderr:
syslogd: number 0 is not in 1..8 range
status 1
stderr:
syslogd: invalid number 'x'
status 1
stderr:
syslogd: invalid number '1x'
status 1
stderr:
syslogd: invalid number '-1'
status 1
stderr:
syslogd: invalid number '+1'
status 1
stderr:
syslogd: invalid number '99999999999'
status 1
stderr:
syslogd: number 3 is not in 4..2097151 range
status 1
stderr:
syslogd: invalid number 'x'
status 1
stderr:
syslogd: invalid number 'x'
status 1
stderr:
syslogd: number 100 is not in 0..99 range
status 1
stderr:
syslogd: number 2097152 is not in 0..2097151 range
status 1
```

## the config

### a -f file that is not there

```cu
(sl-show (list "syslogd" "-n" "-f" "/tmp/x-cu-sl.none"))
```
---
```output
stderr:
syslogd: can't open '/tmp/x-cu-sl.none': No such file or directory
status 1
```

### a line of one word; a line of three

Comments and empty lines are counted.

```cu
(do (sl-show (list "syslogd" "-n" "-f" (sl-conf "# c\n\nkern.info\n")))
    (sl-show (list "syslogd" "-n" "-f" (sl-conf "kern.info /tmp/a extra\n"))))
```
---
```output
stderr:
syslogd: bad line 3: 1 tokens found, 2 needed
status 1
stderr:
syslogd: error in '/tmp/x-cu-sl.conf' at line 1
status 1
```

### selectors that name nothing

A priority and a facility the C library does not name, one without its
dot, one after a ; without its dot, names in capitals, and no facility.

```cu
(do (map (fn (_ text) (sl-show (list "syslogd" "-n" "-f" (sl-conf text))))
         (list "kern.bogus /tmp/a\n" "bogus.info /tmp/a\n" "kern /tmp/a\n" "kern.info;mail /tmp/a\n"
               "mark.info /tmp/a\nKERN.info /tmp/b\n" "kern.info /tmp/a # c\n.info /tmp/b\n"))
    ())
```
---
```output
stderr:
syslogd: error in '/tmp/x-cu-sl.conf' at line 1
status 1
stderr:
syslogd: error in '/tmp/x-cu-sl.conf' at line 1
status 1
stderr:
syslogd: error in '/tmp/x-cu-sl.conf' at line 1
status 1
stderr:
syslogd: error in '/tmp/x-cu-sl.conf' at line 1
status 1
stderr:
syslogd: error in '/tmp/x-cu-sl.conf' at line 2
status 1
stderr:
syslogd: error in '/tmp/x-cu-sl.conf' at line 2
status 1
```
