# @weight 2

Bytes above 0x7F go out as the bytes they are.  A byte turned into a character
and then into a string is written in UTF-8, two bytes for anything above 0x7F,
so every applet that builds its output a byte at a time packs the bytes
themselves (bytes->str).  The expected bytes are the GNU tools' for the same
input, and rev's is the system rev's under LC_ALL=C.

Each case shows its output as the hex od prints, so the bytes are checked by a
tool outside this bundle.  The inputs are spelled as byte lists: u8 is
"héllo wörld" in UTF-8, and lat holds bytes that are not UTF-8 at all.

## the fixtures

### a scratch directory, and a reader for output as hex

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-b && mkdir -p /tmp/x-cu-b && cd /tmp/x-cu-b && printf 'a\\351b\\377\\n' > lat && base64 < lat > lat.b64 && uuencode lat lat > lat.uu && printf 'b\\000\\303\\251\\000a\\000' > z3 && head -c 3000 /dev/zero | tr '\\000' 'z' > shredme")) (def hx (fn (_ argv input) (do (sys-dup2 1 9) (let ((fd (file-open-write "/tmp/x-cu-b/.cap"))) (do (sys-dup2 fd 1) (def hx-st (cu-run argv input)) (sys-dup2 9 1) (file-close fd) (proc-run (list "/bin/sh" "-c" "od -An -tx1 -v /tmp/x-cu-b/.cap | tr -s ' \\n' ' ' | sed 's/^ //; s/ $//' > /tmp/x-cu-b/.hex")) (display (file-read-all "/tmp/x-cu-b/.hex")) (display " | status ") (display hx-st) (newline)))))) (def hxf (fn (_ p) (do (proc-run (list "/bin/sh" "-c" (string-append "od -An -tx1 -v " p " | tr -s ' \\n' ' ' | sed 's/^ //; s/ $//' > /tmp/x-cu-b/.hex"))) (display (file-read-all "/tmp/x-cu-b/.hex")) (newline)))) (def u8 (bytes->str (list 104 195 169 108 108 111 32 119 195 182 114 108 100 10))) (def lat (bytes->str (list 97 233 98 255 10))) (display "made"))
```
---
    made

## the applets that copy bytes

### tr maps the bytes it is asked to and passes the rest through as they are

```cu
(do (hx (list "tr" "l" "L") u8) (hx (list "tr" "-d" "l") u8) (hx (list "tr" "a-z" "A-Z") lat))
```
---
```output
68 c3 a9 4c 4c 6f 20 77 c3 b6 72 4c 64 0a | status 0
68 c3 a9 6f 20 77 c3 b6 72 64 0a | status 0
41 e9 42 ff 0a | status 0
```

### cut -c and -b count bytes and write them as they are

```cu
(do (hx (list "cut" "-c" "1-3") u8) (hx (list "cut" "-b" "2") u8))
```
---
```output
68 c3 a9 0a | status 0
c3 0a | status 0
```

### expand and unexpand count a column per byte and keep the bytes

```cu
(do (hx (list "expand") (bytes->str (list 195 169 9 120 10))) (hx (list "unexpand" "-a") (bytes->str (list 195 169 32 32 32 32 32 32 32 120 10))))
```
---
```output
c3 a9 20 20 20 20 20 20 78 0a | status 0
c3 a9 09 20 78 0a | status 0
```

### echo -e copies the bytes around its escapes

```cu
(hx (list "echo" "-e" (bytes->str (list 104 195 169 92 116 120))) "")
```
---
    68 c3 a9 09 78 0a | status 0

### rev reverses bytes

```cu
(hx (list "rev") (bytes->str (list 97 98 195 169 10 10 99 10)))
```
---
    a9 c3 62 61 0a 0a 63 0a | status 0

## the applets that decode bytes

### base64 -d and uudecode write the bytes they decode

The encoded forms come from the system's base64 and uuencode.

```cu
(do (hx (list "base64" "-d" "/tmp/x-cu-b/lat.b64") "") (hx (list "uudecode" "-o" "-" "/tmp/x-cu-b/lat.uu") ""))
```
---
```output
61 e9 62 ff 0a | status 0
61 e9 62 ff 0a | status 0
```

## the NUL-separated fields

### sort -z and xargs -0 keep the bytes of each field

```cu
(do (cu-run (list "sort" "-z" "-o" "/tmp/x-cu-b/sorted" "/tmp/x-cu-b/z3") "") (hxf "/tmp/x-cu-b/sorted") (hx (list "xargs" "-0" "-a" "/tmp/x-cu-b/z3" "echo") ""))
```
---
```output
61 00 62 00 c3 a9 00
62 20 c3 a9 20 61 0a | status 0
```

## shred

### the passes cover the block the file's last bytes sit in

```cu
(do (cu-run (list "shred" "-n" "1" "/tmp/x-cu-b/shredme") "") (display (%cu-stat-get (file-stat-full "/tmp/x-cu-b/shredme") (lit size))) (newline))
```
---
    4096

## cleanup

### the scratch directory goes

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-b")) (display "clean"))
```
---
    clean
