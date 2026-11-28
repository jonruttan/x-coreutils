# @weight 1

busybox's fstrim (util-linux/fstrim.c): one MOUNTPOINT, -o -l -m read by
xatoull_sfx with kmg_i_suffixes, -v, and getopt_long's names for each.
Darwin has no FITRIM, so here the call is ENOTTY; what the kernel
discards is compared with busybox's own in the Linux leg.

## the fixture

### a run of an applet, what it writes and its status

```cu
(do (def ft-f (fn (_ n) (string-append "/tmp/x-cu-ft." n)))
    (def ft-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (ft-f "out"))) (ee (file-open-write (ft-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (ft-f "out")) "stderr:\n"
                                              (file-read-all (ft-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (display "made"))
```
---
    made

## the line

### no MOUNTPOINT, or two: the usage

```cu
(do (ft-show (list "fstrim"))
    (ft-show (list "fstrim" "/" "/tmp")))
```
---
```output
stderr:
Usage: fstrim [OPTIONS] MOUNTPOINT

	-o OFFSET	Offset in bytes to discard from
	-l LEN		Bytes to discard
	-m MIN		Minimum extent length
	-v		Print number of discarded bytes
status 1
stderr:
Usage: fstrim [OPTIONS] MOUNTPOINT

	-o OFFSET	Offset in bytes to discard from
	-l LEN		Bytes to discard
	-m MIN		Minimum extent length
	-v		Print number of discarded bytes
status 1
```

### options after MOUNTPOINT are read, as getopt_long permutes; a -- ends them

```cu
(do (ft-show (list "fstrim" "/tmp" "-v"))
    (ft-show (list "fstrim" "/tmp" "--" "-v")))
```
---
```output
stderr:
fstrim: FITRIM: Inappropriate ioctl for device
status 1
stderr:
Usage: fstrim [OPTIONS] MOUNTPOINT

	-o OFFSET	Offset in bytes to discard from
	-l LEN		Bytes to discard
	-m MIN		Minimum extent length
	-v		Print number of discarded bytes
status 1
```

## the numbers

### each of -o -l -m and their long names is read before MOUNTPOINT is opened

```cu
(do (ft-show (list "fstrim" "-o" "x" "/nonexistent"))
    (ft-show (list "fstrim" "-l" "+1" "/nonexistent"))
    (ft-show (list "fstrim" "-m" "1kB" "/nonexistent"))
    (ft-show (list "fstrim" "--offset" " 1" "/nonexistent"))
    (ft-show (list "fstrim" "--length=k" "/nonexistent"))
    (ft-show (list "fstrim" "--min" "18446744073709551616" "/nonexistent"))
    (ft-show (list "fstrim" "-l" "18014398509481984k" "/nonexistent")))
```
---
```output
stderr:
fstrim: invalid number 'x'
status 1
stderr:
fstrim: invalid number '+1'
status 1
stderr:
fstrim: invalid number '1kB'
status 1
stderr:
fstrim: invalid number ' 1'
status 1
stderr:
fstrim: invalid number 'k'
status 1
stderr:
fstrim: invalid number '18446744073709551616'
status 1
stderr:
fstrim: number 18014398509481984k is not in 0..18446744073709551615 range
status 1
```

## the call

### a MOUNTPOINT that cannot be opened

```cu
(ft-show (list "fstrim" "-v" "/nonexistent"))
```
---
```output
stderr:
fstrim: can't open '/nonexistent': No such file or directory
status 1
```

### Darwin has no FITRIM: ENOTTY, and -v prints nothing

```cu
(do (ft-show (list "fstrim" "-v" "-o" "1M" "-l" "18446744073709551615" "-m" "4k" "/tmp"))
    (ft-show (list "fstrim" "--verb" "/tmp")))
```
---
```output
stderr:
fstrim: FITRIM: Inappropriate ioctl for device
status 1
stderr:
fstrim: FITRIM: Inappropriate ioctl for device
status 1
```

## the clean-up

```cu
(do (map (fn (_ n) (when (file-exists? (ft-f n)) (file-unlink (ft-f n)))) (list "out" "err"))
    (display "gone"))
```
---
    gone
