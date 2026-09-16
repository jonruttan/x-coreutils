# @weight 2

find walks a tree and applies an expression to every entry it reaches.
The tree is built once, in the first case, and every case below reads it.

Expectations come from `/usr/bin/find` over the same tree, with one
difference held throughout: this walk answers in SORTED order, as every
other descent in this bundle does (cu/walk.x says why), where find(1)
answers in whatever order the filesystem keeps.  The sets are the same;
only the order is settled here and arbitrary there.

## the tree

### fixtures

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-fd && mkdir -p /tmp/x-cu-fd/sub/deep /tmp/x-cu-fd/empty")) (file-write-all "/tmp/x-cu-fd/a.x" "aaa") (file-write-all "/tmp/x-cu-fd/b.txt" "bb") (file-write-all "/tmp/x-cu-fd/sub/c.x" "c") (file-write-all "/tmp/x-cu-fd/sub/d.md" "") (file-write-all "/tmp/x-cu-fd/sub/deep/e.x" "eeeee") (def cu-cap (fn (_ argv) (do (sys-dup2 1 9) (let ((fd (file-open-write "/tmp/x-cu-fd/.cap"))) (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1) (file-close fd) (file-read-all "/tmp/x-cu-fd/.cap")))))) (def fields (fn (_ p) (%cu-delim-fields (list p) (fn (_) "") 0))) (display "made"))
```
---
    made

## the predicates

### no expression prints every entry

```cu
(display (cu-run (list "find" "/tmp/x-cu-fd") ""))
```
---
```output
/tmp/x-cu-fd
/tmp/x-cu-fd/a.x
/tmp/x-cu-fd/b.txt
/tmp/x-cu-fd/empty
/tmp/x-cu-fd/sub
/tmp/x-cu-fd/sub/c.x
/tmp/x-cu-fd/sub/d.md
/tmp/x-cu-fd/sub/deep
/tmp/x-cu-fd/sub/deep/e.x
0
```

### -name matches the basename as a glob

```cu
(display (cu-run (list "find" "/tmp/x-cu-fd" "-name" "*.x") ""))
```
---
```output
/tmp/x-cu-fd/a.x
/tmp/x-cu-fd/sub/c.x
/tmp/x-cu-fd/sub/deep/e.x
0
```

### -iname folds case on both sides

```cu
(display (cu-run (list "find" "/tmp/x-cu-fd" "-iname" "A.X") ""))
```
---
```output
/tmp/x-cu-fd/a.x
0
```

### -type d finds the directories, -type f the files

```cu
(display (cu-run (list "find" "/tmp/x-cu-fd" "-type" "d") ""))
```
---
```output
/tmp/x-cu-fd
/tmp/x-cu-fd/empty
/tmp/x-cu-fd/sub
/tmp/x-cu-fd/sub/deep
0
```

### -type f

```cu
(display (cu-run (list "find" "/tmp/x-cu-fd" "-type" "f") ""))
```
---
```output
/tmp/x-cu-fd/a.x
/tmp/x-cu-fd/b.txt
/tmp/x-cu-fd/sub/c.x
/tmp/x-cu-fd/sub/d.md
/tmp/x-cu-fd/sub/deep/e.x
0
```

### -empty is an empty file or a directory with no entries

```cu
(display (cu-run (list "find" "/tmp/x-cu-fd" "-empty") ""))
```
---
```output
/tmp/x-cu-fd/empty
/tmp/x-cu-fd/sub/d.md
0
```

### -size counts 512-byte blocks, and a partial block counts as one

```cu
(display (cu-run (list "find" "/tmp/x-cu-fd" "-type" "f" "-size" "-1") ""))
```
---
```output
/tmp/x-cu-fd/sub/d.md
0
```

### -size with a c suffix counts bytes

```cu
(display (cu-run (list "find" "/tmp/x-cu-fd" "-type" "f" "-size" "+3c") ""))
```
---
```output
/tmp/x-cu-fd/sub/deep/e.x
0
```

## the depths

### -maxdepth bounds the descent, not just the test

```cu
(display (cu-run (list "find" "/tmp/x-cu-fd" "-maxdepth" "1") ""))
```
---
```output
/tmp/x-cu-fd
/tmp/x-cu-fd/a.x
/tmp/x-cu-fd/b.txt
/tmp/x-cu-fd/empty
/tmp/x-cu-fd/sub
0
```

### -mindepth skips the entries above it

```cu
(display (cu-run (list "find" "/tmp/x-cu-fd" "-mindepth" "2" "-name" "*.x") ""))
```
---
```output
/tmp/x-cu-fd/sub/c.x
/tmp/x-cu-fd/sub/deep/e.x
0
```

## the operators

### two factors side by side are joined by -a

```cu
(display (cu-run (list "find" "/tmp/x-cu-fd" "-type" "f" "-name" "*.x") ""))
```
---
```output
/tmp/x-cu-fd/a.x
/tmp/x-cu-fd/sub/c.x
/tmp/x-cu-fd/sub/deep/e.x
0
```

### ! negates the factor after it

```cu
(display (cu-run (list "find" "/tmp/x-cu-fd" "!" "-name" "*.x") ""))
```
---
```output
/tmp/x-cu-fd
/tmp/x-cu-fd/b.txt
/tmp/x-cu-fd/empty
/tmp/x-cu-fd/sub
/tmp/x-cu-fd/sub/d.md
/tmp/x-cu-fd/sub/deep
0
```

### -o takes either, and parentheses group

```cu
(display (cu-run (list "find" "/tmp/x-cu-fd" "(" "-name" "*.x" "-o" "-name" "*.md" ")") ""))
```
---
```output
/tmp/x-cu-fd/a.x
/tmp/x-cu-fd/sub/c.x
/tmp/x-cu-fd/sub/d.md
/tmp/x-cu-fd/sub/deep/e.x
0
```

### an unclosed group is an error, not a guess

```cu
(display (cu-run (list "find" "/tmp/x-cu-fd" "(" "-name" "*.x") ""))
```
---
    1

## the actions

### -print0 ends each path with a NUL, so a path may hold a newline

The capture is read back as fields, since a string stops at its first NUL.

```cu
(do (cu-cap (list "find" "/tmp/x-cu-fd" "-name" "*.x" "-print0")) (write (fields "/tmp/x-cu-fd/.cap")))
```
---
    ("/tmp/x-cu-fd/a.x" "/tmp/x-cu-fd/sub/c.x" "/tmp/x-cu-fd/sub/deep/e.x")

### -exec runs the command once per entry, {} standing for the path

```cu
(display (cu-run (list "find" "/tmp/x-cu-fd" "-name" "*.md" "-exec" "/bin/echo" "saw" "{}" ";") ""))
```
---
```output
saw /tmp/x-cu-fd/sub/d.md
0
```

### a path that is not there is reported, and the status says so

```cu
(display (cu-run (list "find" "/tmp/x-cu-fd/nope") ""))
```
---
    1
