# @weight 2

busybox's logger (sysklogd/logger.c), run as root with /dev/log held by a
forked reader that writes each datagram it receives in brackets, its time
stamp taken out.  Each case runs the bundle's logger with the case's
arguments and standard input, then busybox's, and compares what each wrote,
its status and the datagrams the reader got; a line of the report past 200
bytes is shown by its length.

## the comparison

### the applet against busybox's, the reader started afresh for each

```cu
(do (import x/sys/socket)
    (def lg-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lg-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lg-reader (fn (_)
      (do (lg-sh "rm -f /dev/log; : > /tmp/lg-got")
          (def fd (Socket unix-dgram-bind "/dev/log"))
          (def pid (sys-fork))
          (when (= pid 0)
            (guard (_ (sys-exit 0))
              (let go ()
                (let ((r (Socket recv fd 4096)))
                  (do (let ((f (file-open-append "/tmp/lg-got")))
                        (do (file-write f (%str-concat (list "[" r "]\n"))) (file-close f)))
                      (go))))))
          (Socket close fd)
          pid)))
    (def lg-got (fn (_ pid)
      (do (lg-sh "sleep 0.3")
          (sys-kill pid 9) (sys-wait pid)
          (lg-sh "sed -E 's/^\\[<([0-9]+)>[A-Z][a-z]{2} [ 0-9][0-9] [0-9:]{8} /[<\\1>/' /tmp/lg-got > /tmp/lg-got2")
          (file-read-all "/tmp/lg-got2"))))
    (def lg-ours (fn (_ args input)
      (do (def pid (lg-reader))
          (sys-dup2 1 9) (sys-dup2 2 8)
          (def oo (file-open-write "/tmp/lg-o")) (def ee (file-open-write "/tmp/lg-e"))
          (sys-dup2 oo 1) (sys-dup2 ee 2)
          (def st (cu-run (pair "logger" args) input))
          (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
          (%str-concat (list (file-read-all "/tmp/lg-o") "stderr:\n" (file-read-all "/tmp/lg-e")
                             "status " (cu-int->str st) "\nsent:\n" (lg-got pid))))))
    (def lg-busybox (fn (_ args input)
      (do (def pid (lg-reader))
          (file-write-all "/tmp/lg-in" input)
          (lg-sh (%str-concat (list "/usr/local/bin/busybox-extra logger " (Str8 join " " (map lg-q args))
                                    " < /tmp/lg-in > /tmp/lg-o 2> /tmp/lg-x; echo $? > /tmp/lg-s;"
                                    " sed '/^BusyBox v/{N;d;}' /tmp/lg-x > /tmp/lg-e")))
          (%str-concat (list (file-read-all "/tmp/lg-o") "stderr:\n" (file-read-all "/tmp/lg-e")
                             "status " (file-read-all "/tmp/lg-s") "sent:\n" (lg-got pid))))))
    (def lg-case (fn (_ args input)
      (do (def a (lg-ours args input)) (def b (lg-busybox args input))
          (file-write-all "/tmp/lg-show" (if (string=? a b) (string-append a "busybox: same\n")
                                           (%str-concat (list "ours:\n" a "busybox:\n" b))))
          ; a line past 200 bytes is shown by its length
          (lg-sh "awk 'length($0) > 200 { print \"(\" length($0) \" bytes)\"; next } { print }' /tmp/lg-show > /tmp/lg-show2")
          (display (file-read-all "/tmp/lg-show2")))))
    (display "made"))
```
---
    made

## a message from the arguments

### the words joined, tagged with the user's name, as user.notice

```cu
(lg-case (list "hello" "world") "")
```
---
```output
stderr:
status 0
sent:
[<13>root: hello world
]
busybox: same
```

### a tag, a facility and level, and a percent sign

```cu
(lg-case (list "-t" "tg" "-p" "daemon.err" "100%" "%s" "done") "")
```
---
```output
stderr:
status 0
sent:
[<27>tg: 100% %s done
]
busybox: same
```

## priorities

### numbers, names in any case, none, mark and security

```cu
(do (lg-case (list "-p" "9" "nine") "")
    (lg-case (list "-p" "1.2" "kern") "")
    (lg-case (list "-p" "12x" "twelve") "")
    (lg-case (list "-p" "AUTHPRIV.Warning" "ap") "")
    (lg-case (list "-p" "local3.none" "n") "")
    (lg-case (list "-p" "mark.info" "m") "")
    (lg-case (list "-p" "security.emerg" "s") ""))
```
---
```output
stderr:
status 0
sent:
[<9>root: nine
]
busybox: same
stderr:
status 0
sent:
[<2>root: kern
]
busybox: same
stderr:
status 0
sent:
[<12>root: twelve
]
busybox: same
stderr:
status 0
sent:
[<84>root: ap
]
busybox: same
stderr:
status 0
sent:
[<152>root: n
]
busybox: same
stderr:
status 0
sent:
[<198>root: m
]
busybox: same
stderr:
status 0
sent:
[<32>root: s
]
busybox: same
```

## standard input

### each line, but an empty one; the last without its newline

```cu
(lg-case (list "-t" "sin") "a\n\n%s b\n\nlast")
```
---
```output
stderr:
status 0
sent:
[<13>sin: a
]
[<13>sin: %s b
]
[<13>sin: last
]
busybox: same
```

### a line longer than the read buffer, in pieces

```cu
(lg-case (list "-t" "long") (string-append (Str8 repeat 3000 "x") "\nend\n"))
```
---
```output
stderr:
status 0
sent:
(1008 bytes)
]
(1008 bytes)
]
(965 bytes)
]
[<13>long: end
]
busybox: same
```

### nothing at all

```cu
(lg-case (list "-t" "none") "")
```
---
```output
stderr:
status 0
sent:
busybox: same
```

## -s

### each message on standard error too

```cu
(do (lg-case (list "-s" "-t" "se" "to" "stderr") "")
    (lg-case (list "-s" "-t" "se") "one\ntwo\n"))
```
---
```output
stderr:
se: to stderr
status 0
sent:
[<13>se: to stderr
]
busybox: same
stderr:
se: one
se: two
status 0
sent:
[<13>se: one
]
[<13>se: two
]
busybox: same
```
