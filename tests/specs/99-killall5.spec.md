# @weight 1

busybox's killall5 (procps/kill.c), over the processes x/sys/host reports.
The scan runs on a fixture /proc, as spec 99-killall's does: the Linux
reader pointed at a tree this spec writes.  No signal reaches any process:
`sys-kill` is rebound to one that writes the pid and the signal it was
handed, STOP and CONT by name, as their numbers differ by kernel.  A kill
of pid -1 is busybox's stop of everything before the scan and its
continue after.  The expectations are read from busybox's source; its
own killall5 signals every process on the machine, so it runs only in the
Linux leg's container.  A `|` marks the end of each line written to
standard output.

## the fixtures

### a /proc of seven processes, this one in a session of its own, a run with the reader pointed at it, and a kill that writes what it was asked

1 is init.  200, 300 and 500 each lead or share another session.  400 is
in this process's session, 777.  600 is a kernel thread, in session 0.
The last is this process, `k5self`.  A kill of 500 under the name `gone`
fails as kill(2) fails for a pid nothing has.

```cu
(def stand-in! (fn (_ envs name v) (List map (fn (_ e) (eval (list (lit set!) name (list (lit lit) v)) e)) envs)))
(do (def me (sys-getpid)) (proc-run (list "/bin/sh" "-c" (string-append "rm -rf /tmp/x-cu-k5 && mkdir -p /tmp/x-cu-k5/proc && cd /tmp/x-cu-k5/proc && printf 'cpu  1 0 1 1 0 0 0 0 0 0\\nbtime 1790000000\\n' > stat && mk() { d=$1; mkdir $d && printf '%s (%s) S %s %s %s 0 -1 0 0 0 0 0 1 1 0 0 20 0 1 0 100 4096 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\\n' $1 \"$2\" $3 $1 $4 > $d/stat && e=$5 && shift 5 && : > $d/cmdline && for a; do printf '%s\\0' \"$a\" >> $d/cmdline; done && if [ -n \"$e\" ]; then ln -s $e $d/exe; fi; } && mk 1 init 0 1 /sbin/init /sbin/init && mk 200 python3 1 200 /usr/bin/python3 python3 && mk 300 sh 1 300 /bin/busybox -sh && mk 400 sleep 1 777 /bin/sleep sleep 4242 && mk 500 sleep 300 300 /bin/sleep sleep 99 && mk 600 kworker/0:1 2 0 '' && mk " (cu-int->str me) " k5self 1 777 /tmp/k5self k5self"))) (def nf (fn (_ n) (string-append "/tmp/x-cu-k5/" n))) (def real-kill sys-kill) (def gone (list #f)) (def signame (fn (_ sig) (match ((= sig (pg-signum "STOP")) "STOP") ((= sig (pg-signum "CONT")) "CONT") (#t (cu-int->str sig))))) (def recorder (fn (_ pid sig) (do (display (%str-concat (list "kill " (cu-int->str pid) " " (signame sig) "\n"))) (if (if (first gone) (= pid 500) #f) (real-kill 2147483647 0) 0)))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (%str-concat (list (Str8 replace "\n" "|\n" (file-read-all (nf ".out"))) "stderr:\n" (file-read-all (nf ".err")) "status " (cu-int->str st) "\n")))))))) (def kernel (Host %backend)) (def fixed (fn (_ argv) (do (Host source (lit linux)) (Host proc-root (nf "proc")) (stand-in! (list (module cu/procps)) (lit sys-kill) recorder) (run argv) (stand-in! (list (module cu/procps)) (lit sys-kill) real-kill) (set-first! gone #f) (Host source kernel) (Host proc-root "/proc") ()))) (display (if (file-exists? (nf (string-append "proc/" (cu-int->str me) "/stat"))) "made" "fixture incomplete")))
```
---
    made

## the scan

### every process outside this session but init and a kernel thread, in pid order, with TERM, between a stop and a continue of everything

```cu
(fixed (list "killall5"))
```
---
```output
kill -1 STOP|
kill 200 15|
kill 300 15|
kill 500 15|
kill -1 CONT|
stderr:
status 0
```

### a refused kill is not said, and still counts as signalled

```cu
(do (set-first! gone #t) (fixed (list "killall5" "-9")))
```
---
```output
kill -1 STOP|
kill 200 9|
kill 300 9|
kill 500 9|
kill -1 CONT|
stderr:
status 0
```

### STOP and CONT themselves: no stop and continue around them

```cu
(do (fixed (list "killall5" "-STOP")) (fixed (list "killall5" "-s" "cont")))
```
---
```output
kill 200 STOP|
kill 300 STOP|
kill 500 STOP|
stderr:
status 0
kill 200 CONT|
kill 300 CONT|
kill 500 CONT|
stderr:
status 0
```

## -o

### -o PID and -oPID spare that process; an -o first takes TERM

```cu
(do (fixed (list "killall5" "-HUP" "-o" "300" "-o200")) (fixed (list "killall5" "-o" "500")))
```
---
```output
kill -1 STOP|
kill 500 1|
kill -1 CONT|
stderr:
status 0
kill -1 STOP|
kill 200 15|
kill 300 15|
kill -1 CONT|
stderr:
status 0
```

### every process spared: status 2

```cu
(fixed (list "killall5" "-o" "200" "-o" "300" "-o" "500"))
```
---
```output
kill -1 STOP|
kill -1 CONT|
stderr:
status 2
```

### a word that is no -o PID is said when the scan reaches a process not spared before it, and ends the scan; with every process spared first, it is never read

```cu
(do (fixed (list "killall5" "-1" "foo")) (fixed (list "killall5" "-o" "200" "junk")) (fixed (list "killall5" "-o" "300" "-o" "200" "-o" "500" "junk")))
```
---
```output
kill -1 STOP|
kill -1 CONT|
stderr:
killall5: bad option 'foo'
status 1
kill -1 STOP|
kill -1 CONT|
stderr:
killall5: bad option 'junk'
status 1
kill -1 STOP|
kill -1 CONT|
stderr:
status 2
```

### a PID that is not all an int, and -o last with none

```cu
(do (fixed (list "killall5" "-o" "2x")) (fixed (list "killall5" "-o" "+5")) (fixed (list "killall5" "-o" "99999999999")) (fixed (list "killall5" "-o")) (fixed (list "killall5" "-o" "-5")))
```
---
```output
kill -1 STOP|
kill -1 CONT|
stderr:
killall5: invalid number '2x'
status 1
kill -1 STOP|
kill -1 CONT|
stderr:
killall5: invalid number '+5'
status 1
kill -1 STOP|
kill -1 CONT|
stderr:
killall5: invalid number '99999999999'
status 1
kill -1 STOP|
kill -1 CONT|
stderr:
killall5: invalid number ''
status 1
kill -1 STOP|
kill 200 15|
kill 300 15|
kill 500 15|
kill -1 CONT|
stderr:
status 0
```

## the signal

### a word that names no signal, -s alone, --, -q and a lone -

```cu
(do (fixed (list "killall5" "-NOPE")) (fixed (list "killall5" "-s")) (fixed (list "killall5" "--")) (fixed (list "killall5" "-q")) (fixed (list "killall5" "-")))
```
---
```output
stderr:
killall5: bad signal name 'NOPE'
status 1
stderr:
killall5: bad signal name 's'
status 1
stderr:
killall5: bad signal name '-'
status 1
stderr:
killall5: bad signal name 'q'
status 1
stderr:
killall5: bad signal name ''
status 1
```

## -l

### a number to its name, a name to its number, up to a word that is neither

```cu
(do (run (list "killall5" "-l" "9" "HUP" "137")) (run (list "killall5" "-l" "2" "nope" "3")))
```
---
```output
KILL|
1|
KILL|
stderr:
status 0
INT|
stderr:
killall5: unknown signal 'nope'
status 1
```
