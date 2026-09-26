# @weight 4

Option parity with busybox, tranche by tranche.  docs/options.md is the
generated scoreboard; each section here is one applet's busybox option
set, spec'd on what is deterministic -- names, order, shapes -- and
never on a clock or an inode.

## the process and file tools

### fixtures

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-pf && mkdir -p /tmp/x-cu-pf && printf 'hello world' > /tmp/x-cu-pf/there && printf secret > /tmp/x-cu-pf/ro && chmod 444 /tmp/x-cu-pf/ro")) (display "made"))
```
---
    made

### truncate -c passes over a file that is not there, and does not make one

```cu
(do (display (cu-run (list "truncate" "-c" "-s" "10" "/tmp/x-cu-pf/absent") "")) (display (if (file-exists? "/tmp/x-cu-pf/absent") "created" "absent")) (newline) (cu-run (list "truncate" "-c" "-s" "5" "/tmp/x-cu-pf/there") "") (display (cu-run (list "stat" "-c" "%s" "/tmp/x-cu-pf/there") "")))
```
---
```output
0absent
5
0
```

### without -c the file is created

```cu
(do (cu-run (list "truncate" "-s" "7" "/tmp/x-cu-pf/made") "") (display (cu-run (list "stat" "-c" "%s" "/tmp/x-cu-pf/made") "")))
```
---
```output
7
0
```

### shred -f writes through a mode that denies it

```cu
(do (display (cu-run (list "shred" "-n" "1" "-f" "/tmp/x-cu-pf/ro") "")) (display (if (string=? (file-read-all "/tmp/x-cu-pf/ro") "secret") "intact" "overwritten")))
```
---
    0overwritten

### timeout -k follows an ignored signal with KILL

`sh` traps TERM and outlives it, so only the KILL ends the command --
128+9, the status a KILLed child reports, rather than the 124 a command
that took the first signal would give.

```cu
(display (cu-run (list "timeout" "-k" "1" "1" "/bin/sh" "-c" "trap '' TERM; sleep 10") ""))
```
---
    137

### a command that ignores the signal and exits on its own still timed out

```cu
(display (cu-run (list "timeout" "1" "/bin/sh" "-c" "trap '' TERM; sleep 3") ""))
```
---
    124

### KILL as the primary signal keeps its own status

```cu
(display (cu-run (list "timeout" "-s" "9" "1" "/bin/sleep" "5") ""))
```
---
    137

### tty -s answers with the status alone

```cu
(do (display (cu-run (list "tty" "-s") "")) (display (cu-run (list "tty") "")))
```
---
```output
1not a tty
1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-pf")) (display "clean"))
```
---
    clean

## the text shapers

`tee -i` is declared and not run here: it sets the interrupt disposition
of the process it runs in, and cu-run runs the applet in the harness's own.

### fixtures

Output is captured and its control bytes spelled the way `cat -A` spells
them, so a tab, a backspace and a carriage return can be read.

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-tx && mkdir -p /tmp/x-cu-tx")) (def cu-cap (fn (_ argv) (do (sys-dup2 1 9) (let ((fd (file-open-write "/tmp/x-cu-tx/.cap"))) (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1) (file-close fd) (Str8 replace (list->string (list (integer->char 13))) "^M" (Str8 replace (list->string (list (integer->char 8))) "^H" (Str8 replace "\t" "^I" (file-read-all "/tmp/x-cu-tx/.cap"))))))))) (file-write-all "/tmp/x-cu-tx/tab" "ab\tcdefghijkl\n") (file-write-all "/tmp/x-cu-tx/words" "the quick brown fox jumps\nabcdefghijklmnop\nab cd ef gh ij kl mn\n") (file-write-all "/tmp/x-cu-tx/ctl" (string-append "abc" (list->string (list (integer->char 8))) "defgh\nabcd" (list->string (list (integer->char 13))) "efghij\n")) (file-write-all "/tmp/x-cu-tx/lead" "\t\ta\tb\n  \tc\td\n") (file-write-all "/tmp/x-cu-tx/runs" "        a        b\n    \t  c\n  x\n") (file-write-all "/tmp/x-cu-tx/stops" "abcdefg h\nabcdef  h\na        \n") (display "made"))
```
---
    made

### fold counts columns, so a tab reaches the next stop; -b counts bytes

```cu
(do (display (cu-cap (list "fold" "-w" "12" "/tmp/x-cu-tx/tab"))) (display (cu-cap (list "fold" "-b" "-w" "12" "/tmp/x-cu-tx/tab"))))
```
---
```output
ab^Icdef
ghijkl
ab^Icdefghijk
l
```

### fold -s breaks after the last space, keeping it

```cu
(display (cu-cap (list "fold" "-s" "-w" "10" "/tmp/x-cu-tx/words")))
```
---
```output
the quick 
brown fox 
jumps
abcdefghij
klmnop
ab cd ef 
gh ij kl 
mn
```

### a backspace gives a column back and a carriage return the whole line

```cu
(display (cu-cap (list "fold" "-w" "5" "/tmp/x-cu-tx/ctl")))
```
---
```output
abc^Hdef
gh
abcd^Mefghi
j
```

### expand -i expands only the leading tabs

```cu
(do (display (cu-cap (list "expand" "/tmp/x-cu-tx/lead"))) (display (cu-cap (list "expand" "-i" "/tmp/x-cu-tx/lead"))))
```
---
```output
                a       b
        c       d
                a^Ib
        c^Id
```

### unexpand respells the leading run, tabs included; -f says so; -a takes every run

```cu
(do (display (cu-cap (list "unexpand" "/tmp/x-cu-tx/runs"))) (display (cu-cap (list "unexpand" "-f" "/tmp/x-cu-tx/runs"))) (display (cu-cap (list "unexpand" "-a" "/tmp/x-cu-tx/runs"))))
```
---
```output
^Ia        b
^I  c
  x
^Ia        b
^I  c
  x
^Ia^I b
^I  c
  x
```

### -f keeps unexpand to the leading run whatever order -a comes in

```cu
(do (display (cu-cap (list "unexpand" "-a" "-f" "/tmp/x-cu-tx/runs"))) (display (cu-cap (list "unexpand" "-f" "-a" "/tmp/x-cu-tx/runs"))))
```
---
```output
^Ia        b
^I  c
  x
^Ia        b
^I  c
  x
```

### -t takes every run as -a does, and -f still keeps it to the leading one

```cu
(do (display (cu-cap (list "unexpand" "-t" "4" "/tmp/x-cu-tx/runs"))) (display (cu-cap (list "unexpand" "-t" "4" "-f" "/tmp/x-cu-tx/runs"))))
```
---
```output
^I^Ia^I^I b
^I^I  c
  x
^I^Ia        b
^I^I  c
  x
```

### under -a a lone space on a stop stays a space; two become a tab; a trailing run counts

```cu
(display (cu-cap (list "unexpand" "-a" "/tmp/x-cu-tx/stops")))
```
---
```output
abcdefg h
abcdef^Ih
a^I 
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-tx")) (display "clean"))
```
---
    clean

## the singles

### fixtures

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-sg && mkdir -p /tmp/x-cu-sg/real && ln -s /tmp/x-cu-sg/real/target /tmp/x-cu-sg/l && : > /tmp/x-cu-sg/reg && printf abcdefghij > /tmp/x-cu-sg/od && printf 'a\\nb\\nc\\n' > /tmp/x-cu-sg/in && printf 'begin 644 t\\n$86)C\"@``\\n`\\nend\\n' > /tmp/x-cu-sg/uu")) (def cu-cap (fn (_ argv) (do (sys-dup2 1 9) (let ((fd (file-open-write "/tmp/x-cu-sg/.cap"))) (do (sys-dup2 fd 1) (cu-run argv "") (sys-dup2 9 1) (file-close fd) (file-read-all "/tmp/x-cu-sg/.cap")))))) (display "made"))
```
---
    made

### id -r reads the real ids, and on its own has nothing to print

The real and effective ids agree in a test process, so the fields are
judged equal to their plain forms rather than to a number.

```cu
(do (display (if (string=? (cu-cap (list "id" "-ru")) (cu-cap (list "id" "-u"))) "same" "differ")) (newline) (display (if (string=? (cu-cap (list "id" "-rg")) (cu-cap (list "id" "-g"))) "same" "differ")) (newline) (display (cu-run (list "id" "-r") "")))
```
---
```output
same
same
1
```

### nproc --ignore holds processors back and never answers below one; --all agrees with the plain count

With neither OpenMP variable set, which is why the case clears them first.

```cu
(do (Sys unsetenv "OMP_NUM_THREADS") (Sys unsetenv "OMP_THREAD_LIMIT") (def n (sys-cpu-count)) (display (if (= (%cu-num-prefix (cu-cap (list "nproc" "--ignore=1"))) (- n 1)) "one held" "wrong")) (newline) (display (cu-cap (list "nproc" "--ignore=9999"))) (display (if (string=? (cu-cap (list "nproc" "--all")) (cu-cap (list "nproc"))) "agree" "differ")))
```
---
```output
one held
1
agree
```

### nproc takes OMP_NUM_THREADS when it holds a count, even above the processors installed

Expectations from GNU nproc.  A list answers its first element, and white
space around the count is allowed.  Every case here clears both variables
before its last line, since the cases of a file share one process.

```cu
(do (Sys unsetenv "OMP_THREAD_LIMIT")
    (Sys setenv "OMP_NUM_THREADS" "2") (def np-two (cu-cap (list "nproc")))
    (Sys setenv "OMP_NUM_THREADS" (%cu-int->str (+ (sys-cpu-count) 5)))
    (def np-above (%cu-num-prefix (cu-cap (list "nproc"))))
    (Sys setenv "OMP_NUM_THREADS" "2,4") (def np-list (cu-cap (list "nproc")))
    (Sys setenv "OMP_NUM_THREADS" " 3 ") (def np-spaced (cu-cap (list "nproc")))
    (Sys setenv "OMP_NUM_THREADS" "2 ,4") (def np-gap (cu-cap (list "nproc")))
    (Sys unsetenv "OMP_NUM_THREADS")
    (display np-two)
    (display (if (= np-above (+ (sys-cpu-count) 5)) "above installed\n" "capped\n"))
    (display np-list) (display np-spaced) (display np-gap))
```
---
```output
2
above installed
2
3
2
```

### OMP_THREAD_LIMIT caps the answer, whether OMP_NUM_THREADS gave it or not

```cu
(do (Sys unsetenv "OMP_NUM_THREADS")
    (Sys setenv "OMP_THREAD_LIMIT" "1") (def np-limited (cu-cap (list "nproc")))
    (Sys setenv "OMP_NUM_THREADS" "5") (Sys setenv "OMP_THREAD_LIMIT" "3")
    (def np-over (cu-cap (list "nproc")))
    (Sys setenv "OMP_NUM_THREADS" "2") (def np-under (cu-cap (list "nproc")))
    (Sys unsetenv "OMP_NUM_THREADS") (Sys unsetenv "OMP_THREAD_LIMIT")
    (display np-limited) (display np-over) (display np-under))
```
---
```output
1
3
2
```

### a value that is not a count leaves the variable unset -- 0, abc and 3x all read as absent

```cu
(do (Sys unsetenv "OMP_NUM_THREADS") (Sys unsetenv "OMP_THREAD_LIMIT")
    (def np-plain (cu-cap (list "nproc")))
    (Sys setenv "OMP_NUM_THREADS" "0") (def np-zero (cu-cap (list "nproc")))
    (Sys setenv "OMP_NUM_THREADS" "abc") (def np-word (cu-cap (list "nproc")))
    (Sys setenv "OMP_NUM_THREADS" "3x") (def np-trail (cu-cap (list "nproc")))
    (Sys unsetenv "OMP_NUM_THREADS") (Sys setenv "OMP_THREAD_LIMIT" "0")
    (def np-nolimit (cu-cap (list "nproc")))
    (Sys unsetenv "OMP_THREAD_LIMIT")
    (List for-each
      (fn (_ v) (display (if (string=? v np-plain) "unset\n" "read\n")))
      (list np-zero np-word np-trail np-nolimit)))
```
---
```output
unset
unset
unset
unset
```

### nproc --all reads neither variable, and --ignore comes off after them

```cu
(do (Sys setenv "OMP_NUM_THREADS" "5") (Sys setenv "OMP_THREAD_LIMIT" "3")
    (def np-all (%cu-num-prefix (cu-cap (list "nproc" "--all"))))
    (Sys unsetenv "OMP_THREAD_LIMIT")
    (def np-held (cu-cap (list "nproc" "--ignore=2")))
    (Sys setenv "OMP_NUM_THREADS" "2") (def np-lowest (cu-cap (list "nproc" "--ignore=5")))
    (Sys unsetenv "OMP_NUM_THREADS")
    (display (if (= np-all (sys-cpu-count)) "installed\n" "narrowed\n"))
    (display np-held) (display np-lowest))
```
---
```output
installed
3
1
```

### pwd -P is the physical directory, and -L is that too when $PWD does not name it

```cu
(do (display (if (string=? (cu-cap (list "pwd" "-P")) (string-append (sys-getcwd) "\n")) "physical" "other")) (newline) (display (if (= (byte-at (cu-cap (list "pwd" "-L")) 0) 47) "absolute" "relative")))
```
---
```output
physical
absolute
```

### readlink -n drops the newline; -v names the trouble

```cu
(do (display (cu-cap (list "readlink" "-n" "/tmp/x-cu-sg/l"))) (display "|") (newline) (display (cu-run (list "readlink" "-v" "/tmp/x-cu-sg/reg") "")) (display (cu-run (list "readlink" "/tmp/x-cu-sg/reg") "")))
```
---
```output
/tmp/x-cu-sg/real/target|
11
```

### which -a is accepted and finds what the plain form finds first

```cu
(display (if (string=? (first (%cu-lines (cu-cap (list "which" "-a" "sh")))) (first (%cu-lines (cu-cap (list "which" "sh"))))) "same first" "differ"))
```
---
    same first

### split -a sets the suffix width

```cu
(do (cu-run (list "split" "-a" "3" "-l" "1" "/tmp/x-cu-sg/in" "/tmp/x-cu-sg/w") "") (display (if (file-exists? "/tmp/x-cu-sg/waaa") "waaa" "no")) (display (if (file-exists? "/tmp/x-cu-sg/waac") " waac" " no")) (newline) (cu-run (list "split" "-a" "1" "-l" "1" "/tmp/x-cu-sg/in" "/tmp/x-cu-sg/v") "") (display (if (file-exists? "/tmp/x-cu-sg/vc") "vc" "no")) (newline) (display (file-read-all "/tmp/x-cu-sg/waab")))
```
---
```output
waaa waac
vc
b
```

### od -j skips into the input and numbers from there; past the end it refuses

```cu
(do (display (cu-cap (list "od" "-j" "4" "-c" "/tmp/x-cu-sg/od"))) (display (cu-cap (list "od" "-A" "d" "-j" "3" "-t" "x1" "/tmp/x-cu-sg/od"))) (display (cu-cap (list "od" "-j4" "-N" "3" "-c" "/tmp/x-cu-sg/od"))) (display (cu-run (list "od" "-j" "99" "-c" "/tmp/x-cu-sg/od") "")))
```
---
```output
0000004   e   f   g   h   i   j
0000012
0000003 64 65 66 67 68 69 6a
0000010
0000004   e   f   g
0000007
1
```

### tr -c complements the first set, under -d and -s as well

```cu
(do (display (cu-run (list "tr" "-c" "a-z" "X") "ab1 cd2\n")) (newline) (display (cu-run (list "tr" "-cd" "a-z") "ab1 cd2\n")) (newline) (display (cu-run (list "tr" "-cs" "a-z" "X") "ab1 cd2\n")) (newline) (display (cu-run (list "tr" "-c" "abc" "XY") "ab1 cd2\n")))
```
---
```output
abXXcdXX0
abcd0
abXcdX0
abYYcYYY0
```

### uudecode -o names the output, and -o - is the standard output the plain form writes

```cu
(do (cu-run (list "uudecode" "-o" "/tmp/x-cu-sg/dec" "/tmp/x-cu-sg/uu") "") (display (file-read-all "/tmp/x-cu-sg/dec")) (display (cu-run (list "uudecode" "-o" "-" "/tmp/x-cu-sg/uu") "")))
```
---
```output
abc
abc
0
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-sg")) (display "clean"))
```
---
    clean

## tail -f

The loop itself never returns, so the specs drive one ROUND of it at a
time through %cu-tail-round with the offsets stated, which is what the
applet does between sleeps.

### fixtures

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-tl && mkdir -p /tmp/x-cu-tl && printf 'l1\\nl2\\nl3\\n' > /tmp/x-cu-tl/f && printf 'a1\\n' > /tmp/x-cu-tl/a && printf 'b1\\n' > /tmp/x-cu-tl/b")) (def cu-cap (fn (_ thunk) (do (sys-dup2 1 9) (let ((fd (file-open-write "/tmp/x-cu-tl/.cap"))) (do (sys-dup2 fd 1) (thunk) (sys-dup2 9 1) (file-close fd) (file-read-all "/tmp/x-cu-tl/.cap")))))) (def grow! (fn (_ p s) (let ((fd (file-open-append p))) (do (file-write fd s) (file-close fd))))) (display "made"))
```
---
    made

### -s without -f is accepted and changes nothing; -f over stdin alone prints the tail and returns

```cu
(do (display (cu-run (list "tail" "-s" "5" "-n" "1" "/tmp/x-cu-tl/f") "")) (display (cu-run (list "tail" "-f" "-n" "1") "p\nq\n")))
```
---
```output
l3
0q
0
```

### a round prints what grew past the offset, and moves the offset to the end

```cu
(do (grow! "/tmp/x-cu-tl/f" "l4\nl5\n") (def r (cu-cap (fn (_) (write (%cu-tail-round (list "/tmp/x-cu-tl/f") (list 9) #f ""))))) (display r))
```
---
```output
l4
l5
((15) . "/tmp/x-cu-tl/f")
```

### nothing grew, nothing printed, the offset stays

```cu
(write (%cu-tail-round (list "/tmp/x-cu-tl/f") (list 15) #f "/tmp/x-cu-tl/f"))
```
---
    ((15) . "/tmp/x-cu-tl/f")

### a file that shrank was truncated: it is read again from its start

```cu
(do (file-write-all "/tmp/x-cu-tl/f" "n1\n") (display (cu-cap (fn (_) (write (%cu-tail-round (list "/tmp/x-cu-tl/f") (list 15) #f "/tmp/x-cu-tl/f"))))))
```
---
```output
n1
((3) . "/tmp/x-cu-tl/f")
```

### growth on another file re-emits its header

```cu
(do (grow! "/tmp/x-cu-tl/a" "a2\n") (grow! "/tmp/x-cu-tl/b" "b2\n") (display (cu-cap (fn (_) (%cu-tail-round (list "/tmp/x-cu-tl/a" "/tmp/x-cu-tl/b") (list 3 3) #t "/tmp/x-cu-tl/b")))))
```
---
```output

==> /tmp/x-cu-tl/a <==
a2

==> /tmp/x-cu-tl/b <==
b2
```

### the file printed last needs no header again

```cu
(do (grow! "/tmp/x-cu-tl/b" "b3\n") (display (cu-cap (fn (_) (%cu-tail-round (list "/tmp/x-cu-tl/a" "/tmp/x-cu-tl/b") (list 6 6) #t "/tmp/x-cu-tl/b")))))
```
---
    b3

### a bounded follow starts where the initial read ended, so growth in between is not lost

```cu
(do (def at (byte-len (file-read-all "/tmp/x-cu-tl/f"))) (grow! "/tmp/x-cu-tl/f" "n2\n") (display (cu-cap (fn (_) (%cu-tail-follow (list "/tmp/x-cu-tl/f") (list at) #f "" "0" 1)))) (display "|"))
```
---
```output
n2
|
```

### a file that cannot be opened is named and dropped; with nothing left to follow, -f says so

The messages go to stderr; what the specs see is that nothing is printed
for the missing file, the good one still is, and the status is 1.

```cu
(do (display (cu-run (list "tail" "/tmp/x-cu-tl/nope") "")) (newline) (display (cu-run (list "tail" "-f" "/tmp/x-cu-tl/nope") "")) (newline) (display (cu-run (list "tail" "-n" "1" "/tmp/x-cu-tl/nope" "/tmp/x-cu-tl/a") "")))
```
---
```output
1
1
==> /tmp/x-cu-tl/a <==
a2
1
```

### cleanup

```cu
(do (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-tl")) (display "clean"))
```
---
    clean
