# @weight 1

busybox's nsenter (util-linux/nsenter.c) reads its options as getopt32long
does, through musl's getopt_long: -m and the rest of the namespaces, -r and
-w take a FILE only in their own word.  Darwin has no namespaces: no /proc
to open a process's from, and setns answers Function not implemented; the
directories, the ids and PROG work as on Linux.  Each run is a child of its
own, so a PROG can take its place.  The namespaces themselves are entered
in the Linux leg, against busybox.

## the fixture

### a run of nsenter in a child, what it writes and its status

```cu
(do (def ns-f (fn (_ n) (string-append "/tmp/x-cu-ns." n)))
    (def ns-uid (cu-int->str (Sys getuid)))
    (def ns-show (fn (_ argv)
      (do (def kid (sys-fork))
          (when (= kid 0)
            (do (sys-dup2 (file-open-write (ns-f "out")) 1) (sys-dup2 (file-open-write (ns-f "err")) 2)
                (sys-exit (cu-run argv ""))))
          (def st (sys-wait kid))
          (display (%str-concat (list (Str8 replace (string-append ns-uid "|\n") "UID|\n" (Str8 replace "\n" "|\n" (file-read-all (ns-f "out")))) "stderr:\n"
                                        (Str8 replace "\n\t" "|" (file-read-all (ns-f "err")))
                                        "status " (cu-int->str st) "\n")))
          ())))
    (display "made"))
```
---
    made

## the options

### letters and long names it does not take, a value missing, a value given to a flag

```cu
(do (ns-show (list "nsenter" "-x"))
    (ns-show (list "nsenter" "--nope"))
    (ns-show (list "nsenter" "--n"))
    (ns-show (list "nsenter" "-t"))
    (ns-show (list "nsenter" "--target"))
    (ns-show (list "nsenter" "--preserve-credentials=1" "true"))
    (ns-show (list "nsenter" "--help")))
```
---
```output
stderr:
nsenter: unrecognized option: x
Usage: nsenter [OPTIONS] [PROG ARGS]
|-t PID		Target process to get namespaces from|-m[FILE]	Enter mount namespace|-u[FILE]	Enter UTS namespace (hostname etc)|-i[FILE]	Enter System V IPC namespace|-n[FILE]	Enter network namespace|-p[FILE]	Enter pid namespace|-U[FILE]	Enter user namespace|-S UID		Set uid in entered namespace|-G GID		Set gid in entered namespace|--preserve-credentials	Don't touch uids or gids|-r[DIR]		Set root directory|-w[DIR]		Set working directory|-F		Don't fork before exec'ing PROG
status 1
stderr:
nsenter: unrecognized option: nope
Usage: nsenter [OPTIONS] [PROG ARGS]
|-t PID		Target process to get namespaces from|-m[FILE]	Enter mount namespace|-u[FILE]	Enter UTS namespace (hostname etc)|-i[FILE]	Enter System V IPC namespace|-n[FILE]	Enter network namespace|-p[FILE]	Enter pid namespace|-U[FILE]	Enter user namespace|-S UID		Set uid in entered namespace|-G GID		Set gid in entered namespace|--preserve-credentials	Don't touch uids or gids|-r[DIR]		Set root directory|-w[DIR]		Set working directory|-F		Don't fork before exec'ing PROG
status 1
stderr:
nsenter: option is ambiguous: n
Usage: nsenter [OPTIONS] [PROG ARGS]
|-t PID		Target process to get namespaces from|-m[FILE]	Enter mount namespace|-u[FILE]	Enter UTS namespace (hostname etc)|-i[FILE]	Enter System V IPC namespace|-n[FILE]	Enter network namespace|-p[FILE]	Enter pid namespace|-U[FILE]	Enter user namespace|-S UID		Set uid in entered namespace|-G GID		Set gid in entered namespace|--preserve-credentials	Don't touch uids or gids|-r[DIR]		Set root directory|-w[DIR]		Set working directory|-F		Don't fork before exec'ing PROG
status 1
stderr:
nsenter: option requires an argument: t
Usage: nsenter [OPTIONS] [PROG ARGS]
|-t PID		Target process to get namespaces from|-m[FILE]	Enter mount namespace|-u[FILE]	Enter UTS namespace (hostname etc)|-i[FILE]	Enter System V IPC namespace|-n[FILE]	Enter network namespace|-p[FILE]	Enter pid namespace|-U[FILE]	Enter user namespace|-S UID		Set uid in entered namespace|-G GID		Set gid in entered namespace|--preserve-credentials	Don't touch uids or gids|-r[DIR]		Set root directory|-w[DIR]		Set working directory|-F		Don't fork before exec'ing PROG
status 1
stderr:
nsenter: option requires an argument: target
Usage: nsenter [OPTIONS] [PROG ARGS]
|-t PID		Target process to get namespaces from|-m[FILE]	Enter mount namespace|-u[FILE]	Enter UTS namespace (hostname etc)|-i[FILE]	Enter System V IPC namespace|-n[FILE]	Enter network namespace|-p[FILE]	Enter pid namespace|-U[FILE]	Enter user namespace|-S UID		Set uid in entered namespace|-G GID		Set gid in entered namespace|--preserve-credentials	Don't touch uids or gids|-r[DIR]		Set root directory|-w[DIR]		Set working directory|-F		Don't fork before exec'ing PROG
status 1
stderr:
nsenter: option does not take an argument: preserve-credentials
Usage: nsenter [OPTIONS] [PROG ARGS]
|-t PID		Target process to get namespaces from|-m[FILE]	Enter mount namespace|-u[FILE]	Enter UTS namespace (hostname etc)|-i[FILE]	Enter System V IPC namespace|-n[FILE]	Enter network namespace|-p[FILE]	Enter pid namespace|-U[FILE]	Enter user namespace|-S UID		Set uid in entered namespace|-G GID		Set gid in entered namespace|--preserve-credentials	Don't touch uids or gids|-r[DIR]		Set root directory|-w[DIR]		Set working directory|-F		Don't fork before exec'ing PROG
status 1
Usage: nsenter [OPTIONS] [PROG ARGS]|
|
	-t PID		Target process to get namespaces from|
	-m[FILE]	Enter mount namespace|
	-u[FILE]	Enter UTS namespace (hostname etc)|
	-i[FILE]	Enter System V IPC namespace|
	-n[FILE]	Enter network namespace|
	-p[FILE]	Enter pid namespace|
	-U[FILE]	Enter user namespace|
	-S UID		Set uid in entered namespace|
	-G GID		Set gid in entered namespace|
	--preserve-credentials	Don't touch uids or gids|
	-r[DIR]		Set root directory|
	-w[DIR]		Set working directory|
	-F		Don't fork before exec'ing PROG|
stderr:
status 0
```

### -t, -S and -G numbers, read before a later refusal

```cu
(do (ns-show (list "nsenter" "-t" "abc" "true"))
    (ns-show (list "nsenter" "-t" "-5" "true"))
    (ns-show (list "nsenter" "-G" "4294967295" "-x" "true"))
    (ns-show (list "nsenter" "--setuid=x" "true")))
```
---
```output
stderr:
nsenter: invalid number 'abc'
status 1
stderr:
nsenter: invalid number '-5'
status 1
stderr:
nsenter: number 4294967295 is not in 0..2147483647 range
status 1
stderr:
nsenter: invalid number 'x'
status 1
```

### a namespace with no FILE and no -t, -t 0, a FILE only in the option's word

```cu
(do (ns-show (list "nsenter" "-n" "true"))
    (ns-show (list "nsenter" "-t" "0" "-n" "true"))
    (ns-show (list "nsenter" "-w" "/bin/pwd"))
    (ns-show (list "nsenter" "--net" "/dev/null" "true")))
```
---
```output
stderr:
Usage: nsenter [OPTIONS] [PROG ARGS]
|-t PID		Target process to get namespaces from|-m[FILE]	Enter mount namespace|-u[FILE]	Enter UTS namespace (hostname etc)|-i[FILE]	Enter System V IPC namespace|-n[FILE]	Enter network namespace|-p[FILE]	Enter pid namespace|-U[FILE]	Enter user namespace|-S UID		Set uid in entered namespace|-G GID		Set gid in entered namespace|--preserve-credentials	Don't touch uids or gids|-r[DIR]		Set root directory|-w[DIR]		Set working directory|-F		Don't fork before exec'ing PROG
status 1
stderr:
Usage: nsenter [OPTIONS] [PROG ARGS]
|-t PID		Target process to get namespaces from|-m[FILE]	Enter mount namespace|-u[FILE]	Enter UTS namespace (hostname etc)|-i[FILE]	Enter System V IPC namespace|-n[FILE]	Enter network namespace|-p[FILE]	Enter pid namespace|-U[FILE]	Enter user namespace|-S UID		Set uid in entered namespace|-G GID		Set gid in entered namespace|--preserve-credentials	Don't touch uids or gids|-r[DIR]		Set root directory|-w[DIR]		Set working directory|-F		Don't fork before exec'ing PROG
status 1
stderr:
Usage: nsenter [OPTIONS] [PROG ARGS]
|-t PID		Target process to get namespaces from|-m[FILE]	Enter mount namespace|-u[FILE]	Enter UTS namespace (hostname etc)|-i[FILE]	Enter System V IPC namespace|-n[FILE]	Enter network namespace|-p[FILE]	Enter pid namespace|-U[FILE]	Enter user namespace|-S UID		Set uid in entered namespace|-G GID		Set gid in entered namespace|--preserve-credentials	Don't touch uids or gids|-r[DIR]		Set root directory|-w[DIR]		Set working directory|-F		Don't fork before exec'ing PROG
status 1
stderr:
Usage: nsenter [OPTIONS] [PROG ARGS]
|-t PID		Target process to get namespaces from|-m[FILE]	Enter mount namespace|-u[FILE]	Enter UTS namespace (hostname etc)|-i[FILE]	Enter System V IPC namespace|-n[FILE]	Enter network namespace|-p[FILE]	Enter pid namespace|-U[FILE]	Enter user namespace|-S UID		Set uid in entered namespace|-G GID		Set gid in entered namespace|--preserve-credentials	Don't touch uids or gids|-r[DIR]		Set root directory|-w[DIR]		Set working directory|-F		Don't fork before exec'ing PROG
status 1
```

## the namespaces

### no /proc to open from, a FILE that is not there, setns where there is none

```cu
(do (ns-show (list "nsenter" "-t" "1" "-n" "true"))
    (ns-show (list "nsenter" "-m/nope" "true"))
    (ns-show (list "nsenter" "-n/dev/null" "true"))
    (ns-show (list "nsenter" "--user=/dev/null" "--uts=/dev/null" "true"))
    (ns-show (list "nsenter" "-p/dev/null" "-F" "true")))
```
---
```output
stderr:
nsenter: can't open '/proc/1/ns/net': No such file or directory
status 1
stderr:
nsenter: can't open '/nope': No such file or directory
status 1
stderr:
nsenter: setns(): can't reassociate to namespace 'net': Function not implemented
status 1
stderr:
nsenter: setns(): can't reassociate to namespace 'user': Function not implemented
status 1
stderr:
nsenter: setns(): can't reassociate to namespace 'pid': Function not implemented
status 1
```

## the rest

### a working directory, a root this user may not change, the ids

```cu
(do (ns-show (list "nsenter" "-w/" "/bin/pwd" "-P"))
    (ns-show (list "nsenter" "--wd=/usr/bin" "/bin/pwd" "-P"))
    (ns-show (list "nsenter" "-r/" "true"))
    (ns-show (list "nsenter" "-S" ns-uid "/usr/bin/id" "-u"))
    (ns-show (list "nsenter" "--no-fork" "--preserve-credentials" "/bin/echo" "kept")))
```
---
```output
/|
stderr:
status 0
/usr/bin|
stderr:
status 0
stderr:
nsenter: can't change root directory to '.': Operation not permitted
status 1
UID|
stderr:
status 0
kept|
stderr:
status 0
```

### PROG: the options end at it or at --, one not found, one not runnable, a login shell

```cu
(do (ns-show (list "nsenter" "/bin/echo" "-n" "hi"))
    (ns-show (list "nsenter" "--" "/bin/echo" "-F"))
    (ns-show (list "nsenter" "nsenter-no-such-command"))
    (ns-show (list "nsenter" "/etc/passwd"))
    (sys-setenv "SHELL" "/nope/sh")
    (ns-show (list "nsenter"))
    (sys-setenv "SHELL" "/bin/echo")
    (ns-show (list "nsenter")))
```
---
```output
histderr:
status 0
-F|
stderr:
status 0
stderr:
nsenter: can't execute 'nsenter-no-such-command': No such file or directory
status 127
stderr:
nsenter: can't execute '/etc/passwd': Permission denied
status 126
stderr:
nsenter: can't execute '/nope/sh': No such file or directory
status 1
|
stderr:
status 0
```
