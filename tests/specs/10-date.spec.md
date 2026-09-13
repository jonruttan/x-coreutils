# @weight 3

date, and the strftime it grew.

Every block pins the time with `-d @SECONDS`; a spec that read the clock would
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

### the zone is UTC because the platform has no other

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

### -I is the date, and its SPEC attaches

`-I`'s argument is optional and attached, which Opts cannot declare, so the
five spellings are declared outright.

```cu
(do (display (cu-run (list "date" "-I" "-d" "@1757796602") ""))
    (display (cu-run (list "date" "-Iseconds" "-d" "@1757796602") "")))
```
---
```output
2025-09-13
02025-09-13T20:50:02+0000
0
```

### -u asks for UTC and gets it, which is all this platform has

```cu
(display (cu-run (list "date" "-u" "-d" "@1757796602" "+%F %T %Z") ""))
```
---
```output
2025-09-13 20:50:02 UTC
0
```

### -s is not declared, because the clock cannot be set from here

```cu
(display (cu-run (list "date" "-s" "2024-01-01") ""))
```
---
    2
