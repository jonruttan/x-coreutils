# @weight 1

id and groups name the groups as well as the user, and describe the users
named on the command line.  id takes a user by name or by uid, groups by name
only; one that is no user is said and passed over.  -n and -r want one of -u,
-g and -G, and id refuses more than one.  The expected text is the system's
own id's, which prints what GNU id does; groups' is built from it, as GNU
groups prints it.

## the fixtures

### the system's answers, and a runner for stdout, stderr and the status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-id && mkdir -p /tmp/x-cu-id && cd /tmp/x-cu-id && /usr/bin/id > full && /usr/bin/id -gn > gname && /usr/bin/id -Gn > glist && /usr/bin/id root > root && /usr/bin/id -Gn root > rootglist")) (def said (fn (_ n) (file-read-all (string-append "/tmp/x-cu-id/" n)))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write "/tmp/x-cu-id/.out")) (ee (file-open-write "/tmp/x-cu-id/.err"))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (string-concat (list (file-read-all "/tmp/x-cu-id/.out") "stderr:\n" (file-read-all "/tmp/x-cu-id/.err") "status " (%cu-int->str st) "\n"))))))) (def ok (fn (_ out) (string-append out "stderr:\nstatus 0\n"))) (def check (fn (_ got want) (display (if (string=? got want) "as id says it" got)))) (display "made"))
```
---
    made

## names

### -gn and -Gn name the groups

```cu
(do (check (run (list "id" "-gn")) (ok (said "gname"))) (newline) (check (run (list "id" "-Gn")) (ok (said "glist"))))
```
---
```output
as id says it
as id says it
```

### the full line names the gid and each group

```cu
(check (run (list "id")) (ok (said "full")))
```
---
    as id says it

## the users named

### id describes a user named, by name or by uid

```cu
(do (check (run (list "id" "root")) (ok (said "root"))) (newline) (check (run (list "id" "-Gn" "root")) (ok (said "rootglist"))) (newline) (check (run (list "id" "-un" "0")) (ok "root\n")))
```
---
```output
as id says it
as id says it
as id says it
```

### a uid may have blanks and a + before it, and no more after it

```cu
(do (check (run (list "id" "-un" " 0")) (ok "root\n")) (newline) (check (run (list "id" "-un" "+0")) (ok "root\n")) (newline) (check (run (list "id" "-un" "00")) (ok "root\n")) (newline) (check (run (list "id" "-un" "0x0")) "stderr:\nid: '0x0': no such user\nstatus 1\n"))
```
---
```output
as id says it
as id says it
as id says it
as id says it
```

### one that is no user is said, and the others are still described

```cu
(check (run (list "id" "-un" "root" "no-such-user-x" "0")) "root\nroot\nstderr:\nid: 'no-such-user-x': no such user\nstatus 1\n")
```
---
    as id says it

## what id refuses

### -n and -r want a field, and one field only

```cu
(do (check (run (list "id" "-n")) "stderr:\nid: printing only names or real IDs requires -u, -g, or -G\nstatus 1\n") (newline) (check (run (list "id" "-r")) "stderr:\nid: printing only names or real IDs requires -u, -g, or -G\nstatus 1\n") (newline) (check (run (list "id" "-u" "-g")) "stderr:\nid: cannot print \"only\" of more than one choice\nstatus 1\n"))
```
---
```output
as id says it
as id says it
as id says it
```

## groups

### groups names the groups, and a user's after its name

```cu
(do (check (run (list "groups")) (ok (said "glist"))) (newline) (check (run (list "groups" "root")) (ok (string-append "root : " (said "rootglist")))))
```
---
```output
as id says it
as id says it
```

### groups reads no uid

```cu
(check (run (list "groups" "0")) "stderr:\ngroups: '0': no such user\nstatus 1\n")
```
---
    as id says it

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-id")) (display "clean"))
```
---
    clean
