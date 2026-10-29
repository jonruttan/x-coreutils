# @weight 1

busybox's ipcs and ipcrm (util-linux/ipcs.c, util-linux/ipcrm.c), run as
root.  This file's process enters an IPC namespace of its own, so no other
file's objects show and the ids are the ones a fresh kernel gives.  The
listings are compared on one set of objects, made once: a shared memory
segment attached and locked, one attached and then marked to go, one
owned by an id with no name, the two attached held by a child of their
own; a semaphore array with a value set, one owned
by the nameless id; a message queue holding two messages, one owned by the
nameless id.  Each removal starts from a namespace made anew for each side,
the same objects made in it, and the objects left after it are listed by
busybox's ipcs.

## the comparison

### the applets against busybox's, on the objects made once, and on objects made anew for each side

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (def lx-c (fn (_ name args) (in-call (apply cu-ptr-call (pair (cu-libc-sym name) args)))))
    (def lx-fresh (fn (_) (lx-c "unshare" (list 134217728))))
    (def lx-holders ())
    (def lx-buf (fn (_ n) (let ((b (str-make-raw n))) (do (List map (fn (_ i) (cu-ptr-set! (cu-str->ptr b) i 0 1)) (List range 0 n)) b))))
    ; the object's owner and group set to 12345, which has no name
    (def lx-own (fn (_ ctl id)
      (do (def b (lx-buf 256))
          (if (string=? ctl "semctl") (lx-c ctl (list id 0 2 b)) (lx-c ctl (list id 2 b)))
          (cu-ptr-set! (cu-str->ptr b) 4 12345 4) (cu-ptr-set! (cu-str->ptr b) 8 12345 4)
          (if (string=? ctl "semctl") (lx-c ctl (list id 0 1 b)) (lx-c ctl (list id 1 b))))))
    (def lx-send (fn (_ id text)
      (do (def b (lx-buf 64))
          (cu-ptr-set! (cu-str->ptr b) 0 1 8)
          (List map (fn (_ i) (cu-ptr-set! (cu-str->ptr b) (+ 8 i) (byte-at text i) 1)) (List range 0 (byte-len text)))
          (lx-c "msgsnd" (list id b (byte-len text) 0)))))
    (def lx-semop (fn (_ id num op)
      (do (def b (lx-buf 8))
          (cu-ptr-set! (cu-str->ptr b) 0 num 2) (cu-ptr-set! (cu-str->ptr b) 2 op 2)
          (lx-c "semop" (list id b 1)))))
    ; the objects: 0x1234 shm, 0x5678 sem, 0x4321 msg, 0x2222 shm, 0x3333 sem, 0x4444 msg
    (def lx-make (fn (_)
      (do (def m1 (lx-c "shmget" (list 4660 4096 (+ 512 416))))
          (lx-c "shmctl" (list m1 11 0))
          (def m2 (lx-c "shmget" (list 0 100 (+ 512 384))))
          ; a child of its own holds the segments, so no process this file
          ; forks later detaches them as it ends
          (lx-sh "rm -f /tmp/lx-sv-held")
          (def lx-holder (sys-fork))
          (when (= lx-holder 0)
            (do (lx-c "shmat" (list m1 0 0)) (lx-c "shmat" (list m2 0 0)) (lx-c "shmctl" (list m2 0 0))
                (def lx-null (file-open-write "/dev/null"))
                (sys-dup2 lx-null 1) (sys-dup2 lx-null 2)
                (lx-sh "touch /tmp/lx-sv-held") (sys-sleep 600) (sys-exit 0)))
          (set! lx-holders (pair lx-holder lx-holders))
          (lx-sh "while [ ! -e /tmp/lx-sv-held ]; do sleep 0.1; done")
          (lx-own "shmctl" (lx-c "shmget" (list 8738 70000 (+ 512 420))))
          (def s1 (lx-c "semget" (list 22136 3 (+ 512 384))))
          (lx-semop s1 1 2)
          (lx-own "semctl" (lx-c "semget" (list 13107 1 (+ 512 438))))
          (def q1 (lx-c "msgget" (list 17185 (+ 512 432))))
          (lx-send q1 "hello") (lx-send q1 "goodbye")
          (lx-own "msgctl" (lx-c "msgget" (list 17476 (+ 512 384))))
          (lx-c "msgget" (list 0 (+ 512 256))))))
    ; WORDS with ID and KEY... standing for the objects' ids and keys
    (def lx-words (fn (_ argv)
      (map (fn (_ w) (List fold (fn (_ s e) (Str8 replace (first e) (rest e) s)) w
                       (list (pair "SHMID" (cu-int->str (lx-c "shmget" (list 4660 0 0))))
                             (pair "SEMID" (cu-int->str (lx-c "semget" (list 22136 0 0))))
                             (pair "MSQID" (cu-int->str (lx-c "msgget" (list 17185 0)))))))
           argv)))
    (def lx-x (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (def lx-o (file-open-write "/tmp/lx-sv-xo")) (def lx-e (file-open-write "/tmp/lx-sv-xe"))
          (sys-dup2 lx-o 1) (sys-dup2 lx-e 2)
          (def lx-st (cu-run (lx-words argv) ""))
          (sys-dup2 9 1) (sys-dup2 8 2) (file-close lx-o) (file-close lx-e)
          (%str-concat (list (lx-read "/tmp/lx-sv-xo") "stderr:\n" (lx-read "/tmp/lx-sv-xe") "status " (cu-int->str lx-st) "\n")))))
    (def lx-bb (fn (_ argv)
      (do (lx-sh (%str-concat (list "/bin/busybox " (Str8 join " " (map lx-q (lx-words argv))) " > /tmp/lx-sv-bo 2> /tmp/lx-sv-bx; echo $? > /tmp/lx-sv-bs; sed '/^BusyBox v/{N;d;}' /tmp/lx-sv-bx > /tmp/lx-sv-be")))
          (%str-concat (list (lx-read "/tmp/lx-sv-bo") "stderr:\n" (lx-read "/tmp/lx-sv-be") "status " (lx-read "/tmp/lx-sv-bs"))))))
    (def lx-show (fn (_ a b) (display (if (string=? a b) "same\n" (%str-concat (list "ours:\n" a "busybox:\n" b))))))
    ; a listing, on the objects made once
    (def lx-case (fn (_ argv) (lx-show (lx-x argv) (lx-bb argv))))
    ; a removal: for each side a namespace made anew, the objects made in it,
    ; RUN and then busybox's listing of what is left
    (def lx-left (fn (_ run argv)
      (do (lx-fresh) (lx-make)
          (def r (run argv))
          (lx-sh "/bin/busybox ipcs > /tmp/lx-sv-left")
          (string-append r (lx-read "/tmp/lx-sv-left")))))
    (def lx-rm (fn (_ argv) (lx-show (lx-left lx-x argv) (lx-left lx-bb argv))))
    (lx-fresh)
    (lx-make)
    (display "made"))
```
---
    made

## ipcs

### every kind, each kind, two of them, the options after an operand left alone

```cu
(do (lx-case (list "ipcs"))
    (lx-case (list "ipcs" "-a"))
    (lx-case (list "ipcs" "-m"))
    (lx-case (list "ipcs" "-s"))
    (lx-case (list "ipcs" "-q"))
    (lx-case (list "ipcs" "-qs"))
    (lx-case (list "ipcs" "-m" "-a"))
    (lx-case (list "ipcs" "x" "-m")))
```
---
```output
same
same
same
same
same
same
same
same
```

### the formats: times, creators, pids, limits, use; the last of them wins

```cu
(do (lx-case (list "ipcs" "-t"))
    (lx-case (list "ipcs" "-c"))
    (lx-case (list "ipcs" "-p"))
    (lx-case (list "ipcs" "-l"))
    (lx-case (list "ipcs" "-u"))
    (lx-case (list "ipcs" "-s" "-t"))
    (lx-case (list "ipcs" "-q" "-p"))
    (lx-case (list "ipcs" "-tcplu"))
    (lx-case (list "ipcs" "-pt")))
```
---
```output
same
same
same
same
same
same
same
same
same
```

### one object: each kind, none such, no kind named, the number refused

```cu
(do (lx-case (list "ipcs" "-m" "-i" "SHMID"))
    (lx-case (list "ipcs" "-i" "SEMID" "-s"))
    (lx-case (list "ipcs" "-qiMSQID"))
    (lx-case (list "ipcs" "-i" "SHMID" "-msq"))
    (lx-case (list "ipcs" "-m" "-i" "999"))
    (lx-case (list "ipcs" "-s" "-i" "999"))
    (lx-case (list "ipcs" "-q" "-i" "999"))
    (lx-case (list "ipcs" "-i" "0"))
    (lx-case (list "ipcs" "-m" "-i" "x"))
    (lx-case (list "ipcs" "-m" "-i" "-x"))
    (lx-case (list "ipcs" "-m" "-i" "+0"))
    (lx-case (list "ipcs" "-m" "-i" "-2147483648"))
    (lx-case (list "ipcs" "-m" "-i" "99999999999"))
    (lx-case (list "ipcs" "-m" "-i" "99999999999999999999"))
    (lx-case (list "ipcs" "-m" "-i" " 1"))
    (lx-case (list "ipcs" "-z"))
    (lx-case (list "ipcs" "-i")))
```
---
```output
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
```

## ipcrm

### by id and by key, each kind, in hex, octal and decimal

```cu
(do (lx-rm (list "ipcrm" "-m" "SHMID"))
    (lx-rm (list "ipcrm" "-s" "SEMID" "-q" "MSQID"))
    (lx-rm (list "ipcrm" "-M" "0x1234"))
    (lx-rm (list "ipcrm" "-S" "0x5678"))
    (lx-rm (list "ipcrm" "-Q" "041441"))
    (lx-rm (list "ipcrm" "-Q" "17476" "-M" "8738" "-S0x3333")))
```
---
```output
same
same
same
same
same
same
```

### what cannot be removed: no such id or key, the private key, a number refused, words left over

```cu
(do (lx-rm (list "ipcrm" "-m" "999999" "-s" "999999" "-q" "999999"))
    (lx-rm (list "ipcrm" "-M" "0x7777" "-S" "0x7777" "-Q" "0x7777"))
    (lx-rm (list "ipcrm" "-M" "0" "-m" "SHMID"))
    (lx-rm (list "ipcrm" "-M" "4294967296"))
    (lx-rm (list "ipcrm" "-s" "SEMID" "-m" "x" "-q" "MSQID"))
    (lx-rm (list "ipcrm" "-M" "0x"))
    (lx-rm (list "ipcrm" "-m" "-1"))
    (lx-rm (list "ipcrm" "-m" "18446744073709551615"))
    (lx-rm (list "ipcrm" "-m" "18446744073709551616"))
    (lx-rm (list "ipcrm" "-m" "SHMID" "x"))
    (lx-rm (list "ipcrm" "x" "-m" "SHMID"))
    (lx-rm (list "ipcrm" "-z"))
    (lx-rm (list "ipcrm" "-m"))
    (lx-rm (list "ipcrm")))
```
---
```output
same
same
same
same
same
same
same
same
same
same
same
same
same
same
```

### the old form: each kind, several ids, ids refused or not there, none given

```cu
(do (lx-rm (list "ipcrm" "shm" "SHMID"))
    (lx-rm (list "ipcrm" "sem" "SEMID"))
    (lx-rm (list "ipcrm" "msg" "MSQID" "999999"))
    (lx-rm (list "ipcrm" "shm" "x" "-1" "+1" "2147483648" "SHMID"))
    (lx-rm (list "ipcrm" "shm"))
    (lx-rm (list "ipcrm" "shmx" "1")))
```
---
```output
same
same
same
same
same
same
```

## the end

### the children holding segments stopped

```cu
(do (List map (fn (_ p) (do (sys-kill p 9) (sys-wait p))) lx-holders) (display ""))
```
---
```output
```
