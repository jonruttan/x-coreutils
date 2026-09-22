# @weight 2

What -R does with a symlink is the last of -H, -L and -P: -P, the default,
changes the link itself and goes through none; -H changes what a link points
at and goes through one named on the command line; -L changes what it points
at and goes through every one.  -h still says the link itself changes.  The
expected text is GNU chgrp's for the same trees.

What the reports name is written back through its measured value, as in
21-chown: OLD for the name of the group a new file gets, and NEW for the
user's group -- its id where a report shows the spec, which gives the id, and
its name where a report shows what a path has.  A report naming anything else
keeps it as it is.

## the fixtures

### a tree with a link in it and a link to it, and readers for both

`d/inside/a` and `d/out-link`, which points at `outside/b` beside the tree;
`top-link` points at `d`.  `is` says what became of a path's group, and
`link-is` what became of a link's own.

```cu
(do (def ch (fn (_ n) (string-append "/tmp/x-cu-chl/" n))) (def mk (fn (_) (proc-run (list "/bin/sh" "-c" "chmod -R u+rwx /tmp/x-cu-chl 2>/dev/null; rm -rf /tmp/x-cu-chl && mkdir -p /tmp/x-cu-chl/d/inside /tmp/x-cu-chl/outside && : > /tmp/x-cu-chl/d/inside/a && : > /tmp/x-cu-chl/outside/b && cd /tmp/x-cu-chl/d && ln -s ../outside out-link && cd /tmp/x-cu-chl && ln -s d top-link")))) (mk) (def u (%cu-int->str (sys-geteuid))) (def g (%cu-int->str (sys-getegid))) (def named (fn (_ n id) (if (null? n) (%cu-int->str id) n))) (def gn (named (sys-group-name (sys-getegid)) (sys-getegid))) (def o (let ((gid (%cu-stat-get (file-stat-full (ch "d/inside/a")) (lit gid)))) (named (sys-group-name gid) gid))) (def show (fn (_ s) (Str8 replace (string-concat (list " to " g "\n")) " to NEW\n" (Str8 replace (string-concat (list "retained as " gn)) "retained as NEW" (Str8 replace (string-concat (list "from " o " to " g)) "from OLD to NEW" s))))) (def co (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (ch ".out"))) (ee (file-open-write (ch ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def co-st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (show (file-read-all (ch ".out")))) (display "stderr:\n") (display (show (file-read-all (ch ".err")))) (display "status ") (display co-st) (newline)))))) (def is (fn (_ p) (if (= (%cu-stat-get (file-stat-full (ch p)) (lit gid)) (sys-getegid)) "changed" "left"))) (def link-is (fn (_ p) (if (= (%cu-stat-get (file-lstat-full (ch p)) (lit gid)) (sys-getegid)) "changed" "left"))) (def says (fn (_ ps) (display (string-append (%cu-join-with (map (fn (_ p) (string-concat (list p " " (is p)))) ps) ", ") "\n")))) (display "made"))
```
---
    made

## -H

### a link named on the command line is gone through, and what it points at changes

```cu
(do (mk) (co (list "chgrp" "-R" "-H" "-v" g (ch "top-link"))) (says (list "d" "d/inside" "d/inside/a")) (display (string-append "top-link itself " (link-is "top-link") "\n")))
```
---
```output
changed group of '/tmp/x-cu-chl/top-link/inside/a' from OLD to NEW
changed group of '/tmp/x-cu-chl/top-link/inside' from OLD to NEW
changed group of '/tmp/x-cu-chl/top-link/out-link' from OLD to NEW
changed group of '/tmp/x-cu-chl/top-link' from OLD to NEW
stderr:
status 0
d changed, d/inside changed, d/inside/a changed
top-link itself left
```

### a link met on the walk is not gone through, but what it points at changes

```cu
(do (says (list "outside" "outside/b")) (display (string-append "out-link itself " (link-is "d/out-link") "\n")))
```
---
```output
outside changed, outside/b left
out-link itself left
```

## -L

### every link is gone through

```cu
(do (mk) (co (list "chgrp" "-R" "-L" "-v" g (ch "top-link"))) (says (list "d" "outside" "outside/b")) (display (string-append "out-link itself " (link-is "d/out-link") ", top-link itself " (link-is "top-link") "\n")))
```
---
```output
changed group of '/tmp/x-cu-chl/top-link/inside/a' from OLD to NEW
changed group of '/tmp/x-cu-chl/top-link/inside' from OLD to NEW
changed group of '/tmp/x-cu-chl/top-link/out-link/b' from OLD to NEW
changed group of '/tmp/x-cu-chl/top-link/out-link' from OLD to NEW
changed group of '/tmp/x-cu-chl/top-link' from OLD to NEW
stderr:
status 0
d changed, outside changed, outside/b changed
out-link itself left, top-link itself left
```

### the last of the three wins

```cu
(do (mk) (co (list "chgrp" "-R" "-L" "-P" "-v" g (ch "top-link"))) (says (list "d")) (mk) (co (list "chgrp" "-R" "-P" "-L" "-v" g (ch "top-link"))) (says (list "d" "outside/b")))
```
---
```output
changed group of '/tmp/x-cu-chl/top-link' from OLD to NEW
stderr:
status 0
d left
changed group of '/tmp/x-cu-chl/top-link/inside/a' from OLD to NEW
changed group of '/tmp/x-cu-chl/top-link/inside' from OLD to NEW
changed group of '/tmp/x-cu-chl/top-link/out-link/b' from OLD to NEW
changed group of '/tmp/x-cu-chl/top-link/out-link' from OLD to NEW
changed group of '/tmp/x-cu-chl/top-link' from OLD to NEW
stderr:
status 0
d changed, outside/b changed
```

### -h keeps the link itself as what changes, and -L still goes through it

```cu
(do (mk) (co (list "chgrp" "-R" "-L" "-h" "-v" g (ch "d"))) (says (list "outside" "outside/b")) (display (string-append "out-link itself " (link-is "d/out-link") "\n")))
```
---
```output
changed group of '/tmp/x-cu-chl/d/inside/a' from OLD to NEW
changed group of '/tmp/x-cu-chl/d/inside' from OLD to NEW
changed group of '/tmp/x-cu-chl/d/out-link/b' from OLD to NEW
changed group of '/tmp/x-cu-chl/d/out-link' from OLD to NEW
changed group of '/tmp/x-cu-chl/d' from OLD to NEW
stderr:
status 0
outside left, outside/b changed
out-link itself changed
```

### without -R the three say nothing: a link is followed, as a plain chgrp follows one

```cu
(do (mk) (co (list "chgrp" "-P" "-v" g (ch "top-link"))) (says (list "d")) (display (string-append "top-link itself " (link-is "top-link") "\n")))
```
---
```output
changed group of '/tmp/x-cu-chl/top-link' from OLD to NEW
stderr:
status 0
d changed
top-link itself left
```

## what -L will not walk twice

### a link to a directory the walk is already inside ends the descent there

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-chl/c && mkdir -p /tmp/x-cu-chl/c/sub && : > /tmp/x-cu-chl/c/sub/a && cd /tmp/x-cu-chl/c/sub && ln -s .. up")) (co (list "chgrp" "-R" "-L" "-v" g (ch "c"))) (display (string-append "up itself " (link-is "c/sub/up") "\n")))
```
---
```output
changed group of '/tmp/x-cu-chl/c/sub/a' from OLD to NEW
changed group of '/tmp/x-cu-chl/c/sub/up' from OLD to NEW
changed group of '/tmp/x-cu-chl/c/sub' from OLD to NEW
changed group of '/tmp/x-cu-chl/c' from OLD to NEW
stderr:
status 0
up itself left
```

### two ways to one directory are both walked, the second finding nothing to change

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-chl/t && mkdir -p /tmp/x-cu-chl/t/sub && : > /tmp/x-cu-chl/t/sub/a && cd /tmp/x-cu-chl/t && ln -s sub twin")) (co (list "chgrp" "-R" "-L" "-v" g (ch "t"))))
```
---
```output
changed group of '/tmp/x-cu-chl/t/sub/a' from OLD to NEW
changed group of '/tmp/x-cu-chl/t/sub' from OLD to NEW
group of '/tmp/x-cu-chl/t/twin/a' retained as NEW
group of '/tmp/x-cu-chl/t/twin' retained as NEW
changed group of '/tmp/x-cu-chl/t' from OLD to NEW
stderr:
status 0
```

### a link pointing nowhere, where what it points at is what would change

The report names the ids the link itself has.  GNU's names an id it never
read -- `from daemon`, and an unfilled number for `chown` -- so the wording
is GNU's and the ids are not.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-chl/n && mkdir -p /tmp/x-cu-chl/n && cd /tmp/x-cu-chl/n && ln -s nowhere dead")) (co (list "chgrp" "-R" "-L" "-v" g (ch "n"))) (display (string-append "dead itself " (link-is "n/dead") "\n")))
```
---
```output
failed to change group of '/tmp/x-cu-chl/n/dead' from OLD to NEW
changed group of '/tmp/x-cu-chl/n' from OLD to NEW
stderr:
chgrp: cannot dereference '/tmp/x-cu-chl/n/dead': No such file or directory
status 1
dead itself left
```
