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
(do (def il (first (%cu-lines (cu-out (list "ls" "-i" "/tmp/x-cu-ls/b.txt"))))) (display (if (> (%cu-num-prefix il) 0) "inode" "none")) (newline) (def hl (first (%cu-lines (cu-out (list "ls" "-lh" "/tmp/x-cu-ls/big.log"))))) (display (if (null? (filter (fn (_ w) (string=? w "4.8K")) (%cu-words-line hl))) "bytes" "4.8K")) (newline) (display (cu-run (list "ls" "/tmp/x-cu-ls/nope") "")))
```
---
```output
inode
4.8K
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
