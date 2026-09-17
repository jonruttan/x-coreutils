# @weight 2

chmod's reports and complaints: -v reports every path and what became of its
mode, -c only a path whose mode changed, and -f keeps the complaints off stderr.
The expected text is GNU chmod's for the same paths.  The setuid, setgid and
sticky bits are spelled as ls -l and stat %A spell them, so those are here too.

## the fixtures

### a scratch directory, and readers for stdout, stderr and the status

cm runs chmod with stdout and stderr each parked on a file, then shows both and
the status, in that order.

```cu
(do (proc-run (list "/bin/sh" "-c" "chmod -R u+rwx /tmp/x-cu-chm 2>/dev/null; rm -rf /tmp/x-cu-chm && mkdir -p /tmp/x-cu-chm && cd /tmp/x-cu-chm && : > f && chmod 644 f")) (def chm (fn (_ n) (string-append "/tmp/x-cu-chm/" n))) (def cm (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((o (file-open-write (chm ".out"))) (e (file-open-write (chm ".err")))) (do (sys-dup2 o 1) (sys-dup2 e 2) (def cm-st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close o) (file-close e) (display (file-read-all (chm ".out"))) (display "stderr:\n") (display (file-read-all (chm ".err"))) (display "status ") (display cm-st) (newline)))))) (def cu-out (fn (_ argv) (do (sys-dup2 1 9) (let ((fd (file-open-write (chm ".out")))) (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1) (file-close fd) (file-read-all (chm ".out"))))))) (display "made"))
```
---
    made

## the reports

### -v reports a change, and a mode kept as it was

```cu
(do (cm (list "chmod" "-v" "755" (chm "f"))) (cm (list "chmod" "-v" "755" (chm "f"))))
```
---
```output
mode of '/tmp/x-cu-chm/f' changed from 0644 (rw-r--r--) to 0755 (rwxr-xr-x)
stderr:
status 0
mode of '/tmp/x-cu-chm/f' retained as 0755 (rwxr-xr-x)
stderr:
status 0
```

### -c reports only a change

```cu
(do (cm (list "chmod" "-c" "755" (chm "f"))) (cm (list "chmod" "-c" "700" (chm "f"))))
```
---
```output
stderr:
status 0
mode of '/tmp/x-cu-chm/f' changed from 0755 (rwxr-xr-x) to 0700 (rwx------)
stderr:
status 0
```

### the later of -c and -v wins

```cu
(do (cm (list "chmod" "-c" "-v" "700" (chm "f"))) (cm (list "chmod" "-v" "-c" "700" (chm "f"))))
```
---
```output
mode of '/tmp/x-cu-chm/f' retained as 0700 (rwx------)
stderr:
status 0
stderr:
status 0
```

### the setuid and sticky bits, in a report

```cu
(do (cm (list "chmod" "-v" "4644" (chm "f"))) (proc-run (list "/bin/sh" "-c" "mkdir /tmp/x-cu-chm/d && chmod 755 /tmp/x-cu-chm/d")) (cm (list "chmod" "-v" "1777" (chm "d"))))
```
---
```output
mode of '/tmp/x-cu-chm/f' changed from 0700 (rwx------) to 4644 (rwSr--r--)
stderr:
status 0
mode of '/tmp/x-cu-chm/d' changed from 0755 (rwxr-xr-x) to 1777 (rwxrwxrwt)
stderr:
status 0
```

### stat and ls -l spell them the same way, and stat's Access line has four digits

```cu
(do (proc-run (list "/bin/sh" "-c" "cd /tmp/x-cu-chm && : > s && chmod 4755 s && : > n && chmod 1776 n && : > p && chmod 644 p")) (display (cu-out (list "stat" "-c" "%a %A" (chm "f") (chm "s") (chm "n") (chm "d")))) (display (substring (cu-out (list "ls" "-ld" (chm "n"))) 0 10)) (newline) (display (substring (%cu-nth 3 (%cu-lines (cu-out (list "stat" (chm "p"))))) 0 25)) (newline))
```
---
```output
4644 -rwSr--r--
4755 -rwsr-xr-x
1776 -rwxrwxrwT
1777 drwxrwxrwt
-rwxrwxrwT
Access: (0644/-rw-r--r--)
```

## the failures

### a path that is not there: the complaint, and under -v a report

```cu
(do (cm (list "chmod" "644" (chm "nope"))) (cm (list "chmod" "-v" "644" (chm "nope"))) (cm (list "chmod" "-c" "644" (chm "nope"))))
```
---
```output
stderr:
chmod: cannot access '/tmp/x-cu-chm/nope': No such file or directory
status 1
'/tmp/x-cu-chm/nope' could not be accessed
stderr:
chmod: cannot access '/tmp/x-cu-chm/nope': No such file or directory
status 1
stderr:
chmod: cannot access '/tmp/x-cu-chm/nope': No such file or directory
status 1
```

### -f keeps the complaint off stderr, and the status still says it failed

```cu
(do (cm (list "chmod" "-f" "644" (chm "nope"))) (cm (list "chmod" "-v" "-f" "644" (chm "nope"))))
```
---
```output
stderr:
status 1
'/tmp/x-cu-chm/nope' could not be accessed
stderr:
status 1
```

### a link to nothing is named as one

```cu
(do (proc-run (list "/bin/sh" "-c" "ln -s /tmp/x-cu-chm/nowhere /tmp/x-cu-chm/dang")) (cm (list "chmod" "644" (chm "dang"))) (cm (list "chmod" "-v" "-f" "644" (chm "dang"))))
```
---
```output
stderr:
chmod: cannot operate on dangling symlink '/tmp/x-cu-chm/dang'
status 1
'/tmp/x-cu-chm/dang' could not be accessed
stderr:
status 1
```

### a mode the system will not set

/ belongs to root and is 0755, so this is the refusal when the suite runs as
anyone else.  -v reports the failure even though the mode asked for is the one
it has.

```cu
(do (cm (list "chmod" "-v" "755" "/")) (cm (list "chmod" "-c" "755" "/")) (cm (list "chmod" "-f" "755" "/")))
```
---
```output
failed to change mode of '/' from 0755 (rwxr-xr-x) to 0755 (rwxr-xr-x)
stderr:
chmod: changing permissions of '/': Operation not permitted
status 1
stderr:
chmod: changing permissions of '/': Operation not permitted
status 1
stderr:
status 1
```

### every operand is tried, and one failure fails the run

```cu
(do (proc-run (list "/bin/sh" "-c" "chmod 644 /tmp/x-cu-chm/f")) (cm (list "chmod" "-v" "600" (chm "nope") (chm "f"))))
```
---
```output
'/tmp/x-cu-chm/nope' could not be accessed
mode of '/tmp/x-cu-chm/f' changed from 0644 (rw-r--r--) to 0600 (rw-------)
stderr:
chmod: cannot access '/tmp/x-cu-chm/nope': No such file or directory
status 1
```

## -R

### a directory is reported before its entries

The entries are visited in sorted order (cu/walk.x), where GNU chmod takes the
directory's own order.

```cu
(do (proc-run (list "/bin/sh" "-c" "cd /tmp/x-cu-chm && mkdir -p t/sub && : > t/a && : > t/sub/b && chmod 755 t t/sub && chmod 644 t/a t/sub/b")) (cm (list "chmod" "-R" "-v" "700" (chm "t"))))
```
---
```output
mode of '/tmp/x-cu-chm/t' changed from 0755 (rwxr-xr-x) to 0700 (rwx------)
mode of '/tmp/x-cu-chm/t/a' changed from 0644 (rw-r--r--) to 0700 (rwx------)
mode of '/tmp/x-cu-chm/t/sub' changed from 0755 (rwxr-xr-x) to 0700 (rwx------)
mode of '/tmp/x-cu-chm/t/sub/b' changed from 0644 (rw-r--r--) to 0700 (rwx------)
stderr:
status 0
```

### a directory's mode is set before it is read, so its entries may be out of reach

```cu
(do (proc-run (list "/bin/sh" "-c" "chmod -R 755 /tmp/x-cu-chm/t")) (cm (list "chmod" "-R" "-v" "600" (chm "t"))) (proc-run (list "/bin/sh" "-c" "chmod 755 /tmp/x-cu-chm/t")) (display "restored"))
```
---
```output
mode of '/tmp/x-cu-chm/t' changed from 0755 (rwxr-xr-x) to 0600 (rw-------)
'/tmp/x-cu-chm/t/a' could not be accessed
'/tmp/x-cu-chm/t/sub' could not be accessed
stderr:
chmod: cannot access '/tmp/x-cu-chm/t/a': Permission denied
chmod: cannot access '/tmp/x-cu-chm/t/sub': Permission denied
status 1
restored
```

### or the directory itself may be

```cu
(do (proc-run (list "/bin/sh" "-c" "chmod -R 755 /tmp/x-cu-chm/t")) (cm (list "chmod" "-R" "-v" "000" (chm "t"))) (proc-run (list "/bin/sh" "-c" "chmod 755 /tmp/x-cu-chm/t")) (display "restored"))
```
---
```output
mode of '/tmp/x-cu-chm/t' changed from 0755 (rwxr-xr-x) to 0000 (---------)
'/tmp/x-cu-chm/t' could not be accessed
stderr:
chmod: cannot read directory '/tmp/x-cu-chm/t': Permission denied
status 1
restored
```
