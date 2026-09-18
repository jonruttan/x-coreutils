# @weight 2

What the tools that read each file on its own say when one will not read --
a file that is not there, and a directory, which opens and will not read.
Each says it and passes over it, and the others are still done: the
digests, cksum, sum, wc, split, dos2unix and unix2dos.  The expected text
and statuses are GNU's for the same files.

## the fixtures

### two files, a directory, and a reader for both streams

`a` holds `a` and `b` holds `b`, a line each; `dd` is a directory.

```cu
(do (def eh (fn (_ n) (string-append "/tmp/x-cu-ef/" n))) (def mk (fn (_) (proc-run (list "/bin/sh" "-c" "chmod -R u+rwx /tmp/x-cu-ef 2>/dev/null; rm -rf /tmp/x-cu-ef && mkdir -p /tmp/x-cu-ef/dd && cd /tmp/x-cu-ef && printf 'a\\n' > a && printf 'b\\n' > b && printf 'x\\r\\n' > crlf && printf 'x\\r\\n' > locked && chmod 444 locked")))) (mk) (def seen (fn (_ s) (Str8 replace "/tmp/x-cu-ef/" "" s))) (def ef (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (eh ".out"))) (ee (file-open-write (eh ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def ef-st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (seen (file-read-all (eh ".out")))) (display (seen (file-read-all (eh ".err")))) (display "status ") (display ef-st) (newline)))))) (def squeeze (fn (_ s) (%cu-join-with (map (fn (_ l) (%cu-join-with (%cu-words-line l) " ")) (%cu-lines s)) "\n"))) (display "made"))
```
---
    made

## the digests

### a file that is not there is said, and the others are still summed

```cu
(do (ef (list "md5sum" (eh "a") (eh "nosuch") (eh "b"))) (ef (list "sha1sum" (eh "a") (eh "nosuch"))) (ef (list "cksum" (eh "a") (eh "nosuch") (eh "b"))) (ef (list "sum" (eh "a") (eh "nosuch") (eh "b"))))
```
---
```output
60b725f10c9c85c70d97880dfe8191b3  a
3b5d5c3712955042212316173ccf37be  b
md5sum: nosuch: No such file or directory
status 1
3f786850e387550fdab836ed7e6dc881de23001b  a
sha1sum: nosuch: No such file or directory
status 1
2418082923 2 a
2454254050 2 b
cksum: nosuch: No such file or directory
status 1
32826     1 a
00059     1 b
sum: nosuch: No such file or directory
status 1
```

### so is a directory

```cu
(do (ef (list "sha256sum" (eh "a") (eh "dd"))) (ef (list "sha512sum" (eh "dd") (eh "b"))))
```
---
```output
87428fc522803d31065e7bce3cf03fe475096631e5e07bbd7a0fde60c4cf25c7  a
sha256sum: dd: Is a directory
status 1
868a6ac6e1d0293d74fad07f6d95952b3e01d3d3153db677a75d8077983fd4e30db6bfc89b7608a93fb26469233a9f1a09572d687a9c5da78b203eb151040a15  b
sha512sum: dd: Is a directory
status 1
```

### -c counts a listed file it cannot read as one that failed to open

The OK and FAILED lines and the status; the warnings -c writes are its own.

```cu
(do (proc-run (list "/bin/sh" "-c" "cd /tmp/x-cu-ef && printf '60b725f10c9c85c70d97880dfe8191b3  /tmp/x-cu-ef/a\\n60b725f10c9c85c70d97880dfe8191b3  /tmp/x-cu-ef/dd\\n' > list")) (sys-dup2 2 8) (let ((ee (file-open-write (eh ".err")))) (do (sys-dup2 ee 2) (def st (cu-run (list "md5sum" "-c" (eh "list")) "")) (sys-dup2 8 2) (file-close ee) (display "status ") (display st) (newline))))
```
---
```output
/tmp/x-cu-ef/a: OK
/tmp/x-cu-ef/dd: FAILED open or read
status 1
```

## wc

### a file that is not there gets no row; a directory gets one, of nothing

The rows are shown with their blanks squeezed: the columns' widths are not
what this is about.

```cu
(do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (eh ".out"))) (ee (file-open-write (eh ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def wc-st (cu-run (list "wc" (eh "a") (eh "nosuch") (eh "dd") (eh "b")) "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (seen (squeeze (file-read-all (eh ".out"))))) (newline) (display (seen (file-read-all (eh ".err")))) (display "status ") (display wc-st) (newline))))
```
---
```output
1 1 2 a
0 0 0 dd
1 1 2 b
wc: nosuch: No such file or directory
wc: dd: Is a directory
status 1
```

## split, dos2unix and unix2dos

### split says a file that will not open, and one that will not read, its own way

```cu
(do (ef (list "split" (eh "nosuch") (eh "pre"))) (ef (list "split" (eh "dd") (eh "pre"))))
```
---
```output
split: cannot open 'nosuch' for reading: No such file or directory
status 1
split: dd: Is a directory
status 1
```

### dos2unix passes over what it cannot read or write back, and converts the rest

```cu
(do (mk) (ef (list "dos2unix" (eh "nosuch") (eh "dd") (eh "locked") (eh "crlf"))) (display (string-append "crlf now holds " (%cu-int->str (byte-len (file-read-all (eh "crlf")))) " bytes\n")) (ef (list "unix2dos" (eh "nosuch"))))
```
---
```output
dos2unix: nosuch: No such file or directory
dos2unix: dd: Is a directory
dos2unix: locked: Permission denied
status 1
crlf now holds 2 bytes
unix2dos: nosuch: No such file or directory
status 1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "chmod -R u+rwx /tmp/x-cu-ef; rm -rf /tmp/x-cu-ef")) (display "clean"))
```
---
    clean
