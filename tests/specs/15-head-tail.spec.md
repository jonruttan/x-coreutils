# @weight 2

head and tail: the counts -n and -c take, the bytes they print, and how they
read their operands.  The expected text is GNU head's and tail's for the same
input.

## the fixtures

### a scratch directory, and readers for what an applet printed

ht runs an applet with stdout and stderr each parked on a file, then shows
stdout, a bar where it ended, stderr and the status -- the bar is what shows
whether the output ended in a newline.  hn shows how many bytes stdout held.

```cu
(do (proc-run (list "/bin/sh" "-c" "chmod 644 /tmp/x-cu-ht/unread 2>/dev/null; rm -rf /tmp/x-cu-ht && mkdir -p /tmp/x-cu-ht/adir && cd /tmp/x-cu-ht && printf '1\\n2\\n3\\n4\\n5\\n' > five && printf '%05000d' 0 > big && printf 'u\\n' > unread && chmod 000 unread")) (def htp (fn (_ n) (string-append "/tmp/x-cu-ht/" n))) (def ht (fn (_ argv input) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((o (file-open-write (htp ".out"))) (e (file-open-write (htp ".err")))) (do (sys-dup2 o 1) (sys-dup2 e 2) (def ht-st (cu-run argv input)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close o) (file-close e) (display (file-read-all (htp ".out"))) (display "|\n") (display (file-read-all (htp ".err"))) (display "status ") (display ht-st) (newline)))))) (def hn (fn (_ label argv) (do (sys-dup2 1 9) (let ((o (file-open-write (htp ".out")))) (do (sys-dup2 o 1) (cu-run argv "") (sys-dup2 9 1) (file-close o) (display label) (display ": ") (display (byte-len (file-read-all (htp ".out")))) (newline)))))) (def five "1\n2\n3\n4\n5\n") (display "made"))
```
---
    made

## the counts

### head: a leading + is the count itself, and a leading - keeps all but the last lines

```cu
(do (ht (list "head" "-n" "+2") five) (ht (list "head" "-n" "-2") five) (ht (list "head" "-n" "-0") five) (ht (list "head" "-n" "-9") five))
```
---
```output
1
2
|
status 0
1
2
3
|
status 0
1
2
3
4
5
|
status 0
|
status 0
```

### head: bytes the same way

```cu
(do (ht (list "head" "-c" "+3") five) (ht (list "head" "-c" "-3") five))
```
---
```output
1
2|
status 0
1
2
3
4|
status 0
```

### tail: a leading + counts from the start, +0 as +1, and a leading - is the count itself

```cu
(do (ht (list "tail" "-n" "+2") five) (ht (list "tail" "-n" "+0") five) (ht (list "tail" "-n" "-2") five) (ht (list "tail" "-n" "+9") five))
```
---
```output
2
3
4
5
|
status 0
1
2
3
4
5
|
status 0
4
5
|
status 0
|
status 0
```

### tail: bytes the same way

```cu
(do (ht (list "tail" "-c" "+3") five) (ht (list "tail" "-c" "-3") five) (ht (list "tail" "-c" "+0") five))
```
---
```output
2
3
4
5
|
status 0

5
|
status 0
1
2
3
4
5
|
status 0
```

### a last line with no newline keeps having none

```cu
(do (ht (list "head" "-n" "2") "a\nb") (ht (list "head" "-n" "-1") "a\nb") (ht (list "tail" "-n" "1") "a\nb") (ht (list "tail" "-n" "+2") "a\nb"))
```
---
```output
a
b|
status 0
a
|
status 0
b|
status 0
b|
status 0
```

### a multiplier: b is 512, K 1024, kB 1000, KiB 1024, and alone it counts one of itself

A count too large to hold is more than any input has.

```cu
(do (hn "head -c 1b" (list "head" "-c" "1b" (htp "big"))) (hn "head -c 1k" (list "head" "-c" "1k" (htp "big"))) (hn "head -c 1K" (list "head" "-c" "1K" (htp "big"))) (hn "head -c 1kB" (list "head" "-c" "1kB" (htp "big"))) (hn "head -c 1KiB" (list "head" "-c" "1KiB" (htp "big"))) (hn "head -c K" (list "head" "-c" "K" (htp "big"))) (hn "head -c 2MB" (list "head" "-c" "2MB" (htp "big"))) (hn "head -c 99999999999999999999" (list "head" "-c" "99999999999999999999" (htp "big"))) (hn "tail -c 1b" (list "tail" "-c" "1b" (htp "big"))) (hn "tail -n +99999999999999999999" (list "tail" "-n" "+99999999999999999999" (htp "big"))))
```
---
```output
head -c 1b: 512
head -c 1k: 1024
head -c 1K: 1024
head -c 1kB: 1000
head -c 1KiB: 1024
head -c K: 1024
head -c 2MB: 5000
head -c 99999999999999999999: 5000
tail -c 1b: 512
tail -n +99999999999999999999: 0
```

### a value that is not a count is refused, naming what followed a leading -

```cu
(do (ht (list "head" "-n" "x") five) (ht (list "head" "-c" "1g") five) (ht (list "head" "-n" "") five) (ht (list "head" "-n" "-x") five) (ht (list "tail" "-n" "++2") five) (ht (list "tail" "-c" "1.5") five) (ht (list "tail" "-n" "3 ") five) (ht (list "tail" "-n" "+x") five))
```
---
```output
|
head: invalid number of lines: 'x'
status 1
|
head: invalid number of bytes: '1g'
status 1
|
head: invalid number of lines: ''
status 1
|
head: invalid number of lines: 'x'
status 1
|
tail: invalid number of lines: '++2'
status 1
|
tail: invalid number of bytes: '1.5'
status 1
|
tail: invalid number of lines: '3 '
status 1
|
tail: invalid number of lines: '+x'
status 1
```

## the inputs

### - is standard input, and its header says so

```cu
(ht (list "head" "-n" "1" "-" (htp "five")) "x\n")
```
---
```output
==> standard input <==
x

==> /tmp/x-cu-ht/five <==
1
|
status 0
```

### a file that cannot be opened is named with the reason, gets no header, and fails the run

The first header printed has no blank line before it, whichever operand it
belongs to.

```cu
(do (ht (list "head" "-n" "1" (htp "nope") (htp "five") (htp "five")) "") (ht (list "tail" "-n" "1" (htp "unread") (htp "five")) ""))
```
---
```output
==> /tmp/x-cu-ht/five <==
1

==> /tmp/x-cu-ht/five <==
1
|
head: cannot open '/tmp/x-cu-ht/nope' for reading: No such file or directory
status 1
==> /tmp/x-cu-ht/five <==
5
|
tail: cannot open '/tmp/x-cu-ht/unread' for reading: Permission denied
status 1
```

### a directory opens and cannot be read: its header, then the reason

```cu
(ht (list "head" (htp "adir") (htp "five")) "")
```
---
```output
==> /tmp/x-cu-ht/adir <==

==> /tmp/x-cu-ht/five <==
1
2
3
4
5
|
head: error reading '/tmp/x-cu-ht/adir': Is a directory
status 1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "chmod 644 /tmp/x-cu-ht/unread; rm -rf /tmp/x-cu-ht")) (display "clean"))
```
---
    clean
