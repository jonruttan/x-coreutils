# @weight 1

User and group names: the system's name for an id, from getpwuid and
getgrgid, where the system has one.  stat's `%U` and `%G` show them, and
`UNKNOWN` where there is none; its default block shows each id in five
columns and its name in eight; whoami and `id -un` answer the system's name
for the user, whatever `$USER` says.  The expected names are the system's
own, from `/bin/ls -l` and `/usr/bin/id`.

## the fixtures

### a file of the user's own, the system's names for it, and a reader

`f` is made here, mode 0644; the system's `ls -l` and `id` write down its
owner and group, their ids, the user's name, and the name of root's group.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-nm && mkdir -p /tmp/x-cu-nm && cd /tmp/x-cu-nm && printf 'x\\n' > f && chmod 644 f && /bin/ls -ld f | awk '{print $3}' > .owner && /bin/ls -ld f | awk '{print $4}' > .group && /bin/ls -ldn f | awk '{print $3}' > .uid && /bin/ls -ldn f | awk '{print $4}' > .gid && /usr/bin/id -un > .me && /usr/bin/id -gn root > .rootgroup")) (def nm (fn (_ n) (string-append "/tmp/x-cu-nm/" n))) (def said (fn (_ n) (first (%cu-lines (file-read-all (nm n)))))) (def cap (fn (_ argv) (do (sys-dup2 1 9) (let ((fd (file-open-write (nm ".cap")))) (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1) (file-close fd) (file-read-all (nm ".cap"))))))) (def pad (fn (self s w) (if (>= (byte-len s) w) s (self (string-append " " s) w)))) (display "made"))
```
---
    made

## the door

### the user, root, and root's group are named as the system names them

```cu
(display (list (string=? (sys-user-name (sys-geteuid)) (said ".me")) (sys-user-name 0) (string=? (sys-group-name 0) (said ".rootgroup"))))
```
---
    (#t root #t)

### an id with no name answers nil, which stat shows as UNKNOWN

```cu
(display (list (sys-user-name 99999) (sys-group-name 99999) (%cu-stat-user 99999) (%cu-stat-group 99999)))
```
---
    (() () UNKNOWN UNKNOWN)

## stat

### %U and %G name the owner and the group, as ls -l does

```cu
(display (list (string=? (cap (list "stat" "-c" "%U %G" (nm "f"))) (string-append (said ".owner") " " (said ".group") "\n")) (cap (list "stat" "-c" "%U" "/etc/hosts"))))
```
---
```output
(#t root
)
```

### the default block shows each id in five columns and its name in eight

```cu
(display (string=? (%cu-nth 3 (%cu-lines (cap (list "stat" (nm "f"))))) (string-concat (list "Access: (0644/-rw-r--r--)  Uid: (" (pad (said ".uid") 5) "/" (pad (said ".owner") 8) ")   Gid: (" (pad (said ".gid") 5) "/" (pad (said ".group") 8) ")"))))
```
---
    #t

## whoami and id

### they answer the system's name, whatever $USER says

```cu
(do (def was (sys-getenv "USER")) (sys-setenv "USER" "not-the-user") (def w (cap (list "whoami"))) (def u (cap (list "id" "-un"))) (if (null? was) (sys-unsetenv "USER") (sys-setenv "USER" was)) (display (list (string=? w (string-append (said ".me") "\n")) (string=? u (string-append (said ".me") "\n")))))
```
---
    (#t #t)

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-nm")) (display "clean"))
```
---
    clean
