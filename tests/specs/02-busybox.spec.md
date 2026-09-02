# @weight 2

The busybox expansion: twenty-seven more applets through the pure
core.  Deterministic expectations from real tool runs; the clock- and
cwd-shaped ones assert shape, not value.

## echo and printf

### echo joins and ends the line; -n does not

```cu
(do (display (cu-run (list "echo" "two" "words") "")) (newline) (display (cu-run (list "echo" "-n" "bare") "")))
```
---
```output
two words
0
bare0
```

### printf reuses its format across the arguments

```cu
(display (cu-run (list "printf" "%s-%d|" "a" "1" "b" "2") ""))
```
---
    a-1|b-2|0

### printf width and left-justification

```cu
(display (cu-run (list "printf" "[%5d][%-5s]\\n" "42" "hi") ""))
```
---
```output
[   42][hi   ]
0
```

## sequences and shapes

### seq one two and three arguments

```cu
(do (display (cu-run (list "seq" "3") "")) (newline) (display (cu-run (list "seq" "2" "5") "")) (newline) (display (cu-run (list "seq" "10" "-3" "1") "")))
```
---
```output
1
2
3
0
2
3
4
5
0
10
7
4
1
0
```

### rev mirrors bytes; tac mirrors lines

```cu
(do (display (cu-run (list "rev") "abc\ndef\n")) (newline) (display (cu-run (list "tac") "1\n2\n3\n")))
```
---
```output
cba
fed
0
3
2
1
0
```

### nl numbers the nonempty lines

```cu
(display (cu-run (list "nl") "one\n\ntwo\n"))
```
---
```output
     1	one
      	
     2	two
0
```

### fold wraps hard

```cu
(display (cu-run (list "fold" "-w" "3") "abcdefgh\n"))
```
---
```output
abc
def
gh
0
```

## the file half

### fixtures

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-bb && mkdir -p /tmp/x-cu-bb")) (file-write-all "/tmp/x-cu-bb/p1" "1\n2\n") (file-write-all "/tmp/x-cu-bb/p2" "a\nb\n") (file-write-all "/tmp/x-cu-bb/d1" "a\nb\nc\n") (file-write-all "/tmp/x-cu-bb/d2" "a\nx\nc\nd\n") (display "made"))
```
---
    made

### paste, tab and -d

```cu
(do (display (cu-run (list "paste" "/tmp/x-cu-bb/p1" "/tmp/x-cu-bb/p2") "")) (newline) (display (cu-run (list "paste" "-d," "/tmp/x-cu-bb/p1" "/tmp/x-cu-bb/p2") "")))
```
---
```output
1	a
2	b
0
1,a
2,b
0
```

### tee writes and passes through

```cu
(do (display (cu-run (list "tee" "/tmp/x-cu-bb/teed") "payload\n")) (newline) (display (file-read-all "/tmp/x-cu-bb/teed")))
```
---
```output
payload
0
payload
```

### touch creates; ls lists sorted, dotfiles hidden

```cu
(do (cu-run (list "touch" "/tmp/x-cu-bb/zz" "/tmp/x-cu-bb/.hidden") "") (display (cu-run (list "ls" "/tmp/x-cu-bb") "")))
```
---
```output
d1
d2
p1
p2
teed
zz
0
```

### mv renames; rmdir removes empties

```cu
(do (cu-run (list "mv" "/tmp/x-cu-bb/zz" "/tmp/x-cu-bb/yy") "") (cu-run (list "mkdir" "/tmp/x-cu-bb/sub") "") (display (cu-run (list "rmdir" "/tmp/x-cu-bb/sub") "")) (newline) (display (if (file-exists? "/tmp/x-cu-bb/yy") "moved" "lost")))
```
---
```output
0
moved
```

### install -d makes parents; install copies into a directory

```cu
(do (cu-run (list "install" "-d" "/tmp/x-cu-bb/a/b") "") (cu-run (list "install" "-c" "-m" "644" "/tmp/x-cu-bb/p1" "/tmp/x-cu-bb/a/b") "") (display (file-read-all "/tmp/x-cu-bb/a/b/p1")))
```
---
```output
1
2
```

### mktemp creates exclusively under the template

```cu
(do (def p1 (cu-run (list "mktemp" "/tmp/x-cu-bb/tmp.XXXXXX") "")) (display p1))
```
---
    0

### cmp: silence on same, char and line on different

```cu
(do (display (cu-run (list "cmp" "-s" "/tmp/x-cu-bb/p1" "/tmp/x-cu-bb/p1") "")) (newline) (display (cu-run (list "cmp" "/tmp/x-cu-bb/d1" "/tmp/x-cu-bb/d2") "")))
```
---
```output
0
/tmp/x-cu-bb/d1 /tmp/x-cu-bb/d2 differ: char 3, line 2
1
```

### diff, normal format

The runner strips a literal `> ` prompt from captured stdout, so diff's
real output (which has `> ` add-lines) is asserted through the quoted
string builder instead -- `write` shows the exact bytes.

```cu
(do (def r (%cu-diff-str (list "/tmp/x-cu-bb/d1" "/tmp/x-cu-bb/d2") (fn (_) ""))) (write (first r)) (newline) (display (rest r)))
```
---
```output
"2c2\n< b\n---\n> x\n3a4\n> d\n"
1
```

### diff agrees on agreement

```cu
(display (cu-run (list "diff" "/tmp/x-cu-bb/d1" "/tmp/x-cu-bb/d1") ""))
```
---
    0

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-bb")) (display "clean"))
```
---
    clean

## the option guard

### an unknown flag refuses instead of masquerading as a file

`ls -l` once printed `-l`.  The dispatcher checks the leading option
tokens against the applet's table: status 2 and a line on stderr.

```cu
(do (display (cu-run (list "ls" "-l" "/tmp") "")) (display " ") (display (cu-run (list "sort" "-rn") "3\n10\n")) )
```
---
```output
2 10
3
0
```

## the system half

### true, false, and test's verdicts

```cu
(do (display (cu-run (list "true") "")) (display (cu-run (list "false") "")) (display (cu-run (list "test" "3" "-lt" "5") "")) (display (cu-run (list "test" "a" "=" "b") "")) (display (cu-run (list "test" "!" "-e" "/tmp/x-cu-none") "")) (display (cu-run (list "[" "-n" "x" "]") "")))
```
---
    010100

### test on the filesystem

```cu
(do (display (cu-run (list "test" "-d" "/tmp") "")) (display (cu-run (list "test" "-f" "/tmp") "")))
```
---
    01

### which finds sh

```cu
(display (cu-run (list "which" "sh") ""))
```
---
```output
/bin/sh
0
```

### xargs appends stdin words

```cu
(display (cu-run (list "xargs" "echo" "got") "a b\nc\n"))
```
---
```output
got a b c
0
```

### printenv answers PATH nonempty, misses missing

```cu
(do (display (if (= (byte-len (sys-getenv "PATH")) 0) "empty" "set")) (newline) (display (cu-run (list "printenv" "X_CU_NO_SUCH_VAR") "")))
```
---
```output
set
1
```

### date +%s is all digits

```cu
(do (def out (date-now-unix)) (display (if (> out 1700000000) "plausible" "odd")))
```
---
    plausible
