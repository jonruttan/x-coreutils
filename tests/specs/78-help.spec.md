# @weight 1

`APPLET --help`, for every applet.  Every expectation is busybox's own output,
from a busybox built from its source, less the banner line its usage text
starts with and the rows for options this bundle does not take.  A `|` marks
the end of each line written to standard output, so a trailing tab shows.
test, `[`, `[[`, true, false and echo take --help as an operand, as POSIX has
it, and busybox has no help text for ascii, tree and pipe_progress.

## the fixture

### a run of an applet, with its stdout, stderr and status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-help && mkdir -p /tmp/x-cu-help")) (def nf (fn (_ n) (string-append "/tmp/x-cu-help/" n))) (def run (fn (_ argv in) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv in)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (Str8 replace "\n" "|\n" (file-read-all (nf ".out"))) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n")))))))) (display "made"))
```
---
    made

## each applet's help

### cat

```cu
(run (list "cat" "--help") "")
```
---
```output
Usage: cat [-nbvteA] [FILE]...|
|
Print FILEs to stdout|
|
	-n	Number output lines|
	-b	Number nonempty lines|
	-v	Show nonprinting characters as ^x or M-x|
	-t	...and tabs as ^I|
	-e	...and end lines with $|
	-A	Same as -vte|
stderr:
status 0
```

### sort

```cu
(run (list "sort" "--help") "")
```
---
```output
Usage: sort [-nrughMcszbdfiokt] [-o FILE] [-k START[.OFS][OPTS][,END[.OFS][OPTS]] [-t CHAR] [FILE]...|
|
Sort lines of text|
|
	-o FILE	Output to FILE|
	-c	Check whether input is sorted|
	-b	Ignore leading blanks|
	-f	Ignore case|
	-i	Ignore unprintable characters|
	-d	Dictionary order (blank or alphanumeric only)|
	-n	Sort numbers|
	-g	General numerical sort|
	-M	Sort month|
	-t CHAR	Field separator|
	-k N[,M] Sort by Nth field|
	-r	Reverse sort order|
	-s	Stable (don't sort ties alphabetically)|
	-u	Suppress duplicate lines|
	-z	NUL terminated input and output|
stderr:
status 0
```

### uniq

```cu
(run (list "uniq" "--help") "")
```
---
```output
Usage: uniq [-cduiz] [-f,s,w N] [FILE [OUTFILE]]|
|
Discard duplicate lines|
|
	-c	Prefix lines by the number of occurrences|
	-d	Only print duplicate lines|
	-u	Only print unique lines|
	-i	Ignore case|
	-f N	Skip first N fields|
	-s N	Skip first N chars (after any skipped fields)|
	-w N	Compare N characters in line|
stderr:
status 0
```

### head

```cu
(run (list "head" "--help") "")
```
---
```output
Usage: head [OPTIONS] [FILE]...|
|
Print first 10 lines of FILEs (or stdin).|
With more than one FILE, precede each with a filename header.|
|
	-n N[bkm]	Print first N lines|
	-n -N[bkm]	Print all except N last lines|
	-c [-]N[bkm]	Print first N bytes|
			(b:*512 k:*1024 m:*1024^2)|
	-q		Never print headers|
	-v		Always print headers|
stderr:
status 0
```

### tail

```cu
(run (list "tail" "--help") "")
```
---
```output
Usage: tail [OPTIONS] [FILE]...|
|
Print last 10 lines of FILEs (or stdin) to.|
With more than one FILE, precede each with a filename header.|
|
	-c [+]N[bkm]	Print last N bytes|
	-n N[bkm]	Print last N lines|
	-n +N[bkm]	Start on Nth line and print the rest|
			(b:*512 k:*1024 m:*1024^2)|
	-q		Never print headers|
	-v		Always print headers|
	-f		Print data as file grows|
	-s SECONDS	Wait SECONDS between reads with -f|
stderr:
status 0
```

### wc

```cu
(run (list "wc" "--help") "")
```
---
```output
Usage: wc [-cmlwL] [FILE]...|
|
Count lines, words, and bytes for FILEs (or stdin)|
|
	-c	Count bytes|
	-m	Count characters|
	-l	Count newlines|
	-w	Count words|
	-L	Print longest line length|
stderr:
status 0
```

### comm

```cu
(run (list "comm" "--help") "")
```
---
```output
Usage: comm [-123] FILE1 FILE2|
|
Compare FILE1 with FILE2|
|
	-1	Suppress lines unique to FILE1|
	-2	Suppress lines unique to FILE2|
	-3	Suppress lines common to both files|
stderr:
status 0
```

### join

```cu
(run (list "join" "--help") "")
```
---
```output
Usage: join [-a 1|2 | -v 1|2] [-e STR] [-o LIST] [-t SEP_CHAR] [-1 NUM] [-2 NUM] FILE1 FILE2|
|
Join FILE1 and FILE2, writing to stdout|
|
	-t CHAR	Use a different field separator|
|
LIST is a space or comma separated list of 1/2.FIELD or 0 (the join field)|
stderr:
status 0
```

### tr

```cu
(run (list "tr" "--help") "")
```
---
```output
Usage: tr [-cds] STRING1 [STRING2]|
|
Translate, squeeze, or delete characters from stdin, writing to stdout|
|
	-c	Take complement of STRING1|
	-d	Delete input characters coded STRING1|
	-s	Squeeze multiple output characters of STRING2 into one character|
stderr:
status 0
```

### cut

```cu
(run (list "cut" "--help") "")
```
---
```output
Usage: cut {-b|c LIST | -f|F LIST [-d SEP] [-s]} [-D] [-O SEP] [FILE]...|
|
Print selected fields from FILEs to stdout|
|
	-b LIST	Output only bytes from LIST|
	-c LIST	Output only characters from LIST|
	-d SEP	Input field delimiter (default -f TAB, -F run of whitespace)|
	-f LIST	Print only these fields (-d is single char)|
	-s	Drop lines with no delimiter (else print them in full)|
	-n	Ignored|
stderr:
status 0
```

### basename

```cu
(run (list "basename" "--help") "")
```
---
```output
Usage: basename FILE [SUFFIX] | -a FILE... | -s SUFFIX FILE...|
|
Strip directory path and SUFFIX from FILE|
|
	-s SUFFIX	Remove SUFFIX (implies -a)|
stderr:
status 0
```

### dirname

```cu
(run (list "dirname" "--help") "")
```
---
```output
Usage: dirname FILENAME|
|
Strip non-directory suffix from FILENAME|
stderr:
status 0
```

### cp

```cu
(run (list "cp" "--help") "")
```
---
```output
Usage: cp [-arPLHpfinlsTu] SOURCE DEST|
or: cp [-arPLHpfinlsu] SOURCE... { -t DIRECTORY | DIRECTORY }|
|
Copy SOURCEs to DEST|
|
	-a	Same as -dpR|
	-R,-r	Recurse|
	-L	Follow all symlinks|
	-H	Follow symlinks on command line|
	-p	Preserve file attributes if possible|
	-f	Overwrite|
	-i	Prompt before overwrite|
	-l,-s	Create (sym)links|
	-T	Refuse to copy if DEST is a directory|
	-u	Copy only newer files|
stderr:
status 0
```

### rm

```cu
(run (list "rm" "--help") "")
```
---
```output
Usage: rm [-irf] FILE...|
|
Remove (unlink) FILEs|
|
	-i	Always prompt before removing|
	-f	Never prompt|
	-R,-r	Recurse|
stderr:
status 0
```

### mkdir

```cu
(run (list "mkdir" "--help") "")
```
---
```output
Usage: mkdir [-m MODE] [-p] DIRECTORY...|
|
Create DIRECTORY|
|
	-m MODE	Mode|
	-p	No error if exists; make parent directories as needed|
stderr:
status 0
```

### sha256sum

```cu
(run (list "sha256sum" "--help") "")
```
---
```output
Usage: sha256sum [-c[sw]] [FILE]...|
|
Print or check SHA256 checksums|
|
	-c	Check sums against list in FILEs|
	-s	Don't output anything, status code shows success|
	-w	Warn about improperly formatted checksum lines|
stderr:
status 0
```

### md5sum

```cu
(run (list "md5sum" "--help") "")
```
---
```output
Usage: md5sum [-c[sw]] [FILE]...|
|
Print or check MD5 checksums|
|
	-c	Check sums against list in FILEs|
	-s	Don't output anything, status code shows success|
	-w	Warn about improperly formatted checksum lines|
stderr:
status 0
```

### sha1sum

```cu
(run (list "sha1sum" "--help") "")
```
---
```output
Usage: sha1sum [-c[sw]] [FILE]...|
|
Print or check SHA1 checksums|
|
	-c	Check sums against list in FILEs|
	-s	Don't output anything, status code shows success|
	-w	Warn about improperly formatted checksum lines|
stderr:
status 0
```

### sha512sum

```cu
(run (list "sha512sum" "--help") "")
```
---
```output
Usage: sha512sum [-c[sw]] [FILE]...|
|
Print or check SHA512 checksums|
|
	-c	Check sums against list in FILEs|
	-s	Don't output anything, status code shows success|
	-w	Warn about improperly formatted checksum lines|
stderr:
status 0
```

### cksum

```cu
(run (list "cksum" "--help") "")
```
---
```output
Usage: cksum FILE...|
|
Calculate CRC32 checksum of FILEs|
stderr:
status 0
```

### sum

```cu
(run (list "sum" "--help") "")
```
---
```output
Usage: sum [-rs] [FILE]...|
|
Checksum and count the blocks in a file|
|
	-r	Use BSD sum algorithm (1K blocks)|
	-s	Use System V sum algorithm (512byte blocks)|
stderr:
status 0
```

### yes

```cu
(run (list "yes" "--help") "")
```
---
```output
Usage: yes [STRING]|
|
Repeatedly print a line with STRING, or 'y'|
stderr:
status 0
```

### factor

```cu
(run (list "factor" "--help") "")
```
---
```output
Usage: factor [NUMBER]...|
|
Print prime factors|
stderr:
status 0
```

### expand

```cu
(run (list "expand" "--help") "")
```
---
```output
Usage: expand [-i] [-t N] [FILE]...|
|
Convert tabs to spaces, writing to stdout|
|
	-i	Don't convert tabs after non blanks|
	-t	Tabstops every N chars|
stderr:
status 0
```

### unexpand

```cu
(run (list "unexpand" "--help") "")
```
---
```output
Usage: unexpand [-fa][-t N] [FILE]...|
|
Convert spaces to tabs, writing to stdout|
|
	-a	Convert all blanks|
	-f	Convert only leading blanks|
	-t N	Tabstops every N chars|
stderr:
status 0
```

### dos2unix

```cu
(run (list "dos2unix" "--help") "")
```
---
```output
Usage: dos2unix [-ud] [FILE]|
|
Convert FILE in-place from DOS to Unix format.|
When no file is given, use stdin/stdout.|
|
	-u	dos2unix|
	-d	unix2dos|
stderr:
status 0
```

### unix2dos

```cu
(run (list "unix2dos" "--help") "")
```
---
```output
Usage: unix2dos [-ud] [FILE]|
|
Convert FILE in-place from Unix to DOS format.|
When no file is given, use stdin/stdout.|
|
	-u	dos2unix|
	-d	unix2dos|
stderr:
status 0
```

### split

```cu
(run (list "split" "--help") "")
```
---
```output
Usage: split [OPTIONS] [INPUT [PREFIX]]|
|
	-b N[k|m]	Split by N (kilo|mega)bytes|
	-l N		Split by N lines|
	-a N		Use N letters as suffix|
stderr:
status 0
```

### shuf

```cu
(run (list "shuf" "--help") "")
```
---
```output
Usage: shuf [-n NUM] [-o FILE] [-z] [FILE | -e [ARG...] | -i L-H]|
|
Randomly permute lines|
|
	-n NUM	Output at most NUM lines|
	-o FILE	Write to FILE, not standard output|
	-z	NUL terminated output|
	-e	Treat ARGs as lines|
	-i L-H	Treat numbers L-H as lines|
stderr:
status 0
```

### base64

```cu
(run (list "base64" "--help") "")
```
---
```output
Usage: base64 [-d] [-w COL] [FILE]|
|
Base64 encode or decode FILE to standard output|
|
	-d	Decode data|
	-w COL	Wrap lines at COL (default 76, 0 disables)|
stderr:
status 0
```

### stat

```cu
(run (list "stat" "--help") "")
```
---
```output
Usage: stat [-ltf] [-c FMT] FILE...|
|
Display file (default) or filesystem status|
|
	-c FMT	Use the specified format|
	-f	Display filesystem status|
	-L	Follow links|
	-t	Terse display|
|
FMT sequences for files:|
 %a	Access rights in octal|
 %A	Access rights in human readable form|
 %b	Number of blocks allocated (see %B)|
 %B	Size in bytes of each block reported by %b|
 %d	Device number in decimal|
 %D	Device number in hex|
 %f	Raw mode in hex|
 %F	File type|
 %g	Group ID|
 %G	Group name|
 %h	Number of hard links|
 %i	Inode number|
 %n	File name|
 %N	File name, with -> TARGET if symlink|
 %o	I/O block size|
 %s	Total size in bytes|
 %t	Major device type in hex|
 %T	Minor device type in hex|
 %u	User ID|
 %U	User name|
 %x	Time of last access|
 %X	Time of last access as seconds since Epoch|
 %y	Time of last modification|
 %Y	Time of last modification as seconds since Epoch|
 %z	Time of last change|
 %Z	Time of last change as seconds since Epoch|
|
FMT sequences for file systems:|
 %a	Free blocks available to non-superuser|
 %b	Total data blocks|
 %c	Total file nodes|
 %d	Free file nodes|
 %f	Free blocks|
 %i	File System ID in hex|
 %l	Maximum length of filenames|
 %n	File name|
 %s	Block size (for faster transfer)|
 %S	Fundamental block size (for block counts)|
 %t	Type in hex|
 %T	Type in human readable form|
stderr:
status 0
```

### du

```cu
(run (list "du" "--help") "")
```
---
```output
Usage: du [-aHLdclsxhmk] [FILE]...|
|
Summarize disk space used for FILEs (or directories)|
|
	-a	Show file sizes too|
	-L	Follow all symlinks|
	-H	Follow symlinks on command line|
	-d N	Limit output to directories (and files with -a) of depth < N|
	-c	Show grand total|
	-l	Count sizes many times if hard linked|
	-s	Display only a total for each argument|
	-x	Skip directories on different filesystems|
	-h	Sizes in human readable format (e.g., 1K 243M 2G)|
	-m	Sizes in megabytes|
	-k	Sizes in kilobytes (default)|
stderr:
status 0
```

### dd

```cu
(run (list "dd" "--help") "")
```
---
```output
Usage: dd [if=FILE] [of=FILE] [ibs=N obs=N/bs=N] [count=N] [skip=N] [seek=N]|
	[conv=notrunc|noerror|sync|fsync]|
	[iflag=skip_bytes|count_bytes|fullblock|direct] [oflag=seek_bytes|append|direct]|
|
Copy a file with converting and formatting|
|
	if=FILE		Read from FILE instead of stdin|
	of=FILE		Write to FILE instead of stdout|
	bs=N		Read and write N bytes at a time|
	ibs=N		Read N bytes at a time|
	obs=N		Write N bytes at a time|
	count=N		Copy only N input blocks|
	skip=N		Skip N input blocks|
	seek=N		Skip N output blocks|
	conv=notrunc	Don't truncate output file|
	conv=noerror	Continue after read errors|
	conv=sync	Pad blocks with zeros|
	conv=fsync	Physically write data out before finishing|
	conv=swab	Swap every pair of bytes|
	iflag=skip_bytes	skip=N is in bytes|
	iflag=count_bytes	count=N is in bytes|
	oflag=seek_bytes	seek=N is in bytes|
	iflag=direct	O_DIRECT input|
	oflag=direct	O_DIRECT output|
	iflag=fullblock	Read full blocks|
	oflag=append	Open output in append mode|
	status=noxfer	Suppress rate output|
	status=none	Suppress all output|
|
N may be suffixed by c (1), w (2), b (512), kB (1000), k (1024), MB, M, GB, G|
stderr:
status 0
```

### truncate

```cu
(run (list "truncate" "--help") "")
```
---
```output
Usage: truncate [-c] -s SIZE FILE...|
|
Truncate FILEs to SIZE|
|
	-c	Do not create files|
	-s SIZE|
stderr:
status 0
```

### unlink

```cu
(run (list "unlink" "--help") "")
```
---
```output
Usage: unlink FILE|
|
Delete FILE by calling unlink()|
stderr:
status 0
```

### shred

```cu
(run (list "shred" "--help") "")
```
---
```output
Usage: shred [-fuz] [-n N] [-s SIZE] FILE...|
|
Overwrite/delete FILEs|
|
	-f	Chmod to ensure writability|
	-n N	Overwrite N times (default 3)|
	-z	Final overwrite with zeros|
	-u	Remove file|
stderr:
status 0
```

### timeout

```cu
(run (list "timeout" "--help") "")
```
---
```output
Usage: timeout [-s SIG] [-k KILL_SECS] SECS PROG ARGS|
|
Run PROG. Send SIG to it if it is not gone in SECS seconds.|
Default SIG: TERM.If it still exists in KILL_SECS seconds, send KILL.|
|
stderr:
status 0
```

### usleep

```cu
(run (list "usleep" "--help") "")
```
---
```output
Usage: usleep N|
|
Pause for N microseconds|
stderr:
status 0
```

### tty

```cu
(run (list "tty" "--help") "")
```
---
```output
Usage: tty [-s]|
|
Print file name of stdin's terminal|
|
	-s	Print nothing, only return exit status|
stderr:
status 0
```

### nohup

```cu
(run (list "nohup" "--help") "")
```
---
```output
Usage: nohup PROG ARGS|
|
Run PROG immune to hangups, with output to a non-tty|
stderr:
status 0
```

### [[

```cu
(run (list "[[" "--help") "")
```
---
```output
stderr:
[[: missing ]]
status 2
```

### od

```cu
(run (list "od" "--help") "")
```
---
```output
Usage: od [-abcdfhilovxs] [-t TYPE] [-A RADIX] [-N SIZE] [-j SKIP] [-S MINSTR] [-w WIDTH] [FILE]...|
|
Print FILEs (or stdin) unambiguously, as octal bytes by default|
stderr:
status 0
```

### uuencode

```cu
(run (list "uuencode" "--help") "")
```
---
```output
Usage: uuencode [-m] [FILE] STORED_FILENAME|
|
Uuencode FILE (or stdin) to stdout|
|
	-m	Use base64 encoding per RFC1521|
stderr:
status 0
```

### uudecode

```cu
(run (list "uudecode" "--help") "")
```
---
```output
Usage: uudecode [-o OUTFILE] [INFILE]|
|
Uudecode a file|
Finds OUTFILE in uuencoded source unless -o is given|
stderr:
status 0
```

### expr

```cu
(run (list "expr" "--help") "")
```
---
```output
Usage: expr EXPRESSION|
|
Print the value of EXPRESSION|
|
EXPRESSION may be:|
	ARG1 | ARG2	ARG1 if it is neither null nor 0, otherwise ARG2|
	ARG1 & ARG2	ARG1 if neither argument is null or 0, otherwise 0|
	ARG1 < ARG2	1 if ARG1 is less than ARG2, else 0. Similarly:|
	ARG1 <= ARG2|
	ARG1 = ARG2|
	ARG1 != ARG2|
	ARG1 >= ARG2|
	ARG1 > ARG2|
	ARG1 + ARG2	Sum of ARG1 and ARG2. Similarly:|
	ARG1 - ARG2|
	ARG1 * ARG2|
	ARG1 / ARG2|
	ARG1 % ARG2|
	STRING : REGEXP		Anchored pattern match of REGEXP in STRING|
	match STRING REGEXP	Same as STRING : REGEXP|
	substr STRING POS LEN	Substring of STRING, POS counts from 1|
	index STRING CHARS	Index in STRING where any CHARS is found, or 0|
	length STRING		Length of STRING|
	quote TOKEN		Interpret TOKEN as a string, even if|
				it is a keyword like 'match' or an|
				operator like '/'|
	(EXPRESSION)		Value of EXPRESSION|
|
Beware that many operators need to be escaped or quoted for shells.|
Comparisons are arithmetic if both ARGs are numbers, else|
lexicographical. Pattern matches return the string matched between|
\( and \) or null; if \( and \) are not used, they return the number|
of characters matched or 0.|
stderr:
status 0
```

### chmod

```cu
(run (list "chmod" "--help") "")
```
---
```output
Usage: chmod [-Rcvf] MODE[,MODE]... FILE...|
|
MODE is octal number (bit pattern sstrwxrwxrwx) or [ugoa]{+|-|=}[rwxXst]|
|
	-R	Recurse|
	-c	List changed files|
	-v	Verbose|
	-f	Hide errors|
stderr:
status 0
```

### chown

```cu
(run (list "chown" "--help") "")
```
---
```output
Usage: chown [-RhLHPcvf]... USER[:[GRP]] FILE...|
|
Change the owner and/or group of FILEs to USER and/or GRP|
|
	-h	Affect symlinks instead of symlink targets|
	-L	Traverse all symlinks to directories|
	-H	Traverse symlinks on command line only|
	-P	Don't traverse symlinks (default)|
	-R	Recurse|
	-c	List changed files|
	-v	Verbose|
	-f	Hide errors|
stderr:
status 0
```

### chgrp

```cu
(run (list "chgrp" "--help") "")
```
---
```output
Usage: chgrp [-RhLHPcvf]... GROUP FILE...|
|
Change the group membership of FILEs to GROUP|
|
	-h	Affect symlinks instead of symlink targets|
	-L	Traverse all symlinks to directories|
	-H	Traverse symlinks on command line only|
	-P	Don't traverse symlinks (default)|
	-R	Recurse|
	-c	List changed files|
	-v	Verbose|
	-f	Hide errors|
stderr:
status 0
```

### ln

```cu
(run (list "ln" "--help") "")
```
---
```output
Usage: ln [-sfnbtv] [-S SUF] TARGET... LINK|DIR|
|
Create a link LINK or DIR/TARGET to the specified TARGET(s)|
|
	-s	Make symlinks instead of hardlinks|
	-f	Remove existing destinations|
	-n	Don't dereference symlinks - treat like normal file|
	-b	Make a backup of the target (if exists) before link operation|
	-v	Verbose|
stderr:
status 0
```

### link

```cu
(run (list "link" "--help") "")
```
---
```output
Usage: link FILE LINK|
|
Create hard LINK to FILE|
stderr:
status 0
```

### readlink

```cu
(run (list "readlink" "--help") "")
```
---
```output
Usage: readlink [-fnv] FILE|
|
Display the value of a symlink|
|
	-n	Don't add newline|
	-f	Canonicalize by following all symlinks|
	-v	Verbose|
stderr:
status 0
```

### realpath

```cu
(run (list "realpath" "--help") "")
```
---
```output
Usage: realpath FILE...|
|
Print absolute pathnames of FILEs|
stderr:
status 0
```

### mkfifo

```cu
(run (list "mkfifo" "--help") "")
```
---
```output
Usage: mkfifo [-m MODE] NAME|
|
Create named pipe|
|
	-m MODE	Mode (default a=rw)|
stderr:
status 0
```

### df

```cu
(run (list "df" "--help") "")
```
---
```output
Usage: df [-PkmhTai] [-B SIZE] [-t TYPE] [FILESYSTEM]...|
|
Print filesystem usage statistics|
|
	-P	POSIX output format|
	-k	1024-byte blocks (default)|
	-m	1M-byte blocks|
	-h	Human readable (e.g. 1K 243M 2G)|
	-T	Print filesystem type|
	-a	Show all filesystems|
	-i	Inodes|
	-B SIZE	Blocksize|
stderr:
status 0
```

### sync

```cu
(run (list "sync" "--help") "")
```
---
```output
Usage: sync [-df] [FILE]...|
|
Write all buffered blocks (in FILEs) to disk|
	-d	Avoid syncing metadata|
	-f	Sync filesystems underlying FILEs|
stderr:
status 0
```

### id

```cu
(run (list "id" "--help") "")
```
---
```output
Usage: id [-ugGnr] [USER]|
|
Print information about USER or the current user|
|
	-u	User ID|
	-g	Group ID|
	-G	Supplementary group IDs|
	-n	Print names instead of numbers|
	-r	Print real ID instead of effective ID|
stderr:
status 0
```

### whoami

```cu
(run (list "whoami" "--help") "")
```
---
```output
Usage: whoami|
|
Print the user name associated with the current effective user id|
stderr:
status 0
```

### logname

```cu
(run (list "logname" "--help") "")
```
---
```output
Usage: logname|
|
Print the name of the current user|
stderr:
status 0
```

### groups

```cu
(run (list "groups" "--help") "")
```
---
```output
Usage: groups [USER]|
|
Print the groups USER is in|
stderr:
status 0
```

### who

```cu
(run (list "who" "--help") "")
```
---
```output
Usage: who [-aH]|
|
Show who is logged on|
|
	-a	Show all|
	-H	Print column headers|
stderr:
status 0
```

### w

```cu
(run (list "w" "--help") "")
```
---
```output
Usage: w|
|
Show who is logged on|
stderr:
status 0
```

### users

```cu
(run (list "users" "--help") "")
```
---
```output
Usage: users|
|
Print the users currently logged on|
stderr:
status 0
```

### uname

```cu
(run (list "uname" "--help") "")
```
---
```output
Usage: uname [-amnrspvio]|
|
Print system information|
|
	-a	Print all|
	-m	Machine (hardware) type|
	-n	Hostname|
	-r	Kernel release|
	-s	Kernel name (default)|
	-p	Processor type|
	-v	Kernel version|
	-i	Hardware platform|
	-o	OS name|
stderr:
status 0
```

### arch

```cu
(run (list "arch" "--help") "")
```
---
```output
Usage: arch|
|
Print system architecture|
stderr:
status 0
```

### nproc

```cu
(run (list "nproc" "--help") "")
```
---
```output
Usage: nproc [--all] [--ignore=N]|
|
Print number of available CPUs|
|
	--all		Number of installed CPUs|
	--ignore=N	Exclude N CPUs|
stderr:
status 0
```

### nice

```cu
(run (list "nice" "--help") "")
```
---
```output
Usage: nice [-n ADJUST] [PROG ARGS]|
|
Change scheduling priority, run PROG|
|
	-n ADJUST	Adjust priority by ADJUST|
stderr:
status 0
```

### chroot

```cu
(run (list "chroot" "--help") "")
```
---
```output
Usage: chroot NEWROOT [PROG ARGS]|
|
Run PROG with root directory set to NEWROOT|
stderr:
status 0
```

### echo

```cu
(run (list "echo" "--help") "")
```
---
```output
--help|
stderr:
status 0
```

### printf

```cu
(run (list "printf" "--help") "")
```
---
```output
Usage: printf FORMAT [ARG]...|
|
Format and print ARG(s) according to FORMAT (a-la C printf)|
stderr:
status 0
```

### true

```cu
(run (list "true" "--help") "")
```
---
```output
stderr:
status 0
```

### false

```cu
(run (list "false" "--help") "")
```
---
```output
stderr:
status 1
```

### seq

```cu
(run (list "seq" "--help") "")
```
---
```output
Usage: seq [-w] [-s SEP] [FIRST [INC]] LAST|
|
Print numbers from FIRST to LAST, in steps of INC.|
FIRST, INC default to 1.|
|
	-w	Pad with leading zeros|
	-s SEP	String separator|
stderr:
status 0
```

### rev

```cu
(run (list "rev" "--help") "")
```
---
```output
Usage: rev [FILE]...|
|
Reverse lines of FILE|
stderr:
status 0
```

### tac

```cu
(run (list "tac" "--help") "")
```
---
```output
Usage: tac [FILE]...|
|
Concatenate FILEs and print them in reverse|
stderr:
status 0
```

### nl

```cu
(run (list "nl" "--help") "")
```
---
```output
Usage: nl [OPTIONS] [FILE]...|
|
Write FILEs to standard output with line numbers added|
|
	-b STYLE	Which lines to number - a: all, t: nonempty, n: none|
	-i N		Line number increment|
	-s STRING	Use STRING as line number separator|
	-v N		Start from N|
	-w N		Width of line numbers|
stderr:
status 0
```

### fold

```cu
(run (list "fold" "--help") "")
```
---
```output
Usage: fold [-bs] [-w WIDTH] [FILE]...|
|
Wrap input lines in FILEs (or stdin), writing to stdout|
|
	-b	Count bytes rather than columns|
	-s	Break at spaces|
	-w	Use WIDTH columns instead of 80|
stderr:
status 0
```

### paste

```cu
(run (list "paste" "--help") "")
```
---
```output
Usage: paste [-d LIST] [-s] [FILE]...|
|
Paste lines from each input file, separated with tab|
|
	-d LIST	Use delimiters from LIST, not tab|
	-s      Serial: one file at a time|
stderr:
status 0
```

### tee

```cu
(run (list "tee" "--help") "")
```
---
```output
Usage: tee [-ai] [FILE]...|
|
Copy stdin to each FILE, and also to stdout|
|
	-a	Append to the given FILEs, don't overwrite|
	-i	Ignore interrupt signals (SIGINT)|
stderr:
status 0
```

### touch

```cu
(run (list "touch" "--help") "")
```
---
```output
Usage: touch [-cham] [-d DATE] [-t DATE] [-r FILE] FILE...|
|
Update mtime of FILEs|
|
	-c	Don't create files|
	-d DT	Date/time to use|
	-t DT	Date/time to use|
	-r FILE	Use FILE's date/time|
stderr:
status 0
```

### ls

```cu
(run (list "ls" "--help") "")
```
---
```output
Usage: ls [-1AaCxdLHRFplinshrSXvctu] [-w WIDTH] [FILE]...|
|
List directory contents|
|
	-1	One column output|
	-a	Include names starting with .|
	-A	Like -a, but exclude . and ..|
	-x	List by lines|
	-d	List directory names, not contents|
	-L	Follow symlinks|
	-H	Follow symlinks on command line|
	-R	Recurse|
	-p	Append / to directory names|
	-F	Append indicator (one of */=@|) to names|
	-l	Long format|
	-i	List inode numbers|
	-n	List numeric UIDs and GIDs instead of names|
	-s	List allocated blocks|
	-lc	List ctime|
	-lu	List atime|
	-h	Human readable sizes (1K 243M 2G)|
	-S	Sort by size|
	-X	Sort by extension|
	-v	Sort by version|
	-t	Sort by mtime|
	-tc	Sort by ctime|
	-tu	Sort by atime|
	-r	Reverse sort order|
	-w N	Format N columns wide|
stderr:
status 0
```

### pwd

```cu
(run (list "pwd" "--help") "")
```
---
```output
Usage: pwd|
|
Print the full filename of the current working directory|
stderr:
status 0
```

### mv

```cu
(run (list "mv" "--help") "")
```
---
```output
Usage: mv [-finT] SOURCE DEST|
or: mv [-fin] SOURCE... { -t DIRECTORY | DIRECTORY }|
|
Rename SOURCE to DEST, or move SOURCEs to DIRECTORY|
|
	-f	Don't prompt before overwriting|
	-i	Interactive, prompt before overwrite|
	-n	Don't overwrite an existing file|
	-T	Refuse to move if DEST is a directory|
stderr:
status 0
```

### rmdir

```cu
(run (list "rmdir" "--help") "")
```
---
```output
Usage: rmdir [-p] DIRECTORY...|
|
Remove DIRECTORY if it is empty|
|
	-p	Include parents|
stderr:
status 0
```

### install

```cu
(run (list "install" "--help") "")
```
---
```output
Usage: install [-cdDsp] [-o USER] [-g GRP] [-m MODE] [-t DIR] [SOURCE]... DEST|
|
Copy files and set attributes|
|
	-c	Just copy (default)|
	-d	Create directories|
	-D	Create leading target directories|
	-p	Preserve date|
	-o USER	Set ownership|
	-g GRP	Set group ownership|
	-m MODE	Set permissions|
	-t DIR	Install to DIR|
stderr:
status 0
```

### mktemp

```cu
(run (list "mktemp" "--help") "")
```
---
```output
Usage: mktemp [-dt] [-p DIR] [TEMPLATE]|
|
Create a temporary file with name based on TEMPLATE and print its name.|
TEMPLATE must end with XXXXXX (e.g. [/dir/]nameXXXXXX).|
Without TEMPLATE, -t tmp.XXXXXX is assumed.|
|
	-d	Make directory, not file|
	-q	Fail silently on errors|
	-t	Prepend base directory name to TEMPLATE|
	-p DIR	Use DIR as a base directory (implies -t)|
	-u	Do not create anything; print a name|
|
Base directory is: -p DIR, else $TMPDIR, else /tmp|
stderr:
status 0
```

### cmp

```cu
(run (list "cmp" "--help") "")
```
---
```output
Usage: cmp [-l|s] [-n NUM] FILE1 [FILE2 [SKIP1 [SKIP2]]]|
|
Compare FILE1 with FILE2 (or stdin)|
|
	-l	Show decimal offset and octal byte value for differing bytes,|
		don't stop on first mismatch|
	-s	Quiet|
	-n NUM	Compare at most NUM bytes|
stderr:
status 0
```

### diff

```cu
(run (list "diff" "--help") "")
```
---
```output
Usage: diff [-abBdiNqrTstw] [-L LABEL] [-S FILE] [-U LINES] FILE1 FILE2|
|
Compare files line by line and output the differences between them.|
This implementation supports unified diffs only.|
|
	-a	Treat all files as text|
	-b	Ignore changes in the amount of whitespace|
	-B	Ignore changes whose lines are all blank|
	-d	Try hard to find a smaller set of changes|
	-i	Ignore case differences|
	-L	Use LABEL instead of the filename in the unified header|
	-N	Treat absent files as empty|
	-q	Output only whether files differ|
	-r	Recurse|
	-S	Start with FILE when comparing directories|
	-T	Make tabs line up by prefixing a tab when necessary|
	-s	Report when two files are the same|
	-t	Expand tabs to spaces in output|
	-U	Output LINES lines of context|
	-w	Ignore all whitespace|
stderr:
status 0
```

### find

```cu
(run (list "find" "--help") "")
```
---
```output
Usage: find [-HL] [PATH]... [OPTIONS] [ACTIONS]|
|
Search for files and perform actions on them.|
First failed action stops processing of current file.|
Defaults: PATH is current directory, action is '-print'|
|
	-maxdepth N	Descend at most N levels. -maxdepth 0 applies|
			actions to command line arguments only|
	-mindepth N	Don't act on first N levels|
|
Actions:|
	( ACTIONS )	Group actions for -o / -a|
	! ACT		Invert ACT's success/failure|
	ACT1 [-a] ACT2	If ACT1 fails, stop, else do ACT2|
	ACT1 -o ACT2	If ACT1 succeeds, stop, else do ACT2|
			Note: -a has higher priority than -o|
	-name PATTERN	Match file name (w/o directory name) to PATTERN|
	-iname PATTERN	Case insensitive -name|
	-path PATTERN	Match path to PATTERN|
	-type X		File type is X (one of: f,d,l,b,c,s,p)|
	-newer FILE	mtime is more recent than FILE's|
	-size N[bck]	File size is N (c:bytes,k:kbytes,b:512 bytes(def.))|
			+/-N: file size is bigger/smaller than N|
	-empty		Match empty file/directory|
If none of the following actions is specified, -print is assumed|
	-print		Print file name|
	-print0		Print file name, NUL terminated|
	-exec CMD ARG ;	Run CMD with all instances of {} replaced by|
			file name. Fails if CMD exits with nonzero|
	-exec CMD ARG + Run CMD with {} replaced by list of file names|
stderr:
status 0
```

### env

```cu
(run (list "env" "--help") "")
```
---
```output
Usage: env [-i0] [-u NAME]... [-] [NAME=VALUE]... [PROG ARGS]|
|
Print current environment or run PROG after setting up environment|
|
	-0	NUL terminated output|
	-u NAME	Remove variable from environment|
stderr:
status 0
```

### printenv

```cu
(run (list "printenv" "--help") "")
```
---
```output
Usage: printenv [VARIABLE]...|
|
Print environment VARIABLEs.|
If no VARIABLE specified, print all.|
stderr:
status 0
```

### sleep

```cu
(run (list "sleep" "--help") "")
```
---
```output
Usage: sleep [N]...|
|
Pause for a time equal to the total of the args given, where each arg can|
have an optional suffix of (s)econds, (m)inutes, (h)ours, or (d)ays|
stderr:
status 0
```

### date

```cu
(run (list "date" "--help") "")
```
---
```output
Usage: date [OPTIONS] [+FMT] [[-s] TIME]|
|
Display time (using +FMT), or set time|
|
	-u		Work in UTC (don't convert to local time)|
	[-s] TIME	Set time to TIME|
	-d TIME		Display TIME, not 'now'|
	-D FMT		FMT (strptime format) for -s/-d TIME conversion|
	-r FILE		Display last modification time of FILE|
	-R		Output RFC-2822 date|
	-I[SPEC]	Output ISO-8601 date|
			SPEC=date (default), hours, minutes, seconds or ns|
|
Recognized TIME formats:|
	@seconds_since_1970|
	hh:mm[:ss]|
	[YYYY.]MM.DD-hh:mm[:ss]|
	YYYY-MM-DD hh:mm[:ss]|
	[[[[[YY]YY]MM]DD]hh]mm[.ss]|
	'date TIME' form accepts MMDDhhmm[[YY]YY][.ss] instead|
stderr:
status 0
```

### which

```cu
(run (list "which" "--help") "")
```
---
```output
Usage: which [-a] COMMAND...|
|
Locate COMMAND|
|
	-a	Show all matches|
stderr:
status 0
```

### wget

```cu
(run (list "wget" "--help") "")
```
---
```output
Usage: wget [-cqS] [--spider] [-O FILE] [-o LOGFILE] [--header STR]...|
	[-U AGENT] [--post-data STR | --post-file FILE] [-Y on/off]|
	[--no-check-certificate] [-P DIR] [-T SEC] [-t TRIES] URL...|
|
Retrieve files via HTTP or FTP|
|
	--spider	Only check URL existence: $? is 0 if exists|
	--header STR	Add STR (of form 'header: value') to headers|
	-U AGENT	Use AGENT for User-Agent header|
	--post-data STR	Send STR using POST method|
	--post-file FILE	Send FILE using POST method|
	--no-check-certificate	Don't validate the server's certificate|
	-c		Continue retrieval of partial download|
	-q		Quiet|
	-P DIR		Save to DIR (default .)|
	-S    		Show server response|
	-t TRIES	Retry count (default 20)|
	-T SEC		Network read timeout is SEC seconds|
	-O FILE		Save to FILE ('-' for stdout)|
	-o LOGFILE	Log messages to FILE|
	-Y on/off	Use proxy|
stderr:
status 0
```

### whois

```cu
(run (list "whois" "--help") "")
```
---
```output
Usage: whois [-i] [-h SERVER] [-p PORT] NAME...|
|
Query WHOIS info about NAME|
|
	-i	Show redirect results too|
	-h,-p	Server to query|
stderr:
status 0
```

### nc

```cu
(run (list "nc" "--help") "")
```
---
```output
Usage: nc [OPTIONS] HOST PORT  - connect|
nc [OPTIONS] -l -p PORT [HOST] [PORT]  - listen|
|
	-e PROG	Run PROG after connect (must be last)|
	-l	Listen mode, for inbound connects|
	-lk	With -e, provides persistent server|
	-p PORT	Local port|
	-s ADDR	Local address|
	-w SEC	Timeout for connects and final net reads|
	-i SEC	Delay interval for lines sent|
	-n	Don't do DNS resolution|
	-u	UDP mode|
	-b	Allow broadcasts|
	-v	Verbose|
	-o FILE	Hex dump traffic|
	-z	Zero-I/O mode (scanning)|
stderr:
status 0
```

### nslookup

```cu
(run (list "nslookup" "--help") "")
```
---
```output
Usage: nslookup [-type=QUERY_TYPE] [-debug] HOST [DNS_SERVER]|
|
Query DNS about HOST|
|
QUERY_TYPE: soa,ns,a,aaaa,cname,mx,txt,ptr,srv,any|
stderr:
status 0
```

### tftp

```cu
(run (list "tftp" "--help") "")
```
---
```output
Usage: tftp [OPTIONS] HOST [PORT]|
|
Transfer a file from/to tftp server|
|
	-l FILE	Local FILE|
	-r FILE	Remote FILE|
	-g	Get file|
	-p	Put file|
	-b SIZE	Transfer blocks in bytes|
stderr:
status 0
```

### ftpget

```cu
(run (list "ftpget" "--help") "")
```
---
```output
Usage: ftpget [OPTIONS] HOST [LOCAL_FILE] REMOTE_FILE|
|
Download a file via FTP|
|
	-c	Continue previous transfer|
	-v	Verbose|
	-u USER	Username|
	-p PASS	Password|
	-P PORT|
stderr:
status 0
```

### ftpput

```cu
(run (list "ftpput" "--help") "")
```
---
```output
Usage: ftpput [OPTIONS] HOST [REMOTE_FILE] LOCAL_FILE|
|
Upload a file to a FTP server|
|
	-v	Verbose|
	-u USER	Username|
	-p PASS	Password|
	-P PORT|
stderr:
status 0
```

### httpd

```cu
(run (list "httpd" "--help") "")
```
---
```output
Usage: httpd [-ifv[v]] [-c CONFFILE] [-p [IP:]PORT] [-M MAXCONN] [-K KILLSEC] [-u USER[:GRP]] [-r REALM] [-h HOME]|
or httpd -d/-e/-m STRING|
|
Listen for incoming HTTP requests|
|
	-i		Inetd mode|
	-f		Run in foreground|
	-v[v]		Verbose|
	-p [IP:]PORT	Bind to IP:PORT (default *:80)|
	-M NUM		Pause if NUM connections are open (default 256)|
	-K NUM		Kill CGIs after NUM seconds|
	-u USER[:GRP]	Set uid/gid after binding to port|
	-r REALM	Authentication Realm for Basic Authentication|
	-h HOME		Home directory (default .)|
	-c FILE		Configuration file (default {/etc,HOME}/httpd.conf)|
	-m STRING	MD5 crypt STRING|
	-e STRING	HTML encode STRING|
	-d STRING	URL decode STRING|
stderr:
status 0
```

### dnsd

```cu
(run (list "dnsd" "--help") "")
```
---
```output
Usage: dnsd [-dvs] [-c CONFFILE] [-t TTL_SEC] [-p PORT] [-i ADDR]|
|
Small static DNS server daemon|
|
	-c FILE	Config file|
	-t SEC	TTL|
	-p PORT	Listen on PORT|
	-i ADDR	Listen on ADDR|
	-d	Daemonize|
	-v	Verbose|
	-s	Send successful replies only. Use this if you want|
		to use /etc/resolv.conf with two nameserver lines:|
			nameserver DNSD_SERVER|
			nameserver NORMAL_DNS_SERVER|
stderr:
status 0
```

### ipcalc

```cu
(run (list "ipcalc" "--help") "")
```
---
```output
Usage: ipcalc [-bnmphs] ADDRESS[/PREFIX] [NETMASK]|
|
Calculate and display network settings from IP address|
|
	-b	Broadcast address|
	-n	Network address|
	-m	Default netmask for IP|
	-p	Prefix for IP/NETMASK|
	-h	Resolved host name|
	-s	No error messages|
stderr:
status 0
```

### xargs

```cu
(run (list "xargs" "--help") "")
```
---
```output
Usage: xargs [OPTIONS] [PROG ARGS]|
|
Run PROG on every item given by stdin|
|
	-0	NUL terminated input|
	-a FILE	Read from FILE instead of stdin|
	-r	Don't run command if input is empty|
	-t	Print the command on stderr before execution|
	-E STR,-e[STR]	STR stops input processing|
	-I STR	Replace STR within PROG ARGS with input line|
	-n N	Pass no more than N args to PROG|
	-s N	Pass command line of no more than N bytes|
	-x	Exit if size is exceeded|
stderr:
status 0
```

### vi

```cu
(run (list "vi" "--help") "")
```
---
```output
Usage: vi [-c CMD] [-R] [-H] [FILE]...|
|
Edit FILE|
|
	-c CMD	Initial command to run ($EXINIT and ~/.exrc also available)|
	-R	Read-only|
	-H	List available features|
stderr:
status 0
```

### more

```cu
(run (list "more" "--help") "")
```
---
```output
Usage: more [FILE]...|
|
View FILE (or stdin) one screenful at a time|
stderr:
status 0
```

### clear

```cu
(run (list "clear" "--help") "")
```
---
```output
Usage: clear|
|
Clear screen|
stderr:
status 0
```

### reset

```cu
(run (list "reset" "--help") "")
```
---
```output
Usage: reset|
|
Reset terminal (ESC codes) and termios (signals, buffering, echo)|
stderr:
status 0
```

### tsort

```cu
(run (list "tsort" "--help") "")
```
---
```output
Usage: tsort [FILE]|
|
Topological sort|
stderr:
status 0
```

### strings

```cu
(run (list "strings" "--help") "")
```
---
```output
Usage: strings [-fo] [-t o|d|x] [-n LEN] [FILE]...|
|
Display printable strings in a binary file|
|
	-f		Precede strings with filenames|
	-o		Precede strings with octal offsets|
	-t o|d|x	Precede strings with offsets in base 8/10/16|
	-n LEN		At least LEN characters form a string (default 4)|
stderr:
status 0
```

### cal

```cu
(run (list "cal" "--help") "")
```
---
```output
Usage: cal [-jmy] [[MONTH] YEAR]|
|
Display a calendar|
|
	-j	Use julian dates|
	-m	Week starts on Monday|
	-y	Display the entire year|
stderr:
status 0
```

### hexdump

```cu
(run (list "hexdump" "--help") "")
```
---
```output
Usage: hexdump [-bcdoxCv] [-e FMT] [-f FMT_FILE] [-n LEN] [-s OFS] [FILE]...|
|
Display FILEs (or stdin) in a user specified format|
|
	-b		1-byte octal display|
	-c		1-byte character display|
	-d		2-byte decimal display|
	-o		2-byte octal display|
	-x		2-byte hex display|
	-C		hex+ASCII 16 bytes per line|
	-v		Show all (no dup folding)|
	-e FORMAT_STR	Example: '16/1 "%02x|""\n"'|
	-f FORMAT_FILE|
	-n LENGTH	Show only first LENGTH bytes|
	-s OFFSET	Skip OFFSET bytes|
stderr:
status 0
```

### hd

```cu
(run (list "hd" "--help") "")
```
---
```output
Usage: hd FILE...|
|
hd is an alias for hexdump -C|
stderr:
status 0
```

### xxd

```cu
(run (list "xxd" "--help") "")
```
---
```output
Usage: xxd [-ri] [-ps] [-g N] [-c N] [-l LEN] [-s OFS] [-o OFS] [FILE]|
|
Hex dump FILE (or stdin)|
|
	-g N		Bytes per group (default 2)|
	-c N		Bytes per line (default:16, -ps:30, -i:12)|
	-ps		Show only hex bytes (no offset/spaces)|
	-i		C include file style|
	-l LENGTH	Show only first LENGTH bytes|
	-s OFFSET	Skip OFFSET bytes|
	-o OFFSET	Add OFFSET to displayed offset|
	-r		Reverse (with -p, assumes no offsets in input)|
stderr:
status 0
```

### fsync

```cu
(run (list "fsync" "--help") "")
```
---
```output
Usage: fsync [-d] FILE...|
|
Write all buffered blocks in FILEs to disk|
|
	-d	Avoid syncing metadata|
stderr:
status 0
```

### flock

```cu
(run (list "flock" "--help") "")
```
---
```output
Usage: flock [-sxun] FD | { FILE [-c] PROG ARGS }|
|
[Un]lock file descriptor, or lock FILE, run PROG|
|
	-s	Shared lock|
	-x	Exclusive lock (default)|
	-u	Unlock FD|
	-n	Fail rather than wait|
stderr:
status 0
```

### setsid

```cu
(run (list "setsid" "--help") "")
```
---
```output
Usage: setsid [-c] PROG ARGS|
|
Run PROG in a new session. PROG will have no controlling terminal|
and will not be affected by keyboard signals (^C etc).|
|
	-c	Set controlling terminal to stdin|
stderr:
status 0
```

### ttysize

```cu
(run (list "ttysize" "--help") "")
```
---
```output
Usage: ttysize [w] [h]|
|
Print dimensions of stdin tty, or 80x24|
stderr:
status 0
```

### nologin

```cu
(run (list "nologin" "--help") "")
```
---
```output
Usage: nologin|
|
Politely refuse a login|
stderr:
status 0
```

### pipe_progress

```cu
(run (list "pipe_progress" "--help") "")
```
---
```output
No help available|
stderr:
status 0
```

### getopt

```cu
(run (list "getopt" "--help") "")
```
---
```output
Usage: getopt [OPTIONS] [--] OPTSTRING PARAMS|
|
	-a		Allow long options starting with single -|
	-l LOPT[,...]	Long options to recognize|
	-n PROGNAME	The name under which errors are reported|
	-o OPTSTRING	Short options to recognize|
	-q		No error messages on unrecognized options|
	-Q		No normal output|
	-s SHELL	Set shell quoting conventions|
	-T		Version test (exits with 4)|
	-u		Don't quote output|
|
Example:|
|
O=`getopt -l bb: -- ab:c:: "$@"` || exit 1|
eval set -- "$O"|
while true; do|
	case "$1" in|
	-a)	echo A; shift;;|
	-b|--bb) echo "B:'$2'"; shift 2;;|
	-c)	case "$2" in|
		"")	echo C; shift 2;;|
		*)	echo "C:'$2'"; shift 2;;|
		esac;;|
	--)	shift; break;;|
	*)	echo Error; exit 1;;|
	esac|
done|
stderr:
status 0
```

### run-parts

```cu
(run (list "run-parts" "--help") "")
```
---
```output
Usage: run-parts [-a ARG]... [-u UMASK] [--reverse] [--test] [--exit-on-error] [--list] DIRECTORY|
|
Run a bunch of scripts in DIRECTORY|
|
	-a ARG		Pass ARG as argument to scripts|
	-u UMASK	Set UMASK before running scripts|
	--reverse	Reverse execution order|
	--test		Dry run|
	--exit-on-error	Exit if a script exits with non-zero|
	--list		Print names of matching files even if they are not executable|
stderr:
status 0
```

### tar

```cu
(run (list "tar" "--help") "")
```
---
```output
Usage: tar c|x|t [-zahmvokO] [-f TARFILE] [-C DIR] [-T FILE] [-X FILE] [LONGOPT]... [FILE]...|
|
Create, extract, or list files from a tar file|
|
	c	Create|
	x	Extract|
	t	List|
	-f FILE	Name of TARFILE ('-' for stdin/out)|
	-C DIR	Change to DIR before operation|
	-v	Verbose|
	-O	Extract to stdout|
	-m	Don't restore mtime|
	-o	Don't restore user:group|
	-k	Don't replace existing files|
	-z	(De)compress using gzip|
	-a	(De)compress based on extension|
	-h	Follow symlinks|
	-T FILE	File with names to include|
	-X FILE	File with glob patterns to exclude|
	--exclude PATTERN	Glob pattern to exclude|
	--overwrite		Replace existing files|
	--strip-components NUM	NUM of leading components to strip|
	--no-recursion		Don't descend in directories|
	--numeric-owner		Use numeric user:group|
	--no-same-permissions	Don't restore access permissions|
stderr:
status 0
```

### gzip

```cu
(run (list "gzip" "--help") "")
```
---
```output
Usage: gzip [-cfkdt] [FILE]...|
|
Compress FILEs (or stdin)|
|
	-d	Decompress|
	-c	Write to stdout|
	-f	Force|
	-k	Keep input files|
	-t	Test integrity|
stderr:
status 0
```

### gunzip

```cu
(run (list "gunzip" "--help") "")
```
---
```output
Usage: gunzip [-cfkt] [FILE]...|
|
Decompress FILEs (or stdin)|
|
	-c	Write to stdout|
	-f	Force|
	-k	Keep input files|
	-t	Test integrity|
stderr:
status 0
```

### zcat

```cu
(run (list "zcat" "--help") "")
```
---
```output
Usage: zcat [FILE]...|
|
Decompress to stdout|
stderr:
status 0
```

### hostname

```cu
(run (list "hostname" "--help") "")
```
---
```output
Usage: hostname [-sidf] [HOSTNAME | -F FILE]|
|
Show or set hostname or DNS domain name|
|
	-s	Short|
	-i	Addresses for the hostname|
	-d	DNS domain name|
	-f	Fully qualified domain name|
	-F FILE	Use FILE's content as hostname|
stderr:
status 0
```

### hostid

```cu
(run (list "hostid" "--help") "")
```
---
```output
Usage: hostid|
|
Print out a unique 32-bit identifier for the machine|
stderr:
status 0
```

### mountpoint

```cu
(run (list "mountpoint" "--help") "")
```
---
```output
Usage: mountpoint [-q] { [-dn] DIR | -x DEVICE }|
|
Check if DIR is a mountpoint|
|
	-q	Quiet|
	-d	Print major:minor of the filesystem|
	-n	Print device name of the filesystem|
	-x	Print major:minor of DEVICE|
stderr:
status 0
```

### mknod

```cu
(run (list "mknod" "--help") "")
```
---
```output
Usage: mknod [-m MODE] NAME TYPE [MAJOR MINOR]|
|
Create a special file (block, character, or pipe)|
|
	-m MODE	Creation mode (default a=rw)|
TYPE:|
	b	Block device|
	c or u	Character device|
	p	Named pipe (MAJOR MINOR must be omitted)|
stderr:
status 0
```

### mesg

```cu
(run (list "mesg" "--help") "")
```
---
```output
Usage: mesg [y|n]|
|
Control write access to your terminal|
	y	Allow write access to your terminal|
	n	Disallow write access to your terminal|
stderr:
status 0
```

### renice

```cu
(run (list "renice" "--help") "")
```
---
```output
Usage: renice [-n] PRIORITY [[-p|g|u] ID...]...|
|
Change scheduling priority of a running process|
|
	-n	Add PRIORITY to current nice value|
		Without -n, nice value is set to PRIORITY|
	-p	Process ids (default)|
	-g	Process group ids|
	-u	Process user names|
stderr:
status 0
```

### ts

```cu
(run (list "ts" "--help") "")
```
---
```output
Usage: ts [-is] [STRFTIME]|
|
Pipe stdin to stdout, add timestamp to each line|
|
	-s	Time since start|
	-i	Time since previous line|
stderr:
status 0
```

### sha384sum

```cu
(run (list "sha384sum" "--help") "")
```
---
```output
Usage: sha384sum [-c[sw]] [FILE]...|
|
Print or check SHA384 checksums|
|
	-c	Check sums against list in FILEs|
	-s	Don't output anything, status code shows success|
	-w	Warn about improperly formatted checksum lines|
stderr:
status 0
```

### tree

```cu
(run (list "tree" "--help") "")
```
---
```output
No help available|
stderr:
status 0
```

### time

```cu
(run (list "time" "--help") "")
```
---
```output
Usage: time [-vpa] [-o FILE] PROG ARGS|
|
Run PROG, display resource usage when it exits|
|
	-v	Verbose|
	-p	POSIX output format|
	-f FMT	Custom format|
	-o FILE	Write result to FILE|
	-a	Append (else overwrite)|
stderr:
status 0
```

### base32

```cu
(run (list "base32" "--help") "")
```
---
```output
Usage: base32 [-d] [-w COL] [FILE]|
|
Base32 encode or decode FILE to standard output|
|
	-d	Decode data|
	-w COL	Wrap lines at COL (default 76, 0 disables)|
stderr:
status 0
```

### crc32

```cu
(run (list "crc32" "--help") "")
```
---
```output
Usage: crc32 FILE...|
|
Calculate CRC32 checksum of FILEs|
stderr:
status 0
```

### ascii

```cu
(run (list "ascii" "--help") "")
```
---
```output
No help available|
stderr:
status 0
```

### uuidgen

```cu
(run (list "uuidgen" "--help") "")
```
---
```output
Usage: uuidgen|
|
Generate a random UUID|
stderr:
status 0
```

### uptime

```cu
(run (list "uptime" "--help") "")
```
---
```output
Usage: uptime|
|
Display the time since the last boot|
stderr:
status 0
```

### free

```cu
(run (list "free" "--help") "")
```
---
```output
Usage: free [-bkmgh]|
|
Display free and used memory|
stderr:
status 0
```

### ps

busybox's usage names -T as well, which ps does not accept: threads are not in
the records it reads.

```cu
(run (list "ps" "--help") "")
```
---
```output
Usage: ps [-o COL1,COL2=HEADER]|
|
Show list of processes|
|
	-o COL1,COL2=HEADER	Select columns for display|
stderr:
status 0
```

### pidof

```cu
(run (list "pidof" "--help") "")
```
---
```output
Usage: pidof [-s] [-o PID] [NAME]...|
|
List PIDs of all processes with names that match NAMEs|
|
	-s	Show only one PID|
	-o PID	Omit given pid|
		Use %PPID to omit pid of pidof's parent|
stderr:
status 0
```

### pgrep

```cu
(run (list "pgrep" "--help") "")
```
---
```output
Usage: pgrep [-flanovx] [-s SID|-P PPID|PATTERN]|
|
Display process(es) selected by regex PATTERN|
|
	-l	Show command name too|
	-a	Show command line too|
	-f	Match against entire command line|
	-n	Show the newest process only|
	-o	Show the oldest process only|
	-v	Negate the match|
	-x	Match whole name (not substring)|
	-s	Match session ID (0 for current)|
	-P	Match parent process ID|
stderr:
status 0
```

### pkill

```cu
(run (list "pkill" "--help") "")
```
---
```output
Usage: pkill [-l|-SIGNAL] [-xfvnoe] [-s SID|-P PPID|PATTERN]|
|
Send signal to processes selected by regex PATTERN|
|
	-l	List all signals|
	-x	Match whole name (not substring)|
	-f	Match against entire command line|
	-s SID	Match session ID (0 for current)|
	-P PPID	Match parent process ID|
	-v	Negate the match|
	-n	Signal the newest process only|
	-o	Signal the oldest process only|
	-e	Display name and PID of the process being killed|
stderr:
status 0
```

### test

```cu
(run (list "test" "--help") "")
```
---
```output
stderr:
status 0
```

### [

```cu
(run (list "[" "--help") "")
```
---
```output
stderr:
[: missing ]
status 2
```

## the cleanup

### the scratch directory goes

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-help")) (display "gone"))
```
---
    gone
