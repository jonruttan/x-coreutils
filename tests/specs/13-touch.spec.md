# @weight 2

touch -d, -t and -r: the time a file is given, rather than the clock.  Times
are read back as unix seconds, so nothing here depends on the timezone of the
machine running it; the expected seconds are GNU touch's under TZ=UTC.  -d
reads its date the way date does, so as UTC (cu/date.x records that
divergence).

## the fixtures

### a scratch directory, and readers for the two times and for stderr

The readers turn an i64 time that arrived unsigned back into a signed one.
Under this harness file-stat-full reads a time before 1970 as its unsigned
64-bit value, where x run from its state image reads it signed, so the
readers accept either and the cases below state the signed time.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-tch && mkdir -p /tmp/x-cu-tch")) (def tch (fn (_ n) (string-append "/tmp/x-cu-tch/" n))) (def signed (fn (_ v) (if (> v 9223372036854775807) (- v 18446744073709551616) v))) (def mt (fn (_ p) (signed (%cu-stat-get (file-stat-full p) (lit mtime))))) (def at (fn (_ p) (signed (%cu-stat-get (file-stat-full p) (lit atime))))) (def times (fn (_ p) (do (display (at p)) (display " ") (display (mt p)) (newline)))) (def cu-err (fn (_ argv) (do (sys-dup2 2 9) (let ((fd (file-open-write (tch ".err")))) (do (sys-dup2 fd 2) (def st (cu-run argv "")) (sys-dup2 9 2) (file-close fd) (string-append (file-read-all (tch ".err")) (%cu-int->str st))))))) (display "made"))
```
---
    made

## the times asked for

### -t sets both times from [[CC]YY]MMDDhhmm[.ss]

```cu
(do (file-write-all (tch "a") "") (cu-run (list "touch" "-t" "202101020304.05" (tch "a")) "") (times (tch "a")))
```
---
    1609556645 1609556645

### two year digits pivot at 69, and a time before 1970 is written and copied correctly

```cu
(do (cu-run (list "touch" "-t" "6901020304" (tch "old")) "") (times (tch "old")) (cu-run (list "touch" "-r" (tch "old") (tch "oldcopy")) "") (times (tch "oldcopy")) (cu-run (list "touch" "-t" "6801020304" (tch "new")) "") (times (tch "new")))
```
---
```output
-31438560 -31438560
-31438560 -31438560
3092699040 3092699040
```

### a leap day is a real date, and a second of 60 rolls into the next minute

```cu
(do (cu-run (list "touch" "-t" "202402290000" (tch "leap")) "") (times (tch "leap")) (cu-run (list "touch" "-t" "202101010000.60" (tch "sixty")) "") (times (tch "sixty")))
```
---
```output
1709164800 1709164800
1609459260 1609459260
```

### -d takes a date or @seconds

```cu
(do (cu-run (list "touch" "-d" "2020-01-02" (tch "d")) "") (times (tch "d")) (cu-run (list "touch" "-d" "@1600000000" (tch "at")) "") (times (tch "at")))
```
---
```output
1577923200 1577923200
1600000000 1600000000
```

### -r copies both times from its file, and -r with -d takes -d's time

```cu
(do (cu-run (list "touch" "-t" "201906151200" (tch "ref")) "") (cu-run (list "touch" "-r" (tch "ref") (tch "copy")) "") (times (tch "copy")) (cu-run (list "touch" "-r" (tch "ref") "-d" "2020-01-02" (tch "both")) "") (times (tch "both")))
```
---
```output
1560600000 1560600000
1577923200 1577923200
```

### a missing operand is created at the time asked, and -c leaves it missing

```cu
(do (cu-run (list "touch" "-t" "202101020304.05" (tch "made")) "") (times (tch "made")) (cu-run (list "touch" "-c" "-t" "202101020304.05" (tch "not")) "") (display (if (file-exists? (tch "not")) "created" "absent")))
```
---
```output
1609556645 1609556645
absent
```

## what is refused

### a stamp that names no real moment is refused, and the file keeps its time

```cu
(do (cu-run (list "touch" "-t" "202101020304.05" (tch "keep")) "") (display (cu-err (list "touch" "-t" "202102300000" (tch "keep")))) (newline) (display (cu-err (list "touch" "-t" "abc" (tch "keep")))) (newline) (times (tch "keep")))
```
---
```output
touch: invalid date format '202102300000'
1
touch: invalid date format 'abc'
1
1609556645 1609556645
```

### a -d that will not read is refused

```cu
(display (cu-err (list "touch" "-d" "nonsense" (tch "keep"))))
```
---
```output
touch: invalid date format 'nonsense'
1
```

### -t with -d or with -r names two times, and -r needs a file to read

```cu
(do (display (cu-err (list "touch" "-r" (tch "ref") "-t" "202101020304" (tch "keep")))) (newline) (display (cu-err (list "touch" "-d" "2020-01-02" "-t" "202101020304" (tch "keep")))) (newline) (display (cu-err (list "touch" "-r" (tch "missing") (tch "keep")))))
```
---
```output
touch: cannot specify times from more than one source
1
touch: cannot specify times from more than one source
1
touch: failed to get attributes of '/tmp/x-cu-tch/missing': No such file or directory
1
```
