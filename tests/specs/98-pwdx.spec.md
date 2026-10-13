# @weight 1

busybox's pwdx (procps/pwdx.c), over the current directories x/sys/host
reports.  The fixture runs point the Linux reader at a /proc this spec
writes, so each answer is fixed on any machine; the runs at the end ask this
kernel about this process.  Every expectation is busybox 1.36.1's in alpine.
A `|` marks the end of each line written to standard output.

## the fixtures

### a /proc of four processes, and a run of pwdx with the reader pointed at it

300's directory is /home/u.  400 is a pid with no process.  500 is a
process whose directory cannot be read, as another user's is not.  600 is a
zombie, which has no directory.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-pw && mkdir -p /tmp/x-cu-pw/proc/400 && cd /tmp/x-cu-pw/proc && printf 'cpu  1 0 1 1 0 0 0 0 0 0\\nbtime 1790000000\\n' > stat && mk() { mkdir $1 && printf '%s (%s) %s 1 %s %s 0 -1 0 0 0 0 0 1 1 0 0 20 0 1 0 100 4096 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\\n' $1 $2 $3 $1 $1 > $1/stat; } && mk 300 sh S && mk 500 sh S && mk 600 sh Z && ln -s /home/u 300/cwd")) (def pw-f (fn (_ n) (string-append "/tmp/x-cu-pw/" n))) (def pw-run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (pw-f ".out"))) (ee (file-open-write (pw-f ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (string-concat (list (Str8 replace "\n" "|\n" (file-read-all (pw-f ".out"))) "stderr:\n" (file-read-all (pw-f ".err")) "status " (%cu-int->str st) "\n"))))))) (def pw-kernel (Host %backend)) (def pw-fixed (fn (_ argv) (do (Host source (lit linux)) (Host proc-root (pw-f "proc")) (def r (pw-run argv)) (Host source pw-kernel) (Host proc-root "/proc") r))) (def pw-show (fn (_ argv) (do (display (pw-fixed argv)) ()))) (display (if (file-exists? (pw-f "proc/600/stat")) "made" "fixture incomplete")))
```
---
    made

## pids

### a pid, the same as /proc/PID, and with leading zeros, each named as it was given

```cu
(pw-show (list "pwdx" "300" "/proc/300" "00300"))
```
---
```output
300: /home/u|
/proc/300: /home/u|
00300: /home/u|
stderr:
status 0
```

### a pid no process has, and a zombie, are no such process, status 0

```cu
(pw-show (list "pwdx" "400" "600" "999" "4294967295" "0"))
```
---
```output
400: No such process|
600: No such process|
999: No such process|
4294967295: No such process|
0: No such process|
stderr:
status 0
```

### a process whose directory cannot be read is permission denied

```cu
(pw-show (list "pwdx" "500"))
```
---
```output
500: Permission denied|
stderr:
status 0
```

### -- ends the options

```cu
(pw-show (list "pwdx" "--" "300"))
```
---
```output
300: /home/u|
stderr:
status 0
```

## refusals

### no pid is busybox's usage, status 1

```cu
(pw-show (list "pwdx"))
```
---
```output
stderr:
Usage: pwdx PID...

Show current directory for PIDs
status 1
```

### a dash and a digit is an option

```cu
(pw-show (list "pwdx" "-5"))
```
---
```output
stderr:
pwdx: unrecognized option: 5
Usage: pwdx PID...

Show current directory for PIDs
status 1
```

### only decimal digits, at least one, up to 4294967295, after an optional /proc/

```cu
(do (pw-show (list "pwdx" "4294967296")) (pw-show (list "pwdx" "abc")) (pw-show (list "pwdx" "")) (pw-show (list "pwdx" "12x")) (pw-show (list "pwdx" "+5")) (pw-show (list "pwdx" " 5")) (pw-show (list "pwdx" "5 ")) (pw-show (list "pwdx" "/proc/")) (pw-show (list "pwdx" "/proc//1")) (pw-show (list "pwdx" "proc/1")))
```
---
```output
stderr:
pwdx: invalid process id: '4294967296'
status 1
stderr:
pwdx: invalid process id: 'abc'
status 1
stderr:
pwdx: invalid process id: ''
status 1
stderr:
pwdx: invalid process id: '12x'
status 1
stderr:
pwdx: invalid process id: '+5'
status 1
stderr:
pwdx: invalid process id: ' 5'
status 1
stderr:
pwdx: invalid process id: '5 '
status 1
stderr:
pwdx: invalid process id: ''
status 1
stderr:
pwdx: invalid process id: '/1'
status 1
stderr:
pwdx: invalid process id: 'proc/1'
status 1
```

### a bad pid ends the run after the lines before it

```cu
(pw-show (list "pwdx" "300" "abc" "300"))
```
---
```output
300: /home/u|
stderr:
pwdx: invalid process id: 'abc'
status 1
```

## this machine

### this process's directory is the one it runs in; a pid no process has is no such process

```cu
(do (def me (%cu-int->str (sys-getpid))) (def r (pw-run (list "pwdx" me "999999999"))) (display (if (str=? r (string-concat (list me ": " (sys-getcwd) "|\n999999999: No such process|\nstderr:\nstatus 0\n"))) "same" r)))
```
---
    same

## cleanup

### the scratch directory goes

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-pw")) (display "gone"))
```
---
    gone
