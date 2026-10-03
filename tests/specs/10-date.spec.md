# @weight 3

date, and the strftime it grew.

Every block pins the time with `-d @SECONDS`, and the suite runs under
`TZ=UTC0` (tests/spec-runner.sh); a spec that read the clock would
pass until midnight somewhere.

The calendar is `x/sys/date.x`'s, so what is exercised here is the formatting,
plus the one sum this applet owns: the day of the year.

## the directives

### the default format is busybox's

```cu
(display (cu-run (list "date" "-d" "@1757796602") ""))
```
---
```output
Sat Sep 13 20:50:02 UTC 2025
0
```

### the date and time directives

```cu
(display (cu-run (list "date" "-d" "@1757796602"
  "+%Y|%y|%C|%m|%d|%e|%H|%k|%I|%l|%M|%S") ""))
```
---
```output
2025|25|20|09|13|13|20|20|08| 8|50|02
0
```

### the names, and the numbered weekday

```cu
(display (cu-run (list "date" "-d" "@1757796602"
  "+%a|%A|%b|%h|%B|%p|%w|%u|%j") ""))
```
---
```output
Sat|Saturday|Sep|Sep|September|PM|6|6|256
0
```

### the compound ones expand to the parts spelled out

```cu
(display (cu-run (list "date" "-d" "@1757796602" "+%D|%F|%T|%R|%r") ""))
```
---
```output
09/13/25|2025-09-13|20:50:02|20:50|08:50:02 PM
0
```

### under TZ=UTC0 the zone is UTC, its offset +0000

```cu
(display (cu-run (list "date" "-d" "@1757796602" "+%z|%Z|%s|%%") ""))
```
---
```output
+0000|UTC|1757796602|%
0
```

### a directive nothing knows is left as it was written

```cu
(display (cu-run (list "date" "-d" "@1757796602" "+%Q|%Y") ""))
```
---
```output
%Q|2025
0
```

## the day of the year, which is the one sum here

### it counts the leap day, and does not count one that is not there

2000 is a leap year and 2100 is not, so March 1st is day 61 in one and 60 in
the other.

```cu
(do (display (cu-run (list "date" "-d" "@951868800" "+%j") ""))
    (display (cu-run (list "date" "-d" "@4107542400" "+%j") "")))
```
---
```output
061
0060
0
```

## reading a time from somewhere else

### -d takes an ISO stamp as well as @SECONDS

```cu
(display (cu-run (list "date" "-d" "2024-03-01T12:30:45Z" "+%F %T") ""))
```
---
```output
2024-03-01 12:30:45
0
```

### -D says how to read it, in the same directives the formatter writes

```cu
(display (cu-run (list "date" "-D" "%Y/%m/%d" "-d" "2024/03/01" "+%F") ""))
```
---
```output
2024-03-01
0
```

### a -d that will not parse is an error, not a fall back to now

```cu
(display (cu-run (list "date" "-d" "not a date") ""))
```
---
    1

### -d reads a date with a time after a space or a T, the seconds optional

```cu
(do (cu-run (list "date" "-d" "2020-01-02 03:04:05" "+%F %T") "")
    (cu-run (list "date" "-d" "2020-01-02 03:04" "+%F %T") "")
    (cu-run (list "date" "-d" "2020-01-02T03:04:05Z" "+%F %T") "")
    (cu-run (list "date" "-d" "2020-01-02T03:04:05z" "+%F %T") "")
    (display (cu-run (list "date" "-d" "2020-01-02T03:04" "+%F %T") "")))
```
---
```output
2020-01-02 03:04:05
2020-01-02 03:04:00
2020-01-02 03:04:05
2020-01-02 03:04:05
2020-01-02 03:04:00
0
```

### white space around a -d and inside it is squeezed, and fields need no padding

```cu
(do (cu-run (list "date" "-d" " 2020-01-02" "+%F %T") "")
    (cu-run (list "date" "-d" "2020-01-02  03:04" "+%F %T") "")
    (cu-run (list "date" "-d" "2020-01-02 3:4:5" "+%F %T") "")
    (display (cu-run (list "date" "-d" "2020-1-2" "+%F %T") "")))
```
---
```output
2020-01-02 00:00:00
2020-01-02 03:04:00
2020-01-02 03:04:05
2020-01-02 00:00:00
0
```

### a time alone is read on today's date

The only block that reads the clock, and it reads it on both sides of the -d,
so a midnight between them cannot fail it.

```cu
(do (def cap (fn (_ argv) (do (sys-dup2 1 9) (let ((fd (file-open-write "/tmp/x-cu-date-cap"))) (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1) (file-close fd) (file-read-all "/tmp/x-cu-date-cap"))))))
    (def before (cap (list "date" "+%F")))
    (def got (cap (list "date" "-d" "03:04:05" "+%F")))
    (def after (cap (list "date" "+%F")))
    (display (if (if (string=? got before) #t (string=? got after)) "today\n" "another day\n"))
    (display (cu-run (list "date" "-d" "03:04" "+%T") "")))
```
---
```output
today
03:04:00
0
```

### a -d must use its whole input and name a real moment

```cu
(do (display (cu-run (list "date" "-d" "2020-01-02 junk") "")) (newline)
    (display (cu-run (list "date" "-d" "2020-02-30") "")) (newline)
    (display (cu-run (list "date" "-d" "24:00") "")) (newline)
    (display (cu-run (list "date" "-d" "2020-01-02 03:04:60") "")))
```
---
```output
1
1
1
1
```

### -r reads a file's modification time

```cu
(do (proc-run (list "/bin/sh" "-c"
      "touch -t 202403011230.45 /tmp/x-cu-date-r"))
    (display (cu-run (list "date" "-u" "-r" "/tmp/x-cu-date-r" "+%F") ""))
    (proc-run (list "/bin/sh" "-c" "rm -f /tmp/x-cu-date-r"))
    ())
```
---
```output
2024-03-01
0
```

## the whole-output flags

### -R is RFC 2822

```cu
(display (cu-run (list "date" "-R" "-d" "@1757796602") ""))
```
---
```output
Sat, 13 Sep 2025 20:50:02 +0000
0
```

### -I is the date, and its SPEC attaches; the zone is +hh:mm, as busybox writes it

`-I`'s argument is optional and attached, which Opts cannot declare, so the
five spellings are declared outright.

```cu
(do (display (cu-run (list "date" "-I" "-d" "@1757796602") ""))
    (display (cu-run (list "date" "-Iseconds" "-d" "@1757796602") "")))
```
---
```output
2025-09-13
02025-09-13T20:50:02+00:00
0
```

### -u asks for UTC, as busybox's TZ=UTC0 does

```cu
(display (cu-run (list "date" "-u" "-d" "@1757796602" "+%F %T %Z") ""))
```
---
```output
2025-09-13 20:50:02 UTC
0
```

## local time

These set TZ to a POSIX rule, which glibc and Darwin read alike with no zone
database, and put the suite's UTC0 back.  The expectations are the system
date's in the same zone: `TZ=... date -r SECS`, and `date -j -f` for reading.

### the default format, %z, %Z and -R in a zone behind UTC with daylight time

```cu
(do (sys-setenv "TZ" "EST5EDT,M3.2.0,M11.1.0")
    (def r (list (cu-run (list "date" "-d" "@1757796602") "")
                 (cu-run (list "date" "-d" "@1757796602" "+%z|%Z") "")
                 (cu-run (list "date" "-R" "-d" "@1757796602") "")
                 (cu-run (list "date" "-Iseconds" "-d" "@1757796602") "")
                 (cu-run (list "date" "-u" "-d" "@1757796602") "")))
    (sys-setenv "TZ" "UTC0")
    (display r))
```
---
```output
Sat Sep 13 16:50:02 EDT 2025
-0400|EDT
Sat, 13 Sep 2025 16:50:02 -0400
2025-09-13T16:50:02-04:00
Sat Sep 13 20:50:02 UTC 2025
(0 0 0 0 0)
```

### a zone half an hour off, across midnight

```cu
(do (sys-setenv "TZ" "<+0530>-5:30")
    (def r (cu-run (list "date" "-d" "@1757796602" "+%F %T %z %Z") ""))
    (sys-setenv "TZ" "UTC0")
    (display r))
```
---
```output
2025-09-14 02:20:02 +0530 +0530
0
```

### -d and -D read a local time, and -u reads it as UTC

```cu
(do (sys-setenv "TZ" "EST5EDT,M3.2.0,M11.1.0")
    (def r (list (cu-run (list "date" "-d" "2025-09-13 16:50:02" "+%s") "")
                 (cu-run (list "date" "-D" "%Y%m%d%H%M%S" "-d" "20250115120000" "+%s") "")
                 (cu-run (list "date" "-u" "-d" "2025-09-13 16:50:02" "+%s") "")))
    (sys-setenv "TZ" "UTC0")
    (display r))
```
---
```output
1757796602
1736960400
1757782202
(0 0 0)
```

### -s is not declared, because the clock cannot be set from here

```cu
(display (cu-run (list "date" "-s" "2024-01-01") ""))
```
---
    1
