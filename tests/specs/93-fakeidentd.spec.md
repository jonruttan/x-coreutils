# @weight 2

fakeidentd as busybox's.  Each case runs it with ARGS split at spaces: i, as
fakeidentd -i ARGS with INPUT (as printf's %b reads it) on stdin; w, with -w
and a listening socket of 127.0.0.1 on its stdin, as inetd hands a wait
service one, and a TCP connection sent INPUT; w2, two in turn; n, with no
input, for the cases that end at once.  Every expectation is busybox's own
output for the same case: === before each answer, the status (i and n),
then stderr, a CR shown as ^M.

## the fixture

### a fakeidentd, a query, and the report

```cu
(do (import x/sys/socket)
  (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-fakeidentd && mkdir -p /tmp/x-cu-fakeidentd"))
  (def fi-f (fn (_ n) (string-append "/tmp/x-cu-fakeidentd/" n)))
  (def fi-cr (fn (_ s) (Str8 replace "\r" "^M" s)))
  (def fi-args (fn (_ s) (filter (fn (_ w) (> (byte-len w) 0)) (Str8 split " " s))))
  (def fi-in (fn (_ s)
    (sys-setenv "FI_IN" s)
    (proc-run (list "/bin/sh" "-c" "printf '%b' \"$FI_IN\" > /tmp/x-cu-fakeidentd/in"))
    (file-read-all (fi-f "in"))))
  (def fi-run (fn (_ argv in)
    (sys-dup2 1 9) (sys-dup2 2 8)
    (let ((oo (file-open-write (fi-f "out"))) (ee (file-open-write (fi-f "err"))))
      (do (sys-dup2 oo 1) (sys-dup2 ee 2)
          (def st (cu-run (pair "fakeidentd" argv) in))
          (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
          (string-concat (list (fi-cr (file-read-all (fi-f "out"))) "[status " (cu-int->str st) "]\n"
                               (fi-cr (file-read-all (fi-f "err")))))))))
  (def fi-ask (fn (_ port req)
    (let ((c (Socket tcp-connect "127.0.0.1" port)))
      (do (when (> (byte-len req) 0) (Socket send c req)) (Socket shutdown c)
          (let go ((acc ""))
            (let ((r (guard (_ ()) (Socket recv-run c 4096))))
              (if (null? r) (do (Socket close c) (fi-cr acc))
                (go (string-append acc (substring (first r) 0 (rest r)))))))))))
  (def fi-wait (fn (_ argv req twice?)
    (def l (Socket tcp-listen-on "127.0.0.1" 0 5))
    (def port (Socket local-port l))
    (def pid (sys-fork))
    (if (= pid 0)
      (do (sys-dup2 l 0) (sys-dup2 (file-open-write (fi-f "err")) 2)
          (sys-exit (cu-run (pair "fakeidentd" (pair "-w" argv)) "")))
      (do (Socket close l)
          (def one (string-append "===\n" (fi-ask port req)))
          (def two (if twice? (string-append "===\n" (fi-ask port req)) ""))
          (sys-usleep 300000) (sys-kill pid 15) (sys-wait pid)
          (string-concat (list one two (fi-cr (file-read-all (fi-f "err")))))))))
  (def fi (fn (_ args kind input)
    (display
      (match ((string=? kind "i") (string-append "===\n" (fi-run (pair "-i" (fi-args args)) (fi-in input))))
             ((string=? kind "n") (fi-run (fi-args args) ""))
             (#t (fi-wait (fi-args args) (fi-in input) (string=? kind "w2")))))))
  (display "made"))
```
---
    made

## busybox's fakeidentd

### -i: the query and the answer

```cu
(fi "" "i" "6193, 23\\r\\n")
```
---
```output
===
6193, 23 : USERID : UNIX : nobody^M
[status 0]
```

### -i: STRING the user named

```cu
(fi "alice" "i" "6193, 23\\r\\n")
```
---
```output
===
6193, 23 : USERID : UNIX : alice^M
[status 0]
```

### -i: a line ended by LF alone

```cu
(fi "" "i" "1, 2\\n")
```
---
```output
===
1, 2 : USERID : UNIX : nobody^M
[status 0]
```

### -i: only what comes before the first CR or LF

```cu
(fi "" "i" "1, 2\\rmore\\n")
```
---
```output
===
1, 2 : USERID : UNIX : nobody^M
[status 0]
```

### -i: no line end, the answer at end of input

```cu
(fi "" "i" "1, 2")
```
---
```output
===
1, 2 : USERID : UNIX : nobody^M
[status 0]
```

### -i: an empty line

```cu
(fi "" "i" "\\r\\n")
```
---
```output
===
 : USERID : UNIX : nobody^M
[status 0]
```

### -i: no input at all

```cu
(fi "" "i" "")
```
---
```output
===
 : USERID : UNIX : nobody^M
[status 0]
```

### -i: a line past 59 bytes, cut at 59

```cu
(fi "" "i" "123456789012345678901234567890123456789012345678901234567890123456789\\r\\n")
```
---
```output
===
12345678901234567890123456789012345678901234567890123456789 : USERID : UNIX : nobody^M
[status 0]
```

### -i: the lines after the first not read

```cu
(fi "" "i" "1, 2\\r\\n3, 4\\r\\n")
```
---
```output
===
1, 2 : USERID : UNIX : nobody^M
[status 0]
```

### -w: a wait service, one query

```cu
(fi "bob" "w" "6193, 23\\r\\n")
```
---
```output
===
6193, 23 : USERID : UNIX : bob^M
```

### -w: two queries in turn

```cu
(fi "" "w2" "7, 8\\r\\n")
```
---
```output
===
7, 8 : USERID : UNIX : nobody^M
===
7, 8 : USERID : UNIX : nobody^M
```

### -b: an address that is not one

```cu
(fi "-f -b nope" "n" "")
```
---
```output
[status 1]
fakeidentd: bad address 'nope'
```

### an option it does not take

```cu
(fi "-x" "n" "")
```
---
```output
[status 1]
fakeidentd: unrecognized option: x
Usage: fakeidentd [-fiw] [-b ADDR] [STRING]

Provide fake ident (auth) service

	-f	Run in foreground
	-i	Inetd mode
	-w	Inetd 'wait' mode
	-b ADDR	Bind to specified address
	STRING	Ident answer string (default: nobody)
```
