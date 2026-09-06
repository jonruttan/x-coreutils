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
