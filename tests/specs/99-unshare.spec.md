# @weight 1

busybox's unshare (util-linux/unshare.c) reads getopt_long's options, then
makes the namespaces they ask for and runs PROG in them, or a login shell.
Darwin has no namespaces: unsharing none runs PROG, and asking for any is
ENOSYS.  Each run is a child of its own, since unshare becomes PROG.  The
namespaces themselves are tested in the Linux leg, against busybox.

## the fixture

### a run of unshare in a child, what it writes and its status

```cu
(do (def us-f (fn (_ n) (string-append "/tmp/x-cu-us." n)))
    (def us-show (fn (_ argv)
      (do (def kid (sys-fork))
          (when (= kid 0)
            (do (sys-dup2 (file-open-write (us-f "out")) 1) (sys-dup2 (file-open-write (us-f "err")) 2)
                (sys-exit (cu-run argv ""))))
          (def st (sys-wait kid))
          (display (string-concat (list (file-read-all (us-f "out")) "stderr:\n"
                                        (file-read-all (us-f "err")) "status " (cu-int->str st) "\n")))
          ())))
    (display "made"))
```
---
    made

## the options

### a PROG and its words, which are its own from the first

```cu
(do (us-show (list "unshare" "/bin/echo" "hi"))
    (us-show (list "unshare" "/bin/echo" "-n" "hi"))
    (us-show (list "unshare" "--" "/bin/echo" "-m"))
    (us-show (list "unshare" "nosuch-x-cu-us")))
```
---
```output
hi
stderr:
status 0
histderr:
status 0
-m
stderr:
status 0
stderr:
unshare: can't execute 'nosuch-x-cu-us': No such file or directory
status 127
```

### musl's refusals: a letter, an ambiguous prefix, a missing argument, one not taken

```cu
(do (us-show (list "unshare" "-x" "true"))
    (us-show (list "unshare" "--mo"))
    (us-show (list "unshare" "--propagation"))
    (us-show (list "unshare" "--fork=1")))
```
---
```output
stderr:
unshare: unrecognized option: x
Usage: unshare [OPTIONS] [PROG ARGS]

	-m,--mount[=FILE]	Unshare mount namespace
	-u,--uts[=FILE]		Unshare UTS namespace (hostname etc.)
	-i,--ipc[=FILE]		Unshare System V IPC namespace
	-n,--net[=FILE]		Unshare network namespace
	-p,--pid[=FILE]		Unshare PID namespace
	-U,--user[=FILE]	Unshare user namespace
	-f			Fork before execing PROG
	-r			Map current user to root (implies -U)
	--mount-proc[=DIR]	Mount /proc filesystem first (implies -m)
	--propagation slave|shared|private|unchanged
				Modify mount propagation in mount namespace
	--setgroups allow|deny	Control the setgroups syscall in user namespaces
status 1
stderr:
unshare: option is ambiguous: mo
Usage: unshare [OPTIONS] [PROG ARGS]

	-m,--mount[=FILE]	Unshare mount namespace
	-u,--uts[=FILE]		Unshare UTS namespace (hostname etc.)
	-i,--ipc[=FILE]		Unshare System V IPC namespace
	-n,--net[=FILE]		Unshare network namespace
	-p,--pid[=FILE]		Unshare PID namespace
	-U,--user[=FILE]	Unshare user namespace
	-f			Fork before execing PROG
	-r			Map current user to root (implies -U)
	--mount-proc[=DIR]	Mount /proc filesystem first (implies -m)
	--propagation slave|shared|private|unchanged
				Modify mount propagation in mount namespace
	--setgroups allow|deny	Control the setgroups syscall in user namespaces
status 1
stderr:
unshare: option requires an argument: propagation
Usage: unshare [OPTIONS] [PROG ARGS]

	-m,--mount[=FILE]	Unshare mount namespace
	-u,--uts[=FILE]		Unshare UTS namespace (hostname etc.)
	-i,--ipc[=FILE]		Unshare System V IPC namespace
	-n,--net[=FILE]		Unshare network namespace
	-p,--pid[=FILE]		Unshare PID namespace
	-U,--user[=FILE]	Unshare user namespace
	-f			Fork before execing PROG
	-r			Map current user to root (implies -U)
	--mount-proc[=DIR]	Mount /proc filesystem first (implies -m)
	--propagation slave|shared|private|unchanged
				Modify mount propagation in mount namespace
	--setgroups allow|deny	Control the setgroups syscall in user namespaces
status 1
stderr:
unshare: option does not take an argument: fork
Usage: unshare [OPTIONS] [PROG ARGS]

	-m,--mount[=FILE]	Unshare mount namespace
	-u,--uts[=FILE]		Unshare UTS namespace (hostname etc.)
	-i,--ipc[=FILE]		Unshare System V IPC namespace
	-n,--net[=FILE]		Unshare network namespace
	-p,--pid[=FILE]		Unshare PID namespace
	-U,--user[=FILE]	Unshare user namespace
	-f			Fork before execing PROG
	-r			Map current user to root (implies -U)
	--mount-proc[=DIR]	Mount /proc filesystem first (implies -m)
	--propagation slave|shared|private|unchanged
				Modify mount propagation in mount namespace
	--setgroups allow|deny	Control the setgroups syscall in user namespaces
status 1
```

### --setgroups and --propagation words, checked before anything is made

```cu
(do (us-show (list "unshare" "--setgroups=maybe" "true"))
    (us-show (list "unshare" "-r" "--setgroups" "allow" "true"))
    (us-show (list "unshare" "--propagation=sideways" "-m" "true"))
    (us-show (list "unshare" "--propagation=sideways" "/bin/echo" "ignored")))
```
---
```output
stderr:
unshare: unrecognized: --setgroups=maybe
status 1
stderr:
unshare: --setgroups=allow and --map-root-user are mutually exclusive
status 1
stderr:
unshare: unrecognized: --propagation=sideways
status 1
ignored
stderr:
status 0
```

## Darwin

### any namespace is ENOSYS, implied ones and long spellings too

```cu
(do (us-show (list "unshare" "-n" "true"))
    (us-show (list "unshare" "-mu" "--ipc" "true"))
    (us-show (list "unshare" "-r" "true"))
    (us-show (list "unshare" "--mount-proc=/tmp" "--pid" "true"))
    (us-show (list "unshare" "--net=/tmp/x-cu-us.ns" "true")))
```
---
```output
stderr:
unshare: unshare(0x40000000): Function not implemented
status 1
stderr:
unshare: unshare(0xc020000): Function not implemented
status 1
stderr:
unshare: unshare(0x10000000): Function not implemented
status 1
stderr:
unshare: unshare(0x20020000): Function not implemented
status 1
stderr:
unshare: unshare(0x40000000): Function not implemented
status 1
```

### -f: the parent leaves as the child did, by its status or its signal

```cu
(do (us-show (list "unshare" "-f" "/bin/echo" "forked"))
    (us-show (list "unshare" "--fork" "/bin/sh" "-c" "exit 3"))
    (us-show (list "unshare" "-f" "/bin/sh" "-c" "kill -TERM $$")))
```
---
```output
forked
stderr:
status 0
stderr:
status 3
stderr:
status 143
```

### no PROG: $SHELL as a login shell, run by its path

```cu
(do (sys-setenv "SHELL" "/usr/bin/true")
    (us-show (list "unshare"))
    (sys-setenv "SHELL" "/nonexistent/x-cu-us")
    (us-show (list "unshare" "-f"))
    (sys-setenv "SHELL" "true")
    (us-show (list "unshare")))
```
---
```output
stderr:
status 0
stderr:
unshare: can't execute '/nonexistent/x-cu-us': No such file or directory
status 1
stderr:
unshare: can't execute 'true': No such file or directory
status 1
```
