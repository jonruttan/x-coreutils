# @weight 1

busybox's getopt (util-linux/getopt.c) and run-parts
(debianutils/run_parts.c).  Every expectation is busybox's own output, from a
busybox built from its source and linked with musl, whose getopt_long getopt
is, less the banner line its usage text starts with.  A `|` marks the end of
each line written to standard output.  The cases run in the fixtures'
directory, as busybox's did, so run-parts' names are relative.

## the fixtures

### the scripts, a run of an applet with its standard input, stdout, stderr and status, and the fixtures' directory as the current one

`rp` holds scripts that print and exit 0 or 3, a link to one, a name with a
character run-parts refuses, a dot file, one not executable, one whose
interpreter is not there, and a directory.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-gp && mkdir -p /tmp/x-cu-gp/rp/60-dir && cd /tmp/x-cu-gp/rp && printf '#!/bin/sh\\necho one \"$@\"\\n' > 10-one && printf '#!/bin/sh\\necho two; exit 3\\n' > 20-two && printf '#!/bin/sh\\necho skip\\n' > 30.bad~ && printf '#!/bin/sh\\necho hidden\\n' > .hid && printf 'echo noexec\\n' > 40-noexec && printf '#!/nonexistent/sh\\n' > 50-plain && printf '#!/bin/sh\\necho four\\n' > 05-four && chmod +x 10-one 20-two 30.bad~ .hid 50-plain 05-four && ln -s 05-four 07-link")) (def nf (fn (_ n) (string-append "/tmp/x-cu-gp/" n))) (def shown (fn (_ mode) (if (string=? mode "x") (do (proc-run (list "/bin/sh" "-c" "od -An -v -tx1 /tmp/x-cu-gp/.out | tr -d ' \\n' | fold -w 64 > /tmp/x-cu-gp/.hex; [ -s /tmp/x-cu-gp/.hex ] && echo >> /tmp/x-cu-gp/.hex")) (file-read-all (nf ".hex"))) (Str8 replace "\n" "|\n" (Str8 replace "/tmp/x-cu-gp/" "" (file-read-all (nf ".out"))))))) (def run (fn (_ mode argv in) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (nf ".out"))) (ee (file-open-write (nf ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run argv in)) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (display (string-concat (list (shown mode) "stderr:\n" (Str8 replace "/tmp/x-cu-gp/" "" (file-read-all (nf ".err"))) "status " (%cu-int->str st) "\n")))))))) (def home (Sys getcwd)) (Sys chdir "/tmp/x-cu-gp") (display "made"))
```
---
    made

## getopt

### the old form: OPTSTRING first, the output unquoted

```cu
(run "-" (list "getopt" "ab:c::" "-a" "-b" "x" "-cy" "file1" "--" "-z") "")
```
---
```output
 -a -b x -c y -- file1 -z|
stderr:
status 0
```

### -o's options and their arguments, each quoted; operands after the options; :: an argument only when attached

```cu
(do (run "-" (list "getopt" "-o" "ab:c::" "--" "-a" "file" "-b" "x" "-c" "-cz" "more") "") (run "-" (list "getopt" "-o" "ab" "--" "-ba") "") (run "-" (list "getopt" "-o" "a" "--" "-" "x" "-") "") (run "-" (list "getopt" "-o" "a") ""))
```
---
```output
 -a -b 'x' -c '' -c 'z' -- 'file' 'more'|
stderr:
status 0
 -b -a --|
stderr:
status 0
 -- '-' 'x' '-'|
stderr:
status 0
 --|
stderr:
status 0
```

### a + first stops at the first operand; a - first puts each in its place

```cu
(do (run "-" (list "getopt" "-o" "+ab" "--" "-a" "file" "-b") "") (run "-" (list "getopt" "-o" "-ab" "--" "-a" "file" "-b" "f2") ""))
```
---
```output
 -a -- 'file' '-b'|
stderr:
status 0
 -a 'file' -b 'f2' --|
stderr:
status 0
```

### -l's long options, by any unique prefix, = or the next word their argument; -a takes them after one dash

```cu
(do (run "-" (list "getopt" "-o" "ab" "-l" "alpha,beta:,gamma::" "--" "--alpha" "--beta=1" "--beta" "2" "--gam" "--gamma=3" "--al" "x") "") (run "-" (list "getopt" "-a" "-o" "x" "-l" "long" "--" "-long" "-x" "-lo") ""))
```
---
```output
 --alpha --beta '1' --beta '2' --gamma '' --gamma '3' --alpha -- 'x'|
stderr:
status 0
 --long -x --long --|
stderr:
status 0
```

### what getopt will not take is said in musl's words, the rest still put out, and the status is 1

```cu
(do (run "-" (list "getopt" "-o" "a" "-l" "alpha,alps" "--" "--al") "") (run "-" (list "getopt" "-o" "a" "-l" "alpha" "--" "--alpha=x" "--zeta" "-q" "-b") "") (run "-" (list "getopt" "-o" "a" "-l" "beta:" "--" "--beta") "") (run "-" (list "getopt" "-n" "myprog" "-o" "a" "--" "-x") "") (run "-" (list "getopt" "-q" "-o" "a" "--" "-x" "y") ""))
```
---
```output
 --|
stderr:
getopt: option is ambiguous: al
status 1
 --|
stderr:
getopt: option does not take an argument: alpha
getopt: unrecognized option: zeta
getopt: unrecognized option: q
getopt: unrecognized option: b
status 1
 --|
stderr:
getopt: option requires an argument: beta
status 1
 --|
stderr:
myprog: unrecognized option: x
status 1
 -- 'y'|
stderr:
status 1
```

### -Q puts nothing out, -u no quotes; -s tcsh quotes for tcsh, and a shell it does not know is bash

```cu
(do (run "-" (list "getopt" "-Q" "-o" "a" "--" "-a" "y") "") (run "-" (list "getopt" "-u" "-o" "a:" "--" "-a" "it's x" "y z") "") (run "-" (list "getopt" "-o" "a:" "--" "-a" "it's x" "y z") "") (run "-" (list "getopt" "-s" "tcsh" "-o" "a:" "--" "-a" "a b!c") "") (run "-" (list "getopt" "-s" "zsh" "-o" "a" "--" "-a") ""))
```
---
```output
stderr:
status 0
 -a it's x -- y z|
stderr:
status 0
 -a 'it'\''s x' -- 'y z'|
stderr:
status 0
 -a 'a'\ 'b'\!'c' --|
stderr:
status 0
 -a --|
stderr:
getopt: unknown shell 'zsh', assuming bash
status 0
```

### -T is 4; no OPTSTRING, or an empty long option, is refused

```cu
(do (run "-" (list "getopt" "-T") "") (run "-" (list "getopt") "") (run "-" (list "getopt" "-l" ":" "-o" "a" "--" "-a") ""))
```
---
```output
stderr:
status 4
stderr:
getopt: missing optstring argument
status 1
stderr:
getopt: empty long option specified
status 1
```

## run-parts

### the executable files in byte order of name, a link as what it points to; one that ends with a status is said, so is one that will not run

```cu
(do (run "-" (list "run-parts" "rp") "") (run "-" (list "run-parts" "-a" "x" "rp/") ""))
```
---
```output
four|
four|
one|
two|
stderr:
run-parts: rp/20-two: exit status 3
run-parts: can't execute 'rp/50-plain': No such file or directory
status 1
four|
four|
one x|
two|
stderr:
run-parts: rp/20-two: exit status 3
run-parts: can't execute 'rp/50-plain': No such file or directory
status 1
```

### --test prints what would run, --list what matches whether it may run or not, --reverse the other way

```cu
(do (run "-" (list "run-parts" "--test" "rp") "") (run "-" (list "run-parts" "--list" "rp") "") (run "-" (list "run-parts" "--reverse" "--test" "rp") "") (run "-" (list "run-parts" "-a" "x" "-a" "y z" "--test" "rp") ""))
```
---
```output
rp/05-four|
rp/07-link|
rp/10-one|
rp/20-two|
rp/50-plain|
stderr:
status 0
rp/05-four|
rp/07-link|
rp/10-one|
rp/20-two|
rp/40-noexec|
rp/50-plain|
stderr:
status 0
rp/50-plain|
rp/20-two|
rp/10-one|
rp/07-link|
rp/05-four|
stderr:
status 0
rp/05-four|
rp/07-link|
rp/10-one|
rp/20-two|
rp/50-plain|
stderr:
status 0
```

### --exit-on-error stops at the first failure; -u is an octal umask

```cu
(do (run "-" (list "run-parts" "--exit-on-error" "rp") "") (run "-" (list "run-parts" "-u" "077" "--test" "rp") "") (run "-" (list "run-parts" "-u" "9" "rp") ""))
```
---
```output
four|
four|
one|
two|
stderr:
run-parts: rp/20-two: exit status 3
status 1
rp/05-four|
rp/07-link|
rp/10-one|
rp/20-two|
rp/50-plain|
stderr:
status 0
stderr:
run-parts: invalid number '9'
status 1
```

### a directory that will not open is said and is not a failure; a file has nothing under it; one directory only

```cu
(do (run "-" (list "run-parts" "nope") "") (run "-" (list "run-parts" "rp/10-one") "") (run "-" (list "run-parts") "") (run "-" (list "run-parts" "rp" "rp") ""))
```
---
```output
stderr:
run-parts: nope: No such file or directory
status 0
stderr:
status 0
stderr:
Usage: run-parts [-a ARG]... [-u UMASK] [--reverse] [--test] [--exit-on-error] [--list] DIRECTORY

Run a bunch of scripts in DIRECTORY

	-a ARG		Pass ARG as argument to scripts
	-u UMASK	Set UMASK before running scripts
	--reverse	Reverse execution order
	--test		Dry run
	--exit-on-error	Exit if a script exits with non-zero
	--list		Print names of matching files even if they are not executable
status 1
stderr:
Usage: run-parts [-a ARG]... [-u UMASK] [--reverse] [--test] [--exit-on-error] [--list] DIRECTORY

Run a bunch of scripts in DIRECTORY

	-a ARG		Pass ARG as argument to scripts
	-u UMASK	Set UMASK before running scripts
	--reverse	Reverse execution order
	--test		Dry run
	--exit-on-error	Exit if a script exits with non-zero
	--list		Print names of matching files even if they are not executable
status 1
```

### back to where the run started

```cu
(do (Sys chdir home) (display "back"))
```
---
    back
