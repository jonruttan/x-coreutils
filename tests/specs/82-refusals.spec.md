# @weight 1

An option an applet does not take, as busybox refuses it: musl getopt's line
-- `unrecognized option: C` for a letter, `unrecognized option: NAME` for a
long option, `option requires an argument: C` for a value option given none --
then the applet's usage text, on standard error, and 1 (2 for sort and tty).
An applet busybox gives no options to takes the word as an operand, as its own
grammar reads it.  Each case is `APPLET -~`, `APPLET --nope`, or the applet's
first value option alone; every expectation is busybox's own output, from a
busybox built from its source, less the banner line its usage text starts
with, and the rows for options this bundle does not take, as its help text
leaves them out.  A `|` marks the end of each line written to standard output.

nohup is left out: it rebinds standard input, which this runner reads from;
chroot too: what chroot(2) answers depends on who runs it.
`ln -t` is left out: this ln takes `-t DIR`, as GNU's does, where busybox's
refuses it.

## the fixture

### a run of an applet, with its stdout, stderr and status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-refuse && mkdir -p /tmp/x-cu-refuse")) (def nf (fn (_ n) (string-append "/tmp/x-cu-refuse/" n))) (def run (fn (_ argv in) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv in)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (Str8 replace "\n" "|\n" (file-read-all (nf ".out"))) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n")))))))) (display "made"))
```
---
    made

## each applet's refusals

### cat -~

```cu
(run (list "cat" "-~") "")
```
---
```output
stderr:
cat: unrecognized option: ~
Usage: cat [-nbvteA] [FILE]...

Print FILEs to stdout

	-n	Number output lines
	-b	Number nonempty lines
	-v	Show nonprinting characters as ^x or M-x
	-t	...and tabs as ^I
	-e	...and end lines with $
	-A	Same as -vte
status 1
```

### cat --nope

```cu
(run (list "cat" "--nope") "")
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
```

### sort -~

```cu
(run (list "sort" "-~") "")
```
---
```output
stderr:
sort: unrecognized option: ~
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

### sort --nope

```cu
(run (list "sort" "--nope") "")
```
---
```output
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

### sort -o

```cu
(run (list "sort" "-o") "")
```
---
```output
stderr:
sort: option requires an argument: o
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

### uniq -~

```cu
(run (list "uniq" "-~") "")
```
---
```output
stderr:
uniq: unrecognized option: ~
Usage: uniq [-cduiz] [-f,s,w N] [FILE [OUTFILE]]

Discard duplicate lines

	-c	Prefix lines by the number of occurrences
	-d	Only print duplicate lines
	-u	Only print unique lines
	-i	Ignore case
	-f N	Skip first N fields
	-s N	Skip first N chars (after any skipped fields)
	-w N	Compare N characters in line
status 1
```

### uniq --nope

```cu
(run (list "uniq" "--nope") "")
```
---
```output
stderr:
uniq: unrecognized option: nope
Usage: uniq [-cduiz] [-f,s,w N] [FILE [OUTFILE]]

Discard duplicate lines

	-c	Prefix lines by the number of occurrences
	-d	Only print duplicate lines
	-u	Only print unique lines
	-i	Ignore case
	-f N	Skip first N fields
	-s N	Skip first N chars (after any skipped fields)
	-w N	Compare N characters in line
status 1
```

### uniq -f

```cu
(run (list "uniq" "-f") "")
```
---
```output
stderr:
uniq: option requires an argument: f
Usage: uniq [-cduiz] [-f,s,w N] [FILE [OUTFILE]]

Discard duplicate lines

	-c	Prefix lines by the number of occurrences
	-d	Only print duplicate lines
	-u	Only print unique lines
	-i	Ignore case
	-f N	Skip first N fields
	-s N	Skip first N chars (after any skipped fields)
	-w N	Compare N characters in line
status 1
```

### head -~

```cu
(run (list "head" "-~") "")
```
---
```output
stderr:
head: unrecognized option: ~
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
```

### head --nope

```cu
(run (list "head" "--nope") "")
```
---
```output
stderr:
head: unrecognized option: -
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
```

### head -n

```cu
(run (list "head" "-n") "")
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
```

### tail -~

```cu
(run (list "tail" "-~") "")
```
---
```output
stderr:
tail: unrecognized option: ~
Usage: tail [OPTIONS] [FILE]...

Print last 10 lines of FILEs (or stdin) to.
With more than one FILE, precede each with a filename header.

	-c [+]N[bkm]	Print last N bytes
	-n N[bkm]	Print last N lines
	-n +N[bkm]	Start on Nth line and print the rest
			(b:*512 k:*1024 m:*1024^2)
	-q		Never print headers
	-v		Always print headers
	-f		Print data as file grows
	-s SECONDS	Wait SECONDS between reads with -f
status 1
```

### tail --nope

```cu
(run (list "tail" "--nope") "")
```
---
```output
stderr:
tail: unrecognized option: nope
Usage: tail [OPTIONS] [FILE]...

Print last 10 lines of FILEs (or stdin) to.
With more than one FILE, precede each with a filename header.

	-c [+]N[bkm]	Print last N bytes
	-n N[bkm]	Print last N lines
	-n +N[bkm]	Start on Nth line and print the rest
			(b:*512 k:*1024 m:*1024^2)
	-q		Never print headers
	-v		Always print headers
	-f		Print data as file grows
	-s SECONDS	Wait SECONDS between reads with -f
status 1
```

### tail -n

```cu
(run (list "tail" "-n") "")
```
---
```output
stderr:
tail: option requires an argument: n
Usage: tail [OPTIONS] [FILE]...

Print last 10 lines of FILEs (or stdin) to.
With more than one FILE, precede each with a filename header.

	-c [+]N[bkm]	Print last N bytes
	-n N[bkm]	Print last N lines
	-n +N[bkm]	Start on Nth line and print the rest
			(b:*512 k:*1024 m:*1024^2)
	-q		Never print headers
	-v		Always print headers
	-f		Print data as file grows
	-s SECONDS	Wait SECONDS between reads with -f
status 1
```

### wc -~

```cu
(run (list "wc" "-~") "")
```
---
```output
stderr:
wc: unrecognized option: ~
Usage: wc [-cmlwL] [FILE]...

Count lines, words, and bytes for FILEs (or stdin)

	-c	Count bytes
	-m	Count characters
	-l	Count newlines
	-w	Count words
	-L	Print longest line length
status 1
```

### wc --nope

```cu
(run (list "wc" "--nope") "")
```
---
```output
stderr:
wc: unrecognized option: nope
Usage: wc [-cmlwL] [FILE]...

Count lines, words, and bytes for FILEs (or stdin)

	-c	Count bytes
	-m	Count characters
	-l	Count newlines
	-w	Count words
	-L	Print longest line length
status 1
```

### comm -~

```cu
(run (list "comm" "-~") "")
```
---
```output
stderr:
comm: unrecognized option: ~
Usage: comm [-123] FILE1 FILE2

Compare FILE1 with FILE2

	-1	Suppress lines unique to FILE1
	-2	Suppress lines unique to FILE2
	-3	Suppress lines common to both files
status 1
```

### comm --nope

```cu
(run (list "comm" "--nope") "")
```
---
```output
stderr:
comm: unrecognized option: nope
Usage: comm [-123] FILE1 FILE2

Compare FILE1 with FILE2

	-1	Suppress lines unique to FILE1
	-2	Suppress lines unique to FILE2
	-3	Suppress lines common to both files
status 1
```

### join -~

```cu
(run (list "join" "-~") "")
```
---
```output
stderr:
join: unrecognized option: ~
Usage: join [-a 1|2 | -v 1|2] [-e STR] [-o LIST] [-t SEP_CHAR] [-1 NUM] [-2 NUM] FILE1 FILE2

Join FILE1 and FILE2, writing to stdout

	-t CHAR	Use a different field separator

LIST is a space or comma separated list of 1/2.FIELD or 0 (the join field)
status 1
```

### join --nope

```cu
(run (list "join" "--nope") "")
```
---
```output
stderr:
join: unrecognized option: nope
Usage: join [-a 1|2 | -v 1|2] [-e STR] [-o LIST] [-t SEP_CHAR] [-1 NUM] [-2 NUM] FILE1 FILE2

Join FILE1 and FILE2, writing to stdout

	-t CHAR	Use a different field separator

LIST is a space or comma separated list of 1/2.FIELD or 0 (the join field)
status 1
```

### join -t

```cu
(run (list "join" "-t") "")
```
---
```output
stderr:
join: option requires an argument: t
Usage: join [-a 1|2 | -v 1|2] [-e STR] [-o LIST] [-t SEP_CHAR] [-1 NUM] [-2 NUM] FILE1 FILE2

Join FILE1 and FILE2, writing to stdout

	-t CHAR	Use a different field separator

LIST is a space or comma separated list of 1/2.FIELD or 0 (the join field)
status 1
```

### tr -~

```cu
(run (list "tr" "-~") "")
```
---
```output
stderr:
tr: unrecognized option: ~
Usage: tr [-cds] STRING1 [STRING2]

Translate, squeeze, or delete characters from stdin, writing to stdout

	-c	Take complement of STRING1
	-d	Delete input characters coded STRING1
	-s	Squeeze multiple output characters of STRING2 into one character
status 1
```

### tr --nope

```cu
(run (list "tr" "--nope") "")
```
---
```output
stderr:
tr: unrecognized option: nope
Usage: tr [-cds] STRING1 [STRING2]

Translate, squeeze, or delete characters from stdin, writing to stdout

	-c	Take complement of STRING1
	-d	Delete input characters coded STRING1
	-s	Squeeze multiple output characters of STRING2 into one character
status 1
```

### cut -~

```cu
(run (list "cut" "-~") "")
```
---
```output
stderr:
cut: unrecognized option: ~
Usage: cut {-b|c LIST | -f|F LIST [-d SEP] [-s]} [-D] [-O SEP] [FILE]...

Print selected fields from FILEs to stdout

	-b LIST	Output only bytes from LIST
	-c LIST	Output only characters from LIST
	-d SEP	Input field delimiter (default -f TAB, -F run of whitespace)
	-f LIST	Print only these fields (-d is single char)
	-s	Drop lines with no delimiter (else print them in full)
	-n	Ignored
status 1
```

### cut --nope

```cu
(run (list "cut" "--nope") "")
```
---
```output
stderr:
cut: unrecognized option: nope
Usage: cut {-b|c LIST | -f|F LIST [-d SEP] [-s]} [-D] [-O SEP] [FILE]...

Print selected fields from FILEs to stdout

	-b LIST	Output only bytes from LIST
	-c LIST	Output only characters from LIST
	-d SEP	Input field delimiter (default -f TAB, -F run of whitespace)
	-f LIST	Print only these fields (-d is single char)
	-s	Drop lines with no delimiter (else print them in full)
	-n	Ignored
status 1
```

### cut -d

```cu
(run (list "cut" "-d") "")
```
---
```output
stderr:
cut: option requires an argument: d
Usage: cut {-b|c LIST | -f|F LIST [-d SEP] [-s]} [-D] [-O SEP] [FILE]...

Print selected fields from FILEs to stdout

	-b LIST	Output only bytes from LIST
	-c LIST	Output only characters from LIST
	-d SEP	Input field delimiter (default -f TAB, -F run of whitespace)
	-f LIST	Print only these fields (-d is single char)
	-s	Drop lines with no delimiter (else print them in full)
	-n	Ignored
status 1
```

### basename -~

```cu
(run (list "basename" "-~") "")
```
---
```output
stderr:
basename: unrecognized option: ~
Usage: basename FILE [SUFFIX] | -a FILE... | -s SUFFIX FILE...

Strip directory path and SUFFIX from FILE

	-s SUFFIX	Remove SUFFIX (implies -a)
status 1
```

### basename --nope

```cu
(run (list "basename" "--nope") "")
```
---
```output
stderr:
basename: unrecognized option: nope
Usage: basename FILE [SUFFIX] | -a FILE... | -s SUFFIX FILE...

Strip directory path and SUFFIX from FILE

	-s SUFFIX	Remove SUFFIX (implies -a)
status 1
```

### basename -s

```cu
(run (list "basename" "-s") "")
```
---
```output
stderr:
basename: option requires an argument: s
Usage: basename FILE [SUFFIX] | -a FILE... | -s SUFFIX FILE...

Strip directory path and SUFFIX from FILE

	-s SUFFIX	Remove SUFFIX (implies -a)
status 1
```

### dirname -~

```cu
(run (list "dirname" "-~") "")
```
---
```output
.|
stderr:
status 0
```

### dirname --nope

```cu
(run (list "dirname" "--nope") "")
```
---
```output
.|
stderr:
status 0
```

### cp -~

```cu
(run (list "cp" "-~") "")
```
---
```output
stderr:
cp: unrecognized option: ~
Usage: cp [-arPLHpfinlsTu] SOURCE DEST
or: cp [-arPLHpfinlsu] SOURCE... { -t DIRECTORY | DIRECTORY }

Copy SOURCEs to DEST

	-a	Same as -dpR
	-R,-r	Recurse
	-L	Follow all symlinks
	-H	Follow symlinks on command line
	-p	Preserve file attributes if possible
	-f	Overwrite
	-i	Prompt before overwrite
	-l,-s	Create (sym)links
	-T	Refuse to copy if DEST is a directory
	-u	Copy only newer files
status 1
```

### cp --nope

```cu
(run (list "cp" "--nope") "")
```
---
```output
stderr:
cp: unrecognized option: nope
Usage: cp [-arPLHpfinlsTu] SOURCE DEST
or: cp [-arPLHpfinlsu] SOURCE... { -t DIRECTORY | DIRECTORY }

Copy SOURCEs to DEST

	-a	Same as -dpR
	-R,-r	Recurse
	-L	Follow all symlinks
	-H	Follow symlinks on command line
	-p	Preserve file attributes if possible
	-f	Overwrite
	-i	Prompt before overwrite
	-l,-s	Create (sym)links
	-T	Refuse to copy if DEST is a directory
	-u	Copy only newer files
status 1
```

### rm -~

```cu
(run (list "rm" "-~") "")
```
---
```output
stderr:
rm: unrecognized option: ~
Usage: rm [-irf] FILE...

Remove (unlink) FILEs

	-i	Always prompt before removing
	-f	Never prompt
	-R,-r	Recurse
status 1
```

### rm --nope

```cu
(run (list "rm" "--nope") "")
```
---
```output
stderr:
rm: unrecognized option: nope
Usage: rm [-irf] FILE...

Remove (unlink) FILEs

	-i	Always prompt before removing
	-f	Never prompt
	-R,-r	Recurse
status 1
```

### mkdir -~

```cu
(run (list "mkdir" "-~") "")
```
---
```output
stderr:
mkdir: unrecognized option: ~
Usage: mkdir [-m MODE] [-p] DIRECTORY...

Create DIRECTORY

	-m MODE	Mode
	-p	No error if exists; make parent directories as needed
status 1
```

### mkdir --nope

```cu
(run (list "mkdir" "--nope") "")
```
---
```output
stderr:
mkdir: unrecognized option: nope
Usage: mkdir [-m MODE] [-p] DIRECTORY...

Create DIRECTORY

	-m MODE	Mode
	-p	No error if exists; make parent directories as needed
status 1
```

### mkdir -m

```cu
(run (list "mkdir" "-m") "")
```
---
```output
stderr:
mkdir: option requires an argument: m
Usage: mkdir [-m MODE] [-p] DIRECTORY...

Create DIRECTORY

	-m MODE	Mode
	-p	No error if exists; make parent directories as needed
status 1
```

### sha256sum -~

```cu
(run (list "sha256sum" "-~") "")
```
---
```output
stderr:
sha256sum: unrecognized option: ~
Usage: sha256sum [-c[sw]] [FILE]...

Print or check SHA256 checksums

	-c	Check sums against list in FILEs
	-s	Don't output anything, status code shows success
	-w	Warn about improperly formatted checksum lines
status 1
```

### sha256sum --nope

```cu
(run (list "sha256sum" "--nope") "")
```
---
```output
stderr:
sha256sum: unrecognized option: nope
Usage: sha256sum [-c[sw]] [FILE]...

Print or check SHA256 checksums

	-c	Check sums against list in FILEs
	-s	Don't output anything, status code shows success
	-w	Warn about improperly formatted checksum lines
status 1
```

### md5sum -~

```cu
(run (list "md5sum" "-~") "")
```
---
```output
stderr:
md5sum: unrecognized option: ~
Usage: md5sum [-c[sw]] [FILE]...

Print or check MD5 checksums

	-c	Check sums against list in FILEs
	-s	Don't output anything, status code shows success
	-w	Warn about improperly formatted checksum lines
status 1
```

### md5sum --nope

```cu
(run (list "md5sum" "--nope") "")
```
---
```output
stderr:
md5sum: unrecognized option: nope
Usage: md5sum [-c[sw]] [FILE]...

Print or check MD5 checksums

	-c	Check sums against list in FILEs
	-s	Don't output anything, status code shows success
	-w	Warn about improperly formatted checksum lines
status 1
```

### sha1sum -~

```cu
(run (list "sha1sum" "-~") "")
```
---
```output
stderr:
sha1sum: unrecognized option: ~
Usage: sha1sum [-c[sw]] [FILE]...

Print or check SHA1 checksums

	-c	Check sums against list in FILEs
	-s	Don't output anything, status code shows success
	-w	Warn about improperly formatted checksum lines
status 1
```

### sha1sum --nope

```cu
(run (list "sha1sum" "--nope") "")
```
---
```output
stderr:
sha1sum: unrecognized option: nope
Usage: sha1sum [-c[sw]] [FILE]...

Print or check SHA1 checksums

	-c	Check sums against list in FILEs
	-s	Don't output anything, status code shows success
	-w	Warn about improperly formatted checksum lines
status 1
```

### sha512sum -~

```cu
(run (list "sha512sum" "-~") "")
```
---
```output
stderr:
sha512sum: unrecognized option: ~
Usage: sha512sum [-c[sw]] [FILE]...

Print or check SHA512 checksums

	-c	Check sums against list in FILEs
	-s	Don't output anything, status code shows success
	-w	Warn about improperly formatted checksum lines
status 1
```

### sha512sum --nope

```cu
(run (list "sha512sum" "--nope") "")
```
---
```output
stderr:
sha512sum: unrecognized option: nope
Usage: sha512sum [-c[sw]] [FILE]...

Print or check SHA512 checksums

	-c	Check sums against list in FILEs
	-s	Don't output anything, status code shows success
	-w	Warn about improperly formatted checksum lines
status 1
```

### cksum -~

```cu
(run (list "cksum" "-~") "")
```
---
```output
stderr:
cksum: unrecognized option: ~
Usage: cksum FILE...

Calculate CRC32 checksum of FILEs
status 1
```

### cksum --nope

```cu
(run (list "cksum" "--nope") "")
```
---
```output
stderr:
cksum: unrecognized option: nope
Usage: cksum FILE...

Calculate CRC32 checksum of FILEs
status 1
```

### sum -~

```cu
(run (list "sum" "-~") "")
```
---
```output
stderr:
sum: unrecognized option: ~
Usage: sum [-rs] [FILE]...

Checksum and count the blocks in a file

	-r	Use BSD sum algorithm (1K blocks)
	-s	Use System V sum algorithm (512byte blocks)
status 1
```

### sum --nope

```cu
(run (list "sum" "--nope") "")
```
---
```output
stderr:
sum: unrecognized option: nope
Usage: sum [-rs] [FILE]...

Checksum and count the blocks in a file

	-r	Use BSD sum algorithm (1K blocks)
	-s	Use System V sum algorithm (512byte blocks)
status 1
```

### factor -~

```cu
(run (list "factor" "-~") "")
```
---
```output
stderr:
Usage: factor [NUMBER]...

Print prime factors
status 1
```

### factor --nope

```cu
(run (list "factor" "--nope") "")
```
---
```output
stderr:
Usage: factor [NUMBER]...

Print prime factors
status 1
```

### expand -~

```cu
(run (list "expand" "-~") "")
```
---
```output
stderr:
expand: unrecognized option: ~
Usage: expand [-i] [-t N] [FILE]...

Convert tabs to spaces, writing to stdout

	-i	Don't convert tabs after non blanks
	-t	Tabstops every N chars
status 1
```

### expand --nope

```cu
(run (list "expand" "--nope") "")
```
---
```output
stderr:
expand: unrecognized option: nope
Usage: expand [-i] [-t N] [FILE]...

Convert tabs to spaces, writing to stdout

	-i	Don't convert tabs after non blanks
	-t	Tabstops every N chars
status 1
```

### expand -t

```cu
(run (list "expand" "-t") "")
```
---
```output
stderr:
expand: option requires an argument: t
Usage: expand [-i] [-t N] [FILE]...

Convert tabs to spaces, writing to stdout

	-i	Don't convert tabs after non blanks
	-t	Tabstops every N chars
status 1
```

### unexpand -~

```cu
(run (list "unexpand" "-~") "")
```
---
```output
stderr:
unexpand: unrecognized option: ~
Usage: unexpand [-fa][-t N] [FILE]...

Convert spaces to tabs, writing to stdout

	-a	Convert all blanks
	-f	Convert only leading blanks
	-t N	Tabstops every N chars
status 1
```

### unexpand --nope

```cu
(run (list "unexpand" "--nope") "")
```
---
```output
stderr:
unexpand: unrecognized option: nope
Usage: unexpand [-fa][-t N] [FILE]...

Convert spaces to tabs, writing to stdout

	-a	Convert all blanks
	-f	Convert only leading blanks
	-t N	Tabstops every N chars
status 1
```

### unexpand -t

```cu
(run (list "unexpand" "-t") "")
```
---
```output
stderr:
unexpand: option requires an argument: t
Usage: unexpand [-fa][-t N] [FILE]...

Convert spaces to tabs, writing to stdout

	-a	Convert all blanks
	-f	Convert only leading blanks
	-t N	Tabstops every N chars
status 1
```

### dos2unix -~

```cu
(run (list "dos2unix" "-~") "")
```
---
```output
stderr:
dos2unix: unrecognized option: ~
Usage: dos2unix [-ud] [FILE]

Convert FILE in-place from DOS to Unix format.
When no file is given, use stdin/stdout.

	-u	dos2unix
	-d	unix2dos
status 1
```

### dos2unix --nope

```cu
(run (list "dos2unix" "--nope") "")
```
---
```output
stderr:
dos2unix: unrecognized option: nope
Usage: dos2unix [-ud] [FILE]

Convert FILE in-place from DOS to Unix format.
When no file is given, use stdin/stdout.

	-u	dos2unix
	-d	unix2dos
status 1
```

### unix2dos -~

```cu
(run (list "unix2dos" "-~") "")
```
---
```output
stderr:
unix2dos: unrecognized option: ~
Usage: unix2dos [-ud] [FILE]

Convert FILE in-place from Unix to DOS format.
When no file is given, use stdin/stdout.

	-u	dos2unix
	-d	unix2dos
status 1
```

### unix2dos --nope

```cu
(run (list "unix2dos" "--nope") "")
```
---
```output
stderr:
unix2dos: unrecognized option: nope
Usage: unix2dos [-ud] [FILE]

Convert FILE in-place from Unix to DOS format.
When no file is given, use stdin/stdout.

	-u	dos2unix
	-d	unix2dos
status 1
```

### split -~

```cu
(run (list "split" "-~") "")
```
---
```output
stderr:
split: unrecognized option: ~
Usage: split [OPTIONS] [INPUT [PREFIX]]

	-b N[k|m]	Split by N (kilo|mega)bytes
	-l N		Split by N lines
	-a N		Use N letters as suffix
status 1
```

### split --nope

```cu
(run (list "split" "--nope") "")
```
---
```output
stderr:
split: unrecognized option: nope
Usage: split [OPTIONS] [INPUT [PREFIX]]

	-b N[k|m]	Split by N (kilo|mega)bytes
	-l N		Split by N lines
	-a N		Use N letters as suffix
status 1
```

### split -b

```cu
(run (list "split" "-b") "")
```
---
```output
stderr:
split: option requires an argument: b
Usage: split [OPTIONS] [INPUT [PREFIX]]

	-b N[k|m]	Split by N (kilo|mega)bytes
	-l N		Split by N lines
	-a N		Use N letters as suffix
status 1
```

### shuf -~

```cu
(run (list "shuf" "-~") "")
```
---
```output
stderr:
shuf: unrecognized option: ~
Usage: shuf [-n NUM] [-o FILE] [-z] [FILE | -e [ARG...] | -i L-H]

Randomly permute lines

	-n NUM	Output at most NUM lines
	-o FILE	Write to FILE, not standard output
	-z	NUL terminated output
	-e	Treat ARGs as lines
	-i L-H	Treat numbers L-H as lines
status 1
```

### shuf --nope

```cu
(run (list "shuf" "--nope") "")
```
---
```output
stderr:
shuf: unrecognized option: nope
Usage: shuf [-n NUM] [-o FILE] [-z] [FILE | -e [ARG...] | -i L-H]

Randomly permute lines

	-n NUM	Output at most NUM lines
	-o FILE	Write to FILE, not standard output
	-z	NUL terminated output
	-e	Treat ARGs as lines
	-i L-H	Treat numbers L-H as lines
status 1
```

### shuf -n

```cu
(run (list "shuf" "-n") "")
```
---
```output
stderr:
shuf: option requires an argument: n
Usage: shuf [-n NUM] [-o FILE] [-z] [FILE | -e [ARG...] | -i L-H]

Randomly permute lines

	-n NUM	Output at most NUM lines
	-o FILE	Write to FILE, not standard output
	-z	NUL terminated output
	-e	Treat ARGs as lines
	-i L-H	Treat numbers L-H as lines
status 1
```

### base64 -~

```cu
(run (list "base64" "-~") "")
```
---
```output
stderr:
base64: unrecognized option: ~
Usage: base64 [-d] [-w COL] [FILE]

Base64 encode or decode FILE to standard output

	-d	Decode data
	-w COL	Wrap lines at COL (default 76, 0 disables)
status 1
```

### base64 --nope

```cu
(run (list "base64" "--nope") "")
```
---
```output
stderr:
base64: unrecognized option: nope
Usage: base64 [-d] [-w COL] [FILE]

Base64 encode or decode FILE to standard output

	-d	Decode data
	-w COL	Wrap lines at COL (default 76, 0 disables)
status 1
```

### base64 -w

```cu
(run (list "base64" "-w") "")
```
---
```output
stderr:
base64: option requires an argument: w
Usage: base64 [-d] [-w COL] [FILE]

Base64 encode or decode FILE to standard output

	-d	Decode data
	-w COL	Wrap lines at COL (default 76, 0 disables)
status 1
```

### stat -~

```cu
(run (list "stat" "-~") "")
```
---
```output
stderr:
stat: unrecognized option: ~
Usage: stat [-ltf] [-c FMT] FILE...

Display file (default) or filesystem status

	-c FMT	Use the specified format
	-f	Display filesystem status
	-L	Follow links
	-t	Terse display

FMT sequences for files:
 %a	Access rights in octal
 %A	Access rights in human readable form
 %b	Number of blocks allocated (see %B)
 %B	Size in bytes of each block reported by %b
 %d	Device number in decimal
 %D	Device number in hex
 %f	Raw mode in hex
 %F	File type
 %g	Group ID
 %G	Group name
 %h	Number of hard links
 %i	Inode number
 %n	File name
 %N	File name, with -> TARGET if symlink
 %o	I/O block size
 %s	Total size in bytes
 %t	Major device type in hex
 %T	Minor device type in hex
 %u	User ID
 %U	User name
 %x	Time of last access
 %X	Time of last access as seconds since Epoch
 %y	Time of last modification
 %Y	Time of last modification as seconds since Epoch
 %z	Time of last change
 %Z	Time of last change as seconds since Epoch

FMT sequences for file systems:
 %a	Free blocks available to non-superuser
 %b	Total data blocks
 %c	Total file nodes
 %d	Free file nodes
 %f	Free blocks
 %i	File System ID in hex
 %l	Maximum length of filenames
 %n	File name
 %s	Block size (for faster transfer)
 %S	Fundamental block size (for block counts)
 %t	Type in hex
 %T	Type in human readable form
status 1
```

### stat --nope

```cu
(run (list "stat" "--nope") "")
```
---
```output
stderr:
stat: unrecognized option: nope
Usage: stat [-ltf] [-c FMT] FILE...

Display file (default) or filesystem status

	-c FMT	Use the specified format
	-f	Display filesystem status
	-L	Follow links
	-t	Terse display

FMT sequences for files:
 %a	Access rights in octal
 %A	Access rights in human readable form
 %b	Number of blocks allocated (see %B)
 %B	Size in bytes of each block reported by %b
 %d	Device number in decimal
 %D	Device number in hex
 %f	Raw mode in hex
 %F	File type
 %g	Group ID
 %G	Group name
 %h	Number of hard links
 %i	Inode number
 %n	File name
 %N	File name, with -> TARGET if symlink
 %o	I/O block size
 %s	Total size in bytes
 %t	Major device type in hex
 %T	Minor device type in hex
 %u	User ID
 %U	User name
 %x	Time of last access
 %X	Time of last access as seconds since Epoch
 %y	Time of last modification
 %Y	Time of last modification as seconds since Epoch
 %z	Time of last change
 %Z	Time of last change as seconds since Epoch

FMT sequences for file systems:
 %a	Free blocks available to non-superuser
 %b	Total data blocks
 %c	Total file nodes
 %d	Free file nodes
 %f	Free blocks
 %i	File System ID in hex
 %l	Maximum length of filenames
 %n	File name
 %s	Block size (for faster transfer)
 %S	Fundamental block size (for block counts)
 %t	Type in hex
 %T	Type in human readable form
status 1
```

### stat -c

```cu
(run (list "stat" "-c") "")
```
---
```output
stderr:
stat: option requires an argument: c
Usage: stat [-ltf] [-c FMT] FILE...

Display file (default) or filesystem status

	-c FMT	Use the specified format
	-f	Display filesystem status
	-L	Follow links
	-t	Terse display

FMT sequences for files:
 %a	Access rights in octal
 %A	Access rights in human readable form
 %b	Number of blocks allocated (see %B)
 %B	Size in bytes of each block reported by %b
 %d	Device number in decimal
 %D	Device number in hex
 %f	Raw mode in hex
 %F	File type
 %g	Group ID
 %G	Group name
 %h	Number of hard links
 %i	Inode number
 %n	File name
 %N	File name, with -> TARGET if symlink
 %o	I/O block size
 %s	Total size in bytes
 %t	Major device type in hex
 %T	Minor device type in hex
 %u	User ID
 %U	User name
 %x	Time of last access
 %X	Time of last access as seconds since Epoch
 %y	Time of last modification
 %Y	Time of last modification as seconds since Epoch
 %z	Time of last change
 %Z	Time of last change as seconds since Epoch

FMT sequences for file systems:
 %a	Free blocks available to non-superuser
 %b	Total data blocks
 %c	Total file nodes
 %d	Free file nodes
 %f	Free blocks
 %i	File System ID in hex
 %l	Maximum length of filenames
 %n	File name
 %s	Block size (for faster transfer)
 %S	Fundamental block size (for block counts)
 %t	Type in hex
 %T	Type in human readable form
status 1
```

### du -~

```cu
(run (list "du" "-~") "")
```
---
```output
stderr:
du: unrecognized option: ~
Usage: du [-aHLdclsxhmk] [FILE]...

Summarize disk space used for FILEs (or directories)

	-a	Show file sizes too
	-L	Follow all symlinks
	-H	Follow symlinks on command line
	-d N	Limit output to directories (and files with -a) of depth < N
	-c	Show grand total
	-l	Count sizes many times if hard linked
	-s	Display only a total for each argument
	-x	Skip directories on different filesystems
	-h	Sizes in human readable format (e.g., 1K 243M 2G)
	-m	Sizes in megabytes
	-k	Sizes in kilobytes (default)
status 1
```

### du --nope

```cu
(run (list "du" "--nope") "")
```
---
```output
stderr:
du: unrecognized option: nope
Usage: du [-aHLdclsxhmk] [FILE]...

Summarize disk space used for FILEs (or directories)

	-a	Show file sizes too
	-L	Follow all symlinks
	-H	Follow symlinks on command line
	-d N	Limit output to directories (and files with -a) of depth < N
	-c	Show grand total
	-l	Count sizes many times if hard linked
	-s	Display only a total for each argument
	-x	Skip directories on different filesystems
	-h	Sizes in human readable format (e.g., 1K 243M 2G)
	-m	Sizes in megabytes
	-k	Sizes in kilobytes (default)
status 1
```

### du -d

```cu
(run (list "du" "-d") "")
```
---
```output
stderr:
du: option requires an argument: d
Usage: du [-aHLdclsxhmk] [FILE]...

Summarize disk space used for FILEs (or directories)

	-a	Show file sizes too
	-L	Follow all symlinks
	-H	Follow symlinks on command line
	-d N	Limit output to directories (and files with -a) of depth < N
	-c	Show grand total
	-l	Count sizes many times if hard linked
	-s	Display only a total for each argument
	-x	Skip directories on different filesystems
	-h	Sizes in human readable format (e.g., 1K 243M 2G)
	-m	Sizes in megabytes
	-k	Sizes in kilobytes (default)
status 1
```

### dd -~

```cu
(run (list "dd" "-~") "")
```
---
```output
stderr:
Usage: dd [if=FILE] [of=FILE] [ibs=N obs=N/bs=N] [count=N] [skip=N] [seek=N]
	[conv=notrunc|noerror|sync|fsync]
	[iflag=skip_bytes|count_bytes|fullblock|direct] [oflag=seek_bytes|append|direct]

Copy a file with converting and formatting

	if=FILE		Read from FILE instead of stdin
	of=FILE		Write to FILE instead of stdout
	bs=N		Read and write N bytes at a time
	ibs=N		Read N bytes at a time
	obs=N		Write N bytes at a time
	count=N		Copy only N input blocks
	skip=N		Skip N input blocks
	seek=N		Skip N output blocks
	conv=notrunc	Don't truncate output file
	conv=noerror	Continue after read errors
	conv=sync	Pad blocks with zeros
	conv=fsync	Physically write data out before finishing
	conv=swab	Swap every pair of bytes
	iflag=skip_bytes	skip=N is in bytes
	iflag=count_bytes	count=N is in bytes
	oflag=seek_bytes	seek=N is in bytes
	iflag=direct	O_DIRECT input
	oflag=direct	O_DIRECT output
	iflag=fullblock	Read full blocks
	oflag=append	Open output in append mode
	status=noxfer	Suppress rate output
	status=none	Suppress all output

N may be suffixed by c (1), w (2), b (512), kB (1000), k (1024), MB, M, GB, G
status 1
```

### dd --nope

```cu
(run (list "dd" "--nope") "")
```
---
```output
stderr:
Usage: dd [if=FILE] [of=FILE] [ibs=N obs=N/bs=N] [count=N] [skip=N] [seek=N]
	[conv=notrunc|noerror|sync|fsync]
	[iflag=skip_bytes|count_bytes|fullblock|direct] [oflag=seek_bytes|append|direct]

Copy a file with converting and formatting

	if=FILE		Read from FILE instead of stdin
	of=FILE		Write to FILE instead of stdout
	bs=N		Read and write N bytes at a time
	ibs=N		Read N bytes at a time
	obs=N		Write N bytes at a time
	count=N		Copy only N input blocks
	skip=N		Skip N input blocks
	seek=N		Skip N output blocks
	conv=notrunc	Don't truncate output file
	conv=noerror	Continue after read errors
	conv=sync	Pad blocks with zeros
	conv=fsync	Physically write data out before finishing
	conv=swab	Swap every pair of bytes
	iflag=skip_bytes	skip=N is in bytes
	iflag=count_bytes	count=N is in bytes
	oflag=seek_bytes	seek=N is in bytes
	iflag=direct	O_DIRECT input
	oflag=direct	O_DIRECT output
	iflag=fullblock	Read full blocks
	oflag=append	Open output in append mode
	status=noxfer	Suppress rate output
	status=none	Suppress all output

N may be suffixed by c (1), w (2), b (512), kB (1000), k (1024), MB, M, GB, G
status 1
```

### truncate -~

```cu
(run (list "truncate" "-~") "")
```
---
```output
stderr:
truncate: unrecognized option: ~
Usage: truncate [-c] -s SIZE FILE...

Truncate FILEs to SIZE

	-c	Do not create files
	-s SIZE
status 1
```

### truncate --nope

```cu
(run (list "truncate" "--nope") "")
```
---
```output
stderr:
truncate: unrecognized option: nope
Usage: truncate [-c] -s SIZE FILE...

Truncate FILEs to SIZE

	-c	Do not create files
	-s SIZE
status 1
```

### truncate -s

```cu
(run (list "truncate" "-s") "")
```
---
```output
stderr:
truncate: option requires an argument: s
Usage: truncate [-c] -s SIZE FILE...

Truncate FILEs to SIZE

	-c	Do not create files
	-s SIZE
status 1
```

### unlink -~

```cu
(run (list "unlink" "-~") "")
```
---
```output
stderr:
unlink: unrecognized option: ~
Usage: unlink FILE

Delete FILE by calling unlink()
status 1
```

### unlink --nope

```cu
(run (list "unlink" "--nope") "")
```
---
```output
stderr:
unlink: unrecognized option: nope
Usage: unlink FILE

Delete FILE by calling unlink()
status 1
```

### shred -~

```cu
(run (list "shred" "-~") "")
```
---
```output
stderr:
shred: unrecognized option: ~
Usage: shred [-fuz] [-n N] [-s SIZE] FILE...

Overwrite/delete FILEs

	-f	Chmod to ensure writability
	-n N	Overwrite N times (default 3)
	-z	Final overwrite with zeros
	-u	Remove file
status 1
```

### shred --nope

```cu
(run (list "shred" "--nope") "")
```
---
```output
stderr:
shred: unrecognized option: nope
Usage: shred [-fuz] [-n N] [-s SIZE] FILE...

Overwrite/delete FILEs

	-f	Chmod to ensure writability
	-n N	Overwrite N times (default 3)
	-z	Final overwrite with zeros
	-u	Remove file
status 1
```

### shred -n

```cu
(run (list "shred" "-n") "")
```
---
```output
stderr:
shred: option requires an argument: n
Usage: shred [-fuz] [-n N] [-s SIZE] FILE...

Overwrite/delete FILEs

	-f	Chmod to ensure writability
	-n N	Overwrite N times (default 3)
	-z	Final overwrite with zeros
	-u	Remove file
status 1
```

### timeout -~

```cu
(run (list "timeout" "-~") "")
```
---
```output
stderr:
timeout: unrecognized option: ~
Usage: timeout [-s SIG] [-k KILL_SECS] SECS PROG ARGS

Run PROG. Send SIG to it if it is not gone in SECS seconds.
Default SIG: TERM.If it still exists in KILL_SECS seconds, send KILL.

status 1
```

### timeout --nope

```cu
(run (list "timeout" "--nope") "")
```
---
```output
stderr:
timeout: unrecognized option: nope
Usage: timeout [-s SIG] [-k KILL_SECS] SECS PROG ARGS

Run PROG. Send SIG to it if it is not gone in SECS seconds.
Default SIG: TERM.If it still exists in KILL_SECS seconds, send KILL.

status 1
```

### timeout -s

```cu
(run (list "timeout" "-s") "")
```
---
```output
stderr:
timeout: option requires an argument: s
Usage: timeout [-s SIG] [-k KILL_SECS] SECS PROG ARGS

Run PROG. Send SIG to it if it is not gone in SECS seconds.
Default SIG: TERM.If it still exists in KILL_SECS seconds, send KILL.

status 1
```

### usleep -~

```cu
(run (list "usleep" "-~") "")
```
---
```output
stderr:
usleep: invalid number '-~'
status 1
```

### usleep --nope

```cu
(run (list "usleep" "--nope") "")
```
---
```output
stderr:
usleep: invalid number '--nope'
status 1
```

### tty -~

```cu
(run (list "tty" "-~") "")
```
---
```output
stderr:
tty: unrecognized option: ~
Usage: tty [-s]

Print file name of stdin's terminal

	-s	Print nothing, only return exit status
status 2
```

### tty --nope

```cu
(run (list "tty" "--nope") "")
```
---
```output
stderr:
tty: unrecognized option: nope
Usage: tty [-s]

Print file name of stdin's terminal

	-s	Print nothing, only return exit status
status 2
```

### [[ -~

```cu
(run (list "[[" "-~") "")
```
---
```output
stderr:
[[: missing ]]
status 2
```

### [[ --nope

```cu
(run (list "[[" "--nope") "")
```
---
```output
stderr:
[[: missing ]]
status 2
```

### od -~

```cu
(run (list "od" "-~") "")
```
---
```output
stderr:
od: unrecognized option: ~
Usage: od [-abcdfhilovxs] [-t TYPE] [-A RADIX] [-N SIZE] [-j SKIP] [-S MINSTR] [-w WIDTH] [FILE]...

Print FILEs (or stdin) unambiguously, as octal bytes by default
status 1
```

### od --nope

```cu
(run (list "od" "--nope") "")
```
---
```output
stderr:
od: unrecognized option: nope
Usage: od [-abcdfhilovxs] [-t TYPE] [-A RADIX] [-N SIZE] [-j SKIP] [-S MINSTR] [-w WIDTH] [FILE]...

Print FILEs (or stdin) unambiguously, as octal bytes by default
status 1
```

### od -A

```cu
(run (list "od" "-A") "")
```
---
```output
stderr:
od: option requires an argument: A
Usage: od [-abcdfhilovxs] [-t TYPE] [-A RADIX] [-N SIZE] [-j SKIP] [-S MINSTR] [-w WIDTH] [FILE]...

Print FILEs (or stdin) unambiguously, as octal bytes by default
status 1
```

### uuencode -~

```cu
(run (list "uuencode" "-~") "")
```
---
```output
stderr:
uuencode: unrecognized option: ~
Usage: uuencode [-m] [FILE] STORED_FILENAME

Uuencode FILE (or stdin) to stdout

	-m	Use base64 encoding per RFC1521
status 1
```

### uuencode --nope

```cu
(run (list "uuencode" "--nope") "")
```
---
```output
stderr:
uuencode: unrecognized option: nope
Usage: uuencode [-m] [FILE] STORED_FILENAME

Uuencode FILE (or stdin) to stdout

	-m	Use base64 encoding per RFC1521
status 1
```

### uudecode -~

```cu
(run (list "uudecode" "-~") "")
```
---
```output
stderr:
uudecode: unrecognized option: ~
Usage: uudecode [-o OUTFILE] [INFILE]

Uudecode a file
Finds OUTFILE in uuencoded source unless -o is given
status 1
```

### uudecode --nope

```cu
(run (list "uudecode" "--nope") "")
```
---
```output
stderr:
uudecode: unrecognized option: nope
Usage: uudecode [-o OUTFILE] [INFILE]

Uudecode a file
Finds OUTFILE in uuencoded source unless -o is given
status 1
```

### uudecode -o

```cu
(run (list "uudecode" "-o") "")
```
---
```output
stderr:
uudecode: option requires an argument: o
Usage: uudecode [-o OUTFILE] [INFILE]

Uudecode a file
Finds OUTFILE in uuencoded source unless -o is given
status 1
```

### expr -~

```cu
(run (list "expr" "-~") "")
```
---
```output
-~|
stderr:
status 0
```

### expr --nope

```cu
(run (list "expr" "--nope") "")
```
---
```output
--nope|
stderr:
status 0
```

### chmod -~

```cu
(run (list "chmod" "-~") "")
```
---
```output
stderr:
Usage: chmod [-Rcvf] MODE[,MODE]... FILE...

MODE is octal number (bit pattern sstrwxrwxrwx) or [ugoa]{+|-|=}[rwxXst]

	-R	Recurse
	-c	List changed files
	-v	Verbose
	-f	Hide errors
status 1
```

### chmod --nope

```cu
(run (list "chmod" "--nope") "")
```
---
```output
stderr:
chmod: unrecognized option: nope
Usage: chmod [-Rcvf] MODE[,MODE]... FILE...

MODE is octal number (bit pattern sstrwxrwxrwx) or [ugoa]{+|-|=}[rwxXst]

	-R	Recurse
	-c	List changed files
	-v	Verbose
	-f	Hide errors
status 1
```

### chown -~

```cu
(run (list "chown" "-~") "")
```
---
```output
stderr:
chown: unrecognized option: ~
Usage: chown [-RhLHPcvf]... USER[:[GRP]] FILE...

Change the owner and/or group of FILEs to USER and/or GRP

	-h	Affect symlinks instead of symlink targets
	-L	Traverse all symlinks to directories
	-H	Traverse symlinks on command line only
	-P	Don't traverse symlinks (default)
	-R	Recurse
	-c	List changed files
	-v	Verbose
	-f	Hide errors
status 1
```

### chown --nope

```cu
(run (list "chown" "--nope") "")
```
---
```output
stderr:
chown: unrecognized option: nope
Usage: chown [-RhLHPcvf]... USER[:[GRP]] FILE...

Change the owner and/or group of FILEs to USER and/or GRP

	-h	Affect symlinks instead of symlink targets
	-L	Traverse all symlinks to directories
	-H	Traverse symlinks on command line only
	-P	Don't traverse symlinks (default)
	-R	Recurse
	-c	List changed files
	-v	Verbose
	-f	Hide errors
status 1
```

### chgrp -~

```cu
(run (list "chgrp" "-~") "")
```
---
```output
stderr:
chgrp: unrecognized option: ~
Usage: chgrp [-RhLHPcvf]... GROUP FILE...

Change the group membership of FILEs to GROUP

	-h	Affect symlinks instead of symlink targets
	-L	Traverse all symlinks to directories
	-H	Traverse symlinks on command line only
	-P	Don't traverse symlinks (default)
	-R	Recurse
	-c	List changed files
	-v	Verbose
	-f	Hide errors
status 1
```

### chgrp --nope

```cu
(run (list "chgrp" "--nope") "")
```
---
```output
stderr:
chgrp: unrecognized option: nope
Usage: chgrp [-RhLHPcvf]... GROUP FILE...

Change the group membership of FILEs to GROUP

	-h	Affect symlinks instead of symlink targets
	-L	Traverse all symlinks to directories
	-H	Traverse symlinks on command line only
	-P	Don't traverse symlinks (default)
	-R	Recurse
	-c	List changed files
	-v	Verbose
	-f	Hide errors
status 1
```

### ln -~

```cu
(run (list "ln" "-~") "")
```
---
```output
stderr:
ln: unrecognized option: ~
Usage: ln [-sfnbtv] [-S SUF] TARGET... LINK|DIR

Create a link LINK or DIR/TARGET to the specified TARGET(s)

	-s	Make symlinks instead of hardlinks
	-f	Remove existing destinations
	-n	Don't dereference symlinks - treat like normal file
	-b	Make a backup of the target (if exists) before link operation
	-v	Verbose
status 1
```

### ln --nope

```cu
(run (list "ln" "--nope") "")
```
---
```output
stderr:
ln: unrecognized option: nope
Usage: ln [-sfnbtv] [-S SUF] TARGET... LINK|DIR

Create a link LINK or DIR/TARGET to the specified TARGET(s)

	-s	Make symlinks instead of hardlinks
	-f	Remove existing destinations
	-n	Don't dereference symlinks - treat like normal file
	-b	Make a backup of the target (if exists) before link operation
	-v	Verbose
status 1
```

### link -~

```cu
(run (list "link" "-~") "")
```
---
```output
stderr:
link: unrecognized option: ~
Usage: link FILE LINK

Create hard LINK to FILE
status 1
```

### link --nope

```cu
(run (list "link" "--nope") "")
```
---
```output
stderr:
link: unrecognized option: nope
Usage: link FILE LINK

Create hard LINK to FILE
status 1
```

### readlink -~

```cu
(run (list "readlink" "-~") "")
```
---
```output
stderr:
readlink: unrecognized option: ~
Usage: readlink [-fnv] FILE

Display the value of a symlink

	-n	Don't add newline
	-f	Canonicalize by following all symlinks
	-v	Verbose
status 1
```

### readlink --nope

```cu
(run (list "readlink" "--nope") "")
```
---
```output
stderr:
readlink: unrecognized option: nope
Usage: readlink [-fnv] FILE

Display the value of a symlink

	-n	Don't add newline
	-f	Canonicalize by following all symlinks
	-v	Verbose
status 1
```

### realpath -~

```cu
(run (list "realpath" "-~") "")
```
---
```output
stderr:
realpath: -~: No such file or directory
status 1
```

### realpath --nope

```cu
(run (list "realpath" "--nope") "")
```
---
```output
stderr:
realpath: --nope: No such file or directory
status 1
```

### mkfifo -~

```cu
(run (list "mkfifo" "-~") "")
```
---
```output
stderr:
mkfifo: unrecognized option: ~
Usage: mkfifo [-m MODE] NAME

Create named pipe

	-m MODE	Mode (default a=rw)
status 1
```

### mkfifo --nope

```cu
(run (list "mkfifo" "--nope") "")
```
---
```output
stderr:
mkfifo: unrecognized option: nope
Usage: mkfifo [-m MODE] NAME

Create named pipe

	-m MODE	Mode (default a=rw)
status 1
```

### mkfifo -m

```cu
(run (list "mkfifo" "-m") "")
```
---
```output
stderr:
mkfifo: option requires an argument: m
Usage: mkfifo [-m MODE] NAME

Create named pipe

	-m MODE	Mode (default a=rw)
status 1
```

### df -~

```cu
(run (list "df" "-~") "")
```
---
```output
stderr:
df: unrecognized option: ~
Usage: df [-PkmhTai] [-B SIZE] [-t TYPE] [FILESYSTEM]...

Print filesystem usage statistics

	-P	POSIX output format
	-k	1024-byte blocks (default)
	-m	1M-byte blocks
	-h	Human readable (e.g. 1K 243M 2G)
	-T	Print filesystem type
	-a	Show all filesystems
	-i	Inodes
	-B SIZE	Blocksize
status 1
```

### df --nope

```cu
(run (list "df" "--nope") "")
```
---
```output
stderr:
df: unrecognized option: nope
Usage: df [-PkmhTai] [-B SIZE] [-t TYPE] [FILESYSTEM]...

Print filesystem usage statistics

	-P	POSIX output format
	-k	1024-byte blocks (default)
	-m	1M-byte blocks
	-h	Human readable (e.g. 1K 243M 2G)
	-T	Print filesystem type
	-a	Show all filesystems
	-i	Inodes
	-B SIZE	Blocksize
status 1
```

### df -B

```cu
(run (list "df" "-B") "")
```
---
```output
stderr:
df: option requires an argument: B
Usage: df [-PkmhTai] [-B SIZE] [-t TYPE] [FILESYSTEM]...

Print filesystem usage statistics

	-P	POSIX output format
	-k	1024-byte blocks (default)
	-m	1M-byte blocks
	-h	Human readable (e.g. 1K 243M 2G)
	-T	Print filesystem type
	-a	Show all filesystems
	-i	Inodes
	-B SIZE	Blocksize
status 1
```

### sync -~

```cu
(run (list "sync" "-~") "")
```
---
```output
stderr:
sync: unrecognized option: ~
Usage: sync [-df] [FILE]...

Write all buffered blocks (in FILEs) to disk
	-d	Avoid syncing metadata
	-f	Sync filesystems underlying FILEs
status 1
```

### sync --nope

```cu
(run (list "sync" "--nope") "")
```
---
```output
stderr:
sync: unrecognized option: nope
Usage: sync [-df] [FILE]...

Write all buffered blocks (in FILEs) to disk
	-d	Avoid syncing metadata
	-f	Sync filesystems underlying FILEs
status 1
```

### id -~

```cu
(run (list "id" "-~") "")
```
---
```output
stderr:
id: unrecognized option: ~
Usage: id [-ugGnr] [USER]

Print information about USER or the current user

	-u	User ID
	-g	Group ID
	-G	Supplementary group IDs
	-n	Print names instead of numbers
	-r	Print real ID instead of effective ID
status 1
```

### id --nope

```cu
(run (list "id" "--nope") "")
```
---
```output
stderr:
id: unrecognized option: nope
Usage: id [-ugGnr] [USER]

Print information about USER or the current user

	-u	User ID
	-g	Group ID
	-G	Supplementary group IDs
	-n	Print names instead of numbers
	-r	Print real ID instead of effective ID
status 1
```

### whoami -~

```cu
(run (list "whoami" "-~") "")
```
---
```output
stderr:
Usage: whoami

Print the user name associated with the current effective user id
status 1
```

### whoami --nope

```cu
(run (list "whoami" "--nope") "")
```
---
```output
stderr:
Usage: whoami

Print the user name associated with the current effective user id
status 1
```

### logname -~

```cu
(run (list "logname" "-~") "")
```
---
```output
stderr:
Usage: logname

Print the name of the current user
status 1
```

### logname --nope

```cu
(run (list "logname" "--nope") "")
```
---
```output
stderr:
Usage: logname

Print the name of the current user
status 1
```

### groups -~

```cu
(run (list "groups" "-~") "")
```
---
```output
stderr:
groups: unrecognized option: ~
Usage: groups [USER]

Print the groups USER is in
status 1
```

### groups --nope

```cu
(run (list "groups" "--nope") "")
```
---
```output
stderr:
groups: unrecognized option: nope
Usage: groups [USER]

Print the groups USER is in
status 1
```

### who -~

```cu
(run (list "who" "-~") "")
```
---
```output
stderr:
who: unrecognized option: ~
Usage: who [-aH]

Show who is logged on

	-a	Show all
	-H	Print column headers
status 1
```

### who --nope

```cu
(run (list "who" "--nope") "")
```
---
```output
stderr:
who: unrecognized option: nope
Usage: who [-aH]

Show who is logged on

	-a	Show all
	-H	Print column headers
status 1
```

### w -~

```cu
(run (list "w" "-~") "")
```
---
```output
stderr:
w: unrecognized option: ~
Usage: w

Show who is logged on
status 1
```

### w --nope

```cu
(run (list "w" "--nope") "")
```
---
```output
stderr:
w: unrecognized option: nope
Usage: w

Show who is logged on
status 1
```

### users -~

```cu
(run (list "users" "-~") "")
```
---
```output
stderr:
users: unrecognized option: ~
Usage: users

Print the users currently logged on
status 1
```

### users --nope

```cu
(run (list "users" "--nope") "")
```
---
```output
stderr:
users: unrecognized option: nope
Usage: users

Print the users currently logged on
status 1
```

### uname -~

```cu
(run (list "uname" "-~") "")
```
---
```output
stderr:
uname: unrecognized option: ~
Usage: uname [-amnrspvio]

Print system information

	-a	Print all
	-m	Machine (hardware) type
	-n	Hostname
	-r	Kernel release
	-s	Kernel name (default)
	-p	Processor type
	-v	Kernel version
	-i	Hardware platform
	-o	OS name
status 1
```

### uname --nope

```cu
(run (list "uname" "--nope") "")
```
---
```output
stderr:
uname: unrecognized option: nope
Usage: uname [-amnrspvio]

Print system information

	-a	Print all
	-m	Machine (hardware) type
	-n	Hostname
	-r	Kernel release
	-s	Kernel name (default)
	-p	Processor type
	-v	Kernel version
	-i	Hardware platform
	-o	OS name
status 1
```

### nproc -~

```cu
(run (list "nproc" "-~") "")
```
---
```output
stderr:
nproc: unrecognized option: ~
Usage: nproc [--all] [--ignore=N]

Print number of available CPUs

	--all		Number of installed CPUs
	--ignore=N	Exclude N CPUs
status 1
```

### nproc --nope

```cu
(run (list "nproc" "--nope") "")
```
---
```output
stderr:
nproc: unrecognized option: nope
Usage: nproc [--all] [--ignore=N]

Print number of available CPUs

	--all		Number of installed CPUs
	--ignore=N	Exclude N CPUs
status 1
```

### nproc --ignore

```cu
(run (list "nproc" "--ignore") "")
```
---
```output
stderr:
nproc: option requires an argument: ignore
Usage: nproc [--all] [--ignore=N]

Print number of available CPUs

	--all		Number of installed CPUs
	--ignore=N	Exclude N CPUs
status 1
```

### nice -~

```cu
(run (list "nice" "-~") "")
```
---
```output
stderr:
Usage: nice [-n ADJUST] [PROG ARGS]

Change scheduling priority, run PROG

	-n ADJUST	Adjust priority by ADJUST
status 1
```

### nice --nope

```cu
(run (list "nice" "--nope") "")
```
---
```output
stderr:
Usage: nice [-n ADJUST] [PROG ARGS]

Change scheduling priority, run PROG

	-n ADJUST	Adjust priority by ADJUST
status 1
```

### nice -n

```cu
(run (list "nice" "-n") "")
```
---
```output
stderr:
Usage: nice [-n ADJUST] [PROG ARGS]

Change scheduling priority, run PROG

	-n ADJUST	Adjust priority by ADJUST
status 1
```

### echo -~

```cu
(run (list "echo" "-~") "")
```
---
```output
-~|
stderr:
status 0
```

### echo --nope

```cu
(run (list "echo" "--nope") "")
```
---
```output
--nope|
stderr:
status 0
```

### printf -~

```cu
(run (list "printf" "-~") "")
```
---
```output
-~stderr:
status 0
```

### printf --nope

```cu
(run (list "printf" "--nope") "")
```
---
```output
--nopestderr:
status 0
```

### true -~

```cu
(run (list "true" "-~") "")
```
---
```output
stderr:
status 0
```

### true --nope

```cu
(run (list "true" "--nope") "")
```
---
```output
stderr:
status 0
```

### false -~

```cu
(run (list "false" "-~") "")
```
---
```output
stderr:
status 1
```

### false --nope

```cu
(run (list "false" "--nope") "")
```
---
```output
stderr:
status 1
```

### seq -~

```cu
(run (list "seq" "-~") "")
```
---
```output
stderr:
seq: unrecognized option: ~
Usage: seq [-w] [-s SEP] [FIRST [INC]] LAST

Print numbers from FIRST to LAST, in steps of INC.
FIRST, INC default to 1.

	-w	Pad with leading zeros
	-s SEP	String separator
status 1
```

### seq --nope

```cu
(run (list "seq" "--nope") "")
```
---
```output
stderr:
seq: unrecognized option: nope
Usage: seq [-w] [-s SEP] [FIRST [INC]] LAST

Print numbers from FIRST to LAST, in steps of INC.
FIRST, INC default to 1.

	-w	Pad with leading zeros
	-s SEP	String separator
status 1
```

### seq -s

```cu
(run (list "seq" "-s") "")
```
---
```output
stderr:
seq: option requires an argument: s
Usage: seq [-w] [-s SEP] [FIRST [INC]] LAST

Print numbers from FIRST to LAST, in steps of INC.
FIRST, INC default to 1.

	-w	Pad with leading zeros
	-s SEP	String separator
status 1
```

### rev -~

```cu
(run (list "rev" "-~") "")
```
---
```output
stderr:
rev: unrecognized option: ~
Usage: rev [FILE]...

Reverse lines of FILE
status 1
```

### rev --nope

```cu
(run (list "rev" "--nope") "")
```
---
```output
stderr:
rev: unrecognized option: nope
Usage: rev [FILE]...

Reverse lines of FILE
status 1
```

### tac -~

```cu
(run (list "tac" "-~") "")
```
---
```output
stderr:
tac: unrecognized option: ~
Usage: tac [FILE]...

Concatenate FILEs and print them in reverse
status 1
```

### tac --nope

```cu
(run (list "tac" "--nope") "")
```
---
```output
stderr:
tac: unrecognized option: nope
Usage: tac [FILE]...

Concatenate FILEs and print them in reverse
status 1
```

### nl -~

```cu
(run (list "nl" "-~") "")
```
---
```output
stderr:
nl: unrecognized option: ~
Usage: nl [OPTIONS] [FILE]...

Write FILEs to standard output with line numbers added

	-b STYLE	Which lines to number - a: all, t: nonempty, n: none
	-i N		Line number increment
	-s STRING	Use STRING as line number separator
	-v N		Start from N
	-w N		Width of line numbers
status 1
```

### nl --nope

```cu
(run (list "nl" "--nope") "")
```
---
```output
stderr:
nl: unrecognized option: nope
Usage: nl [OPTIONS] [FILE]...

Write FILEs to standard output with line numbers added

	-b STYLE	Which lines to number - a: all, t: nonempty, n: none
	-i N		Line number increment
	-s STRING	Use STRING as line number separator
	-v N		Start from N
	-w N		Width of line numbers
status 1
```

### nl -b

```cu
(run (list "nl" "-b") "")
```
---
```output
stderr:
nl: option requires an argument: b
Usage: nl [OPTIONS] [FILE]...

Write FILEs to standard output with line numbers added

	-b STYLE	Which lines to number - a: all, t: nonempty, n: none
	-i N		Line number increment
	-s STRING	Use STRING as line number separator
	-v N		Start from N
	-w N		Width of line numbers
status 1
```

### fold -~

```cu
(run (list "fold" "-~") "")
```
---
```output
stderr:
fold: unrecognized option: ~
Usage: fold [-bs] [-w WIDTH] [FILE]...

Wrap input lines in FILEs (or stdin), writing to stdout

	-b	Count bytes rather than columns
	-s	Break at spaces
	-w	Use WIDTH columns instead of 80
status 1
```

### fold --nope

```cu
(run (list "fold" "--nope") "")
```
---
```output
stderr:
fold: unrecognized option: nope
Usage: fold [-bs] [-w WIDTH] [FILE]...

Wrap input lines in FILEs (or stdin), writing to stdout

	-b	Count bytes rather than columns
	-s	Break at spaces
	-w	Use WIDTH columns instead of 80
status 1
```

### fold -w

```cu
(run (list "fold" "-w") "")
```
---
```output
stderr:
fold: option requires an argument: w
Usage: fold [-bs] [-w WIDTH] [FILE]...

Wrap input lines in FILEs (or stdin), writing to stdout

	-b	Count bytes rather than columns
	-s	Break at spaces
	-w	Use WIDTH columns instead of 80
status 1
```

### paste -~

```cu
(run (list "paste" "-~") "")
```
---
```output
stderr:
paste: unrecognized option: ~
Usage: paste [-d LIST] [-s] [FILE]...

Paste lines from each input file, separated with tab

	-d LIST	Use delimiters from LIST, not tab
	-s      Serial: one file at a time
status 1
```

### paste --nope

```cu
(run (list "paste" "--nope") "")
```
---
```output
stderr:
paste: unrecognized option: nope
Usage: paste [-d LIST] [-s] [FILE]...

Paste lines from each input file, separated with tab

	-d LIST	Use delimiters from LIST, not tab
	-s      Serial: one file at a time
status 1
```

### paste -d

```cu
(run (list "paste" "-d") "")
```
---
```output
stderr:
paste: option requires an argument: d
Usage: paste [-d LIST] [-s] [FILE]...

Paste lines from each input file, separated with tab

	-d LIST	Use delimiters from LIST, not tab
	-s      Serial: one file at a time
status 1
```

### tee -~

```cu
(run (list "tee" "-~") "")
```
---
```output
stderr:
tee: unrecognized option: ~
Usage: tee [-ai] [FILE]...

Copy stdin to each FILE, and also to stdout

	-a	Append to the given FILEs, don't overwrite
	-i	Ignore interrupt signals (SIGINT)
status 1
```

### tee --nope

```cu
(run (list "tee" "--nope") "")
```
---
```output
stderr:
tee: unrecognized option: nope
Usage: tee [-ai] [FILE]...

Copy stdin to each FILE, and also to stdout

	-a	Append to the given FILEs, don't overwrite
	-i	Ignore interrupt signals (SIGINT)
status 1
```

### tar -~

```cu
(run (list "tar" "-~") "")
```
---
```output
stderr:
tar: unrecognized option: ~
Usage: tar c|x|t [-zahmvokO] [-f TARFILE] [-C DIR] [-T FILE] [-X FILE] [LONGOPT]... [FILE]...

Create, extract, or list files from a tar file

	c	Create
	x	Extract
	t	List
	-f FILE	Name of TARFILE ('-' for stdin/out)
	-C DIR	Change to DIR before operation
	-v	Verbose
	-O	Extract to stdout
	-m	Don't restore mtime
	-o	Don't restore user:group
	-k	Don't replace existing files
	-z	(De)compress using gzip
	-a	(De)compress based on extension
	-h	Follow symlinks
	-T FILE	File with names to include
	-X FILE	File with glob patterns to exclude
	--exclude PATTERN	Glob pattern to exclude
	--overwrite		Replace existing files
	--strip-components NUM	NUM of leading components to strip
	--no-recursion		Don't descend in directories
	--numeric-owner		Use numeric user:group
	--no-same-permissions	Don't restore access permissions
status 1
```

### tar --nope

```cu
(run (list "tar" "--nope") "")
```
---
```output
stderr:
tar: unrecognized option: nope
Usage: tar c|x|t [-zahmvokO] [-f TARFILE] [-C DIR] [-T FILE] [-X FILE] [LONGOPT]... [FILE]...

Create, extract, or list files from a tar file

	c	Create
	x	Extract
	t	List
	-f FILE	Name of TARFILE ('-' for stdin/out)
	-C DIR	Change to DIR before operation
	-v	Verbose
	-O	Extract to stdout
	-m	Don't restore mtime
	-o	Don't restore user:group
	-k	Don't replace existing files
	-z	(De)compress using gzip
	-a	(De)compress based on extension
	-h	Follow symlinks
	-T FILE	File with names to include
	-X FILE	File with glob patterns to exclude
	--exclude PATTERN	Glob pattern to exclude
	--overwrite		Replace existing files
	--strip-components NUM	NUM of leading components to strip
	--no-recursion		Don't descend in directories
	--numeric-owner		Use numeric user:group
	--no-same-permissions	Don't restore access permissions
status 1
```

### tar -f

```cu
(run (list "tar" "-f") "")
```
---
```output
stderr:
tar: option requires an argument: f
Usage: tar c|x|t [-zahmvokO] [-f TARFILE] [-C DIR] [-T FILE] [-X FILE] [LONGOPT]... [FILE]...

Create, extract, or list files from a tar file

	c	Create
	x	Extract
	t	List
	-f FILE	Name of TARFILE ('-' for stdin/out)
	-C DIR	Change to DIR before operation
	-v	Verbose
	-O	Extract to stdout
	-m	Don't restore mtime
	-o	Don't restore user:group
	-k	Don't replace existing files
	-z	(De)compress using gzip
	-a	(De)compress based on extension
	-h	Follow symlinks
	-T FILE	File with names to include
	-X FILE	File with glob patterns to exclude
	--exclude PATTERN	Glob pattern to exclude
	--overwrite		Replace existing files
	--strip-components NUM	NUM of leading components to strip
	--no-recursion		Don't descend in directories
	--numeric-owner		Use numeric user:group
	--no-same-permissions	Don't restore access permissions
status 1
```

### gzip -~

```cu
(run (list "gzip" "-~") "")
```
---
```output
stderr:
gzip: unrecognized option: ~
Usage: gzip [-cfkdt] [FILE]...

Compress FILEs (or stdin)

	-d	Decompress
	-c	Write to stdout
	-f	Force
	-k	Keep input files
	-t	Test integrity
status 1
```

### gzip --nope

```cu
(run (list "gzip" "--nope") "")
```
---
```output
stderr:
gzip: unrecognized option: nope
Usage: gzip [-cfkdt] [FILE]...

Compress FILEs (or stdin)

	-d	Decompress
	-c	Write to stdout
	-f	Force
	-k	Keep input files
	-t	Test integrity
status 1
```

### gunzip -~

```cu
(run (list "gunzip" "-~") "")
```
---
```output
stderr:
gunzip: unrecognized option: ~
Usage: gunzip [-cfkt] [FILE]...

Decompress FILEs (or stdin)

	-c	Write to stdout
	-f	Force
	-k	Keep input files
	-t	Test integrity
status 1
```

### gunzip --nope

```cu
(run (list "gunzip" "--nope") "")
```
---
```output
stderr:
gunzip: unrecognized option: nope
Usage: gunzip [-cfkt] [FILE]...

Decompress FILEs (or stdin)

	-c	Write to stdout
	-f	Force
	-k	Keep input files
	-t	Test integrity
status 1
```

### zcat -~

```cu
(run (list "zcat" "-~") "")
```
---
```output
stderr:
zcat: unrecognized option: ~
Usage: zcat [FILE]...

Decompress to stdout
status 1
```

### zcat --nope

```cu
(run (list "zcat" "--nope") "")
```
---
```output
stderr:
zcat: unrecognized option: nope
Usage: zcat [FILE]...

Decompress to stdout
status 1
```

### hostname -~

```cu
(run (list "hostname" "-~") "")
```
---
```output
stderr:
hostname: unrecognized option: ~
Usage: hostname [-sidf] [HOSTNAME | -F FILE]

Show or set hostname or DNS domain name

	-s	Short
	-i	Addresses for the hostname
	-d	DNS domain name
	-f	Fully qualified domain name
	-F FILE	Use FILE's content as hostname
status 1
```

### hostname --nope

```cu
(run (list "hostname" "--nope") "")
```
---
```output
stderr:
hostname: unrecognized option: nope
Usage: hostname [-sidf] [HOSTNAME | -F FILE]

Show or set hostname or DNS domain name

	-s	Short
	-i	Addresses for the hostname
	-d	DNS domain name
	-f	Fully qualified domain name
	-F FILE	Use FILE's content as hostname
status 1
```

### hostid -~

```cu
(run (list "hostid" "-~") "")
```
---
```output
stderr:
Usage: hostid

Print out a unique 32-bit identifier for the machine
status 1
```

### hostid --nope

```cu
(run (list "hostid" "--nope") "")
```
---
```output
stderr:
Usage: hostid

Print out a unique 32-bit identifier for the machine
status 1
```

### mountpoint -~

```cu
(run (list "mountpoint" "-~") "")
```
---
```output
stderr:
mountpoint: unrecognized option: ~
Usage: mountpoint [-q] { [-dn] DIR | -x DEVICE }

Check if DIR is a mountpoint

	-q	Quiet
	-d	Print major:minor of the filesystem
	-n	Print device name of the filesystem
	-x	Print major:minor of DEVICE
status 1
```

### mountpoint --nope

```cu
(run (list "mountpoint" "--nope") "")
```
---
```output
stderr:
mountpoint: unrecognized option: nope
Usage: mountpoint [-q] { [-dn] DIR | -x DEVICE }

Check if DIR is a mountpoint

	-q	Quiet
	-d	Print major:minor of the filesystem
	-n	Print device name of the filesystem
	-x	Print major:minor of DEVICE
status 1
```

### mknod -~

```cu
(run (list "mknod" "-~") "")
```
---
```output
stderr:
mknod: unrecognized option: ~
Usage: mknod [-m MODE] NAME TYPE [MAJOR MINOR]

Create a special file (block, character, or pipe)

	-m MODE	Creation mode (default a=rw)
TYPE:
	b	Block device
	c or u	Character device
	p	Named pipe (MAJOR MINOR must be omitted)
status 1
```

### mknod --nope

```cu
(run (list "mknod" "--nope") "")
```
---
```output
stderr:
mknod: unrecognized option: nope
Usage: mknod [-m MODE] NAME TYPE [MAJOR MINOR]

Create a special file (block, character, or pipe)

	-m MODE	Creation mode (default a=rw)
TYPE:
	b	Block device
	c or u	Character device
	p	Named pipe (MAJOR MINOR must be omitted)
status 1
```

### mesg -~

```cu
(run (list "mesg" "-~") "")
```
---
```output
stderr:
Usage: mesg [y|n]

Control write access to your terminal
	y	Allow write access to your terminal
	n	Disallow write access to your terminal
status 1
```

### mesg --nope

```cu
(run (list "mesg" "--nope") "")
```
---
```output
stderr:
Usage: mesg [y|n]

Control write access to your terminal
	y	Allow write access to your terminal
	n	Disallow write access to your terminal
status 1
```

### renice -~

```cu
(run (list "renice" "-~") "")
```
---
```output
stderr:
renice: invalid number '~'
status 1
```

### renice --nope

```cu
(run (list "renice" "--nope") "")
```
---
```output
stderr:
renice: invalid number '-nope'
status 1
```

### ts -~

```cu
(run (list "ts" "-~") "")
```
---
```output
stderr:
ts: unrecognized option: ~
Usage: ts [-is] [STRFTIME]

Pipe stdin to stdout, add timestamp to each line

	-s	Time since start
	-i	Time since previous line
status 1
```

### ts --nope

```cu
(run (list "ts" "--nope") "")
```
---
```output
stderr:
ts: unrecognized option: nope
Usage: ts [-is] [STRFTIME]

Pipe stdin to stdout, add timestamp to each line

	-s	Time since start
	-i	Time since previous line
status 1
```

### sha384sum -~

```cu
(run (list "sha384sum" "-~") "")
```
---
```output
stderr:
sha384sum: unrecognized option: ~
Usage: sha384sum [-c[sw]] [FILE]...

Print or check SHA384 checksums

	-c	Check sums against list in FILEs
	-s	Don't output anything, status code shows success
	-w	Warn about improperly formatted checksum lines
status 1
```

### sha384sum --nope

```cu
(run (list "sha384sum" "--nope") "")
```
---
```output
stderr:
sha384sum: unrecognized option: nope
Usage: sha384sum [-c[sw]] [FILE]...

Print or check SHA384 checksums

	-c	Check sums against list in FILEs
	-s	Don't output anything, status code shows success
	-w	Warn about improperly formatted checksum lines
status 1
```

### hostname -F

```cu
(run (list "hostname" "-F") "")
```
---
```output
stderr:
hostname: option requires an argument: F
Usage: hostname [-sidf] [HOSTNAME | -F FILE]

Show or set hostname or DNS domain name

	-s	Short
	-i	Addresses for the hostname
	-d	DNS domain name
	-f	Fully qualified domain name
	-F FILE	Use FILE's content as hostname
status 1
```

### mknod -m

```cu
(run (list "mknod" "-m") "")
```
---
```output
stderr:
mknod: option requires an argument: m
Usage: mknod [-m MODE] NAME TYPE [MAJOR MINOR]

Create a special file (block, character, or pipe)

	-m MODE	Creation mode (default a=rw)
TYPE:
	b	Block device
	c or u	Character device
	p	Named pipe (MAJOR MINOR must be omitted)
status 1
```

### touch -~

```cu
(run (list "touch" "-~") "")
```
---
```output
stderr:
touch: unrecognized option: ~
Usage: touch [-cham] [-d DATE] [-t DATE] [-r FILE] FILE...

Update mtime of FILEs

	-c	Don't create files
	-d DT	Date/time to use
	-t DT	Date/time to use
	-r FILE	Use FILE's date/time
status 1
```

### touch --nope

```cu
(run (list "touch" "--nope") "")
```
---
```output
stderr:
touch: unrecognized option: nope
Usage: touch [-cham] [-d DATE] [-t DATE] [-r FILE] FILE...

Update mtime of FILEs

	-c	Don't create files
	-d DT	Date/time to use
	-t DT	Date/time to use
	-r FILE	Use FILE's date/time
status 1
```

### touch -r

```cu
(run (list "touch" "-r") "")
```
---
```output
stderr:
touch: option requires an argument: r
Usage: touch [-cham] [-d DATE] [-t DATE] [-r FILE] FILE...

Update mtime of FILEs

	-c	Don't create files
	-d DT	Date/time to use
	-t DT	Date/time to use
	-r FILE	Use FILE's date/time
status 1
```

### ls -~

```cu
(run (list "ls" "-~") "")
```
---
```output
stderr:
ls: unrecognized option: ~
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

### ls --nope

```cu
(run (list "ls" "--nope") "")
```
---
```output
stderr:
ls: unrecognized option: nope
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

### ls -w

```cu
(run (list "ls" "-w") "")
```
---
```output
stderr:
ls: option requires an argument: w
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

### pwd -~

```cu
(run (list "pwd" "-~") "")
```
---
```output
stderr:
pwd: unrecognized option: ~
Usage: pwd

Print the full filename of the current working directory
status 1
```

### pwd --nope

```cu
(run (list "pwd" "--nope") "")
```
---
```output
stderr:
pwd: unrecognized option: nope
Usage: pwd

Print the full filename of the current working directory
status 1
```

### mv -~

```cu
(run (list "mv" "-~") "")
```
---
```output
stderr:
mv: unrecognized option: ~
Usage: mv [-finT] SOURCE DEST
or: mv [-fin] SOURCE... { -t DIRECTORY | DIRECTORY }

Rename SOURCE to DEST, or move SOURCEs to DIRECTORY

	-f	Don't prompt before overwriting
	-i	Interactive, prompt before overwrite
	-n	Don't overwrite an existing file
	-T	Refuse to move if DEST is a directory
status 1
```

### mv --nope

```cu
(run (list "mv" "--nope") "")
```
---
```output
stderr:
mv: unrecognized option: nope
Usage: mv [-finT] SOURCE DEST
or: mv [-fin] SOURCE... { -t DIRECTORY | DIRECTORY }

Rename SOURCE to DEST, or move SOURCEs to DIRECTORY

	-f	Don't prompt before overwriting
	-i	Interactive, prompt before overwrite
	-n	Don't overwrite an existing file
	-T	Refuse to move if DEST is a directory
status 1
```

### rmdir -~

```cu
(run (list "rmdir" "-~") "")
```
---
```output
stderr:
rmdir: unrecognized option: ~
Usage: rmdir [-p] DIRECTORY...

Remove DIRECTORY if it is empty

	-p	Include parents
status 1
```

### rmdir --nope

```cu
(run (list "rmdir" "--nope") "")
```
---
```output
stderr:
rmdir: unrecognized option: nope
Usage: rmdir [-p] DIRECTORY...

Remove DIRECTORY if it is empty

	-p	Include parents
status 1
```

### install -~

```cu
(run (list "install" "-~") "")
```
---
```output
stderr:
install: unrecognized option: ~
Usage: install [-cdDsp] [-o USER] [-g GRP] [-m MODE] [-t DIR] [SOURCE]... DEST

Copy files and set attributes

	-c	Just copy (default)
	-d	Create directories
	-D	Create leading target directories
	-p	Preserve date
	-o USER	Set ownership
	-g GRP	Set group ownership
	-m MODE	Set permissions
	-t DIR	Install to DIR
status 1
```

### install --nope

```cu
(run (list "install" "--nope") "")
```
---
```output
stderr:
install: unrecognized option: nope
Usage: install [-cdDsp] [-o USER] [-g GRP] [-m MODE] [-t DIR] [SOURCE]... DEST

Copy files and set attributes

	-c	Just copy (default)
	-d	Create directories
	-D	Create leading target directories
	-p	Preserve date
	-o USER	Set ownership
	-g GRP	Set group ownership
	-m MODE	Set permissions
	-t DIR	Install to DIR
status 1
```

### install -m

```cu
(run (list "install" "-m") "")
```
---
```output
stderr:
install: option requires an argument: m
Usage: install [-cdDsp] [-o USER] [-g GRP] [-m MODE] [-t DIR] [SOURCE]... DEST

Copy files and set attributes

	-c	Just copy (default)
	-d	Create directories
	-D	Create leading target directories
	-p	Preserve date
	-o USER	Set ownership
	-g GRP	Set group ownership
	-m MODE	Set permissions
	-t DIR	Install to DIR
status 1
```

### mktemp -~

```cu
(run (list "mktemp" "-~") "")
```
---
```output
stderr:
mktemp: unrecognized option: ~
Usage: mktemp [-dt] [-p DIR] [TEMPLATE]

Create a temporary file with name based on TEMPLATE and print its name.
TEMPLATE must end with XXXXXX (e.g. [/dir/]nameXXXXXX).
Without TEMPLATE, -t tmp.XXXXXX is assumed.

	-d	Make directory, not file
	-q	Fail silently on errors
	-t	Prepend base directory name to TEMPLATE
	-p DIR	Use DIR as a base directory (implies -t)
	-u	Do not create anything; print a name

Base directory is: -p DIR, else $TMPDIR, else /tmp
status 1
```

### mktemp --nope

```cu
(run (list "mktemp" "--nope") "")
```
---
```output
stderr:
mktemp: unrecognized option: nope
Usage: mktemp [-dt] [-p DIR] [TEMPLATE]

Create a temporary file with name based on TEMPLATE and print its name.
TEMPLATE must end with XXXXXX (e.g. [/dir/]nameXXXXXX).
Without TEMPLATE, -t tmp.XXXXXX is assumed.

	-d	Make directory, not file
	-q	Fail silently on errors
	-t	Prepend base directory name to TEMPLATE
	-p DIR	Use DIR as a base directory (implies -t)
	-u	Do not create anything; print a name

Base directory is: -p DIR, else $TMPDIR, else /tmp
status 1
```

### mktemp -p

```cu
(run (list "mktemp" "-p") "")
```
---
```output
stderr:
mktemp: option requires an argument: p
Usage: mktemp [-dt] [-p DIR] [TEMPLATE]

Create a temporary file with name based on TEMPLATE and print its name.
TEMPLATE must end with XXXXXX (e.g. [/dir/]nameXXXXXX).
Without TEMPLATE, -t tmp.XXXXXX is assumed.

	-d	Make directory, not file
	-q	Fail silently on errors
	-t	Prepend base directory name to TEMPLATE
	-p DIR	Use DIR as a base directory (implies -t)
	-u	Do not create anything; print a name

Base directory is: -p DIR, else $TMPDIR, else /tmp
status 1
```

### cmp -~

```cu
(run (list "cmp" "-~") "")
```
---
```output
stderr:
cmp: unrecognized option: ~
Usage: cmp [-l|s] [-n NUM] FILE1 [FILE2 [SKIP1 [SKIP2]]]

Compare FILE1 with FILE2 (or stdin)

	-l	Show decimal offset and octal byte value for differing bytes,
		don't stop on first mismatch
	-s	Quiet
	-n NUM	Compare at most NUM bytes
status 1
```

### cmp --nope

```cu
(run (list "cmp" "--nope") "")
```
---
```output
stderr:
cmp: unrecognized option: nope
Usage: cmp [-l|s] [-n NUM] FILE1 [FILE2 [SKIP1 [SKIP2]]]

Compare FILE1 with FILE2 (or stdin)

	-l	Show decimal offset and octal byte value for differing bytes,
		don't stop on first mismatch
	-s	Quiet
	-n NUM	Compare at most NUM bytes
status 1
```

### cmp -n

```cu
(run (list "cmp" "-n") "")
```
---
```output
stderr:
cmp: option requires an argument: n
Usage: cmp [-l|s] [-n NUM] FILE1 [FILE2 [SKIP1 [SKIP2]]]

Compare FILE1 with FILE2 (or stdin)

	-l	Show decimal offset and octal byte value for differing bytes,
		don't stop on first mismatch
	-s	Quiet
	-n NUM	Compare at most NUM bytes
status 1
```

### diff -~

```cu
(run (list "diff" "-~") "")
```
---
```output
stderr:
diff: unrecognized option: ~
Usage: diff [-abBdiNqrTstw] [-L LABEL] [-S FILE] [-U LINES] FILE1 FILE2

Compare files line by line and output the differences between them.
This implementation supports unified diffs only.

	-a	Treat all files as text
	-b	Ignore changes in the amount of whitespace
	-B	Ignore changes whose lines are all blank
	-d	Try hard to find a smaller set of changes
	-i	Ignore case differences
	-L	Use LABEL instead of the filename in the unified header
	-N	Treat absent files as empty
	-q	Output only whether files differ
	-r	Recurse
	-S	Start with FILE when comparing directories
	-T	Make tabs line up by prefixing a tab when necessary
	-s	Report when two files are the same
	-t	Expand tabs to spaces in output
	-U	Output LINES lines of context
	-w	Ignore all whitespace
status 1
```

### diff --nope

```cu
(run (list "diff" "--nope") "")
```
---
```output
stderr:
diff: unrecognized option: nope
Usage: diff [-abBdiNqrTstw] [-L LABEL] [-S FILE] [-U LINES] FILE1 FILE2

Compare files line by line and output the differences between them.
This implementation supports unified diffs only.

	-a	Treat all files as text
	-b	Ignore changes in the amount of whitespace
	-B	Ignore changes whose lines are all blank
	-d	Try hard to find a smaller set of changes
	-i	Ignore case differences
	-L	Use LABEL instead of the filename in the unified header
	-N	Treat absent files as empty
	-q	Output only whether files differ
	-r	Recurse
	-S	Start with FILE when comparing directories
	-T	Make tabs line up by prefixing a tab when necessary
	-s	Report when two files are the same
	-t	Expand tabs to spaces in output
	-U	Output LINES lines of context
	-w	Ignore all whitespace
status 1
```

### diff -U

```cu
(run (list "diff" "-U") "")
```
---
```output
stderr:
diff: option requires an argument: U
Usage: diff [-abBdiNqrTstw] [-L LABEL] [-S FILE] [-U LINES] FILE1 FILE2

Compare files line by line and output the differences between them.
This implementation supports unified diffs only.

	-a	Treat all files as text
	-b	Ignore changes in the amount of whitespace
	-B	Ignore changes whose lines are all blank
	-d	Try hard to find a smaller set of changes
	-i	Ignore case differences
	-L	Use LABEL instead of the filename in the unified header
	-N	Treat absent files as empty
	-q	Output only whether files differ
	-r	Recurse
	-S	Start with FILE when comparing directories
	-T	Make tabs line up by prefixing a tab when necessary
	-s	Report when two files are the same
	-t	Expand tabs to spaces in output
	-U	Output LINES lines of context
	-w	Ignore all whitespace
status 1
```

### find -~

```cu
(run (list "find" "-~") "")
```
---
```output
stderr:
find: unrecognized: -~
Usage: find [-HL] [PATH]... [OPTIONS] [ACTIONS]

Search for files and perform actions on them.
First failed action stops processing of current file.
Defaults: PATH is current directory, action is '-print'

	-maxdepth N	Descend at most N levels. -maxdepth 0 applies
			actions to command line arguments only
	-mindepth N	Don't act on first N levels

Actions:
	( ACTIONS )	Group actions for -o / -a
	! ACT		Invert ACT's success/failure
	ACT1 [-a] ACT2	If ACT1 fails, stop, else do ACT2
	ACT1 -o ACT2	If ACT1 succeeds, stop, else do ACT2
			Note: -a has higher priority than -o
	-name PATTERN	Match file name (w/o directory name) to PATTERN
	-iname PATTERN	Case insensitive -name
	-path PATTERN	Match path to PATTERN
	-type X		File type is X (one of: f,d,l,b,c,s,p)
	-newer FILE	mtime is more recent than FILE's
	-size N[bck]	File size is N (c:bytes,k:kbytes,b:512 bytes(def.))
			+/-N: file size is bigger/smaller than N
	-empty		Match empty file/directory
If none of the following actions is specified, -print is assumed
	-print		Print file name
	-print0		Print file name, NUL terminated
	-exec CMD ARG ;	Run CMD with all instances of {} replaced by
			file name. Fails if CMD exits with nonzero
	-exec CMD ARG + Run CMD with {} replaced by list of file names
status 1
```

### find --nope

```cu
(run (list "find" "--nope") "")
```
---
```output
stderr:
find: unrecognized: --nope
Usage: find [-HL] [PATH]... [OPTIONS] [ACTIONS]

Search for files and perform actions on them.
First failed action stops processing of current file.
Defaults: PATH is current directory, action is '-print'

	-maxdepth N	Descend at most N levels. -maxdepth 0 applies
			actions to command line arguments only
	-mindepth N	Don't act on first N levels

Actions:
	( ACTIONS )	Group actions for -o / -a
	! ACT		Invert ACT's success/failure
	ACT1 [-a] ACT2	If ACT1 fails, stop, else do ACT2
	ACT1 -o ACT2	If ACT1 succeeds, stop, else do ACT2
			Note: -a has higher priority than -o
	-name PATTERN	Match file name (w/o directory name) to PATTERN
	-iname PATTERN	Case insensitive -name
	-path PATTERN	Match path to PATTERN
	-type X		File type is X (one of: f,d,l,b,c,s,p)
	-newer FILE	mtime is more recent than FILE's
	-size N[bck]	File size is N (c:bytes,k:kbytes,b:512 bytes(def.))
			+/-N: file size is bigger/smaller than N
	-empty		Match empty file/directory
If none of the following actions is specified, -print is assumed
	-print		Print file name
	-print0		Print file name, NUL terminated
	-exec CMD ARG ;	Run CMD with all instances of {} replaced by
			file name. Fails if CMD exits with nonzero
	-exec CMD ARG + Run CMD with {} replaced by list of file names
status 1
```

### env -~

```cu
(run (list "env" "-~") "")
```
---
```output
stderr:
env: unrecognized option: ~
Usage: env [-i0] [-u NAME]... [-] [NAME=VALUE]... [PROG ARGS]

Print current environment or run PROG after setting up environment

	-0	NUL terminated output
	-u NAME	Remove variable from environment
status 1
```

### env --nope

```cu
(run (list "env" "--nope") "")
```
---
```output
stderr:
env: unrecognized option: nope
Usage: env [-i0] [-u NAME]... [-] [NAME=VALUE]... [PROG ARGS]

Print current environment or run PROG after setting up environment

	-0	NUL terminated output
	-u NAME	Remove variable from environment
status 1
```

### env -u

```cu
(run (list "env" "-u") "")
```
---
```output
stderr:
env: option requires an argument: u
Usage: env [-i0] [-u NAME]... [-] [NAME=VALUE]... [PROG ARGS]

Print current environment or run PROG after setting up environment

	-0	NUL terminated output
	-u NAME	Remove variable from environment
status 1
```

### printenv -~

```cu
(run (list "printenv" "-~") "")
```
---
```output
stderr:
status 1
```

### printenv --nope

```cu
(run (list "printenv" "--nope") "")
```
---
```output
stderr:
status 1
```

### sleep -~

```cu
(run (list "sleep" "-~") "")
```
---
```output
stderr:
sleep: invalid number '-~'
status 1
```

### sleep --nope

```cu
(run (list "sleep" "--nope") "")
```
---
```output
stderr:
sleep: invalid number '--nope'
status 1
```

### date -~

```cu
(run (list "date" "-~") "")
```
---
```output
stderr:
date: unrecognized option: ~
Usage: date [OPTIONS] [+FMT] [[-s] TIME]

Display time (using +FMT), or set time

	-u		Work in UTC (don't convert to local time)
	[-s] TIME	Set time to TIME
	-d TIME		Display TIME, not 'now'
	-D FMT		FMT (strptime format) for -s/-d TIME conversion
	-r FILE		Display last modification time of FILE
	-R		Output RFC-2822 date
	-I[SPEC]	Output ISO-8601 date
			SPEC=date (default), hours, minutes, seconds or ns

Recognized TIME formats:
	@seconds_since_1970
	hh:mm[:ss]
	[YYYY.]MM.DD-hh:mm[:ss]
	YYYY-MM-DD hh:mm[:ss]
	[[[[[YY]YY]MM]DD]hh]mm[.ss]
	'date TIME' form accepts MMDDhhmm[[YY]YY][.ss] instead
status 1
```

### date --nope

```cu
(run (list "date" "--nope") "")
```
---
```output
stderr:
date: unrecognized option: nope
Usage: date [OPTIONS] [+FMT] [[-s] TIME]

Display time (using +FMT), or set time

	-u		Work in UTC (don't convert to local time)
	[-s] TIME	Set time to TIME
	-d TIME		Display TIME, not 'now'
	-D FMT		FMT (strptime format) for -s/-d TIME conversion
	-r FILE		Display last modification time of FILE
	-R		Output RFC-2822 date
	-I[SPEC]	Output ISO-8601 date
			SPEC=date (default), hours, minutes, seconds or ns

Recognized TIME formats:
	@seconds_since_1970
	hh:mm[:ss]
	[YYYY.]MM.DD-hh:mm[:ss]
	YYYY-MM-DD hh:mm[:ss]
	[[[[[YY]YY]MM]DD]hh]mm[.ss]
	'date TIME' form accepts MMDDhhmm[[YY]YY][.ss] instead
status 1
```

### date -d

```cu
(run (list "date" "-d") "")
```
---
```output
stderr:
date: option requires an argument: d
Usage: date [OPTIONS] [+FMT] [[-s] TIME]

Display time (using +FMT), or set time

	-u		Work in UTC (don't convert to local time)
	[-s] TIME	Set time to TIME
	-d TIME		Display TIME, not 'now'
	-D FMT		FMT (strptime format) for -s/-d TIME conversion
	-r FILE		Display last modification time of FILE
	-R		Output RFC-2822 date
	-I[SPEC]	Output ISO-8601 date
			SPEC=date (default), hours, minutes, seconds or ns

Recognized TIME formats:
	@seconds_since_1970
	hh:mm[:ss]
	[YYYY.]MM.DD-hh:mm[:ss]
	YYYY-MM-DD hh:mm[:ss]
	[[[[[YY]YY]MM]DD]hh]mm[.ss]
	'date TIME' form accepts MMDDhhmm[[YY]YY][.ss] instead
status 1
```

### which -~

```cu
(run (list "which" "-~") "")
```
---
```output
stderr:
which: unrecognized option: ~
Usage: which [-a] COMMAND...

Locate COMMAND

	-a	Show all matches
status 1
```

### which --nope

```cu
(run (list "which" "--nope") "")
```
---
```output
stderr:
which: unrecognized option: nope
Usage: which [-a] COMMAND...

Locate COMMAND

	-a	Show all matches
status 1
```

### wget -~

```cu
(run (list "wget" "-~") "")
```
---
```output
stderr:
wget: unrecognized option: ~
Usage: wget [-cqS] [--spider] [-O FILE] [-o LOGFILE] [--header STR]...
	[-U AGENT] [--post-data STR | --post-file FILE] [-Y on/off]
	[--no-check-certificate] [-P DIR] [-T SEC] [-t TRIES] URL...

Retrieve files via HTTP or FTP

	--spider	Only check URL existence: $? is 0 if exists
	--header STR	Add STR (of form 'header: value') to headers
	-U AGENT	Use AGENT for User-Agent header
	--post-data STR	Send STR using POST method
	--post-file FILE	Send FILE using POST method
	--no-check-certificate	Don't validate the server's certificate
	-c		Continue retrieval of partial download
	-q		Quiet
	-P DIR		Save to DIR (default .)
	-S    		Show server response
	-t TRIES	Retry count (default 20)
	-T SEC		Network read timeout is SEC seconds
	-O FILE		Save to FILE ('-' for stdout)
	-o LOGFILE	Log messages to FILE
	-Y on/off	Use proxy
status 1
```

### wget --nope

```cu
(run (list "wget" "--nope") "")
```
---
```output
stderr:
wget: unrecognized option: nope
Usage: wget [-cqS] [--spider] [-O FILE] [-o LOGFILE] [--header STR]...
	[-U AGENT] [--post-data STR | --post-file FILE] [-Y on/off]
	[--no-check-certificate] [-P DIR] [-T SEC] [-t TRIES] URL...

Retrieve files via HTTP or FTP

	--spider	Only check URL existence: $? is 0 if exists
	--header STR	Add STR (of form 'header: value') to headers
	-U AGENT	Use AGENT for User-Agent header
	--post-data STR	Send STR using POST method
	--post-file FILE	Send FILE using POST method
	--no-check-certificate	Don't validate the server's certificate
	-c		Continue retrieval of partial download
	-q		Quiet
	-P DIR		Save to DIR (default .)
	-S    		Show server response
	-t TRIES	Retry count (default 20)
	-T SEC		Network read timeout is SEC seconds
	-O FILE		Save to FILE ('-' for stdout)
	-o LOGFILE	Log messages to FILE
	-Y on/off	Use proxy
status 1
```

### wget -O

```cu
(run (list "wget" "-O") "")
```
---
```output
stderr:
wget: option requires an argument: O
Usage: wget [-cqS] [--spider] [-O FILE] [-o LOGFILE] [--header STR]...
	[-U AGENT] [--post-data STR | --post-file FILE] [-Y on/off]
	[--no-check-certificate] [-P DIR] [-T SEC] [-t TRIES] URL...

Retrieve files via HTTP or FTP

	--spider	Only check URL existence: $? is 0 if exists
	--header STR	Add STR (of form 'header: value') to headers
	-U AGENT	Use AGENT for User-Agent header
	--post-data STR	Send STR using POST method
	--post-file FILE	Send FILE using POST method
	--no-check-certificate	Don't validate the server's certificate
	-c		Continue retrieval of partial download
	-q		Quiet
	-P DIR		Save to DIR (default .)
	-S    		Show server response
	-t TRIES	Retry count (default 20)
	-T SEC		Network read timeout is SEC seconds
	-O FILE		Save to FILE ('-' for stdout)
	-o LOGFILE	Log messages to FILE
	-Y on/off	Use proxy
status 1
```

### whois -~

```cu
(run (list "whois" "-~") "")
```
---
```output
stderr:
whois: unrecognized option: ~
Usage: whois [-i] [-h SERVER] [-p PORT] NAME...

Query WHOIS info about NAME

	-i	Show redirect results too
	-h,-p	Server to query
status 1
```

### whois --nope

```cu
(run (list "whois" "--nope") "")
```
---
```output
stderr:
whois: unrecognized option: nope
Usage: whois [-i] [-h SERVER] [-p PORT] NAME...

Query WHOIS info about NAME

	-i	Show redirect results too
	-h,-p	Server to query
status 1
```

### whois -h

```cu
(run (list "whois" "-h") "")
```
---
```output
stderr:
whois: option requires an argument: h
Usage: whois [-i] [-h SERVER] [-p PORT] NAME...

Query WHOIS info about NAME

	-i	Show redirect results too
	-h,-p	Server to query
status 1
```

### tftp -~

```cu
(run (list "tftp" "-~") "")
```
---
```output
stderr:
tftp: unrecognized option: ~
Usage: tftp [OPTIONS] HOST [PORT]

Transfer a file from/to tftp server

	-l FILE	Local FILE
	-r FILE	Remote FILE
	-g	Get file
	-p	Put file
	-b SIZE	Transfer blocks in bytes
status 1
```

### tftp --nope

```cu
(run (list "tftp" "--nope") "")
```
---
```output
stderr:
tftp: unrecognized option: nope
Usage: tftp [OPTIONS] HOST [PORT]

Transfer a file from/to tftp server

	-l FILE	Local FILE
	-r FILE	Remote FILE
	-g	Get file
	-p	Put file
	-b SIZE	Transfer blocks in bytes
status 1
```

### tftp -l

```cu
(run (list "tftp" "-l") "")
```
---
```output
stderr:
tftp: option requires an argument: l
Usage: tftp [OPTIONS] HOST [PORT]

Transfer a file from/to tftp server

	-l FILE	Local FILE
	-r FILE	Remote FILE
	-g	Get file
	-p	Put file
	-b SIZE	Transfer blocks in bytes
status 1
```

### nslookup -~

```cu
(run (list "nslookup" "-~") "")
```
---
```output
stderr:
Usage: nslookup [-type=QUERY_TYPE] [-debug] HOST [DNS_SERVER]

Query DNS about HOST

QUERY_TYPE: soa,ns,a,aaaa,cname,mx,txt,ptr,srv,any
status 1
```

### nslookup --nope

```cu
(run (list "nslookup" "--nope") "")
```
---
```output
stderr:
Usage: nslookup [-type=QUERY_TYPE] [-debug] HOST [DNS_SERVER]

Query DNS about HOST

QUERY_TYPE: soa,ns,a,aaaa,cname,mx,txt,ptr,srv,any
status 1
```

### nslookup -type

```cu
(run (list "nslookup" "-type") "")
```
---
```output
stderr:
nslookup: invalid query type ""
status 1
```

### ftpget -~

```cu
(run (list "ftpget" "-~") "")
```
---
```output
stderr:
ftpget: unrecognized option: ~
Usage: ftpget [OPTIONS] HOST [LOCAL_FILE] REMOTE_FILE

Download a file via FTP

	-c	Continue previous transfer
	-v	Verbose
	-u USER	Username
	-p PASS	Password
	-P PORT
status 1
```

### ftpget --nope

```cu
(run (list "ftpget" "--nope") "")
```
---
```output
stderr:
ftpget: unrecognized option: nope
Usage: ftpget [OPTIONS] HOST [LOCAL_FILE] REMOTE_FILE

Download a file via FTP

	-c	Continue previous transfer
	-v	Verbose
	-u USER	Username
	-p PASS	Password
	-P PORT
status 1
```

### ftpget -u

```cu
(run (list "ftpget" "-u") "")
```
---
```output
stderr:
ftpget: option requires an argument: u
Usage: ftpget [OPTIONS] HOST [LOCAL_FILE] REMOTE_FILE

Download a file via FTP

	-c	Continue previous transfer
	-v	Verbose
	-u USER	Username
	-p PASS	Password
	-P PORT
status 1
```

### ftpput -~

```cu
(run (list "ftpput" "-~") "")
```
---
```output
stderr:
ftpput: unrecognized option: ~
Usage: ftpput [OPTIONS] HOST [REMOTE_FILE] LOCAL_FILE

Upload a file to a FTP server

	-v	Verbose
	-u USER	Username
	-p PASS	Password
	-P PORT
status 1
```

### ftpput --nope

```cu
(run (list "ftpput" "--nope") "")
```
---
```output
stderr:
ftpput: unrecognized option: nope
Usage: ftpput [OPTIONS] HOST [REMOTE_FILE] LOCAL_FILE

Upload a file to a FTP server

	-v	Verbose
	-u USER	Username
	-p PASS	Password
	-P PORT
status 1
```

### ftpput -u

```cu
(run (list "ftpput" "-u") "")
```
---
```output
stderr:
ftpput: option requires an argument: u
Usage: ftpput [OPTIONS] HOST [REMOTE_FILE] LOCAL_FILE

Upload a file to a FTP server

	-v	Verbose
	-u USER	Username
	-p PASS	Password
	-P PORT
status 1
```

### httpd -~

```cu
(run (list "httpd" "-~") "")
```
---
```output
stderr:
httpd: unrecognized option: ~
Usage: httpd [-ifv[v]] [-c CONFFILE] [-p [IP:]PORT] [-M MAXCONN] [-K KILLSEC] [-u USER[:GRP]] [-r REALM] [-h HOME]
or httpd -d/-e/-m STRING

Listen for incoming HTTP requests

	-i		Inetd mode
	-f		Run in foreground
	-v[v]		Verbose
	-p [IP:]PORT	Bind to IP:PORT (default *:80)
	-M NUM		Pause if NUM connections are open (default 256)
	-K NUM		Kill CGIs after NUM seconds
	-u USER[:GRP]	Set uid/gid after binding to port
	-r REALM	Authentication Realm for Basic Authentication
	-h HOME		Home directory (default .)
	-c FILE		Configuration file (default {/etc,HOME}/httpd.conf)
	-m STRING	MD5 crypt STRING
	-e STRING	HTML encode STRING
	-d STRING	URL decode STRING
status 1
```

### httpd --nope

```cu
(run (list "httpd" "--nope") "")
```
---
```output
stderr:
httpd: unrecognized option: nope
Usage: httpd [-ifv[v]] [-c CONFFILE] [-p [IP:]PORT] [-M MAXCONN] [-K KILLSEC] [-u USER[:GRP]] [-r REALM] [-h HOME]
or httpd -d/-e/-m STRING

Listen for incoming HTTP requests

	-i		Inetd mode
	-f		Run in foreground
	-v[v]		Verbose
	-p [IP:]PORT	Bind to IP:PORT (default *:80)
	-M NUM		Pause if NUM connections are open (default 256)
	-K NUM		Kill CGIs after NUM seconds
	-u USER[:GRP]	Set uid/gid after binding to port
	-r REALM	Authentication Realm for Basic Authentication
	-h HOME		Home directory (default .)
	-c FILE		Configuration file (default {/etc,HOME}/httpd.conf)
	-m STRING	MD5 crypt STRING
	-e STRING	HTML encode STRING
	-d STRING	URL decode STRING
status 1
```

### ftpd -~

```cu
(run (list "ftpd" "-~") "")
```
---
```output
stderr:
ftpd: unrecognized option: ~
Usage: ftpd [-wvS] [-a USER] [-t SEC] [-T SEC] [DIR]

FTP server. Chroots to DIR, if this fails (run by non-root), cds to it.
It is an inetd service, inetd.conf line:
	21 stream tcp nowait root ftpd ftpd /files/to/serve
Can be run from tcpsvd:
	tcpsvd -vE 0.0.0.0 21 ftpd /files/to/serve

	-w	Allow upload
	-A	No login required, client access occurs under ftpd's UID
	-a USER	Enable 'anonymous' login and map it to USER
	-v	Log errors to stderr. -vv: verbose log
	-S	Log errors to syslog. -SS: verbose log
	-t,-T N	Idle and absolute timeout
status 1
```

### ftpd --nope

```cu
(run (list "ftpd" "--nope") "")
```
---
```output
stderr:
ftpd: unrecognized option: nope
Usage: ftpd [-wvS] [-a USER] [-t SEC] [-T SEC] [DIR]

FTP server. Chroots to DIR, if this fails (run by non-root), cds to it.
It is an inetd service, inetd.conf line:
	21 stream tcp nowait root ftpd ftpd /files/to/serve
Can be run from tcpsvd:
	tcpsvd -vE 0.0.0.0 21 ftpd /files/to/serve

	-w	Allow upload
	-A	No login required, client access occurs under ftpd's UID
	-a USER	Enable 'anonymous' login and map it to USER
	-v	Log errors to stderr. -vv: verbose log
	-S	Log errors to syslog. -SS: verbose log
	-t,-T N	Idle and absolute timeout
status 1
```

### dnsd -~

```cu
(run (list "dnsd" "-~") "")
```
---
```output
stderr:
dnsd: unrecognized option: ~
Usage: dnsd [-dvs] [-c CONFFILE] [-t TTL_SEC] [-p PORT] [-i ADDR]

Small static DNS server daemon

	-c FILE	Config file
	-t SEC	TTL
	-p PORT	Listen on PORT
	-i ADDR	Listen on ADDR
	-d	Daemonize
	-v	Verbose
	-s	Send successful replies only. Use this if you want
		to use /etc/resolv.conf with two nameserver lines:
			nameserver DNSD_SERVER
			nameserver NORMAL_DNS_SERVER
status 1
```

### dnsd --nope

```cu
(run (list "dnsd" "--nope") "")
```
---
```output
stderr:
dnsd: unrecognized option: nope
Usage: dnsd [-dvs] [-c CONFFILE] [-t TTL_SEC] [-p PORT] [-i ADDR]

Small static DNS server daemon

	-c FILE	Config file
	-t SEC	TTL
	-p PORT	Listen on PORT
	-i ADDR	Listen on ADDR
	-d	Daemonize
	-v	Verbose
	-s	Send successful replies only. Use this if you want
		to use /etc/resolv.conf with two nameserver lines:
			nameserver DNSD_SERVER
			nameserver NORMAL_DNS_SERVER
status 1
```

### httpd -c

```cu
(run (list "httpd" "-c") "")
```
---
```output
stderr:
httpd: option requires an argument: c
Usage: httpd [-ifv[v]] [-c CONFFILE] [-p [IP:]PORT] [-M MAXCONN] [-K KILLSEC] [-u USER[:GRP]] [-r REALM] [-h HOME]
or httpd -d/-e/-m STRING

Listen for incoming HTTP requests

	-i		Inetd mode
	-f		Run in foreground
	-v[v]		Verbose
	-p [IP:]PORT	Bind to IP:PORT (default *:80)
	-M NUM		Pause if NUM connections are open (default 256)
	-K NUM		Kill CGIs after NUM seconds
	-u USER[:GRP]	Set uid/gid after binding to port
	-r REALM	Authentication Realm for Basic Authentication
	-h HOME		Home directory (default .)
	-c FILE		Configuration file (default {/etc,HOME}/httpd.conf)
	-m STRING	MD5 crypt STRING
	-e STRING	HTML encode STRING
	-d STRING	URL decode STRING
status 1
```

### ipcalc -~

```cu
(run (list "ipcalc" "-~") "")
```
---
```output
stderr:
ipcalc: unrecognized option: ~
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

### ipcalc --nope

```cu
(run (list "ipcalc" "--nope") "")
```
---
```output
stderr:
ipcalc: unrecognized option: nope
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

### nc -~

```cu
(run (list "nc" "-~") "")
```
---
```output
stderr:
nc: unrecognized option: ~
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

### nc --nope

```cu
(run (list "nc" "--nope") "")
```
---
```output
stderr:
nc: unrecognized option: nope
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

### xargs -~

```cu
(run (list "xargs" "-~") "")
```
---
```output
stderr:
xargs: unrecognized option: ~
Usage: xargs [OPTIONS] [PROG ARGS]

Run PROG on every item given by stdin

	-0	NUL terminated input
	-a FILE	Read from FILE instead of stdin
	-r	Don't run command if input is empty
	-t	Print the command on stderr before execution
	-E STR,-e[STR]	STR stops input processing
	-I STR	Replace STR within PROG ARGS with input line
	-n N	Pass no more than N args to PROG
	-s N	Pass command line of no more than N bytes
	-x	Exit if size is exceeded
status 1
```

### xargs --nope

```cu
(run (list "xargs" "--nope") "")
```
---
```output
stderr:
xargs: unrecognized option: nope
Usage: xargs [OPTIONS] [PROG ARGS]

Run PROG on every item given by stdin

	-0	NUL terminated input
	-a FILE	Read from FILE instead of stdin
	-r	Don't run command if input is empty
	-t	Print the command on stderr before execution
	-E STR,-e[STR]	STR stops input processing
	-I STR	Replace STR within PROG ARGS with input line
	-n N	Pass no more than N args to PROG
	-s N	Pass command line of no more than N bytes
	-x	Exit if size is exceeded
status 1
```

### xargs -n

```cu
(run (list "xargs" "-n") "")
```
---
```output
stderr:
xargs: option requires an argument: n
Usage: xargs [OPTIONS] [PROG ARGS]

Run PROG on every item given by stdin

	-0	NUL terminated input
	-a FILE	Read from FILE instead of stdin
	-r	Don't run command if input is empty
	-t	Print the command on stderr before execution
	-E STR,-e[STR]	STR stops input processing
	-I STR	Replace STR within PROG ARGS with input line
	-n N	Pass no more than N args to PROG
	-s N	Pass command line of no more than N bytes
	-x	Exit if size is exceeded
status 1
```

### vi -~

```cu
(run (list "vi" "-~") "")
```
---
```output
stderr:
vi: unrecognized option: ~
Usage: vi [-c CMD] [-R] [-H] [FILE]...

Edit FILE

	-c CMD	Initial command to run ($EXINIT and ~/.exrc also available)
	-R	Read-only
	-H	List available features
status 1
```

### vi --nope

```cu
(run (list "vi" "--nope") "")
```
---
```output
stderr:
vi: unrecognized option: nope
Usage: vi [-c CMD] [-R] [-H] [FILE]...

Edit FILE

	-c CMD	Initial command to run ($EXINIT and ~/.exrc also available)
	-R	Read-only
	-H	List available features
status 1
```

### vi -c

```cu
(run (list "vi" "-c") "")
```
---
```output
stderr:
vi: option requires an argument: c
Usage: vi [-c CMD] [-R] [-H] [FILE]...

Edit FILE

	-c CMD	Initial command to run ($EXINIT and ~/.exrc also available)
	-R	Read-only
	-H	List available features
status 1
```

### more -~

```cu
(run (list "more" "-~") "")
```
---
```output
stderr:
more: unrecognized option: ~
Usage: more [FILE]...

View FILE (or stdin) one screenful at a time
status 1
```

### more --nope

```cu
(run (list "more" "--nope") "")
```
---
```output
stderr:
more: unrecognized option: nope
Usage: more [FILE]...

View FILE (or stdin) one screenful at a time
status 1
```

### clear -~

```cu
(run (list "clear" "-~") "")
```
---
```output
[H[Jstderr:
status 0
```

### clear --nope

```cu
(run (list "clear" "--nope") "")
```
---
```output
[H[Jstderr:
status 0
```

### reset -~

```cu
(run (list "reset" "-~") "")
```
---
```output
stderr:
status 0
```

### reset --nope

```cu
(run (list "reset" "--nope") "")
```
---
```output
stderr:
status 0
```

### tsort -~

```cu
(run (list "tsort" "-~") "")
```
---
```output
stderr:
tsort: can't open '-~': No such file or directory
status 1
```

### tsort --nope

```cu
(run (list "tsort" "--nope") "")
```
---
```output
stderr:
tsort: can't open '--nope': No such file or directory
status 1
```

### strings -~

```cu
(run (list "strings" "-~") "")
```
---
```output
stderr:
strings: unrecognized option: ~
Usage: strings [-fo] [-t o|d|x] [-n LEN] [FILE]...

Display printable strings in a binary file

	-f		Precede strings with filenames
	-o		Precede strings with octal offsets
	-t o|d|x	Precede strings with offsets in base 8/10/16
	-n LEN		At least LEN characters form a string (default 4)
status 1
```

### strings --nope

```cu
(run (list "strings" "--nope") "")
```
---
```output
stderr:
strings: unrecognized option: nope
Usage: strings [-fo] [-t o|d|x] [-n LEN] [FILE]...

Display printable strings in a binary file

	-f		Precede strings with filenames
	-o		Precede strings with octal offsets
	-t o|d|x	Precede strings with offsets in base 8/10/16
	-n LEN		At least LEN characters form a string (default 4)
status 1
```

### strings -n

```cu
(run (list "strings" "-n") "")
```
---
```output
stderr:
strings: option requires an argument: n
Usage: strings [-fo] [-t o|d|x] [-n LEN] [FILE]...

Display printable strings in a binary file

	-f		Precede strings with filenames
	-o		Precede strings with octal offsets
	-t o|d|x	Precede strings with offsets in base 8/10/16
	-n LEN		At least LEN characters form a string (default 4)
status 1
```

### cal -~

```cu
(run (list "cal" "-~") "")
```
---
```output
stderr:
cal: unrecognized option: ~
Usage: cal [-jmy] [[MONTH] YEAR]

Display a calendar

	-j	Use julian dates
	-m	Week starts on Monday
	-y	Display the entire year
status 1
```

### cal --nope

```cu
(run (list "cal" "--nope") "")
```
---
```output
stderr:
cal: unrecognized option: nope
Usage: cal [-jmy] [[MONTH] YEAR]

Display a calendar

	-j	Use julian dates
	-m	Week starts on Monday
	-y	Display the entire year
status 1
```

### hexdump -~

```cu
(run (list "hexdump" "-~") "")
```
---
```output
stderr:
hexdump: unrecognized option: ~
Usage: hexdump [-bcdoxCv] [-e FMT] [-f FMT_FILE] [-n LEN] [-s OFS] [FILE]...

Display FILEs (or stdin) in a user specified format

	-b		1-byte octal display
	-c		1-byte character display
	-d		2-byte decimal display
	-o		2-byte octal display
	-x		2-byte hex display
	-C		hex+ASCII 16 bytes per line
	-v		Show all (no dup folding)
	-e FORMAT_STR	Example: '16/1 "%02x|""\n"'
	-f FORMAT_FILE
	-n LENGTH	Show only first LENGTH bytes
	-s OFFSET	Skip OFFSET bytes
status 1
```

### hexdump --nope

```cu
(run (list "hexdump" "--nope") "")
```
---
```output
stderr:
hexdump: unrecognized option: -
Usage: hexdump [-bcdoxCv] [-e FMT] [-f FMT_FILE] [-n LEN] [-s OFS] [FILE]...

Display FILEs (or stdin) in a user specified format

	-b		1-byte octal display
	-c		1-byte character display
	-d		2-byte decimal display
	-o		2-byte octal display
	-x		2-byte hex display
	-C		hex+ASCII 16 bytes per line
	-v		Show all (no dup folding)
	-e FORMAT_STR	Example: '16/1 "%02x|""\n"'
	-f FORMAT_FILE
	-n LENGTH	Show only first LENGTH bytes
	-s OFFSET	Skip OFFSET bytes
status 1
```

### hexdump -e

```cu
(run (list "hexdump" "-e") "")
```
---
```output
stderr:
hexdump: option requires an argument: e
Usage: hexdump [-bcdoxCv] [-e FMT] [-f FMT_FILE] [-n LEN] [-s OFS] [FILE]...

Display FILEs (or stdin) in a user specified format

	-b		1-byte octal display
	-c		1-byte character display
	-d		2-byte decimal display
	-o		2-byte octal display
	-x		2-byte hex display
	-C		hex+ASCII 16 bytes per line
	-v		Show all (no dup folding)
	-e FORMAT_STR	Example: '16/1 "%02x|""\n"'
	-f FORMAT_FILE
	-n LENGTH	Show only first LENGTH bytes
	-s OFFSET	Skip OFFSET bytes
status 1
```

### hd -~

```cu
(run (list "hd" "-~") "")
```
---
```output
stderr:
hd: unrecognized option: ~
Usage: hd FILE...

hd is an alias for hexdump -C
status 1
```

### hd --nope

```cu
(run (list "hd" "--nope") "")
```
---
```output
stderr:
hd: unrecognized option: -
Usage: hd FILE...

hd is an alias for hexdump -C
status 1
```

### xxd -~

```cu
(run (list "xxd" "-~") "")
```
---
```output
stderr:
xxd: unrecognized option: ~
Usage: xxd [-ri] [-ps] [-g N] [-c N] [-l LEN] [-s OFS] [-o OFS] [FILE]

Hex dump FILE (or stdin)

	-g N		Bytes per group (default 2)
	-c N		Bytes per line (default:16, -ps:30, -i:12)
	-ps		Show only hex bytes (no offset/spaces)
	-i		C include file style
	-l LENGTH	Show only first LENGTH bytes
	-s OFFSET	Skip OFFSET bytes
	-o OFFSET	Add OFFSET to displayed offset
	-r		Reverse (with -p, assumes no offsets in input)
status 1
```

### xxd --nope

```cu
(run (list "xxd" "--nope") "")
```
---
```output
stderr:
xxd: unrecognized option: nope
Usage: xxd [-ri] [-ps] [-g N] [-c N] [-l LEN] [-s OFS] [-o OFS] [FILE]

Hex dump FILE (or stdin)

	-g N		Bytes per group (default 2)
	-c N		Bytes per line (default:16, -ps:30, -i:12)
	-ps		Show only hex bytes (no offset/spaces)
	-i		C include file style
	-l LENGTH	Show only first LENGTH bytes
	-s OFFSET	Skip OFFSET bytes
	-o OFFSET	Add OFFSET to displayed offset
	-r		Reverse (with -p, assumes no offsets in input)
status 1
```

### xxd -l

```cu
(run (list "xxd" "-l") "")
```
---
```output
stderr:
xxd: option requires an argument: l
Usage: xxd [-ri] [-ps] [-g N] [-c N] [-l LEN] [-s OFS] [-o OFS] [FILE]

Hex dump FILE (or stdin)

	-g N		Bytes per group (default 2)
	-c N		Bytes per line (default:16, -ps:30, -i:12)
	-ps		Show only hex bytes (no offset/spaces)
	-i		C include file style
	-l LENGTH	Show only first LENGTH bytes
	-s OFFSET	Skip OFFSET bytes
	-o OFFSET	Add OFFSET to displayed offset
	-r		Reverse (with -p, assumes no offsets in input)
status 1
```

### fsync -~

```cu
(run (list "fsync" "-~") "")
```
---
```output
stderr:
fsync: unrecognized option: ~
Usage: fsync [-d] FILE...

Write all buffered blocks in FILEs to disk

	-d	Avoid syncing metadata
status 1
```

### fsync --nope

```cu
(run (list "fsync" "--nope") "")
```
---
```output
stderr:
fsync: unrecognized option: nope
Usage: fsync [-d] FILE...

Write all buffered blocks in FILEs to disk

	-d	Avoid syncing metadata
status 1
```

### flock -~

```cu
(run (list "flock" "-~") "")
```
---
```output
stderr:
flock: unrecognized option: ~
Usage: flock [-sxun] FD | { FILE [-c] PROG ARGS }

[Un]lock file descriptor, or lock FILE, run PROG

	-s	Shared lock
	-x	Exclusive lock (default)
	-u	Unlock FD
	-n	Fail rather than wait
status 1
```

### flock --nope

```cu
(run (list "flock" "--nope") "")
```
---
```output
stderr:
flock: unrecognized option: nope
Usage: flock [-sxun] FD | { FILE [-c] PROG ARGS }

[Un]lock file descriptor, or lock FILE, run PROG

	-s	Shared lock
	-x	Exclusive lock (default)
	-u	Unlock FD
	-n	Fail rather than wait
status 1
```

### setsid -~

```cu
(run (list "setsid" "-~") "")
```
---
```output
stderr:
setsid: unrecognized option: ~
Usage: setsid [-c] PROG ARGS

Run PROG in a new session. PROG will have no controlling terminal
and will not be affected by keyboard signals (^C etc).

	-c	Set controlling terminal to stdin
status 1
```

### setsid --nope

```cu
(run (list "setsid" "--nope") "")
```
---
```output
stderr:
setsid: unrecognized option: nope
Usage: setsid [-c] PROG ARGS

Run PROG in a new session. PROG will have no controlling terminal
and will not be affected by keyboard signals (^C etc).

	-c	Set controlling terminal to stdin
status 1
```

### pipe_progress -~

```cu
(run (list "pipe_progress" "-~") "")
```
---
```output
stderr:

status 0
```

### pipe_progress --nope

```cu
(run (list "pipe_progress" "--nope") "")
```
---
```output
stderr:

status 0
```

### tree -~

```cu
(run (list "tree" "-~") "")
```
---
```output
-~ [error opening dir]|
|
0 directories, 0 files|
stderr:
status 0
```

### tree --nope

```cu
(run (list "tree" "--nope") "")
```
---
```output
--nope [error opening dir]|
|
0 directories, 0 files|
stderr:
status 0
```

### time -~

```cu
(run (list "time" "-~") "")
```
---
```output
stderr:
time: unrecognized option: ~
Usage: time [-vpa] [-o FILE] PROG ARGS

Run PROG, display resource usage when it exits

	-v	Verbose
	-p	POSIX output format
	-f FMT	Custom format
	-o FILE	Write result to FILE
	-a	Append (else overwrite)
status 1
```

### time --nope

```cu
(run (list "time" "--nope") "")
```
---
```output
stderr:
time: unrecognized option: nope
Usage: time [-vpa] [-o FILE] PROG ARGS

Run PROG, display resource usage when it exits

	-v	Verbose
	-p	POSIX output format
	-f FMT	Custom format
	-o FILE	Write result to FILE
	-a	Append (else overwrite)
status 1
```

### time -o

```cu
(run (list "time" "-o") "")
```
---
```output
stderr:
time: option requires an argument: o
Usage: time [-vpa] [-o FILE] PROG ARGS

Run PROG, display resource usage when it exits

	-v	Verbose
	-p	POSIX output format
	-f FMT	Custom format
	-o FILE	Write result to FILE
	-a	Append (else overwrite)
status 1
```

### base32 -~

```cu
(run (list "base32" "-~") "")
```
---
```output
stderr:
base32: unrecognized option: ~
Usage: base32 [-d] [-w COL] [FILE]

Base32 encode or decode FILE to standard output

	-d	Decode data
	-w COL	Wrap lines at COL (default 76, 0 disables)
status 1
```

### base32 --nope

```cu
(run (list "base32" "--nope") "")
```
---
```output
stderr:
base32: unrecognized option: nope
Usage: base32 [-d] [-w COL] [FILE]

Base32 encode or decode FILE to standard output

	-d	Decode data
	-w COL	Wrap lines at COL (default 76, 0 disables)
status 1
```

### base32 -w

```cu
(run (list "base32" "-w") "")
```
---
```output
stderr:
base32: option requires an argument: w
Usage: base32 [-d] [-w COL] [FILE]

Base32 encode or decode FILE to standard output

	-d	Decode data
	-w COL	Wrap lines at COL (default 76, 0 disables)
status 1
```

### crc32 -~

```cu
(run (list "crc32" "-~") "")
```
---
```output
stderr:
crc32: unrecognized option: ~
Usage: crc32 FILE...

Calculate CRC32 checksum of FILEs
status 1
```

### crc32 --nope

```cu
(run (list "crc32" "--nope") "")
```
---
```output
stderr:
crc32: unrecognized option: nope
Usage: crc32 FILE...

Calculate CRC32 checksum of FILEs
status 1
```

### ascii -~

```cu
(run (list "ascii" "-~") "")
```
---
```output
Dec Hex    Dec Hex    Dec Hex  Dec Hex  Dec Hex  Dec Hex   Dec Hex   Dec Hex|
  0 00 NUL  16 10 DLE  32 20    48 30 0  64 40 @  80 50 P   96 60 `  112 70 p|
  1 01 SOH  17 11 DC1  33 21 !  49 31 1  65 41 A  81 51 Q   97 61 a  113 71 q|
  2 02 STX  18 12 DC2  34 22 "  50 32 2  66 42 B  82 52 R   98 62 b  114 72 r|
  3 03 ETX  19 13 DC3  35 23 #  51 33 3  67 43 C  83 53 S   99 63 c  115 73 s|
  4 04 EOT  20 14 DC4  36 24 $  52 34 4  68 44 D  84 54 T  100 64 d  116 74 t|
  5 05 ENQ  21 15 NAK  37 25 %  53 35 5  69 45 E  85 55 U  101 65 e  117 75 u|
  6 06 ACK  22 16 SYN  38 26 &  54 36 6  70 46 F  86 56 V  102 66 f  118 76 v|
  7 07 BEL  23 17 ETB  39 27 '  55 37 7  71 47 G  87 57 W  103 67 g  119 77 w|
  8 08 BS   24 18 CAN  40 28 (  56 38 8  72 48 H  88 58 X  104 68 h  120 78 x|
  9 09 HT   25 19 EM   41 29 )  57 39 9  73 49 I  89 59 Y  105 69 i  121 79 y|
 10 0a NL   26 1a SUB  42 2a *  58 3a :  74 4a J  90 5a Z  106 6a j  122 7a z|
 11 0b VT   27 1b ESC  43 2b +  59 3b ;  75 4b K  91 5b [  107 6b k  123 7b {|
 12 0c FF   28 1c FS   44 2c ,  60 3c <  76 4c L  92 5c \  108 6c l  124 7c ||
 13 0d CR   29 1d GS   45 2d -  61 3d =  77 4d M  93 5d ]  109 6d m  125 7d }|
 14 0e SO   30 1e RS   46 2e .  62 3e >  78 4e N  94 5e ^  110 6e n  126 7e ~|
 15 0f SI   31 1f US   47 2f /  63 3f ?  79 4f O  95 5f _  111 6f o  127 7f DEL|
stderr:
status 0
```

### ascii --nope

```cu
(run (list "ascii" "--nope") "")
```
---
```output
Dec Hex    Dec Hex    Dec Hex  Dec Hex  Dec Hex  Dec Hex   Dec Hex   Dec Hex|
  0 00 NUL  16 10 DLE  32 20    48 30 0  64 40 @  80 50 P   96 60 `  112 70 p|
  1 01 SOH  17 11 DC1  33 21 !  49 31 1  65 41 A  81 51 Q   97 61 a  113 71 q|
  2 02 STX  18 12 DC2  34 22 "  50 32 2  66 42 B  82 52 R   98 62 b  114 72 r|
  3 03 ETX  19 13 DC3  35 23 #  51 33 3  67 43 C  83 53 S   99 63 c  115 73 s|
  4 04 EOT  20 14 DC4  36 24 $  52 34 4  68 44 D  84 54 T  100 64 d  116 74 t|
  5 05 ENQ  21 15 NAK  37 25 %  53 35 5  69 45 E  85 55 U  101 65 e  117 75 u|
  6 06 ACK  22 16 SYN  38 26 &  54 36 6  70 46 F  86 56 V  102 66 f  118 76 v|
  7 07 BEL  23 17 ETB  39 27 '  55 37 7  71 47 G  87 57 W  103 67 g  119 77 w|
  8 08 BS   24 18 CAN  40 28 (  56 38 8  72 48 H  88 58 X  104 68 h  120 78 x|
  9 09 HT   25 19 EM   41 29 )  57 39 9  73 49 I  89 59 Y  105 69 i  121 79 y|
 10 0a NL   26 1a SUB  42 2a *  58 3a :  74 4a J  90 5a Z  106 6a j  122 7a z|
 11 0b VT   27 1b ESC  43 2b +  59 3b ;  75 4b K  91 5b [  107 6b k  123 7b {|
 12 0c FF   28 1c FS   44 2c ,  60 3c <  76 4c L  92 5c \  108 6c l  124 7c ||
 13 0d CR   29 1d GS   45 2d -  61 3d =  77 4d M  93 5d ]  109 6d m  125 7d }|
 14 0e SO   30 1e RS   46 2e .  62 3e >  78 4e N  94 5e ^  110 6e n  126 7e ~|
 15 0f SI   31 1f US   47 2f /  63 3f ?  79 4f O  95 5f _  111 6f o  127 7f DEL|
stderr:
status 0
```

### uuidgen -~

```cu
(run (list "uuidgen" "-~") "")
```
---
```output
stderr:
uuidgen: unrecognized option: ~
Usage: uuidgen

Generate a random UUID
status 1
```

### uuidgen --nope

```cu
(run (list "uuidgen" "--nope") "")
```
---
```output
stderr:
uuidgen: unrecognized option: nope
Usage: uuidgen

Generate a random UUID
status 1
```

### uptime -~

```cu
(run (list "uptime" "-~") "")
```
---
```output
stderr:
uptime: unrecognized option: ~
Usage: uptime

Display the time since the last boot
status 1
```

### uptime --nope

```cu
(run (list "uptime" "--nope") "")
```
---
```output
stderr:
uptime: unrecognized option: nope
Usage: uptime

Display the time since the last boot
status 1
```

### free -~

```cu
(run (list "free" "-~") "")
```
---
```output
stderr:
Usage: free [-bkmgh]

Display free and used memory
status 1
```

### free --nope

```cu
(run (list "free" "--nope") "")
```
---
```output
stderr:
Usage: free [-bkmgh]

Display free and used memory
status 1
```

### ps -~

```cu
(run (list "ps" "-~") "")
```
---
```output
stderr:
ps: unrecognized option: ~
Usage: ps [-o COL1,COL2=HEADER]

Show list of processes

	-o COL1,COL2=HEADER	Select columns for display
status 1
```

### ps --nope

```cu
(run (list "ps" "--nope") "")
```
---
```output
stderr:
ps: unrecognized option: nope
Usage: ps [-o COL1,COL2=HEADER]

Show list of processes

	-o COL1,COL2=HEADER	Select columns for display
status 1
```

### ps -o

```cu
(run (list "ps" "-o") "")
```
---
```output
stderr:
ps: option requires an argument: o
Usage: ps [-o COL1,COL2=HEADER]

Show list of processes

	-o COL1,COL2=HEADER	Select columns for display
status 1
```

### pidof -~

```cu
(run (list "pidof" "-~") "")
```
---
```output
stderr:
pidof: unrecognized option: ~
Usage: pidof [-s] [-o PID] [NAME]...

List PIDs of all processes with names that match NAMEs

	-s	Show only one PID
	-o PID	Omit given pid
		Use %PPID to omit pid of pidof's parent
status 1
```

### pidof --nope

```cu
(run (list "pidof" "--nope") "")
```
---
```output
stderr:
pidof: unrecognized option: nope
Usage: pidof [-s] [-o PID] [NAME]...

List PIDs of all processes with names that match NAMEs

	-s	Show only one PID
	-o PID	Omit given pid
		Use %PPID to omit pid of pidof's parent
status 1
```

### pidof -o

```cu
(run (list "pidof" "-o") "")
```
---
```output
stderr:
pidof: option requires an argument: o
Usage: pidof [-s] [-o PID] [NAME]...

List PIDs of all processes with names that match NAMEs

	-s	Show only one PID
	-o PID	Omit given pid
		Use %PPID to omit pid of pidof's parent
status 1
```

### pgrep -~

```cu
(run (list "pgrep" "-~") "")
```
---
```output
stderr:
pgrep: unrecognized option: ~
Usage: pgrep [-flanovx] [-s SID|-P PPID|PATTERN]

Display process(es) selected by regex PATTERN

	-l	Show command name too
	-a	Show command line too
	-f	Match against entire command line
	-n	Show the newest process only
	-o	Show the oldest process only
	-v	Negate the match
	-x	Match whole name (not substring)
	-s	Match session ID (0 for current)
	-P	Match parent process ID
status 1
```

### pgrep --nope

```cu
(run (list "pgrep" "--nope") "")
```
---
```output
stderr:
pgrep: unrecognized option: nope
Usage: pgrep [-flanovx] [-s SID|-P PPID|PATTERN]

Display process(es) selected by regex PATTERN

	-l	Show command name too
	-a	Show command line too
	-f	Match against entire command line
	-n	Show the newest process only
	-o	Show the oldest process only
	-v	Negate the match
	-x	Match whole name (not substring)
	-s	Match session ID (0 for current)
	-P	Match parent process ID
status 1
```

### pgrep -P

```cu
(run (list "pgrep" "-P") "")
```
---
```output
stderr:
pgrep: option requires an argument: P
Usage: pgrep [-flanovx] [-s SID|-P PPID|PATTERN]

Display process(es) selected by regex PATTERN

	-l	Show command name too
	-a	Show command line too
	-f	Match against entire command line
	-n	Show the newest process only
	-o	Show the oldest process only
	-v	Negate the match
	-x	Match whole name (not substring)
	-s	Match session ID (0 for current)
	-P	Match parent process ID
status 1
```

### pkill -~

```cu
(run (list "pkill" "-~") "")
```
---
```output
stderr:
pkill: unrecognized option: ~
Usage: pkill [-l|-SIGNAL] [-xfvnoe] [-s SID|-P PPID|PATTERN]

Send signal to processes selected by regex PATTERN

	-l	List all signals
	-x	Match whole name (not substring)
	-f	Match against entire command line
	-s SID	Match session ID (0 for current)
	-P PPID	Match parent process ID
	-v	Negate the match
	-n	Signal the newest process only
	-o	Signal the oldest process only
	-e	Display name and PID of the process being killed
status 1
```

### pkill --nope

```cu
(run (list "pkill" "--nope") "")
```
---
```output
stderr:
pkill: unrecognized option: nope
Usage: pkill [-l|-SIGNAL] [-xfvnoe] [-s SID|-P PPID|PATTERN]

Send signal to processes selected by regex PATTERN

	-l	List all signals
	-x	Match whole name (not substring)
	-f	Match against entire command line
	-s SID	Match session ID (0 for current)
	-P PPID	Match parent process ID
	-v	Negate the match
	-n	Signal the newest process only
	-o	Signal the oldest process only
	-e	Display name and PID of the process being killed
status 1
```

### pkill -P

```cu
(run (list "pkill" "-P") "")
```
---
```output
stderr:
pkill: option requires an argument: P
Usage: pkill [-l|-SIGNAL] [-xfvnoe] [-s SID|-P PPID|PATTERN]

Send signal to processes selected by regex PATTERN

	-l	List all signals
	-x	Match whole name (not substring)
	-f	Match against entire command line
	-s SID	Match session ID (0 for current)
	-P PPID	Match parent process ID
	-v	Negate the match
	-n	Signal the newest process only
	-o	Signal the oldest process only
	-e	Display name and PID of the process being killed
status 1
```

### test -~

```cu
(run (list "test" "-~") "")
```
---
```output
stderr:
status 0
```

### test --nope

```cu
(run (list "test" "--nope") "")
```
---
```output
stderr:
status 0
```

### [ -~

```cu
(run (list "[" "-~") "")
```
---
```output
stderr:
[: missing ]
status 2
```

### [ --nope

```cu
(run (list "[" "--nope") "")
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
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-refuse")) (display "gone"))
```
---
    gone
