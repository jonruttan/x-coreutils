# @weight 1

An option an applet does not take is refused in GNU's words, before the
applet runs.  A long option is `unrecognized option '--NAME'`.  In a short
cluster, read left to right as getopt reads one, the first letter the applet
does not declare is `invalid option -- 'C'`.  A value option with nothing
after it `requires an argument`.  The status is GNU's for the applet: 125 for
env, which runs a command; 2 for sort and ls; 1 for the rest.  The expected
text is GNU's, less the line GNU adds after a refusal to point at --help,
which no applet here has.

## the fixtures

### a runner for stdout, stderr and the status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-io && mkdir -p /tmp/x-cu-io")) (def nf (fn (_ n) (string-append "/tmp/x-cu-io/" n))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (file-read-all (nf ".out")) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n")))))))) (display "made"))
```
---
    made

## invalid option

### a letter alone, and the first undeclared letter of a cluster

cat takes -v, so `-vQ` is refused at the Q; sort does not, so `-vQ` is
refused at the v.

```cu
(do (run (list "cat" "-Q")) (run (list "cat" "-vQ")) (run (list "head" "-qZ")) (run (list "sort" "-vQ")))
```
---
```output
stderr:
cat: invalid option -- 'Q'
status 1
stderr:
cat: invalid option -- 'Q'
status 1
stderr:
head: invalid option -- 'Z'
status 1
stderr:
sort: invalid option -- 'v'
status 2
```

### the status is GNU's for the applet

```cu
(do (run (list "env" "-Q")) (run (list "ls" "-y")))
```
---
```output
stderr:
env: invalid option -- 'Q'
status 125
stderr:
ls: invalid option -- 'y'
status 2
```

## unrecognized option

### a long option, after a cluster the applet takes

```cu
(do (run (list "cat" "--nope")) (run (list "sort" "-rn" "--nope")))
```
---
```output
stderr:
cat: unrecognized option '--nope'
status 1
stderr:
sort: unrecognized option '--nope'
status 2
```

## option requires an argument

### a value option last on the line, alone, in a cluster, and long

```cu
(do (run (list "head" "-n")) (run (list "head" "-qn")) (run (list "cut" "-b")) (run (list "nproc" "--ignore")))
```
---
```output
stderr:
head: option requires an argument -- 'n'
status 1
stderr:
head: option requires an argument -- 'n'
status 1
stderr:
cut: option requires an argument -- 'b'
status 1
stderr:
nproc: option '--ignore' requires an argument
status 1
```

### an applet that reads its own line

nc parses its options itself and refuses through its declaration, where its
value options are hidden rows.

```cu
(do (run (list "nc" "-p")) (run (list "nc" "-w")))
```
---
```output
stderr:
nc: option requires an argument -- 'p'
status 1
stderr:
nc: option requires an argument -- 'w'
status 1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-io")) (display "clean"))
```
---
    clean
