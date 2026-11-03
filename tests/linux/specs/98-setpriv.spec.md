# @weight 1

busybox's setpriv (util-linux/setpriv.c), run as root.  Each side runs in a
child of its own, since setpriv becomes PROG: the bundle's applet, then
busybox's on the same words.  What each writes and its status are compared.
A case may first change the child as both sides are changed -- become
nobody, set no_new_privs, raise capabilities -- so -d is compared in more
than one state.  A PROG that is busybox's setpriv -d shows what was set.

## the comparison

### the applet against busybox's, each in a child set up alike

```cu
(do (def lx-read (fn (_ f) (file-read-all f)))
    (def lx-door (fn (_ name) (syscall-door name)))
    (def lx-prctl (lx-door (lit prctl)))
    ; nobody, in nobody's group alone, every capability gone with root
    (def lx-nobody (fn (_)
      (do (def g (str-make-raw 4)) ((prim-ref (lit ptr) (lit set!)) ((prim-ref (lit str) (lit ->ptr)) g) 0 65534 4)
          ((lx-door (lit setgroups)) 1 g)
          ((lx-door (lit setresgid)) 65534 65534 65534)
          ((lx-door (lit setresuid)) 65534 65534 65534))))
    (def lx-nnp (fn (_) (lx-prctl 38 1 0 0 0)))
    (def lx-none (fn (_) ()))
    (def lx-side (fn (_ pre run tag)
      (do (def lx-o (file-open-write (string-append "/tmp/lx-o" tag)))
          (def lx-e (file-open-write (string-append "/tmp/lx-e" tag)))
          (def lx-child (sys-fork))
          (when (= lx-child 0)
            (do (sys-dup2 lx-o 1) (sys-dup2 lx-e 2) (pre) (sys-exit (run))))
          (file-close lx-o) (file-close lx-e)
          (def lx-st (sys-wait lx-child))
          (proc-run (list "/bin/sh" "-c" (%str-concat (list "sed -i '/^BusyBox v/{N;d;}' /tmp/lx-e" tag))))
          (%str-concat (list (lx-read (string-append "/tmp/lx-o" tag)) "stderr:\n"
                               (lx-read (string-append "/tmp/lx-e" tag)) "status " (cu-int->str lx-st) "\n")))))
    (def lx-case-in (fn (_ pre argv)
      (do (def lx-a (lx-side pre (fn (_) (cu-run argv "")) "x"))
          (def lx-b (lx-side pre (fn (_) (do (sys-exec "/bin/busybox" argv) 99)) "b"))
          (display (if (string=? lx-a lx-b) "same\n" (%str-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    (def lx-case (fn (_ argv) (lx-case-in lx-none argv)))
    (display "made"))
```
---
    made

## the options

### none, -d with more, unknown, ambiguous, a value missing

```cu
(do (lx-case (list "setpriv"))
    (lx-case (list "setpriv" "-d" "true"))
    (lx-case (list "setpriv" "--dump" "--nnp"))
    (lx-case (list "setpriv" "-d" "--inh-caps" "+chown"))
    (lx-case (list "setpriv" "-z" "true"))
    (lx-case (list "setpriv" "--n" "true"))
    (lx-case (list "setpriv" "--inh-caps"))
    (lx-case (list "setpriv" "--nnp")))
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

### prefixes, =VALUE, -d twice, options after PROG

```cu
(do (lx-case (list "setpriv" "--du"))
    (lx-case (list "setpriv" "-d" "-d"))
    (lx-case (list "setpriv" "--inh=+kill" "/bin/busybox" "setpriv" "-d"))
    (lx-case (list "setpriv" "--amb" "-chown" "--no-new" "/bin/busybox" "setpriv" "-d"))
    (lx-case (list "setpriv" "/bin/busybox" "setpriv" "--nnp" "-d")))
```
---
```output
same
same
same
same
same
```

## the dump

### as root, with no_new_privs, as nobody

```cu
(do (lx-case (list "setpriv" "-d"))
    (lx-case-in lx-nnp (list "setpriv" "--dump"))
    (lx-case-in lx-nobody (list "setpriv" "-d")))
```
---
```output
same
same
same
```

## capabilities

### names: by name in any case, by number, signs, empty words, refused

```cu
(do (lx-case (list "setpriv" "--inh-caps" "+CHOWN,+Net_Raw,,+cap_ 5,+cap_+7" "/bin/busybox" "setpriv" "-d"))
    (lx-case (list "setpriv" "--inh-caps" "+cap_40,+cap_38,-cap_40,+audit_read" "/bin/busybox" "setpriv" "-d"))
    (lx-case (list "setpriv" "--inh-caps" "cap_40" "true"))
    (lx-case (list "setpriv" "--inh-caps" "+cap_41" "true"))
    (lx-case (list "setpriv" "--inh-caps" "+perfmon" "true"))
    (lx-case (list "setpriv" "--inh-caps" "+cap_-0,+cap_1x" "/bin/busybox" "setpriv" "-d"))
    (lx-case (list "setpriv" "--inh-caps" "+cap_-1" "true"))
    (lx-case (list "setpriv" "--inh-caps" "+" "true"))
    (lx-case (list "setpriv" "--inh-caps" "" "/bin/busybox" "setpriv" "-d")))
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

### ambient: raised with the inheritable, refused without, lowered

```cu
(do (lx-case (list "setpriv" "--inh-caps" "+chown,+kill" "--ambient-caps" "+chown,+kill,-kill" "/bin/busybox" "setpriv" "-d"))
    (lx-case (list "setpriv" "--ambient-caps" "+chown,+kill" "/bin/busybox" "setpriv" "-d"))
    (lx-case (list "setpriv" "--ambient-caps" "-chown,+bogus" "true"))
    (lx-case (list "setpriv" "--ambient-caps" "+chown")))
```
---
```output
same
same
same
same
```

### as nobody: capset refused, ambient refused, no_new_privs set

```cu
(do (lx-case-in lx-nobody (list "setpriv" "--inh-caps" "+chown" "true"))
    (lx-case-in lx-nobody (list "setpriv" "--inh-caps" "-chown" "/bin/busybox" "setpriv" "-d"))
    (lx-case-in lx-nobody (list "setpriv" "--ambient-caps" "+chown" "true"))
    (lx-case-in lx-nobody (list "setpriv" "--nnp" "/bin/busybox" "setpriv" "-d")))
```
---
```output
same
same
same
same
```

## a PROG

### not found, not runnable, its status

```cu
(do (lx-case (list "setpriv" "nosuchprog"))
    (lx-case (list "setpriv" "/etc"))
    (lx-case (list "setpriv" "--nnp" "sh" "-c" "exit 3")))
```
---
```output
same
same
same
```
