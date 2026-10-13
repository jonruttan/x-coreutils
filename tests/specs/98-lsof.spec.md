# @weight 1

busybox's lsof (procps/lsof.c), over the open files x/sys/host reports.  The
listing is checked on a fixture /proc: the Linux reader pointed at a tree this
spec writes, so the lines are fixed on any machine.  The run at the end finds
a file a process this spec started holds open.  A `|` marks the end of each
line written to standard output.

## the fixtures

### a /proc of five processes, and a run of lsof with the reader pointed at it

1 is init, whose descriptors this user may not list: it has no fd directory,
as /proc/1/fd is closed to another user.  300 is a shell holding a file, a
socket, a pipe and an eventfd.  400's executable cannot be read, and it holds
a terminal and a deleted file.  500 holds nothing, and 600 is a kernel thread.
Each expectation is busybox's own output on this tree, its lines in the order
a kernel's /proc lists them: by pid, then by descriptor.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-lsof && mkdir -p /tmp/x-cu-lsof/proc && cd /tmp/x-cu-lsof/proc && printf 'cpu  1 0 1 1 0 0 0 0 0 0\\nbtime 1790000000\\n' > stat && mk() { mkdir $1 && printf '%s (%s) S 1 %s %s 0 -1 0 0 0 0 0 1 1 0 0 20 0 1 0 100 4096 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\\n' $1 \"$2\" $1 $1 > $1/stat && : > $1/cmdline && if [ -n \"$3\" ]; then ln -s \"$3\" $1/exe; fi; } && mk 1 init /sbin/init && mk 300 sh /bin/busybox && mkdir 300/fd && ln -s /dev/null 300/fd/0 && ln -s 'socket:[12345]' 300/fd/1 && ln -s 'pipe:[678]' 300/fd/2 && ln -s 'anon_inode:[eventfd]' 300/fd/10 && mk 400 gone '' && mkdir 400/fd && ln -s /dev/pts/0 400/fd/0 && ln -s '/tmp/x (deleted)' 400/fd/3 && mk 500 idle /bin/sleep && mkdir 500/fd && mk 600 kworker ''")) (def nf (fn (_ n) (string-append "/tmp/x-cu-lsof/" n))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (Str8 replace "\n" "|\n" (file-read-all (nf ".out"))) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n")))))))) (def kernel (Host %backend)) (def fixed (fn (_ argv) (do (Host source (lit linux)) (Host proc-root (nf "proc")) (run argv) (Host source kernel) (Host proc-root "/proc") ()))) (display (if (file-exists? (nf "proc/600/stat")) "made" "fixture incomplete")))
```
---
    made

## the listing

### each process's descriptors: pid, executable or (null), descriptor, the link's text

```cu
(fixed (list "lsof"))
```
---
```output
300	/bin/busybox	0	/dev/null|
300	/bin/busybox	1	socket:[12345]|
300	/bin/busybox	2	pipe:[678]|
300	/bin/busybox	10	anon_inode:[eventfd]|
400	(null)	0	/dev/pts/0|
400	(null)	3	/tmp/x (deleted)|
stderr:
status 0
```

### lsof reads no options and no operands

```cu
(fixed (list "lsof" "-~" "--nope" "300"))
```
---
```output
300	/bin/busybox	0	/dev/null|
300	/bin/busybox	1	socket:[12345]|
300	/bin/busybox	2	pipe:[678]|
300	/bin/busybox	10	anon_inode:[eventfd]|
400	(null)	0	/dev/pts/0|
400	(null)	3	/tmp/x (deleted)|
stderr:
status 0
```

### a descriptor the kernel does not name reads as its type, and its number where it has one

Darwin names only a file; a socket or pipe has the kernel's handle for it.

```cu
(list (%lsof-target (list (pair 'fd 5) (pair 'type 'socket) (pair 'name ()) (pair 'id 99)))
      (%lsof-target (list (pair 'fd 6) (pair 'type 'kqueue) (pair 'name ()) (pair 'id ())))
      (%lsof-target (list (pair 'fd 7) (pair 'type 'file) (pair 'name "/etc/hosts") (pair 'id ()))))
```
---
    ("socket:[99]" "kqueue" "/etc/hosts")

## this machine

### a file a process this spec started holds open is listed, and lsof leaves itself out

The child holds the file on descriptor 7 and sleeps until it is killed,
past the whole walk, which takes half a minute on a busy machine; lsof's
line for it ends with the file's path, which Darwin gives through
/private/tmp.  A machine's listing runs to thousands of lines, so grep picks
out the two processes' own.

```cu
(do (def me (sys-getpid)) (proc-run (list "/bin/sh" "-c" ": > /tmp/x-cu-lsof/held")) (def kid (sys-fork)) (if (= kid 0) (do (sys-exec "/bin/sh" (list "-c" "exec 7</tmp/x-cu-lsof/held; exec sleep 600")) (sys-exit 127)) ()) (def holds? (fn (_) (List any? (fn (_ f) (= 7 (Assoc get 'fd f))) (host-files kid)))) (def open-wait (fn (self n) (if (if (> n 0) (not (holds?)) #f) (do (sys-usleep 20000) (self (- n 1))) ()))) (open-wait 250) (sys-dup2 1 9) (def oo (file-open-write (nf ".out"))) (sys-dup2 oo 1) (def st (cu-run (list "lsof") "")) (sys-dup2 9 1) (file-close oo) (sys-kill kid 15) (sys-wait kid) (def lines-of (fn (_ pid) (do (proc-run (list "/bin/sh" "-c" (string-concat (list "grep '^" (%cu-int->str pid) "\t' /tmp/x-cu-lsof/.out > /tmp/x-cu-lsof/.sel; :")))) (List reject (fn (_ l) (str=? l "")) (Str8 split "\n" (file-read-all (nf ".sel"))))))) (list st (List any? (fn (_ l) (if (Str8 ends? "/tmp/x-cu-lsof/held" l) (not (null? (Str8 index-of "\t7\t/" l))) #f)) (lines-of kid)) (lines-of me)))
```
---
    (0 #t ())

## cleanup

### the scratch directory goes

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-lsof")) (display "gone"))
```
---
    gone
