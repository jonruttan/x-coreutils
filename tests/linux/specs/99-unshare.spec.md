# @weight 1

busybox's unshare (util-linux/unshare.c), run as root against busybox's
own.  Each case runs the bundle's unshare in a child of this file's
process, since unshare becomes PROG, then busybox's on the same words; a
shell command after each side shows what outlived it, and undoes it.  The
PROGs show the namespaces they were given.  A mount refused names the
process's /proc/PID/ns, so the pid is taken out of both sides.  busybox
runs under a shell, which says `Terminated` when it dies by a signal; that
line is the shell's, and goes.

## the comparison

### the applet against busybox's, a command after each side

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (def lx-pids " | sed -E 's#/proc/[0-9]+/ns#/proc/PID/ns#'")
    (def lx-after (fn (_ post)
      (do (lx-sh (%str-concat (list "{ " post "; } > /tmp/lx-us-af 2>&1")))
          (lx-read "/tmp/lx-us-af"))))
    (def lx-x1 (fn (_ argv post)
      (do (def lx-kid (sys-fork))
          (when (= lx-kid 0)
            (do (sys-dup2 (file-open-write "/tmp/lx-us-xo") 1) (sys-dup2 (file-open-write "/tmp/lx-us-xx") 2)
                (sys-exit (cu-run argv ""))))
          (def lx-st (sys-wait lx-kid))
          (lx-sh (string-append "cat /tmp/lx-us-xx" (string-append lx-pids " > /tmp/lx-us-xe")))
          (%str-concat (list (lx-read "/tmp/lx-us-xo") "stderr:\n" (lx-read "/tmp/lx-us-xe") "status " (cu-int->str lx-st) "\n" (lx-after post))))))
    (def lx-bb1 (fn (_ argv post)
      (do (lx-sh (%str-concat (list "/bin/busybox " (Str8 join " " (map lx-q argv)) " > /tmp/lx-us-bo 2> /tmp/lx-us-bx; echo $? > /tmp/lx-us-bs; sed '/^BusyBox v/{N;d;}; /^Terminated$/d' /tmp/lx-us-bx" lx-pids " > /tmp/lx-us-be")))
          (%str-concat (list (lx-read "/tmp/lx-us-bo") "stderr:\n" (lx-read "/tmp/lx-us-be") "status " (lx-read "/tmp/lx-us-bs") (lx-after post))))))
    (def lx-case (fn (_ argv post)
      (do (def lx-a (lx-x1 argv post)) (def lx-b (lx-bb1 argv post))
          (display (if (string=? lx-a lx-b) "same\n" (%str-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    (lx-sh "touch /tmp/lx-us-ns /tmp/lx-us-mnt")
    (display "made"))
```
---
    made

## the words

### none, PROG's own words, an unknown option, a prefix of two, an argument missing or not taken

```cu
(do (lx-case (list "unshare" "/bin/echo" "-n" "hi") "true")
    (lx-case (list "unshare" "--" "echo" "-m") "true")
    (lx-case (list "unshare" "nosuch") "true")
    (lx-case (list "unshare" "-x") "true")
    (lx-case (list "unshare" "--mo") "true")
    (lx-case (list "unshare" "--setgroups") "true")
    (lx-case (list "unshare" "--fork=1" "true") "true")
    (lx-case (list "unshare" "--fo" "--map" "--ne" "true") "true"))
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

### --setgroups and --propagation words

```cu
(do (lx-case (list "unshare" "--setgroups=maybe" "true") "true")
    (lx-case (list "unshare" "-r" "--setgroups=allow" "true") "true")
    (lx-case (list "unshare" "--propagation=sideways" "-m" "true") "true")
    (lx-case (list "unshare" "--propagation=sideways" "echo" "ignored") "true")
    (lx-case (list "unshare" "--setgroups=deny" "true") "true"))
```
---
```output
same
same
same
same
same
```

### a login shell when there is no PROG

```cu
(do (lx-sh "printf '#!/bin/sh\\necho $0\\n' > /tmp/lx-us-sh; chmod +x /tmp/lx-us-sh")
    (sys-setenv "SHELL" "/tmp/lx-us-sh")
    (lx-case (list "unshare" "-u") "true")
    (lx-case (list "unshare" "-f" "-n") "true")
    (sys-setenv "SHELL" "/nonexistent")
    (lx-case (list "unshare") "true")
    (sys-setenv "SHELL" "/bin/sh")
    (display ""))
```
---
```output
same
same
same
```

## the namespaces

### each one, shown from inside, and the host's left alone

```cu
(do (lx-case (list "unshare" "-u" "sh" "-c" "hostname lx-us; hostname") "hostname | grep -c lx-us")
    (lx-case (list "unshare" "-n" "sh" "-c" "ip -o link | grep -c UP") "true")
    (lx-case (list "unshare" "--net" "--ipc" "--uts" "true") "true")
    (lx-case (list "unshare" "-p" "-f" "--mount-proc" "sh" "-c" "echo $$; ls /proc | grep -c '^[0-9]'") "true")
    (lx-case (list "unshare" "-p" "--fork" "sh" "-c" "echo $$") "true"))
```
---
```output
same
same
same
same
same
```

### a user namespace: unmapped, mapped to root, setgroups denied

```cu
(do (lx-case (list "unshare" "-U" "id") "true")
    (lx-case (list "unshare" "-r" "sh" "-c" "id; cat /proc/self/uid_map /proc/self/gid_map /proc/self/setgroups") "true")
    (lx-case (list "unshare" "--user" "--setgroups" "deny" "cat" "/proc/self/setgroups") "true"))
```
---
```output
same
same
same
```

### the mount tree's propagation, each word

```cu
(do (def lx-root "awk '$5==\"/\" {sub(/:.*/, \"\", $7); print $7}' /proc/self/mountinfo")
    (lx-case (list "unshare" "-m" "sh" "-c" lx-root) "true")
    (lx-case (list "unshare" "-m" "--propagation" "shared" "sh" "-c" lx-root) "true")
    (lx-case (list "unshare" "-m" "--propagation=slave" "sh" "-c" lx-root) "true")
    (lx-case (list "unshare" "-m" "--propagation=private" "sh" "-c" lx-root) "true")
    (lx-case (list "unshare" "-m" "--propagation=unchanged" "true") "true"))
```
---
```output
same
same
same
same
same
```

### a namespace bound to a file, by this process or by a child while the mount namespace is made

```cu
(do (def lx-bound "awk '$5 ~ /lx-us/ {sub(/:.*/, \"\", $4); print $4, $5}' /proc/self/mountinfo; umount /tmp/lx-us-ns /tmp/lx-us-mnt 2>/dev/null; true")
    (lx-case (list "unshare" "--net=/tmp/lx-us-ns" "true") lx-bound)
    (lx-case (list "unshare" "--mount=/tmp/lx-us-mnt" "true") lx-bound)
    (lx-case (list "unshare" "-m" "--uts=/tmp/lx-us-ns" "true") lx-bound)
    (lx-case (list "unshare" "--net=/nonexistent" "true") lx-bound)
    (lx-case (list "unshare" "-m" "--ipc=/nonexistent" "true") lx-bound)
    (lx-case (list "unshare" "--mount-proc=/nonexistent" "true") lx-bound))
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

### -f: the parent leaves as the child did

```cu
(do (lx-case (list "unshare" "-f" "sh" "-c" "exit 3") "true")
    (lx-case (list "unshare" "-f" "sh" "-c" "kill -TERM $$") "true"))
```
---
```output
same
same
```
