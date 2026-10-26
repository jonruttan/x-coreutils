# @weight 2

busybox's pstree (procps/pstree.c), against busybox's own on trees of
processes made here.  The table is the whole container's, and other files'
processes come and go in it, so each case draws one of these trees: by its
top's id, by a thread's id, or by a user, lxpst, made for this file and
owning only processes it starts.  Each case runs the bundle's pstree and
busybox's on the same words, $COLUMNS set for both or for neither, and
compares what they write and their statuses: `same`, or both.

## the comparison

### the trees, then the applet against busybox's

```cu
(do (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all (string-append "/tmp/lx-pst/" f))))
    (def lx-x (fn (_ cols argv)
      (do (if (null? cols) (sys-unsetenv "COLUMNS") (sys-setenv "COLUMNS" cols))
          (sys-dup2 1 9) (sys-dup2 2 8)
          (def lx-o (file-open-write "/tmp/lx-pst/xo")) (def lx-e (file-open-write "/tmp/lx-pst/xe"))
          (sys-dup2 lx-o 1) (sys-dup2 lx-e 2)
          (def lx-st (cu-run argv ""))
          (sys-dup2 9 1) (sys-dup2 8 2) (file-close lx-o) (file-close lx-e)
          (sys-unsetenv "COLUMNS")
          (string-concat (list (lx-read "xo") "stderr:\n" (lx-read "xe") "status " (cu-int->str lx-st) "\n")))))
    (def lx-bb (fn (_ cols argv)
      (do (lx-sh (string-concat (list (if (null? cols) "unset COLUMNS; " (string-concat (list "COLUMNS=" (lx-q cols) " ")))
                                      "/bin/busybox " (Str8 join " " (map lx-q argv))
                                      " > /tmp/lx-pst/bo 2> /tmp/lx-pst/bx; echo $? > /tmp/lx-pst/bs; sed '/^BusyBox v/{N;d;}' /tmp/lx-pst/bx > /tmp/lx-pst/be")))
          (string-concat (list (lx-read "bo") "stderr:\n" (lx-read "be") "status " (lx-read "bs"))))))
    (def lx-case (fn (_ cols argv)
      (do (def lx-a (lx-x cols argv)) (def lx-b (lx-bb cols argv))
          (display (if (string=? lx-a lx-b) "same\n" (string-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    ; a tree's top: its id, once no process under it is still a shell
    (def lx-top (fn (_ name)
      (let ((p (Str8 replace "\n" "" (lx-read name))))
        (do (lx-sh (string-concat (list "n=0; while [ $n -lt 100 ] && busybox pstree " p " | grep -q sh; do n=$((n+1)); sleep 0.1; done")))
            p))))
    (lx-sh (Str8 join "\n" (list
      "rm -rf /tmp/lx-pst; mkdir /tmp/lx-pst && cd /tmp/lx-pst || exit 1"
      "cat > thr.c <<'EOF'"
      "#define _GNU_SOURCE"
      "#include <pthread.h>"
      "#include <unistd.h>"
      "static void *run(void *a) { if (a) pthread_setname_np(pthread_self(), a); sleep(600); return 0; }"
      "int main(int c, char **v) { pthread_t t; for (int i = 1; i < c; i++) pthread_create(&t, 0, run, v[i][0] == '-' ? 0 : v[i]); sleep(600); return 0; }"
      "EOF"
      "cc -o thr thr.c -lpthread || exit 1"
      "cp thr 't\\b'; cp thr \"t$(printf '\\001')x\"; cp thr abcdefghijklmnopqrstu"
      "adduser -D -H lxpst 2>/dev/null"
      ; a: threads, runs of children alike, a run of trees alike, odd names
      "(sleep 600 & sleep 600 & (sleep 600 & exec sleep 601) & (sleep 600 & exec sleep 601) &"
      " ./thr - - ab 'a\\b' \"$(printf '\\tq')\" & ./'t\\b' & ./\"t$(printf '\\001')x\" & ./abcdefghijklmnopqrstu &"
      " exec sleep 602) < /dev/null > /dev/null 2>&1 &"
      "echo $! > a"
      ; lxpst: a process alone, and one with a child
      "su lxpst -s /bin/sh -c 'exec sleep 603' < /dev/null > /dev/null 2>&1 &"
      "su lxpst -s /bin/sh -c 'sleep 603 & exec sleep 604' < /dev/null > /dev/null 2>&1 &"
      "sleep 1"
      "true")))
    (def lx-a (lx-top "a"))
    (def lx-val (fn (_ cmd) (do (lx-sh (string-append cmd " > /tmp/lx-pst/v")) (Str8 replace "\n" "" (lx-read "v")))))
    (def lx-thr (lx-val "busybox pidof thr"))
    (def lx-tid (lx-val (string-append "ls /proc/" lx-thr "/task | sort -n | tail -1")))
    (display (list (> (byte-len lx-a) 0) (> (byte-len lx-thr) 0) (> (byte-len lx-tid) 0))))
```
---
    (#t #t #t)

## the tree

### by its top, with ids, a thread alone

```cu
(do (lx-case () (list "pstree" lx-a))
    (lx-case () (list "pstree" "-p" lx-a))
    (lx-case () (list "pstree" lx-thr))
    (lx-case () (list "pstree" "-p" lx-tid)))
```
---
```output
same
same
same
same
```

### cut at $COLUMNS, at the width of a connector, too narrow to read, none

```cu
(do (lx-case "12" (list "pstree" lx-a))
    (lx-case "9" (list "pstree" "-p" lx-a))
    (lx-case "26" (list "pstree" lx-a))
    (lx-case "1" (list "pstree" lx-a))
    (lx-case "x" (list "pstree" lx-a)))
```
---
```output
same
same
same
same
same
```

## a user

### each tree under 1 its user's, a blank line between; a user with none

```cu
(do (lx-case () (list "pstree" "lxpst"))
    (lx-case () (list "pstree" "-p" "lxpst"))
    (lx-case () (list "pstree" "nobody")))
```
---
```output
same
same
same
```

## the operands

### no such id, numbers that are not, an unknown user, two operands, an unknown option

```cu
(do (lx-case () (list "pstree" "0000999999"))
    (lx-case () (list "pstree" "1x"))
    (lx-case () (list "pstree" "4294967296"))
    (lx-case () (list "pstree" "3000000000"))
    (lx-case () (list "pstree" "nosuchuser"))
    (lx-case () (list "pstree" "1" "2"))
    (lx-case () (list "pstree" "-x")))
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
```

## the end

### the trees taken down

```cu
(do (lx-sh "busybox pkill -9 -u lxpst; for p in $(busybox pgrep -P $(cat /tmp/lx-pst/a)); do busybox pkill -9 -P $p; done; busybox pkill -9 -P $(cat /tmp/lx-pst/a); kill -9 $(cat /tmp/lx-pst/a); deluser lxpst 2>/dev/null; rm -rf /tmp/lx-pst")
    (display "gone"))
```
---
    gone
