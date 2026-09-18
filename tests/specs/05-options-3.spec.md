# @weight 5

Option parity with busybox, tranche by tranche.  docs/options.md is the
generated scoreboard; each section here is one applet's busybox option
set, spec'd on what is deterministic -- names, order, shapes -- and
never on a clock or an inode.

## ls in columns

The layout is ls's, spelled in spaces: a column as wide as its widest
cell, two spaces between, the last cell of a row unpadded, the most
columns that fit.  Names are chosen so one is wider than a column's
share.

### fixtures

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-lc && mkdir -p /tmp/x-cu-lc/d && cd /tmp/x-cu-lc && for n in a1 a10 a2 b.txt big.log sub y.h z.c averyveryverylongname; do : > $n; done && ln -s b.txt link")) (def cu-lc (fn (_ argv) (do (sys-dup2 1 9) (let ((fd (file-open-write "/tmp/x-cu-lc/.cap"))) (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1) (file-close fd) (file-read-all "/tmp/x-cu-lc/.cap")))))) (display "made"))
```
---
    made

### -C fills down the columns, -x across the rows, within -w

```cu
(do (display (cu-run (list "ls" "-C" "-w" "40" "/tmp/x-cu-lc") "")) (display (cu-run (list "ls" "-x" "-w" "40" "/tmp/x-cu-lc") "")))
```
---
```output
a1   averyveryverylongname  d     y.h
a10  b.txt                  link  z.c
a2   big.log                sub
0a1                     a10    a2
averyveryverylongname  b.txt  big.log
d                      link   sub
y.h                    z.c
0
```

### a narrower width takes fewer columns, both ways

```cu
(do (display (cu-run (list "ls" "-C" "-w" "30" "/tmp/x-cu-lc") "")) (display (cu-run (list "ls" "-x" "-w" "30" "/tmp/x-cu-lc") "")))
```
---
```output
a1                     d
a10                    link
a2                     sub
averyveryverylongname  y.h
b.txt                  z.c
big.log
0a1     a10
a2     averyveryverylongname
b.txt  big.log
d      link
sub    y.h
z.c
0
```

### the -F marks count toward a cell's width

```cu
(display (cu-run (list "ls" "-C" "-F" "-w" "40" "/tmp/x-cu-lc") ""))
```
---
```output
a1   averyveryverylongname  d/     y.h
a10  b.txt                  link@  z.c
a2   big.log                sub
0
```

### too narrow for two columns is one; -w 0 is no limit

```cu
(do (display (cu-run (list "ls" "-C" "-w" "20" "/tmp/x-cu-lc") "")) (display (cu-run (list "ls" "-C" "-w" "0" "/tmp/x-cu-lc") "")))
```
---
```output
a1
a10
a2
averyveryverylongname
b.txt
big.log
d
link
sub
y.h
z.c
0a1  a10  a2  averyveryverylongname  b.txt  big.log  d  link  sub  y.h  z.c
0
```

### -1 and -l each turn columns off

```cu
(do (display (cu-run (list "ls" "-1" "-C" "-w" "40" "/tmp/x-cu-lc/a1" "/tmp/x-cu-lc/a2") "")) (display (substring (first (%cu-lines (cu-lc (list "ls" "-C" "-l" "-w" "40" "/tmp/x-cu-lc")))) 0 5)))
```
---
```output
/tmp/x-cu-lc/a1
/tmp/x-cu-lc/a2
0total
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-lc")) (display "clean"))
```
---
    clean

## stat -f -t, df -T

The numbers are a machine's; the specs judge order, shape and the
relations stat itself guarantees.

### fixtures

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-st && mkdir -p /tmp/x-cu-st && printf hello > /tmp/x-cu-st/f && chmod 644 /tmp/x-cu-st/f")) (def cu-sf (fn (_ argv) (do (sys-dup2 1 9) (let ((fd (file-open-write "/tmp/x-cu-st/.cap"))) (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1) (file-close fd) (file-read-all "/tmp/x-cu-st/.cap")))))) (def words (fn (_ s) (%cu-words-line (first (%cu-lines s))))) (display "made"))
```
---
    made

### -t is the sixteen fields of -c's terse order

```cu
(do (def t (cu-sf (list "stat" "-t" "/tmp/x-cu-st/f"))) (def c (cu-sf (list "stat" "-c" "%n %s %b %f %u %g %D %i %h %t %T %X %Y %Z %W %o" "/tmp/x-cu-st/f"))) (display (length (words t))) (newline) (display (if (string=? t c) "same" "differ")))
```
---
```output
16
same
```

### a regular file has no device type; %D is %d in hex; a birth precedes a modify

```cu
(do (def w (words (cu-sf (list "stat" "-c" "%t %T %r %R %d %D %W %Y %f" "/tmp/x-cu-st/f")))) (display (%cu-join-with (%cu-take w 4) " ")) (newline) (display (if (string=? (%cu-hexs (%cu-num-prefix (%cu-nth 4 w))) (%cu-nth 5 w)) "hex" "no")) (newline) (display (if (<= (%cu-num-prefix (%cu-nth 6 w)) (%cu-num-prefix (%cu-nth 7 w))) "ordered" "no")) (newline) (display (%cu-nth 8 w)))
```
---
```output
0 0 0 0
hex
ordered
81a4
```

### the default block names the device as major,minor and pads the inode

```cu
(do (def l3 (%cu-nth 2 (%cu-lines (cu-sf (list "stat" "/tmp/x-cu-st/f"))))) (display (substring l3 0 8)) (newline) (display (if (null? (filter (fn (_ w) (string=? w "Inode:")) (%cu-words-line l3))) "no" "Inode:")) (newline) (display (%cu-last (%cu-words-line l3))))
```
---
```output
Device: 
Inode:
1
```

### -f -t is the eleven fields of the filesystem, in stat's order

```cu
(do (def w (words (cu-sf (list "stat" "-f" "-t" "/tmp/x-cu-st")))) (display (length w)) (newline) (display (first w)) (newline) (display (if (> (%cu-num-prefix (%cu-nth 5 w)) 0) "block size" "no")) (newline) (display (if (>= (%cu-num-prefix (%cu-nth 7 w)) (%cu-num-prefix (%cu-nth 8 w))) "total>=free" "no")) (newline) (display (if (> (byte-len (%cu-nth 4 w)) 0) "typed" "no")))
```
---
```output
11
/tmp/x-cu-st
block size
total>=free
typed
```

### -f's block has stat's five lines, and a missing path is refused

```cu
(do (def ls (%cu-lines (cu-sf (list "stat" "-f" "/tmp/x-cu-st")))) (display (length ls)) (newline) (display (%cu-join-with (map (fn (_ l) (first (%cu-words-line l))) ls) "|")) (newline) (display (cu-run (list "stat" "-f" "/tmp/x-cu-st/nope") "")))
```
---
```output
5
File:|ID:|Block|Blocks:|Inodes:
1
```

### df -T puts the type stat -f names after the filesystem

```cu
(do (def out (cu-sf (list "df" "-T" "/tmp/x-cu-st"))) (def hdr (first (%cu-lines out))) (def row (%cu-nth 1 (%cu-lines out))) (display (%cu-join-with (%cu-take (%cu-words-line hdr) 3) " ")) (newline) (display (if (string=? (%cu-nth 1 (%cu-words-line row)) (first (words (cu-sf (list "stat" "-f" "-c" "%T" "/tmp/x-cu-st"))))) "same type" "differ")) (newline) (display (%cu-join-with (%cu-take (%cu-words-line (first (%cu-lines (cu-sf (list "df" "/tmp/x-cu-st"))))) 2) " ")))
```
---
```output
Filesystem Type 1K-blocks
same type
Filesystem 1K-blocks
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-st")) (display "clean"))
```
---
    clean

## df over the mount table

### fixtures

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-mt && mkdir -p /tmp/x-cu-mt/deep/er")) (def cu-mt (fn (_ argv) (do (sys-dup2 1 9) (let ((fd (file-open-write "/tmp/x-cu-mt/.cap"))) (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1) (file-close fd) (file-read-all "/tmp/x-cu-mt/.cap")))))) (def lines (fn (_ argv) (filter (fn (_ l) (> (byte-len l) 0)) (%cu-lines (cu-mt argv))))) (def last-word (fn (_ l) (%cu-last (%cu-words-line l)))) (display "made"))
```
---
    made

### a bare df lists the mounted filesystems, the root among them, named from and on

```cu
(do (def ls (lines (list "df"))) (display (%cu-join-with (%cu-words-line (first ls)) " ")) (newline) (display (if (null? (filter (fn (_ l) (string=? (last-word l) "/")) (rest ls))) "no root" "root listed")) (newline) (display (if (null? (filter (fn (_ l) (string=? (first (%cu-words-line l)) "Filesystem")) (rest ls))) "rows named" "unnamed")))
```
---
```output
Filesystem 1K-blocks Used Available Use% Mounted on
root listed
rows named
```

### -a lists at least as many, and no row of a plain df has a dash for its counts

```cu
(do (def plain (lines (list "df"))) (def all (lines (list "df" "-a"))) (display (if (>= (length all) (length plain)) "all>=plain" "fewer")) (newline) (display (if (null? (filter (fn (_ l) (string=? (%cu-nth 1 (%cu-words-line l)) "-")) (rest plain))) "no dashes" "dashes")))
```
---
```output
all>=plain
no dashes
```

### an operand is reported on the mount it sits on, not by its own path

```cu
(do (def row (%cu-nth 1 (lines (list "df" "/tmp/x-cu-mt/deep/er")))) (def on (last-word row)) (display (if (string=? on "/tmp/x-cu-mt/deep/er") "the path" "a mount point")) (newline) (display (if (string=? (substring (%cu-realpath-of "/tmp/x-cu-mt/deep/er") 0 (byte-len on)) on) "which contains it" "elsewhere")))
```
---
```output
a mount point
which contains it
```

### -P is the portable heading, -m and -B name their unit, -h its columns

```cu
(do (display (%cu-join-with (%cu-words-line (first (lines (list "df" "-P" "/tmp")))) " ")) (newline) (display (%cu-nth 1 (%cu-words-line (first (lines (list "df" "-m" "/tmp")))))) (newline) (display (%cu-nth 1 (%cu-words-line (first (lines (list "df" "-B" "2048" "/tmp")))))) (newline) (display (%cu-join-with (%cu-words-line (first (lines (list "df" "-h" "/tmp")))) " ")))
```
---
```output
Filesystem 1024-blocks Used Available Capacity Mounted on
1M-blocks
2K-blocks
Filesystem Size Used Avail Use% Mounted on
```

### a missing operand is named, and the others still print

```cu
(do (def out (lines (list "df" "/tmp/x-cu-mt/nope" "/tmp"))) (display (length out)) (newline) (display (cu-run (list "df" "/tmp/x-cu-mt/nope") "")))
```
---
```output
2
1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-mt")) (display "clean"))
```
---
    clean
