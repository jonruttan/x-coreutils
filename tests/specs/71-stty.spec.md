# @weight 1

busybox's stty (coreutils/stty.c) on a pseudo-terminal, named with -F.
What a setting did is read back from the terminal through x's Term; what is
shown is checked for busybox's shape here, and word for word against busybox
on Linux (tests/linux/specs/99-stty.spec.md).  Each case puts the terminal
back first: its settings as they were opened, 24 rows and 80 columns.

## the fixtures

### a terminal, a run of stty on it, and its settings read back

```cu
(do (import x/sys/pty) (import x/repl/term)
    (proc-run (list "/bin/sh" "-c" "rm -rf /tmp/x-cu-stty && mkdir -p /tmp/x-cu-stty"))
    (def st-f (fn (_ n) (string-append "/tmp/x-cu-stty/" n)))
    (def st-pty (Pty open))
    (def st-p (rest st-pty))
    (def st-fd (File open st-p (list 'rdwr 'noctty)))
    (def st-init (Term words (Term settings st-fd)))
    (def st-reset (fn (_) (do (def s (Term settings st-fd)) (Term words! s st-init) (Term apply! st-fd s) (Term window! st-fd 80 24))))
    (def st-capture (fn (_ argv) (do (st-reset) (st-as-is argv))))
    (def st-as-is (fn (_ argv) (do (sys-dup2 1 9) (sys-dup2 2 8) (let ((oo (file-open-write (st-f ".out"))) (ee (file-open-write (st-f ".err")))) (do (sys-dup2 oo 1) (sys-dup2 ee 2) (def st (cu-run (map (fn (_ w) (if (string=? w "@P") st-p w)) argv) "")) (sys-dup2 9 1) (sys-dup2 8 2) (file-close oo) (file-close ee) (list (file-read-all (st-f ".out")) (file-read-all (st-f ".err")) st))))))
    (def st (fn (_ . words) (st-capture (pair "stty" (pair "-F" (pair "@P" words))))))
    (def st-run (fn (_ . words) (let ((r (st-capture (pair "stty" words)))) (display (%str-concat (list (first r) "stderr:\n" (first (rest r)) "status " (cu-int->str (first (rest (rest r)))) "\n"))))))
    (def st-is (fn (_ name) (Term setting (Term settings st-fd) name)))
    (def st-word? (fn (_ w o) (Str8 includes? (%str-concat (list " " w " ")) (Str8 replace "\n" " " (string-append " " o)))))
    (display (if (null? st-init) "no terminal" "made")))
```
---
    made

## showing

### alone: the speed and line, the characters, min and time, then what differs from sane

The first line ends at the speed (and the line discipline, where there is
one), the characters follow, and min and time end theirs.  A terminal as
`sane` leaves it shows no mode sane sets, and a mode turned off that sane
sets is shown off.

```cu
(let ((r (st "sane")) (o (first (st-as-is (list "stty" "-F" "@P")))))
  (do (st-as-is (list "stty" "-F" "@P" "-echo"))
      (def off (first (st-as-is (list "stty" "-F" "@P"))))
      (list (Str8 starts? "speed " o) (Str8 includes? "intr = ^C; quit = ^\\; erase = ^?; kill = ^U; eof = ^D;" o)
            (Str8 includes? "min = 1; time = 0;" o) (st-word? "-echo" o) (st-word? "echo" o) (st-word? "icanon" o)
            (st-word? "-echo" off) (Str8 ends? "\n" o) (first (rest (rest r))))))
```
---
    (#t #t #t #f #f #f #t #t 0)

### -a: every mode, on or off, and the window's size

```cu
(let ((o (first (st "-a"))))
  (list (Str8 includes? "rows 24; columns 80;" o) (Str8 includes? " cs8 " o)
        (if (st-word? "hupcl" o) (not (st-word? "-hupcl" o)) (st-word? "-hupcl" o))
        (Str8 includes? " icanon " o) (Str8 includes? " echo " o) (Str8 includes? " tab0 " o)
        (Str8 includes? "tandem" o) (Str8 includes? "crterase" o)))
```
---
    (#t #t #t #t #t #t #f #f)

### no line is wider than the window, which $COLUMNS gives

```cu
(do (Sys setenv "COLUMNS" "40")
    (def o (first (st "-a")))
    (Sys unsetenv "COLUMNS")
    (list (null? (List find (fn (_ l) (>= (byte-len l) 40)) (Str8 split "\n" o))) (> (List length (Str8 split "\n" o)) 10)))
```
---
    (#t #t)

### -g: the four flag words and every control character in hex, which stty reads back

```cu
(let ((g (first (st "-g"))))
  (do (st "-echo" "intr" "^A")
      (def changed (st-is 'echo))
      (def back (st-capture (list "stty" "-F" "@P" (Str8 replace "\n" "" g))))
      (list (= (List length (Str8 split ":" g)) (+ 4 (Term nccs))) changed (st-is 'echo) (st-is 'vintr)
            (first (rest (rest back))))))
```
---
    (#t #f #t 3 0)

### size, and speed, after settings in order

```cu
(do (st-run "-F" "@P" "rows" "30" "cols" "100" "size")
    (st-run "-F" "@P" "9600" "speed"))
```
---
```output
30 100
stderr:
status 0
9600
stderr:
status 0
```

## settings

### a mode on and off, an alias, a delay, a combination

```cu
(list (do (st "-echo" "-icanon") (list (st-is 'echo) (st-is 'icanon)))
      (do (st "tandem" "crterase") (list (st-is 'ixoff) (st-is 'echoe)))
      (do (st "tab3") (list (st-is 'tab0) (st-is 'tab3)))
      (do (st "raw") (list (st-is 'isig) (st-is 'icanon) (st-is 'opost) (st-is 'icrnl) (st-is 'vmin) (st-is 'vtime)))
      (do (st "raw" "sane") (list (st-is 'isig) (st-is 'icanon) (st-is 'opost) (st-is 'icrnl) (st-is 'echo)))
      (do (st "dec") (list (st-is 'vintr) (st-is 'verase) (st-is 'vkill) (st-is 'echoctl)))
      (do (st "-tabs") (st-is 'tab3)))
```
---
    ((#f #f) (#t #t) (#f #t) (#f #f #f #f 1 0) (#t #t #t #t #t) (3 127 21 #t) #t)

### control characters: ^X, ^?, undef, a character, a number, min and time

```cu
(do (st "intr" "^A" "quit" "^?" "erase" "undef" "eof" "x" "eol" "7" "-icanon" "min" "5" "time" "3")
    (list (st-is 'vintr) (st-is 'vquit) (st-is 'verase) (st-is 'veof) (st-is 'veol) (st-is 'vmin) (st-is 'vtime)))
```
---
    (1 127 () 120 55 5 3)

### the window's size, one side at a time

```cu
(do (st "rows" "33") (def a (Term measure st-fd)) (st "cols" "101") (list a (Term measure st-fd)))
```
---
    ((80 . 33) (101 . 24))

## refusals

### the words busybox refuses with, and its status

```cu
(do (st-run "-F" "@P" "-a" "-g") (st-run "-F" "@P" "-a" "echo") (st-run "-F" "@P" "-cs8")
    (st-run "-F" "@P" "12345") (st-run "-F" "@P" "nosuch") (st-run "-F" "@P" "intr")
    (st-run "-F" "@P" "min" "1k") (st-run "-F" "@P" "rows" "0") (st-run "-F" "@P" "-x")
    (st-run "-F") (st-run "-F" "@P" "-F" "@P") (st-run "-F" "/tmp/x-cu-stty/none"))
```
---
```output
stderr:
stty: -a and -g are mutually exclusive
status 1
stderr:
stty: modes may not be set when -a or -g is used
status 1
stderr:
stty: invalid argument '-cs8'
status 1
stderr:
stty: invalid argument '12345'
status 1
stderr:
stty: invalid number 'nosuch'
status 1
stderr:
stty: intr requires an argument
status 1
stderr:
stty: number 1k is not in 0..255 range
status 1
stderr:
stty: number 0 is not in 1..2147483647 range
status 1
stderr:
stty: invalid argument '-x'
status 1
stderr:
stty: -F requires an argument
status 1
stderr:
stty: only one device may be specified
status 1
stderr:
stty: can't open '/tmp/x-cu-stty/none': No such file or directory
status 1
```

### a device that is no terminal is said by libc's words for ENOTTY

```cu
(let ((r (st-capture (list "stty" "-F" "/dev/null"))))
  (list (first r) (string=? (first (rest r)) (%str-concat (list "stty: /dev/null: " (libc-strerror 25) "\n")))
        (first (rest (rest r)))))
```
---
    ("" #t 1)

### reset is stty sane once the screen is reset, and only at a terminal

```cu
(do (st "-echo")
    (def r (cu-run (list "reset") ""))
    (list r (st-is 'echo)))
```
---
    (0 #f)
