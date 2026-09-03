# @weight 3

Parity with busybox's coreutils set: the digests, the encodings, the
line tools and the file-and-process half.  Every digest expectation
below is the system tool's own output for the same bytes; the clock-
and machine-shaped ones assert shape, not value.

## the digests

### md5sum matches the reference vectors

```cu
(do (display (cu-run (list "md5sum") "")) (newline) (display (cu-run (list "md5sum") "hello world\n")))
```
---
```output
d41d8cd98f00b204e9800998ecf8427e  -
0
6f5902ac237024bdd0c176cb93063dc4  -
0
```

### sha1sum matches the reference vectors

```cu
(do (display (cu-run (list "sha1sum") "")) (newline) (display (cu-run (list "sha1sum") "hello world\n")))
```
---
```output
da39a3ee5e6b4b0d3255bfef95601890afd80709  -
0
22596363b3de40b06f981fb85d82312e8c0ed511  -
0
```

### md5 and sha1 cross the 64-byte block boundary

```cu
(do (display (cu-run (list "md5sum") "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz")) (newline) (display (cu-run (list "sha1sum") "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz")))
```
---
```output
15061fc3840896c5299a5b8cc1cf5b5f  -
0
f2090afe4177d6f288072a474804327d0f481ada  -
0
```

### cksum is the POSIX CRC-32, with the byte count

```cu
(do (display (cu-run (list "cksum") "")) (newline) (display (cu-run (list "cksum") "hello world\n")))
```
---
```output
4294967295 0
0
3733384285 12
0
```

### sum is BSD by default and System V under -s

```cu
(do (display (cu-run (list "sum") "hello world\n")) (newline) (display (cu-run (list "sum" "-s") "hello world\n")))
```
---
```output
03762     1
0
1126 1
0
```

## the encodings

### base64 round-trips, and pads

```cu
(do (display (cu-run (list "base64") "hello world")) (newline) (display (cu-run (list "base64" "-d") "aGVsbG8gd29ybGQ=\n")) (newline) (display (cu-run (list "base64") "hi")))
```
---
```output
aGVsbG8gd29ybGQ=
0
hello world0
aGk=
0
```

### base64 wraps at 76 columns

```cu
(display (cu-run (list "base64") "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
```
---
```output
YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFh
YWFh
0
```

### od dumps octal shorts by default and bytes under -c

```cu
(do (display (cu-run (list "od" "-c") "abc\n")) (newline) (display (cu-run (list "od" "-An" "-tx1") "abc")))
```
---
```output
0000000   a   b   c  \n
0000004
0
 61 62 63
0
```

### od collapses a repeated line to a star

```cu
(display (cu-run (list "od" "-c") "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
```
---
```output
0000000   a   a   a   a   a   a   a   a   a   a   a   a   a   a   a   a
*
0000040   a   a   a   a
0000044
0
```

### uuencode writes the historical alphabet; uudecode reads it back

```cu
(do (display (cu-run (list "uuencode" "t") "abc\n")) (newline) (display (cu-run (list "uudecode") "begin 644 t\n$86)C\"@``\n`\nend\n")))
```
---
```output
begin 644 t
$86)C"@``
`
end
0
abc
0
```

## the line tools

### factor walks the primes

```cu
(display (cu-run (list "factor" "360" "97" "1") ""))
```
---
```output
360: 2 2 2 3 3 5
97: 97
1:
0
```

### expand turns tabs into stops; unexpand turns the leading run back

```cu
(do (display (cu-run (list "expand") "a\tb\n")) (newline) (display (cu-run (list "expand" "-t" "4") "a\tb\n")) (newline) (display (cu-run (list "unexpand") "        deep\n")))
```
---
```output
a       b
0
a   b
0
	deep
0
```

### dos2unix strips the carriage returns

```cu
(display (cu-run (list "dos2unix") "a\r\nb\r\n"))
```
---
```output
a
b
0
```

### unix2dos and dos2unix rewrite a named file in place

The carriage returns are counted, not printed: a spec cannot show one.

```cu
(do (file-write-all "/tmp/x-cu-crlf" "a\nb\n") (cu-run (list "unix2dos" "/tmp/x-cu-crlf") "") (display (byte-len (file-read-all "/tmp/x-cu-crlf"))) (newline) (cu-run (list "dos2unix" "/tmp/x-cu-crlf") "") (display (byte-len (file-read-all "/tmp/x-cu-crlf"))) (file-unlink "/tmp/x-cu-crlf"))
```
---
```output
6
4
```

### expr does arithmetic, comparison and the string operators

```cu
(do (display (cu-run (list "expr" "2" "+" "3" "*" "4") "")) (display (cu-run (list "expr" "10" "-" "4" "/" "2") "")) (display (cu-run (list "expr" "3" "<" "5") "")) (display (cu-run (list "expr" "length" "hello") "")) (display (cu-run (list "expr" "substr" "hello" "2" "3") "")) (display (cu-run (list "expr" "index" "hello" "l") "")))
```
---
```output
14
08
01
05
0ell
03
0
```

### expr matches an anchored expression, and captures what it groups

```cu
(do (display (cu-run (list "expr" "abc123" ":" "[a-z]*") "")) (display (cu-run (list "expr" "abc123" ":" "\\([a-z]*\\)") "")) (display (cu-run (list "expr" "hello.txt" ":" "\\(.*\\)\\.txt") "")) (display (cu-run (list "expr" "abcabcx" ":" "\\(abc\\)*x") "")))
```
---
```output
3
0abc
0hello
0abc
0
```

### shuf of one line is that line; -e takes its operands

```cu
(do (display (cu-run (list "shuf") "only\n")) (newline) (display (cu-run (list "shuf" "-e" "solo") "")) (newline) (display (cu-run (list "shuf" "-n" "0") "1\n2\n3\n")))
```
---
```output
only
0
solo
0
0
```

## the file and process half

### fixtures

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-par && mkdir -p /tmp/x-cu-par")) (file-write-all "/tmp/x-cu-par/f" "0123456789") (display "made"))
```
---
    made

### stat -c reads the fields the wide decode carries

```cu
(display (cu-run (list "stat" "-c" "%n %s %F" "/tmp/x-cu-par/f") ""))
```
---
```output
/tmp/x-cu-par/f 10 regular file
0
```

### stat refuses a path that is not there

```cu
(display (cu-run (list "stat" "-c" "%s" "/tmp/x-cu-par/gone") ""))
```
---
    1

### truncate cuts, and extends

```cu
(do (cu-run (list "truncate" "-s" "4" "/tmp/x-cu-par/f") "") (display (file-read-all "/tmp/x-cu-par/f")) (newline) (cu-run (list "truncate" "-s" "6" "/tmp/x-cu-par/f") "") (display (cu-run (list "stat" "-c" "%s" "/tmp/x-cu-par/f") "")))
```
---
```output
0123
6
0
```

### dd copies a bounded slice and reports its records

```cu
(display (cu-run (list "dd" "bs=4" "count=2" "status=none") "abcdefghij"))
```
---
    abcdefgh0

### dd skips and seeks through a file

```cu
(do (file-write-all "/tmp/x-cu-par/src" "abcdefghij") (cu-run (list "dd" "if=/tmp/x-cu-par/src" "of=/tmp/x-cu-par/dst" "bs=2" "skip=1" "count=2" "status=none") "") (display (file-read-all "/tmp/x-cu-par/dst")))
```
---
    cdef

### split cuts by lines, suffixing aa ab ac

```cu
(do (cu-run (list "split" "-l" "2" "-" "/tmp/x-cu-par/s") "a\nb\nc\nd\ne\n") (display (file-read-all "/tmp/x-cu-par/saa")) (display (file-read-all "/tmp/x-cu-par/sac")))
```
---
```output
a
b
e
```

### unlink removes one name, and refuses a missing one

```cu
(do (file-write-all "/tmp/x-cu-par/gonesoon" "x") (display (cu-run (list "unlink" "/tmp/x-cu-par/gonesoon") "")) (display (if (file-exists? "/tmp/x-cu-par/gonesoon") "still" "gone")) (newline) (display (cu-run (list "unlink" "/tmp/x-cu-par/never") "")))
```
---
```output
0gone
1
```

### shred overwrites the bytes and -u takes the name away

```cu
(do (file-write-all "/tmp/x-cu-par/secret" "confidential") (cu-run (list "shred" "-n" "1" "/tmp/x-cu-par/secret") "") (display (if (string=? (file-read-all "/tmp/x-cu-par/secret") "confidential") "intact" "overwritten")) (newline) (cu-run (list "shred" "-n" "1" "-u" "/tmp/x-cu-par/secret") "") (display (if (file-exists? "/tmp/x-cu-par/secret") "still" "gone")))
```
---
```output
overwritten
gone
```

### du reports 1024-byte blocks; a path that is not there is zero

```cu
(display (cu-run (list "du" "-s" "/tmp/x-cu-par/nope") ""))
```
---
```output
0	/tmp/x-cu-par/nope
0
```

### [[ is test with the doubled closer

```cu
(do (display (cu-run (list "[[" "-d" "/tmp/x-cu-par" "]]") "")) (display (cu-run (list "[[" "1" "-lt" "2" "]]") "")) (display (cu-run (list "[[" "-d" "/tmp/x-cu-par") "")))
```
---
    002

### usleep returns; timeout kills a command that overstays

```cu
(do (display (cu-run (list "usleep" "1000") "")) (display (cu-run (list "timeout" "1" "/bin/sleep" "5") "")) (display (cu-run (list "timeout" "5" "/usr/bin/true") "")))
```
---
    01240

### the option guard reaches the new applets too

```cu
(do (display (cu-run (list "base64" "-Z") "")) (display (cu-run (list "du" "-Q") "")))
```
---
    22

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-par")) (display "clean"))
```
---
    clean
