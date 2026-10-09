# @weight 2

Each checksum tool's `-c`, and the two flags that shape what it says.
Its own file: these blocks write fixtures and read them back, and the
suite runs a file's snippets in one process without collecting between
them, so they belong beside their own fixtures rather than on the end of
the option specs.

`md5sum`, `sha1sum`, `sha256sum` and `sha512sum` share one driver, so
they share one option set and one set of answers; the shared block at
the end is what pins that rather than four copies of everything.

## reading checksums back

### fixtures

```cu
(do (file-write-all "/tmp/x-cu-ck-a" "hello world\n")
    (file-write-all "/tmp/x-cu-ck-ok"
      "6f5902ac237024bdd0c176cb93063dc4  /tmp/x-cu-ck-a\n")
    (display "made"))
```
---
    made

### -c recomputes and says OK, and answers 0

```cu
(display (cu-run (list "md5sum" "-c" "/tmp/x-cu-ck-ok") ""))
```
---
```output
/tmp/x-cu-ck-a: OK
0
```

### the checksum lines can come from stdin

```cu
(display (cu-run (list "md5sum" "-c")
  "6f5902ac237024bdd0c176cb93063dc4  /tmp/x-cu-ck-a\n"))
```
---
```output
/tmp/x-cu-ck-a: OK
0
```

### a digest that does not match is FAILED, and the status moves

```cu
(display (cu-run (list "md5sum" "-c")
  "00000000000000000000000000000000  /tmp/x-cu-ck-a\n"))
```
---
```output
/tmp/x-cu-ck-a: FAILED
1
```

### a listed file that cannot be read is FAILED too

```cu
(display (cu-run (list "md5sum" "-c")
  "6f5902ac237024bdd0c176cb93063dc4  /tmp/x-cu-ck-absent\n"))
```
---
```output
/tmp/x-cu-ck-absent: FAILED
1
```

### a digest spelled in upper case still matches

The comparison is case-insensitive, and is the only place that cares --
nothing lowers the whole line first.

```cu
(display (cu-run (list "md5sum" "-c")
  "6F5902AC237024BDD0C176CB93063DC4  /tmp/x-cu-ck-a\n"))
```
---
```output
/tmp/x-cu-ck-a: OK
0
```

### GNU's binary separator reads the same as ours

We write two spaces; `DIGEST *NAME` is the other spelling in the wild.

```cu
(display (cu-run (list "md5sum" "-c")
  "6f5902ac237024bdd0c176cb93063dc4 */tmp/x-cu-ck-a\n"))
```
---
```output
/tmp/x-cu-ck-a: OK
0
```

## the flags that shape the report

### -s says nothing at all, and still answers 1

```cu
(display (cu-run (list "md5sum" "-s" "-c")
  "00000000000000000000000000000000  /tmp/x-cu-ck-a\n"))
```
---
    1

### -w says a line that is not a checksum line is one

The notice goes to stderr, so only the OK line and the status reach stdout.
A line with no space in it is no checksum line, and it fails the list, as
busybox's does.

```cu
(display (cu-run (list "md5sum" "-w" "-c")
  "not-a-checksum-line\n6f5902ac237024bdd0c176cb93063dc4  /tmp/x-cu-ck-a\n"))
```
---
```output
/tmp/x-cu-ck-a: OK
1
```

### a file of nothing but junk verified nothing, and says so

```cu
(display (cu-run (list "md5sum" "-c") "not-a-checksum-line\n"))
```
---
    1

## all four take it

### sha1sum, sha256sum and sha512sum check the same way

```cu
(do
  (display (cu-run (list "sha1sum" "-c")
    "22596363b3de40b06f981fb85d82312e8c0ed511  /tmp/x-cu-ck-a\n"))
  (display (cu-run (list "sha256sum" "-c")
    "a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447  /tmp/x-cu-ck-a\n"))
  (display (cu-run (list "sha512sum" "-c")
    "db3974a97f2407b7cae1ae637c0030687a11913274d578492558e39c16c017de84eacdc8c62fe34ee4e12b4b1428817f09b6a2760c3f8a664ceae94d2434a593  /tmp/x-cu-ck-a\n")))
```
---
```output
/tmp/x-cu-ck-a: OK
0/tmp/x-cu-ck-a: OK
0/tmp/x-cu-ck-a: OK
0
```

### and writing is unchanged by any of it

```cu
(display (cu-run (list "md5sum") "hello world\n"))
```
---
```output
6f5902ac237024bdd0c176cb93063dc4  -
0
```

## -b and -t

### -b marks the name with a star, -t takes it back, and the later one wins

busybox's help lists neither.  The expectations are busybox's.

```cu
(do (display (cu-run (list "md5sum" "-b") "abc\n"))
    (display (cu-run (list "md5sum" "-t") "abc\n"))
    (display (cu-run (list "md5sum" "-bt") "abc\n"))
    (display (cu-run (list "md5sum" "-tb") "abc\n"))
    (display (cu-run (list "md5sum" "-b" "-t") "abc\n"))
    (display (cu-run (list "md5sum" "-t" "-b") "abc\n")))
```
---
```output
0bee89b07a248e27c83fc3d5951213c1 *-
00bee89b07a248e27c83fc3d5951213c1  -
00bee89b07a248e27c83fc3d5951213c1  -
00bee89b07a248e27c83fc3d5951213c1 *-
00bee89b07a248e27c83fc3d5951213c1  -
00bee89b07a248e27c83fc3d5951213c1 *-
0
```

### every digest takes -b

```cu
(do (display (cu-run (list "sha1sum" "-b") "abc\n"))
    (display (cu-run (list "sha256sum" "-b") "abc\n"))
    (display (cu-run (list "sha384sum" "-b") "abc\n"))
    (display (cu-run (list "sha512sum" "-b") "abc\n")))
```
---
```output
03cfd743661f07975fa2f1220c5194cbaff48451 *-
0edeaaff3f1774ad2888673770c6d64097e391bc362d7d6fb34982ddf0efd18cb *-
0e8d1420b4ff41c3f12186d894a99e1c4aa681da79c47007e9dadecd9ecb0482ee1e224510e7484078c0289f34396b9c3 *-
04f285d0c0cc77286d8731798b7aae2639e28270d4166f40d769cbbdca5230714d848483d364e2f39fe6cb9083c15229b39a33615ebc6d57605f7c43f6906739d *-
0
```

### cleanup

```cu
(do (file-unlink "/tmp/x-cu-ck-a") (file-unlink "/tmp/x-cu-ck-ok")
    (display "clean"))
```
---
    clean
