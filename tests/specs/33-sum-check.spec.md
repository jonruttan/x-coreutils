# @weight 2

What the digests' `-c` says about each list it checks: a listed file that
will not read, the warnings that end each list, `-w`'s numbered lines,
what `-s` still says, and the lists that come to nothing.  The expected
text and statuses are GNU's for the same files, both streams in the order
they were written.

## the fixtures

### files, lists of their checksums, and a reader for both streams

`a` holds `a` and `b` holds `b`, a line each; `dd` is a directory.  `good`
lists `a` rightly, `bad` lists `b` wrongly, `miss` lists a file that is
not there, and `junk` is one line that is no checksum line; `all` is the
four in that order.  `dirl` lists `dd`, `twobad` is `bad` twice, `twojunk`
is `junk` twice then `good`, and `bjg` is a blank line, `junk`, then
`good`.

```cu
(do (def kh (fn (_ n) (string-append "/tmp/x-cu-sc/" n))) (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-sc && mkdir -p /tmp/x-cu-sc/dd && cd /tmp/x-cu-sc && printf 'a\\n' > a && printf 'b\\n' > b && printf '60b725f10c9c85c70d97880dfe8191b3  /tmp/x-cu-sc/a\\n' > good && printf '00000000000000000000000000000000  /tmp/x-cu-sc/b\\n' > bad && printf '60b725f10c9c85c70d97880dfe8191b3  /tmp/x-cu-sc/gone\\n' > miss && printf 'not a checksum line\\n' > junk && cat good bad miss junk > all && printf '60b725f10c9c85c70d97880dfe8191b3  /tmp/x-cu-sc/dd\\n' > dirl && cat bad bad > twobad && cat junk junk good > twojunk && { printf '\\n'; cat junk good; } > bjg")) (def ck (fn (_ argv input) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (kh ".out")))) (do (sys-dup2 oo 1) (sys-dup2 oo 2) (def ck-st (cu-run argv input)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (display (Str8 replace "/tmp/x-cu-sc/" "" (file-read-all (kh ".out")))) (display "status ") (display ck-st) (newline)))))) (display "made"))
```
---
    made

## what a list comes to

### each line is said in turn, and the list ends with its warnings

A listed file that is not there is said on stderr as well as FAILED.

```cu
(ck (list "md5sum" "-c" (kh "all")) "")
```
---
```output
a: OK
b: FAILED
md5sum: gone: No such file or directory
gone: FAILED open or read
md5sum: WARNING: 1 line is improperly formatted
md5sum: WARNING: 1 listed file could not be read
md5sum: WARNING: 1 computed checksum did NOT match
status 1
```

### more than one is counted in the plural

Lines that are not checksum lines do not move the status while any line
is one.

```cu
(do (ck (list "md5sum" "-c" (kh "twobad")) "") (ck (list "md5sum" "-c" (kh "twojunk")) ""))
```
---
```output
b: FAILED
b: FAILED
md5sum: WARNING: 2 computed checksums did NOT match
status 1
a: OK
md5sum: WARNING: 2 lines are improperly formatted
status 0
```

### a listed directory is said, and fails to open

```cu
(ck (list "md5sum" "-c" (kh "dirl")) "")
```
---
```output
md5sum: dd: Is a directory
dd: FAILED open or read
md5sum: WARNING: 1 listed file could not be read
status 1
```

## -w and -s

### -w names a line that is no checksum line by the list, its number and the algorithm

```cu
(ck (list "md5sum" "-c" "-w" (kh "all")) "")
```
---
```output
a: OK
b: FAILED
md5sum: gone: No such file or directory
gone: FAILED open or read
md5sum: all: 4: improperly formatted MD5 checksum line
md5sum: WARNING: 1 line is improperly formatted
md5sum: WARNING: 1 listed file could not be read
md5sum: WARNING: 1 computed checksum did NOT match
status 1
```

### a blank line is passed over, and still numbered

```cu
(ck (list "md5sum" "-c" "-w" (kh "bjg")) "")
```
---
```output
md5sum: bjg: 2: improperly formatted MD5 checksum line
a: OK
md5sum: WARNING: 1 line is improperly formatted
status 0
```

### each of the family names its own algorithm

```cu
(do (ck (list "sha1sum" "-c" "-w" (kh "junk")) "") (ck (list "sha256sum" "-c" "-w" (kh "junk")) "") (ck (list "sha512sum" "-c" "-w" (kh "junk")) ""))
```
---
```output
sha1sum: junk: 1: improperly formatted SHA1 checksum line
sha1sum: junk: no properly formatted checksum lines found
status 1
sha256sum: junk: 1: improperly formatted SHA256 checksum line
sha256sum: junk: no properly formatted checksum lines found
status 1
sha512sum: junk: 1: improperly formatted SHA512 checksum line
sha512sum: junk: no properly formatted checksum lines found
status 1
```

### -s drops the lines and the warnings, not what would not read

```cu
(ck (list "md5sum" "-c" "-s" (kh "all")) "")
```
---
```output
md5sum: gone: No such file or directory
status 1
```

## lists that come to nothing

### a list with no checksum line in it is said, under -s as well, and answers 1

```cu
(do (ck (list "md5sum" "-c" (kh "junk")) "") (ck (list "md5sum" "-c" "-s" (kh "junk")) ""))
```
---
```output
md5sum: junk: no properly formatted checksum lines found
status 1
md5sum: junk: no properly formatted checksum lines found
status 1
```

### standard input is named 'standard input'

```cu
(do (ck (list "md5sum" "-c") "not a checksum line\n") (ck (list "md5sum" "-c" "-w") "not a checksum line\nnot a checksum line\n60b725f10c9c85c70d97880dfe8191b3  /tmp/x-cu-sc/a\n"))
```
---
```output
md5sum: 'standard input': no properly formatted checksum lines found
status 1
md5sum: 'standard input': 1: improperly formatted MD5 checksum line
md5sum: 'standard input': 2: improperly formatted MD5 checksum line
a: OK
md5sum: WARNING: 2 lines are improperly formatted
status 0
```

### a list that is not there, and one that is a directory

```cu
(do (ck (list "md5sum" "-c" (kh "nosuchlist")) "") (ck (list "md5sum" "-c" (kh "dd")) ""))
```
---
```output
md5sum: nosuchlist: No such file or directory
status 1
md5sum: dd: read error
status 1
```

## more than one list

### each list ends with its own warnings

```cu
(ck (list "md5sum" "-c" (kh "bad") (kh "twojunk")) "")
```
---
```output
b: FAILED
md5sum: WARNING: 1 computed checksum did NOT match
a: OK
md5sum: WARNING: 2 lines are improperly formatted
status 1
```

### a list of nothing answers 1 though the next list is all OK

```cu
(ck (list "md5sum" "-c" (kh "junk") (kh "good")) "")
```
---
```output
md5sum: junk: no properly formatted checksum lines found
a: OK
status 1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-sc")) (display "clean"))
```
---
    clean
