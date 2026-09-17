# @weight 2

chown's and chgrp's reports and complaints: -v reports every path and what
became of its ids, -c only a path whose ids changed, and -f keeps the
complaints off stderr while the status still says a path failed.  The expected
text is GNU chown's and chgrp's for the same paths.

Which ids a machine hands out is its own business, so every report below is
shown with the ids it named written back as OLD, NEW and U -- a report naming
an id it was not asked for keeps its digits and fails its case.  The cases are
an ordinary user's: they take it that the runner is not root and that /tmp
gives a new file a group of its own.

## the fixtures

### a scratch tree, the ids, and a reader for stdout, stderr and the status

co runs an applet with stdout and stderr each parked on a file, then shows
both and the status, in that order.

```cu
(do (proc-run (list "/bin/sh" "-c" "chmod -R u+rwx /tmp/x-cu-cho 2>/dev/null; rm -rf /tmp/x-cu-cho && mkdir -p /tmp/x-cu-cho/d/sub && cd /tmp/x-cu-cho && : > f && : > f2 && : > f3 && : > f4 && : > t && : > t2 && ln -s t lk && ln -s t2 lk2 && : > d/b && : > d/sub/a")) (def ch (fn (_ n) (string-append "/tmp/x-cu-cho/" n))) (def u (%cu-int->str (sys-geteuid))) (def g (%cu-int->str (sys-getegid))) (def o (%cu-int->str (%cu-stat-get (file-stat-full (ch "f")) (lit gid)))) (def show (fn (_ s) (Str8 replace (string-concat (list " to " g "\n")) " to NEW\n" (Str8 replace (string-concat (list "retained as " g)) "retained as NEW" (Str8 replace (string-concat (list "from " u " to 0")) "from U to 0" (Str8 replace (string-concat (list "from " u ":" o " to " u ":" g)) "from U:OLD to U:NEW" (Str8 replace (string-concat (list "from " o " to " g)) "from OLD to NEW" s))))))) (def co (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (ch ".out"))) (ee (file-open-write (ch ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def co-st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (show (file-read-all (ch ".out")))) (display "stderr:\n") (display (show (file-read-all (ch ".err")))) (display "status ") (display co-st) (newline)))))) (display "made"))
```
---
    made

## the reports

### -v names the group, and what it was and became

```cu
(co (list "chgrp" "-v" g (ch "f")))
```
---
```output
changed group of '/tmp/x-cu-cho/f' from OLD to NEW
stderr:
status 0
```

### the same group again is retained, not changed

```cu
(co (list "chgrp" "-v" g (ch "f")))
```
---
```output
group of '/tmp/x-cu-cho/f' retained as NEW
stderr:
status 0
```

### -c reports only a change

```cu
(do (co (list "chgrp" "-c" g (ch "f2"))) (co (list "chgrp" "-c" g (ch "f2"))))
```
---
```output
changed group of '/tmp/x-cu-cho/f2' from OLD to NEW
stderr:
status 0
stderr:
status 0
```

### the later of -c and -v wins, as it does for chmod

```cu
(do (co (list "chgrp" "-c" "-v" g (ch "f2"))) (co (list "chgrp" "-v" "-c" g (ch "f2"))))
```
---
```output
group of '/tmp/x-cu-cho/f2' retained as NEW
stderr:
status 0
stderr:
status 0
```

### chown names a group where only a group was asked for, and both where the spec named the two

```cu
(do (co (list "chown" "-v" (string-append ":" g) (ch "f3"))) (co (list "chown" "-v" (string-append u ":" g) (ch "f4"))))
```
---
```output
changed group of '/tmp/x-cu-cho/f3' from OLD to NEW
stderr:
status 0
changed ownership of '/tmp/x-cu-cho/f4' from U:OLD to U:NEW
stderr:
status 0
```

## the complaints

### a path that is not there: the reason on stderr, and under -v the ids it never reached

```cu
(co (list "chgrp" "-v" g (ch "nope")))
```
---
```output
failed to change group of '/tmp/x-cu-cho/nope' to NEW
stderr:
chgrp: cannot access '/tmp/x-cu-cho/nope': No such file or directory
status 1
```

### -f keeps the complaint off stderr, and the status still says it failed

```cu
(co (list "chgrp" "-f" "-v" g (ch "nope")))
```
---
```output
failed to change group of '/tmp/x-cu-cho/nope' to NEW
stderr:
status 1
```

### an id the caller may not set: the report names both, the complaint the reason

```cu
(co (list "chown" "-v" "0" (ch "f")))
```
---
```output
failed to change ownership of '/tmp/x-cu-cho/f' from U to 0
stderr:
chown: changing ownership of '/tmp/x-cu-cho/f': Operation not permitted
status 1
```

## -R, and what it will not touch

### the entries of a directory are changed before the directory itself

```cu
(co (list "chgrp" "-R" "-v" g (ch "d")))
```
---
```output
changed group of '/tmp/x-cu-cho/d/b' from OLD to NEW
changed group of '/tmp/x-cu-cho/d/sub/a' from OLD to NEW
changed group of '/tmp/x-cu-cho/d/sub' from OLD to NEW
changed group of '/tmp/x-cu-cho/d' from OLD to NEW
stderr:
status 0
```

### a directory whose entries cannot be read is left as it was

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-cho/e && mkdir -p /tmp/x-cu-cho/e/sub && : > /tmp/x-cu-cho/e/b && : > /tmp/x-cu-cho/e/sub/a && chmod 000 /tmp/x-cu-cho/e/sub")) (co (list "chgrp" "-R" "-v" g (ch "e"))) (proc-run (list "/bin/sh" "-c" "chmod 755 /tmp/x-cu-cho/e/sub")) (display (if (= (%cu-stat-get (file-stat-full (ch "e/sub")) (lit gid)) (sys-getegid)) "the directory changed" "the directory was left")) (newline))
```
---
```output
changed group of '/tmp/x-cu-cho/e/b' from OLD to NEW
failed to change group of '/tmp/x-cu-cho/e/sub' to NEW
changed group of '/tmp/x-cu-cho/e' from OLD to NEW
stderr:
chgrp: cannot read directory '/tmp/x-cu-cho/e/sub': Permission denied
status 1
the directory was left
```

## links

### a symlink is followed, as chown follows one

```cu
(do (co (list "chgrp" "-v" g (ch "lk"))) (display (if (= (%cu-stat-get (file-stat-full (ch "t")) (lit gid)) (sys-getegid)) "the target changed" "the target was left")) (newline))
```
---
```output
changed group of '/tmp/x-cu-cho/lk' from OLD to NEW
stderr:
status 0
the target changed
```

### -h changes the link itself, and leaves what it points at alone

```cu
(do (co (list "chgrp" "-h" "-v" g (ch "lk2"))) (display (if (= (%cu-stat-get (file-lstat-full (ch "lk2")) (lit gid)) (sys-getegid)) "the link changed" "the link was left")) (newline) (display (if (= (%cu-stat-get (file-stat-full (ch "t2")) (lit gid)) (sys-getegid)) "the target changed" "the target was left")) (newline))
```
---
```output
changed group of '/tmp/x-cu-cho/lk2' from OLD to NEW
stderr:
status 0
the link changed
the target was left
```

### -R changes a link it meets and does not walk through it

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-cho/w /tmp/x-cu-cho/outside && mkdir -p /tmp/x-cu-cho/w/inside /tmp/x-cu-cho/outside && : > /tmp/x-cu-cho/w/inside/a && : > /tmp/x-cu-cho/outside/b && ln -s ../outside /tmp/x-cu-cho/w/lk")) (co (list "chgrp" "-R" "-v" g (ch "w"))) (display (if (= (%cu-stat-get (file-lstat-full (ch "w/lk")) (lit gid)) (sys-getegid)) "the link changed" "the link was left")) (newline) (display (if (= (%cu-stat-get (file-stat-full (ch "outside/b")) (lit gid)) (sys-getegid)) "the tree it points at changed" "the tree it points at was left")) (newline))
```
---
```output
changed group of '/tmp/x-cu-cho/w/inside/a' from OLD to NEW
changed group of '/tmp/x-cu-cho/w/inside' from OLD to NEW
changed group of '/tmp/x-cu-cho/w/lk' from OLD to NEW
changed group of '/tmp/x-cu-cho/w' from OLD to NEW
stderr:
status 0
the link changed
the tree it points at was left
```
