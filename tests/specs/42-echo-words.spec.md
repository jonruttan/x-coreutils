# @weight 1

echo's options are a leading run of words, each a `-` and one or more of the
letters n, e and E.  The first word that is anything else -- `--`, a lone `-`,
`-x`, `-nx` -- is text, and so is every word after it; echo refuses nothing.
Of -e and -E, the one given last wins.  The expected text is GNU's.

## the fixtures

### a runner for stdout, stderr and the status

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-ew && mkdir -p /tmp/x-cu-ew")) (def nf (fn (_ n) (string-append "/tmp/x-cu-ew/" n))) (def run (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (file-read-all (nf ".out")) "stderr:\n" (file-read-all (nf ".err")) "status " (%cu-int->str st) "\n")))))))) (display "made"))
```
---
    made

## the options

### a word that is not a cluster of n, e and E is text

```cu
(do (run (list "echo" "-x")) (run (list "echo" "-nx" "a")) (run (list "echo" "--n" "a")) (run (list "echo" "-")))
```
---
```output
-x
stderr:
status 0
-nx a
stderr:
status 0
--n a
stderr:
status 0
-
stderr:
status 0
```

### and so is --

```cu
(do (run (list "echo" "--" "a")) (run (list "echo" "-n" "--" "a")) (run (list "echo" "-en" "--" "a")))
```
---
```output
-- a
stderr:
status 0
-- astderr:
status 0
-- astderr:
status 0
```

### an empty word is text, and no word at all is an empty line

```cu
(do (run (list "echo" "")) (run (list "echo" "-n" "")) (run (list "echo")))
```
---
```output

stderr:
status 0
stderr:
status 0

stderr:
status 0
```

### the options end at the first word that is not one

```cu
(do (run (list "echo" "-n" "-x" "a")) (run (list "echo" "-x" "-n" "a")) (run (list "echo" "-ne" "-x")) (run (list "echo" "a" "-n")))
```
---
```output
-x astderr:
status 0
-x -n a
stderr:
status 0
-xstderr:
status 0
a -n
stderr:
status 0
```

## -e and -E

### the one given last wins

```cu
(do (run (list "echo" "-e" "-E" "a\\tb")) (run (list "echo" "-E" "-e" "a\\tb")))
```
---
```output
a\tb
stderr:
status 0
a	b
stderr:
status 0
```

### in a cluster as well

```cu
(do (run (list "echo" "-eE" "a\\tb")) (run (list "echo" "-Ee" "a\\tb")) (run (list "echo" "-neEn" "a\\tb")))
```
---
```output
a\tb
stderr:
status 0
a	b
stderr:
status 0
a\tbstderr:
status 0
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-ew")) (display "clean"))
```
---
    clean
