# @weight 6

test, `[` and `[[` -- the whole expression grammar, and the file
questions it asks.  Its own file: these blocks stat a great deal, and
the suite runs a file's snippets in one process without collecting
between them, so a long tail of them belongs beside its own fixtures
rather than on the end of the option specs.

## test, and its two other spellings

### fixtures

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-t && mkdir -p /tmp/x-cu-t/dir && cd /tmp/x-cu-t && : > plain && : > x1 && chmod 755 x1 && chmod 644 plain && ln -s plain link && ln -s nowhere dangling && mkfifo pipe")) (display "made"))
```
---
    made

### the file-type tests FOLLOW a link; -L and -h ask about the link

`test -d /tmp` is true on a machine where /tmp is itself a symlink,
which is what reading them all off lstat got wrong.

```cu
(do (display (cu-run (list "test" "-d" "/tmp/x-cu-t/dir") "")) (display (cu-run (list "test" "-f" "/tmp/x-cu-t/link") "")) (display (cu-run (list "test" "-L" "/tmp/x-cu-t/link") "")) (display (cu-run (list "test" "-h" "/tmp/x-cu-t/link") "")) (display (cu-run (list "test" "-L" "/tmp/x-cu-t/plain") "")) (display (cu-run (list "test" "-p" "/tmp/x-cu-t/pipe") "")))
```
---
    000010

### -e is about existence, and a dangling link does not exist

```cu
(do (display (cu-run (list "test" "-e" "/tmp/x-cu-t/plain") "")) (display (cu-run (list "test" "-e" "/tmp/x-cu-t/dangling") "")) (display (cu-run (list "test" "-s" "/tmp/x-cu-t/plain") "")))
```
---
    011

### the permission tests read the triple that applies to us

```cu
(do (display (cu-run (list "test" "-r" "/tmp/x-cu-t/plain") "")) (display (cu-run (list "test" "-w" "/tmp/x-cu-t/plain") "")) (display (cu-run (list "test" "-x" "/tmp/x-cu-t/plain") "")) (display (cu-run (list "test" "-x" "/tmp/x-cu-t/x1") "")))
```
---
    0010

### -a and -o join terms, ! negates, and parentheses group

```cu
(do (display (cu-run (list "test" "-f" "/tmp/x-cu-t/plain" "-a" "-d" "/tmp/x-cu-t/dir") "")) (display (cu-run (list "test" "-f" "/tmp/x-cu-t/nope" "-o" "-d" "/tmp/x-cu-t/dir") "")) (display (cu-run (list "test" "-f" "/tmp/x-cu-t/plain" "-a" "-f" "/tmp/x-cu-t/nope") "")) (display (cu-run (list "test" "!" "-f" "/tmp/x-cu-t/nope") "")) (display (cu-run (list "test" "(" "-f" "/tmp/x-cu-t/nope" "-o" "-d" "/tmp/x-cu-t/dir" ")" "-a" "-f" "/tmp/x-cu-t/plain") "")))
```
---
    00100

### -ef is the same file, -nt and -ot compare the stamps

```cu
(do (proc-run (list "/bin/sh" "-c" "ln /tmp/x-cu-t/plain /tmp/x-cu-t/hard && sleep 1 && : > /tmp/x-cu-t/newer")) (display (cu-run (list "test" "/tmp/x-cu-t/plain" "-ef" "/tmp/x-cu-t/hard") "")) (display (cu-run (list "test" "/tmp/x-cu-t/plain" "-ef" "/tmp/x-cu-t/x1") "")) (display (cu-run (list "test" "/tmp/x-cu-t/newer" "-nt" "/tmp/x-cu-t/plain") "")) (display (cu-run (list "test" "/tmp/x-cu-t/newer" "-ot" "/tmp/x-cu-t/plain") "")))
```
---
    0101

### a malformed expression is status 2, which is not "false"

```cu
(do (display (cu-run (list "test" "(" "-f" "/tmp/x-cu-t/plain") "")) (display (cu-run (list "test" "-f") "")) (display (cu-run (list "[" "-d" "/tmp/x-cu-t/dir") "")))
```
---
    202

### [ and [[ are test with their closers

```cu
(do (display (cu-run (list "[" "-d" "/tmp/x-cu-t/dir" "]") "")) (display (cu-run (list "[[" "-f" "/tmp/x-cu-t/plain" "]]") "")) (display (cu-run (list "[" "1" "-lt" "2" "]") "")))
```
---
    000

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-t")) (display "clean"))
```
---
    clean
