# @weight 1

busybox's bunzip2 and bzcat (archival/bbunzip.c and libarchive's
unpack_bz2_stream), and zcat's reading of bzip2 data.  Every expectation is
busybox 1.36.1's own output, run as root in alpine, less the banner line its
usage text starts with.  A `|` marks the end of each line written to standard
output; `after:` is what a command run after shows.

## the fixtures

### the files, which busybox made, and a run of an applet in a fresh directory

`hello` and `three` are text, and `hello.bz2` and `three.bz2` busybox's
bzip2 of them; `big.bz2` is 150000 bytes compressed at -1, two blocks.
`two.bz2` is two streams, `trail.bz2` a stream with bytes after it, and
`empty.bz2` the stream of nothing.  From `hello.bz2`: `badcrc.bz2` has its
block CRC changed, `header.bz2` its block size digit made 0, `rand.bz2` its
block marked randomised, `badblock.bz2` its origin past the block, and
`short.bz2` is cut short; `plain.bz2` is text.  Each run is in
`/tmp/x-cu-bz/w`, made afresh from them: PRE runs before the applet, with
standard input the file IN (`-` for none), and POST after it, both through
the shell.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-bz && mkdir -p /tmp/x-cu-bz/w")) (def bz-f (fn (_ n) (string-append "/tmp/x-cu-bz/" n))) (file-write-all (bz-f "fx.b64") "H4sIAAAAAAAAA+2aT0gUURjAX1JkQ4cuS1EEa0nYHHLemxnHoMhdzLxImruBXXLW3XWH1p1lnNCsaBO2oKg89IfCg7ApIoS3DaFAiUCpoEMQEVGEl45Rhoeo3oyIuZZr4pvR9vuxzOzuLMzHfvOb773vTbSzHLFGoCiybO8puXv7PZaJQhQRE4yRgAWsEOSVmUdGOd1uqobXiwxdNxf7Xb7ja5RoZ7lpqFp8X6iLsDqHleAKSfp7/ivIXP4FQvNP00/zL7AK6HcKPP/+E7H92Ne0p7FpbDT1EaF1PoS2FFX3IeEFelKz985W43BlfY91zL5MtESr2xEDKwn1P6SGW4wWhjeAvP7Luf7TrQT+O8Gc/z/z+O92pAALrPofMyKR1Vb/cQX47wRz/hefPf8aofVjKeq/72bKi/Dm4pLMq/H0EVI5+LmjtDG9CV1++C7pdsTASkL9j7QlzTOu+k9lz/VfgvrvCJb/MzXe7UgAN6D+G2oizFL/ZYz/sSzC/N8R5s//UzD+LzCo/+0x3TBdrf/iH+q/Av47weL9P7ejA1hj9f+0VqblP6//IpFz1n+wKEP9dwTqP57xPzvx5RnqrWyg8/8qtEPLjgoo233pXjOqC/oGdh9tnKrqDzQjIchNBrlvfDrBX7zla3hsv370XXk55JkOctN8unnI0z14PF0/7Le2D77a3/QMeb4/3RC+Wxd9lL0dRsNv6J2F3mjaBt6i0aIPZdoA4rZrKdQfkLpuVE8drBsPnOsZfJ6uKeUPjAei/gzx7JzkJX/m/SfuephXShpGuGu1gZA/c8yzzf5wnz90dWRXb1mterJko9v/6VrC6v916O76j0Upt/5LRAD/nWDp63/QKfwfme3/szzHMvp/hGDw3wn0RISjBYCzLwLO7WgAp6H+xyJqOGKssvV/Edb/HIFWdWFp9d/tSAEWUP+TcVVLuLv+pyxc/4f5vyMkdNMb6tKSxBtWTRUGAIWGXf/jcaYdgH+v/9R/GP87wtLn/25HCrBg5vnfUFxvOcXsFrCM8b8I63/OMN//C+B/gTFb/1meI6//wsL+H4bn/xzBTj4M+wEAAAqOX888IOQAPgAA") (proc-run (list "/bin/sh" "-c" "cd /tmp/x-cu-bz && base64 -d < fx.b64 | tar xzf -")) (def bz-home (Sys getcwd)) (def bz-sh (fn (_ cmd out) (proc-run (list "/bin/sh" "-c" (%str-concat (list "cd /tmp/x-cu-bz/w && { " cmd "; } > " out " 2>&1")))))) (def bz-in (fn (_ name) (if (string=? name "-") "" (let ((fd (file-open-read (string-append "/tmp/x-cu-bz/w/" name))) (buf (str-make-raw 65536))) (let ((n (File read fd buf 65536))) (do (file-close fd) (pair buf n))))))) (def bz-shown (fn (_ mode) (if (string=? mode "x") (do (proc-run (list "/bin/sh" "-c" "od -An -v -tx1 /tmp/x-cu-bz/o | tr -d ' \\n' | fold -w 64 > /tmp/x-cu-bz/hex; echo >> /tmp/x-cu-bz/hex")) (file-read-all (bz-f "hex"))) (Str8 replace "\n" "|\n" (file-read-all (bz-f "o")))))) (def bz-case (fn (_ fresh in pre post mode argv) (do (if fresh (bz-sh "cd /tmp/x-cu-bz && rm -rf w && mkdir w && cp -p fx/* w/" "/dev/null") ()) (if (string=? pre "@") () (bz-sh pre "/dev/null")) (def bz-stdin (bz-in in)) (Sys chdir "/tmp/x-cu-bz/w") (sys-dup2 1 9) (sys-dup2 2 8) (def st (let ((oo (file-open-write (bz-f "o"))) (ee (file-open-write (bz-f "e")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def rs (cu-run argv bz-stdin)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) rs))) (Sys chdir bz-home) (display (%str-concat (list (bz-shown mode) "stderr:\n" (file-read-all (bz-f "e")) "status " (cu-int->str st) "\n" (if (string=? post "@") "" (do (bz-sh post (bz-f "p")) (string-append "after:\n" (file-read-all (bz-f "p"))))))))))) (display "made"))
```
---
    made

## bunzip2 and bzcat

### standard input to standard output; bzcat; -c with two files

```cu
(do (bz-case #t "hello.bz2" "@" "@" "t" (list "bunzip2")) (bz-case #t "-" "@" "@" "t" (list "bzcat" "three.bz2")) (bz-case #t "-" "@" "@" "t" (list "bunzip2" "-c" "hello.bz2" "three.bz2")))
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
(do (bz-case #t "-" "chmod 640 hello.bz2; rm hello" "ls -l hello* | awk '{print substr($1, 1, 10), $NF}'; cat hello" "t" (list "bunzip2" "hello.bz2")) (bz-case #t "-" "rm hello" "ls hello*" "t" (list "bunzip2" "-k" "hello.bz2")) (bz-case #t "-" "rm hello" "ls hello*" "t" (list "bunzip2" "-c" "hello.bz2")))
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
hello.bz2
hello|
stderr:
status 0
after:
hello.bz2
```

### an output already there stays, and the input with it, unless -f

```cu
(do (bz-case #t "-" "@" "ls hello*; cat hello" "t" (list "bunzip2" "hello.bz2")) (bz-case #t "-" "echo old > hello" "ls hello*; cat hello" "t" (list "bunzip2" "-f" "hello.bz2")))
```
---
```output
stderr:
bunzip2: can't open 'hello': File exists
status 1
after:
hello
hello.bz2
hello
stderr:
status 0
after:
hello
hello
```

### a name without .bz2, and one that is not there; the next name is still taken

```cu
(do (bz-case #t "-" "@" "ls hello*" "t" (list "bunzip2" "hello")) (bz-case #t "-" "rm hello" "ls hello*" "t" (list "bunzip2" "nothere.bz2" "hello.bz2")))
```
---
```output
stderr:
bunzip2: hello: unknown suffix - ignored
status 1
after:
hello
hello.bz2
stderr:
bunzip2: nothere.bz2: No such file or directory
status 1
after:
hello
```

### every stream of a file, what follows the last left, and a stream of nothing

```cu
(do (bz-case #t "-" "@" "@" "t" (list "bzcat" "two.bz2")) (bz-case #t "-" "@" "@" "t" (list "bzcat" "trail.bz2")) (bz-case #t "-" "@" "@" "t" (list "bzcat" "empty.bz2")))
```
---
```output
hello|
one|
two|
three|
stderr:
status 0
hello|
stderr:
status 0
stderr:
status 0
```

### two blocks

```cu
(do (bz-case #t "-" "@" "cksum big; ls big*" "t" (list "bunzip2" "big.bz2")))
```
---
```output
stderr:
status 0
after:
1704299336 150000 big
big
```

### bad data: busybox's words and status 1, the output file taken away

```cu
(do (bz-case #t "-" "@" "ls plain*" "t" (list "bunzip2" "plain.bz2")) (bz-case #t "-" "@" "ls short*" "t" (list "bunzip2" "short.bz2")) (bz-case #t "-" "@" "@" "t" (list "bzcat" "header.bz2")) (bz-case #t "-" "@" "@" "t" (list "bzcat" "rand.bz2")) (bz-case #t "-" "@" "@" "t" (list "bzcat" "badblock.bz2")) (bz-case #t "-" "rm hello" "ls hello* badcrc*" "t" (list "bunzip2" "badcrc.bz2")) (bz-case #t "-" "@" "@" "t" (list "bzcat" "badcrc.bz2")))
```
---
```output
stderr:
bunzip2: invalid magic
status 1
after:
plain.bz2
stderr:
bunzip2: bunzip error -3
status 1
after:
short.bz2
stderr:
bzcat: bunzip error -2
status 1
stderr:
bzcat: bunzip error -7
status 1
stderr:
bzcat: bunzip error -5
status 1
stderr:
bunzip2: CRC error
status 1
after:
badcrc.bz2
hello.bz2
stderr:
bzcat: CRC error
status 1
```

### -t reads the data and writes nothing

```cu
(do (bz-case #t "-" "@" "ls hello*" "t" (list "bunzip2" "-t" "hello.bz2")) (bz-case #t "-" "@" "@" "t" (list "bunzip2" "-t" "badcrc.bz2")))
```
---
```output
stderr:
status 0
after:
hello
hello.bz2
stderr:
bunzip2: CRC error
status 1
```

### standard input that is not bzip2 data, and none at all

```cu
(do (bz-case #t "plain.bz2" "@" "@" "t" (list "bunzip2")) (bz-case #t "-" "@" "@" "t" (list "bzcat")))
```
---
```output
stderr:
bunzip2: invalid magic
status 1
stderr:
bzcat: invalid magic
status 1
```

### zcat of bzip2 data

```cu
(do (bz-case #t "-" "@" "@" "t" (list "zcat" "hello.bz2")))
```
---
```output
hello|
stderr:
status 0
```

