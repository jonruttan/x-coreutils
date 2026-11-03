# @weight 1

busybox's powertop (procps/powertop.c) reads /proc: stat, interrupts,
acpi/processor/*/power and timer_stats.  Darwin has none of them, so here
it answers as busybox does, unable to open /proc/stat.  The screens are
checked over a fixture /proc, tests/fixtures/powertop, through Host's
proc-root: each key moves the interrupts and the first processor's power
file on to the next sample, as the Linux leg does before each key it
presses, and the screens expected are busybox's own over the same samples
there.  A run is a child of its own; an ESC is written `^[` and the end of
each line written to standard output `|`.

## the fixture

### a run of powertop in a child, its stdin a file, over the fixture /proc or none

```cu
(def stand-in! (fn (_ envs name v) (List map (fn (_ e) (eval (list (lit set!) name (list (lit lit) v)) e)) envs)))
(do (def pt-f (fn (_ n) (string-append "/tmp/x-cu-ptop/" n)))
    (def pt-fx (string-append (sys-getcwd) "/tests/fixtures/powertop/"))
    (def pt-sh (fn (_ cmd) (proc-run (list "/bin/sh" "-c" cmd))))
    (pt-sh "rm -rf /tmp/x-cu-ptop && mkdir -p /tmp/x-cu-ptop && : > /tmp/x-cu-ptop/none && printf q > /tmp/x-cu-ptop/q")
    (def pt-esc (bytes->str (list 27)))
    (def pt-show (fn (_ st)
      (display (Str8 replace pt-esc "^["
                 (%str-concat (list (Str8 replace "\n" "|\n" (file-read-all (pt-f "out"))) "stderr:\n"
                                      (file-read-all (pt-f "err")) "status " (cu-int->str st) "\n"))))))
    ; ARGV with stdin the file IN, PREP run first in the child
    (def pt-run (fn (_ argv in prep)
      (do (def kid (sys-fork))
          (when (= kid 0)
            (guard (e (sys-exit 99))
              (do (sys-dup2 (file-open-read in) 0) (set-first! cu-stdin-moved #t)
                  (sys-dup2 (file-open-write (pt-f "out")) 1) (sys-dup2 (file-open-write (pt-f "err")) 2)
                  (prep)
                  (sys-exit (cu-run argv "")))))
          (pt-show (sys-wait kid))
          ())))
    (def pt-cp (fn (_ from to) (%str-concat (list "cp " pt-fx from " /tmp/x-cu-ptop/proc/" to))))
    ; the fixture /proc: SET's first interrupts, the power files when ACPI,
    ; timer_stats a file of the fixture's, a directory or none
    (def pt-proc! (fn (_ set acpi timer)
      (do (pt-sh (Str8 join " && " (append
            (list "rm -rf /tmp/x-cu-ptop/proc" "mkdir -p /tmp/x-cu-ptop/proc/acpi/processor/CPU0 /tmp/x-cu-ptop/proc/acpi/processor/CPU1"
                  (pt-cp "stat" "stat") (pt-cp (string-append set ".a") "interrupts")
                  (if acpi (pt-cp "power.a" "acpi/processor/CPU0/power") "rm -r /tmp/x-cu-ptop/proc/acpi")
                  (if acpi (pt-cp "power.a" "acpi/processor/CPU1/power") ":"))
            (match ((str=? timer "file") (list (pt-cp "timer_stats" "timer_stats")))
                   ((str=? timer "dir") (list "mkdir /tmp/x-cu-ptop/proc/timer_stats"))
                   (#t ())))))
          (Host proc-root (pt-f "proc")))))
    ; N keys, each after the next sample: SET's b then c (big's b twice),
    ; and the first processor's power file's b when ACPI
    (def pt-keys! (fn (_ n set acpi)
      (do (def left (list 0))
          (stand-in! (list (module cu/powertop)) (lit %ptop-key)
            (fn (_ seconds)
              (if (>= (first left) n) (lit quit)
                (do (pt-sh (string-append (pt-cp (string-append set (if (if (= (first left) 0) #t (str=? set "big")) ".b" ".c")) "interrupts")
                                          (if acpi (string-append " && " (pt-cp "power.b" "acpi/processor/CPU0/power")) "")))
                    (set-first! left (+ (first left) 1))
                    (lit key))))))))
    ; timer_stats as the kernel keeps it: written to, and read back as the fixture's
    (def pt-kernel-timer! (fn (_) (stand-in! (list (module cu/powertop)) (lit %ptop-timer!) (fn (_ s) #f))))
    (display "made"))
```
---
    made

## the words

### --help, and words it ignores

```cu
(do (pt-run (list "powertop" "--help") (pt-f "none") (fn (_) ()))
    (pt-run (list "powertop" "-x" "y") (pt-f "none") (fn (_) (pt-proc! "interrupts" #t "file"))))
```
---
```output
Usage: powertop|
|
Analyze power consumption on Intel-based laptops|
stderr:
status 0
Collecting data for 10 seconds|
|
stderr:
powertop: run as root to collect enough information
status 0
```

## Darwin

### no /proc: busybox's answer, once it has warned it is not root

```cu
(pt-run (list "powertop") (pt-f "none") (fn (_) ()))
```
---
```output
stderr:
powertop: run as root to collect enough information
powertop: can't open '/proc/stat': No such file or directory
status 1
```

## the fixture /proc

### two samples, the kernel keeping timer_stats: C-states, timers and interrupts

```cu
(pt-run (list "powertop") (pt-f "none")
  (fn (_) (do (pt-proc! "interrupts" #t "file") (pt-keys! 2 "interrupts" #t) (pt-kernel-timer!))))
```
---
```output
Collecting data for 10 seconds|
^[[H^[[JCn		  Avg residency|
C0 (cpu running)        (26.0%)|
C1		  4.2ms ( 4.0%)|
C2		348.3ms (69.0%)|
|
Wakeups-from-idle in 10 seconds: 240|
|
Top causes for wakeups:|
  44.0% (  135)       <interrupt> : extra timer interrupt|
  24.8% (   76)     <kernel core> : hrtimer_start_range_ns (tick_sched_timer)|
   9.8% (   30)       <interrupt> : i8042|
   7.8% (   24)           firefox : hrtimer_start_range_ns (hrtimer_wakeup)|
   6.5% (   20)       <interrupt> : acpi|
   2.9% (    9)   averyveryverylo : hrtimer_start (hrtimer_wakeup)|
   2.0% (    6)       <interrupt> : 1048576-edge      nvme0q0, nvme0q1, nvme0q2, nvme0q3xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|
   1.6% (    5)   [kernel module] : foo (bar)|
   0.7% (    2)      <kernel IPI> : Non-maskable interrupts|
^[[H^[[JCn		  Avg residency|
C0 (cpu running)        (100.0%)|
C1		  0.0ms ( 0.0%)|
C2		  0.0ms ( 0.0%)|
|
Wakeups-from-idle in 10 seconds: 388|
|
Top causes for wakeups:|
  32.9% (  235)       <interrupt> : extra timer interrupt|
  10.6% (   76)     <kernel core> : hrtimer_start_range_ns (tick_sched_timer)|
   7.0% (   50)       <interrupt> : acpi|
   3.4% (   24)           firefox : hrtimer_start_range_ns (hrtimer_wakeup)|
   1.3% (    9)   averyveryverylo : hrtimer_start (hrtimer_wakeup)|
   0.8% (    6)      <kernel IPI> : Non-maskable interrupts|
   0.7% (    5)   [kernel module] : foo (bar)|
   0.1% (    1)       <interrupt> : 1048576-edge      nvme0q0, nvme0q1, nvme0q2, nvme0q3xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|
   0.1% (    1)       <interrupt> : i8042|
|
stderr:
powertop: run as root to collect enough information
status 0
```

### timer_stats a directory no write opens

```cu
(pt-run (list "powertop") (pt-f "none")
  (fn (_) (do (pt-proc! "interrupts" #t "dir") (pt-keys! 1 "interrupts" #t))))
```
---
```output
Collecting data for 10 seconds|
^[[H^[[JCn		  Avg residency|
C0 (cpu running)        (26.0%)|
C1		  4.2ms ( 4.0%)|
C2		348.3ms (69.0%)|
|
Wakeups-from-idle in 10 seconds: 240|
|
|
stderr:
powertop: run as root to collect enough information
powertop: no stats available; run as root or enable the timer_stats module
status 0
```

### timer_stats a file the writes land in, no power files; a terminal of 14 lines, 2 of them causes

```cu
(do (pt-run (list "powertop") (pt-f "none")
       (fn (_) (do (pt-proc! "interrupts" #f "file") (pt-keys! 1 "interrupts" #f))))
    (pt-run (list "powertop") (pt-f "none")
      (fn (_) (do (pt-proc! "interrupts" #t "file") (pt-keys! 1 "interrupts" #t) (pt-kernel-timer!)
                  (sys-setenv "LINES" "14")))))
```
---
```output
Collecting data for 10 seconds|
^[[H^[[JC-state information is not available|
|
Wakeups-from-idle in 10 seconds: 58|
|
Top causes for wakeups:|
  51.7% (   30)       <interrupt> : i8042|
  34.5% (   20)       <interrupt> : acpi|
  10.3% (    6)       <interrupt> : 1048576-edge      nvme0q0, nvme0q1, nvme0q2, nvme0q3xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx|
   3.4% (    2)      <kernel IPI> : Non-maskable interrupts|
|
stderr:
powertop: run as root to collect enough information
status 0
Collecting data for 10 seconds|
^[[H^[[JCn		  Avg residency|
C0 (cpu running)        (26.0%)|
C1		  4.2ms ( 4.0%)|
C2		348.3ms (69.0%)|
|
Wakeups-from-idle in 10 seconds: 240|
|
Top causes for wakeups:|
  44.0% (  135)       <interrupt> : extra timer interrupt|
  24.8% (   76)     <kernel core> : hrtimer_start_range_ns (tick_sched_timer)|
|
stderr:
powertop: run as root to collect enough information
status 0
```

### 45 sources, past the 40 kept, in thousands, 60 lines

```cu
(pt-run (list "powertop") (pt-f "none")
  (fn (_) (do (pt-proc! "big" #f "file") (pt-keys! 2 "big" #f) (sys-setenv "LINES" "60"))))
```
---
```output
Collecting data for 10 seconds|
^[[H^[[JC-state information is not available|
|
Wakeups-from-idle in 10 seconds: 102678965|
|
Top causes for wakeups:|
   4.4% (4394K)       <interrupt> : dev45|
   4.3% (4296K)       <interrupt> : dev44|
   4.2% (4199K)       <interrupt> : dev43|
   4.1% (4101K)       <interrupt> : dev42|
   4.0% (4003K)       <interrupt> : dev41|
   3.9% (3867K)       <interrupt> : dev40|
   3.8% (3770K)       <interrupt> : dev39|
   3.7% (3673K)       <interrupt> : dev38|
   3.6% (3577K)       <interrupt> : dev37|
   3.5% (3480K)       <interrupt> : dev36|
   3.4% (3383K)       <interrupt> : dev35|
   3.3% (3287K)       <interrupt> : dev34|
   3.2% (3190K)       <interrupt> : dev33|
   3.1% (3093K)       <interrupt> : dev32|
   3.0% (2997K)       <interrupt> : dev31|
   2.9% (2900K)       <interrupt> : dev30|
   2.8% (2803K)       <interrupt> : dev29|
   2.7% (2707K)       <interrupt> : dev28|
   2.6% (2610K)       <interrupt> : dev27|
   2.5% (2513K)       <interrupt> : dev26|
   2.4% (2416K)       <interrupt> : dev25|
   2.3% (2320K)       <interrupt> : dev24|
   2.2% (2223K)       <interrupt> : dev23|
   2.1% (2126K)       <interrupt> : dev22|
   2.0% (2030K)       <interrupt> : dev21|
   1.9% (1933K)       <interrupt> : dev20|
   1.8% (1836K)       <interrupt> : dev19|
   1.7% (1740K)       <interrupt> : dev18|
   1.6% (1643K)       <interrupt> : dev17|
   1.5% (1546K)       <interrupt> : dev16|
   1.4% (1450K)       <interrupt> : dev15|
   1.3% (1353K)       <interrupt> : dev14|
   1.3% (1256K)       <interrupt> : dev13|
   1.2% (1160K)       <interrupt> : dev12|
   1.1% (1063K)       <interrupt> : dev11|
   1.0% ( 966K)       <interrupt> : dev10|
   0.9% ( 870K)       <interrupt> : dev9|
   0.8% ( 773K)       <interrupt> : dev8|
   0.7% ( 676K)       <interrupt> : dev7|
   0.6% ( 580K)       <interrupt> : dev6|
   0.5% ( 483K)       <interrupt> : dev5|
   0.4% ( 386K)       <interrupt> : dev4|
   0.3% ( 290K)       <interrupt> : dev3|
   0.2% ( 193K)       <interrupt> : dev2|
   0.1% (98999)       <interrupt> : dev1|
^[[H^[[JC-state information is not available|
|
Wakeups-from-idle in 10 seconds: 21499785|
|
Top causes for wakeups:|
   3.6% (4394K)       <interrupt> : dev45|
   3.5% (4296K)       <interrupt> : dev44|
   3.5% (4199K)       <interrupt> : dev43|
   3.4% (4101K)       <interrupt> : dev42|
   3.3% (4003K)       <interrupt> : dev41|
|
stderr:
powertop: run as root to collect enough information
status 0
```

