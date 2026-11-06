# @weight 1

busybox's bzip2 (archival/bzip2.c on bbunzip.c's bbunpack frame).  Every
expectation is busybox 1.36.1's own output, run as root in alpine, less the
banner line its usage text starts with.  A `|` marks the end of each line
written to standard output; output that is not text is shown as its bytes in
hex, 32 to a line; `after:` is what a command run after shows.  The bytes are
busybox's own: x-lang's Bzip2 writes the stream its compressor writes.

## the fixtures

### the files, and a run of an applet in a fresh directory

`hello` and `three` are text, and `hello.bz2` busybox's bzip2 of `hello`.
Each run is in `/tmp/x-cu-bz2/w`, made afresh from them: PRE runs before the
applet, with standard input the file IN (`-` for none), and POST after it,
both through the shell.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-bz2 && mkdir -p /tmp/x-cu-bz2/fx /tmp/x-cu-bz2/w")) (def bz2-f (fn (_ n) (string-append "/tmp/x-cu-bz2/" n))) (file-write-all (bz2-f "fx/hello") "hello\n") (file-write-all (bz2-f "fx/three") "one\ntwo\nthree\n") (proc-run (list "/bin/sh" "-c" "printf QlpoOTFBWSZTWcHAgOIAAAFBAAAQAkSgADDNAMNGKZcXckU4UJDBwIDi | base64 -d > /tmp/x-cu-bz2/fx/hello.bz2")) (def bz2-home (Sys getcwd)) (def bz2-sh (fn (_ cmd out) (proc-run (list "/bin/sh" "-c" (%str-concat (list "cd /tmp/x-cu-bz2/w && { " cmd "; } > " out " 2>&1")))))) (def bz2-in (fn (_ name) (if (string=? name "-") "" (let ((fd (file-open-read (string-append "/tmp/x-cu-bz2/w/" name))) (buf (str-make-raw 65536))) (let ((n (File read fd buf 65536))) (do (file-close fd) (pair buf n))))))) (def bz2-shown (fn (_ mode) (if (string=? mode "x") (do (proc-run (list "/bin/sh" "-c" "od -An -v -tx1 /tmp/x-cu-bz2/o | tr -d ' \\n' | fold -w 64 > /tmp/x-cu-bz2/hex; echo >> /tmp/x-cu-bz2/hex")) (file-read-all (bz2-f "hex"))) (Str8 replace "\n" "|\n" (file-read-all (bz2-f "o")))))) (def bz2-case (fn (_ fresh in pre post mode argv) (do (if fresh (bz2-sh "cd /tmp/x-cu-bz2 && rm -rf w && mkdir w && cp -p fx/* w/" "/dev/null") ()) (if (string=? pre "@") () (bz2-sh pre "/dev/null")) (def bz2-stdin (bz2-in in)) (Sys chdir "/tmp/x-cu-bz2/w") (sys-dup2 1 9) (sys-dup2 2 8) (def st (let ((oo (file-open-write (bz2-f "o"))) (ee (file-open-write (bz2-f "e")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def rs (cu-run argv bz2-stdin)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) rs))) (Sys chdir bz2-home) (display (%str-concat (list (bz2-shown mode) "stderr:\n" (file-read-all (bz2-f "e")) "status " (cu-int->str st) "\n" (if (string=? post "@") "" (do (bz2-sh post (bz2-f "p")) (string-append "after:\n" (file-read-all (bz2-f "p"))))))))))) (display "made"))
```
---
    made

## bzip2

### standard input to standard output: the stream at -9, and at -1

```cu
(do (bz2-case #t "hello" "@" "@" "x" (list "bzip2")) (bz2-case #t "three" "@" "@" "x" (list "bzip2" "-1")))
```
---
```output
425a6839314159265359c1c080e2000001410000100244a00030cd00c3462997
177245385090c1c080e2
stderr:
status 0
425a6831314159265359087b7dd7000004c1800010024194802000310c0821a3
d4c885473238a8f177245385090087b7dd70
stderr:
status 0
```

### a file is replaced by FILE.bz2, its mode kept; -k keeps it; -c writes to standard output and keeps it

```cu
(do (bz2-case #t "-" "rm -f hello.bz2; chmod 640 hello" "ls -l hello* | awk '{print substr($1, 1, 10), $NF}'; od -An -v -tx1 hello.bz2 | tr -d ' \\n'; echo" "-" (list "bzip2" "hello")) (bz2-case #t "-" "rm -f hello.bz2" "ls hello*" "-" (list "bzip2" "-k" "hello")) (bz2-case #t "-" "@" "ls hello*" "x" (list "bzip2" "-c" "hello" "three")))
```
---
```output
stderr:
status 0
after:
-rw-r----- hello.bz2
425a6839314159265359c1c080e2000001410000100244a00030cd00c3462997177245385090c1c080e2
stderr:
status 0
after:
hello
hello.bz2
425a6839314159265359c1c080e2000001410000100244a00030cd00c3462997
177245385090c1c080e2425a6839314159265359087b7dd7000004c180001002
4194802000310c0821a3d4c885473238a8f177245385090087b7dd70
stderr:
status 0
after:
hello
hello.bz2
```

### FILE.bz2 already there is refused unless -f; a missing file is said and the rest are done

```cu
(do (bz2-case #t "-" "@" "ls hello*" "-" (list "bzip2" "hello")) (bz2-case #t "-" "@" "ls hello*; od -An -v -tx1 hello.bz2 | tr -d ' \\n' | head -c 32; echo" "-" (list "bzip2" "-f" "hello")) (bz2-case #t "-" "@" "ls three*" "-" (list "bzip2" "nope" "three")))
```
---
```output
stderr:
bzip2: can't open 'hello.bz2': File exists
status 1
after:
hello
hello.bz2
stderr:
status 0
after:
hello.bz2
425a6839314159265359c1c080e20000
stderr:
bzip2: nope: No such file or directory
status 1
after:
three.bz2
```

### the level is the lowest given, 9 when none; -s is -2; -z, -q and -v are taken; long options are not

```cu
(do (bz2-case #t "three" "@" "@" "x" (list "bzip2" "-9" "-1")) (bz2-case #t "three" "@" "@" "x" (list "bzip2" "-s")) (bz2-case #t "three" "@" "@" "x" (list "bzip2" "-3s")) (bz2-case #t "three" "@" "@" "x" (list "bzip2" "-z" "-q" "-v")) (bz2-case #t "three" "@" "@" "x" (list "bzip2" "--best")))
```
---
```output
425a6831314159265359087b7dd7000004c1800010024194802000310c0821a3
d4c885473238a8f177245385090087b7dd70
stderr:
status 0
425a6832314159265359087b7dd7000004c1800010024194802000310c0821a3
d4c885473238a8f177245385090087b7dd70
stderr:
status 0
425a6832314159265359087b7dd7000004c1800010024194802000310c0821a3
d4c885473238a8f177245385090087b7dd70
stderr:
status 0
425a6839314159265359087b7dd7000004c1800010024194802000310c0821a3
d4c885473238a8f177245385090087b7dd70
stderr:
status 0

stderr:
bzip2: unrecognized option: best
Usage: bzip2 [-cfkdt123456789] [FILE]...

Compress FILEs (or stdin) with bzip2 algorithm

	-1..9	Compression level
	-d	Decompress
	-c	Write to stdout
	-f	Force
	-k	Keep input files
	-t	Test integrity
status 1
```

### -d and -t are bunzip2

```cu
(do (bz2-case #t "hello.bz2" "@" "@" "t" (list "bzip2" "-d")) (bz2-case #t "-" "rm -f hello" "ls hello*" "t" (list "bzip2" "-d" "hello.bz2")) (bz2-case #t "-" "@" "ls hello*" "t" (list "bzip2" "-t" "hello.bz2")) (bz2-case #t "hello.bz2" "@" "@" "t" (list "bzip2" "-dc" "-1")))
```
---
```output
hello|
stderr:
status 0
stderr:
status 0
after:
hello
stderr:
status 0
after:
hello
hello.bz2
stderr:
bzip2: unrecognized option: 1
Usage: bzip2 [-cfkdt123456789] [FILE]...

Compress FILEs (or stdin) with bzip2 algorithm

	-1..9	Compression level
	-d	Decompress
	-c	Write to stdout
	-f	Force
	-k	Keep input files
	-t	Test integrity
status 1
```

### 200 KB, three blocks at -1: bunzip2 reads it back, and the bytes are the ones busybox writes

```cu
(do (bz2-case #t "-" "awk 'BEGIN { for (i = 0; i < 20000; i++) printf \"%d %x %o line\\n\", i, i * 7919, i * 31 }' > big; wc -c < big" "cksum < big.bz2; bunzip2 -c big.bz2 | cmp - big && echo same; ls big*" "-" (list "bzip2" "-k" "-1" "big")))
```
---
```output
stderr:
status 0
after:
1819421382 148183
same
big
big.bz2
```

