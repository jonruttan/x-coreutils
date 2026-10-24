# @weight 2

popmaildir as busybox's, against a scripted POP3 server run as its
connection helper (sh S).  Each case makes /tmp/x-cu-pop afresh: the maildir
D with tmp, new and cur (FLAGS nomd: no maildir; nonew, notmp: no such
subdirectory), and the mailbox BOX (as printf's %b reads it), its messages
split by lines @@, each line sent with CR LF.  The server greets "+OK POP3
ready" (-ERR with nogreet, "+OK <stamp>" with stamp, nothing with mute),
takes USER, PASS (-ERR for "bad"), APOP, STAT (+OK 9 999 with stat9), RETR
and TOP (the message and a dot -- with short no dot, and its stdout closed),
DELE (-ERR with nodele) and QUIT, anything else -ERR.  popmaildir runs in a
child with ARGS (split as sh splits them) and STDIN (as printf's %b reads it).
Every expectation is busybox's own output for the same case, through cat -v:
stdout, the status, stderr, what the server got, each file of new/ and the
count in tmp/, then /tmp/x-cu-pop/filt when the case wrote it -- the name of
a message file shown as tmp/NAME or new/NAME.

## the fixture

### a maildir, a mailbox, a popmaildir, and the report

```cu
(do
  (def pm-f (fn (_ n) (string-append "/tmp/x-cu-pop/" n)))
  (def pm-lines (fn (_ s)
    (let go ((i 0) (acc ()))
      (let ((nl (wget-index s #\newline i)))
        (if (null? nl) (reverse (if (< i (byte-len s)) (pair (substring s i (byte-len s)) acc) acc))
          (go (+ nl 1) (pair (substring s i nl) acc)))))))
  (def pm-sh (fn (_ script) (proc-run (list "/bin/sh" "-c" script))))
  (def pm-srv (string-concat (list
    "exec 2>/dev/null\n"
    "d=/tmp/x-cu-pop; f=\" $(cat $d/flags) \"; cr=$(printf '\\r')\n"
    "has() { case \"$f\" in *\" $1 \"*) return 0;; esac; return 1; }\n"
    "say() { printf '%s\\r\\n' \"$1\"; }\n"
    "n=$(ls $d/box | wc -l | tr -d ' ')\n"
    "has mute && exit 0\n"
    "if has nogreet; then say \"-ERR busy\"; elif has stamp; then say \"+OK <1896.697170952@dbc.mtview.ca.us>\"; else say \"+OK POP3 ready\"; fi\n"
    "while IFS= read -r l; do\n"
    "  l=${l%\"$cr\"}; printf '%s\\n' \"$l\" >> $d/got\n"
    "  set -- $l\n"
    "  case \"$1\" in\n"
    "    USER) say \"+OK user\" ;;\n"
    "    PASS) if [ \"$2\" = bad ]; then say \"-ERR denied\"; else say \"+OK in\"; fi ;;\n"
    "    APOP) say \"+OK in\" ;;\n"
    "    STAT) if has stat9; then say \"+OK 9 999\"; else say \"+OK $n 120\"; fi ;;\n"
    "    RETR|TOP) if [ -f $d/box/$2 ]; then say \"+OK msg\"; cat $d/box/$2; if has short; then exec 1>&-; else say \".\"; fi\n"
    "              else say \"-ERR no such message\"; fi ;;\n"
    "    DELE) if has nodele; then say \"-ERR locked\"; else say \"+OK gone\"; fi ;;\n"
    "    QUIT) say \"+OK bye\"; exit 0 ;;\n"
    "    *) say \"-ERR what\" ;;\n"
    "  esac\n"
    "done\n")))
  (def pm (fn (_ flags args input box)
    (cu-heap-collect)
    (sys-setenv "PM_FLAGS" flags) (sys-setenv "PM_ARGS" args) (sys-setenv "PM_IN" input) (sys-setenv "PM_BOX" box)
    (pm-sh (string-concat (list
      "d=/tmp/x-cu-pop; rm -rf $d; mkdir -p $d/box; "
      "case \" $PM_FLAGS \" in *\" nomd \"*) ;; *) mkdir -p $d/md/tmp $d/md/new $d/md/cur;; esac; "
      "case \" $PM_FLAGS \" in *\" nonew \"*) rmdir $d/md/new;; esac; "
      "case \" $PM_FLAGS \" in *\" notmp \"*) rmdir $d/md/tmp;; esac; "
      "printf '%s' \"$PM_FLAGS\" > $d/flags; : > $d/got; printf '%b' \"$PM_IN\" > $d/in; "
      "printf '%b' \"$PM_BOX\" | awk -v d=$d/box 'BEGIN { n = 1 } /^@@$/ { n++; next } { printf \"%s\\r\\n\", $0 > (d \"/\" n) }'; "
      "eval \"set -- $(printf ' %s ' \"$PM_ARGS\" | sed \"s# D # $d/md #g; s# S # $d/srv #g\")\"; "
      "for a; do printf '%s\\n' \"$a\"; done > $d/argv")))
    (file-write-all (pm-f "srv") pm-srv)
    (def argv (pm-lines (file-read-all (pm-f "argv"))))
    (def in (file-read-all (pm-f "in")))
    (def pid (sys-fork))
    (when (= pid 0)
      (do (Sys chdir "/tmp")
          (sys-dup2 (file-open-write (pm-f "out")) 1) (sys-dup2 (file-open-write (pm-f "err")) 2)
          (sys-exit (guard (e (do (file-write 2 "uncaught\n") 99)) (cu-run (pair "popmaildir" argv) in)))))
    (def st (sys-wait pid))
    (pm-sh (string-concat (list
      "d=/tmp/x-cu-pop; norm() { sed -E \"s#(tmp|new)/[0-9]+\\.[0-9]+\\.[^' ]+#\\1/NAME#g\"; }; "
      "{ LC_ALL=C cat -v $d/out; echo \"[status " (cu-int->str st) "]\"; LC_ALL=C cat -v $d/err | norm; "
      "echo \"--- server got\"; LC_ALL=C cat -v $d/got; "
      "if [ -d $d/md/new ]; then for m in $(ls $d/md/new); do echo \"--- new\"; LC_ALL=C cat -v $d/md/new/$m; done; fi; "
      "if [ -d $d/md/tmp ]; then echo \"--- tmp $(ls $d/md/tmp | wc -l | tr -d ' ')\"; fi; "
      "if [ -e $d/filt ]; then echo \"--- filt\"; LC_ALL=C cat -v $d/filt; fi; } > $d/report")))
    (display (file-read-all (pm-f "report")))))
  (display "made"))
```
---
    made

## busybox's popmaildir

### two messages fetched, each deleted, the last first

```cu
(pm "" "D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 0]
--- server got
USER u
PASS pw
STAT
RETR 2
DELE 2
RETR 1
DELE 1
QUIT
--- new
From: d@e.f^M
Subject: two^M
^M
second^M
.dotted^M
last^M
--- new
From: a@b.c^M
Subject: one^M
^M
hello^M
--- tmp 0
```

### -k keeps them on the server

```cu
(pm "" "-k D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 0]
--- server got
USER u
PASS pw
STAT
RETR 2
RETR 1
QUIT
--- new
From: d@e.f^M
Subject: two^M
^M
second^M
.dotted^M
last^M
--- new
From: a@b.c^M
Subject: one^M
^M
hello^M
--- tmp 0
```

### -T fetches with TOP, -H the lines

```cu
(pm "" "-T -H 5 D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 0]
--- server got
USER u
PASS pw
STAT
TOP 2 5
DELE 2
TOP 1 5
DELE 1
QUIT
--- new
From: d@e.f^M
Subject: two^M
^M
second^M
.dotted^M
last^M
--- new
From: a@b.c^M
Subject: one^M
^M
hello^M
--- tmp 0
```

### -T without -H: TOP N 0

```cu
(pm "" "-T D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 0]
--- server got
USER u
PASS pw
STAT
TOP 2 0
DELE 2
TOP 1 0
DELE 1
QUIT
--- new
From: d@e.f^M
Subject: two^M
^M
second^M
.dotted^M
last^M
--- new
From: a@b.c^M
Subject: one^M
^M
hello^M
--- tmp 0
```

### -s skips the login

```cu
(pm "" "-s D -- sh S" "" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 0]
--- server got
STAT
RETR 2
DELE 2
RETR 1
DELE 1
QUIT
--- new
From: d@e.f^M
Subject: two^M
^M
second^M
.dotted^M
last^M
--- new
From: a@b.c^M
Subject: one^M
^M
hello^M
--- tmp 0
```

### -a with a stamp in the greeting: APOP and the digest

```cu
(pm "stamp" "-a D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 0]
--- server got
APOP u fee8bb0d4776c9e211f670be1263cbaa
STAT
RETR 2
DELE 2
RETR 1
DELE 1
QUIT
--- new
From: d@e.f^M
Subject: two^M
^M
second^M
.dotted^M
last^M
--- new
From: a@b.c^M
Subject: one^M
^M
hello^M
--- tmp 0
```

### -a and no stamp: USER and PASS

```cu
(pm "" "-a D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 0]
--- server got
USER u
PASS pw
STAT
RETR 2
DELE 2
RETR 1
DELE 1
QUIT
--- new
From: d@e.f^M
Subject: two^M
^M
second^M
.dotted^M
last^M
--- new
From: a@b.c^M
Subject: one^M
^M
hello^M
--- tmp 0
```

### a refused password ends the run

```cu
(pm "" "D -- sh S" "u\\nbad\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 1]
popmaildir: PASS bad failed, reply was: -ERR denied^M
--- server got
USER u
PASS bad
--- tmp 0
```

### a refused greeting

```cu
(pm "nogreet" "D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 1]
popmaildir: (null) failed, reply was: -ERR busy^M
--- server got
--- tmp 0
```

### a server that says nothing

```cu
(pm "mute" "-s D -- sh S" "" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 1]
popmaildir: (null) failed, reply was: (null)
--- server got
--- tmp 0
```

### no username or password

```cu
(pm "" "D -- sh S" "" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 1]
popmaildir: no username or password
--- server got
--- tmp 0
```

### a user and no password

```cu
(pm "" "D -- sh S" "u\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 1]
popmaildir: no username or password
--- server got
--- tmp 0
```

### an empty user

```cu
(pm "" "D -- sh S" "\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 1]
popmaildir: no username or password
--- server got
--- tmp 0
```

### no maildir

```cu
(pm "nomd" "D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 1]
popmaildir: can't change directory to '/tmp/x-cu-pop/md': No such file or directory
--- server got
```

### no new/: the move fails, then QUIT

```cu
(pm "nonew" "D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 0]
popmaildir: can't move 'tmp/NAME' to 'new/NAME': No such file or directory
--- server got
USER u
PASS pw
STAT
RETR 2
DELE 2
QUIT
--- tmp 1
```

### no tmp/: the run ends

```cu
(pm "notmp" "D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 1]
popmaildir: can't open 'tmp/NAME': No such file or directory
--- server got
USER u
PASS pw
STAT
RETR 2
```

### a refused DELE

```cu
(pm "nodele" "D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 1]
popmaildir: DELE 2 failed, reply was: -ERR locked^M
--- server got
USER u
PASS pw
STAT
RETR 2
DELE 2
--- tmp 1
```

### a message STAT counts that RETR cannot find

```cu
(pm "stat9" "D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 1]
popmaildir: RETR 9 failed, reply was: -ERR no such message^M
--- server got
USER u
PASS pw
STAT
RETR 9
--- tmp 0
```

### an empty mailbox: STAT, then QUIT

```cu
(pm "" "D -- sh S" "u\\npw\\n" "")
```
---
```output
[status 0]
--- server got
USER u
PASS pw
STAT
QUIT
--- tmp 0
```

### a message cut short: the server's end ends it

```cu
(pm "short" "D -- sh S" "u\\npw\\n" "one\\ntwo")
```
---
```output
[status 1]
popmaildir: DELE 1 failed, reply was: (null)
--- server got
USER u
PASS pw
STAT
RETR 1
DELE 1
--- tmp 1
```

### -F: the message to a filter, kept, nothing in new/

```cu
(pm "" "-F 'cat >> /tmp/x-cu-pop/filt' D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 0]
--- server got
USER u
PASS pw
STAT
RETR 2
RETR 1
QUIT
--- tmp 0
--- filt
From: d@e.f^M
Subject: two^M
^M
second^M
.dotted^M
last^M
From: a@b.c^M
Subject: one^M
^M
hello^M
```

### -M after -F: the last one delivers

```cu
(pm "" "-F 'cat > /dev/null' -M 'cat >> /tmp/x-cu-pop/filt' D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 0]
--- server got
USER u
PASS pw
STAT
RETR 2
RETR 1
QUIT
--- tmp 0
--- filt
From: d@e.f^M
Subject: two^M
^M
second^M
.dotted^M
last^M
From: a@b.c^M
Subject: one^M
^M
hello^M
```

### -M sees FILENAME

```cu
(pm "" "-M 'cut -c1-3 > /dev/null; echo \"$FILENAME\" | cut -c1-4 >> /tmp/x-cu-pop/filt' D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 0]
--- server got
USER u
PASS pw
STAT
RETR 2
RETR 1
QUIT
--- tmp 0
--- filt
tmp/
tmp/
```

### -t takes a number

```cu
(pm "" "-t x D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 1]
popmaildir: invalid number 'x'
--- server got
--- tmp 0
```

### no helper: the server on stdin, the commands on stdout

```cu
(pm "" "-s D" "+OK hi\\r\\n+OK 1 10\\r\\n+OK\\r\\nline\\r\\n.\\r\\n+OK\\r\\n+OK bye\\r\\n" "")
```
---
```output
STAT^M
RETR 1^M
DELE 1^M
QUIT^M
[status 0]
--- server got
--- new
line^M
--- tmp 0
```

### no helper: the login first, then the server

```cu
(pm "" "D" "u\\npw\\n+OK hi\\r\\n+OK\\r\\n+OK\\r\\n+OK 0 0\\r\\n+OK bye\\r\\n" "")
```
---
```output
USER u^M
PASS pw^M
STAT^M
QUIT^M
[status 0]
--- server got
--- tmp 0
```

### options after the maildir

```cu
(pm "" "D -k -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 0]
--- server got
USER u
PASS pw
STAT
RETR 2
RETR 1
QUIT
--- new
From: d@e.f^M
Subject: two^M
^M
second^M
.dotted^M
last^M
--- new
From: a@b.c^M
Subject: one^M
^M
hello^M
--- tmp 0
```

### the ignored options

```cu
(pm "" "-b -m -V -c -Z 1-2 -t 5 D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 0]
--- server got
USER u
PASS pw
STAT
RETR 2
DELE 2
RETR 1
DELE 1
QUIT
--- new
From: d@e.f^M
Subject: two^M
^M
second^M
.dotted^M
last^M
--- new
From: a@b.c^M
Subject: one^M
^M
hello^M
--- tmp 0
```

### -H without -T: no TOP

```cu
(pm "" "-H 3 D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 0]
--- server got
USER u
PASS pw
STAT
RETR 2
DELE 2
RETR 1
DELE 1
QUIT
--- new
From: d@e.f^M
Subject: two^M
^M
second^M
.dotted^M
last^M
--- new
From: a@b.c^M
Subject: one^M
^M
hello^M
--- tmp 0
```

### a stamp, no -a: USER and PASS

```cu
(pm "stamp" "D -- sh S" "u\\npw\\n" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 0]
--- server got
USER u
PASS pw
STAT
RETR 2
DELE 2
RETR 1
DELE 1
QUIT
--- new
From: d@e.f^M
Subject: two^M
^M
second^M
.dotted^M
last^M
--- new
From: a@b.c^M
Subject: one^M
^M
hello^M
--- tmp 0
```

### -a and -s: no login at all

```cu
(pm "stamp" "-a -s D -- sh S" "" "From: a@b.c\\nSubject: one\\n\\nhello\\n@@\\nFrom: d@e.f\\nSubject: two\\n\\nsecond\\n..dotted\\nlast")
```
---
```output
[status 0]
--- server got
STAT
RETR 2
DELE 2
RETR 1
DELE 1
QUIT
--- new
From: d@e.f^M
Subject: two^M
^M
second^M
.dotted^M
last^M
--- new
From: a@b.c^M
Subject: one^M
^M
hello^M
--- tmp 0
```
