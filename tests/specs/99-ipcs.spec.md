# @weight 1

busybox's ipcs and ipcrm (util-linux/ipcs.c, util-linux/ipcrm.c) on Darwin,
whose kernel walks its System V objects for the kern.sysv.ipcs sysctls
rather than answering SHM_STAT and the rest.  The fixture makes a shared
memory segment, a semaphore array with a value set and a message queue
holding two messages, under keys 0x7a110001 to 0x7a110003.  Each listing's
line for them is checked against the system's own ipcs, its facts written
with busybox's formats by the shell's printf; the limits against ipcs -T;
the use against what ipcs lists.  -i prints the kernel's whole mode, which
on Darwin carries the bit that marks a segment (04000) or an array (01000)
in use.  The listings are tested against busybox
itself in the Linux leg.

## the fixture

### a run of an applet, with its stdout, stderr and status; the objects made

```cu
(do (def ic-f (fn (_ n) (string-append "/tmp/x-cu-ipcs." n)))
    (def ic-sh (fn (_ cmd)
      (do (proc-run (list "/bin/sh" "-c" (string-concat (list "{ " cmd "\n} > " (ic-f "sh") " 2>&1"))))
          (file-read-all (ic-f "sh")))))
    (def ic-run (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (ic-f "out"))) (ee (file-open-write (ic-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2) (file-close oo) (file-close ee)))
          (def ic-st (cu-run argv ""))
          (sys-dup2 9 1) (sys-dup2 8 2)
          (string-concat (list (file-read-all (ic-f "out")) "stderr:\n" (file-read-all (ic-f "err")) "status " (cu-int->str ic-st) "\n")))))
    ; ARGV run, then the shell's CHECK, which reads its output in $OUT
    (def ic-check (fn (_ argv check)
      (do (ic-run argv)
          (display (ic-sh (string-concat (list "OUT=" (ic-f "out") "\n" ic-oracle check)))))))
    ; the system ipcs's line for a key, as $1...; busybox's printf of it beside ours
    (def ic-oracle
      (Str8 join "\n"
        (list "row() { set -- $(/usr/bin/ipcs -a | awk -v k=\"$1\" '$3==k'); R=\"$*\"; }"
              "same() { if [ \"$1\" = \"$2\" ]; then echo same; else printf 'ours:\\n%s\\noracle:\\n%s\\n' \"$1\" \"$2\"; fi; }"
              "line() { grep \"^$1\" \"$OUT\"; }"
              "")))
    (def ic-c (fn (_ name args) (Sys %sign-fold (apply cu-ptr-call (pair (cu-libc-sym name) args)))))
    (def ic-zeros (fn (_ n) (let ((b (str-make-raw n))) (do (List map (fn (_ i) (cu-ptr-set! (cu-str->ptr b) i 0 1)) (List range 0 n)) b))))
    (def ic-gone (fn (_)
      (do (List map (fn (_ k) (let ((id (ic-c "shmget" (list k 0 0)))) (when (>= id 0) (ic-c "shmctl" (list id 0 0)))))
            (list 2047934465 2047934468))
          (List map (fn (_ k) (let ((id (ic-c "semget" (list k 0 0)))) (when (>= id 0) (ic-c "__semctl" (list id 0 0 0)))))
            (list 2047934466 2047934469))
          (List map (fn (_ k) (let ((id (ic-c "msgget" (list k 0)))) (when (>= id 0) (ic-c "msgctl" (list id 0 0)))))
            (list 2047934467 2047934470)))))
    (def ic-send (fn (_ id text)
      (do (def b (ic-zeros 64))
          (cu-ptr-set! (cu-str->ptr b) 0 1 8)
          (List map (fn (_ i) (cu-ptr-set! (cu-str->ptr b) (+ 8 i) (byte-at text i) 1)) (List range 0 (byte-len text)))
          (ic-c "msgsnd" (list id b (byte-len text) 0)))))
    (ic-gone)
    (ic-c "shmget" (list 2047934465 4096 (+ 512 416)))
    (def ic-sem (ic-c "semget" (list 2047934466 3 (+ 512 384))))
    (def ic-op (ic-zeros 8))
    (cu-ptr-set! (cu-str->ptr ic-op) 0 1 2) (cu-ptr-set! (cu-str->ptr ic-op) 2 2 2)
    (ic-c "semop" (list ic-sem ic-op 1))
    (def ic-q (ic-c "msgget" (list 2047934467 (+ 512 432))))
    (ic-send ic-q "hello") (ic-send ic-q "goodbye")
    (display "made"))
```
---
    made

## the options

### unknown options, the usage, numbers refused, a kind -i needs

```cu
(do (display (ic-run (list "ipcs" "-z")))
    (display (ic-run (list "ipcs" "-i" "5")))
    (display (ic-run (list "ipcs" "-m" "-i" "-x")))
    (display (ic-run (list "ipcs" "-m" "-i" "3000000000")))
    (display (ic-run (list "ipcs" "-m" "-i" "-3000000000")))
    (display (ic-run (list "ipcs" "-m" "-i" "99999999999"))))
```
---
```output
stderr:
ipcs: unrecognized option: z
Usage: ipcs [[-smq] -i SHMID] | [[-asmq] [-tcplu]]

	-i ID	Show specific resource
Resource specification:
	-m	Shared memory segments
	-q	Message queues
	-s	Semaphore arrays
	-a	All (default)
Output format:
	-t	Time
	-c	Creator
	-p	Pid
	-l	Limits
	-u	Summary
status 1
stderr:
Usage: ipcs [[-smq] -i SHMID] | [[-asmq] [-tcplu]]

	-i ID	Show specific resource
Resource specification:
	-m	Shared memory segments
	-q	Message queues
	-s	Semaphore arrays
	-a	All (default)
Output format:
	-t	Time
	-c	Creator
	-p	Pid
	-l	Limits
	-u	Summary
status 1
stderr:
ipcs: invalid number 'x'
status 1
stderr:
ipcs: number 3000000000 is not in 0..2147483647 range
status 1
stderr:
ipcs: number 3000000000 is not in 0..2147483647 range
status 1
stderr:
ipcs: invalid number '99999999999'
status 1
```

### ipcrm: nothing given, an unknown option, the old form without ids, ids and keys refused

```cu
(do (display (ic-run (list "ipcrm")))
    (display (ic-run (list "ipcrm" "-z")))
    (display (ic-run (list "ipcrm" "shm")))
    (display (ic-run (list "ipcrm" "shm" "x" "-1" "2147483648")))
    (display (ic-run (list "ipcrm" "-m" "x")))
    (display (ic-run (list "ipcrm" "-M" "0" "-Q" "0x100000000")))
    (display (ic-run (list "ipcrm" "-m" "999999" "-S" "0x7a1100ff"))))
```
---
```output
stderr:
status 0
stderr:
ipcrm: unrecognized option: z
Usage: ipcrm [-MQS key] [-mqs id]

Upper-case options MQS remove an object by shmkey value.
Lower-case options remove an object by shmid value.

	-mM	Remove memory segment after last detach
	-qQ	Remove message queue
	-sS	Remove semaphore
status 1
stderr:
Usage: ipcrm [-MQS key] [-mqs id]

Upper-case options MQS remove an object by shmkey value.
Lower-case options remove an object by shmid value.

	-mM	Remove memory segment after last detach
	-qQ	Remove message queue
	-sS	Remove semaphore
status 1
stderr:
ipcrm: invalid id: x
ipcrm: invalid id: -1
ipcrm: invalid id: 2147483648
status 1
stderr:
ipcrm: invalid number 'x'
status 1
stderr:
ipcrm: illegal key (0)
ipcrm: illegal key (0x100000000)
status 2
stderr:
ipcrm: invalid id (999999)
ipcrm: invalid key (0x7a1100ff)
status 2
```

## the listings

### each kind's line, as the system's ipcs reports the object

```cu
(do (ic-check (list "ipcs" "-m")
      "row 0x7a110001; set -- $R; same \"$(line 0x7a110001)\" \"$(printf '0x%08x %-10d %-10.10s %-10s %-10d %-10d %-6s %-6s' 0x7a110001 $2 $5 640 ${10} $9 ' ' ' ')\"")
    (ic-check (list "ipcs" "-s")
      "row 0x7a110002; set -- $R; same \"$(line 0x7a110002)\" \"$(printf '0x%08x %-10d %-10.9s %-10s %-10d' 0x7a110002 $2 $5 600 $9)\"")
    (ic-check (list "ipcs" "-q")
      "row 0x7a110003; set -- $R; same \"$(line 0x7a110003)\" \"$(printf '0x%08x %-10d %-10.10s %-10s %-12d %-12d' 0x7a110003 $2 $5 660 $9 ${10})\""))
```
---
```output
same
same
same
```

### creators, pids, and the times of what has not happened

```cu
(do (ic-check (list "ipcs" "-m" "-c")
      "row 0x7a110001; set -- $R; same \"$(line \"$2 \")\" \"$(printf '%-10d %-10s %-10s %-10s %-10s %-10s' $2 640 $7 $8 $5 $6)\"")
    (ic-check (list "ipcs" "-q" "-c")
      "row 0x7a110003; set -- $R; same \"$(line \"$2 \")\" \"$(printf '%-10d %-10s %-10s %-10s %-10s %-10s' $2 660 $7 $8 $5 $6)\"")
    (ic-check (list "ipcs" "-m" "-p")
      "row 0x7a110001; set -- $R; same \"$(line \"$2 \")\" \"$(printf '%-10d %-10.10s %-10d %-10d' $2 $5 ${11} ${12})\"")
    (ic-check (list "ipcs" "-q" "-p")
      "row 0x7a110003; set -- $R; same \"$(line \"$2 \")\" \"$(printf '%-8d %-10.10s  %5d     %5d' $2 $5 ${12} ${13})\"")
    (ic-check (list "ipcs" "-m" "-t")
      "row 0x7a110001; set -- $R; same \"$(line \"$2 \" | cut -c1-63)\" \"$(printf '%-10d %-10.10s %-20s %-20s' $2 $5 'Not set' 'Not set')\""))
```
---
```output
same
same
same
same
same
```

### the limits, as ipcs -T reports them; the use, counted from what ipcs lists

```cu
(do (ic-check (list "ipcs" "-l")
      (Str8 join "\n"
        (list "t() { /usr/bin/ipcs -T | awk -v k=\"$1:\" '$1==k{print $2}'; }"
              "same \"$(cat $OUT)\" \"$(printf '\\n------ Messages: Limits --------\\nmax queues system wide = %d\\nmax size of message (bytes) = %d\\ndefault max size of queue (bytes) = %d\\n\\n------ Shared Memory Limits --------\\nmax number of segments = %d\\nmax seg size (kbytes) = %d\\nmax total shared memory (pages) = %d\\nmin seg size (bytes) = %d\\n\\n------ Semaphore Limits --------\\nmax number of arrays = %d\\nmax semaphores per array = %d\\nmax semaphores system wide = %d\\nmax ops per semop call = %d\\nsemaphore max value = %d\\n' $(t msgmni) $(t msgmax) $(t msgmnb) $(t shmmni) $(( $(t shmmax) / 1024 )) $(t shmall) $(t shmmin) $(t semmni) $(t semmsl) $(t semmns) $(t semopm) $(t semvmx))\"")))
    (ic-check (list "ipcs" "-u")
      "same \"$(cat $OUT)\" \"$(/usr/bin/ipcs -a | awk -v p=$(pagesize) '$1==\"m\"{m++; pg+=int(($10+p-1)/p)} $1==\"s\"{s++; ns+=$9} $1==\"q\"{q++; qn+=$10; cb+=$9} END{printf \"\\n------ Messages: Status --------\\nallocated queues = %d\\nused headers = %d\\nused space = %d bytes\\n\\n------ Shared Memory Status --------\\nsegments allocated %d\\npages allocated %d\\npages resident  0\\npages swapped   0\\nSwap performance: 0 attempts\\t0 successes\\n\\n------ Semaphore Status --------\\nused arrays = %d\\nallocated semaphores = %d\\n\", q, qn, cb, m, pg, s, ns}')\""))
```
---
```output
same
same
```

### one object: each kind, the semaphores' values and the last pid to change them

```cu
(do (ic-run (list "ipcs" "-m" "-i" (cu-int->str (ic-c "shmget" (list 2047934465 0 0)))))
    (display (ic-sh (string-concat (list "OUT=" (ic-f "out") "\n" ic-oracle
      "row 0x7a110001; set -- $R; same \"$(sed -n 2,6p $OUT)\" \"$(printf 'Shared memory Segment shmid=%d\\nuid=%d\\tgid=%d\\tcuid=%d\\tcgid=%d\\nmode=04640\\taccess_perms=0640\\nbytes=4096\\tlpid=0\\tcpid=%d\\tnattch=0\\natt_time=Not set                   ' $2 $(id -u) $(id -g) $(id -u) $(id -g) ${11})\""))))
    (ic-run (list "ipcs" "-s" "-i" (cu-int->str ic-sem)))
    (display (ic-sh (string-concat (list "OUT=" (ic-f "out") "\n" ic-oracle
      "same \"$(sed -n '2,5p;9,12p' $OUT)\" \"$(printf 'Semaphore Array semid=%d\\nuid=%d\\t gid=%d\\t cuid=%d\\t cgid=%d\\nmode=01600, access_perms=0600\\nnsems = 3\\n0          0          0          0          0         \\n1          2          0          0          %-10d\\n2          0          0          0          0         \\n' " (cu-int->str ic-sem) " $(id -u) $(id -g) $(id -u) $(id -g) " (cu-int->str (sys-getpid)) ")\""))))
    (ic-run (list "ipcs" "-q" "-i" (cu-int->str ic-q)))
    (display (ic-sh (string-concat (list "OUT=" (ic-f "out") "\n" ic-oracle
      "same \"$(sed -n 2,4p $OUT)\" \"$(printf 'Message Queue msqid=%d\\nuid=%d\\tgid=%d\\tcuid=%d\\tcgid=%d\\tmode=0660\\ncbytes=12\\tqbytes=2048\\tqnum=2\\tlspid=%d\\tlrpid=0' " (cu-int->str ic-q) " $(id -u) $(id -g) $(id -u) $(id -g) " (cu-int->str (sys-getpid)) ")\""))))
    (display (ic-run (list "ipcs" "-m" "-i" "999999"))))
```
---
```output
same
same
same
stderr:
ipcs: shmctl: Invalid argument
status 0
```

## removals

### by id and by key, each kind, and the old form; what the system's ipcs lists after

```cu
(do (ic-c "shmget" (list 2047934468 4096 (+ 512 384)))
    (ic-c "semget" (list 2047934469 1 (+ 512 384)))
    (ic-c "msgget" (list 2047934470 (+ 512 384)))
    (display (ic-run (list "ipcrm" "-m" (cu-int->str (ic-c "shmget" (list 2047934465 0 0))) "-S" "0x7a110002"
                           "-Q" "2047934467" "-M" "017204200004")))
    (display (ic-run (list "ipcrm" "sem" (cu-int->str (ic-c "semget" (list 2047934469 0 0))))))
    (display (ic-run (list "ipcrm" "-q" (cu-int->str (ic-c "msgget" (list 2047934470 0))))))
    (display (ic-sh "/usr/bin/ipcs -a | grep -c 0x7a1100 ")))
```
---
```output
stderr:
status 0
resource(s) deleted
stderr:
status 0
stderr:
status 0
0
```

### the fixture's files gone

```cu
(do (ic-gone) (proc-run (list "/bin/sh" "-c" "rm -f /tmp/x-cu-ipcs.*")) (display ""))
```
---
```output
```
