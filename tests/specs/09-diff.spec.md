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

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -f /tmp/x-cu-df-*")) (display "clean"))
```
---
    clean
