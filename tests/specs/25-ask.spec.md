# @weight 2

Which of -f, -i and -n decides, what cp, mv and rm ask, and what a question
answered no comes to.  mv takes the last of -f, -i and -n, and rm the last of
-f and -i; cp's -f does not take over from -i.  A no is a failure for cp and
mv, and none for rm.  The expected text and statuses are GNU's for the same
files.

There is no terminal here to answer, so every question is answered no -- and,
as GNU leaves it when its input ends, stands unended on stderr.

## the fixtures

### a scratch directory, and readers for what was said and what is left

```cu
(do (def ask (fn (_ n) (string-append "/tmp/x-cu-ask/" n))) (def mk (fn (_) (proc-run (list "/bin/sh" "-c" "chmod -R u+rwx /tmp/x-cu-ask 2>/dev/null; rm -rf /tmp/x-cu-ask && mkdir -p /tmp/x-cu-ask/full /tmp/x-cu-ask/empty && cd /tmp/x-cu-ask && printf new > a && printf old > b && : > e && printf x > f && ln -s f l && mkfifo p && : > full/x")))) (mk) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (ask ".out"))) (ee (file-open-write (ask ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def run-st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (Str8 replace "/tmp/x-cu-ask/" "" (file-read-all (ask ".out")))) (display (string-append "[" (Str8 replace "/tmp/x-cu-ask/" "" (file-read-all (ask ".err"))) "]\n")) (display "status ") (display run-st) (newline)))))) (def b-is (fn (_) (display (string-append "b holds " (first (%cu-lines (file-read-all (ask "b")))) "\n")))) (def there (fn (_ ps) (display (string-append (%cu-join-with (map (fn (_ p) (string-append p (if (eq? (file-lstat-kind (ask p)) (lit none)) " gone" " there"))) ps) ", ") "\n")))) (display "made"))
```
---
    made

## mv

### told nothing, mv moves over what is there

```cu
(do (mk) (run (list "mv" (ask "a") (ask "b"))) (b-is))
```
---
```output
[]
status 0
b holds new
```

### -i asks, and a no leaves both names as they were and fails

```cu
(do (mk) (run (list "mv" "-i" (ask "a") (ask "b"))) (b-is) (there (list "a")))
```
---
```output
[mv: overwrite 'b'? ]
status 1
b holds old
a there
```

### the last of -f and -i says whether to ask

```cu
(do (mk) (run (list "mv" "-i" "-f" (ask "a") (ask "b"))) (b-is) (mk) (run (list "mv" "-f" "-i" (ask "a") (ask "b"))) (b-is))
```
---
```output
[]
status 0
b holds new
[mv: overwrite 'b'? ]
status 1
b holds old
```

### and the last of -f, -i and -n whether to move at all

```cu
(do (mk) (run (list "mv" "-n" "-f" (ask "a") (ask "b"))) (b-is) (mk) (run (list "mv" "-f" "-n" (ask "a") (ask "b"))) (b-is) (mk) (run (list "mv" "-i" "-n" (ask "a") (ask "b"))) (b-is) (mk) (run (list "mv" "-n" "-i" (ask "a") (ask "b"))) (b-is))
```
---
```output
[]
status 0
b holds new
[]
status 0
b holds old
[]
status 0
b holds old
[mv: overwrite 'b'? ]
status 1
b holds old
```

## cp

### -i asks, a no fails, and -f does not take over from it

```cu
(do (mk) (run (list "cp" "-i" (ask "a") (ask "b"))) (b-is) (run (list "cp" "-i" "-f" (ask "a") (ask "b"))) (run (list "cp" "-f" "-i" (ask "a") (ask "b"))) (b-is))
```
---
```output
[cp: overwrite 'b'? ]
status 1
b holds old
[cp: overwrite 'b'? ]
status 1
[cp: overwrite 'b'? ]
status 1
b holds old
```

## rm

### -i asks about each path in the words for what it is, and a no is no failure

```cu
(do (mk) (run (list "rm" "-i" (ask "e") (ask "f") (ask "l") (ask "p"))) (there (list "e" "f" "l" "p")))
```
---
```output
[rm: remove regular empty file 'e'? rm: remove regular file 'f'? rm: remove symbolic link 'l'? rm: remove fifo 'p'? ]
status 0
e there, f there, l there, p there
```

### the last of -f and -i says whether to ask

```cu
(do (mk) (run (list "rm" "-i" "-f" (ask "e") (ask "f"))) (there (list "e" "f")) (mk) (run (list "rm" "-f" "-i" (ask "e") (ask "f"))) (there (list "e" "f")))
```
---
```output
[]
status 0
e gone, f gone
[rm: remove regular empty file 'e'? rm: remove regular file 'f'? ]
status 0
e there, f there
```

### -f passes over a path that is not there, until -i takes over from it

```cu
(do (run (list "rm" "-i" "-f" (ask "nope"))) (run (list "rm" "-f" "-i" (ask "nope"))) (run (list "rm" (ask "nope"))))
```
---
```output
[]
status 0
[rm: cannot remove 'nope': No such file or directory
]
status 1
[rm: cannot remove 'nope': No such file or directory
]
status 1
```

### -i asks to remove an empty directory, and to go into one that holds anything

```cu
(do (mk) (run (list "rm" "-i" "-r" (ask "empty") (ask "full"))) (there (list "empty" "full" "full/x")))
```
---
```output
[rm: remove directory 'empty'? rm: descend into directory 'full'? ]
status 0
empty there, full there, full/x there
```

### -v says a directory is one

```cu
(do (mk) (run (list "rm" "-r" "-v" (ask "full"))))
```
---
```output
removed 'full/x'
removed directory 'full'
[]
status 0
```

### a removal refused is said, and leaves the directory holding it

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-ask/ro && mkdir -p /tmp/x-cu-ask/ro && : > /tmp/x-cu-ask/ro/f && chmod 555 /tmp/x-cu-ask/ro")) (run (list "rm" (ask "ro/f"))) (run (list "rm" "-r" (ask "ro"))) (proc-run (list "/bin/sh" "-c" "chmod 755 /tmp/x-cu-ask/ro")) (there (list "ro" "ro/f")))
```
---
```output
[rm: cannot remove 'ro/f': Permission denied
]
status 1
[rm: cannot remove 'ro/f': Permission denied
]
status 1
ro there, ro/f there
```

### a directory it cannot read is said, and left

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-ask/u && mkdir -p /tmp/x-cu-ask/u/in && : > /tmp/x-cu-ask/u/in/f && chmod 000 /tmp/x-cu-ask/u/in")) (run (list "rm" "-r" (ask "u"))) (proc-run (list "/bin/sh" "-c" "chmod 755 /tmp/x-cu-ask/u/in")) (there (list "u" "u/in" "u/in/f")))
```
---
```output
[rm: cannot remove 'u/in': Permission denied
]
status 1
u there, u/in there, u/in/f there
```
