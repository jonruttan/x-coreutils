# @weight 4

The applets that ride a door x-lang opened for this bundle: chmod,
chown, chgrp, ln, link, readlink, realpath, mkfifo, df, sync, id,
whoami, logname, groups, uname, arch, nproc, nice and chroot.

These need x-lang NEWER than the release lang.xon pins.  Where the
answer is a fact of this machine -- a uid, a processor count, a
filesystem's size -- the spec asserts SHAPE; where it is a fact of the
POSIX contract, it asserts the value.

## fixtures

### a directory to work in, and a way to read an applet's output back

An applet writes to stdout; a spec that must COMPARE that output needs
it as a value.  fd 1 is parked on fd 9, pointed at a file for the run,
and put back -- the dup2 door the bundle already carries, used the way
a shell uses it.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-dr && mkdir -p /tmp/x-cu-dr/sub")) (file-write-all "/tmp/x-cu-dr/f" "body") (def cu-out (fn (_ argv) (do (sys-dup2 1 9) (let ((fd (file-open-write "/tmp/x-cu-dr/.cap"))) (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1) (file-close fd) (file-read-all "/tmp/x-cu-dr/.cap")))))) (display "made"))
```
---
    made

## modes

### chmod takes an octal mode

```cu
(do (cu-run (list "chmod" "600" "/tmp/x-cu-dr/f") "") (display (cu-run (list "stat" "-c" "%a %A" "/tmp/x-cu-dr/f") "")))
```
---
```output
600 -rw-------
0
```

### chmod takes a symbolic mode, and the who selects the triple

```cu
(do (cu-run (list "chmod" "600" "/tmp/x-cu-dr/f") "") (cu-run (list "chmod" "u+x" "/tmp/x-cu-dr/f") "") (display (cu-run (list "stat" "-c" "%a" "/tmp/x-cu-dr/f") "")) (cu-run (list "chmod" "go+r" "/tmp/x-cu-dr/f") "") (display (cu-run (list "stat" "-c" "%a" "/tmp/x-cu-dr/f") "")) (cu-run (list "chmod" "a=r" "/tmp/x-cu-dr/f") "") (display (cu-run (list "stat" "-c" "%a" "/tmp/x-cu-dr/f") "")))
```
---
```output
700
0744
0444
0
```

### chmod -R reaches into a directory

```cu
(do (file-write-all "/tmp/x-cu-dr/sub/deep" "x") (cu-run (list "chmod" "-R" "700" "/tmp/x-cu-dr/sub") "") (display (cu-run (list "stat" "-c" "%a" "/tmp/x-cu-dr/sub/deep") "")))
```
---
```output
700
0
```

### chmod refuses a path that is not there

```cu
(display (cu-run (list "chmod" "644" "/tmp/x-cu-dr/nope") ""))
```
---
    1

### chgrp sets the group stat reads back

```cu
(do (cu-run (list "chgrp" (%cu-int->str (sys-getegid)) "/tmp/x-cu-dr/f") "") (display (if (= (%cu-stat-get (file-stat-full "/tmp/x-cu-dr/f") (lit gid)) (sys-getegid)) "same" "different")))
```
---
    same

## links

### ln -s writes a link readlink reads back

```cu
(do (cu-run (list "ln" "-s" "/tmp/x-cu-dr/f" "/tmp/x-cu-dr/l") "") (display (cu-run (list "readlink" "/tmp/x-cu-dr/l") "")) (display (cu-run (list "stat" "-c" "%F" "/tmp/x-cu-dr/l") "")))
```
---
```output
/tmp/x-cu-dr/f
0regular file
0
```

### readlink refuses something that is not a link

```cu
(display (cu-run (list "readlink" "/tmp/x-cu-dr/f") ""))
```
---
    1

### ln makes a hard link that outlives the first name

```cu
(do (file-write-all "/tmp/x-cu-dr/h1" "shared") (cu-run (list "link" "/tmp/x-cu-dr/h1" "/tmp/x-cu-dr/h2") "") (cu-run (list "rm" "/tmp/x-cu-dr/h1") "") (display (file-read-all "/tmp/x-cu-dr/h2")))
```
---
    shared

### ln -f replaces a name already taken

```cu
(do (file-write-all "/tmp/x-cu-dr/taken" "old") (display (cu-run (list "ln" "-s" "-f" "/tmp/x-cu-dr/f" "/tmp/x-cu-dr/taken") "")) (display (cu-run (list "readlink" "/tmp/x-cu-dr/taken") "")))
```
---
```output
0/tmp/x-cu-dr/f
0
```

### realpath folds . and .. and resolves every link in the path

The ANSWER is a fact of this machine -- on macOS /tmp is itself a link
into /private -- so the three spellings are compared with each other
rather than against a literal.

```cu
(do (def a (cu-out (list "realpath" "/tmp/x-cu-dr/sub/../f"))) (def b (cu-out (list "realpath" "/tmp/x-cu-dr/l"))) (def c (cu-out (list "readlink" "-f" "/tmp/x-cu-dr/l"))) (display (if (if (string=? a b) (string=? b c) #f) "same" "different")) (newline) (display (= (byte-at a 0) 47)))
```
---
```output
same
#t
```

### realpath refuses a path that is not there

```cu
(display (cu-run (list "realpath" "/tmp/x-cu-dr/nope") ""))
```
---
    1

## the filesystem

### mkfifo makes a path whose type is a fifo

```cu
(do (cu-run (list "mkfifo" "/tmp/x-cu-dr/pipe") "") (display (cu-run (list "stat" "-c" "%F" "/tmp/x-cu-dr/pipe") "")))
```
---
```output
fifo
0
```

### df measures the filesystem a path sits on

```cu
(display (cu-run (list "df" "-Q") ""))
```
---
    2

### sync returns cleanly

```cu
(display (cu-run (list "sync") ""))
```
---
    0

## identity and the machine

### id -u is the effective uid, and whoami names it

```cu
(do (display (if (string=? (cu-out (list "id" "-u")) (string-append (%cu-int->str (sys-geteuid)) "\n")) "same" "different")) (newline) (display (> (byte-len (cu-out (list "whoami"))) 1)))
```
---
```output
same
#t
```

### uname names this system, and arch is its machine

```cu
(do (display (if (string=? (cu-out (list "uname")) (string-append (%cu-uname-field (sys-uname) (lit sysname)) "\n")) "named" "wrong")) (newline) (display (if (string=? (cu-out (list "arch")) (cu-out (list "uname" "-m"))) "same" "different")))
```
---
```output
named
same
```

### nproc counts at least one processor

```cu
(display (>= (%cu-num-prefix (cu-out (list "nproc"))) 1))
```
---
    #t

### groups lists the effective group among them

```cu
(display (> (byte-len (cu-out (list "groups"))) 1))
```
---
    #t

### the option guard reaches the door applets too

```cu
(do (display (cu-run (list "chmod" "-Q" "644" "/tmp/x-cu-dr/f") "")) (display (cu-run (list "uname" "-Q") "")) (display (cu-run (list "id" "-Q") "")))
```
---
    222

## cleanup

### tidy up

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-dr")) (display "clean"))
```
---
    clean
