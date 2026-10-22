# @weight 1

busybox's pmap (procps/pmap.c), its 64-bit layout.  Every expectation in the
first section is busybox's own output over the fixture /proc at
tests/fixtures/pmap/proc, which the cases point Host's Linux reader at, so
they run on either kernel: pid 42 a busybox shell's regions; pid 7 a cmdline
with a control byte and trailing empty arguments, a region of no size and
one too wide for its column; pid 11 a cmdline past the 4095 bytes busybox
reads; pid 9 a process with no smaps; pid 99 none at all.  The second section
runs pmap on this machine's own process and checks its shape.  A `|` marks
the end of each line written to standard output.

## the fixture

### a run of pmap over the fixture /proc, with its stdout, stderr and status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-pmap && mkdir -p /tmp/x-cu-pmap")) (def nf (fn (_ n) (string-append "/tmp/x-cu-pmap/" n))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (list (file-read-all (nf ".out")) (file-read-all (nf ".err")) st)))))) (def show (fn (_ r) (display (string-concat (list (Str8 replace "\n" "|\n" (first r)) "stderr:\n" (first (rest r)) "status " (cu-int->str (first (rest (rest r)))) "\n"))))) (def fixture (fn (_ argv) (do (Host source 'linux) (Host proc-root "tests/fixtures/pmap/proc") (def r (run argv)) (Host source (if os-darwin? 'darwin 'linux)) (Host proc-root "/proc") (show r)))) (display "made"))
```
---
    made

## busybox's output over the fixture

### pmap 42

```cu
(fixture (list "pmap" "42"))
```
---
```output
42: /bin/sh -c sleep 9|
000055d4c8a00000     112K r--p  /bin/busybox|
000055d4c8a1c000    1096K r-xp  /bin/busybox|
000055d4c8d2e000      12K rw-p  /bin/busybox|
000055d4c9a00000     132K rw-p  [heap]|
00007f3a10000000     132K rw-p    [ anon ]|
00007f3a10021000   65404K ---p    [ anon ]|
00007f3a14100000     340K r-xp  /lib/ld-musl-x86_64.so.1 (deleted)|
00007f3a14200000       4K rw-s  /dev/shm/a b|
00007ffd5a000000     132K rw-p  [stack]|
00007ffd5a1f0000      16K r--p  [vvar]|
00007ffd5a1f4000       8K r-xp  [vdso]|
ffffffffff600000       4K --xp  [vsyscall]|
 total             67392K|
stderr:
status 0
```

### pmap -x 42

```cu
(fixture (list "pmap" "-x" "42"))
```
---
```output
42: /bin/sh -c sleep 9|
Address		  Kbytes     PSS   Dirty    Swap  Mode  Mapping|
000055d4c8a00000     112      56       0       0  r--p  /bin/busybox|
000055d4c8a1c000    1096     450       0       0  r-xp  /bin/busybox|
000055d4c8d2e000      12      12      12       0  rw-p  /bin/busybox|
000055d4c9a00000     132      20      20       8  rw-p  [heap]|
00007f3a10000000     132       4       4      64  rw-p    [ anon ]|
00007f3a10021000   65404       0       0       0  ---p    [ anon ]|
00007f3a14100000     340     113       0       0  r-xp  /lib/ld-musl-x86_64.so.1 (deleted)|
00007f3a14200000       4       2       4       0  rw-s  /dev/shm/a b|
00007ffd5a000000     132      16      16       4  rw-p  [stack]|
00007ffd5a1f0000      16       0       0       0  r--p  [vvar]|
00007ffd5a1f4000       8       0       0       0  r-xp  [vdso]|
ffffffffff600000       4       0       0       0  --xp  [vsyscall]|
----------------  ------  ------  ------  ------|
total kB           67392     673      56      76|
stderr:
status 0
```

### pmap -q 42

```cu
(fixture (list "pmap" "-q" "42"))
```
---
```output
42: /bin/sh -c sleep 9|
000055d4c8a00000     112K r--p  /bin/busybox|
000055d4c8a1c000    1096K r-xp  /bin/busybox|
000055d4c8d2e000      12K rw-p  /bin/busybox|
000055d4c9a00000     132K rw-p  [heap]|
00007f3a10000000     132K rw-p    [ anon ]|
00007f3a10021000   65404K ---p    [ anon ]|
00007f3a14100000     340K r-xp  /lib/ld-musl-x86_64.so.1 (deleted)|
00007f3a14200000       4K rw-s  /dev/shm/a b|
00007ffd5a000000     132K rw-p  [stack]|
00007ffd5a1f0000      16K r--p  [vvar]|
00007ffd5a1f4000       8K r-xp  [vdso]|
ffffffffff600000       4K --xp  [vsyscall]|
stderr:
status 0
```

### pmap -xq 42

```cu
(fixture (list "pmap" "-xq" "42"))
```
---
```output
42: /bin/sh -c sleep 9|
000055d4c8a00000     112      56       0       0  r--p  /bin/busybox|
000055d4c8a1c000    1096     450       0       0  r-xp  /bin/busybox|
000055d4c8d2e000      12      12      12       0  rw-p  /bin/busybox|
000055d4c9a00000     132      20      20       8  rw-p  [heap]|
00007f3a10000000     132       4       4      64  rw-p    [ anon ]|
00007f3a10021000   65404       0       0       0  ---p    [ anon ]|
00007f3a14100000     340     113       0       0  r-xp  /lib/ld-musl-x86_64.so.1 (deleted)|
00007f3a14200000       4       2       4       0  rw-s  /dev/shm/a b|
00007ffd5a000000     132      16      16       4  rw-p  [stack]|
00007ffd5a1f0000      16       0       0       0  r--p  [vvar]|
00007ffd5a1f4000       8       0       0       0  r-xp  [vdso]|
ffffffffff600000       4       0       0       0  --xp  [vsyscall]|
stderr:
status 0
```

### pmap -x 7

```cu
(fixture (list "pmap" "-x" "7"))
```
---
```output
7: a?b x y|
Address		  Kbytes     PSS   Dirty    Swap  Mode  Mapping|
0000000000400000       4       4       0       0  r-xp  /a|
0000001000000000 134217728    2048    2048 1048576  rw-p    [ anon ]|
----------------  ------  ------  ------  ------|
total kB       134217732    2052    2048 1048576|
stderr:
status 0
```

### pmap 7 42

```cu
(fixture (list "pmap" "7" "42"))
```
---
```output
7: a?b x y|
0000000000400000       4K r-xp  /a|
0000001000000000 134217728K rw-p    [ anon ]|
 total         134217732K|
42: /bin/sh -c sleep 9|
000055d4c8a00000     112K r--p  /bin/busybox|
000055d4c8a1c000    1096K r-xp  /bin/busybox|
000055d4c8d2e000      12K rw-p  /bin/busybox|
000055d4c9a00000     132K rw-p  [heap]|
00007f3a10000000     132K rw-p    [ anon ]|
00007f3a10021000   65404K ---p    [ anon ]|
00007f3a14100000     340K r-xp  /lib/ld-musl-x86_64.so.1 (deleted)|
00007f3a14200000       4K rw-s  /dev/shm/a b|
00007ffd5a000000     132K rw-p  [stack]|
00007ffd5a1f0000      16K r--p  [vvar]|
00007ffd5a1f4000       8K r-xp  [vdso]|
ffffffffff600000       4K --xp  [vsyscall]|
 total             67392K|
stderr:
status 0
```

### pmap 9

```cu
(fixture (list "pmap" "9"))
```
---
```output
9: init|
stderr:
status 42
```

### pmap -x 9

```cu
(fixture (list "pmap" "-x" "9"))
```
---
```output
9: init|
Address		  Kbytes     PSS   Dirty    Swap  Mode  Mapping|
stderr:
status 42
```

### pmap 99

```cu
(fixture (list "pmap" "99"))
```
---
```output
stderr:
status 42
```

### pmap -x 99 42

```cu
(fixture (list "pmap" "-x" "99" "42"))
```
---
```output
42: /bin/sh -c sleep 9|
Address		  Kbytes     PSS   Dirty    Swap  Mode  Mapping|
000055d4c8a00000     112      56       0       0  r--p  /bin/busybox|
000055d4c8a1c000    1096     450       0       0  r-xp  /bin/busybox|
000055d4c8d2e000      12      12      12       0  rw-p  /bin/busybox|
000055d4c9a00000     132      20      20       8  rw-p  [heap]|
00007f3a10000000     132       4       4      64  rw-p    [ anon ]|
00007f3a10021000   65404       0       0       0  ---p    [ anon ]|
00007f3a14100000     340     113       0       0  r-xp  /lib/ld-musl-x86_64.so.1 (deleted)|
00007f3a14200000       4       2       4       0  rw-s  /dev/shm/a b|
00007ffd5a000000     132      16      16       4  rw-p  [stack]|
00007ffd5a1f0000      16       0       0       0  r--p  [vvar]|
00007ffd5a1f4000       8       0       0       0  r-xp  [vdso]|
ffffffffff600000       4       0       0       0  --xp  [vsyscall]|
----------------  ------  ------  ------  ------|
total kB           67392     673      56      76|
stderr:
status 42
```

### pmap abc 42

```cu
(fixture (list "pmap" "abc" "42"))
```
---
```output
stderr:
pmap: invalid number 'abc'
status 1
```

### pmap 42 3000000000

```cu
(fixture (list "pmap" "42" "3000000000"))
```
---
```output
42: /bin/sh -c sleep 9|
000055d4c8a00000     112K r--p  /bin/busybox|
000055d4c8a1c000    1096K r-xp  /bin/busybox|
000055d4c8d2e000      12K rw-p  /bin/busybox|
000055d4c9a00000     132K rw-p  [heap]|
00007f3a10000000     132K rw-p    [ anon ]|
00007f3a10021000   65404K ---p    [ anon ]|
00007f3a14100000     340K r-xp  /lib/ld-musl-x86_64.so.1 (deleted)|
00007f3a14200000       4K rw-s  /dev/shm/a b|
00007ffd5a000000     132K rw-p  [stack]|
00007ffd5a1f0000      16K r--p  [vvar]|
00007ffd5a1f4000       8K r-xp  [vdso]|
ffffffffff600000       4K --xp  [vsyscall]|
 total             67392K|
stderr:
pmap: number 3000000000 is not in 0..2147483647 range
status 1
```

### pmap -qx 7 9

```cu
(fixture (list "pmap" "-qx" "7" "9"))
```
---
```output
7: a?b x y|
0000000000400000       4       4       0       0  r-xp  /a|
0000001000000000 134217728    2048    2048 1048576  rw-p    [ anon ]|
9: init|
stderr:
status 42
```

### pmap 4294967296

```cu
(fixture (list "pmap" "4294967296"))
```
---
```output
stderr:
pmap: invalid number '4294967296'
status 1
```

### pmap 11

```cu
(fixture (list "pmap" "11"))
```
---
```output
11: prog argument-000-abcdefghijklmnopqrstuvwxyz0123456789 argument-001-abcdefghijklmnopqrstuvwxyz0123456789 argument-002-abcdefghijklmnopqrstuvwxyz0123456789 argument-003-abcdefghijklmnopqrstuvwxyz0123456789 argument-004-abcdefghijklmnopqrstuvwxyz0123456789 argument-005-abcdefghijklmnopqrstuvwxyz0123456789 argument-006-abcdefghijklmnopqrstuvwxyz0123456789 argument-007-abcdefghijklmnopqrstuvwxyz0123456789 argument-008-abcdefghijklmnopqrstuvwxyz0123456789 argument-009-abcdefghijklmnopqrstuvwxyz0123456789 argument-010-abcdefghijklmnopqrstuvwxyz0123456789 argument-011-abcdefghijklmnopqrstuvwxyz0123456789 argument-012-abcdefghijklmnopqrstuvwxyz0123456789 argument-013-abcdefghijklmnopqrstuvwxyz0123456789 argument-014-abcdefghijklmnopqrstuvwxyz0123456789 argument-015-abcdefghijklmnopqrstuvwxyz0123456789 argument-016-abcdefghijklmnopqrstuvwxyz0123456789 argument-017-abcdefghijklmnopqrstuvwxyz0123456789 argument-018-abcdefghijklmnopqrstuvwxyz0123456789 argument-019-abcdefghijklmnopqrstuvwxyz0123456789 argument-020-abcdefghijklmnopqrstuvwxyz0123456789 argument-021-abcdefghijklmnopqrstuvwxyz0123456789 argument-022-abcdefghijklmnopqrstuvwxyz0123456789 argument-023-abcdefghijklmnopqrstuvwxyz0123456789 argument-024-abcdefghijklmnopqrstuvwxyz0123456789 argument-025-abcdefghijklmnopqrstuvwxyz0123456789 argument-026-abcdefghijklmnopqrstuvwxyz0123456789 argument-027-abcdefghijklmnopqrstuvwxyz0123456789 argument-028-abcdefghijklmnopqrstuvwxyz0123456789 argument-029-abcdefghijklmnopqrstuvwxyz0123456789 argument-030-abcdefghijklmnopqrstuvwxyz0123456789 argument-031-abcdefghijklmnopqrstuvwxyz0123456789 argument-032-abcdefghijklmnopqrstuvwxyz0123456789 argument-033-abcdefghijklmnopqrstuvwxyz0123456789 argument-034-abcdefghijklmnopqrstuvwxyz0123456789 argument-035-abcdefghijklmnopqrstuvwxyz0123456789 argument-036-abcdefghijklmnopqrstuvwxyz0123456789 argument-037-abcdefghijklmnopqrstuvwxyz0123456789 argument-038-abcdefghijklmnopqrstuvwxyz0123456789 argument-039-abcdefghijklmnopqrstuvwxyz0123456789 argument-040-abcdefghijklmnopqrstuvwxyz0123456789 argument-041-abcdefghijklmnopqrstuvwxyz0123456789 argument-042-abcdefghijklmnopqrstuvwxyz0123456789 argument-043-abcdefghijklmnopqrstuvwxyz0123456789 argument-044-abcdefghijklmnopqrstuvwxyz0123456789 argument-045-abcdefghijklmnopqrstuvwxyz0123456789 argument-046-abcdefghijklmnopqrstuvwxyz0123456789 argument-047-abcdefghijklmnopqrstuvwxyz0123456789 argument-048-abcdefghijklmnopqrstuvwxyz0123456789 argument-049-abcdefghijklmnopqrstuvwxyz0123456789 argument-050-abcdefghijklmnopqrstuvwxyz0123456789 argument-051-abcdefghijklmnopqrstuvwxyz0123456789 argument-052-abcdefghijklmnopqrstuvwxyz0123456789 argument-053-abcdefghijklmnopqrstuvwxyz0123456789 argument-054-abcdefghijklmnopqrstuvwxyz0123456789 argument-055-abcdefghijklmnopqrstuvwxyz0123456789 argument-056-abcdefghijklmnopqrstuvwxyz0123456789 argument-057-abcdefghijklmnopqrstuvwxyz0123456789 argument-058-abcdefghijklmnopqrstuvwxyz0123456789 argument-059-abcdefghijklmnopqrstuvwxyz0123456789 argument-060-abcdefghijklmnopqrstuvwxyz0123456789 argument-061-abcdefghijklmnopqrstuvwxyz0123456789 argument-062-abcdefghijklmnopqrstuvwxyz0123456789 argument-063-abcdefghijklmnopqrstuvwxyz0123456789 argument-064-abcdefghijklmnopqrstuvwxyz0123456789 argument-065-abcdefghijklmnopqrstuvwxyz0123456789 argument-066-abcdefghijklmnopqrstuvwxyz0123456789 argument-067-abcdefghijklmnopqrstuvwxyz0123456789 argument-068-abcdefghijklmnopqrstuvwxyz0123456789 argument-069-abcdefghijklmnopqrstuvwxyz0123456789 argument-070-abcdefghijklmnopqrstuvwxyz0123456789 argument-071-abcdefghijklmnopqrstuvwxyz0123456789 argument-072-abcdefghijklmnopqrstuvwxyz0123456789 argument-073-abcdefghijklmnopqrstuvwxyz0123456789 argument-074-abcdefghijklmnopqrstuvwxyz0123456789 argument-075-abcdefghijklmnopqrstuvwxyz0123456789 argument-076-abcdefghijklmnopqrstuvwxyz0123456789 argument-077-abcdefghijklmnopqrstuvwxyz0123456789 argument-078-abcdefghijklmnopqrstuvwxyz0123456789 argument-079-abcdefghijklmnopqrstuvwxyz0123456789 argument-080-abcdefghijklmnopqrstuvwxyz0123456789 argument-081-abcdefghijklmnopqrstuvwxyz0|
0000000000400000       4K r-xp  /prog|
 total                 4K|
stderr:
status 0
```

### no pid: the usage text, and 1

```cu
(fixture (list "pmap"))
```
---
```output
stderr:
Usage: pmap [-xq] PID...

Display process memory usage

	-x	Show details
	-q	Quiet
status 1
```

## this machine

### pmap's own process: its line, a row a region in address order, the total of their sizes

```cu
(let ((r (run (list "pmap" (cu-int->str (sys-getpid)))))) (def ls (filter (fn (_ l) (> (byte-len l) 0)) (cu-lines (first r)))) (def rows (rest (reverse (rest (reverse ls))))) (def kib (fn (_ l) (cu-num-prefix (Str8 trim-left (substring l 17 (byte-len l)))))) (def addrs (map (fn (_ l) (substring l 0 16)) rows)) (def sorted? (fn (self as) (if (null? (rest as)) #t (if (Str8 <? (first as) (first (rest as))) (self (rest as)) #f)))) (list (Str8 starts? (string-append (cu-int->str (sys-getpid)) ": ") (first ls)) (> (length rows) 4) (sorted? addrs) (= (List fold (fn (_ a l) (+ a (kib l))) 0 rows) (let ((t (first (reverse ls)))) (cu-num-prefix (Str8 trim-left (substring t 7 (byte-len t)))))) (first (rest r)) (first (rest (rest r)))))
```
---
    (#t #t #t #t "" 0)

### -x on its own process: the header, a row a region, the dashes and the totals

```cu
(let ((r (run (list "pmap" "-x" (cu-int->str (sys-getpid)))))) (def ls (filter (fn (_ l) (> (byte-len l) 0)) (cu-lines (first r)))) (list (first (rest ls)) (first (rest (reverse ls))) (Str8 starts? "total kB " (first (reverse ls))) (first (rest (rest r)))))
```
---
    ("Address\t\t  Kbytes     PSS   Dirty    Swap  Mode  Mapping" "----------------  ------  ------  ------  ------" #t 0)
