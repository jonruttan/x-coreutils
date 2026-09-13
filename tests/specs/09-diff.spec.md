# @weight 4

diff's comparison and report options.  diff had none at all, and no
specs either.

THE BODY IS ASSERTED THROUGH THE STRING DOOR, not through stdout: the
normal format writes `> ` at the head of an added line, and the spec
runner strips a literal `"> "` prompt from captured output, so a quoted
body would be compared against text the runner has already edited.
`%cu-diff-str` answers `(OUTPUT . STATUS)` without displaying, which is
what it exists for.  Where the observable is the status -- which is what
`-i`, `-b`, `-w` and `-B` actually change -- the status is what these
blocks assert.

## fixtures

### two files that differ only by case, and two only by spacing

```cu
(do (file-write-all "/tmp/x-cu-df-1" "alpha\nbeta\ngamma\n")
    (file-write-all "/tmp/x-cu-df-2" "ALPHA\nbeta\ngamma\n")
    (file-write-all "/tmp/x-cu-df-3" "alpha\nbeta  x\ngamma\n")
    (file-write-all "/tmp/x-cu-df-4" "alpha\nbeta x\ngamma\n")
    (file-write-all "/tmp/x-cu-df-5" "a b\nc\n")
    (file-write-all "/tmp/x-cu-df-6" "ab\nc\n")
    (file-write-all "/tmp/x-cu-df-7" "a\n\n\nb\n")
    (file-write-all "/tmp/x-cu-df-8" "a\nb\n")
    (file-write-all "/tmp/x-cu-df-u1" "one\ntwo\nthree\nfour\nfive\nsix\nseven\n")
    (file-write-all "/tmp/x-cu-df-u2" "one\ntwo\nTHREE\nfour\nfive\nsix\nseven\n")
    (file-write-all "/tmp/x-cu-df-g1" "1\n2\n3\n4\n5\n6\n7\n")
    (file-write-all "/tmp/x-cu-df-g2" "1\n2\nX\n4\n5\n6\nY\n")
    (file-write-all "/tmp/x-cu-df-i1" "a\nb\n")
    (file-write-all "/tmp/x-cu-df-i2" "a\nNEW\nb\n")
    (file-write-all "/tmp/x-cu-df-t1" "a\tb\nc\n")
    (file-write-all "/tmp/x-cu-df-t2" "a\tB\nc\n")
    ; how many hunks -U CTX produces over the two-change fixture: one
    ; "@@ -" begins each header
    (def %cu-diff-hunk-count
      (fn (_ ctx)
        (def out (first (%cu-diff-str
                          (list "-U" ctx "/tmp/x-cu-df-g1" "/tmp/x-cu-df-g2") "")))
        (def end (byte-len out))
        (def go
          (fn (self i k)
            (if (> (+ i 4) end) k
              (if (string=? (substring out i (+ i 4)) "@@ -")
                (self (+ i 4) (+ k 1))
                (self (+ i 1) k)))))
        (%cu-int->str (go 0 0))))
    (display "made"))
```
---
    made

## the normal format still reads as it did

### a case change is one hunk, quoted both ways

```cu
(display (string=?
  (first (%cu-diff-str (list "/tmp/x-cu-df-1" "/tmp/x-cu-df-2") ""))
  "1c1\n< alpha\n---\n> ALPHA\n"))
```
---
    #t

### and the status says they differ

```cu
(display (cu-run (list "diff" "/tmp/x-cu-df-1" "/tmp/x-cu-df-2") ""))
```
---
```output
1c1
< alpha
---
ALPHA
1
```

## what counts as the same line

### -i folds case

```cu
(display (cu-run (list "diff" "-i" "/tmp/x-cu-df-1" "/tmp/x-cu-df-2") ""))
```
---
    0

### -b ignores the amount of whitespace, not its presence

Two spaces and one space are the same line; a space and no space are
not.  Read through the string door, because the second of these prints
a body and a body cannot be quoted here.

```cu
(do (display (rest (%cu-diff-str (list "-b" "/tmp/x-cu-df-3" "/tmp/x-cu-df-4") "")))
    (display (rest (%cu-diff-str (list "-b" "/tmp/x-cu-df-5" "/tmp/x-cu-df-6") ""))))
```
---
    01

### -w ignores whitespace entirely, which is the difference

```cu
(display (cu-run (list "diff" "-w" "/tmp/x-cu-df-5" "/tmp/x-cu-df-6") ""))
```
---
    0

### -B ignores a change that is only blank lines

```cu
(do (display (cu-run (list "diff" "/tmp/x-cu-df-7" "/tmp/x-cu-df-8") ""))
    (display (cu-run (list "diff" "-B" "/tmp/x-cu-df-7" "/tmp/x-cu-df-8") "")))
```
---
    10

## reporting instead of showing

### -q names the pair and says nothing else

```cu
(display (cu-run (list "diff" "-q" "/tmp/x-cu-df-1" "/tmp/x-cu-df-2") ""))
```
---
```output
Files /tmp/x-cu-df-1 and /tmp/x-cu-df-2 differ
1
```

### -q says nothing at all when they match

That is why `-q` and `-s` are two flags and not one.

```cu
(display (cu-run (list "diff" "-q" "/tmp/x-cu-df-1" "/tmp/x-cu-df-1") ""))
```
---
    0

### -s names them when they DO match

```cu
(display (cu-run (list "diff" "-s" "/tmp/x-cu-df-1" "/tmp/x-cu-df-1") ""))
```
---
```output
Files /tmp/x-cu-df-1 and /tmp/x-cu-df-1 are identical
0
```

## the two that do nothing, on purpose

### -a and -d are accepted and change no answer

`-a` turns off a binary mode this diff does not have, and `-d` asks for
a smaller change set than an LCS already gives.  Both are honoured by
behaving exactly as before.

```cu
(display (string=?
  (first (%cu-diff-str (list "-a" "-d" "/tmp/x-cu-df-1" "/tmp/x-cu-df-2") ""))
  (first (%cu-diff-str (list "/tmp/x-cu-df-1" "/tmp/x-cu-df-2") ""))))
```
---
    #t

### an option diff does not take is still refused

```cu
(display (cu-run (list "diff" "-Z" "/tmp/x-cu-df-1" "/tmp/x-cu-df-2") ""))
```
---
    2

## the unified format

### -U N prints hunks with N lines of context

Asserted through the string door for the same reason as the bodies
above: a `+` line is safe to quote but a context line is not, and the
whole point is the shape of the hunk.

```cu
(display (first (%cu-diff-str
  (list "-U" "1" "/tmp/x-cu-df-u1" "/tmp/x-cu-df-u2") "")))
```
---
```output
--- /tmp/x-cu-df-u1
+++ /tmp/x-cu-df-u2
@@ -2,3 +2,3 @@
 two
-three
+THREE
 four
```

### widening the context merges hunks that would otherwise be two

Two changes three lines apart are two hunks at `-U 1` and one at `-U 2`:
the run between them is no longer than the context either side would
print anyway.

```cu
(do (display (%cu-diff-hunk-count "1")) (display " ")
    (display (%cu-diff-hunk-count "2")))
```
---
    2 1

### the counts are lines, not ops

A hunk header counts a-lines and b-lines, so a pure insertion has a
zero-length old side and names the line it follows.

```cu
(display (first (%cu-diff-str
  (list "-U" "1" "/tmp/x-cu-df-i1" "/tmp/x-cu-df-i2") "")))
```
---
```output
--- /tmp/x-cu-df-i1
+++ /tmp/x-cu-df-i2
@@ -1,2 +1,3 @@
 a
+NEW
 b
```

### -L names the files instead

The first -L is the old side, the second the new.  A header carries no
timestamp: GNU and busybox write the file's mtime, and this bundle has
no clock a spec can pin.

```cu
(display (first (%cu-diff-str
  (list "-U" "1" "-L" "old" "-L" "new"
    "/tmp/x-cu-df-u1" "/tmp/x-cu-df-u2") "")))
```
---
```output
--- old
+++ new
@@ -2,3 +2,3 @@
 two
-three
+THREE
 four
```

### -t expands tabs, -T prefixes one so the marker does not shift the text

```cu
(do (display (byte-len (first (%cu-diff-str
       (list "-U" "1" "/tmp/x-cu-df-t1" "/tmp/x-cu-df-t2") ""))))
    (display " ")
    (display (byte-len (first (%cu-diff-str
       (list "-U" "1" "-t" "/tmp/x-cu-df-t1" "/tmp/x-cu-df-t2") ""))))
    (display " ")
    (display (byte-len (first (%cu-diff-str
       (list "-U" "1" "-T" "/tmp/x-cu-df-t1" "/tmp/x-cu-df-t2") "")))))
```
---
    69 81 72

### unified says nothing when the files match

```cu
(display (cu-run (list "diff" "-U" "3" "/tmp/x-cu-df-1" "/tmp/x-cu-df-1") ""))
```
---
    0

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -f /tmp/x-cu-df-*")) (display "clean"))
```
---
    clean
