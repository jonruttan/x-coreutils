# @weight 2

env: the environment it builds, printed or handed to a command.  The expected
text is GNU env's for the same arguments, except the order new names are
printed in: this env places them as setenv does, in the order given, which is
what BSD env and GNU env over glibc print (GNU env on macOS goes through
putenv, which puts each new name first).

The cases start from -i, or name the variables they look at, so what they
print does not depend on the environment the suite runs in.

## the fixtures

### a scratch directory, a file that cannot be run, and a reader for what env printed

ev shows stdout, a bar where it ended, stderr and the status.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-env && mkdir -p /tmp/x-cu-env && printf '#!/bin/sh\\necho ran\\n' > /tmp/x-cu-env/notexec && chmod 644 /tmp/x-cu-env/notexec")) (Sys setenv "X_CU_ENV_KEEP" "kept") (def ev (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((o (file-open-write "/tmp/x-cu-env/.out")) (e (file-open-write "/tmp/x-cu-env/.err"))) (do (sys-dup2 o 1) (sys-dup2 e 2) (def ev-st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close o) (file-close e) (display (file-read-all "/tmp/x-cu-env/.out")) (display "|\n") (display (file-read-all "/tmp/x-cu-env/.err")) (display "status ") (display ev-st) (newline)))))) (display "made"))
```
---
    made

## the environment printed

### a NAME=VALUE replaces its name where it stands, or goes at the end

```cu
(do (ev (list "env" "-i" "A=1" "B=2")) (ev (list "env" "-i" "A=1" "B=2" "A=3")) (ev (list "env" "-i" "A=")))
```
---
```output
A=1
B=2
|
status 0
A=3
B=2
|
status 0
A=
|
status 0
```

### a - before the operands starts from an empty environment, as -i does

```cu
(ev (list "env" "-" "A=1"))
```
---
```output
A=1
|
status 0
```

### -0 ends each entry with a NUL

The bytes are read with od, since a string stops at the first NUL.

```cu
(do (sys-dup2 1 9) (let ((fd (file-open-write "/tmp/x-cu-env/.z"))) (do (sys-dup2 fd 1) (cu-run (list "env" "-i" "-0" "A=1" "B=2") "") (sys-dup2 9 1) (file-close fd))) (proc-run (list "/bin/sh" "-c" "od -An -tx1 -v /tmp/x-cu-env/.z | tr -s ' \\n' ' ' | sed 's/^ //; s/ $//' > /tmp/x-cu-env/.zhex")) (display (file-read-all "/tmp/x-cu-env/.zhex")) (newline))
```
---
    41 3d 31 00 42 3d 32 00

## a command

### the command runs with the changes: set, unset, and the rest kept

```cu
(do (ev (list "env" "X_CU_ENV_A=1" "/bin/sh" "-c" "printenv X_CU_ENV_A; printenv X_CU_ENV_KEEP")) (ev (list "env" "-u" "X_CU_ENV_KEEP" "/bin/sh" "-c" "printenv X_CU_ENV_KEEP || echo gone")) (ev (list "env" "-i" "A=1" "/usr/bin/printenv" "A")))
```
---
```output
1
kept
|
status 0
gone
|
status 0
1
|
status 0
```

### the options end at the first operand, so a command keeps its own

```cu
(do (ev (list "env" "-i" "/bin/echo" "-n" "hi")) (ev (list "env" "-i" "A=1" "-u" "A")))
```
---
```output
hi|
status 0
|
env: '-u': No such file or directory
status 127
```

### env answers how the command ended: its status, 127 for none, 126 for one that cannot run

```cu
(do (ev (list "env" "-i" "/bin/sh" "-c" "exit 3")) (ev (list "env" "-i" "x-cu-env-no-such-command")) (ev (list "env" "-i" "/tmp/x-cu-env/notexec")))
```
---
```output
|
status 3
|
env: 'x-cu-env-no-such-command': No such file or directory
status 127
|
env: '/tmp/x-cu-env/notexec': Permission denied
status 126
```

### -0 has nothing to end when there is a command

GNU env follows this with a line pointing at --help, which this env does not
have.

```cu
(ev (list "env" "-0" "-i" "A=1" "/usr/bin/true"))
```
---
```output
|
env: cannot specify --null (-0) with command
status 125
```

## cleanup

### the scratch directory goes

```cu
(do (Sys unsetenv "X_CU_ENV_KEEP") (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-env")) (display "clean"))
```
---
    clean
