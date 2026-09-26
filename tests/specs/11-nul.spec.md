# @weight 4

The NUL delimiters: sort -z, shuf -z, env -0, xargs -0, shred -z.

A NUL is reachable, and only the helpers that ask a C string its length
say otherwise: `File read` and `File write` take an explicit count and
carry every byte, `byte-at` reads past as many NULs as there are, and the
zero bytes themselves come from /dev/zero (cu/prims.x).  A field between
two delimiters holds no delimiter, so each is an ordinary string once cut
and the usual helpers work on it -- only the buffer needs the discipline.

The cases hand their input as an OPERAND rather than as stdin: the
harness gives an applet one x string for its standard input, which a NUL
would cut short, so a -z applet reads the real descriptor instead --
which is not the harness's.

### fixtures

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-z && mkdir -p /tmp/x-cu-z/d && printf 'pear\\000apple\\000fig\\000' > /tmp/x-cu-z/f0 && printf 'b\\000a\\000b\\000' > /tmp/x-cu-z/dup0 && printf 'no-trailer-a\\000no-trailer-b' > /tmp/x-cu-z/part0 && printf 'secret data' > /tmp/x-cu-z/s && : > '/tmp/x-cu-z/d/a b' && : > /tmp/x-cu-z/d/c && cd /tmp/x-cu-z/d && find . -type f -print0 > /tmp/x-cu-z/find0")) (def cu-z (fn (_ argv) (do (sys-dup2 1 9) (let ((fd (file-open-write "/tmp/x-cu-z/.cap"))) (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1) (file-close fd) (file-read-all "/tmp/x-cu-z/.cap")))))) (def fields (fn (_ p) (%cu-delim-fields (list p) (fn (_) "") 0))) (display "made"))
```
---
    made

### sort -z reads and writes NUL-delimited records

The captured output is read back as fields, since a string stops at the
first NUL -- which is the whole point of the flag.

```cu
(do (cu-run (list "sort" "-z" "-o" "/tmp/x-cu-z/out0" "/tmp/x-cu-z/f0") "") (write (fields "/tmp/x-cu-z/out0")) (newline) (cu-run (list "sort" "-z" "-r" "-o" "/tmp/x-cu-z/out0" "/tmp/x-cu-z/f0") "") (write (fields "/tmp/x-cu-z/out0")) (newline) (cu-run (list "sort" "-z" "-u" "-o" "/tmp/x-cu-z/out0" "/tmp/x-cu-z/dup0") "") (write (fields "/tmp/x-cu-z/out0")))
```
---
```output
("apple" "fig" "pear")
("pear" "fig" "apple")
("a" "b")
```

### a record without a trailing delimiter is still a record

```cu
(do (cu-run (list "sort" "-z" "-o" "/tmp/x-cu-z/out0" "/tmp/x-cu-z/part0") "") (write (fields "/tmp/x-cu-z/out0")))
```
---
    ("no-trailer-a" "no-trailer-b")

### shuf -z keeps the records whole, whatever their order

```cu
(do (cu-run (list "shuf" "-z" "-o" "/tmp/x-cu-z/sh0" "/tmp/x-cu-z/f0") "") (cu-run (list "sort" "-z" "-o" "/tmp/x-cu-z/sh1" "/tmp/x-cu-z/sh0") "") (write (fields "/tmp/x-cu-z/sh1")))
```
---
    ("apple" "fig" "pear")

### a record may hold a newline, which is what the flag is for

```cu
(do (proc-run (list "/bin/sh" "-c" "printf 'two\\nlines\\000one\\000' > /tmp/x-cu-z/nl0")) (cu-run (list "sort" "-z" "-o" "/tmp/x-cu-z/out0" "/tmp/x-cu-z/nl0") "") (write (fields "/tmp/x-cu-z/out0")))
```
---
    ("one" "two\nlines")

### env -0 ends each entry with a NUL where env ends it with a newline

Judged by size rather than content, which is the machine's: one
delimiter per entry either way, so the two outputs weigh the same, and
an empty environment under -i weighs nothing.  The size is taken from
the captured FILE -- reading it into a string would stop at the first
NUL, which is the thing being tested.

```cu
(do (def cap-size (fn (_ argv) (do (cu-z argv) (%cu-stat-get (file-stat-full "/tmp/x-cu-z/.cap") (lit size))))) (display (if (= (cap-size (list "env" "-0")) (cap-size (list "env"))) "same size" "differ")) (newline) (display (cap-size (list "env" "-i" "-0"))))
```
---
```output
same size
0
```

### xargs -0 splits on the NUL alone, so a space stays inside an item

`find -print0` wrote the names; each reaches echo whole.

```cu
(display (cu-run (list "xargs" "-0" "-a" "/tmp/x-cu-z/find0" "/bin/echo") ""))
```
---
```output
./c ./a b
0
```

### -0 with -n1 hands over one item per command

```cu
(display (cu-run (list "xargs" "-0" "-n1" "-a" "/tmp/x-cu-z/find0" "/bin/echo") ""))
```
---
```output
./c
./a b
0
```

### shred -z fills the blocks it covered with zeros

```cu
(do (cu-run (list "shred" "-n" "1" "-z" "/tmp/x-cu-z/s") "") (display (cu-run (list "stat" "-c" "%s" "/tmp/x-cu-z/s") "")) (def fd (file-open-read "/tmp/x-cu-z/s")) (def buf (%str-make-raw 32)) (def n (File read fd buf 32)) (file-close fd) (def allzero (fn (self i) (if (>= i n) #t (if (= (byte-at buf i) 0) (self (+ i 1)) #f)))) (display (if (allzero 0) "all zero" "not zero")))
```
---
```output
4096
0all zero
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-z")) (display "clean"))
```
---
    clean
