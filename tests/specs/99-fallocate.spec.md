# @weight 1

busybox's fallocate (util-linux/fallocate.c): -l LEN and one FILE, -o
OFS, both read by xatoull_sfx with kmg_i_suffixes.  The space is set
aside by posix_fallocate on Linux, where the Linux leg compares it with
busybox's own, and by F_PREALLOCATE on Darwin; on both the file is then
at least OFS+LEN long.

## the fixture

### a run of an applet, what it writes and its status, and a file's size

```cu
(do (def fa-f (fn (_ n) (string-append "/tmp/x-cu-fa." n)))
    (def fa-show (fn (_ argv)
      (do (sys-dup2 1 9) (sys-dup2 2 8)
          (let ((oo (file-open-write (fa-f "out"))) (ee (file-open-write (fa-f "err"))))
            (do (sys-dup2 oo 1) (sys-dup2 ee 2)
                (def st (cu-run argv ""))
                (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee)
                (display (%str-concat (list (file-read-all (fa-f "out")) "stderr:\n"
                                              (file-read-all (fa-f "err")) "status " (cu-int->str st) "\n")))
                ())))))
    (def fa-size (fn (_ n) (display (%str-concat (list n " " (cu-int->str (Assoc get (lit size) (file-stat (fa-f n)))) "\n")))))
    (def fa-fresh (fn (_ n) (when (file-exists? (fa-f n)) (file-unlink (fa-f n)))))
    (display "made"))
```
---
    made

## the line

### no -l, no FILE, or two: the usage

```cu
(do (fa-show (list "fallocate" "f"))
    (fa-show (list "fallocate" "-l" "1"))
    (fa-show (list "fallocate" "-l" "1" "a" "b")))
```
---
```output
stderr:
Usage: fallocate [-o OFS] -l LEN FILE

Preallocate space for FILE

	-o OFS	Offset of range
	-l LEN	Length of range
status 1
stderr:
Usage: fallocate [-o OFS] -l LEN FILE

Preallocate space for FILE

	-o OFS	Offset of range
	-l LEN	Length of range
status 1
stderr:
Usage: fallocate [-o OFS] -l LEN FILE

Preallocate space for FILE

	-o OFS	Offset of range
	-l LEN	Length of range
status 1
```

## the space

### a new FILE is made LEN long

```cu
(do (fa-fresh "a")
    (fa-show (list "fallocate" "-l" "100" (fa-f "a")))
    (fa-size "a"))
```
---
```output
stderr:
status 0
a 100
```

### -o OFS: the file runs to OFS+LEN, its bytes before OFS kept

```cu
(do (fa-fresh "b")
    (file-write-all (fa-f "b") "abc")
    (fa-show (list "fallocate" "-o" "10" "-l" "5" (fa-f "b")))
    (fa-size "b")
    (display (%str-concat (list (substring (file-read-all (fa-f "b")) 0 3) "\n"))))
```
---
```output
stderr:
status 0
b 15
abc
```

### a range inside the file leaves its length alone

```cu
(do (fa-fresh "c")
    (file-write-all (fa-f "c") "0123456789")
    (fa-show (list "fallocate" "-o" "2" "-l" "3" (fa-f "c")))
    (fa-size "c"))
```
---
```output
stderr:
status 0
c 10
```

### the suffixes are 1024's powers, KiB kiB K k and the M and G forms

```cu
(do (fa-fresh "d")
    (fa-show (list "fallocate" "-l" "2k" (fa-f "d")))
    (fa-size "d")
    (fa-show (list "fallocate" "-o" "1KiB" "-l" "1kiB" (fa-f "d")))
    (fa-size "d")
    (fa-show (list "fallocate" "-l" "1M" (fa-f "d")))
    (fa-size "d")
    (fa-show (list "fallocate" "-l" "1kB" (fa-f "d"))))
```
---
```output
stderr:
status 0
d 2048
stderr:
status 0
d 2048
stderr:
status 0
d 1048576
stderr:
fallocate: invalid number '1kB'
status 1
```

## the refusals

### a word that is no number: a sign, a space, no digits, too many

```cu
(do (fa-fresh "e")
    (fa-show (list "fallocate" "-l" "+1" (fa-f "e")))
    (fa-show (list "fallocate" "-l" " 1" (fa-f "e")))
    (fa-show (list "fallocate" "-l" "k" (fa-f "e")))
    (fa-show (list "fallocate" "-o" "x" "-l" "1" (fa-f "e")))
    (fa-show (list "fallocate" "-l" "18446744073709551616" (fa-f "e")))
    (display (if (file-exists? (fa-f "e")) "made\n" "none\n")))
```
---
```output
stderr:
fallocate: invalid number '+1'
status 1
stderr:
fallocate: invalid number ' 1'
status 1
stderr:
fallocate: invalid number 'k'
status 1
stderr:
fallocate: invalid number 'x'
status 1
stderr:
fallocate: invalid number '18446744073709551616'
status 1
none
```

### a suffix that carries the count past 2^64-1: out of range

```cu
(fa-show (list "fallocate" "-l" "18014398509481984k" (fa-f "e")))
```
---
```output
stderr:
fallocate: number 18014398509481984k is not in 0..18446744073709551615 range
status 1
```

### a zero LEN, or one past off_t, is the call's EINVAL

```cu
(do (fa-fresh "e")
    (fa-show (list "fallocate" "-l" "0" (fa-f "e")))
    (fa-show (list "fallocate" "-l" "9223372036854775808" (fa-f "e")))
    (fa-size "e"))
```
---
```output
stderr:
fallocate: fallocate '/tmp/x-cu-fa.e': Invalid argument
status 1
stderr:
fallocate: fallocate '/tmp/x-cu-fa.e': Invalid argument
status 1
e 0
```

### a FILE that cannot be opened

```cu
(fa-show (list "fallocate" "-l" "1" "/tmp"))
```
---
```output
stderr:
fallocate: can't open '/tmp': Is a directory
status 1
```

## the clean-up

```cu
(do (map (fn (_ n) (fa-fresh n)) (list "a" "b" "c" "d" "e" "out" "err"))
    (display "gone"))
```
---
    gone
