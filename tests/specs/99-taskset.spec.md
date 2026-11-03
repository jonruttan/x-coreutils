# @weight 1

busybox's taskset (util-linux/taskset.c) reads its options, a PID and a
mask or list, and asks the kernel for the affinity; Darwin binds no process
to CPUs, so here every process's mask is every CPU online, and a mask is
set only when it holds them all.  Each run is a child of its own, so a PROG
can take its place; the mask asked for is this spec's process's, its pid
shown as PID, and the CPUs it holds are N.  The affinity set and read
through the kernel is tested in the Linux leg, against busybox.

## the fixture

### a run of taskset in a child, what it writes and its status

```cu
(do (def tk-f (fn (_ n) (string-append "/tmp/x-cu-tk." n)))
    (def tk-pid (cu-int->str (sys-getpid)))
    (def tk-n (sys-cpu-count))
    (def tk-ones (fn (self n acc)
      (if (< n 4) (string-append (if (= n 0) "" (cu-int->str (- (<< 1 n) 1))) acc) (self (- n 4) (string-append acc "f")))))
    (def tk-show (fn (_ argv)
      (do (def kid (sys-fork))
          (when (= kid 0)
            (do (sys-dup2 (file-open-write (tk-f "out")) 1) (sys-dup2 (file-open-write (tk-f "err")) 2)
                (sys-exit (cu-run argv ""))))
          (def st (sys-wait kid))
          (def mask (tk-ones tk-n ""))
          (display (Str8 replace (string-append "affinity list: 0-" (cu-int->str (- tk-n 1))) "affinity list: 0-N"
                     (Str8 replace (string-append "affinity mask: " mask "\n") "affinity mask: ALL\n"
                       (Str8 replace (%str-concat (list "pid " tk-pid "'s")) "pid PID's"
                         (%str-concat (list (file-read-all (tk-f "out")) "stderr:\n"
                                              (file-read-all (tk-f "err")) "status " (cu-int->str st) "\n"))))))
          ())))
    (display "made"))
```
---
    made

## the words

### none, a mask with no PROG, -p with nothing after it, options it does not take

```cu
(do (tk-show (list "taskset"))
    (tk-show (list "taskset" "ff"))
    (tk-show (list "taskset" "-p"))
    (tk-show (list "taskset" "-x" "ff" "/bin/echo"))
    (tk-show (list "taskset" "-p" "-1" "1")))
```
---
```output
stderr:
Usage: taskset [-ap] [HEXMASK | -c LIST] { PID | PROG ARGS }

Set or get CPU affinity

	-p	Operate on PID
	-a	Operate on all threads
	-c	Affinity is a list, not mask
status 1
stderr:
Usage: taskset [-ap] [HEXMASK | -c LIST] { PID | PROG ARGS }

Set or get CPU affinity

	-p	Operate on PID
	-a	Operate on all threads
	-c	Affinity is a list, not mask
status 1
stderr:
Usage: taskset [-ap] [HEXMASK | -c LIST] { PID | PROG ARGS }

Set or get CPU affinity

	-p	Operate on PID
	-a	Operate on all threads
	-c	Affinity is a list, not mask
status 1
stderr:
taskset: unrecognized option: x
Usage: taskset [-ap] [HEXMASK | -c LIST] { PID | PROG ARGS }

Set or get CPU affinity

	-p	Operate on PID
	-a	Operate on all threads
	-c	Affinity is a list, not mask
status 1
stderr:
taskset: unrecognized option: 1
Usage: taskset [-ap] [HEXMASK | -c LIST] { PID | PROG ARGS }

Set or get CPU affinity

	-p	Operate on PID
	-a	Operate on all threads
	-c	Affinity is a list, not mask
status 1
```

### PIDs: none of 0, no number, no process

```cu
(do (tk-show (list "taskset" "-p" "0"))
    (tk-show (list "taskset" "-p" "ff" "12x"))
    (tk-show (list "taskset" "-p" "2147483647"))
    (tk-show (list "taskset" "-p" "2147483648")))
```
---
```output
stderr:
taskset: number 0 is not in 1..2147483647 range
status 1
stderr:
taskset: invalid number '12x'
status 1
stderr:
taskset: can't get pid 2147483647's affinity: No such process
status 1
stderr:
taskset: number 2147483648 is not in 1..2147483647 range
status 1
```

## shown

### the mask, the list, each thread's, which with no /proc is PID's

```cu
(do (tk-show (list "taskset" "-p" tk-pid))
    (tk-show (list "taskset" "-pc" tk-pid))
    (tk-show (list "taskset" "-a" "-p" tk-pid)))
```
---
```output
pid PID's current affinity mask: ALL
stderr:
status 0
pid PID's current affinity list: 0-N
stderr:
status 0
pid PID's current affinity mask: ALL
stderr:
status 0
```

## set

### every CPU, a 0x before it, bits past the buffer dropped, a list past the CPUs

```cu
(do (tk-show (list "taskset" "-p" "ffffffffffffffff" tk-pid))
    (tk-show (list "taskset" "-p" "0XFFFFFFFFFFFFFFFF" tk-pid))
    (tk-show (list "taskset" "-p" "123ffffffffffffffff" tk-pid))
    (tk-show (list "taskset" "-pc" "0-4000" tk-pid "ignored")))
```
---
```output
pid PID's current affinity mask: ALL
pid PID's new affinity mask: ALL
stderr:
status 0
pid PID's current affinity mask: ALL
pid PID's new affinity mask: ALL
stderr:
status 0
pid PID's current affinity mask: ALL
pid PID's new affinity mask: ALL
stderr:
status 0
pid PID's current affinity list: 0-N
pid PID's new affinity list: 0-N
stderr:
status 0
```

### some CPUs, none, none online

```cu
(do (tk-show (list "taskset" "-p" "1" tk-pid))
    (tk-show (list "taskset" "-pc" "0-7:2" tk-pid))
    (tk-show (list "taskset" "-p" "0x" tk-pid))
    (tk-show (list "taskset" "-pc" "4000" tk-pid)))
```
---
```output
pid PID's current affinity mask: ALL
stderr:
taskset: can't set pid PID's affinity: Operation not supported
status 1
pid PID's current affinity list: 0-N
stderr:
taskset: can't set pid PID's affinity: Operation not supported
status 1
pid PID's current affinity mask: ALL
stderr:
taskset: can't set pid PID's affinity: Invalid argument
status 1
pid PID's current affinity list: 0-N
stderr:
taskset: can't set pid PID's affinity: Invalid argument
status 1
```

### masks and lists it will not read

```cu
(do (tk-show (list "taskset" "-p" "0xfg" tk-pid))
    (map (fn (_ l) (tk-show (list "taskset" "-pc" l tk-pid)))
         (list "" "a" " 1" "1 " "1-" "3-1" "0-7:0" "0-7:" "1,,2" "1,"
               "0x1" "+1" "1-2:1073741825" "4294967295" "4294967294-4294967295"))
    (display ""))
```
---
```output
pid PID's current affinity mask: ALL
stderr:
taskset: bad affinity 'fg'
status 1
pid PID's current affinity list: 0-N
stderr:
taskset: bad affinity ''
status 1
pid PID's current affinity list: 0-N
stderr:
taskset: bad affinity 'a'
status 1
pid PID's current affinity list: 0-N
stderr:
taskset: bad affinity ' 1'
status 1
pid PID's current affinity list: 0-N
stderr:
taskset: bad affinity '1 '
status 1
pid PID's current affinity list: 0-N
stderr:
taskset: bad affinity '1-'
status 1
pid PID's current affinity list: 0-N
stderr:
taskset: bad affinity '3-1'
status 1
pid PID's current affinity list: 0-N
stderr:
taskset: bad affinity '0-7:0'
status 1
pid PID's current affinity list: 0-N
stderr:
taskset: bad affinity '0-7:'
status 1
pid PID's current affinity list: 0-N
stderr:
taskset: bad affinity '1,,2'
status 1
pid PID's current affinity list: 0-N
stderr:
taskset: bad affinity '1,'
status 1
pid PID's current affinity list: 0-N
stderr:
taskset: bad affinity '0x1'
status 1
pid PID's current affinity list: 0-N
stderr:
taskset: bad affinity '+1'
status 1
pid PID's current affinity list: 0-N
stderr:
taskset: bad affinity '1-2:1073741825'
status 1
pid PID's current affinity list: 0-N
stderr:
taskset: bad affinity '4294967295'
status 1
pid PID's current affinity list: 0-N
stderr:
taskset: bad affinity '4294967294-4294967295'
status 1
```

## PROG

### run with every CPU, its options its own, refused with some, none to run

```cu
(do (tk-show (list "taskset" "ffffffffffffffff" "/bin/echo" "ran"))
    (tk-show (list "taskset" "-c" "0-4000" "/bin/echo" "-p" "x"))
    (tk-show (list "taskset" "1" "/bin/echo" "ran"))
    (tk-show (list "taskset" "ffffffffffffffff" "/nonexist/prog")))
```
---
```output
ran
stderr:
status 0
-p x
stderr:
status 0
stderr:
taskset: can't set pid 0's affinity: Operation not supported
status 1
stderr:
taskset: can't execute '/nonexist/prog': No such file or directory
status 127
```
