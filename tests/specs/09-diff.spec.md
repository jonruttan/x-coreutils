# @weight 3

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

### a space-only line is not blank, even under -w

```cu
(do (file-write-all "/tmp/x-cu-df-b1" "x\n \ny\n")
    (file-write-all "/tmp/x-cu-df-b2" "x\ny\n")
    (display (cu-run (list "diff" "-B" "-w"
                       "/tmp/x-cu-df-b1" "/tmp/x-cu-df-b2") "")))
```
---
    1

### -b ignores whitespace at the end of a line entirely

Not the rule it applies in the middle: `"a  "` and `"a"` are the same
line, while `"  a"` and `"a"` are not.

```cu
(do (file-write-all "/tmp/x-cu-df-e1" "a  \n")
    (file-write-all "/tmp/x-cu-df-e2" "a\n")
    (file-write-all "/tmp/x-cu-df-e3" "  a\n")
    (display (rest (%cu-diff-str (list "-b" "/tmp/x-cu-df-e1" "/tmp/x-cu-df-e2") "")))
    (display (rest (%cu-diff-str (list "-b" "/tmp/x-cu-df-e3" "/tmp/x-cu-df-e2") ""))))
```
---
    01

### -B ignores a change that is only blank lines

Blank means EMPTY, read from the line as it is -- a line holding one
space is not blank, and stays not blank under `-w` even though `-w`
compares it equal to an empty one.  That is what /usr/bin/diff answers,
and it is not the intuitive rule.

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

## directories

### fixtures

```cu
(do (proc-run (list "/bin/sh" "-c"
      "rm -rf /tmp/x-cu-dd && mkdir -p /tmp/x-cu-dd/A/sub /tmp/x-cu-dd/B/sub"))
    (file-write-all "/tmp/x-cu-dd/A/same.txt" "same\n")
    (file-write-all "/tmp/x-cu-dd/B/same.txt" "same\n")
    (file-write-all "/tmp/x-cu-dd/A/diff.txt" "one\n")
    (file-write-all "/tmp/x-cu-dd/B/diff.txt" "two\n")
    (file-write-all "/tmp/x-cu-dd/A/onlyA.txt" "only A\n")
    (file-write-all "/tmp/x-cu-dd/B/onlyB.txt" "only B\n")
    (file-write-all "/tmp/x-cu-dd/A/sub/deep.txt" "deep a\n")
    (file-write-all "/tmp/x-cu-dd/B/sub/deep.txt" "deep b\n")
    ; the walk's output as a string.  Asserted in x rather than quoted:
    ; a body carries "> " lines and the runner strips a literal "> "
    ; prompt from captured stdout.
    (def %cu-dd
      (fn (_ flags start)
        (first (%cu-diff-dir
                 (%cu-opts "diff" (append flags
                                    (list "/tmp/x-cu-dd/A" "/tmp/x-cu-dd/B")))
                 flags "/tmp/x-cu-dd/A" "/tmp/x-cu-dd/B" start))))
    (def %cu-dd-has?
      (fn (_ hay needle)
        (def hn (byte-len hay))
        (def nn (byte-len needle))
        (def go
          (fn (self i)
            (if (> (+ i nn) hn) #f
              (if (string=? (substring hay i (+ i nn)) needle) #t
                (self (+ i 1))))))
        (go 0)))
    (display "made"))
```
---
    made

### a file only one side has is named, not compared

```cu
(do (def out (%cu-dd () ()))
    (display (%cu-dd-has? out "Only in /tmp/x-cu-dd/A: onlyA.txt\n"))
    (display (%cu-dd-has? out "Only in /tmp/x-cu-dd/B: onlyB.txt\n")))
```
---
    #t#t

### a shared subdirectory is common, until -r

```cu
(do (display (%cu-dd-has? (%cu-dd () ())
       "Common subdirectories: /tmp/x-cu-dd/A/sub and /tmp/x-cu-dd/B/sub\n"))
    (display (%cu-dd-has? (%cu-dd (list "-r") ())
       "Common subdirectories")))
```
---
    #t#f

### -r looks inside it, and the header repeats the flags

The header is the command that would show that one file, so it carries
the flags as they were given.

```cu
(display (%cu-dd-has? (%cu-dd (list "-r") ())
  "diff -r /tmp/x-cu-dd/A/sub/deep.txt /tmp/x-cu-dd/B/sub/deep.txt\n"))
```
---
    #t

### -N compares an absent file as an empty one

The name that was only on one side is no longer merely named: it is
compared, against nothing.

```cu
(do (def out (%cu-dd (list "-r" "-N") ()))
    (display (%cu-dd-has? out "Only in"))
    (display (%cu-dd-has? out
      "diff -r -N /tmp/x-cu-dd/A/onlyA.txt /tmp/x-cu-dd/B/onlyA.txt\n1d0\n")))
```
---
    #f#t

### -S starts the walk at a name, in the ORDER the walk uses

```cu
(do (def out (%cu-dd (list "-r" "-S" "same.txt") "same.txt"))
    (display (%cu-dd-has? out "diff.txt"))
    (display (%cu-dd-has? out "sub/deep.txt")))
```
---
    #f#t

### and -S applies to the directory it was given, not to each one under it

`sub/deep.txt` is still compared when the walk starts at `same.txt`,
because the nested walk starts at its own beginning.  The BSD diff on
this machine filters every level instead, so `-S sub` there hides
`sub/deep.txt` -- measured, and not followed: a flag that silently drops
files in directories it was never pointed at is a surprise, not a
feature.

```cu
(display (%cu-dd-has? (%cu-dd (list "-r" "-S" "sub") "sub") "deep.txt"))
```
---
    #t

### diff FILE DIR compares FILE with the entry of that name

```cu
(display (cu-run (list "diff" "/tmp/x-cu-dd/A/same.txt" "/tmp/x-cu-dd/B") ""))
```
---
    0

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-df-* /tmp/x-cu-dd"))
    (display "clean"))
```
---
    clean
