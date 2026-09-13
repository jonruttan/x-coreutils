# @weight 4

The checksum family's `-c`, and the two flags that shape what it says.
Its own file: these blocks write fixtures and read them back, and the
suite runs a file's snippets in one process without collecting between
them, so they belong beside their own fixtures rather than on the end of
the option specs.

`md5sum`, `sha1sum`, `sha256sum` and `sha512sum` share one driver, so
they share one option set and one set of answers; the family block at
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
/tmp/x-cu-ck-absent: FAILED open or read
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

### -w names a line that is not a checksum line

The per-line notice goes to stderr, so only the status and the OK line
reach stdout -- the point of the flag is that the notice exists at all.

```cu
(display (cu-run (list "md5sum" "-w" "-c")
  "not a checksum line\n6f5902ac237024bdd0c176cb93063dc4  /tmp/x-cu-ck-a\n"))
```
---
```output
/tmp/x-cu-ck-a: OK
0
```

### a file of nothing but junk verified nothing, and says so

```cu
(display (cu-run (list "md5sum" "-c") "not a checksum line\n"))
```
---
    1

## the whole family takes it

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

### cleanup

```cu
(do (file-unlink "/tmp/x-cu-ck-a") (file-unlink "/tmp/x-cu-ck-ok")
    (display "clean"))
```
---
    clean
