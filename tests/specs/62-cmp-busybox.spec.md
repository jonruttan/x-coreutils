# @weight 1

cmp as busybox's: `FILE1 [FILE2 [SKIP1 [SKIP2]]]`, FILE2 standard input when
it is not given.  The first difference is `differ: byte N, line L`; -l lists
each as its offset and the two bytes in octal, three wide; -n and the skips
take the suffixes k, M and G (1024, 1024², 1024³, with the forms busybox also
reads: K, kiB, KiB, m, miB, MiB, g, giB, GiB).  A count that is not a number,
no operand, or more than four, is refused with 1; an option cmp does not take
is refused with 1 too.

The first cases are busybox's testsuite/cmp.tests: standard input holds `bar`
and the file `input` holds `foo`.

## the fixtures

### the file, and a run of an applet with its standard input, stdout, stderr and status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-cmpbb && mkdir -p /tmp/x-cu-cmpbb && printf foo > /tmp/x-cu-cmpbb/input")) (def nf (fn (_ n) (string-append "/tmp/x-cu-cmpbb/" n))) (def run (fn (_ argv in) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv in)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (Str8 replace "/tmp/x-cu-cmpbb/" "" (string-concat (list (file-read-all (nf ".out")) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n"))))))))) (display "made"))
```
---
    made

## busybox's tests

### cmp -s, cmp, and -n with and without a suffix

```cu
(do (run (list "cmp" "-s" "-" (nf "input")) "bar") (run (list "cmp" "-" (nf "input")) "bar") (run (list "cmp" "-n2" "-" (nf "input")) "bar") (run (list "cmp" "-n2k" "-" (nf "input")) "bar") (run (list "cmp" "-n" "1g" "-" (nf "input")) "bar"))
```
---
```output
stderr:
status 1
- input differ: byte 1, line 1
stderr:
status 1
- input differ: byte 1, line 1
stderr:
status 1
- input differ: byte 1, line 1
stderr:
status 1
- input differ: byte 1, line 1
stderr:
status 1
```

### -l with a count, with a count in megabytes, and past a byte of each

```cu
(do (run (list "cmp" "-ln2" "-" (nf "input")) "bar") (run (list "cmp" "-ln2M" "-" (nf "input")) "bar") (run (list "cmp" "-ln2" "-" (nf "input") "1" "1") "bar"))
```
---
```output
1 142 146
2 141 157
stderr:
status 1
1 142 146
2 141 157
3 162 157
stderr:
status 1
1 141 157
2 162 157
stderr:
status 1
```

## operands

### one file is compared with standard input, and standard input with itself is the same

```cu
(do (run (list "cmp" (nf "input")) "bar") (run (list "cmp" (nf "input")) "foo") (run (list "cmp" "-" "-") "bar"))
```
---
```output
input - differ: byte 1, line 1
stderr:
status 1
stderr:
status 0
stderr:
status 0
```

### the skips pass bytes in each file, and the offsets count from there

Past one byte of `foo` and none of `oo`, the files match.

```cu
(do (proc-run (list "/bin/sh" "-c" "printf oo > /tmp/x-cu-cmpbb/oo")) (run (list "cmp" (nf "input") (nf "oo") "1") "") (run (list "cmp" (nf "input") (nf "oo") "1" "1") "") (run (list "cmp" (nf "input") (nf "oo") "1k") ""))
```
---
```output
stderr:
status 0
stderr:
cmp: EOF on oo
status 1
stderr:
cmp: EOF on input
status 1
```

## refusals

### a count that is not a number, and an option cmp does not take

```cu
(do (run (list "cmp" "-n" "2x" "-" (nf "input")) "bar") (run (list "cmp" (nf "input") (nf "oo") "k") "") (run (list "cmp" "-Q" (nf "input")) "bar"))
```
---
```output
stderr:
cmp: invalid number '2x'
status 1
stderr:
cmp: invalid number 'k'
status 1
stderr:
cmp: unrecognized option: Q
Usage: cmp [-l|s] [-n NUM] FILE1 [FILE2 [SKIP1 [SKIP2]]]

Compare FILE1 with FILE2 (or stdin)

	-l	Show decimal offset and octal byte value for differing bytes,
		don't stop on first mismatch
	-s	Quiet
	-n NUM	Compare at most NUM bytes
status 1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-cmpbb")) (display "clean"))
```
---
    clean
