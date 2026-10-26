# @weight 1

busybox's nsenter (util-linux/nsenter.c), run as root against busybox's
own.  Each side makes processes of its own to enter, so neither sees what
the other did: A in new uts, ipc, net and mount namespaces, its hostname
lx-inner, its msgmax 1234, a tmpfs on /mnt holding lx-inner, its working
directory /usr; Q the first process of a new pid namespace; U in a new user
namespace, root mapped to root.  A case's words name them A, Q and U.  The
bundle's nsenter runs in a child of this file's process, so a PROG can take
its place, and the two sides' output and statuses are compared.

## the comparison

### the applet against busybox's, processes of its own on each side

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (def lx-word (fn (_ f) (Str8 replace "\n" "" (lx-read f))))
    (def lx-x1 (fn (_ argv)
      (do (def lx-kid (sys-fork))
          (when (= lx-kid 0)
            (do (sys-dup2 (file-open-read "/dev/null") 0)
                (sys-dup2 (file-open-write "/tmp/lx-ns-xo") 1) (sys-dup2 (file-open-write "/tmp/lx-ns-xe") 2)
                (sys-exit (cu-run argv ""))))
          ; the child's end as the shell reports busybox's: Killed for a
          ; SIGKILL, and 128 and the signal for its status
          (def lx-raw (str-make-raw 4))
          (in-call (cu-ptr-call (in-c "waitpid") lx-kid (cu-str->ptr lx-raw) 0))
          (def lx-w (cu-ptr-ref (cu-str->ptr lx-raw) 0 4))
          (def lx-sig (% lx-w 128))
          (def lx-st (if (> lx-sig 0) (+ 128 lx-sig) (% (>> lx-w 8) 256)))
          (string-concat (list (lx-read "/tmp/lx-ns-xo") "stderr:\n" (lx-read "/tmp/lx-ns-xe")
                               (if (= lx-sig 9) "Killed\n" "") "status " (cu-int->str lx-st) "\n")))))
    (def lx-bb1 (fn (_ argv)
      (do (lx-sh (string-concat (list "/bin/busybox " (Str8 join " " (map lx-q argv)) " < /dev/null > /tmp/lx-ns-bo 2> /tmp/lx-ns-bx; echo $? > /tmp/lx-ns-bs; sed '/^BusyBox v/{N;d;}' /tmp/lx-ns-bx > /tmp/lx-ns-be")))
          (string-concat (list (lx-read "/tmp/lx-ns-bo") "stderr:\n" (lx-read "/tmp/lx-ns-be") "status " (lx-read "/tmp/lx-ns-bs"))))))
    ; the three processes, their pids in /tmp/lx-ns-{a,q,u}
    (def lx-make (fn (_)
      (lx-sh (string-concat (list
        "rm -f /tmp/lx-ns-a /tmp/lx-ns-p /tmp/lx-ns-q /tmp/lx-ns-u; "
        "/bin/busybox unshare -u -i -n -m sh -c 'hostname lx-inner; echo 1234 > /proc/sys/kernel/msgmax; "
        "mount -t tmpfs none /mnt && touch /mnt/lx-inner; cd /usr; echo $$ > /tmp/lx-ns-a; exec sleep 999' > /dev/null 2>&1 & "
        "/bin/busybox unshare -p -f sleep 999 > /dev/null 2>&1 & echo $! > /tmp/lx-ns-p; "
        "/bin/busybox unshare -U -r sh -c 'echo $$ > /tmp/lx-ns-u; exec sleep 999' > /dev/null 2>&1 & "
        ; /proc's files are size 0, so the children are read, and the wait
        ; gives up after 10 s
        "p=$(cat /tmp/lx-ns-p); n=0; while [ $n -lt 100 ] && { [ ! -s /tmp/lx-ns-a ] || [ ! -s /tmp/lx-ns-u ] || "
        "! grep -q . /proc/$p/task/$p/children 2> /dev/null; }; do sleep 0.1; n=$((n + 1)); done; "
        "tr -d ' ' < /proc/$p/task/$p/children > /tmp/lx-ns-q")))))
    (def lx-end (fn (_)
      (lx-sh "kill -9 $(cat /tmp/lx-ns-a) $(cat /tmp/lx-ns-q) $(cat /tmp/lx-ns-u) $(cat /tmp/lx-ns-p) 2> /dev/null; wait")))
    (def lx-run (fn (_ one runs)
      (do (lx-make)
          (def lx-ids (list (pair "A" (lx-word "/tmp/lx-ns-a")) (pair "Q" (lx-word "/tmp/lx-ns-q"))
                            (pair "U" (lx-word "/tmp/lx-ns-u"))))
          (def lx-at (fn (_ w) (let ((e (List find (fn (_ e) (string=? (first e) w)) lx-ids))) (if (null? e) w (rest e)))))
          (def lx-out (string-concat (map (fn (_ argv) (one (map lx-at argv))) runs)))
          (lx-end)
          lx-out)))
    (def lx-case (fn (_ runs)
      (do (def lx-a (lx-run lx-x1 runs)) (def lx-b (lx-run lx-bb1 runs))
          (display (if (string=? lx-a lx-b) "same\n" (string-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    (display "made"))
```
---
    made

## the options

### letters and long names it does not take, a value missing, numbers, a prefix

```cu
(do (lx-case (list (list "nsenter" "-x") (list "nsenter" "--nope") (list "nsenter" "--n")))
    (lx-case (list (list "nsenter" "-t") (list "nsenter" "--target") (list "nsenter" "--preserve-credentials=1" "true")))
    (lx-case (list (list "nsenter" "-t" "abc" "true") (list "nsenter" "-t" "-5" "true")
                   (list "nsenter" "-G" "4294967295" "-x" "id")))
    (lx-case (list (list "nsenter" "--ta" "A" "--ut" "cat" "/proc/sys/kernel/hostname")
                   (list "nsenter" "--pre" "true"))))
```
---
```output
same
same
same
same
```

### no FILE and no -t, -t 0, a FILE only in the option's word, -pF

```cu
(do (lx-case (list (list "nsenter" "-n" "true") (list "nsenter" "-t" "0" "-n" "true")))
    (lx-case (list (list "nsenter" "-w" "pwd") (list "nsenter" "--net" "/proc/1/ns/net" "true")))
    (lx-case (list (list "nsenter" "-t" "A" "-pF" "true"))))
```
---
```output
same
same
same
```

## the namespaces

### each of A's, by -t and by FILE, and all of them at once

```cu
(do (lx-case (list (list "nsenter" "-t" "A" "-u" "cat" "/proc/sys/kernel/hostname")
                   (list "nsenter" "-t" "A" "-i" "cat" "/proc/sys/kernel/msgmax")
                   (list "nsenter" "-t" "A" "-n" "cat" "/proc/net/dev")))
    (lx-case (list (list "nsenter" "-t" "A" "-m" "ls" "/mnt")
                   (list "nsenter" "--mount=/proc/A/ns/mnt" "--uts=/proc/A/ns/uts" "cat" "/proc/sys/kernel/hostname" "/mnt/lx-inner")
                   (list "nsenter" "-n/proc/A/ns/net" "cat" "/proc/net/dev")))
    (lx-case (list (list "nsenter" "-t" "A" "-m" "-u" "-i" "-n" "-w" "-r" "pwd"))))
```
---
```output
same
same
same
```

### a pid namespace: the fork, the child's status, a signal's end, -F

```cu
(do (lx-case (list (list "nsenter" "-t" "Q" "-p" "sh" "-c" "echo $$")
                   (list "nsenter" "-t" "Q" "-p" "sh" "-c" "exit 3")
                   (list "nsenter" "-t" "Q" "-p" "sh" "-c" "kill -9 $$")))
    (lx-case (list (list "nsenter" "-t" "Q" "-p" "-F" "sh" "-c" "test $$ -gt 1"))))
```
---
```output
same
same
```

### a user namespace: root in it, the ids kept, its own namespace refused

```cu
(do (lx-case (list (list "nsenter" "-t" "U" "-U" "id")
                   (list "nsenter" "-t" "U" "-U" "--preserve-credentials" "id")
                   (list "nsenter" "-t" "U" "-U" "-S" "5" "id")))
    (lx-case (list (list "nsenter" "-U/proc/self/ns/user" "true"))))
```
---
```output
same
same
```

### what is refused: no such process, a FILE that is not there or not a namespace of the kind

```cu
(do (lx-case (list (list "nsenter" "-t" "999999" "-n" "true") (list "nsenter" "-m/nope" "true")))
    (lx-case (list (list "nsenter" "-m/proc/1/ns/net" "true") (list "nsenter" "-n/etc/passwd" "true"))))
```
---
```output
same
same
```

## the rest

### directories, ids, PROG and a login shell

```cu
(do (lx-case (list (list "nsenter" "-t" "A" "-w" "pwd") (list "nsenter" "--root=/" "--wd=/etc" "pwd")
                   (list "nsenter" "-r/tmp" "pwd")))
    (lx-case (list (list "nsenter" "-S" "65534" "-G" "65534" "id") (list "nsenter" "--setgid=65534" "id")))
    (lx-case (list (list "nsenter" "nsenter-no-such-command") (list "nsenter" "/etc/passwd")
                   (list "nsenter" "echo" "-n" "hi") (list "nsenter" "--" "echo" "-F")))
    (lx-sh "mkdir -p /tmp/lx-ns-home && echo 'echo login' > /tmp/lx-ns-home/.profile")
    (sys-setenv "HOME" "/tmp/lx-ns-home")
    (sys-setenv "SHELL" "/bin/sh")
    (lx-case (list (list "nsenter")))
    (sys-setenv "SHELL" "/nope/sh")
    (lx-case (list (list "nsenter"))))
```
---
```output
same
same
same
same
same
```
