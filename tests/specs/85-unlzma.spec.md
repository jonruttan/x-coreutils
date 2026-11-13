# @weight 1

busybox's unlzma and lzcat (archival/bbunzip.c's unlzma_main and
libarchive's unpack_lzma_stream).  Every expectation is busybox 1.36.1's own
output, run in alpine 3.20, less the banner line its usage text starts
with.  A `|` marks the end of each line written to standard output;
`after:` is what a command run after shows.

## the fixtures

### the files, xz's .lzma of them, and a run of an applet in a fresh directory

`hello` and `three` are text, and `hello.lzma` and `three.lzma` xz 5.8.4's
`--format=lzma -9` of them, which declare no length and end at the end
marker.  `big.lzma` is 150000 bytes through a 4096-byte window, so busybox
writes it a window at a time; `short.lzma` is its first half.  `known.lzma`
is `hello.lzma` with its length, 6, in the header; `two.lzma` is two
streams and `trail.lzma` a stream with text after it; `empty.lzma` is the
stream of nothing.  From `hello.lzma`: `header.lzma` has its properties byte
made 225 and `shorthdr.lzma` is its first ten bytes; `plain.lzma` is text.
Each run is in `/tmp/x-cu-lz/w`, made afresh from them: PRE runs before the
applet, with standard input the file IN (`-` for none), and POST after it,
both through the shell.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-lz && mkdir -p /tmp/x-cu-lz/w")) (def lz-f (fn (_ n) (string-append "/tmp/x-cu-lz/" n))) (file-write-all (lz-f "fx.b64") "H4sIAJ9292oAA0ur0GegNTAwMDA3NVUA02YQ2sDIBEJDgYKhqZG5qZm5sZGxuYKBoaGJiSmDginNXQYEpcUliUVAp2Tl5+FVB1SWloZHHuoPOD1EQFqFfklRYmaOXk5VbiKN7ACGh5mJCZ74NzVGi39jExNjBgUDGrkHBYzw+I8FYpb/UMBgIun5rveurdX9///vCjEwgFNGZl66QklqRQnXQDt1FNAAAPN/UmY6LXM/4fxvZmCCnv8NzEfzP11ALIMAAwM8/xvMOPEo9uEHv/4vWxy+VDDFfGJj3Ft9Rf/QjQu6s9Rmm3GeYd7aI6O48G9afPWxPivljUt2LXh9Jf/7fY3ZzLUsqzd+tVKpFvjlaja9NID36YSF5z95OCny50hbHpJ3+rG4U8O3v9de5YbPLV8zd63yT/sk/UpFXf5/5V1quWPHYhH/PwdLGBNv7Ku9/37XjplV135rx8srOZ+stnC6enxbltoMZu1asSsSyyMW7LryeUmevQe3/56NK9fn3FGczto4e9c50edr7jfOSPTRdvig0bLo0IvWu57ncl7Jac+RrmZ5tfJ0UcCRXu/o/v7FB9UKlF6F8r+ennfSxFbt/rwJSaVhto+Ozzc+X2zpl8KzYPqty0z9LYusJy82Ml/pd2H/rbU3Wwo0c9Y0Gbv2zVTcZ8V9+v1ppSUe5hftmLtOFBkoJTvIr3LXePm1qcGF/WJDjGvUtYXz97xj7s5WM+99KDWLTyz5uPoSfYcN/9R9Hy7rfrGJRYy/+8L1RdaJzCyBD7Tm/6/iHtj4B9X/GUWpqQNa/5uYYtb/BqP5nx4Atf43n91x5tuxBOOj7hN/Lu2J8zaZ9f9vfcFAu3EU0A4A839GamJKahENCwCC+d8YI/+bmo3mf7qAhwx42v+jYNgDYP4vyEnMzBvQ+t/ADKP+NzYczf/0ABmpOTn5o137EQuA+T81t6CkckDzv5E5Rv43Mx/N//QAqO3/5v+///8/MNBuGgX0A7D+Py3tIJj/DdHrfyMTc5PR/E8PkJ+XylVSns8FTgSj7YARB4D5Pzsvv3xg2/+Y/X8Ts9H8TxcArv/ZYLzR/v9IA+DxP2AXkJZ2kN7/Nxpt/9MJjPb/RzYA5v/ijPyikoGs/40NjEbr/wECQ3/+f6BDcGgDUP+/PH9g1/8YYuZ/YAkwmv/pAfCu/xtdHDDsAaz9P9j6/8aj6//oAvDm/1Ew7AGs/Z+RQrsVQITH/9HrfxPD0fU/9AGI/D/QLhkFo2AUjIJRQE8AAP0mrG0AOgAA") (proc-run (list "/bin/sh" "-c" "cd /tmp/x-cu-lz && base64 -d < fx.b64 | tar xzf -")) (def lz-home (Sys getcwd)) (def lz-sh (fn (_ cmd out) (proc-run (list "/bin/sh" "-c" (%str-concat (list "cd /tmp/x-cu-lz/w && { " cmd "; } > " out " 2>&1")))))) (def lz-in (fn (_ name) (if (string=? name "-") "" (let ((fd (file-open-read (string-append "/tmp/x-cu-lz/w/" name))) (buf (str-make-raw 65536))) (let ((n (File read fd buf 65536))) (do (file-close fd) (pair buf n))))))) (def lz-shown (fn (_ mode) (if (string=? mode "x") (do (proc-run (list "/bin/sh" "-c" "od -An -v -tx1 /tmp/x-cu-lz/o | tr -d ' \\n' | fold -w 64 > /tmp/x-cu-lz/hex; echo >> /tmp/x-cu-lz/hex")) (file-read-all (lz-f "hex"))) (Str8 replace "\n" "|\n" (file-read-all (lz-f "o")))))) (def lz-case (fn (_ fresh in pre post mode argv) (do (if fresh (lz-sh "cd /tmp/x-cu-lz && rm -rf w && mkdir w && cp -p fx/* w/" "/dev/null") ()) (if (string=? pre "@") () (lz-sh pre "/dev/null")) (def lz-stdin (lz-in in)) (Sys chdir "/tmp/x-cu-lz/w") (sys-dup2 1 9) (sys-dup2 2 8) (def st (let ((oo (file-open-write (lz-f "o"))) (ee (file-open-write (lz-f "e")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def rs (cu-run argv lz-stdin)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) rs))) (Sys chdir lz-home) (display (%str-concat (list (lz-shown mode) "stderr:\n" (file-read-all (lz-f "e")) "status " (cu-int->str st) "\n" (if (string=? post "@") "" (do (lz-sh post (lz-f "p")) (string-append "after:\n" (file-read-all (lz-f "p"))))))))))) (display "made"))
```
---
    made

## unlzma and lzcat

### standard input to standard output; lzcat; -c with two files

```cu
(do (lz-case #t "hello.lzma" "@" "@" "t" (list "unlzma")) (lz-case #t "-" "@" "@" "t" (list "lzcat" "three.lzma")) (lz-case #t "-" "@" "@" "t" (list "unlzma" "-c" "hello.lzma" "three.lzma")))
```
---
```output
hello|
stderr:
status 0
one|
two|
three|
stderr:
status 0
hello|
one|
two|
three|
stderr:
status 0
```

### a file is replaced by FILE, its mode kept; -k keeps it; -c writes to standard output and keeps it

```cu
(do (lz-case #t "-" "chmod 640 hello.lzma; rm hello" "ls -l hello* | awk '{print substr($1, 1, 10), $NF}'; cat hello" "t" (list "unlzma" "hello.lzma")) (lz-case #t "-" "rm hello" "ls hello*" "t" (list "unlzma" "-k" "hello.lzma")) (lz-case #t "-" "rm hello" "ls hello*" "t" (list "unlzma" "-c" "hello.lzma")))
```
---
```output
stderr:
status 0
after:
-rw-r----- hello
hello
stderr:
status 0
after:
hello
hello.lzma
hello|
stderr:
status 0
after:
hello.lzma
```

### an output already there stays, and the input with it, unless -f

```cu
(do (lz-case #t "-" "@" "ls hello*; cat hello" "t" (list "unlzma" "hello.lzma")) (lz-case #t "-" "echo old > hello" "ls hello*; cat hello" "t" (list "unlzma" "-f" "hello.lzma")))
```
---
```output
stderr:
unlzma: can't open 'hello': File exists
status 1
after:
hello
hello.lzma
hello
stderr:
status 0
after:
hello
hello
```

### a name without .lzma, and one that is not there; the next name is still taken

```cu
(do (lz-case #t "-" "@" "ls hello*" "t" (list "unlzma" "hello")) (lz-case #t "-" "rm hello" "ls hello*" "t" (list "unlzma" "nothere.lzma" "hello.lzma")))
```
---
```output
stderr:
unlzma: hello: unknown suffix - ignored
status 1
after:
hello
hello.lzma
stderr:
unlzma: nothere.lzma: No such file or directory
status 1
after:
hello
```

### one stream and nothing after it; the stream of nothing; a header that says the length

```cu
(do (lz-case #t "-" "@" "@" "t" (list "lzcat" "two.lzma")) (lz-case #t "-" "@" "@" "t" (list "lzcat" "trail.lzma")) (lz-case #t "-" "@" "@" "t" (list "lzcat" "empty.lzma")) (lz-case #t "-" "@" "@" "t" (list "lzcat" "known.lzma")))
```
---
```output
hello|
stderr:
status 0
hello|
stderr:
status 0
stderr:
status 0
hello|
stderr:
status 0
```

### a window that wraps

```cu
(do (lz-case #t "-" "rm big" "cksum big; ls big*" "t" (list "unlzma" "big.lzma")))
```
---
```output
stderr:
status 0
after:
2343275866 150000 big
big
```

### bad data: busybox's words and status 1, the output file taken away

```cu
(do (lz-case #t "-" "@" "ls plain*" "t" (list "unlzma" "plain.lzma")) (lz-case #t "-" "@" "@" "t" (list "lzcat" "header.lzma")) (lz-case #t "-" "@" "@" "t" (list "lzcat" "shorthdr.lzma")))
```
---
```output
stderr:
unlzma: bad lzma header
status 1
after:
plain.lzma
stderr:
lzcat: bad lzma header
status 1
stderr:
lzcat: bad lzma header
status 1
```

### data cut short ends the run there, the windows written so far kept

busybox's read dies at the end of the input: the output file stays with
the twelve whole windows written before it, the input stays, and a name
after it is not taken.

```cu
(do (lz-case #t "-" "rm big" "ls big* short*; cksum short" "t" (list "unlzma" "short.lzma")) (lz-case #t "-" "rm hello" "ls hello* short*" "t" (list "unlzma" "short.lzma" "hello.lzma")) (lz-case #t "-" "rm hello" "ls hello* short*" "t" (list "unlzma" "hello.lzma" "short.lzma")))
```
---
```output
stderr:
unlzma: unexpected EOF
status 1
after:
big.lzma
short
short.lzma
shorthdr.lzma
422661423 49152 short
stderr:
unlzma: unexpected EOF
status 1
after:
hello.lzma
short
short.lzma
shorthdr.lzma
stderr:
unlzma: unexpected EOF
status 1
after:
hello
short
short.lzma
shorthdr.lzma
```

### -t reads the data and writes nothing

```cu
(do (lz-case #t "-" "@" "ls hello*" "t" (list "unlzma" "-t" "hello.lzma")) (lz-case #t "-" "@" "@" "t" (list "unlzma" "-t" "short.lzma")))
```
---
```output
stderr:
status 0
after:
hello
hello.lzma
stderr:
unlzma: unexpected EOF
status 1
```

### standard input that is not lzma data, and none at all

```cu
(do (lz-case #t "plain.lzma" "@" "@" "t" (list "unlzma")) (lz-case #t "-" "@" "@" "t" (list "lzcat")))
```
---
```output
stderr:
unlzma: bad lzma header
status 1
stderr:
lzcat: bad lzma header
status 1
```
