# @weight 2

What the tools that read their files whole say when one will not read: a
file that is not there, and a directory, which opens and will not read.
Each says it in its own words; most print what the other files hold and
fail, and sort stops at the first and prints nothing.  The expected text and
statuses are GNU's for the same files, and BSD's for rev, uuencode and
uudecode, which have no GNU build here.

## the fixtures

### two files, a directory, and a reader for both streams

`a` holds `a TAB b` and `b` holds `c TAB d`; `dd` is a directory.  A tab
shows as `^I`.

```cu
(do (def rh (fn (_ n) (string-append "/tmp/x-cu-rd/" n))) (proc-run (list "/bin/sh" "-c" "chmod -R u+rwx /tmp/x-cu-rd 2>/dev/null; rm -rf /tmp/x-cu-rd && mkdir -p /tmp/x-cu-rd/dd /tmp/x-cu-rd/ro && cd /tmp/x-cu-rd && printf 'a\\tb\\n' > a && printf 'c\\td\\n' > b && printf 'begin 644 t\\n#86)C\\n`\\nend\\n' > u && chmod 555 ro")) (def seen (fn (_ s) (Str8 replace "\t" "^I" (Str8 replace "/tmp/x-cu-rd/" "" s)))) (def rd (fn (_ argv input) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (rh ".out"))) (ee (file-open-write (rh ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def rd-st (cu-run argv input)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (seen (file-read-all (rh ".out")))) (display (seen (file-read-all (rh ".err")))) (display "status ") (display rd-st) (newline)))))) (display "made"))
```
---
    made

## the readers that carry on

### a file that is not there is said, and the others are still printed

```cu
(do (rd (list "cat" (rh "a") (rh "nosuch") (rh "b")) "") (rd (list "nl" (rh "a") (rh "nosuch") (rh "b")) "") (rd (list "cut" "-f1" (rh "a") (rh "nosuch") (rh "b")) "") (rd (list "rev" (rh "a") (rh "nosuch") (rh "b")) ""))
```
---
```output
a^Ib
c^Id
cat: nosuch: No such file or directory
status 1
     1^Ia^Ib
     2^Ic^Id
nl: nosuch: No such file or directory
status 1
a
c
cut: nosuch: No such file or directory
status 1
b^Ia
d^Ic
rev: nosuch: No such file or directory
status 1
```

### and by fold, expand, unexpand, od and tac, which says it its own way

```cu
(do (rd (list "fold" (rh "a") (rh "nosuch") (rh "b")) "") (rd (list "expand" (rh "a") (rh "nosuch") (rh "b")) "") (rd (list "unexpand" (rh "a") (rh "nosuch") (rh "b")) "") (rd (list "od" (rh "a") (rh "nosuch") (rh "b")) "") (rd (list "tac" (rh "a") (rh "nosuch")) ""))
```
---
```output
a^Ib
c^Id
fold: nosuch: No such file or directory
status 1
a       b
c       d
expand: nosuch: No such file or directory
status 1
a^Ib
c^Id
unexpand: nosuch: No such file or directory
status 1
0000000 004541 005142 004543 005144
0000010
od: nosuch: No such file or directory
status 1
a^Ib
tac: failed to open 'nosuch' for reading: No such file or directory
status 1
```

### a directory opens and will not read, and is said so

```cu
(do (rd (list "cat" (rh "a") (rh "dd") (rh "b")) "") (rd (list "cut" "-f1" (rh "a") (rh "dd")) "") (rd (list "od" (rh "a") (rh "dd") (rh "b")) "") (rd (list "tac" (rh "a") (rh "dd")) ""))
```
---
```output
a^Ib
c^Id
cat: dd: Is a directory
status 1
a
cut: dd: Is a directory
status 1
0000000 004541 005142 004543 005144
0000010
od: dd: Is a directory
status 1
a^Ib
tac: dd: read error: Is a directory
status 1
```

## the readers that stop

### sort reads nothing past the first file it cannot read, prints nothing, and fails as sort fails

```cu
(do (rd (list "sort" (rh "a") (rh "nosuch") (rh "b")) "") (rd (list "sort" (rh "a") (rh "dd") (rh "b")) "") (rd (list "sort" (rh "nosuch") (rh "dd")) ""))
```
---
```output
sort: cannot read: nosuch: No such file or directory
status 2
sort: read failed: dd: Is a directory
status 2
sort: cannot read: nosuch: No such file or directory
status 2
```

### shuf, base64 and uniq read one file, and print nothing without it

```cu
(do (rd (list "shuf" (rh "nosuch")) "") (rd (list "shuf" (rh "dd")) "") (rd (list "base64" (rh "nosuch")) "") (rd (list "base64" (rh "dd")) "") (rd (list "uniq" (rh "nosuch")) "") (rd (list "uniq" (rh "dd")) ""))
```
---
```output
shuf: nosuch: No such file or directory
status 1
shuf: read error: Is a directory
status 1
base64: nosuch: No such file or directory
status 1
base64: read error: Is a directory
status 1
uniq: nosuch: No such file or directory
status 1
uniq: error reading 'dd': Is a directory
status 1
```

### so do uuencode and uudecode

```cu
(do (rd (list "uuencode" (rh "nosuch") "name") "") (rd (list "uudecode" (rh "nosuch")) ""))
```
---
```output
uuencode: nosuch: No such file or directory
status 1
uudecode: nosuch: No such file or directory
status 1
```

### uudecode names its input when it cannot write -o

```cu
(do (rd (list "uudecode" "-o" (rh "ro/x") (rh "u")) "") (rd (list "uudecode" "-o" (rh "ro/x")) "begin 644 t\n#86)C\n`\nend\n"))
```
---
```output
uudecode: u: ro/x: Permission denied
status 1
uudecode: stdin: ro/x: Permission denied
status 1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "chmod -R u+rwx /tmp/x-cu-rd; rm -rf /tmp/x-cu-rd")) (display "clean"))
```
---
    clean
