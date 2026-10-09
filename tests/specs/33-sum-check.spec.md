# @weight 2

What the digests' `-c` says about each list it checks: the line for each
listed file, the warning that ends a list where anything failed, `-w`'s
`invalid format`, what `-s` still says, the lists that come to nothing, and
what `-s` and `-w` do without `-c`.  The expected text and statuses are
busybox's for the same files: standard output, then standard error, then
the status.

## the fixtures

### files, lists of their checksums, and a reader for both streams

`a` holds `a` and `b` holds `b`, a line each; `dd` is a directory.  `good`
lists `a` rightly, `bad` lists `b` wrongly, `miss` lists a file that is
not there, and `junk` is one line that is no checksum line; `all` is the
four in that order.  `dirl` lists `dd`, `twobad` is `bad` twice, `twojunk`
is `junk` twice then `good`, `bjg` is a blank line, `junk`, then `good`,
and `none` is empty.  `seps` spells its digests in upper case, or with one
space, or with a star before the name.

```cu
(do (def kh (fn (_ n) (string-append "/tmp/x-cu-sc/" n))) (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-sc && mkdir -p /tmp/x-cu-sc/dd && cd /tmp/x-cu-sc && printf 'a\\n' > a && printf 'b\\n' > b && printf '60b725f10c9c85c70d97880dfe8191b3  /tmp/x-cu-sc/a\\n' > good && printf '00000000000000000000000000000000  /tmp/x-cu-sc/b\\n' > bad && printf '60b725f10c9c85c70d97880dfe8191b3  /tmp/x-cu-sc/gone\\n' > miss && printf 'not-a-checksum-line\\n' > junk && cat good bad miss junk > all && printf '60b725f10c9c85c70d97880dfe8191b3  /tmp/x-cu-sc/dd\\n' > dirl && cat bad bad > twobad && cat junk junk good > twojunk && { printf '\\n'; cat junk good; } > bjg && : > none && printf '60B725F10C9C85C70D97880DFE8191B3 /tmp/x-cu-sc/a\\n3b5d5c3712955042212316173ccf37be */tmp/x-cu-sc/b\\n' > seps")) (def seen (fn (_ s) (Str8 replace "/tmp/x-cu-sc/" "" s))) (def ck (fn (_ argv input) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (kh ".out"))) (ee (file-open-write (kh ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def ck-st (cu-run argv input)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (seen (file-read-all (kh ".out")))) (display (seen (file-read-all (kh ".err")))) (display "status ") (display ck-st) (newline)))))) (display "made"))
```
---
    made

## what a list comes to

### each line is said in turn, and the list ends with how many failed

A listed file that is not there is said on stderr as well as FAILED, and a
line that is no checksum line counts as one that failed.

```cu
(ck (list "md5sum" "-c" (kh "all")) "")
```
---
```output
a: OK
b: FAILED
gone: FAILED
md5sum: can't open 'gone': No such file or directory
md5sum: WARNING: 3 of 4 computed checksums did NOT match
status 1
```

### the count is of the list's lines, and a line that is no checksum line moves the status

```cu
(do (ck (list "md5sum" "-c" (kh "twobad")) "") (ck (list "md5sum" "-c" (kh "twojunk")) ""))
```
---
```output
b: FAILED
b: FAILED
md5sum: WARNING: 2 of 2 computed checksums did NOT match
status 1
a: OK
md5sum: WARNING: 2 of 3 computed checksums did NOT match
status 1
```

### a listed directory opens and will not read

```cu
(ck (list "md5sum" "-c" (kh "dirl")) "")
```
---
```output
dd: FAILED
md5sum: can't read 'dd': Is a directory
md5sum: WARNING: 1 of 1 computed checksums did NOT match
status 1
```

### upper case, one space and a star all read

```cu
(ck (list "md5sum" "-c" (kh "seps")) "")
```
---
```output
a: OK
b: OK
status 0
```

## -w and -s

### -w says invalid format for a line that is no checksum line

```cu
(ck (list "md5sum" "-c" "-w" (kh "all")) "")
```
---
```output
a: OK
b: FAILED
gone: FAILED
md5sum: can't open 'gone': No such file or directory
md5sum: invalid format
md5sum: WARNING: 3 of 4 computed checksums did NOT match
status 1
```

### a blank line is no checksum line either

```cu
(ck (list "md5sum" "-c" "-w" (kh "bjg")) "")
```
---
```output
a: OK
md5sum: invalid format
md5sum: invalid format
md5sum: WARNING: 2 of 3 computed checksums did NOT match
status 1
```

### every tool says it the same way

```cu
(do (ck (list "sha1sum" "-c" "-w" (kh "junk")) "") (ck (list "sha256sum" "-c" "-w" (kh "junk")) "") (ck (list "sha512sum" "-c" "-w" (kh "junk")) ""))
```
---
```output
sha1sum: invalid format
sha1sum: WARNING: 1 of 1 computed checksums did NOT match
status 1
sha256sum: invalid format
sha256sum: WARNING: 1 of 1 computed checksums did NOT match
status 1
sha512sum: invalid format
sha512sum: WARNING: 1 of 1 computed checksums did NOT match
status 1
```

### -s drops the lines and the warning, not what would not read nor -w's line

```cu
(do (ck (list "md5sum" "-c" "-s" (kh "all")) "") (ck (list "md5sum" "-c" "-s" "-w" (kh "all")) "") (ck (list "md5sum" "-c" "-s" (kh "good")) ""))
```
---
```output
md5sum: can't open 'gone': No such file or directory
status 1
md5sum: can't open 'gone': No such file or directory
md5sum: invalid format
status 1
status 0
```

### without -c, -s and -w are refused with the usage text

```cu
(do (ck (list "md5sum" "-s" (kh "a")) "") (ck (list "md5sum" "-w" (kh "a")) ""))
```
---
```output
Usage: md5sum [-c[sw]] [FILE]...

Print or check MD5 checksums

	-c	Check sums against list in FILEs
	-s	Don't output anything, status code shows success
	-w	Warn about improperly formatted checksum lines
status 1
Usage: md5sum [-c[sw]] [FILE]...

Print or check MD5 checksums

	-c	Check sums against list in FILEs
	-s	Don't output anything, status code shows success
	-w	Warn about improperly formatted checksum lines
status 1
```

## lists that come to nothing

### a list of no lines is said, under -s as well, and answers 1

```cu
(do (ck (list "md5sum" "-c" (kh "none")) "") (ck (list "md5sum" "-c" "-s" (kh "none")) ""))
```
---
```output
md5sum: none: no checksum lines found
status 1
md5sum: none: no checksum lines found
status 1
```

### standard input is named -

```cu
(do (ck (list "md5sum" "-c") "") (ck (list "md5sum" "-c" "-w") "not-a-checksum-line\nnot-a-checksum-line\n60b725f10c9c85c70d97880dfe8191b3  /tmp/x-cu-sc/a\n"))
```
---
```output
md5sum: -: no checksum lines found
status 1
a: OK
md5sum: invalid format
md5sum: invalid format
md5sum: WARNING: 2 of 3 computed checksums did NOT match
status 1
```

### a list that is not there, and one that is a directory

```cu
(do (ck (list "md5sum" "-c" (kh "nosuchlist")) "") (ck (list "md5sum" "-c" (kh "dd")) ""))
```
---
```output
md5sum: nosuchlist: No such file or directory
status 1
md5sum: dd: no checksum lines found
status 1
```

## more than one list

### a list that is not there ends the run

```cu
(ck (list "md5sum" "-c" (kh "good") (kh "nosuchlist") (kh "good")) "")
```
---
```output
a: OK
md5sum: nosuchlist: No such file or directory
status 1
```

### each list ends with its own warning

```cu
(ck (list "md5sum" "-c" (kh "bad") (kh "twojunk")) "")
```
---
```output
b: FAILED
a: OK
md5sum: WARNING: 1 of 1 computed checksums did NOT match
md5sum: WARNING: 2 of 3 computed checksums did NOT match
status 1
```

### a list of nothing answers 1 though the next list is all OK

```cu
(ck (list "md5sum" "-c" (kh "none") (kh "good")) "")
```
---
```output
a: OK
md5sum: none: no checksum lines found
status 1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-sc")) (display "clean"))
```
---
    clean
