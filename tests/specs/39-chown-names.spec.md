# @weight 1

chown's and chgrp's specs take names as well as numbers.  Each half is a
name the system knows or a number, `+N` always a number; `OWNER:` is the
owner and the owner's login group; `OWNER.GROUP` is read as `OWNER:GROUP`
with a warning; a name the system does not know refuses the spec before any
path is touched.  A report shows the ids asked for as they were written --
where the group is written as a name and the owner is not, chown shows the
owner as nothing -- and a path's own by name.  The expected text is GNU
chown's and chgrp's for the same paths.

The cases are an ordinary user's, as in 21-chown: the runner is not root, and
/tmp gives a new file a group other than the user's own.  Each case builds
what GNU prints from the names measured here, and shows what it got when that
is not what it printed.

## the fixtures

### files, the names, and a runner for stdout, stderr and the status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-chn && mkdir -p /tmp/x-cu-chn && cd /tmp/x-cu-chn && for f in f f2 f3 f4 f5 f6 f7 f8; do : > $f; done && /usr/bin/id -gn > .login")) (def cn (fn (_ n) (string-append "/tmp/x-cu-chn/" n))) (def named (fn (_ n id) (if (null? n) (%cu-int->str id) n))) (def u (%cu-int->str (sys-geteuid))) (def g (%cu-int->str (sys-getegid))) (def un (named (sys-user-name (sys-geteuid)) (sys-geteuid))) (def gn (named (sys-group-name (sys-getegid)) (sys-getegid))) (def on (let ((gid (%cu-stat-get (file-stat-full (cn "f")) (lit gid)))) (named (sys-group-name gid) gid))) (def login (first (%cu-lines (file-read-all (cn ".login"))))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (cn ".out"))) (ee (file-open-write (cn ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (string-concat (list (file-read-all (cn ".out")) "stderr:\n" (file-read-all (cn ".err")) "status " (%cu-int->str st) "\n"))))))) (def check (fn (_ got want) (display (if (string=? got want) "as chown says it" got)))) (display "made"))
```
---
    made

## names

### a user named by name

```cu
(check (run (list "chown" "-v" un (cn "f"))) (string-concat (list "ownership of '" (cn "f") "' retained as " un "\nstderr:\nstatus 0\n")))
```
---
    as chown says it

### a group by name alone, the owner shown as nothing

```cu
(check (run (list "chown" "-v" (string-append ":" gn) (cn "f"))) (string-concat (list "changed ownership of '" (cn "f") "' from " un ":" on " to :" gn "\nstderr:\nstatus 0\n")))
```
---
    as chown says it

### both by name

```cu
(check (run (list "chown" "-v" (string-concat (list un ":" gn)) (cn "f2"))) (string-concat (list "changed ownership of '" (cn "f2") "' from " un ":" on " to " un ":" gn "\nstderr:\nstatus 0\n")))
```
---
    as chown says it

### OWNER: takes the owner's login group

```cu
(check (run (list "chown" "-v" (string-append un ":") (cn "f3"))) (string-concat (list "changed ownership of '" (cn "f3") "' from " un ":" on " to " un ":" login "\nstderr:\nstatus 0\n")))
```
---
    as chown says it

### a numeric owner beside a named group is shown as nothing

```cu
(check (run (list "chown" "-v" (string-concat (list u ":" gn)) (cn "f4"))) (string-concat (list "changed ownership of '" (cn "f4") "' from " un ":" on " to :" gn "\nstderr:\nstatus 0\n")))
```
---
    as chown says it

### a numeric group alone is a change of group

```cu
(check (run (list "chown" "-v" (string-append ":" g) (cn "f5"))) (string-concat (list "changed group of '" (cn "f5") "' from " on " to " g "\nstderr:\nstatus 0\n")))
```
---
    as chown says it

### chgrp by name, and +N as a number

```cu
(do (check (run (list "chgrp" "-v" gn (cn "f6"))) (string-concat (list "changed group of '" (cn "f6") "' from " on " to " gn "\nstderr:\nstatus 0\n"))) (newline) (check (run (list "chgrp" "-v" (string-append "+" g) (cn "f7"))) (string-concat (list "changed group of '" (cn "f7") "' from " on " to " g "\nstderr:\nstatus 0\n"))))
```
---
```output
as chown says it
as chown says it
```

### OWNER.GROUP is read as OWNER:GROUP, with a warning

```cu
(check (run (list "chown" "-v" (string-concat (list un "." gn)) (cn "f8"))) (string-concat (list "changed ownership of '" (cn "f8") "' from " un ":" on " to " un ":" gn "\nstderr:\nchown: warning: '.' should be ':': '" un "." gn "'\nstatus 0\n")))
```
---
    as chown says it

### a bare : changes nothing, and says so

```cu
(check (run (list "chown" "-v" ":" (cn "f"))) (string-concat (list "ownership of '" (cn "f") "' retained\nstderr:\nstatus 0\n")))
```
---
    as chown says it

## refusals

### a name the system does not know refuses the spec, and nothing is touched

```cu
(do (check (run (list "chown" "no-such-user-x" (cn "f"))) "stderr:\nchown: invalid user: 'no-such-user-x'\nstatus 1\n") (newline) (check (run (list "chown" (string-append un ":no-such-group-x") (cn "f"))) (string-concat (list "stderr:\nchown: invalid group: '" un ":no-such-group-x'\nstatus 1\n"))) (newline) (check (run (list "chgrp" "no-such-group-x" (cn "f"))) "stderr:\nchgrp: invalid group: 'no-such-group-x'\nstatus 1\n"))
```
---
```output
as chown says it
as chown says it
as chown says it
```

### +NAME is no number, and a numeric OWNER: has no login group

```cu
(do (check (run (list "chown" (string-append "+" un) (cn "f"))) (string-concat (list "stderr:\nchown: invalid user: '+" un "'\nstatus 1\n"))) (newline) (check (run (list "chown" (string-append u ":") (cn "f"))) (string-concat (list "stderr:\nchown: invalid spec: '" u ":'\nstatus 1\n"))))
```
---
```output
as chown says it
as chown says it
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-chn")) (display "clean"))
```
---
    clean
