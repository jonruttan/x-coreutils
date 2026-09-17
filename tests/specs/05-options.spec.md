# @weight 5

Option parity with busybox, tranche by tranche.  docs/options.md is the
generated scoreboard; each section here is one applet's busybox option
set, spec'd on what is deterministic -- names, order, shapes -- and
never on a clock or an inode.

## ls

### fixtures

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-ls && mkdir -p /tmp/x-cu-ls/sub && cd /tmp/x-cu-ls && printf abc > b.txt && printf %05000d 0 > big.log && chmod +x big.log && : > .hidden && ln -s b.txt link && : > sub/inner && : > a10 && : > a2 && : > a1 && : > z.c && : > y.h")) (def cu-out (fn (_ argv) (do (sys-dup2 1 9) (let ((fd (file-open-write "/tmp/x-cu-ls/.cap"))) (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1) (file-close fd) (file-read-all "/tmp/x-cu-ls/.cap")))))) (display "made"))
```
---
    made

### the plain listing hides dotfiles; -A shows them; -a adds . and ..

```cu
(do (display (cu-run (list "ls" "/tmp/x-cu-ls") "")) (display (cu-run (list "ls" "-A" "/tmp/x-cu-ls") "")) (display (cu-run (list "ls" "-a" "/tmp/x-cu-ls") "")))
```
---
```output
a1
a10
a2
b.txt
big.log
link
sub
y.h
z.c
0.hidden
a1
a10
a2
b.txt
big.log
link
sub
y.h
z.c
0.
..
.hidden
a1
a10
a2
b.txt
big.log
link
sub
y.h
z.c
0
```

### -S orders by size, -r reverses, -v is version order, -X by extension

```cu
(do (display (cu-run (list "ls" "-S" "/tmp/x-cu-ls") "")) (display (cu-run (list "ls" "-r" "/tmp/x-cu-ls") "")) (display (cu-run (list "ls" "-v" "/tmp/x-cu-ls") "")) (display (cu-run (list "ls" "-X" "/tmp/x-cu-ls") "")))
```
---
```output
big.log
sub
link
b.txt
a1
a10
a2
y.h
z.c
0z.c
y.h
sub
link
big.log
b.txt
a2
a10
a1
0a1
a2
a10
b.txt
big.log
link
sub
y.h
z.c
0a1
a10
a2
link
sub
z.c
y.h
big.log
b.txt
0
```

### -F and -p mark the kind; -d lists the operand itself; -R descends with headers

```cu
(do (display (cu-run (list "ls" "-F" "/tmp/x-cu-ls") "")) (display (cu-run (list "ls" "-d" "/tmp/x-cu-ls") "")) (display (cu-run (list "ls" "-R" "/tmp/x-cu-ls/sub") "")))
```
---
```output
a1
a10
a2
b.txt
big.log*
link@
sub/
y.h
z.c
0/tmp/x-cu-ls
0/tmp/x-cu-ls/sub:
inner
0
```

### -l opens with total and the mode, and a link shows its target

The columns between the mode and the name are a machine's facts -- links,
ids, a clock -- so the line is judged by its ends.

```cu
(do (def out (cu-out (list "ls" "-l" "/tmp/x-cu-ls"))) (def ls (%cu-lines out)) (display (substring (first ls) 0 6)) (newline) (display (substring (first (rest ls)) 0 10)) (newline) (def link-line (first (filter (fn (_ l) (> (byte-len l) 0)) (filter (fn (_ l) (string=? (%cu-last (%cu-words-line l)) "b.txt")) (filter (fn (_ l) (= (byte-at l 0) 108)) ls))))) (display (%cu-join-with (%cu-nthrest (- (length (%cu-words-line link-line)) 3) (%cu-words-line link-line)) " ")))
```
---
```output
total 
-rw-r--r--
link -> b.txt
```

### -i and -s prefix every line; -h abbreviates a size; a missing operand is loud

```cu
(do (def il (first (%cu-lines (cu-out (list "ls" "-i" "/tmp/x-cu-ls/b.txt"))))) (display (if (> (%cu-num-prefix il) 0) "inode" "none")) (newline) (def hl (first (%cu-lines (cu-out (list "ls" "-lh" "/tmp/x-cu-ls/big.log"))))) (display (if (null? (filter (fn (_ w) (string=? w "4.9K")) (%cu-words-line hl))) "bytes" "4.9K")) (newline) (display (cu-run (list "ls" "/tmp/x-cu-ls/nope") "")))
```
---
```output
inode
4.9K
1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-ls")) (display "clean"))
```
---
    clean

## cat

### -n numbers every line, -b only the ones with something on them

```cu
(do (display (cu-run (list "cat" "-n") "a\nb\n")) (display (cu-run (list "cat" "-b") "\nx\n")))
```
---
```output
     1	a
     2	b
0
     1	x
0
```

### -A spells the tab, the newline and the unprintables

```cu
(do (display (cu-run (list "cat" "-A") "a\tb\n")) (display (cu-run (list "cat" "-e") "p\n")) (display (cu-run (list "cat" "-t") "q\tr\n")))
```
---
```output
a^Ib$
0p$
0q^Ir
0
```

## the file movers

### fixtures

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-fs && mkdir -p /tmp/x-cu-fs/d/sub && cd /tmp/x-cu-fs && printf x > d/one && printf y > d/sub/two && printf body > f.txt && chmod 741 f.txt")) (display "made"))
```
---
    made

### cp -r copies a tree; rm -r removes one

`rm -r` was listed by the option guard and did NOTHING: the flag was
accepted, unlink was called on a directory, and it failed.

```cu
(do (display (cu-run (list "cp" "-r" "/tmp/x-cu-fs/d" "/tmp/x-cu-fs/copy") "")) (display (file-read-all "/tmp/x-cu-fs/copy/sub/two")) (newline) (display (cu-run (list "rm" "-r" "/tmp/x-cu-fs/copy") "")) (display (if (file-exists? "/tmp/x-cu-fs/copy") "still" "gone")))
```
---
```output
0y
0gone
```

### cp without -r refuses a directory, and rm without -r refuses one

```cu
(do (display (cu-run (list "cp" "/tmp/x-cu-fs/d" "/tmp/x-cu-fs/nope") "")) (display (cu-run (list "rm" "/tmp/x-cu-fs/d") "")) (display (if (file-exists? "/tmp/x-cu-fs/d") "intact" "gone")))
```
---
    11intact

### cp -p keeps the mode; a plain copy takes the default

```cu
(do (cu-run (list "cp" "-p" "/tmp/x-cu-fs/f.txt" "/tmp/x-cu-fs/kept") "") (display (cu-run (list "stat" "-c" "%a" "/tmp/x-cu-fs/kept") "")) (cu-run (list "cp" "/tmp/x-cu-fs/f.txt" "/tmp/x-cu-fs/plain") "") (display (cu-run (list "stat" "-c" "%a" "/tmp/x-cu-fs/plain") "")))
```
---
```output
741
0644
0
```

### cp carries bytes a string cannot hold

read-all + write-all ended the copy at the first NUL; the fd-level door
does not.

```cu
(do (proc-run (list "/bin/sh" "-c" "printf 'A\\000B\\000C' > /tmp/x-cu-fs/bin.dat")) (cu-run (list "cp" "/tmp/x-cu-fs/bin.dat" "/tmp/x-cu-fs/bin2.dat") "") (display (cu-run (list "stat" "-c" "%s" "/tmp/x-cu-fs/bin2.dat") "")) (display (cu-run (list "cmp" "/tmp/x-cu-fs/bin.dat" "/tmp/x-cu-fs/bin2.dat") "")))
```
---
```output
5
00
```

### cp -u keeps a target that is not older; mv -n keeps one that exists

```cu
(do (file-write-all "/tmp/x-cu-fs/old" "old") (file-write-all "/tmp/x-cu-fs/new" "new") (cu-run (list "cp" "-u" "/tmp/x-cu-fs/old" "/tmp/x-cu-fs/new") "") (display (file-read-all "/tmp/x-cu-fs/new")) (newline) (cu-run (list "mv" "-n" "/tmp/x-cu-fs/old" "/tmp/x-cu-fs/new") "") (display (file-read-all "/tmp/x-cu-fs/new")))
```
---
```output
new
new
```

### cp -T will not unmake a directory to take its name

```cu
(display (cu-run (list "cp" "-T" "/tmp/x-cu-fs/f.txt" "/tmp/x-cu-fs/d") ""))
```
---
    1

### mkdir -m sets the mode; rmdir -p walks the parents up

```cu
(do (cu-run (list "mkdir" "-m" "700" "/tmp/x-cu-fs/m") "") (display (cu-run (list "stat" "-c" "%a" "/tmp/x-cu-fs/m") "")) (cu-run (list "mkdir" "-p" "/tmp/x-cu-fs/p/q/r") "") (cu-run (list "rmdir" "-p" "/tmp/x-cu-fs/p/q/r") "") (display (if (file-exists? "/tmp/x-cu-fs/p") "still" "gone")))
```
---
```output
700
0gone
```

### ln -sfv says what it linked, and -b keeps what it displaced

```cu
(do (file-write-all "/tmp/x-cu-fs/taken" "older") (display (cu-run (list "ln" "-sfv" "/tmp/x-cu-fs/f.txt" "/tmp/x-cu-fs/lk") "")) (cu-run (list "ln" "-sb" "/tmp/x-cu-fs/f.txt" "/tmp/x-cu-fs/taken") "") (display (file-read-all "/tmp/x-cu-fs/taken~")))
```
---
```output
'/tmp/x-cu-fs/lk' -> '/tmp/x-cu-fs/f.txt'
0older
```

### rm -v names what it removed, and -f forgives what was never there

```cu
(do (file-write-all "/tmp/x-cu-fs/gone" "x") (display (cu-run (list "rm" "-v" "/tmp/x-cu-fs/gone") "")) (display (cu-run (list "rm" "-f" "/tmp/x-cu-fs/never") "")) (display (cu-run (list "rm" "/tmp/x-cu-fs/never") "")))
```
---
```output
removed '/tmp/x-cu-fs/gone'
001
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-fs")) (display "clean"))
```
---
    clean

## sort

### -k names the key and -t the separator, in either spelling

```cu
(do (display (cu-run (list "sort" "-k2" "-n") "b 2\na 10\nc 1\n")) (display (cu-run (list "sort" "-k" "2" "-n") "b 2\na 10\nc 1\n")) (display (cu-run (list "sort" "-t," "-k2") "x,3\ny,1\nz,2\n")))
```
---
```output
c 1
b 2
a 10
0c 1
b 2
a 10
0y,1
z,2
x,3
0
```

### the orderings: -f folds, -M is months, -g reads a decimal

```cu
(do (display (cu-run (list "sort" "-f") "b\nA\na\n")) (display (cu-run (list "sort" "-M") "Mar\nJan\nFeb\n")) (display (cu-run (list "sort" "-g") "1.5\n1.25\n10\n")))
```
---
```output
A
a
b
0Jan
Feb
Mar
01.25
1.5
10
0
```

### -c answers whether the input was sorted, and names where it was not

```cu
(do (display (cu-run (list "sort" "-c") "a\nb\n")) (display (cu-run (list "sort" "-c") "b\na\n")))
```
---
    01

### -u drops what the comparison calls equal; -o writes it out

```cu
(do (display (cu-run (list "sort" "-u") "b\na\nb\n")) (display (cu-run (list "sort" "-o" "/tmp/x-cu-sorted") "b\na\n")) (display (file-read-all "/tmp/x-cu-sorted")) (file-unlink "/tmp/x-cu-sorted"))
```
---
```output
a
b
00a
b
```

### -b ignores leading blanks, -r reverses

```cu
(do (display (cu-run (list "sort" "-b") "  b\n a\n")) (display (cu-run (list "sort" "-r") "a\nb\n")))
```
---
```output
 a
  b
0b
a
0
```

## uniq

### -d keeps only what repeated, -u only what did not, -c counts

```cu
(do (display (cu-run (list "uniq" "-c") "a\na\nb\n")) (display (cu-run (list "uniq" "-d") "a\na\nb\n")) (display (cu-run (list "uniq" "-u") "a\na\nb\n")))
```
---
```output
   2 a
   1 b
0a
0b
0
```

### -i ignores case, -f skips fields, -w compares a prefix

```cu
(do (display (cu-run (list "uniq" "-i") "A\na\nB\n")) (display (cu-run (list "uniq" "-f1") "x a\ny a\nz b\n")) (display (cu-run (list "uniq" "-w1") "abc\nabd\nxyz\n")))
```
---
```output
A
B
0x a
z b
0abc
xyz
0
```

## nl

### -b a numbers every line; the default leaves the empty ones blank

```cu
(do (display (cu-run (list "nl") "a\n\nb\n")) (display (cu-run (list "nl" "-ba" "-w3") "a\n\nb\n")))
```
---
```output
     1	a
      	
     2	b
0  1	a
  2	
  3	b
0
```

### -w -s -v -i set the width, the separator, the first number and the step

```cu
(display (cu-run (list "nl" "-ba" "-w3" "-s:" "-v10" "-i5") "a\nb\n"))
```
---
```output
 10:a
 15:b
0
```

### -n chooses left, right, or right with zeros

```cu
(do (display (cu-run (list "nl" "-n" "ln" "-w3") "a\n")) (display (cu-run (list "nl" "-n" "rz" "-w3") "a\n")))
```
---
```output
1  	a
0001	a
0
```


## the declaration

### the guard and the applet cannot disagree about a flag

Both go through `%cu-opts` against the one row in `cu/cli.x`, so a flag
the guard admits is a flag the applet reads.  These three spellings
each broke a DIFFERENT hand-rolled reader before the library: a
cluster, an attached value, and a value flag read as a flag.

```cu
(do (display (cu-run (list "uname" "-sm") "")) (newline) (display (cu-run (list "sort" "-k2" "-n") "b 2\na 10\n")) (newline) (display (cu-run (list "wc" "-lw") "a b\n")))
```
---
```output
Darwin arm64
0
b 2
a 10
0
       1       2
0
```

### comm's flags are DIGITS, and the declaration says so

`-12` is two of comm's flags, not the number twelve.  v0.13.0's Opts
decides by shape first, so comm reads its three digits itself until
x-lang#650 ships; the guard and the operands still come off the parse.

```cu
(do (proc-run (list "/bin/sh" "-c" "printf 'a\nb\n' > /tmp/x-cu-c1 && printf 'b\nc\n' > /tmp/x-cu-c2")) (display (cu-run (list "comm" "-12" "/tmp/x-cu-c1" "/tmp/x-cu-c2") "")) (display (cu-run (list "comm" "-13" "/tmp/x-cu-c1" "/tmp/x-cu-c2") "")) (proc-run (list "/bin/sh" "-c" "rm -f /tmp/x-cu-c1 /tmp/x-cu-c2")) ())
```
---
```output
b
0c
0
```

### an undeclared flag is still refused, by the same parse

```cu
(do (display (cu-run (list "sort" "-Q") "a\n")) (display (cu-run (list "ls" "-Q") "")) (display (cu-run (list "cat" "-Q") "")))
```
---
    222

### an attached value, and a number that is nobody's flag

```cu
(do (display (cu-run (list "cut" "-d," "-f1") "a,b\n")) (display (cu-run (list "head" "-n1") "x\ny\n")))
```
---
```output
a
0x
0
```

## the file-metadata tools

### cut -b selects bytes, and -c does the same here

This cut is byte-oriented, so a character is a byte and the two flags are
one operation.

```cu
(do (display (cu-run (list "cut" "-b" "1-3") "abcdef\n"))
    (display (cu-run (list "cut" "-c" "1-3") "abcdef\n"))
    (display (cu-run (list "cut" "-b1,3") "abcdef\n")))
```
---
```output
abc
0abc
0ac
0
```

### cut -s drops a line that holds no delimiter

Without it such a line passes whole, which is what POSIX asks for.

```cu
(do (display (cu-run (list "cut" "-d:" "-f2") "a:b\nplain\n"))
    (display (cu-run (list "cut" "-d:" "-f2" "-s") "a:b\nplain\n")))
```
---
```output
b
plain
0b
0
```

### cut -n is honoured and changes nothing

It asks not to split a multibyte character, which cannot happen when
nothing is multibyte.

```cu
(display (cu-run (list "cut" "-n" "-b" "1-3") "abcdef\n"))
```
---
```output
abc
0
```

### cut with no list says so

```cu
(display (cu-run (list "cut" "x") ""))
```
---
    1

### wc -L is the longest line, -m counts what -c counts

A character is a byte here, so -m and -c report the same number; asking
for both prints it twice, which is what asking for both means.

```cu
(do (display (cu-run (list "wc" "-L") "ab cd\nefghij\n"))
    (display (cu-run (list "wc" "-m") "ab cd\nefghij\n")))
```
---
```output
       6
0      13
0
```

### wc with no flag is unchanged: lines, words, bytes

-m and -L are shown when asked for, never by default.

```cu
(display (cu-run (list "wc") "ab cd\nefghij\n"))
```
---
```output
       2       3      13
0
```

### shuf -i shuffles a range and reads nothing

Sorted back, the range is exactly itself.

```cu
(display (%cu-join-with
  (%cu-msort (%cu-shuf-range "1-5") %cu-str<) ","))
```
---
    1,2,3,4,5

### shuf -o writes where the shuffle goes

```cu
(do (cu-run (list "shuf" "-i" "1-4" "-o" "/tmp/x-cu-opt-shuf") "")
    (display (length (%cu-lines (file-read-all "/tmp/x-cu-opt-shuf"))))
    (file-unlink "/tmp/x-cu-opt-shuf"))
```
---
    4

### env -i starts from an empty environment, so it prints nothing

```cu
(display (cu-run (list "env" "-i") ""))
```
---
    0

### env -u drops exactly the name it was given

```cu
(do (def cap
      (fn (_ argv)
        (do (sys-dup2 1 9)
            (let ((fd (file-open-write "/tmp/x-cu-opt-env")))
              (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1)
                  (file-close fd)
                  (file-read-all "/tmp/x-cu-opt-env"))))))
    (def all (%cu-lines (cap (list "env"))))
    (def minus (%cu-lines (cap (list "env" "-u" "PATH"))))
    (display (- (length all) (length minus)))
    (display (%cu-dd-has?
      (map (fn (_ e) (first (%cu-split-byte e 61))) minus) "PATH"))
    (file-unlink "/tmp/x-cu-opt-env"))
```
---
    1#f

### dos2unix -d and unix2dos -u each take the other direction

The two are one tool with a default, and the flags name the direction
outright.

```cu
(do (file-write-all "/tmp/x-cu-opt-crlf" "a\r\nb\r\n")
    (cu-run (list "dos2unix" "/tmp/x-cu-opt-crlf") "")
    (display (byte-len (file-read-all "/tmp/x-cu-opt-crlf")))
    (cu-run (list "dos2unix" "-d" "/tmp/x-cu-opt-crlf") "")
    (display (byte-len (file-read-all "/tmp/x-cu-opt-crlf")))
    (cu-run (list "unix2dos" "-u" "/tmp/x-cu-opt-crlf") "")
    (display (byte-len (file-read-all "/tmp/x-cu-opt-crlf")))
    (file-unlink "/tmp/x-cu-opt-crlf"))
```
---
    464

### sync takes a file, and -f the filesystem holding it

```cu
(do (file-write-all "/tmp/x-cu-opt-sync" "x")
    (display (cu-run (list "sync") ""))
    (display (cu-run (list "sync" "-d" "/tmp/x-cu-opt-sync") ""))
    (display (cu-run (list "sync" "-f" "/tmp/x-cu-opt-sync") ""))
    (file-unlink "/tmp/x-cu-opt-sync"))
```
---
    000

### basename -s strips a suffix, as a second operand still does

```cu
(do (display (cu-run (list "basename" "-s" ".txt" "/a/b/c.txt") ""))
    (display (cu-run (list "basename" "/a/b/c.txt" ".txt") "")))
```
---
```output
c
0c
0
```

### echo -E turns escapes off, undoing an -e earlier on the line

```cu
(do (display (cu-run (list "echo" "-e" "a\\tb") ""))
    (display (cu-run (list "echo" "-e" "-E" "a\\tb") "")))
```
---
```output
a	b
0a\tb
0
```

### cmp -l lists every differing byte in octal, and keeps going

```cu
(do (file-write-all "/tmp/x-cu-opt-c1" "abcXef\n")
    (file-write-all "/tmp/x-cu-opt-c2" "abcYeZ\n")
    (display (cu-run (list "cmp" "-l" "/tmp/x-cu-opt-c1" "/tmp/x-cu-opt-c2") "")))
```
---
```output
     4 130 131
     6 146 132
1
```

### cmp -n bounds how far either file is read

The first three bytes match, so a comparison stopped there finds nothing.

```cu
(do (display (cu-run (list "cmp" "-n" "3" "/tmp/x-cu-opt-c1" "/tmp/x-cu-opt-c2") ""))
    (file-unlink "/tmp/x-cu-opt-c1")
    (file-unlink "/tmp/x-cu-opt-c2"))
```
---
    0

### seq -w pads to the widest value

```cu
(display (cu-run (list "seq" "-w" "8" "11") ""))
```
---
```output
08
09
10
11
0
```

### seq -s separates between, and ends with a newline

That is GNU's and busybox's shape. The BSD seq appends the separator
after the last value and ends without a newline; busybox is the parity
target, so this differs from the system seq on purpose.

```cu
(display (cu-run (list "seq" "-s" "," "3") ""))
```
---
```output
1,2,3
0
```

### paste -s puts a file on one line instead of pasting files together

```cu
(do (file-write-all "/tmp/x-cu-opt-p" "a\nb\nc\n")
    (display (cu-run (list "paste" "-s" "-d" "," "/tmp/x-cu-opt-p") ""))
    (file-unlink "/tmp/x-cu-opt-p"))
```
---
```output
a,b,c
0
```

### base64 -w sets the wrap column

```cu
(display (cu-run (list "base64" "-w" "4") "hello world"))
```
---
```output
aGVs
bG8g
d29y
bGQ=
0
```

### fixtures

```cu
(do (def cu-out (fn (_ argv) (do (sys-dup2 1 9) (let ((fd (file-open-write "/tmp/x-cu-fm/.cap"))) (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1) (file-close fd) (file-read-all "/tmp/x-cu-fm/.cap")))))) (def %cu-first-line (fn (_ s) (first (%cu-lines s)))) (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-fm && mkdir -p /tmp/x-cu-fm/sub && printf 'a\nb\nc\nd\ne\n' > /tmp/x-cu-fm/five && printf x > /tmp/x-cu-fm/sub/one")) (display "made"))
```
---
    made

### head and tail take -c bytes as well as -n lines

```cu
(do (display (cu-run (list "head" "-c" "3") "a\nb\nc\n")) (display (cu-run (list "tail" "-c" "2") "a\nb\n")) (display (cu-run (list "head" "-n" "1") "a\nb\n")) (display (cu-run (list "tail" "-n" "1") "a\nb\n")))
```
---
```output
a
b0b
0a
0b
0
```

### a header per operand when there are several; -v forces, -q suppresses

```cu
(do (display (cu-run (list "head" "-n1" "/tmp/x-cu-fm/five" "/tmp/x-cu-fm/sub/one") "")) (display (cu-run (list "head" "-n1" "-q" "/tmp/x-cu-fm/five" "/tmp/x-cu-fm/sub/one") "")) (display (cu-run (list "head" "-n1" "-v" "/tmp/x-cu-fm/five") "")))
```
---
```output
==> /tmp/x-cu-fm/five <==
a

==> /tmp/x-cu-fm/sub/one <==
x0a
x0==> /tmp/x-cu-fm/five <==
a
0
```

### du -d limits what is PRINTED, not what is counted; -c adds the total

```cu
(do (display (cu-run (list "du" "-d" "0" "/tmp/x-cu-fm") "")) (display (cu-run (list "du" "-c" "-s" "/tmp/x-cu-fm") "")))
```
---
```output
8	/tmp/x-cu-fm
08	/tmp/x-cu-fm
8	total
0
```

### mktemp -u names without creating; -d makes a directory

```cu
(do (display (if (file-exists? (%cu-first-line (cu-out (list "mktemp" "-u")))) "created" "named only")) (newline) (def d (%cu-first-line (cu-out (list "mktemp" "-d")))) (display (if (file-dir? d) "dir" "not a dir")) (file-rmdir d))
```
---
```output
named only
dir
```

### chown -v says what it changed, and -R reaches into a directory

```cu
(do (display (cu-run (list "chown" "-R" "-v" (%cu-int->str (sys-geteuid)) "/tmp/x-cu-fm/sub") "")))
```
---
```output
changed ownership of '/tmp/x-cu-fm/sub'
changed ownership of '/tmp/x-cu-fm/sub/one'
0
```

### uname says `unknown` for what it cannot ask

`-p` and `-i` are sysctl and `-o` is a string busybox compiles in;
none has a door, and printing the machine instead would be worse.

```cu
(do (display (cu-run (list "uname" "-p") "")) (display (cu-run (list "uname" "-o") "")))
```
---
```output
unknown
0unknown
0
```

### df counts blocks, or inodes under -i, in the unit -m and -B choose

```cu
(do (def row (fn (_ flag) (%cu-nth 1 (%cu-words-line (first (rest (%cu-lines (cu-out (list "df" flag "/tmp"))))))))) (display (if (> (%cu-num-prefix (row "-k")) (%cu-num-prefix (row "-m"))) "k>m" "wrong")) (newline) (display (%cu-join-with (%cu-words-line (first (%cu-lines (cu-out (list "df" "-i" "/tmp"))))) " ")))
```
---
```output
k>m
Filesystem Inodes IUsed IFree IUse% Mounted on
```

### -h scales blocks to bytes: du and df count 1024-byte blocks, %ls-human formats bytes

`%ls-human` is `ls -h`'s formatter and takes BYTES.  Both `du -h` and
`df -h` handed it their own block counts unscaled, so a 256K directory
printed as a bare `256` and a 926G filesystem as `926M` -- a thousandfold
under-report that reads as a plausible number.  The check is relational,
so it holds on any machine: the `-h` field must be what `%ls-human` makes
of the `-k` count scaled to bytes.

```cu
(do (def kb (%cu-num-prefix (cu-out (list "du" "-k" "-s" "/tmp/x-cu-fm")))) (display (if (string=? (cu-out (list "du" "-h" "-s" "/tmp/x-cu-fm")) (string-concat (list (%ls-human (* 1024 kb)) "\t/tmp/x-cu-fm\n"))) "du-h-scaled" "du-h-wrong")) (newline) (def hsize (%cu-nth 1 (%cu-words-line (first (rest (%cu-lines (cu-out (list "df" "-h" "/tmp")))))))) (def kb (%cu-num-prefix (%cu-nth 1 (%cu-words-line (first (rest (%cu-lines (cu-out (list "df" "-k" "/tmp"))))))))) (display (if (string=? hsize (%ls-human (* 1024 kb))) "df-h-scaled" "df-h-wrong")))
```
---
```output
du-h-scaled
df-h-scaled
```

### install honours the mode, makes parents under -D, and -t names a directory

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-in && mkdir -p /tmp/x-cu-in/into && printf body > /tmp/x-cu-in/src")) (cu-run (list "install" "-m" "750" "/tmp/x-cu-in/src" "/tmp/x-cu-in/dst") "") (display (cu-run (list "stat" "-c" "%a" "/tmp/x-cu-in/dst") "")) (cu-run (list "install" "-D" "-m" "700" "/tmp/x-cu-in/src" "/tmp/x-cu-in/a/b/dst") "") (display (cu-run (list "stat" "-c" "%a" "/tmp/x-cu-in/a/b/dst") "")) (cu-run (list "install" "-t" "/tmp/x-cu-in/into" "/tmp/x-cu-in/src") "") (display (if (file-exists? "/tmp/x-cu-in/into/src") "into" "missing")) (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-in")) ())
```
---
```output
750
0700
0into
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-fm")) (display "clean"))
```
---
    clean


## the process and file tools

### fixtures

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-pf && mkdir -p /tmp/x-cu-pf && printf 'hello world' > /tmp/x-cu-pf/there && printf secret > /tmp/x-cu-pf/ro && chmod 444 /tmp/x-cu-pf/ro")) (display "made"))
```
---
    made

### truncate -c passes over a file that is not there, and does not make one

```cu
(do (display (cu-run (list "truncate" "-c" "-s" "10" "/tmp/x-cu-pf/absent") "")) (display (if (file-exists? "/tmp/x-cu-pf/absent") "created" "absent")) (newline) (cu-run (list "truncate" "-c" "-s" "5" "/tmp/x-cu-pf/there") "") (display (cu-run (list "stat" "-c" "%s" "/tmp/x-cu-pf/there") "")))
```
---
```output
0absent
5
0
```

### without -c the file is created

```cu
(do (cu-run (list "truncate" "-s" "7" "/tmp/x-cu-pf/made") "") (display (cu-run (list "stat" "-c" "%s" "/tmp/x-cu-pf/made") "")))
```
---
```output
7
0
```

### shred -f writes through a mode that denies it

```cu
(do (display (cu-run (list "shred" "-n" "1" "-f" "/tmp/x-cu-pf/ro") "")) (display (if (string=? (file-read-all "/tmp/x-cu-pf/ro") "secret") "intact" "overwritten")))
```
---
    0overwritten

### timeout -k follows an ignored signal with KILL

`sh` traps TERM and outlives it, so only the KILL ends the command --
128+9, the status a KILLed child reports, rather than the 124 a command
that took the first signal would give.

```cu
(display (cu-run (list "timeout" "-k" "1" "1" "/bin/sh" "-c" "trap '' TERM; sleep 10") ""))
```
---
    137

### a command that ignores the signal and exits on its own still timed out

```cu
(display (cu-run (list "timeout" "1" "/bin/sh" "-c" "trap '' TERM; sleep 3") ""))
```
---
    124

### KILL as the primary signal keeps its own status

```cu
(display (cu-run (list "timeout" "-s" "9" "1" "/bin/sleep" "5") ""))
```
---
    137

### tty -s answers with the status alone

```cu
(do (display (cu-run (list "tty" "-s") "")) (display (cu-run (list "tty") "")))
```
---
```output
1not a tty
1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-pf")) (display "clean"))
```
---
    clean

## the text shapers

`tee -i` is declared and not run here: it sets the interrupt disposition
of the process it runs in, and cu-run runs the applet in the harness's own.

### fixtures

Output is captured and its control bytes spelled the way `cat -A` spells
them, so a tab, a backspace and a carriage return can be read.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-tx && mkdir -p /tmp/x-cu-tx")) (def cu-cap (fn (_ argv) (do (sys-dup2 1 9) (let ((fd (file-open-write "/tmp/x-cu-tx/.cap"))) (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1) (file-close fd) (Str8 replace (list->string (list (integer->char 13))) "^M" (Str8 replace (list->string (list (integer->char 8))) "^H" (Str8 replace "\t" "^I" (file-read-all "/tmp/x-cu-tx/.cap"))))))))) (file-write-all "/tmp/x-cu-tx/tab" "ab\tcdefghijkl\n") (file-write-all "/tmp/x-cu-tx/words" "the quick brown fox jumps\nabcdefghijklmnop\nab cd ef gh ij kl mn\n") (file-write-all "/tmp/x-cu-tx/ctl" (string-append "abc" (list->string (list (integer->char 8))) "defgh\nabcd" (list->string (list (integer->char 13))) "efghij\n")) (file-write-all "/tmp/x-cu-tx/lead" "\t\ta\tb\n  \tc\td\n") (file-write-all "/tmp/x-cu-tx/runs" "        a        b\n    \t  c\n  x\n") (file-write-all "/tmp/x-cu-tx/stops" "abcdefg h\nabcdef  h\na        \n") (display "made"))
```
---
    made

### fold counts columns, so a tab reaches the next stop; -b counts bytes

```cu
(do (display (cu-cap (list "fold" "-w" "12" "/tmp/x-cu-tx/tab"))) (display (cu-cap (list "fold" "-b" "-w" "12" "/tmp/x-cu-tx/tab"))))
```
---
```output
ab^Icdef
ghijkl
ab^Icdefghijk
l
```

### fold -s breaks after the last space, keeping it

```cu
(display (cu-cap (list "fold" "-s" "-w" "10" "/tmp/x-cu-tx/words")))
```
---
```output
the quick 
brown fox 
jumps
abcdefghij
klmnop
ab cd ef 
gh ij kl 
mn
```

### a backspace gives a column back and a carriage return the whole line

```cu
(display (cu-cap (list "fold" "-w" "5" "/tmp/x-cu-tx/ctl")))
```
---
```output
abc^Hdef
gh
abcd^Mefghi
j
```

### expand -i expands only the leading tabs

```cu
(do (display (cu-cap (list "expand" "/tmp/x-cu-tx/lead"))) (display (cu-cap (list "expand" "-i" "/tmp/x-cu-tx/lead"))))
```
---
```output
                a       b
        c       d
                a^Ib
        c^Id
```

### unexpand respells the leading run, tabs included; -f says so; -a takes every run

```cu
(do (display (cu-cap (list "unexpand" "/tmp/x-cu-tx/runs"))) (display (cu-cap (list "unexpand" "-f" "/tmp/x-cu-tx/runs"))) (display (cu-cap (list "unexpand" "-a" "/tmp/x-cu-tx/runs"))))
```
---
```output
^Ia        b
^I  c
  x
^Ia        b
^I  c
  x
^Ia^I b
^I  c
  x
```

### under -a a lone space on a stop stays a space; two become a tab; a trailing run counts

```cu
(display (cu-cap (list "unexpand" "-a" "/tmp/x-cu-tx/stops")))
```
---
```output
abcdefg h
abcdef^Ih
a^I 
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-tx")) (display "clean"))
```
---
    clean

## the singles

### fixtures

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-sg && mkdir -p /tmp/x-cu-sg/real && ln -s /tmp/x-cu-sg/real/target /tmp/x-cu-sg/l && : > /tmp/x-cu-sg/reg && printf abcdefghij > /tmp/x-cu-sg/od && printf 'a\\nb\\nc\\n' > /tmp/x-cu-sg/in && printf 'begin 644 t\\n$86)C\"@``\\n`\\nend\\n' > /tmp/x-cu-sg/uu")) (def cu-cap (fn (_ argv) (do (sys-dup2 1 9) (let ((fd (file-open-write "/tmp/x-cu-sg/.cap"))) (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1) (file-close fd) (file-read-all "/tmp/x-cu-sg/.cap")))))) (display "made"))
```
---
    made

### id -r reads the real ids, and on its own has nothing to print

The real and effective ids agree in a test process, so the fields are
judged equal to their plain forms rather than to a number.

```cu
(do (display (if (string=? (cu-cap (list "id" "-ru")) (cu-cap (list "id" "-u"))) "same" "differ")) (newline) (display (if (string=? (cu-cap (list "id" "-rg")) (cu-cap (list "id" "-g"))) "same" "differ")) (newline) (display (cu-run (list "id" "-r") "")))
```
---
```output
same
same
1
```

### nproc --ignore holds processors back and never answers below one; --all agrees with the plain count

With neither OpenMP variable set, which is why the case clears them first.

```cu
(do (Sys unsetenv "OMP_NUM_THREADS") (Sys unsetenv "OMP_THREAD_LIMIT") (def n (sys-cpu-count)) (display (if (= (%cu-num-prefix (cu-cap (list "nproc" "--ignore=1"))) (- n 1)) "one held" "wrong")) (newline) (display (cu-cap (list "nproc" "--ignore=9999"))) (display (if (string=? (cu-cap (list "nproc" "--all")) (cu-cap (list "nproc"))) "agree" "differ")))
```
---
```output
one held
1
agree
```

### nproc takes OMP_NUM_THREADS when it holds a count, even above the processors installed

Expectations from GNU nproc.  A list answers its first element, and white
space around the count is allowed.  Every case here clears both variables
before its last line, since the cases of a file share one process.

```cu
(do (Sys unsetenv "OMP_THREAD_LIMIT")
    (Sys setenv "OMP_NUM_THREADS" "2") (def np-two (cu-cap (list "nproc")))
    (Sys setenv "OMP_NUM_THREADS" (%cu-int->str (+ (sys-cpu-count) 5)))
    (def np-above (%cu-num-prefix (cu-cap (list "nproc"))))
    (Sys setenv "OMP_NUM_THREADS" "2,4") (def np-list (cu-cap (list "nproc")))
    (Sys setenv "OMP_NUM_THREADS" " 3 ") (def np-spaced (cu-cap (list "nproc")))
    (Sys setenv "OMP_NUM_THREADS" "2 ,4") (def np-gap (cu-cap (list "nproc")))
    (Sys unsetenv "OMP_NUM_THREADS")
    (display np-two)
    (display (if (= np-above (+ (sys-cpu-count) 5)) "above installed\n" "capped\n"))
    (display np-list) (display np-spaced) (display np-gap))
```
---
```output
2
above installed
2
3
2
```

### OMP_THREAD_LIMIT caps the answer, whether OMP_NUM_THREADS gave it or not

```cu
(do (Sys unsetenv "OMP_NUM_THREADS")
    (Sys setenv "OMP_THREAD_LIMIT" "1") (def np-limited (cu-cap (list "nproc")))
    (Sys setenv "OMP_NUM_THREADS" "5") (Sys setenv "OMP_THREAD_LIMIT" "3")
    (def np-over (cu-cap (list "nproc")))
    (Sys setenv "OMP_NUM_THREADS" "2") (def np-under (cu-cap (list "nproc")))
    (Sys unsetenv "OMP_NUM_THREADS") (Sys unsetenv "OMP_THREAD_LIMIT")
    (display np-limited) (display np-over) (display np-under))
```
---
```output
1
3
2
```

### a value that is not a count leaves the variable unset -- 0, abc and 3x all read as absent

```cu
(do (Sys unsetenv "OMP_NUM_THREADS") (Sys unsetenv "OMP_THREAD_LIMIT")
    (def np-plain (cu-cap (list "nproc")))
    (Sys setenv "OMP_NUM_THREADS" "0") (def np-zero (cu-cap (list "nproc")))
    (Sys setenv "OMP_NUM_THREADS" "abc") (def np-word (cu-cap (list "nproc")))
    (Sys setenv "OMP_NUM_THREADS" "3x") (def np-trail (cu-cap (list "nproc")))
    (Sys unsetenv "OMP_NUM_THREADS") (Sys setenv "OMP_THREAD_LIMIT" "0")
    (def np-nolimit (cu-cap (list "nproc")))
    (Sys unsetenv "OMP_THREAD_LIMIT")
    (List for-each
      (fn (_ v) (display (if (string=? v np-plain) "unset\n" "read\n")))
      (list np-zero np-word np-trail np-nolimit)))
```
---
```output
unset
unset
unset
unset
```

### nproc --all reads neither variable, and --ignore comes off after them

```cu
(do (Sys setenv "OMP_NUM_THREADS" "5") (Sys setenv "OMP_THREAD_LIMIT" "3")
    (def np-all (%cu-num-prefix (cu-cap (list "nproc" "--all"))))
    (Sys unsetenv "OMP_THREAD_LIMIT")
    (def np-held (cu-cap (list "nproc" "--ignore=2")))
    (Sys setenv "OMP_NUM_THREADS" "2") (def np-lowest (cu-cap (list "nproc" "--ignore=5")))
    (Sys unsetenv "OMP_NUM_THREADS")
    (display (if (= np-all (sys-cpu-count)) "installed\n" "narrowed\n"))
    (display np-held) (display np-lowest))
```
---
```output
installed
3
1
```

### pwd -P is the physical directory, and -L is that too when $PWD does not name it

```cu
(do (display (if (string=? (cu-cap (list "pwd" "-P")) (string-append (sys-getcwd) "\n")) "physical" "other")) (newline) (display (if (= (byte-at (cu-cap (list "pwd" "-L")) 0) 47) "absolute" "relative")))
```
---
```output
physical
absolute
```

### readlink -n drops the newline; -v names the trouble

```cu
(do (display (cu-cap (list "readlink" "-n" "/tmp/x-cu-sg/l"))) (display "|") (newline) (display (cu-run (list "readlink" "-v" "/tmp/x-cu-sg/reg") "")) (display (cu-run (list "readlink" "/tmp/x-cu-sg/reg") "")))
```
---
```output
/tmp/x-cu-sg/real/target|
11
```

### which -a is accepted and finds what the plain form finds first

```cu
(display (if (string=? (first (%cu-lines (cu-cap (list "which" "-a" "sh")))) (first (%cu-lines (cu-cap (list "which" "sh"))))) "same first" "differ"))
```
---
    same first

### split -a sets the suffix width

```cu
(do (cu-run (list "split" "-a" "3" "-l" "1" "/tmp/x-cu-sg/in" "/tmp/x-cu-sg/w") "") (display (if (file-exists? "/tmp/x-cu-sg/waaa") "waaa" "no")) (display (if (file-exists? "/tmp/x-cu-sg/waac") " waac" " no")) (newline) (cu-run (list "split" "-a" "1" "-l" "1" "/tmp/x-cu-sg/in" "/tmp/x-cu-sg/v") "") (display (if (file-exists? "/tmp/x-cu-sg/vc") "vc" "no")) (newline) (display (file-read-all "/tmp/x-cu-sg/waab")))
```
---
```output
waaa waac
vc
b
```

### od -j skips into the input and numbers from there; past the end it refuses

```cu
(do (display (cu-cap (list "od" "-j" "4" "-c" "/tmp/x-cu-sg/od"))) (display (cu-cap (list "od" "-A" "d" "-j" "3" "-t" "x1" "/tmp/x-cu-sg/od"))) (display (cu-cap (list "od" "-j4" "-N" "3" "-c" "/tmp/x-cu-sg/od"))) (display (cu-run (list "od" "-j" "99" "-c" "/tmp/x-cu-sg/od") "")))
```
---
```output
0000004   e   f   g   h   i   j
0000012
0000003 64 65 66 67 68 69 6a
0000010
0000004   e   f   g
0000007
1
```

### tr -c complements the first set, under -d and -s as well

```cu
(do (display (cu-run (list "tr" "-c" "a-z" "X") "ab1 cd2\n")) (newline) (display (cu-run (list "tr" "-cd" "a-z") "ab1 cd2\n")) (newline) (display (cu-run (list "tr" "-cs" "a-z" "X") "ab1 cd2\n")) (newline) (display (cu-run (list "tr" "-c" "abc" "XY") "ab1 cd2\n")))
```
---
```output
abXXcdXX0
abcd0
abXcdX0
abYYcYYY0
```

### uudecode -o names the output, and -o - is the standard output the plain form writes

```cu
(do (cu-run (list "uudecode" "-o" "/tmp/x-cu-sg/dec" "/tmp/x-cu-sg/uu") "") (display (file-read-all "/tmp/x-cu-sg/dec")) (display (cu-run (list "uudecode" "-o" "-" "/tmp/x-cu-sg/uu") "")))
```
---
```output
abc
abc
0
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-sg")) (display "clean"))
```
---
    clean

## tail -f

The loop itself never returns, so the specs drive one ROUND of it at a
time through %cu-tail-round with the offsets stated, which is what the
applet does between sleeps.

### fixtures

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-tl && mkdir -p /tmp/x-cu-tl && printf 'l1\\nl2\\nl3\\n' > /tmp/x-cu-tl/f && printf 'a1\\n' > /tmp/x-cu-tl/a && printf 'b1\\n' > /tmp/x-cu-tl/b")) (def cu-cap (fn (_ thunk) (do (sys-dup2 1 9) (let ((fd (file-open-write "/tmp/x-cu-tl/.cap"))) (do (sys-dup2 fd 1) (thunk) (sys-dup2 9 1) (file-close fd) (file-read-all "/tmp/x-cu-tl/.cap")))))) (def grow! (fn (_ p s) (let ((fd (file-open-append p))) (do (file-write fd s) (file-close fd))))) (display "made"))
```
---
    made

### -s without -f is accepted and changes nothing; -f over stdin alone prints the tail and returns

```cu
(do (display (cu-run (list "tail" "-s" "5" "-n" "1" "/tmp/x-cu-tl/f") "")) (display (cu-run (list "tail" "-f" "-n" "1") "p\nq\n")))
```
---
```output
l3
0q
0
```

### a round prints what grew past the offset, and moves the offset to the end

```cu
(do (grow! "/tmp/x-cu-tl/f" "l4\nl5\n") (def r (cu-cap (fn (_) (write (%cu-tail-round (list "/tmp/x-cu-tl/f") (list 9) #f ""))))) (display r))
```
---
```output
l4
l5
((15) . "/tmp/x-cu-tl/f")
```

### nothing grew, nothing printed, the offset stays

```cu
(write (%cu-tail-round (list "/tmp/x-cu-tl/f") (list 15) #f "/tmp/x-cu-tl/f"))
```
---
    ((15) . "/tmp/x-cu-tl/f")

### a file that shrank was truncated: it is read again from its start

```cu
(do (file-write-all "/tmp/x-cu-tl/f" "n1\n") (display (cu-cap (fn (_) (write (%cu-tail-round (list "/tmp/x-cu-tl/f") (list 15) #f "/tmp/x-cu-tl/f"))))))
```
---
```output
n1
((3) . "/tmp/x-cu-tl/f")
```

### growth on another file re-emits its header

```cu
(do (grow! "/tmp/x-cu-tl/a" "a2\n") (grow! "/tmp/x-cu-tl/b" "b2\n") (display (cu-cap (fn (_) (%cu-tail-round (list "/tmp/x-cu-tl/a" "/tmp/x-cu-tl/b") (list 3 3) #t "/tmp/x-cu-tl/b")))))
```
---
```output

==> /tmp/x-cu-tl/a <==
a2

==> /tmp/x-cu-tl/b <==
b2
```

### the file printed last needs no header again

```cu
(do (grow! "/tmp/x-cu-tl/b" "b3\n") (display (cu-cap (fn (_) (%cu-tail-round (list "/tmp/x-cu-tl/a" "/tmp/x-cu-tl/b") (list 6 6) #t "/tmp/x-cu-tl/b")))))
```
---
    b3

### a bounded follow starts where the initial read ended, so growth in between is not lost

```cu
(do (def at (byte-len (file-read-all "/tmp/x-cu-tl/f"))) (grow! "/tmp/x-cu-tl/f" "n2\n") (display (cu-cap (fn (_) (%cu-tail-follow (list "/tmp/x-cu-tl/f") (list at) #f "" "0" 1)))) (display "|"))
```
---
```output
n2
|
```

### a file that cannot be opened is named and dropped; with nothing left to follow, -f says so

The messages go to stderr; what the specs see is that nothing is printed
for the missing file, the good one still is, and the status is 1.

```cu
(do (display (cu-run (list "tail" "/tmp/x-cu-tl/nope") "")) (newline) (display (cu-run (list "tail" "-f" "/tmp/x-cu-tl/nope") "")) (newline) (display (cu-run (list "tail" "-n" "1" "/tmp/x-cu-tl/nope" "/tmp/x-cu-tl/a") "")))
```
---
```output
1
1
==> /tmp/x-cu-tl/a <==
a2
1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-tl")) (display "clean"))
```
---
    clean

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
