# @weight 2

busybox's pstree (procps/pstree.c) over trees of processes made here: a
shell starts each tree's children in the background and becomes the
tree's top with exec, and the cases wait until every process in the tree
shows the program it became.  Each case draws one tree by its top's id;
the table's other processes are this host's and are not drawn.  Threads,
users and busybox's own drawing of the same trees are tested as root in
the Linux leg.

## the fixture

### trees of processes, a run of pstree, what it writes and its status

```cu
(do (def pt-f (fn (_ n) (string-append "/tmp/x-cu-pst." n)))
    (def pt-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (pt-f "out"))) (ee (file-open-write (pt-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (pt-f "out")) "stderr:\n"
                                              (file-read-all (pt-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (def pt-pids (fn (_ ps ppid)
      (List sort (fn (_ a b) (< a b))
        (map (fn (_ p) (Assoc get (lit pid) p))
             (List filter (fn (_ p) (= (Assoc get (lit ppid) p) ppid)) ps)))))
    (def pt-comm (fn (_ ps pid) (Assoc get (lit comm) (List find (fn (_ p) (= (Assoc get (lit pid) p) pid)) ps))))
    ; the tree from TOP as names: its own, then each child's, a slash and its children's
    (def pt-shape (fn (_ ps top)
      (pair (pt-comm ps top) (map (fn (_ k) (%str-concat (pair (pt-comm ps k) (pair "/" (map (fn (_ g) (pt-comm ps g)) (pt-pids ps k))))))
           (pt-pids ps top)))))
    (def pt-wait (fn (self top want n)
      (cu-heap-collect)
      (if (if (> n 0) (not (equal? (pt-shape (host-processes) top) want)) #f)
        (do (sys-usleep 200000) (self top want (- n 1)))
        (equal? (pt-shape (host-processes) top) want))))
    ; SCRIPT run by a shell with no terminal and no pipe of this file's
    (def pt-start (fn (_ script)
      (let ((pid (sys-fork)))
        (if (= pid 0)
          (do (sys-exec "/bin/sh" (list "-c" (string-append "exec < /dev/null > /dev/null 2>&1; " script)))
              (sys-exit 127))
          pid))))
    (def pt-end (fn (_ top)
      (do (def ps (host-processes))
          (def all (List flat-map (fn (_ k) (pair k (pt-pids ps k))) (pair top (pt-pids ps top))))
          (map (fn (_ p) (sys-kill p 9)) all)
          (sys-wait top)
          ())))
    (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-pst.d; mkdir /tmp/x-cu-pst.d && cp /bin/sleep '/tmp/x-cu-pst.d/s\tl' && cp /bin/sleep '/tmp/x-cu-pst.d/s\\l'"))
    (def pt-a (pt-start (%str-concat (list
                "/bin/sleep 600 & /bin/sleep 600 & "
                "/bin/sh -c '/bin/sleep 600 & exec /bin/sleep 600' & "
                "/bin/sh -c '/bin/sleep 600 & exec /bin/sleep 600' & "
                "/usr/bin/tail -f /dev/null & exec /bin/sleep 601"))))
    (def pt-b (pt-start "'/tmp/x-cu-pst.d/s\\l' 600 & '/tmp/x-cu-pst.d/s\tl' 600 & exec /bin/sleep 601"))
    (sys-unsetenv "COLUMNS")
    (display (list (pt-wait pt-a (list "sleep" "sleep/" "sleep/" "sleep/sleep" "sleep/sleep" "tail/") 100)
                   (pt-wait pt-b (list "sleep" "s\\l/" "s\tl/") 100))))
```
---
    (#t #t)

## the tree

### a run of children with the same trees drawn once, then by id with -p

```cu
(pt-show (list "pstree" (cu-int->str pt-a)))
```
---
```output
sleep-+-2*[sleep]
      |-2*[sleep---sleep]
      `-tail
stderr:
status 0
```

```cu
(do (def pa (cu-int->str pt-a))
    (def ps (host-processes))
    (def gs (pt-pids ps pt-a))
    (def pid (fn (_ p) (%str-concat (list "(" (cu-int->str p) ")"))))
    (def pad (%str-concat (map (fn (_ i) " ") (List range 0 (+ (byte-len pa) 8)))))
    (sys-dup2 1 9) (def oo (file-open-write (pt-f "p"))) (sys-dup2 oo 1)
    (def st (cu-run (list "pstree" "-p" pa) ""))
    (sys-dup2 9 1) (file-close oo)
    (def want (%str-concat (list
      "sleep" (pid pt-a) "-+-sleep" (pid (List ref 0 gs)) "\n"
      pad "|-sleep" (pid (List ref 1 gs)) "\n"
      pad "|-sleep" (pid (List ref 2 gs)) "---sleep" (pid (first (pt-pids ps (List ref 2 gs)))) "\n"
      pad "|-sleep" (pid (List ref 3 gs)) "---sleep" (pid (first (pt-pids ps (List ref 3 gs)))) "\n"
      pad "`-tail" (pid (List ref 4 gs)) "\n")))
    (def got (file-read-all (pt-f "p")))
    (display (if (string=? got want) (list st "same") (list st got want))))
```
---
    (0 same)

### a name's backslash doubled and its control bytes in octal

```cu
(pt-show (list "pstree" (cu-int->str pt-b)))
```
---
```output
sleep-+-s\011l
      `-s\\l
stderr:
status 0
```

## the width

### $COLUMNS cuts each line, its last column a +, and the children of a cut line are not drawn

```cu
(do (sys-setenv "COLUMNS" "12")
    (pt-show (list "pstree" (cu-int->str pt-a)))
    (sys-unsetenv "COLUMNS")
    (display ""))
```
---
```output
sleep-+-2*[+
      |-2*[+
      `-tai+
stderr:
status 0
```

### a width of 1, or none in $COLUMNS, is 80

```cu
(do (sys-setenv "COLUMNS" "1")
    (pt-show (list "pstree" (cu-int->str pt-b)))
    (sys-setenv "COLUMNS" "x")
    (pt-show (list "pstree" (cu-int->str pt-b)))
    (sys-unsetenv "COLUMNS")
    (display ""))
```
---
```output
sleep-+-s\011l
      `-s\\l
stderr:
status 0
sleep-+-s\011l
      `-s\\l
stderr:
status 0
```

## the operands

### an id none has draws nothing; leading zeros are read past

```cu
(pt-show (list "pstree" "0000999999"))
```
---
```output
stderr:
status 0
```

### a number that is not one, past an unsigned int, past an int

```cu
(do (pt-show (list "pstree" "1x"))
    (pt-show (list "pstree" "4294967296"))
    (pt-show (list "pstree" "3000000000")))
```
---
```output
stderr:
pstree: invalid number '1x'
status 1
stderr:
pstree: invalid number '4294967296'
status 1
stderr:
pstree: number 3000000000 is not in 0..2147483647 range
status 1
```

### a user there is none of

```cu
(pt-show (list "pstree" "x-cu-no-such-user"))
```
---
```output
stderr:
pstree: unknown user x-cu-no-such-user
status 1
```

### two operands

```cu
(pt-show (list "pstree" "1" "2"))
```
---
```output
stderr:
Usage: pstree [-p] [PID|USER]

Display process tree, optionally start from USER or PID

	-p	Show pids
status 1
```

## the end

### the trees taken down

```cu
(do (pt-end pt-a) (pt-end pt-b) (proc-run (list "/bin/rm" "-rf" "/tmp/x-cu-pst.d")) (display "gone"))
```
---
    gone
