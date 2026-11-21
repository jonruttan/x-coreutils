# @weight 1

busybox's stty (coreutils/stty.c) on a pseudo-terminal.  Each case puts the
terminal back as it was opened -- its settings from the `-g` line read then,
24 rows and 80 columns -- runs the bundle's stty in a child of its own, then
puts it back again and runs busybox's on the same words, and compares what
each writes, its status, and the terminal it leaves: the `-g` line and the
size busybox reads after.  @P in a word is the terminal's name.  Standard
input is /dev/null unless a case gives the terminal there, so `standard
input` is no terminal.

## the comparison

### the applet against busybox's, the terminal put back before each

```cu
(do (import x/sys/pty)
    (def lx-q (fn (_ w) (string-append "'" (Str8 replace "'" "'\\''" w) "'")))
    (def lx-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (def lx-read (fn (_ f) (file-read-all f)))
    (def lx-pty (Pty open))
    (def lx-p (rest lx-pty))
    (lx-sh (string-append "/bin/busybox stty -F " lx-p " -g > /tmp/lx-st-init"))
    (def lx-init (Str8 replace "\n" "" (lx-read "/tmp/lx-st-init")))
    (def lx-words (fn (_ argv) (map (fn (_ w) (Str8 replace "@P" lx-p w)) argv)))
    (def lx-reset (fn (_) (lx-sh (%str-concat (list "/bin/busybox stty -F " lx-p " " lx-init " rows 24 cols 80")))))
    (def lx-after (fn (_) (do (lx-sh (%str-concat (list "{ /bin/busybox stty -F " lx-p " -g; /bin/busybox stty -F " lx-p " size; } > /tmp/lx-st-af 2>&1"))) (lx-read "/tmp/lx-st-af"))))
    (def lx-x1 (fn (_ argv in)
      (do (lx-reset)
          (def lx-o (file-open-write "/tmp/lx-xo")) (def lx-e (file-open-write "/tmp/lx-xe"))
          (def lx-child (sys-fork))
          (when (= lx-child 0)
            (do (def lx-i (file-open-read in))
                (sys-dup2 lx-i 0) (sys-dup2 lx-i 3) (sys-dup2 lx-o 1) (sys-dup2 lx-e 2)
                (sys-exit (cu-run (lx-words argv) ""))))
          (file-close lx-o) (file-close lx-e)
          (def lx-st (sys-wait lx-child))
          (%str-concat (list (lx-read "/tmp/lx-xo") "stderr:\n" (lx-read "/tmp/lx-xe") "status " (cu-int->str lx-st) "\n" (lx-after))))))
    (def lx-bb1 (fn (_ argv in)
      (do (lx-reset)
          (lx-sh (%str-concat (list "/bin/busybox " (Str8 join " " (map lx-q (lx-words argv))) " < " in " > /tmp/lx-bo 2> /tmp/lx-be; echo $? > /tmp/lx-bs")))
          (%str-concat (list (lx-read "/tmp/lx-bo") "stderr:\n" (lx-read "/tmp/lx-be") "status " (lx-read "/tmp/lx-bs") (lx-after))))))
    (def lx-on (fn (_ argv in)
      (do (def lx-a (lx-x1 argv in)) (def lx-b (lx-bb1 argv in))
          (display (if (string=? lx-a lx-b) "same\n" (%str-concat (list "ours:\n" lx-a "busybox:\n" lx-b)))))))
    (def lx-case (fn (_ argv) (lx-on argv "/dev/null")))
    (def lx-f (fn (_ . words) (lx-case (pair "stty" (pair "-F" (pair "@P" words))))))
    (display (if (> (byte-len lx-init) 0) "made" "no terminal")))
```
---
    made

## showing

### alone, -a, -g, size and speed; -F joined to its name, or after the settings

```cu
(do (lx-f) (lx-f "-a") (lx-f "-g") (lx-f "size") (lx-f "speed")
    (lx-case (list "stty" "-F@P" "-a")) (lx-case (list "stty" "-g" "-F" "@P")))
```
---
```output
same
same
same
same
same
same
same
```

### standard input: no terminal, then the terminal itself

```cu
(do (lx-case (list "stty")) (lx-case (list "stty" "-a"))
    (lx-on (list "stty") lx-p) (lx-on (list "stty" "-a") lx-p) (lx-on (list "stty" "-echo" "size") lx-p))
```
---
```output
same
same
same
same
same
```

### a narrow window wraps the lines at its width

```cu
(do (Sys setenv "COLUMNS" "40") (lx-f) (lx-f "-a") (Sys setenv "COLUMNS" "200") (lx-f "-a")
    (Sys unsetenv "COLUMNS"))
```
---
```output
same
same
same
```

## the combinations

### each, and each turned off where that may be done

```cu
(List for-each (fn (_ w) (lx-f w))
  (list "evenp" "-evenp" "parity" "-parity" "oddp" "-oddp" "nl" "-nl" "ek" "sane"
        "cooked" "-cooked" "raw" "-raw" "pass8" "-pass8" "litout" "-litout" "cbreak" "-cbreak"
        "crt" "dec" "decctlq" "-decctlq" "tabs" "-tabs" "lcase" "-lcase" "LCASE" "-LCASE"))
```
---
```output
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
```

### raw, then shown; changed, then sane

```cu
(do (lx-f "raw" "-a") (lx-f "-echo" "-icanon" "tab3" "nl1" "sane"))
```
---
```output
same
same
```

## the modes

### flags turned on and off, aliases among them

```cu
(List for-each (fn (_ ws) (List for-each (fn (_ w) (lx-f w)) ws))
  (list (list "-echo" "-icanon" "-isig" "-iexten" "echonl" "noflsh" "xcase" "tostop" "echoprt" "-echoctl" "-echoke" "flusho" "extproc")
        (list "crterase" "-crterase" "prterase" "ctlecho" "-ctlecho" "crtkill" "-crtkill")
        (list "ignbrk" "brkint" "ignpar" "parmrk" "inpck" "istrip" "inlcr" "igncr" "-icrnl" "-ixon" "ixoff" "tandem" "-tandem" "iuclc" "ixany" "imaxbel" "iutf8")
        (list "-opost" "olcuc" "ocrnl" "-onlcr" "onocr" "onlret" "ofill" "ofdel")
        (list "hupcl" "-hupcl" "hup" "-hup" "cstopb" "clocal" "crtscts" "-cread")))
```
---
```output
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
```

### the delays, set and then shown

```cu
(List for-each (fn (_ w) (lx-f w "-a"))
  (list "nl1" "nl0" "cr1" "cr2" "cr3" "cr0" "tab1" "tab2" "tab3" "tab0" "bs1" "bs0" "vt1" "vt0" "ff1" "ff0"))
```
---
```output
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
```

### the size and parity a pseudo-terminal keeps its own of

```cu
(List for-each (fn (_ w) (lx-f w)) (list "cs7" "cs5" "parenb" "parodd" "cmspar" "cs8" "-parenb"))
```
---
```output
same
same
same
same
same
same
same
```

## the control characters

### a character, ^X, ^?, undef and ^-, a number, a count with a suffix

```cu
(do (lx-f "intr" "^A") (lx-f "erase" "undef") (lx-f "kill" "^-") (lx-f "quit" "^?")
    (lx-f "eof" "x") (lx-f "eol" "7") (lx-f "eol2" "65") (lx-f "swtch" "^Z") (lx-f "start" "")
    (lx-f "susp" "^Zjunk") (lx-f "rprnt" "M") (lx-f "werase" "255") (lx-f "lnext" "200")
    (lx-f "flush" "^O") (lx-f "min" "5" "time" "3") (lx-f "-icanon" "min" "0" "time" "9"))
```
---
```output
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
same
```

### a value out of range, not a number, or missing

```cu
(do (lx-f "stop" "300") (lx-f "min" "1k") (lx-f "time" "1b") (lx-f "min" "2B") (lx-f "lnext" "12b")
    (lx-f "min" "x") (lx-f "intr") (lx-f "time"))
```
---
```output
same
same
same
same
same
same
same
same
```

## the parameters

### the window's size set and shown

```cu
(do (lx-f "rows" "30" "cols" "100") (lx-f "columns" "90" "size") (lx-f "rows" "40" "-a")
    (lx-f "rows" "2b") (lx-f "rows" "0") (lx-f "cols" "x") (lx-f "rows"))
```
---
```output
same
same
same
same
same
same
same
```

### speeds: a baud alone, ispeed and ospeed, one not in the table, not a number

```cu
(do (lx-f "9600") (lx-f "ispeed" "19200") (lx-f "ospeed" "4800" "speed") (lx-f "ispeed" "2400" "ospeed" "1200" "-a")
    (lx-f "ispeed" "12345") (lx-f "ospeed" "x") (lx-f "12345") (lx-f "38400" "speed"))
```
---
```output
same
same
same
same
same
same
same
same
```

### the line discipline, and a line -g wrote read back

```cu
(do (lx-f "line" "1") (lx-f "line" "0")
    (lx-f lx-init) (lx-f (string-append lx-init ":0")) (lx-f (Str8 replace ":" ";" lx-init)))
```
---
```output
same
same
same
same
same
```

## the refusals

### options together, an option with settings, a mode that may not be turned off, the unknown

```cu
(do (lx-f "-a" "-g") (lx-f "-ag") (lx-f "-a" "echo") (lx-f "-g" "raw") (lx-f "-cs8") (lx-f "-sane")
    (lx-f "-x") (lx-f "nosuch") (lx-f "-") (lx-case (list "stty" "-F")))
```
---
```output
same
same
same
same
same
same
same
same
same
same
```

### a device not there, two devices

```cu
(do (lx-case (list "stty" "-F" "/nonexistent")) (lx-case (list "stty" "-F" "@P" "-F" "@P")))
```
---
```output
same
same
```
