# @weight 1

busybox's pidof (procps/pidof.c) and pgrep and pkill (procps/pgrep.c), over
the processes x/sys/host reports.  The matching is checked on a fixture
/proc: the Linux reader pointed at a tree this spec writes, so each rule has
a process made for it and the answers are fixed on any machine.  The runs at
the end find and signal a process this spec starts.  A `|` marks the end of
each line written to standard output.

## the fixtures

### a /proc of six processes, and a run of an applet with the reader pointed at it

1 is init.  200's comm fills busybox's 15 bytes, so the basename of its
argv[1] settles a match.  300 is a login shell, `-sh`, whose executable is
busybox.  400 and 500 are two sleeps, 400 a child of 300 in its session, 500
of 1.  600 is a kernel thread, with no command line and no executable.  Each
run puts the reader back to this kernel's by name: `(Host source ())` leaves
the field as it was.  Each stat line has the 50 fields a kernel writes after
the comm, those past rss zeros: the reader takes the processor from field 39.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-pg && mkdir -p /tmp/x-cu-pg/proc && cd /tmp/x-cu-pg/proc && printf 'cpu  1 0 1 1 0 0 0 0 0 0\\nbtime 1790000000\\n' > stat && mk() { d=$1; mkdir $d && printf '%s (%s) S %s %s %s 0 -1 0 0 0 0 0 1 1 0 0 20 0 1 0 100 4096 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\\n' $1 \"$2\" $3 $1 $4 > $d/stat && e=$5 && shift 5 && : > $d/cmdline && for a; do printf '%s\\0' \"$a\" >> $d/cmdline; done && if [ -n \"$e\" ]; then ln -s $e $d/exe; fi; } && mk 1 init 0 1 /sbin/init /sbin/init && mk 200 a-very-long-nam 1 1 /usr/bin/python3 python3 /opt/a-very-long-name.py && mk 300 sh 1 300 /bin/busybox -sh && mk 400 sleep 300 300 /bin/sleep sleep 4242 && mk 500 sleep 1 1 /bin/sleep sleep 99 && mk 600 kworker/0:1 2 0 ''")) (def nf (fn (_ n) (string-append "/tmp/x-cu-pg/" n))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (Str8 replace "\n" "|\n" (file-read-all (nf ".out"))) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n")))))))) (def kernel (Host %backend)) (def fixed (fn (_ argv) (do (Host source (lit linux)) (Host proc-root (nf "proc")) (run argv) (Host source kernel) (Host proc-root "/proc") ()))) (display (if (file-exists? (nf "proc/600/stat")) "made" "fixture incomplete")))
```
---
    made

## pidof

### a name by comm, newest pid first, -s for one, -o to leave one out

```cu
(do (fixed (list "pidof" "init")) (fixed (list "pidof" "sleep")) (fixed (list "pidof" "-s" "sleep")) (fixed (list "pidof" "-o" "500" "sleep")))
```
---
```output
1|
stderr:
status 0
500 400|
stderr:
status 0
500|
stderr:
status 0
400|
stderr:
status 0
```

### by argv[0]'s basename, by the executable's, by its path, and a truncated comm settled by argv[1]

```cu
(fixed (list "pidof" "sh" "busybox" "/bin/busybox" "a-very-long-name.py" "a-very-long-nam" "python3"))
```
---
```output
300 300 300 200 200|
stderr:
status 0
```

### a name no process has prints nothing and answers 1

```cu
(fixed (list "pidof" "nosuch"))
```
---
```output
stderr:
status 1
```

## pgrep

### a pattern matches argv[0], then comm; -l shows argv[0], or comm when comm matched

```cu
(do (fixed (list "pgrep" "sleep")) (fixed (list "pgrep" "-l" "sleep")) (fixed (list "pgrep" "-l" "kworker")) (fixed (list "pgrep" "-x" "-l" "sh")))
```
---
```output
400|
500|
stderr:
status 0
400 sleep|
500 sleep|
stderr:
status 0
600 kworker/0:1|
stderr:
status 0
300 sh|
stderr:
status 0
```

### -f matches the whole command line; -a with it shows the line

```cu
(do (fixed (list "pgrep" "-f" "sleep 42")) (fixed (list "pgrep" "-f" "-a" "sleep 42")) (fixed (list "pgrep" "-l" "-f" "very-long-name")))
```
---
```output
400|
stderr:
status 0
400 sleep 4242|
stderr:
status 0
200 python3|
stderr:
status 0
```

### -P and -s pick by parent and session, -o and -n the oldest and newest, -v the rest

```cu
(do (fixed (list "pgrep" "-P" "300")) (fixed (list "pgrep" "-s" "1")) (fixed (list "pgrep" "-o" "sleep")) (fixed (list "pgrep" "-n" "sleep")) (fixed (list "pgrep" "-v" "sleep")))
```
---
```output
400|
stderr:
status 0
1|
200|
500|
stderr:
status 0
400|
stderr:
status 0
500|
stderr:
status 0
1|
200|
300|
600|
stderr:
status 0
```

### nothing matched answers 1; no pattern and no -s or -P is busybox's usage

```cu
(do (fixed (list "pgrep" "nosuch")) (fixed (list "pgrep")))
```
---
```output
stderr:
status 1
stderr:
Usage: pgrep [-flanovx] [-s SID|-P PPID|PATTERN]

Display process(es) selected by regex PATTERN

	-l	Show command name too
	-a	Show command line too
	-f	Match against entire command line
	-n	Show the newest process only
	-o	Show the oldest process only
	-v	Negate the match
	-x	Match whole name (not substring)
	-s	Match session ID (0 for current)
	-P	Match parent process ID
status 1
```

## pkill

### -l lists this kernel's signals, as busybox's print_signames does

```cu
(let ((sg (sys-signals))) (do (sys-dup2 1 9) (def oo (file-open-write (nf ".out"))) (sys-dup2 oo 1) (cu-run (list "pkill" "-l") "") (sys-dup2 9 1) (file-close oo) (display (str=? (file-read-all (nf ".out")) (string-concat (map (fn (_ e) (string-concat (list (%cu-pad-left (%cu-int->str (rest e)) 2) ") " (first e) "\n"))) sg))))))
```
---
    #t

### get_signum: a number, a name in any case, with or without SIG, EXIT; nothing else

```cu
(list (%pg-signum "9") (%pg-signum "term") (%pg-signum "SIGKILL") (%pg-signum "sigHup") (%pg-signum "EXIT") (%pg-signum "NOPE") (%pg-signum "99") (%pg-signum "9x"))
```
---
    (9 15 9 1 0 () () ())

## this machine

### pgrep -P finds a process this spec started, and pkill -e signals it with the signal asked for

The process is picked by its parent and its name, which need no argument
vector; -e shows its first argument, or its name where the kernel gives no
argument vector to read.

```cu
(do (def me (sys-getpid)) (def kid (sys-fork)) (if (= kid 0) (do (sys-exec "/bin/sleep" (list "30.4242")) (sys-exit 127)) ()) (def exec-wait (fn (self n) (if (if (> n 0) (not (str=? (host-exe kid) "/bin/sleep")) #f) (do (sys-usleep 20000) (self (- n 1))) ()))) (exec-wait 250) (sys-dup2 1 9) (def oo (file-open-write (nf ".out"))) (sys-dup2 oo 1) (def st1 (cu-run (list "pgrep" "-P" (%cu-int->str me) "sleep") "")) (def st2 (cu-run (list "pkill" "-INT" "-e" "-P" (%cu-int->str me) "sleep") "")) (sys-dup2 9 1) (file-close oo) (def out (file-read-all (nf ".out"))) (def w (sys-wait kid)) (def said (fn (_ shown) (str=? out (string-concat (list (%cu-int->str kid) "\n" shown " killed (pid " (%cu-int->str kid) ")\n"))))) (list (if (said "/bin/sleep") #t (said "sleep")) st1 st2 w))
```
---
    (#t 0 0 130)

## cleanup

### the scratch directory goes

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-pg")) (display "gone"))
```
---
    gone
