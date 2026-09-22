# @weight 2

chown's and chgrp's reports and complaints: -v reports every path and what
became of its ids, -c only a path whose ids changed, and -f keeps the
complaints off stderr while the status still says a path failed.  The expected
text is GNU chown's and chgrp's for the same paths.

Which ids and names a machine hands out is its own business, so every report
below is shown with what it named written back: USER and UID for the user's
name and id, OLDGROUP for the name of the group a new file gets, GROUP for the
name of the user's group and G for its id as the spec gives it.  A report
naming anything else keeps it as it is and fails its case.  A report shows the
ids asked for as they were written, and the path's own by name.  The cases are
an ordinary user's: they take it that the runner is not root and that /tmp
gives a new file a group of its own.

## the fixtures

### a scratch tree, the ids, and a reader for stdout, stderr and the status

co runs an applet with stdout and stderr each parked on a file, then shows
both and the status, in that order.

```cu
(do (proc-run (list "/bin/sh" "-c" "chmod -R u+rwx /tmp/x-cu-cho 2>/dev/null; rm -rf /tmp/x-cu-cho && mkdir -p /tmp/x-cu-cho/d/sub && cd /tmp/x-cu-cho && : > f && : > f2 && : > f3 && : > f4 && : > t && : > t2 && ln -s t lk && ln -s t2 lk2 && : > d/b && : > d/sub/a")) (def ch (fn (_ n) (string-append "/tmp/x-cu-cho/" n))) (def u (%cu-int->str (sys-geteuid))) (def g (%cu-int->str (sys-getegid))) (def named (fn (_ n id) (if (null? n) (%cu-int->str id) n))) (def un (named (sys-user-name (sys-geteuid)) (sys-geteuid))) (def gn (named (sys-group-name (sys-getegid)) (sys-getegid))) (def on (let ((gid (%cu-stat-get (file-stat-full (ch "f")) (lit gid)))) (named (sys-group-name gid) gid))) (def show (fn (_ s) (Str8 replace (string-concat (list " to " g "\n")) " to G\n" (Str8 replace (string-concat (list "retained as " gn)) "retained as GROUP" (Str8 replace (string-concat (list "from " on " to " g)) "from OLDGROUP to G" (Str8 replace (string-concat (list "from " un " to 0")) "from USER to 0" (Str8 replace (string-concat (list "from " un ":" on " to " u ":" g)) "from USER:OLDGROUP to UID:G" s))))))) (def co (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (ch ".out"))) (ee (file-open-write (ch ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def co-st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (show (file-read-all (ch ".out")))) (display "stderr:\n") (display (show (file-read-all (ch ".err")))) (display "status ") (display co-st) (newline)))))) (display "made"))
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
changed group of '/tmp/x-cu-cho/f' from OLDGROUP to G
stderr:
status 0
```

### the same group again is retained, not changed

```cu
(co (list "chgrp" "-v" g (ch "f")))
```
---
```output
group of '/tmp/x-cu-cho/f' retained as GROUP
stderr:
status 0
```

### -c reports only a change

```cu
(do (co (list "chgrp" "-c" g (ch "f2"))) (co (list "chgrp" "-c" g (ch "f2"))))
```
---
```output
changed group of '/tmp/x-cu-cho/f2' from OLDGROUP to G
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
group of '/tmp/x-cu-cho/f2' retained as GROUP
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
changed group of '/tmp/x-cu-cho/f3' from OLDGROUP to G
stderr:
status 0
changed ownership of '/tmp/x-cu-cho/f4' from USER:OLDGROUP to UID:G
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
failed to change group of '/tmp/x-cu-cho/nope' to G
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
failed to change group of '/tmp/x-cu-cho/nope' to G
stderr:
status 1
```

### an id the caller may not set: the report names both, the complaint the reason

```cu
(co (list "chown" "-v" "0" (ch "f")))
```
---
```output
failed to change ownership of '/tmp/x-cu-cho/f' from USER to 0
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
changed group of '/tmp/x-cu-cho/d/b' from OLDGROUP to G
changed group of '/tmp/x-cu-cho/d/sub/a' from OLDGROUP to G
changed group of '/tmp/x-cu-cho/d/sub' from OLDGROUP to G
changed group of '/tmp/x-cu-cho/d' from OLDGROUP to G
stderr:
status 0
```

### a directory whose entries cannot be read is left as it was

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-cho/e && mkdir -p /tmp/x-cu-cho/e/sub && : > /tmp/x-cu-cho/e/b && : > /tmp/x-cu-cho/e/sub/a && chmod 000 /tmp/x-cu-cho/e/sub")) (co (list "chgrp" "-R" "-v" g (ch "e"))) (proc-run (list "/bin/sh" "-c" "chmod 755 /tmp/x-cu-cho/e/sub")) (display (if (= (%cu-stat-get (file-stat-full (ch "e/sub")) (lit gid)) (sys-getegid)) "the directory changed" "the directory was left")) (newline))
```
---
```output
changed group of '/tmp/x-cu-cho/e/b' from OLDGROUP to G
failed to change group of '/tmp/x-cu-cho/e/sub' to G
changed group of '/tmp/x-cu-cho/e' from OLDGROUP to G
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
changed group of '/tmp/x-cu-cho/lk' from OLDGROUP to G
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
changed group of '/tmp/x-cu-cho/lk2' from OLDGROUP to G
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
changed group of '/tmp/x-cu-cho/w/inside/a' from OLDGROUP to G
changed group of '/tmp/x-cu-cho/w/inside' from OLDGROUP to G
changed group of '/tmp/x-cu-cho/w/lk' from OLDGROUP to G
changed group of '/tmp/x-cu-cho/w' from OLDGROUP to G
stderr:
status 0
the link changed
the tree it points at was left
```
