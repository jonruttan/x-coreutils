# @weight 4

xargs and the seven busybox options it now takes.  Its own file: every
block here SPAWNS A PROCESS, and the suite runs a file's snippets in one
process without collecting between them, so these belong beside their
own fixtures rather than on the end of the option specs.

Two of busybox's nine are deliberately absent, and `cu/sys2.x` records
why: `-0` cannot receive its input, because a NUL truncates an x string
at every door this bundle has, and `-p` wants a tty the applet protocol
never hands an applet.  Declaring either would accept a flag the applet
cannot honour, which is how every option bug in this bundle got in.

## the items, and where they come from

### the default still appends stdin's words

```cu
(display (cu-run (list "xargs" "echo" "got") "a b\nc\n"))
```
---
```output
got a b c
0
```

### -n batches, and the status is the worst of the runs

```cu
(display (cu-run (list "xargs" "-n" "1" "echo") "a b c\n"))
```
---
```output
a
b
c
0
```

### -a reads the items from a file instead of stdin

```cu
(do (file-write-all "/tmp/x-cu-xa" "x y\nz\n")
    (display (cu-run (list "xargs" "-a" "/tmp/x-cu-xa" "echo") ""))
    (file-unlink "/tmp/x-cu-xa"))
```
---
```output
x y z
0
```

### -E ends the input at its marker

```cu
(display (cu-run (list "xargs" "-E" "STOP" "echo") "a b STOP c d\n"))
```
---
```output
a b
0
```

## empty input, which is where -r earns its name

### by default the command runs once, over nothing

POSIX runs it; `-r` is the flag that asks for the other answer.  This
bundle used to answer the other way round with no way to ask.

```cu
(display (cu-run (list "xargs" "echo" "empty") ""))
```
---
```output
empty
0
```

### -r does not run it at all

```cu
(display (cu-run (list "xargs" "-r" "echo" "empty") ""))
```
---
    0

## shaping the command line

### -I substitutes into the arguments, one item per run

Nothing is appended after them -- that is the difference between `-I`
and `-n 1`.

```cu
(display (cu-run (list "xargs" "-I" "{}" "echo" "[{}]") "a b\n"))
```
---
```output
[a]
[b]
0
```

### -s splits on a character budget

```cu
(display (cu-run (list "xargs" "-s" "12" "echo") "aa bb cc dd\n"))
```
---
```output
aa bb
cc dd
0
```

### an item too large for -s runs anyway, unless -x

A batch never takes zero items: taking none would not shorten the line,
it would spin.  `-x` is how a caller asks to stop instead.

```cu
(display (cu-run (list "xargs" "-s" "6" "echo") "aaaaaaaaaa\n"))
```
---
```output
aaaaaaaaaa
0
```

### -x refuses it and the status moves

The refusal goes to stderr, so only the status reaches stdout.

```cu
(display (cu-run (list "xargs" "-x" "-s" "6" "echo") "aaaaaaaaaa\n"))
```
---
    1

### -t traces to stderr, so stdout is the command's own output

```cu
(display (cu-run (list "xargs" "-t" "echo") "a b\n"))
```
---
```output
a b
0
```

## the guard and the reader agree

### an option xargs does not take is refused, not ignored

```cu
(display (cu-run (list "xargs" "-Z" "echo") "a\n"))
```
---
    2
