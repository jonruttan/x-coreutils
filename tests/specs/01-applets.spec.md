# @weight 2

The applets through the pure core: (cu-run ARGV INPUT), output on
stdout, the status as the value.  Expectations from real
/usr/bin/{sort,uniq,wc,comm,join,tr,cut,...} runs; sha256 against the
FIPS vectors.

## the line tools

### cat passes through

```cu
(display (cu-run (list "cat") "a\nb\n"))
```
---
```output
a
b
0
```

### sort orders bytes

```cu
(display (cu-run (list "sort") "b\na\nc\n"))
```
---
```output
a
b
c
0
```

### sort -r reverses, -u dedupes

```cu
(display (cu-run (list "sort" "-ru") "b\na\nb\n"))
```
---
```output
b
a
0
```

### sort -n compares numerically

```cu
(display (cu-run (list "sort" "-n") "10\n9\n-2\n"))
```
---
```output
-2
9
10
0
```

### uniq collapses adjacent; -c counts in fours

```cu
(display (cu-run (list "uniq" "-c") "a\na\na\nb\n"))
```
---
```output
   3 a
   1 b
0
```

### head and tail take their counts

```cu
(do (display (cu-run (list "head" "-n" "2") "1\n2\n3\n")) (newline) (display (cu-run (list "tail" "-n1") "1\n2\n3\n")))
```
---
```output
1
2
0
3
0
```

### wc counts lines words bytes, padded to eight

```cu
(display (cu-run (list "wc") "x y\n"))
```
---
```output
       1       2       4
0
```

### wc -l alone

```cu
(display (cu-run (list "wc" "-l") "x\ny\n"))
```
---
```output
       2
0
```

## comm and join

### fixture

```cu
(do (file-write-all "/tmp/x-cu-1.txt" "a\nb\nc\n") (file-write-all "/tmp/x-cu-2.txt" "b\nc\nd\n") (display "made"))
```
---
    made

### comm's three columns

```cu
(display (cu-run (list "comm" "/tmp/x-cu-1.txt" "/tmp/x-cu-2.txt") ""))
```
---
```output
a
		b
		c
	d
0
```

### comm -12 keeps the intersection

```cu
(display (cu-run (list "comm" "-12" "/tmp/x-cu-1.txt" "/tmp/x-cu-2.txt") ""))
```
---
```output
b
c
0
```

### join pairs on field one

```cu
(do (file-write-all "/tmp/x-cu-j1.txt" "1 alpha\n2 beta\n") (file-write-all "/tmp/x-cu-j2.txt" "1 one\n3 three\n") (display (cu-run (list "join" "/tmp/x-cu-j1.txt" "/tmp/x-cu-j2.txt") "")))
```
---
```output
1 alpha one
0
```

### cleanup

```cu
(do (file-unlink "/tmp/x-cu-1.txt") (file-unlink "/tmp/x-cu-2.txt") (file-unlink "/tmp/x-cu-j1.txt") (file-unlink "/tmp/x-cu-j2.txt") (display "clean"))
```
---
    clean

## tr and cut

### tr translates ranges

```cu
(display (cu-run (list "tr" "a-c" "x-z") "abc\n"))
```
---
```output
xyz
0
```

### tr -d deletes

```cu
(display (cu-run (list "tr" "-d" "aeiou") "boot maker\n"))
```
---
```output
bt mkr
0
```

### tr -s squeezes

```cu
(display (cu-run (list "tr" "-s" "a") "aab\n"))
```
---
```output
ab
0
```

### cut -d -f picks fields

```cu
(display (cu-run (list "cut" "-d" " " "-f" "2") "a b c\n"))
```
---
```output
b
0
```

### cut -f ranges and pass-through without the delimiter

```cu
(display (cu-run (list "cut" "-d" ":" "-f" "1,3-") "a:b:c:d\nplain\n"))
```
---
```output
a:c:d
plain
0
```

### cut -c takes characters

```cu
(display (cu-run (list "cut" "-c" "2-3") "abcdef\n"))
```
---
```output
bc
0
```

## paths

### basename strips directories and a suffix

```cu
(do (display (cu-run (list "basename" "/a/b/c.txt") "")) (newline) (display (cu-run (list "basename" "/a/b/c.txt" ".txt") "")))
```
---
```output
c.txt
0
c
0
```

### dirname answers the directory

```cu
(do (display (cu-run (list "dirname" "/a/b/c") "")) (newline) (display (cu-run (list "dirname" "plain") "")))
```
---
```output
/a/b
0
.
0
```

## sha256

### the FIPS vectors: empty and abc

```cu
(do (display (cu-sha256 "")) (newline) (display (cu-sha256 "abc")))
```
---
```output
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
```

### the applet's line format

```cu
(display (cu-run (list "sha256sum") "hello\n"))
```
---
```output
5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03  -
0
```

### a two-block message (65 bytes crosses the boundary)

```cu
(display (cu-sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
```
---
    635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0
