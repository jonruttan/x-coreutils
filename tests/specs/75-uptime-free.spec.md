# @weight 1

busybox's uptime (procps/uptime.c) and free (procps/free.c), over the
machine as x/sys/host reports it.  The layouts are checked against busybox's
own code: its printf lines and its make_human_readable_str, compiled
unchanged and run on the inputs each case gives.  The runs at the end ask the
machine this runs on, so they check the shape of the line and what the system
tools report, not a value.

## the fixtures

### a run of an applet with its standard input, stdout, stderr and status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-upf && mkdir -p /tmp/x-cu-upf")) (def nf (fn (_ n) (string-append "/tmp/x-cu-upf/" n))) (def run-out (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (list (file-read-all (nf ".out")) (file-read-all (nf ".err")) st)))))) (def sh-out (fn (_ cmd) (do (proc-run (list "/bin/sh" "-c" (string-append cmd (string-append " > " (nf ".sh"))))) (file-read-all (nf ".sh"))))) (def with-tz (fn (_ tz thunk) (do (def was (sys-getenv "TZ")) (sys-setenv "TZ" tz) (def r (thunk)) (if (null? was) (sys-unsetenv "TZ") (sys-setenv "TZ" was)) r))) (display "made"))
```
---
    made

## uptime

### the line: under an hour, an hour, a day, days; the users; the loads

The time is 1790000000, 14:13:20 in the zone TZ=UTC0 names.  The loads are
hundredths, as load-centi makes them from the kernel's fixed-point counts.

```cu
(with-tz "UTC0" (fn (_) (display (%ps-uptime-line 1790000000 59 0 (list 0 0 0))) (display (%ps-uptime-line 1790000000 3599 1 (list 100 50 0))) (display (%ps-uptime-line 1790000000 3600 2 (list 384 530 708))) (display (%ps-uptime-line 1790000000 87000 3 (list 188 99 0))) (display (%ps-uptime-line 1790000000 191220 12 (list 1525 1525 1500))) (display (%ps-uptime-line 1790036309 38700 1 (list 0 199 10000)))))
```
---
```output
 14:13:20 up 0 min,  0 users,  load average: 0.00, 0.00, 0.00
 14:13:20 up 59 min,  1 users,  load average: 1.00, 0.50, 0.00
 14:13:20 up  1:00,  2 users,  load average: 3.84, 5.30, 7.08
 14:13:20 up 1 day, 10 min,  3 users,  load average: 1.88, 0.99, 0.00
 14:13:20 up 2 days,  5:07,  12 users,  load average: 15.25, 15.25, 15.00
 00:18:29 up 10:45,  1 users,  load average: 0.00, 1.99, 100.00
```

### the clock is local time: a zone behind UTC with daylight time, and one half an hour off

POSIX rule strings, which glibc and Darwin read alike with no zone database.

```cu
(do (with-tz "EST5EDT,M3.2.0,M11.1.0" (fn (_) (display (%ps-uptime-line 1790000000 3599 1 (list 100 50 0))) (display (%ps-uptime-line 1790036309 38700 1 (list 0 199 10000))))) (with-tz "<+0530>-5:30" (fn (_) (display (%ps-uptime-line 1790000000 3599 1 (list 100 50 0))) (display (%ps-uptime-line 1790036309 38700 1 (list 0 199 10000))))))
```
---
```output
 10:13:20 up 59 min,  1 users,  load average: 1.00, 0.50, 0.00
 20:18:29 up 10:45,  1 users,  load average: 0.00, 1.99, 100.00
 19:43:20 up 59 min,  1 users,  load average: 1.00, 0.50, 0.00
 05:48:29 up 10:45,  1 users,  load average: 0.00, 1.99, 100.00
```

### load-centi truncates a count over its scale to hundredths, as LOAD_INT and LOAD_FRAC do

Counts over 65536, sysinfo's scale, and over 2048, Darwin's fscale.

```cu
(map (fn (_ c) (load-centi (Float / (first c) (rest c)))) (list (pair 655 65536) (pair 252160 65536) (pair 347680 65536) (pair 464640 65536) (pair 65535 65536) (pair 131071 65536) (pair 6553600 65536) (pair 7880 2048) (pair 2047 2048)))
```
---
    (0 384 530 708 99 199 10000 384 99)

### uptime -s: the boot time, in UTC and in local zones

```cu
(map (fn (_ tz) (with-tz tz (fn (_) (%ps-boot-line 1790000000)))) (list "UTC0" "EST5EDT,M3.2.0,M11.1.0" "<+0530>-5:30"))
```
---
    ("2026-09-21 14:13:20\n" "2026-09-21 10:13:20\n" "2026-09-21 19:43:20\n")

## free

Each case shows two machines: one whose /proc/meminfo has every line free
reads, and one shaped as Darwin reports it, with no shared, buffers,
reclaimable or available -- busybox's lines not there, so its
`-/+ buffers/cache:` line.

### in kilobytes, busybox's default and -k

```cu
(do (display (%ps-free-text (list (pair (lit total) 8192000000) (pair (lit free) 1024000000) (pair (lit shared) 51200000) (pair (lit buffers) 102400000) (pair (lit cached) 2048000000) (pair (lit reclaimable) 307200000) (pair (lit available) 5120000000) (pair (lit swap-total) 2147483648) (pair (lit swap-free) 1073741824)) 1024)) (display (%ps-free-text (list (pair (lit total) 17179869184) (pair (lit free) 106414080) (pair (lit shared) ()) (pair (lit buffers) ()) (pair (lit cached) 3298534400) (pair (lit reclaimable) ()) (pair (lit available) ()) (pair (lit swap-total) 17179869184) (pair (lit swap-free) 1468203008)) 1024)))
```
---
```output
              total        used        free      shared  buff/cache   available
Mem:        8000000     4600000     1000000       50000     2400000     5000000
Swap:       2097152     1048576     1048576
              total        used        free      shared  buff/cache   available
Mem:       16777216    13452071      103920           0     3221225           0
-/+ buffers/cache:     13452071     3325145
Swap:      16777216    15343424     1433792
```

### -b: in bytes

```cu
(do (display (%ps-free-text (list (pair (lit total) 8192000000) (pair (lit free) 1024000000) (pair (lit shared) 51200000) (pair (lit buffers) 102400000) (pair (lit cached) 2048000000) (pair (lit reclaimable) 307200000) (pair (lit available) 5120000000) (pair (lit swap-total) 2147483648) (pair (lit swap-free) 1073741824)) 1)) (display (%ps-free-text (list (pair (lit total) 17179869184) (pair (lit free) 106414080) (pair (lit shared) ()) (pair (lit buffers) ()) (pair (lit cached) 3298534400) (pair (lit reclaimable) ()) (pair (lit available) ()) (pair (lit swap-total) 17179869184) (pair (lit swap-free) 1468203008)) 1)))
```
---
```output
              total        used        free      shared  buff/cache   available
Mem:     8192000000  4710400000  1024000000    51200000  2457600000  5120000000
Swap:    2147483648  1073741824  1073741824
              total        used        free      shared  buff/cache   available
Mem:    17179869184 13774920704   106414080           0  3298534400           0
-/+ buffers/cache:  13774920704  3404948480
Swap:   17179869184 15711666176  1468203008
```

### -m: in mebibytes

```cu
(do (display (%ps-free-text (list (pair (lit total) 8192000000) (pair (lit free) 1024000000) (pair (lit shared) 51200000) (pair (lit buffers) 102400000) (pair (lit cached) 2048000000) (pair (lit reclaimable) 307200000) (pair (lit available) 5120000000) (pair (lit swap-total) 2147483648) (pair (lit swap-free) 1073741824)) 1048576)) (display (%ps-free-text (list (pair (lit total) 17179869184) (pair (lit free) 106414080) (pair (lit shared) ()) (pair (lit buffers) ()) (pair (lit cached) 3298534400) (pair (lit reclaimable) ()) (pair (lit available) ()) (pair (lit swap-total) 17179869184) (pair (lit swap-free) 1468203008)) 1048576)))
```
---
```output
              total        used        free      shared  buff/cache   available
Mem:           7813        4492         977          49        2344        4883
Swap:          2048        1024        1024
              total        used        free      shared  buff/cache   available
Mem:          16384       13137         101           0        3146           0
-/+ buffers/cache:        13137        3247
Swap:         16384       14984        1400
```

### -g: in gibibytes

```cu
(do (display (%ps-free-text (list (pair (lit total) 8192000000) (pair (lit free) 1024000000) (pair (lit shared) 51200000) (pair (lit buffers) 102400000) (pair (lit cached) 2048000000) (pair (lit reclaimable) 307200000) (pair (lit available) 5120000000) (pair (lit swap-total) 2147483648) (pair (lit swap-free) 1073741824)) 1073741824)) (display (%ps-free-text (list (pair (lit total) 17179869184) (pair (lit free) 106414080) (pair (lit shared) ()) (pair (lit buffers) ()) (pair (lit cached) 3298534400) (pair (lit reclaimable) ()) (pair (lit available) ()) (pair (lit swap-total) 17179869184) (pair (lit swap-free) 1468203008)) 1073741824)))
```
---
```output
              total        used        free      shared  buff/cache   available
Mem:              8           4           1           0           2           5
Swap:             2           1           1
              total        used        free      shared  buff/cache   available
Mem:             16          13           0           0           3           0
-/+ buffers/cache:           13           3
Swap:            16          15           1
```

### -h: to a tenth, in the largest unit under 1024

```cu
(do (display (%ps-free-text (list (pair (lit total) 8192000000) (pair (lit free) 1024000000) (pair (lit shared) 51200000) (pair (lit buffers) 102400000) (pair (lit cached) 2048000000) (pair (lit reclaimable) 307200000) (pair (lit available) 5120000000) (pair (lit swap-total) 2147483648) (pair (lit swap-free) 1073741824)) 0)) (display (%ps-free-text (list (pair (lit total) 17179869184) (pair (lit free) 106414080) (pair (lit shared) ()) (pair (lit buffers) ()) (pair (lit cached) 3298534400) (pair (lit reclaimable) ()) (pair (lit available) ()) (pair (lit swap-total) 17179869184) (pair (lit swap-free) 1468203008)) 0)))
```
---
```output
              total        used        free      shared  buff/cache   available
Mem:           7.6G        4.4G      976.6M       48.8M        2.3G        4.8G
Swap:          2.0G        1.0G        1.0G
              total        used        free      shared  buff/cache   available
Mem:          16.0G       12.8G      101.5M           0        3.1G           0
-/+ buffers/cache:        12.8G        3.2G
Swap:         16.0G       14.6G        1.4G
```

### -h at the edges: under 1024 bare, 1023.95K up to 1024.0K, a tenth rounded down

```cu
(display (%ps-free-text (list (pair (lit total) 5242880) (pair (lit free) 1023) (pair (lit shared) 1048575) (pair (lit buffers) 1048524) (pair (lit cached) 0) (pair (lit reclaimable) 0) (pair (lit available) 1024) (pair (lit swap-total) 1048576000) (pair (lit swap-free) 1048051)) 0))
```
---
```output
              total        used        free      shared  buff/cache   available
Mem:           5.0M        4.0M        1023     1024.0K     1023.9K        1.0K
Swap:       1000.0M      999.0M     1023.5K
```

## this machine

### uptime: the time, up, the users, the load average, and status 0

```cu
(let ((r (run-out (list "uptime" "ignored")))) (def out (first r)) (list (Str8 starts? " " out) (= (byte-at out 3) #\:) (Str8 starts? " up " (substring out 9 13)) (Str8 includes? " users,  load average: " out) (Str8 ends? "\n" out) (first (rest r)) (first (rest (rest r)))))
```
---
    (#t #t #t #t #t "" 0)

### uptime -s: when the system says it booted

On Darwin the system's word is `sysctl kern.boottime`; elsewhere this case
compares the line with itself.

```cu
(let ((r (run-out (list "uptime" "-s")))) (def sys (sh-out "b=$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/^{ sec = \\([0-9]*\\),.*/\\1/p'); if [ -n \"$b\" ]; then date -r \"$b\" '+%Y-%m-%d %H:%M:%S'; fi")) (list (if (str=? sys "") #t (str=? sys (first r))) (first (rest r)) (first (rest (rest r)))))
```
---
    (#t "" 0)

### free: busybox's header, and the total the system reports, in kilobytes

```cu
(let ((r (run-out (list "free" "ignored")))) (def sys (sh-out "m=$(sysctl -n hw.memsize 2>/dev/null); if [ -n \"$m\" ]; then echo $(( (m + 512) / 1024 )); else awk '/^MemTotal:/ { print $2 }' /proc/meminfo; fi")) (def lines (Str8 split "\n" (first r))) (list (first lines) (str=? (Str8 trim sys) (first (rest (filter (fn (_ f) (not (str=? f ""))) (Str8 split " " (first (rest lines))))))) (first (rest r)) (first (rest (rest r)))))
```
---
    ("              total        used        free      shared  buff/cache   available" #t "" 0)

### free -m and free -h run; the unit is the first word's first letter, as busybox reads it

```cu
(list (first (rest (rest (run-out (list "free" "-m"))))) (first (rest (rest (run-out (list "free" "-h"))))) (map %ps-free-unit (list () (list "-b") (list "-k") (list "-m") (list "-g") (list "-h") (list "-mg") (list "-m" "-g") (list "-gm"))))
```
---
    (0 0 (1024 1 1024 1048576 1073741824 0 1048576 1048576 1073741824))

### an option neither knows is refused, as busybox refuses it: uptime through getopt, free with its usage alone

```cu
(list (rest (run-out (list "uptime" "-x"))) (rest (run-out (list "free" "-x"))))
```
---
    (("uptime: unrecognized option: x\nUsage: uptime\n\nDisplay the time since the last boot\n" 1) ("Usage: free [-bkmgh]\n\nDisplay free and used memory\n" 1))

## cleanup

### the scratch directory goes

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-upf")) (display "gone"))
```
---
    gone
