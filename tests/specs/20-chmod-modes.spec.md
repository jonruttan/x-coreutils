# @weight 2

chmod's modes: the symbolic grammar, what a directory keeps, and what chmod
refuses.  Each case shows the mode the path ended with, in octal, and the
status.  The expected modes are GNU chmod's for the same mode on the same
starting mode.

## the fixtures

### a scratch directory, and readers that set a mode and show what came of it

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-md && mkdir -p /tmp/x-cu-md")) (def shown (fn (_ p st) (do (display (%cu-oct->str (bit-and (%cu-stat-get (file-stat-full p) (lit mode)) 4095))) (display " status ") (display st) (newline)))) (def mf (fn (_ start mode) (do (proc-run (list "/bin/sh" "-c" (string-concat (list "rm -f /tmp/x-cu-md/f && : > /tmp/x-cu-md/f && chmod " start " /tmp/x-cu-md/f")))) (shown "/tmp/x-cu-md/f" (cu-run (list "chmod" mode "/tmp/x-cu-md/f") ""))))) (def md (fn (_ start mode) (do (proc-run (list "/bin/sh" "-c" (string-concat (list "rm -rf /tmp/x-cu-md/d && mkdir /tmp/x-cu-md/d && chmod " start " /tmp/x-cu-md/d")))) (shown "/tmp/x-cu-md/d" (cu-run (list "chmod" mode "/tmp/x-cu-md/d") ""))))) (display "made"))
```
---
    made

## the symbolic grammar

### the who says which triples a clause touches

```cu
(do (mf "644" "u+x") (mf "644" "go-r") (mf "644" "a+x") (mf "644" "ug=rw"))
```
---
```output
744 status 0
600 status 0
755 status 0
664 status 0
```

### a clause takes more than one op, and a mode more than one clause

```cu
(do (mf "644" "u+r-w") (mf "644" "u+x,g-r") (mf "644" "a=r,u+w"))
```
---
```output
444 status 0
704 status 0
644 status 0
```

### a perm of u, g or o copies that class as it stands

```cu
(do (mf "640" "g=u") (mf "644" "o=u") (mf "750" "g=o"))
```
---
```output
660 status 0
646 status 0
700 status 0
```

### s is setuid with u and setgid with g, t is sticky with o, and = clears them

```cu
(do (mf "644" "u+s") (mf "644" "+t") (mf "644" "u+t") (mf "644" "o+t") (mf "4755" "u=rw") (mf "4755" "u=") (mf "4755" "a=rwx"))
```
---
```output
4644 status 0
1644 status 0
644 status 0
1644 status 0
655 status 0
55 status 0
777 status 0
```

### X is x where one is set already, or on a directory

```cu
(do (mf "644" "a+X") (mf "700" "a+X") (mf "755" "u+X") (md "644" "a+X"))
```
---
```output
644 status 0
711 status 0
755 status 0
755 status 0
```

### an empty perm list clears the class

```cu
(do (mf "644" "o=") (mf "644" "u=rwx,g=rx,o="))
```
---
```output
640 status 0
750 status 0
```

## what a directory keeps

### setuid and setgid survive a mode that does not name them; a file keeps neither

An octal mode of five digits names them, and so does a clause with an s.

```cu
(do (md "4755" "755") (md "4755" "u=rwx") (md "4755" "00755") (md "4755" "u-s") (mf "4755" "755") (mf "4755" "u+w"))
```
---
```output
4755 status 0
4755 status 0
755 status 0
755 status 0
755 status 0
4755 status 0
```

## the umask

### a clause with no who grants nothing the umask holds, where a named who grants it all

The umask is this run's, so the case says what it means rather than a number:
a+w grants w to everyone, and +w grants only what the umask leaves.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -f /tmp/x-cu-md/f && : > /tmp/x-cu-md/f && chmod 644 /tmp/x-cu-md/f")) (cu-run (list "chmod" "+w" "/tmp/x-cu-md/f") "") (display (= (bit-and (%cu-stat-get (file-stat-full "/tmp/x-cu-md/f") (lit mode)) 4095) (bit-or 420 (bit-and 146 (bit-xor (bit-and (sys-umask) 511) 4095))))) (newline) (proc-run (list "/bin/sh" "-c" "chmod 644 /tmp/x-cu-md/f")) (cu-run (list "chmod" "a+w" "/tmp/x-cu-md/f") "") (display (%cu-oct->str (bit-and (%cu-stat-get (file-stat-full "/tmp/x-cu-md/f") (lit mode)) 4095))) (newline))
```
---
```output
#t
666
```

## what chmod refuses

### a mode it cannot read, named, with nothing touched

```cu
(do (mf "644" "zzz") (mf "644" "u+q") (mf "644" "u") (mf "644" "8") (mf "644" "999") (mf "644" "+"))
```
---
```output
644 status 1
644 status 1
644 status 1
644 status 1
644 status 1
644 status 0
```

## cleanup

### the scratch directory goes

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-md")) (display "clean"))
```
---
    clean
