# @weight 1

busybox's hostname, hostid, mountpoint, mknod, mesg, renice, ts and
sha384sum.  Every expectation is busybox's own output, from a busybox built
from its source, run as an ordinary user, less the banner line its usage text
starts with; a case at the end checks what is the machine's own -- its name,
its id, the time.  A `|` marks the end of each line written to standard
output; `after:` is what a command run after shows.

## the fixture

### a run of an applet in a fresh directory

Each run is in `/tmp/x-cu-si/w`, made afresh: PRE runs before the applet,
with standard input the file IN (`-` for none), and POST after it, both
through the shell.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-si && mkdir -p /tmp/x-cu-si/w")) (def si-f (fn (_ n) (string-append "/tmp/x-cu-si/" n))) (def si-home (Sys getcwd)) (def si-sh (fn (_ cmd out) (proc-run (list "/bin/sh" "-c" (string-concat (list "cd /tmp/x-cu-si/w && { " cmd "; } > " out " 2>&1")))))) (def si-in (fn (_ name) (if (string=? name "-") "" (file-read-all (string-append "/tmp/x-cu-si/w/" name))))) (def si-case (fn (_ fresh in pre post mode argv) (do (if fresh (si-sh "cd /tmp/x-cu-si && rm -rf w && mkdir w" "/dev/null") ()) (if (string=? pre "@") () (si-sh pre "/dev/null")) (def si-stdin (si-in in)) (Sys chdir "/tmp/x-cu-si/w") (sys-dup2 1 9) (sys-dup2 2 8) (def st (let ((oo (file-open-write (si-f "o"))) (ee (file-open-write (si-f "e")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def rs (cu-run argv si-stdin)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) rs))) (Sys chdir si-home) (display (string-concat (list (Str8 replace "\n" "|\n" (file-read-all (si-f "o"))) "stderr:\n" (file-read-all (si-f "e")) "status " (%cu-int->str st) "\n" (if (string=? post "@") "" (do (si-sh post (si-f "p")) (string-append "after:\n" (file-read-all (si-f "p"))))))))))) (display "made"))
```
---
    made

## mountpoint

### / is one, a directory under it not; a file is not a directory, a missing name is said; -q only answers

```cu
(do (si-case #t "-" "mkdir d; : > f" "@" "-" (list "mountpoint" "/")) (si-case #t "-" "mkdir d; : > f" "@" "-" (list "mountpoint" "d")) (si-case #t "-" "mkdir d; : > f" "@" "-" (list "mountpoint" "f")) (si-case #t "-" "@" "@" "-" (list "mountpoint" "nope")) (si-case #t "-" "mkdir d" "@" "-" (list "mountpoint" "-q" "d")) (si-case #t "-" "@" "@" "-" (list "mountpoint" "-q" "/")))
```
---
```output
/ is a mountpoint|
stderr:
status 0
d is not a mountpoint|
stderr:
status 1
stderr:
mountpoint: f: Not a directory
status 1
stderr:
mountpoint: nope: No such file or directory
status 1
stderr:
status 1
stderr:
status 0
```

### -x wants a block device; one name, no more

```cu
(do (si-case #t "-" ": > f" "@" "-" (list "mountpoint" "-x" "f")) (si-case #t "-" "@" "@" "-" (list "mountpoint" "-x" "nope")) (si-case #t "-" "@" "@" "-" (list "mountpoint")) (si-case #t "-" "@" "@" "-" (list "mountpoint" "a" "b")))
```
---
```output
stderr:
mountpoint: f: not a block device
status 1
stderr:
mountpoint: nope: No such file or directory
status 1
stderr:
Usage: mountpoint [-q] { [-dn] DIR | -x DEVICE }

Check if DIR is a mountpoint

	-q	Quiet
	-d	Print major:minor of the filesystem
	-n	Print device name of the filesystem
	-x	Print major:minor of DEVICE
status 1
stderr:
Usage: mountpoint [-q] { [-dn] DIR | -x DEVICE }

Check if DIR is a mountpoint

	-q	Quiet
	-d	Print major:minor of the filesystem
	-n	Print device name of the filesystem
	-x	Print major:minor of DEVICE
status 1
```

## mknod

### p makes a fifo, with a=rw less the umask, or -m's mode exactly; b and c need root

```cu
(do (si-case #t "-" "@" "ls -l p1 | cut -c1-10" "-" (list "mknod" "p1" "p")) (si-case #t "-" "@" "ls -l p3 | cut -c1-10" "-" (list "mknod" "-m" "600" "p3" "p")) (si-case #t "-" "@" "ls -l p4 | cut -c1-10" "-" (list "mknod" "-m" "666" "p4" "p")) (si-case #t "-" "@" "@" "-" (list "mknod" "c1" "c" "1" "3")) (si-case #t "-" "@" "@" "-" (list "mknod" "b1" "b" "1" "3")))
```
---
```output
stderr:
status 0
after:
prw-r--r--
stderr:
status 0
after:
prw-------
stderr:
status 0
after:
prw-rw-rw-
stderr:
mknod: c1: Operation not permitted
status 1
stderr:
mknod: b1: Operation not permitted
status 1
```

### a type it has not, a fifo given numbers, a device without both

```cu
(do (si-case #t "-" "@" "@" "-" (list "mknod" "x1" "q")) (si-case #t "-" "@" "@" "-" (list "mknod" "p2" "p" "1" "2")) (si-case #t "-" "@" "@" "-" (list "mknod" "c2" "c" "1")))
```
---
```output
stderr:
Usage: mknod [-m MODE] NAME TYPE [MAJOR MINOR]

Create a special file (block, character, or pipe)

	-m MODE	Creation mode (default a=rw)
TYPE:
	b	Block device
	c or u	Character device
	p	Named pipe (MAJOR MINOR must be omitted)
status 1
stderr:
Usage: mknod [-m MODE] NAME TYPE [MAJOR MINOR]

Create a special file (block, character, or pipe)

	-m MODE	Creation mode (default a=rw)
TYPE:
	b	Block device
	c or u	Character device
	p	Named pipe (MAJOR MINOR must be omitted)
status 1
stderr:
Usage: mknod [-m MODE] NAME TYPE [MAJOR MINOR]

Create a special file (block, character, or pipe)

	-m MODE	Creation mode (default a=rw)
TYPE:
	b	Block device
	c or u	Character device
	p	Named pipe (MAJOR MINOR must be omitted)
status 1
```

## mesg

### standard input not a terminal is said; a word but y or n is the usage

```cu
(do (si-case #t "-" "@" "@" "-" (list "mesg")) (si-case #t "-" "@" "@" "-" (list "mesg" "y")) (si-case #t "-" "@" "@" "-" (list "mesg" "x")))
```
---
```output
stderr:
mesg: not a tty
status 1
stderr:
mesg: not a tty
status 1
stderr:
Usage: mesg [y|n]

Control write access to your terminal
	y	Allow write access to your terminal
	n	Disallow write access to your terminal
status 1
```

## renice

### a number it cannot read, a user there is not, a process there is not; none at all is the usage

```cu
(do (si-case #t "-" "@" "@" "-" (list "renice")) (si-case #t "-" "@" "@" "-" (list "renice" "x")) (si-case #t "-" "@" "@" "-" (list "renice" "+x")) (si-case #t "-" "@" "@" "-" (list "renice" "1" "-p" "x")) (si-case #t "-" "@" "@" "-" (list "renice" "5" "-p" "+3")) (si-case #t "-" "@" "@" "-" (list "renice" "1" "-u" "nopeuser")) (si-case #t "-" "@" "@" "-" (list "renice" "1" "-p" "999999")))
```
---
```output
stderr:
Usage: renice [-n] PRIORITY [[-p|g|u] ID...]...

Change scheduling priority of a running process

	-n	Add PRIORITY to current nice value
		Without -n, nice value is set to PRIORITY
	-p	Process ids (default)
	-g	Process group ids
	-u	Process user names
status 1
stderr:
renice: invalid number 'x'
status 1
stderr:
renice: invalid number 'x'
status 1
stderr:
renice: invalid number 'x'
status 1
stderr:
renice: invalid number '+3'
status 1
stderr:
renice: unknown user nopeuser
status 1
stderr:
renice: setpriority: No such process
status 1
```

## hostname and hostid

### setting the name needs root; -F's file must open; hostid takes no words

```cu
(do (si-case #t "-" "@" "@" "-" (list "hostname" "newname")) (si-case #t "-" "@" "@" "-" (list "hostname" "-F" "/nonexistent")) (si-case #t "-" "@" "@" "-" (list "hostid" "x")))
```
---
```output
stderr:
hostname: sethostname: Operation not permitted
status 1
stderr:
hostname: can't open '/nonexistent': No such file or directory
status 1
stderr:
Usage: hostid

Print out a unique 32-bit identifier for the machine
status 1
```

## ts

### each line stamped: a format with no fields; -s and -i count from the start and the line before; a last line with no newline keeps none

```cu
(do (si-case #t "two" "printf 'a\\nb' > two" "@" "-" (list "ts" "X")) (si-case #t "two" "printf 'a\\nb' > two" "@" "-" (list "ts" "-s" "[%S]")) (si-case #t "two" "printf 'a\\nb' > two" "@" "-" (list "ts" "-i" "%s")) (si-case #t "-" "@" "@" "-" (list "ts" "a" "b")))
```
---
```output
X a|
X bstderr:
status 0
[00] a|
[00] bstderr:
status 0
0 a|
0 bstderr:
status 0
stderr:
Usage: ts [-is] [STRFTIME]

Pipe stdin to stdout, add timestamp to each line

	-s	Time since start
	-i	Time since previous line
status 1
```

## sha384sum

### the digests of abc and of nothing; -c reads them back

```cu
(do (si-case #t "-" "printf abc > abc; : > empty" "@" "-" (list "sha384sum" "abc" "empty")) (si-case #t "-" "printf abc > abc; printf 'cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7  abc\\n' > sums" "@" "-" (list "sha384sum" "-c" "sums")))
```
---
```output
cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7  abc|
38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b  empty|
stderr:
status 0
abc: OK|
stderr:
status 0
```

## what is the machine's

### hostname is the system's name, -s it up to a dot; hostid is eight hex digits

```cu
(do (si-sh "hostname > ../want; hostname | sed 's/[.].*//' > ../want-s" "/dev/null") (si-case #t "-" "@" "@" "-" (list "hostname")) (def si-a (file-read-all (si-f "o"))) (si-case #t "-" "@" "@" "-" (list "hostname" "-s")) (def si-b (file-read-all (si-f "o"))) (si-case #t "-" "@" "@" "-" (list "hostid")) (def si-c (file-read-all (si-f "o"))) (si-sh "printf '%s' \"$(cat ../o)\" | tr -d '0-9a-f' | wc -c | tr -d ' ' > ../other" "/dev/null") (display (list (string=? si-a (file-read-all (si-f "want"))) (string=? si-b (file-read-all (si-f "want-s"))) (byte-len si-c) (string=? (file-read-all (si-f "other")) "0\n"))))
```
---
    (#t #t 9 #t)

### ts's default stamp is the local month, day and time; %.S adds microseconds

```cu
(do (si-sh "printf 'a\\n' > one" "/dev/null") (si-case #f "one" "@" "@" "-" (list "ts")) (def si-d (file-read-all (si-f "o"))) (si-case #f "one" "@" "@" "-" (list "ts" "-s" "%.S")) (def si-e (file-read-all (si-f "o"))) (display (list (byte-len si-d) (string=? (substring si-d 15 18) " a\n") (byte-len si-e) (string=? (substring si-e 0 3) "00.") (string=? (substring si-e 9 12) " a\n"))))
```
---
    (18 #t 12 #t #t)
