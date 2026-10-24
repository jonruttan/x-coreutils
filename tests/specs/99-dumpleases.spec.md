# @weight 1

dumpleases as busybox's, TZ=UTC.  Each case writes the lease file SPEC
describes to /tmp/x-cu-dl/leases (none: no file) and runs dumpleases ARGS
there.  SPEC is a header then ;-separated leases.  The header: F a time
written in the future (2^40), which dumpleases takes as now, so the time left
is exactly a lease's own; P the past (1000000000); S a 4-byte header; Z
nothing.  A lease: REL,IP,MAC,HOST -- its expiry REL seconds after the
header's time, HOST with \NNN octal escapes, at most 19 bytes kept -- or T,
ten stray bytes.  Every expectation is busybox's own output for the same
case: stdout, the status, then stderr.

## the fixture

### a lease file, a dumpleases, and the report

```cu
(do
  (def dl-f (fn (_ n) (string-append "/tmp/x-cu-dl/" n)))
  (def dl-lines (fn (_ s)
    (let go ((i 0) (acc ()))
      (let ((nl (wget-index s #\newline i)))
        (if (null? nl) (reverse (if (< i (byte-len s)) (pair (substring s i (byte-len s)) acc) acc))
          (go (+ nl 1) (pair (substring s i nl) acc)))))))
  (def dl-sh (fn (_ script) (proc-run (list "/bin/sh" "-c" script))))
  (sys-setenv "TZ" "UTC")
  (def dl-be (fn (_ n k) (let go ((j 0) (n n) (acc ())) (if (= j k) acc (go (+ j 1) (wget-div n 256) (pair (% n 256) acc))))))
  ; HOST's bytes, \NNN read as an octal byte
  (def dl-host (fn (_ s)
    (let go ((i 0) (acc ()))
      (if (>= i (byte-len s)) (reverse acc)
        (if (if (= (byte-at s i) #\\) (<= (+ i 4) (byte-len s)) #f)
          (go (+ i 4) (pair (+ (* 64 (- (byte-at s (+ i 1)) #\0)) (* 8 (- (byte-at s (+ i 2)) #\0)) (- (byte-at s (+ i 3)) #\0)) acc))
          (go (+ i 1) (pair (byte-at s i) acc)))))))
  (def dl-lease (fn (_ r)
    (if (string=? r "T") (tn-str-bytes "abcdefghij")
      (let ((f (Str8 split "," r)))
        (let ((host (List take 19 (dl-host (if (> (length f) 3) (cu-nth 3 f) "")))))
          (append (dl-be (wget-digits (first f)) 4)
                  (map wget-digits (Str8 split "." (cu-nth 1 f)))
                  (map (fn (_ h) (first (nt-unhex h))) (Str8 split ":" (cu-nth 2 f)))
                  host (nt-zeros (- 22 (length host)))))))))
  (def dl-bytes (fn (_ spec)
    (let ((parts (Str8 split ";" spec)))
      (append (match ((string=? (first parts) "F") (dl-be 1099511627776 8))
                     ((string=? (first parts) "P") (dl-be 1000000000 8))
                     ((string=? (first parts) "S") (dl-be 1 4))
                     (#t ()))
              (List fold (fn (_ acc r) (if (string=? r "") acc (append acc (dl-lease r)))) () (rest parts))))))
  (def dl (fn (_ args spec)
    (cu-heap-collect)
    (sys-setenv "DL_ARGS" args)
    (dl-sh "d=/tmp/x-cu-dl; rm -rf $d; mkdir -p $d; eval \"set -- $DL_ARGS\"; for a; do printf '%s\\n' \"$a\"; done > $d/.argv")
    (unless (string=? spec "none")
      (let ((b (dl-bytes spec)) (fd (file-open-write (dl-f "leases"))))
        (do (File write fd (nt-raw b) (length b)) (file-close fd))))
    (def argv (dl-lines (file-read-all (dl-f ".argv"))))
    (def pid (sys-fork))
    (when (= pid 0)
      (do (Sys chdir "/tmp/x-cu-dl")
          (sys-dup2 (file-open-write (dl-f ".so")) 1) (sys-dup2 (file-open-write (dl-f ".se")) 2)
          (sys-exit (guard (e 99) (cu-run (pair "dumpleases" argv) "")))))
    (def st (sys-wait pid))
    (display (string-concat (list (file-read-all (dl-f ".so")) "[status " (cu-int->str st) "]\n" (file-read-all (dl-f ".se")))))))
  (display "made"))
```
---
    made

## busybox's dumpleases

### the remaining time of each lease, expired ones said

```cu
(dl "-f leases" "F;3661,192.168.1.10,00:11:22:33:44:55,laptop;90061,10.0.0.2,aa:bb:cc:dd:ee:ff,phone;0,10.0.0.3,01:02:03:04:05:06,gone;59,10.0.0.4,de:ad:be:ef:00:01,")
```
---
```output
Mac Address       IP Address      Host Name           Expires in
00:11:22:33:44:55 192.168.1.10    laptop              01:01:01
aa:bb:cc:dd:ee:ff 10.0.0.2        phone               1 days 01:01:01
01:02:03:04:05:06 10.0.0.3        gone                expired
de:ad:be:ef:00:01 10.0.0.4                            00:00:59
[status 0]
```

### -d: the remaining seconds

```cu
(dl "-f leases -d" "F;3661,192.168.1.10,00:11:22:33:44:55,laptop;90061,10.0.0.2,aa:bb:cc:dd:ee:ff,phone;0,10.0.0.3,01:02:03:04:05:06,gone;59,10.0.0.4,de:ad:be:ef:00:01,")
```
---
```output
Mac Address       IP Address      Host Name           Expires in
00:11:22:33:44:55 192.168.1.10    laptop              3661
aa:bb:cc:dd:ee:ff 10.0.0.2        phone               90061
01:02:03:04:05:06 10.0.0.3        gone                expired
de:ad:be:ef:00:01 10.0.0.4                            59
[status 0]
```

### -a: when each lease ends

```cu
(dl "-f leases -a" "P;2147483648,192.168.1.10,00:11:22:33:44:55,laptop;100,10.0.0.3,01:02:03:04:05:06,old")
```
---
```output
Mac Address       IP Address      Host Name           Expires at
00:11:22:33:44:55 192.168.1.10    laptop              Fri Sep 27 05:00:48 2069
01:02:03:04:05:06 10.0.0.3        old                 expired
[status 0]
```

### -a -d: the end in seconds

```cu
(dl "-f leases -a -d" "P;2147483648,192.168.1.10,00:11:22:33:44:55,laptop")
```
---
```output
Mac Address       IP Address      Host Name           Expires at
00:11:22:33:44:55 192.168.1.10    laptop              3147483648
[status 0]
```

### -r after -a: the remaining time

```cu
(dl "-f leases -a -r" "F;3661,192.168.1.10,00:11:22:33:44:55,laptop;90061,10.0.0.2,aa:bb:cc:dd:ee:ff,phone;0,10.0.0.3,01:02:03:04:05:06,gone;59,10.0.0.4,de:ad:be:ef:00:01,")
```
---
```output
[status 1]
Usage: dumpleases [-r|-a] [-d] [-f LEASEFILE]

Display DHCP leases granted by udhcpd

	-f FILE	Lease file
	-r	Show remaining time
	-a	Show expiration time
	-d	Show time in seconds
```

### -a after -r

```cu
(dl "-f leases -r -a" "P;2147483648,192.168.1.10,00:11:22:33:44:55,laptop")
```
---
```output
[status 1]
Usage: dumpleases [-r|-a] [-d] [-f LEASEFILE]

Display DHCP leases granted by udhcpd

	-f FILE	Lease file
	-r	Show remaining time
	-a	Show expiration time
	-d	Show time in seconds
```

### the long options

```cu
(dl "--file=leases --decimal --remaining" "F;3661,192.168.1.10,00:11:22:33:44:55,laptop;90061,10.0.0.2,aa:bb:cc:dd:ee:ff,phone;0,10.0.0.3,01:02:03:04:05:06,gone;59,10.0.0.4,de:ad:be:ef:00:01,")
```
---
```output
Mac Address       IP Address      Host Name           Expires in
00:11:22:33:44:55 192.168.1.10    laptop              3661
aa:bb:cc:dd:ee:ff 10.0.0.2        phone               90061
01:02:03:04:05:06 10.0.0.3        gone                expired
de:ad:be:ef:00:01 10.0.0.4                            59
[status 0]
```

### --absolute

```cu
(dl "--file leases --absolute" "P;2147483648,10.1.2.3,00:00:00:00:00:01,host")
```
---
```output
Mac Address       IP Address      Host Name           Expires at
00:00:00:00:00:01 10.1.2.3        host                Fri Sep 27 05:00:48 2069
[status 0]
```

### a nineteen-byte name, and a longer one cut

```cu
(dl "-f leases" "F;100,1.2.3.4,00:00:00:00:00:01,abcdefghijklmnopqrs;100,1.2.3.5,00:00:00:00:00:02,abcdefghijklmnopqrstuvwxyz")
```
---
```output
Mac Address       IP Address      Host Name           Expires in
00:00:00:00:00:01 1.2.3.4         abcdefghijklmnopqrs 00:01:40
00:00:00:00:00:02 1.2.3.5         abcdefghijklmnopqrs 00:01:40
[status 0]
```

### a name with a control byte and a high byte

```cu
(dl "-f leases" "F;100,1.2.3.4,00:00:00:00:00:01,a\\001b\\351c")
```
---
```output
Mac Address       IP Address      Host Name           Expires in
00:00:00:00:00:01 1.2.3.4         a?b?c               00:01:40
[status 0]
```

### an empty name

```cu
(dl "-f leases" "F;100,1.2.3.4,00:00:00:00:00:01,")
```
---
```output
Mac Address       IP Address      Host Name           Expires in
00:00:00:00:00:01 1.2.3.4                             00:01:40
[status 0]
```

### a stray partial record at the end

```cu
(dl "-f leases" "F;100,1.2.3.4,00:00:00:00:00:01,one;T")
```
---
```output
Mac Address       IP Address      Host Name           Expires in
00:00:00:00:00:01 1.2.3.4         one                 00:01:40
[status 0]
```

### a header and no leases

```cu
(dl "-f leases" "F")
```
---
```output
Mac Address       IP Address      Host Name           Expires in
[status 0]
```

### an empty file

```cu
(dl "-f leases" "Z")
```
---
```output
Mac Address       IP Address      Host Name           Expires in
[status 1]
dumpleases: short read
```

### a short header

```cu
(dl "-f leases" "S")
```
---
```output
Mac Address       IP Address      Host Name           Expires in
[status 1]
dumpleases: short read
```

### no such file

```cu
(dl "-f nofile" "none")
```
---
```output
[status 1]
dumpleases: can't open 'nofile': No such file or directory
```

### the default file

```cu
(dl "" "none")
```
---
```output
[status 1]
dumpleases: can't open '/var/lib/misc/udhcpd.leases': No such file or directory
```

### an operand

```cu
(dl "-f leases extra" "F")
```
---
```output
[status 1]
Usage: dumpleases [-r|-a] [-d] [-f LEASEFILE]

Display DHCP leases granted by udhcpd

	-f FILE	Lease file
	-r	Show remaining time
	-a	Show expiration time
	-d	Show time in seconds
```

### a large remaining time

```cu
(dl "-f leases" "F;4294967295,1.2.3.4,00:00:00:00:00:01,big")
```
---
```output
Mac Address       IP Address      Host Name           Expires in
00:00:00:00:00:01 1.2.3.4         big                 49710 days 06:28:15
[status 0]
```
