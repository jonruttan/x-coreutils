# @weight 1

An option an applet does not take is refused in busybox's words, which are
musl getopt's, before the applet runs: `unrecognized option: C` for a letter
-- in a short cluster, read left to right as getopt reads one, the first
letter the applet does not declare -- `unrecognized option: NAME` for a long
option, and `option requires an argument: C` (or `NAME`) for a value option
with nothing after it.  The applet's usage text follows, on standard error.
The status is 1, or 2 for sort and tty.  The expected text is busybox's, less
the banner line its usage text starts with and the rows for options this
bundle does not take.

## the fixtures

### a runner for stdout, stderr and the status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-io && mkdir -p /tmp/x-cu-io")) (def nf (fn (_ n) (string-append "/tmp/x-cu-io/" n))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (file-read-all (nf ".out")) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n")))))))) (display "made"))
```
---
    made

## unrecognized option

### a letter alone, and the first undeclared letter of a cluster

cat takes -v, so `-vQ` is refused at the Q; sort does not, so `-vQ` is
refused at the v.

```cu
(do (run (list "cat" "-Q")) (run (list "cat" "-vQ")) (run (list "head" "-qZ")) (run (list "sort" "-vQ")))
```
---
```output
stderr:
cat: unrecognized option: Q
Usage: cat [-nbvteA] [FILE]...

Print FILEs to stdout

	-n	Number output lines
	-b	Number nonempty lines
	-v	Show nonprinting characters as ^x or M-x
	-t	...and tabs as ^I
	-e	...and end lines with $
	-A	Same as -vte
status 1
stderr:
cat: unrecognized option: Q
Usage: cat [-nbvteA] [FILE]...

Print FILEs to stdout

	-n	Number output lines
	-b	Number nonempty lines
	-v	Show nonprinting characters as ^x or M-x
	-t	...and tabs as ^I
	-e	...and end lines with $
	-A	Same as -vte
status 1
stderr:
head: unrecognized option: Z
Usage: head [OPTIONS] [FILE]...

Print first 10 lines of FILEs (or stdin).
With more than one FILE, precede each with a filename header.

	-n N[bkm]	Print first N lines
	-n -N[bkm]	Print all except N last lines
	-c [-]N[bkm]	Print first N bytes
			(b:*512 k:*1024 m:*1024^2)
	-q		Never print headers
	-v		Always print headers
status 1
stderr:
sort: unrecognized option: v
Usage: sort [-nrughMcszbdfiokt] [-o FILE] [-k START[.OFS][OPTS][,END[.OFS][OPTS]] [-t CHAR] [FILE]...

Sort lines of text

	-o FILE	Output to FILE
	-c	Check whether input is sorted
	-b	Ignore leading blanks
	-f	Ignore case
	-i	Ignore unprintable characters
	-d	Dictionary order (blank or alphanumeric only)
	-n	Sort numbers
	-g	General numerical sort
	-M	Sort month
	-t CHAR	Field separator
	-k N[,M] Sort by Nth field
	-r	Reverse sort order
	-s	Stable (don't sort ties alphabetically)
	-u	Suppress duplicate lines
	-z	NUL terminated input and output
status 2
```

### the status is 1 whatever the applet runs; sort and tty keep 2

```cu
(do (run (list "env" "-Q")) (run (list "ls" "-y")))
```
---
```output
stderr:
env: unrecognized option: Q
Usage: env [-i0] [-u NAME]... [-] [NAME=VALUE]... [PROG ARGS]

Print current environment or run PROG after setting up environment

	-0	NUL terminated output
	-u NAME	Remove variable from environment
status 1
stderr:
ls: unrecognized option: y
Usage: ls [-1AaCxdLHRFplinshrSXvctu] [-w WIDTH] [FILE]...

List directory contents

	-1	One column output
	-a	Include names starting with .
	-A	Like -a, but exclude . and ..
	-x	List by lines
	-d	List directory names, not contents
	-L	Follow symlinks
	-H	Follow symlinks on command line
	-R	Recurse
	-p	Append / to directory names
	-F	Append indicator (one of */=@|) to names
	-l	Long format
	-i	List inode numbers
	-n	List numeric UIDs and GIDs instead of names
	-s	List allocated blocks
	-lc	List ctime
	-lu	List atime
	-h	Human readable sizes (1K 243M 2G)
	-S	Sort by size
	-X	Sort by extension
	-v	Sort by version
	-t	Sort by mtime
	-tc	Sort by ctime
	-tu	Sort by atime
	-r	Reverse sort order
	-w N	Format N columns wide
status 1
```

### a long option, after a cluster the applet takes

```cu
(do (run (list "cat" "--nope")) (run (list "sort" "-rn" "--nope")))
```
---
```output
stderr:
cat: unrecognized option: nope
Usage: cat [-nbvteA] [FILE]...

Print FILEs to stdout

	-n	Number output lines
	-b	Number nonempty lines
	-v	Show nonprinting characters as ^x or M-x
	-t	...and tabs as ^I
	-e	...and end lines with $
	-A	Same as -vte
status 1
stderr:
sort: unrecognized option: nope
Usage: sort [-nrughMcszbdfiokt] [-o FILE] [-k START[.OFS][OPTS][,END[.OFS][OPTS]] [-t CHAR] [FILE]...

Sort lines of text

	-o FILE	Output to FILE
	-c	Check whether input is sorted
	-b	Ignore leading blanks
	-f	Ignore case
	-i	Ignore unprintable characters
	-d	Dictionary order (blank or alphanumeric only)
	-n	Sort numbers
	-g	General numerical sort
	-M	Sort month
	-t CHAR	Field separator
	-k N[,M] Sort by Nth field
	-r	Reverse sort order
	-s	Stable (don't sort ties alphabetically)
	-u	Suppress duplicate lines
	-z	NUL terminated input and output
status 2
```

## option requires an argument

### a value option last on the line, alone, in a cluster, and long

```cu
(do (run (list "head" "-n")) (run (list "head" "-qn")) (run (list "cut" "-b")) (run (list "nproc" "--ignore")))
```
---
```output
stderr:
head: option requires an argument: n
Usage: head [OPTIONS] [FILE]...

Print first 10 lines of FILEs (or stdin).
With more than one FILE, precede each with a filename header.

	-n N[bkm]	Print first N lines
	-n -N[bkm]	Print all except N last lines
	-c [-]N[bkm]	Print first N bytes
			(b:*512 k:*1024 m:*1024^2)
	-q		Never print headers
	-v		Always print headers
status 1
stderr:
head: option requires an argument: n
Usage: head [OPTIONS] [FILE]...

Print first 10 lines of FILEs (or stdin).
With more than one FILE, precede each with a filename header.

	-n N[bkm]	Print first N lines
	-n -N[bkm]	Print all except N last lines
	-c [-]N[bkm]	Print first N bytes
			(b:*512 k:*1024 m:*1024^2)
	-q		Never print headers
	-v		Always print headers
status 1
stderr:
cut: option requires an argument: b
Usage: cut {-b|c LIST | -f|F LIST [-d SEP] [-s]} [-D] [-O SEP] [FILE]...

Print selected fields from FILEs to stdout

	-b LIST	Output only bytes from LIST
	-c LIST	Output only characters from LIST
	-d SEP	Input field delimiter (default -f TAB, -F run of whitespace)
	-f LIST	Print only these fields (-d is single char)
	-s	Drop lines with no delimiter (else print them in full)
	-n	Ignored
status 1
stderr:
nproc: option requires an argument: ignore
Usage: nproc [--all] [--ignore=N]

Print number of available CPUs

	--all		Number of installed CPUs
	--ignore=N	Exclude N CPUs
status 1
```

### an applet that reads its own line

nc parses its options itself and refuses through its declaration, where its
value options are hidden rows.

```cu
(do (run (list "nc" "-p")) (run (list "nc" "-w")))
```
---
```output
stderr:
nc: option requires an argument: p
Usage: nc [OPTIONS] HOST PORT  - connect
nc [OPTIONS] -l -p PORT [HOST] [PORT]  - listen

	-e PROG	Run PROG after connect (must be last)
	-l	Listen mode, for inbound connects
	-lk	With -e, provides persistent server
	-p PORT	Local port
	-s ADDR	Local address
	-w SEC	Timeout for connects and final net reads
	-i SEC	Delay interval for lines sent
	-n	Don't do DNS resolution
	-u	UDP mode
	-b	Allow broadcasts
	-v	Verbose
	-o FILE	Hex dump traffic
	-z	Zero-I/O mode (scanning)
status 1
stderr:
nc: option requires an argument: w
Usage: nc [OPTIONS] HOST PORT  - connect
nc [OPTIONS] -l -p PORT [HOST] [PORT]  - listen

	-e PROG	Run PROG after connect (must be last)
	-l	Listen mode, for inbound connects
	-lk	With -e, provides persistent server
	-p PORT	Local port
	-s ADDR	Local address
	-w SEC	Timeout for connects and final net reads
	-i SEC	Delay interval for lines sent
	-n	Don't do DNS resolution
	-u	UDP mode
	-b	Allow broadcasts
	-v	Verbose
	-o FILE	Hex dump traffic
	-z	Zero-I/O mode (scanning)
status 1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-io")) (display "clean"))
```
---
    clean
