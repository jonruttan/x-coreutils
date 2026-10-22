# @weight 1

busybox's vmstat, iostat, mpstat and nmeter (procps/).  Their numbers are
checked against busybox's own: smart_ulltoa4 and smart_ulltoa5 and printf's
%.2f as a program built from busybox's source prints them, and each applet's
whole output as busybox's prints it over the same two samples -- a fixture
/proc at tests/fixtures/procstat/a, then b a second later.  The fixture runs
Host's Linux reader on either kernel; the wait between samples is replaced by
the step from a to b, and the memory record, which Host's Linux reader takes
from sysinfo(2), is the fixture's meminfo.  On this machine each applet is
then checked for its shape, since what it shows changes from run to run.  A
`|` marks the end of each line written to standard output.

## the fixture

### a run of an applet, with its stdout, stderr and status; the fixture's two samples

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-counters && mkdir -p /tmp/x-cu-counters")) (def nf (fn (_ n) (string-append "/tmp/x-cu-counters/" n))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (list (file-read-all (nf ".out")) (file-read-all (nf ".err")) st)))))) (def lines (fn (_ s) (filter (fn (_ l) (> (byte-len l) 0)) (cu-lines s)))) (def real-memory host-memory) (def real-wait host-wait) (def real-uptime host-uptime) (def real-now host-now) (def mem (fn (_ free dirty) (map (fn (_ p) (pair (first p) (* 1024 (rest p)))) (list (pair 'total 16384000) (pair 'free free) (pair 'shared 0) (pair 'buffers 234567) (pair 'cached 3456789) (pair 'reclaimable 123456) (pair 'available 13000000) (pair 'swap-total 2097152) (pair 'swap-free 1048576) (pair 'anon 0) (pair 'mapped 0) (pair 'slab 345678) (pair 'dirty dirty) (pair 'writeback 56))))) (def sample (fn (_ s) (do (Host source 'linux) (Host proc-root (string-append "tests/fixtures/procstat/" s)) (set! host-memory (fn (_) (if (str=? s "a") (mem 12345678 1234) (mem 12000000 4321)))) (set! host-uptime (fn (_) (if (str=? s "a") 1234567 1234667))) (set! host-now (fn (_) (if (str=? s "a") 0 1))) (set! host-wait (fn (_ us) (sample "b")))))) (def back (fn (_) (do (Host source (if os-darwin? 'darwin 'linux)) (Host proc-root "/proc") (set! host-memory real-memory) (set! host-wait real-wait) (set! host-uptime real-uptime) (set! host-now real-now)))) (def fixture (fn (_ argv) (do (sample "a") (def r (run argv)) (back) r))) (def mark (fn (_ s) (bytes->str ((fn (self i acc) (if (< i 0) acc (self (- i 1) (if (= (byte-at s i) 10) (pair 124 (pair 10 acc)) (pair (byte-at s i) acc))))) (- (byte-len s) 1) ())))) (def after-first (fn (_ s) ((fn (self i) (if (>= i (byte-len s)) "" (if (= (byte-at s i) 10) (substring s (+ i 1) (byte-len s)) (self (+ i 1))))) 0))) (def body (fn (_ r) (do (display (mark (after-first (first r)))) (list (first (rest r)) (first (rest (rest r))))))) (display "made"))
```
---
    made

## busybox's numbers

### smart_ulltoa5: five characters, scaled by 1024 past 99999

```cu
(map (fn (_ n) (vm-five n " kmgtpezy")) (list 0 7 9999 10000 10239 10240 99999 100000 102400 1023999 1048576 9437184 123456789 104857600 1073741824 1099511627776))
```
---
    ("    0" "    7" " 9999" "10000" "10239" "10240" "99999" "97.6k" " 100k" " 999k" "1024k" "9216k" " 117m" " 100m" "1024m" "1024g")

### smart_ulltoa4: four characters, scaled by 1024 past 9999

```cu
(map (fn (_ n) (vm-four n " kmgtpezy")) (list 0 7 9999 10000 10239 10240 99999 100000 102400 1023999 1048576 9437184 123456789 104857600 1073741824 1099511627776))
```
---
    ("   0" "   7" "9999" "9.7k" "9.9k" " 10k" " 97k" " 97k" "100k" "999k" "1.0m" "9.0m" "117m" "100m" "1.0g" "1.0t")

### a rate as printf's %.2f writes (double)A / B * 100: the double's own value, a tie to even

```cu
(map (fn (_ r) (vm-fixed (vm-rate (first r) (first (rest r)) 100) 2)) (list (list 0 1) (list 1 800) (list 1 3) (list 2 3) (list 123 1000) (list 5 8) (list 1 8000) (list 7 40000) (list 1234567 1000) (list 200 1) (list 3 1600) (list 1 6) (list 99999 100000)))
```
---
    ("0.00" "0.12" "33.33" "66.67" "12.30" "62.50" "0.01" "0.02" "123456.70" "20000.00" "0.19" "16.67" "100.00")

## vmstat

### over the fixture: the first row against a sample taken just before, the second a second later

```cu
(let ((r (fixture (list "vmstat" "1" "2")))) (display (mark (first r))) (list (first (rest r)) (first (rest (rest r)))))
```
---
```output
procs -----------memory---------- ---swap-- -----io---- -system-- -------cpu-------|
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st gu|
 2  1 1048576 12345678 234567 3580245 0   0     0     0    0    0  0  0  0  0  0  0|
 4  0 1048576 12000000 234567 3580245 12k 3  146k  4096 120k  44k 41 19 25  2  2 10|
("" 0)
```

### -n and no operands: one row under one header

```cu
(let ((r (fixture (list "vmstat" "-n")))) (list (length (lines (first r))) (first (rest (rest r)))))
```
---
    (3 0)

### on this machine: two header lines, then a row of eighteen numbers

```cu
(let ((r (run (list "vmstat")))) (def ls (lines (first r))) (list (first (rest (rest r))) (first (rest r)) (length ls) (first ls) (not (null? (re-search (re-compile "^ *[0-9]+( +[0-9]+[kmgt]?){17}$") (cu-nth 2 ls))))))
```
---
    (0 "" 3 "procs -----------memory---------- ---swap-- -----io---- -system-- -------cpu-------" #t)

### an interval or count that is not a number is refused as xatoi_positive refuses it, and -2 as an option

```cu
(list (run (list "vmstat" "x")) (run (list "vmstat" "99999999999")) (let ((r (run (list "vmstat" "1" "-2")))) (list (first (lines (first (rest r)))) (first (rest (rest r))))))
```
---
    (("" "vmstat: invalid number 'x'\n" 1) ("" "vmstat: invalid number '99999999999'\n" 1) ("vmstat: unrecognized option: 2" 1))

### a count of 0 is one row, and -n after the operands is still -n

```cu
(let ((r (fixture (list "vmstat" "1" "0" "-n")))) (list (length (lines (first r))) (first (rest (rest r)))))
```
---
    (3 0)

## iostat

### over the fixture: since boot, then over the second; a partition and an unused disk left out

```cu
(body (fixture (list "iostat" "1" "2")))
```
---
```output
|
avg-cpu:  %user   %nice %system %iowait  %steal   %idle|
          10.79    0.05    2.48    0.32    0.01   86.34|
|
Device:            tps   Blk_read/s   Blk_wrtn/s   Blk_read   Blk_wrtn|
sda              12.15       162.00        81.00    2000000    1000000|
nvme0n1           0.81        11.34         4.86     140000      60000|
|
avg-cpu:  %user   %nice %system %iowait  %steal   %idle|
          50.00    1.00   19.00    2.50    2.50   25.00|
|
Device:            tps   Blk_read/s   Blk_wrtn/s   Blk_read   Blk_wrtn|
sda             168.00      4567.00      1024.00       4567       1024|
nvme0n1           0.00         0.00         0.00          0          0|
|
("" 0)
```

### -d -k -z ALL: kilobytes, every disk but a partition, one with no transfers since the last left out

```cu
(body (fixture (list "iostat" "-d" "-k" "-z" "ALL" "1" "2")))
```
---
```output
|
Device:            tps    kB_read/s    kB_wrtn/s    kB_read    kB_wrtn|
sda              12.15        81.00        40.50    1000000     500000|
nvme0n1           0.81         5.67         2.43      70000      30000|
|
Device:            tps    kB_read/s    kB_wrtn/s    kB_read    kB_wrtn|
sda             168.00      2283.50       512.00       2283        512|
|
("" 0)
```

### on this machine: the system line, the CPU's shares, and a line a disk

```cu
(let ((r (run (list "iostat")))) (def ls (lines (first r))) (list (first (rest (rest r))) (first (rest r)) (not (null? (re-search (re-compile "^[A-Za-z]+ [^ ]+ \\([^)]*\\) \t[0-9][0-9]/[0-9][0-9]/[0-9][0-9] \t_[^_]+_\t\\([0-9]+ CPU\\)$") (first ls)))) (cu-nth 1 ls) (not (null? (re-search (re-compile "^ {8}( +[0-9]+\\.[0-9][0-9]){6}$") (cu-nth 2 ls)))) (cu-nth 3 ls)))
```
---
    (0 "" #t "avg-cpu:  %user   %nice %system %iowait  %steal   %idle" #t "Device:            tps   Blk_read/s   Blk_wrtn/s   Blk_read   Blk_wrtn")

## mpstat

### -A over the fixture: every report for each processor, then the average

```cu
(body (fixture (list "mpstat" "-A" "1" "1")))
```
---
```output
|
00:00:00     CPU    %usr   %nice    %sys %iowait    %irq   %soft  %steal  %guest   %idle|
00:00:01     all   40.00    1.00   15.00    2.50    2.50    1.50    2.50   10.00   25.00|
00:00:01       0   44.35    0.81   16.13    3.23    2.42    1.61    3.23   12.10   16.13|
00:00:01       1   32.89    1.32   13.16    1.32    2.63    1.32    1.32    6.58   39.47|
|
00:00:00     CPU    intr/s|
00:00:01     all  99561.29|
00:00:01       0    403.23|
00:00:01       1    328.95|
|
00:00:00     CPU       0/s       8/s      16/s     NMI/s     LOC/s     ERR/s|
00:00:01       0      0.00      0.00    403.23      0.00    806.45      0.00|
00:00:01       1      0.00      0.00    201.61      0.00    805.65      0.00|
|
00:00:00     CPU      HI/s   TIMER/s  NET_RX/s BLOCK_IOPOLL/s|
00:00:01       0      0.00    322.58     96.77      0.00|
00:00:01       1      0.00    241.94     80.65      0.00|
|
Average:     CPU    %usr   %nice    %sys %iowait    %irq   %soft  %steal  %guest   %idle|
Average:     all   40.00    1.00   15.00    2.50    2.50    1.50    2.50   10.00   25.00|
Average:       0   44.35    0.81   16.13    3.23    2.42    1.61    3.23   12.10   16.13|
Average:       1   32.89    1.32   13.16    1.32    2.63    1.32    1.32    6.58   39.47|
|
Average:     CPU    intr/s|
Average:     all  99561.29|
Average:       0    403.23|
Average:       1    328.95|
|
Average:     CPU       0/s       8/s      16/s     NMI/s     LOC/s     ERR/s|
Average:       0      0.00      0.00    403.23      0.00    806.45      0.00|
Average:       1      0.00      0.00    201.61      0.00    805.65      0.00|
|
Average:     CPU      HI/s   TIMER/s  NET_RX/s BLOCK_IOPOLL/s|
Average:       0      0.00    322.58     96.77      0.00|
Average:       1      0.00    241.94     80.65      0.00|
("" 0)
```

### -I SUM -P 1 since boot: processor 1's numbered interrupts over its own ticks

```cu
(body (fixture (list "mpstat" "-I" "SUM" "-P" "1")))
```
---
```output
|
00:00:00     CPU    intr/s|
00:00:00       1     42.52|
("" 0)
```

### a processor past the last, an -I that is not one, and a count with no interval are refused

```cu
(list (run (list "mpstat" "-P" "9999")) (let ((r (run (list "mpstat" "-I" "NOPE")))) (list (first (lines (first (rest r)))) (first (rest (rest r))))) (let ((r (run (list "mpstat" "0" "2")))) (first (rest (rest r)))))
```
---
    (("" "mpstat: not that many processors\n" 1) ("Usage: mpstat [-A] [-I SUM|CPU|ALL|SCPU] [-u] [-P num|ALL] [INTERVAL [COUNT]]" 1) 1)

### on this machine: the system line and the shares of all

```cu
(let ((r (run (list "mpstat")))) (def ls (lines (first r))) (list (first (rest (rest r))) (first (rest r)) (not (null? (re-search (re-compile "^[A-Za-z]+ [^ ]+ \\([^)]*\\)\t[0-9][0-9]/[0-9][0-9]/[0-9][0-9]\t_[^_]+_\t\\([0-9]+ CPU\\)$") (first ls)))) (not (null? (re-search (re-compile "^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]     all( +[0-9]+\\.[0-9][0-9]){9}$") (cu-nth 2 ls))))))
```
---
    (0 "" #t #t)

## nmeter

### a line over the fixture's second sample: each reading as busybox shows it

```cu
(do (sample "a") (def p (nm-parse "c[%c] C[%[c20]] n[%[neth0]] lo[%[nlo]] x[%[nnope]] m[%m] md[%[md]] mw[%[mw]] mf[%[mf]] mt[%[mt]] s[%s] f[%f] i[%i] i16[%16i] i9[%9i] x[%x] p[%p] pn[%[pn]] b[%b] 100%%")) (def primed (rest (nm-line (first p) (nm-sample)))) (sample "b") (def r (first (nm-line primed (nm-sample)))) (back) (list r (rest p)))
```
---
    ("c[SSUUUUU...] C[SSSUUUUUUUUUUDI.....] n[*976k  97k] lo[  100  100] x[??????????] m[338m] md[4.2m] mw[ 56k] mf[ 15g] mt[ 15g] s[1.0g] f[4096] i[120k] i16[ 750] i9[   0] x[ 44k] p[   7] pn[ 460] b[2.2m 512k] 100%" #f)

### on this machine: a line over two samples, a tenth of a second apart

```cu
(do (def p (nm-parse "%c|%m|%s|%f|%x|%[pn]|%b|%t")) (def primed (rest (nm-line (first p) (nm-sample)))) (sys-usleep 100000) (def l (first (nm-line primed (nm-sample)))) (list (byte-len l) (not (null? (re-search (re-compile "^[SUNDIi.?]{10}\\|[ 0-9.][0-9.kmgt ]{3}\\|[ 0-9.][0-9.kmgt ]{3}\\|[ 0-9.?][0-9.kmgt?]{3}\\|[ 0-9.?][0-9.kmgt?]{3}\\|[ 0-9.?][0-9.kmgt?]{3}\\|.... ....\\|[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$") l)))))
```
---
    (54 #t)

### %r ends the line in a carriage return; %t and %T are clocks to PREC places

```cu
(do (def p (nm-parse "a%rb %3t %T")) (list (length (first p)) (rest p) (first (first (first p))) (first (first (rest (first p))))))
```
---
    (2 #t "ab " " ")

### a format letter nmeter does not know, a [ left open, a % at the end and no format at all show the usage

```cu
(map (fn (_ f) (let ((r (run (list "nmeter" f)))) (list (first (lines (first (rest r)))) (first (rest (rest r)))))) (list "%q" "%[c" "x%" "%[n]"))
```
---
    (("Usage: nmeter [-d MSEC] FORMAT_STRING" 1) ("Usage: nmeter [-d MSEC] FORMAT_STRING" 1) ("Usage: nmeter [-d MSEC] FORMAT_STRING" 1) ("Usage: nmeter [-d MSEC] FORMAT_STRING" 1))

## the end

### the scratch directory goes

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-counters")) (display "gone"))
```
---
    gone
