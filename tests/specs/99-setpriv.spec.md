# @weight 1

busybox's setpriv (util-linux/setpriv.c) reads its options and capability
names, then asks the kernel through prctl, capget and capset.  Darwin has
none of the three, so here the options and names are read as busybox reads
them, the calls fail as ENOSYS, and PROG still runs; the capabilities are
tested as root in the Linux leg.

## the fixture

### a run of setpriv in a child, since it becomes PROG: what it writes and its status

```cu
(do (def sp-f (fn (_ n) (string-append "/tmp/x-cu-sp." n)))
    (def sp-show (fn (_ argv)
      (do (def sp-o (file-open-write (sp-f "out"))) (def sp-e (file-open-write (sp-f "err")))
          (def sp-child (sys-fork))
          (when (= sp-child 0)
            (do (sys-dup2 sp-o 1) (sys-dup2 sp-e 2) (sys-exit (cu-run argv ""))))
          (file-close sp-o) (file-close sp-e)
          (def sp-st (sys-wait sp-child))
          (display (%str-concat (list (file-read-all (sp-f "out")) "stderr:\n"
                                        (file-read-all (sp-f "err")) "status " (cu-int->str sp-st) "\n")))
          ())))
    (display "made"))
```
---
    made

## the options

### none, -d with more, ambiguous and unknown long options

```cu
(do (sp-show (list "setpriv"))
    (sp-show (list "setpriv" "-d" "true"))
    (sp-show (list "setpriv" "--n" "true"))
    (sp-show (list "setpriv" "--nope")))
```
---
```output
stderr:
Usage: setpriv [OPTIONS] PROG ARGS

Run PROG with different privilege settings

-d,--dump		Show current capabilities
--nnp,--no-new-privs	Ignore setuid/setgid bits and file capabilities
--inh-caps CAP,CAP	Set inheritable capabilities
--ambient-caps CAP,CAP	Set ambient capabilities
status 1
stderr:
Usage: setpriv [OPTIONS] PROG ARGS

Run PROG with different privilege settings

-d,--dump		Show current capabilities
--nnp,--no-new-privs	Ignore setuid/setgid bits and file capabilities
--inh-caps CAP,CAP	Set inheritable capabilities
--ambient-caps CAP,CAP	Set ambient capabilities
status 1
stderr:
setpriv: option is ambiguous: n
Usage: setpriv [OPTIONS] PROG ARGS

Run PROG with different privilege settings

-d,--dump		Show current capabilities
--nnp,--no-new-privs	Ignore setuid/setgid bits and file capabilities
--inh-caps CAP,CAP	Set inheritable capabilities
--ambient-caps CAP,CAP	Set ambient capabilities
status 1
stderr:
setpriv: unrecognized option: nope
Usage: setpriv [OPTIONS] PROG ARGS

Run PROG with different privilege settings

-d,--dump		Show current capabilities
--nnp,--no-new-privs	Ignore setuid/setgid bits and file capabilities
--inh-caps CAP,CAP	Set inheritable capabilities
--ambient-caps CAP,CAP	Set ambient capabilities
status 1
```

## the calls

### -d, a prefix of --dump, --nnp and --inh-caps: Darwin has no prctl or capget

```cu
(do (sp-show (list "setpriv" "-d"))
    (sp-show (list "setpriv" "--du"))
    (sp-show (list "setpriv" "--no-new" "true"))
    (sp-show (list "setpriv" "--inh=+chown" "true")))
```
---
```output
stderr:
setpriv: prctl: GET_NO_NEW_PRIVS: Function not implemented
status 1
stderr:
setpriv: prctl: GET_NO_NEW_PRIVS: Function not implemented
status 1
stderr:
setpriv: prctl: SET_NO_NEW_PRIVS: Function not implemented
status 1
stderr:
setpriv: capget: Function not implemented
status 1
```

### --ambient-caps: names read and refused, each failure said, PROG run still

```cu
(do (sp-show (list "setpriv" "--ambient-caps" "chown" "true"))
    (sp-show (list "setpriv" "--ambient-caps" "+cap_41" "true"))
    (sp-show (list "setpriv" "--ambient-caps" "+perfmon" "true"))
    (sp-show (list "setpriv" "--amb" "+CHOWN,,-cap_ 5" "sh" "-c" "echo ran; exit 3")))
```
---
```output
stderr:
setpriv: invalid capability 'chown'
status 1
stderr:
setpriv: unknown capability 'cap_41'
status 1
stderr:
setpriv: unknown capability 'perfmon'
status 1
ran
stderr:
setpriv: cap_ambient_raise: Function not implemented
setpriv: cap_ambient_lower: Function not implemented
status 3
```

## a PROG

### run with its words, not found, not runnable

```cu
(do (sp-show (list "setpriv" "sh" "-c" "echo $0 $1" "a" "b"))
    (sp-show (list "setpriv" "nosuchprog"))
    (sp-show (list "setpriv" "/etc")))
```
---
```output
a b
stderr:
status 0
stderr:
setpriv: can't execute 'nosuchprog': No such file or directory
status 127
stderr:
setpriv: can't execute '/etc': Permission denied
status 126
```
