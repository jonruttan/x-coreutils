# @weight 1

busybox's uncompress (archival/bbunzip.c's uncompress_main and
libarchive's unpack_Z_stream).  Every expectation is busybox 1.36.1's own
output, built from its defconfig with CONFIG_UNCOMPRESS on (the defconfig
leaves it off) and run in alpine 3.20, less the banner line its usage text
starts with.  A `|` marks the end of each line written to standard output;
`after:` is what a command run after shows.

## the fixtures

### the files, compress(1)'s .Z of them, and a run of the applet in a fresh directory

`hello` and `three` are text, and `hello.Z` and `three.Z` compress's of
them.  `txt.Z` is `compress -b 12` of 23690 bytes of text, whose codes widen
to 12 bits and whose table fills; `short.Z` is its first half.  `noblock.Z`
is `three.Z` with its block mode flag cleared.  `plain.Z` is text and
`empty` is nothing; `header.Z` is the magic alone, `bits17.Z` a header that
asks for 17 bits, `first.Z` a stream whose first code is not a byte, and
`undef.Z` one whose second code is past the next entry.  Each run is in
`/tmp/x-cu-z/w`, made afresh from them: PRE runs before the applet, with
standard input the file IN (`-` for none), and POST after it, both through
the shell.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-z && mkdir -p /tmp/x-cu-z/w")) (def z-f (fn (_ n) (string-append "/tmp/x-cu-z/" n))) (file-write-all (z-f "fx.b64") "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") (proc-run (list "/bin/sh" "-c" "cd /tmp/x-cu-z && base64 -d < fx.b64 | tar xzf -")) (def z-home (Sys getcwd)) (def z-sh (fn (_ cmd out) (proc-run (list "/bin/sh" "-c" (%str-concat (list "cd /tmp/x-cu-z/w && { " cmd "; } > " out " 2>&1")))))) (def z-in (fn (_ name) (if (string=? name "-") "" (let ((fd (file-open-read (string-append "/tmp/x-cu-z/w/" name))) (buf (str-make-raw 65536))) (let ((n (File read fd buf 65536))) (do (file-close fd) (pair buf n))))))) (def z-shown (fn (_ mode) (if (string=? mode "x") (do (proc-run (list "/bin/sh" "-c" "od -An -v -tx1 /tmp/x-cu-z/o | tr -d ' \\n' | fold -w 64 > /tmp/x-cu-z/hex; echo >> /tmp/x-cu-z/hex")) (file-read-all (z-f "hex"))) (Str8 replace "\n" "|\n" (file-read-all (z-f "o")))))) (def z-case (fn (_ fresh in pre post mode argv) (do (if fresh (z-sh "cd /tmp/x-cu-z && rm -rf w && mkdir w && cp -p fx/* w/" "/dev/null") ()) (if (string=? pre "@") () (z-sh pre "/dev/null")) (def z-stdin (z-in in)) (Sys chdir "/tmp/x-cu-z/w") (sys-dup2 1 9) (sys-dup2 2 8) (def st (let ((oo (file-open-write (z-f "o"))) (ee (file-open-write (z-f "e")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def rs (cu-run argv z-stdin)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) rs))) (Sys chdir z-home) (display (%str-concat (list (z-shown mode) "stderr:\n" (file-read-all (z-f "e")) "status " (cu-int->str st) "\n" (if (string=? post "@") "" (do (z-sh post (z-f "p")) (string-append "after:\n" (file-read-all (z-f "p"))))))))))) (display "made"))
```
---
    made

## uncompress

### standard input to standard output; -c with two files

```cu
(do (z-case #t "hello.Z" "@" "@" "t" (list "uncompress")) (z-case #t "-" "@" "@" "t" (list "uncompress" "-c" "hello.Z" "three.Z")))
```
---
```output
hello|
stderr:
status 0
hello|
one|
two|
three|
stderr:
status 0
```

### a file is replaced by FILE, its mode kept; -c writes to standard output and keeps it

```cu
(do (z-case #t "-" "chmod 640 hello.Z; rm hello" "ls -l hello* | awk '{print substr($1, 1, 10), $NF}'; cat hello" "t" (list "uncompress" "hello.Z")) (z-case #t "-" "rm hello" "ls hello*" "t" (list "uncompress" "-c" "hello.Z")))
```
---
```output
stderr:
status 0
after:
-rw-r----- hello
hello
hello|
stderr:
status 0
after:
hello.Z
```

### an output already there stays, and the input with it, unless -f

```cu
(do (z-case #t "-" "@" "ls hello*; cat hello" "t" (list "uncompress" "hello.Z")) (z-case #t "-" "echo old > hello" "ls hello*; cat hello" "t" (list "uncompress" "-f" "hello.Z")))
```
---
```output
stderr:
uncompress: can't open 'hello': File exists
status 1
after:
hello
hello.Z
hello
stderr:
status 0
after:
hello
hello
```

### a name without .Z, and one that is not there; the next name is still taken

```cu
(do (z-case #t "-" "@" "ls hello*" "t" (list "uncompress" "hello")) (z-case #t "-" "rm hello" "ls hello*" "t" (list "uncompress" "nothere.Z" "hello.Z")))
```
---
```output
stderr:
uncompress: hello: unknown suffix - ignored
status 1
after:
hello
hello.Z
stderr:
uncompress: nothere.Z: No such file or directory
status 1
after:
hello
```

### codes that widen to 12 bits through a full table; no block mode; data cut short is the end of it

```cu
(do (z-case #t "-" "@" "cksum txt noblock; ls txt* noblock*" "t" (list "uncompress" "txt.Z" "noblock.Z")) (z-case #t "-" "@" "cksum short" "t" (list "uncompress" "short.Z")))
```
---
```output
stderr:
status 0
after:
3775088276 23690 txt
80847427 14 noblock
noblock
txt
stderr:
status 0
after:
84270564 11543 short
```

### bad data: busybox's words and status 1, the output file taken away and the next name taken

```cu
(do (z-case #t "-" "@" "ls plain*" "t" (list "uncompress" "plain.Z")) (z-case #t "-" "@" "@" "t" (list "uncompress" "-c" "header.Z" "bits17.Z")) (z-case #t "empty" "@" "@" "t" (list "uncompress")) (z-case #t "-" "@" "ls undef*" "t" (list "uncompress" "undef.Z")) (z-case #t "-" "@" "@" "t" (list "uncompress" "-c" "undef.Z" "hello.Z")) (z-case #t "-" "@" "@" "t" (list "uncompress" "-c" "hello.Z" "plain.Z" "three.Z")))
```
---
```output
stderr:
uncompress: invalid magic
status 1
after:
plain.Z
stderr:
uncompress: short read
uncompress: compressed with 17 bits, can only handle 16 bits
status 1
stderr:
uncompress: invalid magic
status 1
stderr:
uncompress: corrupted data
status 1
after:
undef.Z
hello|
stderr:
uncompress: corrupted data
status 1
hello|
one|
two|
three|
stderr:
uncompress: invalid magic
status 1
```

### a first code that is not a byte ends the run there, the output file kept

busybox dies on it: the output file stays, empty, the input stays, and a
name after it is not taken.

```cu
(do (z-case #t "-" "rm hello" "ls first* hello*; wc -c < first | tr -d ' '" "t" (list "uncompress" "first.Z" "hello.Z")) (z-case #t "-" "@" "@" "t" (list "uncompress" "-c" "first.Z" "hello.Z")))
```
---
```output
stderr:
uncompress: corrupted data
status 1
after:
first
first.Z
hello.Z
0
stderr:
uncompress: corrupted data
status 1
```
