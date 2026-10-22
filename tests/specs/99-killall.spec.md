# @weight 1

busybox's killall (procps/kill.c), over the processes x/sys/host reports.
The names are matched on a fixture /proc, as spec 85 matches pidof's: the
Linux reader pointed at a tree this spec writes.  No signal reaches a
fixture's process: `sys-kill` is rebound to one that writes the pid and the
signal it was handed, and answers as kill(2) would for a process that is
gone where the fixture says so.  The run at the end signals a process this
spec starts.  Every expectation is busybox's own, from a busybox built from
its source, run with the same words.  A `|` marks the end of each line
written to standard output.

## the fixtures

### a /proc of seven processes, a run with the reader pointed at it, and a kill that writes what it was asked

1 is init.  200's comm fills busybox's 15 bytes, so the basename of its
argv[1] settles a match.  300 is a login shell, `-sh`, whose executable is
busybox.  400 and 500 are two sleeps.  600 is a kernel thread, with no
command line and no executable.  The last is this process, `kaself`.  A
kill of 500 under the name `gone` fails as kill(2) fails for a pid nothing
has: the rebound kill hands that one to the real kill, as pid 2147483647
with signal 0.

```cu
(do (def me (sys-getpid)) (proc-run (list "/bin/sh" "-c" (string-append "rm -rf /tmp/x-cu-ka && mkdir -p /tmp/x-cu-ka/proc && cd /tmp/x-cu-ka/proc && printf 'cpu  1 0 1 1 0 0 0 0 0 0\\nbtime 1790000000\\n' > stat && mk() { d=$1; mkdir $d && printf '%s (%s) S %s %s %s 0 -1 0 0 0 0 0 1 1 0 0 20 0 1 0 100 4096 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\\n' $1 \"$2\" $3 $1 $4 > $d/stat && e=$5 && shift 5 && : > $d/cmdline && for a; do printf '%s\\0' \"$a\" >> $d/cmdline; done && if [ -n \"$e\" ]; then ln -s $e $d/exe; fi; } && mk 1 init 0 1 /sbin/init /sbin/init && mk 200 a-very-long-nam 1 1 /usr/bin/python3 python3 /opt/a-very-long-name.py && mk 300 sh 1 300 /bin/busybox -sh && mk 400 sleep 300 300 /bin/sleep sleep 4242 && mk 500 sleep 1 1 /bin/sleep sleep 99 && mk 600 kworker/0:1 2 0 '' && mk " (cu-int->str me) " kaself 1 1 /tmp/kaself kaself"))) (def nf (fn (_ n) (string-append "/tmp/x-cu-ka/" n))) (def real-kill sys-kill) (def gone (list #f)) (def recorder (fn (_ pid sig) (do (display (string-concat (list "kill " (cu-int->str pid) " " (cu-int->str sig) "\n"))) (if (if (first gone) (= pid 500) #f) (real-kill 2147483647 0) 0)))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (Str8 replace "\n" "|\n" (file-read-all (nf ".out"))) "stderr:\n" (file-read-all (nf ".err")) "status " (cu-int->str st) "\n")))))))) (def kernel (Host %backend)) (def fixed (fn (_ argv) (do (Host source (lit linux)) (Host proc-root (nf "proc")) (set! sys-kill recorder) (run argv) (set! sys-kill real-kill) (set-first! gone #f) (Host source kernel) (Host proc-root "/proc") ()))) (display (if (file-exists? (nf (string-append "proc/" (cu-int->str me) "/stat"))) "made" "fixture incomplete")))
```
---
    made

## the names

### each process a name names, in pid order, with TERM

```cu
(fixed (list "killall" "sleep"))
```
---
```output
kill 400 15|
kill 500 15|
stderr:
status 0
```

### by comm, by argv[0]'s basename, and a truncated comm settled by argv[1]; each name in turn

```cu
(fixed (list "killall" "-9" "init" "python3" "a-very-long-name.py" "-sh"))
```
---
```output
kill 1 9|
kill 200 9|
kill 200 9|
kill 300 9|
stderr:
status 0
```

### this process is never signalled, and counts as found

```cu
(fixed (list "killall" "kaself"))
```
---
```output
stderr:
status 0
```

### a name no process has is said, and counts one; -q says nothing

```cu
(do (fixed (list "killall" "nosuch" "sleep" "other")) (fixed (list "killall" "-q" "nosuch" "sh")))
```
---
```output
kill 400 15|
kill 500 15|
stderr:
killall: nosuch: no process killed
killall: other: no process killed
status 2
kill 300 15|
stderr:
status 1
```

### a refused signal is said with kill(2)'s reason, and counts one; -q says nothing

```cu
(do (set-first! gone #t) (fixed (list "killall" "-INT" "sleep")) (set-first! gone #t) (fixed (list "killall" "-q" "-INT" "sleep")))
```
---
```output
kill 400 2|
kill 500 2|
stderr:
killall: can't kill pid 500: No such process
status 1
kill 400 2|
kill 500 2|
stderr:
status 1
```

## the signal

### -SIG and -s SIG: a number, a name in any case, with or without SIG, EXIT; -- ends the words

```cu
(do (fixed (list "killall" "-1" "sh")) (fixed (list "killall" "-sigquit" "sh")) (fixed (list "killall" "-s" "KILL" "sh")) (fixed (list "killall" "-s" "exit" "sh")) (fixed (list "killall" "-q" "-s" "HUP" "sh")) (fixed (list "killall" "--" "sh")))
```
---
```output
kill 300 1|
stderr:
status 0
kill 300 3|
stderr:
status 0
kill 300 9|
stderr:
status 0
kill 300 0|
stderr:
status 0
kill 300 1|
stderr:
status 0
kill 300 15|
stderr:
status 0
```

### only the first word is read for a signal; the next are names

```cu
(fixed (list "killall" "-9" "-q" "nosuch"))
```
---
```output
stderr:
killall: -q: no process killed
killall: nosuch: no process killed
status 2
```

### a word that names no signal, -s alone, and -q's -l

```cu
(do (fixed (list "killall" "-x" "sleep")) (fixed (list "killall" "-NOPE" "sleep")) (fixed (list "killall" "--nope")) (fixed (list "killall" "-s")) (fixed (list "killall" "-q" "-l")) (fixed (list "killall" "-")))
```
---
```output
stderr:
killall: bad signal name 'x'
status 1
stderr:
killall: bad signal name 'NOPE'
status 1
stderr:
killall: bad signal name '-nope'
status 1
stderr:
killall: bad signal name 's'
status 1
stderr:
killall: bad signal name 'l'
status 1
stderr:
killall: bad signal name ''
status 1
```

### no name, after a signal or none; -q alone is busybox's usage

```cu
(do (fixed (list "killall")) (fixed (list "killall" "-s" "HUP")) (fixed (list "killall" "-q")))
```
---
```output
stderr:
killall: you need to specify whom to kill
status 1
stderr:
killall: you need to specify whom to kill
status 1
stderr:
Usage: killall [-lq] [-SIG] PROCESS_NAME...

Send a signal (default: TERM) to given processes

	-l	List all signal names and numbers
	-q	Don't complain if no processes were killed
status 1
```

## -l

### alone, this kernel's signals, then libc's RTMIN and RTMAX where it has them, as busybox's print_signames lists them

```cu
(let ((rt (pg-rt)) (line (fn (_ n name) (string-concat (list (cu-pad-left (cu-int->str n) 2) ") " name "\n"))))) (do (sys-dup2 1 9) (def oo (file-open-write (nf ".out"))) (sys-dup2 oo 1) (def st (cu-run (list "killall" "-l") "")) (sys-dup2 9 1) (file-close oo) (list st (str=? (file-read-all (nf ".out")) (string-concat (append (map (fn (_ e) (line (rest e) (first e))) (sys-signals)) (if (null? rt) () (list (line (first rt) "RTMIN") (line (rest rt) "RTMAX")))))))))
```
---
    (0 #t)

### a number to its name by its low seven bits, a name to its number, up to a word that is neither

```cu
(do (run (list "killall" "-l" "9" "HUP" "sigterm" "137" "0" "64" "009")) (run (list "killall" "-l" "2" "nope" "3")) (run (list "killall" "-l" "99x")) (run (list "killall" "-l" "-q")) (run (list "killall" "-l" "4294967296")))
```
---
```output
KILL|
1|
15|
KILL|
EXIT|
64|
KILL|
stderr:
status 0
INT|
stderr:
killall: unknown signal 'nope'
status 1
stderr:
killall: unknown signal '99x'
status 1
stderr:
killall: unknown signal '-q'
status 1
stderr:
killall: unknown signal '4294967296'
status 1
```

## this machine

### killall signals a process this spec started, by its name, with the signal asked for

The process is sleep, run through a link with a name no other process has,
so its argv[0] names it (macOS stops a copy of a system binary).

```cu
(do (def name (string-append "kap" (cu-int->str (sys-getpid)))) (def path (nf name)) (proc-run (list "/bin/ln" "-s" "/bin/sleep" path)) (def kid (sys-fork)) (if (= kid 0) (do (sys-exec path (list "30.4242")) (sys-exit 127)) ()) (def exec-wait (fn (self n) (if (if (> n 0) (let ((e (host-exe kid))) (if (null? e) #t (not (str=? (pg-base e) "sleep")))) #f) (do (sys-usleep 20000) (self (- n 1))) ()))) (exec-wait 250) (def st (cu-run (list "killall" "-INT" name) "")) (list st (sys-wait kid)))
```
---
    (0 130)

## cleanup

### the scratch directory goes

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-ka")) (display "gone"))
```
---
    gone
